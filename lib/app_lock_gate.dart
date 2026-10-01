part of 'main.dart';

// ============================================================
// APP-WIDE PRIVACY LOCK GATE
// ============================================================
//
// ZeroLogPrivacyLock (privacy_lock.dart) only used to guard the single
// "Gizlilik" settings sub-screen: tapping into Settings > Privacy asked
// for the PIN/biometric, but the chat list, messages and calls behind it
// were always fully visible with no challenge at all. For a
// privacy-focused messaging app that is close to pointless as a
// protection: anyone holding the unlocked phone could already read every
// conversation without ever opening that sub-screen.
//
// AppLockGate fixes that by wrapping the entire app (via
// MaterialApp.builder, so it sits above every route/screen) and
// challenging the user:
//   - once on cold start, if a PIN has been configured, and
//   - again every time the app returns to the foreground after being
//     backgrounded (app switcher, lock screen, another app) -- the same
//     model used by Signal/WhatsApp's screen-lock feature.
//
// It intentionally never forces PIN setup by itself: if the user has
// never opted in under Settings > Privacy, ZeroLogPrivacyLock.isConfigured()
// is false and this gate stays fully transparent.
//
// It also takes care not to interrupt an incoming/active call with a
// lock prompt (see ZeroLogPushService.callScreenActive / hasPendingCall).
class AppLockGate extends StatefulWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _checkedOnce = false;
  bool _locked = false;
  bool _authenticating = false;
  bool _wasBackgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _evaluateOnStart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _evaluateOnStart() async {
    final configured = await ZeroLogPrivacyLock.isConfigured();
    if (!mounted) return;

    setState(() {
      _locked = configured;
      _checkedOnce = true;
    });

    if (_locked) {
      final pendingCall = await ZeroLogPushService.hasPendingCall();
      if (!mounted) return;

      if (ZeroLogPushService.callScreenActive || pendingCall) {
        setState(() => _locked = false);
        return;
      }

      _promptUnlock();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _wasBackgrounded = true;
      return;
    }

    if (state == AppLifecycleState.resumed && _wasBackgrounded) {
      _wasBackgrounded = false;
      _onResumedFromBackground();
    }
  }

  Future<void> _onResumedFromBackground() async {
    // Never interrupt an active call, or one that is about to open from
    // a native full-screen incoming-call intent, with a lock prompt.
    if (ZeroLogPushService.callScreenActive) return;
    if (await ZeroLogPushService.hasPendingCall()) return;

    final configured = await ZeroLogPrivacyLock.isConfigured();
    if (!mounted || !configured) return;

    // Re-check: a call may have started while the checks above were
    // in flight.
    if (ZeroLogPushService.callScreenActive) return;

    setState(() => _locked = true);
    _promptUnlock();
  }

  Future<void> _promptUnlock() async {
    if (_authenticating) return;
    _authenticating = true;

    // Give any in-flight incoming-call navigation a brief moment to land
    // before the lock prompt steals focus.
    await Future<void>.delayed(const Duration(milliseconds: 250));

    if (!mounted || !_locked) {
      _authenticating = false;
      return;
    }

    if (ZeroLogPushService.callScreenActive ||
        await ZeroLogPushService.hasPendingCall()) {
      _authenticating = false;
      if (mounted) setState(() => _locked = false);
      return;
    }

    // Use the app's root navigator context rather than this widget's own
    // context: AppLockGate wraps the Navigator (it sits in
    // MaterialApp.builder, above `child`), so its own BuildContext is an
    // ancestor of the Navigator, not a descendant of it, and showDialog
    // would fail to resolve a Navigator from it.
    final dialogContext = zeroLogNavigatorKey.currentContext;
    if (dialogContext == null || !dialogContext.mounted) {
      _authenticating = false;
      return;
    }

    final ok = await ZeroLogPrivacyLock.authenticate(dialogContext);

    _authenticating = false;
    if (!mounted) return;

    if (ok) {
      setState(() => _locked = false);
    }
    // If cancelled, the overlay stays up; its own button lets the user
    // retry authentication.
  }

  @override
  Widget build(BuildContext context) {
    if (!_checkedOnce) {
      // Fast local secure-storage read; this placeholder is on screen for
      // a frame or two at most, just long enough to avoid a flash of
      // unlocked content before the initial check resolves.
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Stack(
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(child: _AppLockScreen(onUnlock: _promptUnlock)),
      ],
    );
  }
}

class _AppLockScreen extends StatelessWidget {
  final VoidCallback onUnlock;

  const _AppLockScreen({required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.instance.data;

    return PopScope(
      canPop: false,
      child: Material(
        color: theme.background,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: theme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_rounded,
                      size: 40,
                      color: theme.primary,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'ZeroLog kilitli',
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Devam etmek için kimliğinizi doğrulayın.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.text.withValues(alpha: 0.55),
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 26),
                  FilledButton.icon(
                    onPressed: onUnlock,
                    icon: const Icon(Icons.lock_open_rounded),
                    label: const Text('Kilidi aç'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
