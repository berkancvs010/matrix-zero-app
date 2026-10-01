part of 'main.dart';

/// Protects the in-app privacy center with a device-local PIN and, when
/// available, the device's biometric authentication.
class ZeroLogPrivacyLock {
  ZeroLogPrivacyLock._();

  static final LocalAuthentication _auth = LocalAuthentication();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _hashKey = 'zerolog.privacy_lock.pin_hash.v1';
  static const String _saltKey = 'zerolog.privacy_lock.pin_salt.v1';
  static const String _biometricKey = 'zerolog.privacy_lock.biometric.v1';
  static const String _failedAttemptsKey = 'zerolog.privacy_lock.failed_attempts.v1';
  static const String _lockUntilKey = 'zerolog.privacy_lock.lock_until.v1';
  static const int _maxAttemptsBeforeDelay = 3;
  static bool authenticationInProgress = false;

  static Future<bool> isConfigured() async {
    final hash = await _storage.read(key: _hashKey);
    return hash != null && hash.isNotEmpty;
  }

  static Future<bool> biometricAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> biometricEnabled() async {
    return (await _storage.read(key: _biometricKey)) == '1';
  }

  static Future<void> _setBiometricEnabled(bool value) async {
    await _storage.write(key: _biometricKey, value: value ? '1' : '0');
  }

  static Future<void> configurePin(String pin, {required bool biometric}) async {
    final normalized = pin.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(normalized)) {
      throw ArgumentError('PIN must be exactly 6 digits.');
    }

    final random = math.Random.secure();
    final saltBytes = List<int>.generate(16, (_) => random.nextInt(256));
    final salt = base64UrlEncode(saltBytes);
    final hash = _hashPin(normalized, salt);

