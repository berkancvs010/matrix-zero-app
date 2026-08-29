part of 'main.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  // Login ekranındaki ZeroLog yeşili ile aynı renk.
  static const Color _welcomeGreen = Color(0xFF39FF88);

  final List<String> _lines = [];
  Timer? _timer;

  static const List<String> _sequence = [
    'ZEROLOG',
    'PRIVATE',
    'ENCRYPTED',
    'NO LOGS',
  ];

  int _index = 0;

  static const String _lastWelcomeAtKey = 'zerolog.last_welcome_at';
  bool _welcomeShouldShow = true;

  late final Future<bool> _sessionRestoreFuture;

  @override
  void initState() {
    super.initState();

    _sessionRestoreFuture = _restoreSession();

    _checkWelcomeSchedule();
  }

  Future<void> _checkWelcomeSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_lastWelcomeAtKey);
    final now = DateTime.now().millisecondsSinceEpoch;

    final shouldShow =
        last == null || now - last >= const Duration(hours: 12).inMilliseconds;

    if (!shouldShow) {
      if (!mounted) return;

      setState(() {
        _welcomeShouldShow = false;
      });

      await _openLogin();
      return;
    }

    await prefs.setInt(_lastWelcomeAtKey, now);

    if (!mounted) return;

    _showNext();
  }

  Future<bool> _restoreSession() async {
    try {
      final saved = await SecureSession.read();

      if (saved == null) {
        return false;
      }

      final ok = await WsClient.instance.connect(
        saved['username']!,
        saved['password']!,
      );

      return ok;
    } catch (_) {
      return false;
    }
  }

  void _showNext() {
    if (!mounted) return;

    setState(() {
      _lines.add(_sequence[_index]);
      _index++;
    });

    if (_index >= _sequence.length) {
      _timer = Timer(const Duration(milliseconds: 900), _openLogin);
      return;
    }

    _timer = Timer(const Duration(milliseconds: 550), _showNext);
  }

  Future<void> _openLogin() async {
    if (!mounted) return;

    final restored = await _sessionRestoreFuture;

    if (!mounted) return;

    if (restored) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainScreen(
            nickname:
                WsClient.instance.nickname ?? WsClient.instance.username ?? '',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, animation, secondaryAnimation) =>
            const NicknameScreen(),
        transitionDuration: const Duration(milliseconds: 450),
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_welcomeShouldShow) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: _welcomeGreen)),
      );
    }

    return Scaffold(
      // Karşılama ekranının orijinal yeşil görünümü.
      // Login ekranına ve uygulamanın diğer temalarına dokunulmaz.
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shield_outlined, size: 78, color: _welcomeGreen),
              const SizedBox(height: 30),
              ..._lines.map(
                (line) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(
                    line,
                    style: TextStyle(
                      fontSize: line == 'ZEROLOG' ? 30 : 17,
                      fontWeight: line == 'ZEROLOG'
                          ? FontWeight.bold
                          : FontWeight.w500,
                      letterSpacing: line == 'ZEROLOG' ? 5 : 3,
                      color: _welcomeGreen,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _welcomeGreen,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SECURE SESSION
// ============================================================