    await _storage.write(key: _saltKey, value: salt);
    await _storage.write(key: _hashKey, value: hash);
    await _storage.delete(key: _failedAttemptsKey);
    await _storage.delete(key: _lockUntilKey);
    await _setBiometricEnabled(biometric);
  }

  static String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin:ZeroLogPrivacyLock:v1');
    return sha256.convert(bytes).toString();
  }

  static Future<bool> _verifyPin(String pin) async {
    final salt = await _storage.read(key: _saltKey);
    final expected = await _storage.read(key: _hashKey);
    if (salt == null || expected == null) return false;
    return _hashPin(pin, salt) == expected;
  }

  static Future<bool> authenticate(BuildContext context) async {
    if (authenticationInProgress) return false;
    authenticationInProgress = true;

    try {
      if (!await isConfigured()) {
        if (!context.mounted) return false;
        final configured = await _showSetup(context);
        if (!configured) return false;
      }

      final biometricEnabledForLock = await biometricEnabled();
      final biometricReady =
          biometricEnabledForLock && await biometricAvailable();

      // A PIN is always stored when the privacy lock is configured. If
      // biometric authentication is enabled, it is a preferred method, not
      // the only method: the user can deliberately choose the PIN or use it
      // as a fallback after an unsuccessful biometric attempt.
      if (biometricReady) {
        if (!context.mounted) return false;

        final method = await _showAuthenticationMethodChoice(context);
        if (method == null) return false;

        if (method == 'pin') {
          if (!context.mounted) return false;
          return _showPinPrompt(context);
        }

        try {
          final biometricOk = await _auth.authenticate(
            localizedReason: 'ZeroLog Gizlilik Merkezi\'ni açmak için doğrulayın.',
            options: const AuthenticationOptions(
              biometricOnly: true,
              stickyAuth: false,
            ),
          );

          if (biometricOk) return true;

          // The biometric prompt can be cancelled, rejected, or exhausted
          // after failed attempts. The PIN remains a deliberate second
          // authentication method and must stay available.
          if (!context.mounted) return false;
          return _showPinPrompt(context);
        } on PlatformException {
          if (!context.mounted) return false;
          return _showPinPrompt(context);
        } catch (_) {
          if (!context.mounted) return false;
          return _showPinPrompt(context);
        }
      }

      if (!context.mounted) return false;
      return _showPinPrompt(context);
    } finally {
      authenticationInProgress = false;
    }
  }

  static Future<String?> _showAuthenticationMethodChoice(
    BuildContext context,
  ) async {
    if (!context.mounted) return null;
    final theme = ThemeController.instance.data;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Gizlilik Merkezi'),
          content: Text(
            'Doğrulama yöntemini seçin. PIN, biyometri başarısız olduğunda da kullanılabilir.',
            style: TextStyle(
              color: theme.text.withValues(alpha: 0.68),
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'pin'),
              child: const Text('PIN ile giriş'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'biometric'),
              icon: const Icon(Icons.fingerprint_rounded),
              label: const Text('Biyometri ile giriş'),
            ),
          ],
        );
      },
    );
  }

  static Future<bool> _showSetup(BuildContext context) async {
    final biometric = await biometricAvailable();
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    if (!context.mounted) return false;
    var useBiometric = biometric;
    var error = '';

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final theme = ThemeController.instance.data;
            return AlertDialog(
              title: const Text('Gizlilik kilidini oluştur'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gizlilik Merkezi yalnızca sizin doğrulamanızdan sonra açılır. 6 haneli bir PIN belirleyin.',
                      style: TextStyle(
                        color: theme.text.withValues(alpha: 0.62),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: '6 haneli PIN',
                        prefixIcon: Icon(Icons.pin_outlined),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: confirmController,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'PIN tekrar',
                        prefixIcon: Icon(Icons.verified_user_outlined),
                        counterText: '',
                      ),
                    ),
                    if (biometric) ...[
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: useBiometric,
                        onChanged: (value) => setState(() => useBiometric = value),
                        title: const Text('Parmak izi / biyometri kullan'),
                        subtitle: const Text(
                          'Biyometriyi tercih edin; PIN her zaman yedek giriş olarak kullanılabilir.',
                        ),
                      ),
                    ],
                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        error,
                        style: TextStyle(color: theme.primary, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('İptal'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final pin = controller.text.trim();
                    final confirm = confirmController.text.trim();
                    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
                      setState(() => error = 'PIN tam olarak 6 rakam olmalı.');
                      return;
                    }
                    if (pin != confirm) {
                      setState(() => error = 'PIN kodları eşleşmiyor.');
                      return;
                    }
                    await configurePin(pin, biometric: useBiometric);
                    if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                  },
                  icon: const Icon(Icons.lock_outline_rounded),
                  label: const Text('Kilidi oluştur'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    confirmController.dispose();
    return result == true;
  }

  static Future<bool> _showPinPrompt(BuildContext context) async {
    final controller = TextEditingController();
    final pinFocusNode = FocusNode();
    var error = '';
    var attempts = int.tryParse(
          await _storage.read(key: _failedAttemptsKey) ?? '0',
        ) ??
        0;
    var lockUntilMs =
        int.tryParse(await _storage.read(key: _lockUntilKey) ?? '0') ?? 0;
    Timer? ticker;
    bool submittingPin = false;

    Future<void> persistFailure() async {
      attempts += 1;
      await _storage.write(key: _failedAttemptsKey, value: '$attempts');

      if (attempts >= _maxAttemptsBeforeDelay) {
        final duration = attempts >= 12
            ? const Duration(minutes: 30)
            : attempts >= 8
                ? const Duration(minutes: 10)
                : attempts >= 5
                    ? const Duration(minutes: 2)
                    : const Duration(seconds: 30);
        lockUntilMs = DateTime.now().add(duration).millisecondsSinceEpoch;
        await _storage.write(
          key: _lockUntilKey,
          value: '$lockUntilMs',
        );
      }
    }

    Future<void> clearFailures() async {
      attempts = 0;
      lockUntilMs = 0;
      await _storage.delete(key: _failedAttemptsKey);
      await _storage.delete(key: _lockUntilKey);
    }

    Future<void> submitPin(
      BuildContext dialogContext,
      void Function(void Function()) setState,
    ) async {
      if (submittingPin) return;

      final pin = controller.text.trim();
      if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
        if (!dialogContext.mounted) return;
        setState(() => error = 'PIN tam olarak 6 rakam olmalı.');
        return;
      }

      submittingPin = true;
      if (dialogContext.mounted) {
        setState(() {});
      }
      try {
        final ok = await _verifyPin(pin);
        if (ok && dialogContext.mounted) {
          await clearFailures();
          ticker?.cancel();
          if (!dialogContext.mounted) return;
          Navigator.pop(dialogContext, true);
          return;
        }

        await persistFailure();
        if (!dialogContext.mounted) return;
        controller.clear();
        setState(() {
          error = attempts >= _maxAttemptsBeforeDelay
              ? 'PIN hatalı. Güvenlik kilidi devreye girdi.'
              : 'PIN hatalı. Kalan deneme: ${_maxAttemptsBeforeDelay - attempts}.';
        });
      } finally {
        submittingPin = false;
        if (dialogContext.mounted) {
          setState(() {});
        }
      }
    }

    if (!context.mounted) {
      pinFocusNode.dispose();
      return false;
    }
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (dialogContext.mounted && !pinFocusNode.hasFocus) {
            pinFocusNode.requestFocus();
          }
        });
        return StatefulBuilder(
          builder: (context, setState) {
            final remaining = lockUntilMs > DateTime.now().millisecondsSinceEpoch
                ? Duration(
                    milliseconds:
                        lockUntilMs - DateTime.now().millisecondsSinceEpoch,
                  )
                : Duration.zero;
            final locked = remaining > Duration.zero;

            if (locked && ticker == null) {
              ticker = Timer.periodic(const Duration(seconds: 1), (_) {
                if (!dialogContext.mounted) return;
                setState(() {});
              });
            }

            final seconds = remaining.inSeconds + (remaining.inMilliseconds % 1000 == 0 ? 0 : 1);

            return AlertDialog(
              title: Row(
                children: [
                  Icon(
                    locked ? Icons.lock_clock_rounded : Icons.lock_rounded,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      locked
                          ? 'Gizlilik Merkezi geçici olarak kilitli'
                          : 'PIN ile doğrulama',
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    locked
                        ? Icons.timer_outlined
                        : Icons.verified_user_outlined,
                    size: 44,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    locked
                        ? 'Çok sayıda hatalı deneme nedeniyle geçici olarak kilitlendi.'
                        : 'Devam etmek için 6 haneli PIN kodunuzu girin.',
                    textAlign: TextAlign.center,
                  ),
                  if (locked) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Tekrar deneyebilmeniz için yaklaşık $seconds saniye kaldı.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: ThemeController.instance.data.primary,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 18),
                    TextField(
                      controller: controller,
                      focusNode: pinFocusNode,
                      autofocus: false,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 6,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) {
                        if (error.isNotEmpty) setState(() => error = '');
                        setState(() {});
                      },
                      onSubmitted: (_) => unawaited(
                        submitPin(dialogContext, setState),
                      ),
                      decoration: InputDecoration(
                        labelText: 'PIN',
                        prefixIcon: const Icon(Icons.pin_outlined),
                        errorText: error.isEmpty ? null : error,
                        counterText: '',
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    ticker?.cancel();
                    Navigator.pop(dialogContext, false);
                  },
                  child: const Text('İptal'),
                ),
                if (!locked)
                  FilledButton.icon(
                    onPressed: controller.text.trim().length == 6 && !submittingPin
                        ? () => submitPin(dialogContext, setState)
                        : null,
                    icon: const Icon(Icons.lock_open_rounded),
                    label: const Text('Giriş yap'),
                  ),
              ],
            );
          },
        );
      },
    );

    ticker?.cancel();
    pinFocusNode.dispose();
    controller.dispose();
    return result == true;
  }

  static Future<String> statusLabel() async {
    if (!await isConfigured()) return 'İlk kullanımda PIN oluşturulacak';
    if (await biometricEnabled() && await biometricAvailable()) {
      return 'Biyometri + PIN yedek doğrulaması aktif';
    }
    return '6 haneli PIN koruması aktif';
  }

  /// Wipes all privacy-lock state (PIN hash/salt, biometric preference,
  /// lockout counters). Must be called whenever the local account is
  /// removed from this device (logout / delete account), otherwise a PIN
  /// configured by the previous account would keep locking out whoever
  /// uses the app next on the same device.
  static Future<void> clearAll() async {
    await _storage.delete(key: _hashKey);
    await _storage.delete(key: _saltKey);
    await _storage.delete(key: _biometricKey);
    await _storage.delete(key: _failedAttemptsKey);
    await _storage.delete(key: _lockUntilKey);
  }
}
