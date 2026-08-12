import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const String wsUrl = 'wss://zerolog.giize.com:8443/ws';

const List<String> rooms = [
  'genel',
  'sohbet',
  'teknoloji',
  'oyun',
  'müzik',
  'film',
  'spor',
  'gece',
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MatrixZeroApp());
}

// ============================================================
// THEMES
// ============================================================

enum ZeroLogTheme { black, matrix, whatsapp, pink, grey, midnight }

class ZeroLogThemeData {
  final String name;
  final Color background;
  final Color surface;
  final Color primary;
  final Color secondary;
  final Color text;
  final Color bubbleMine;
  final Color bubbleOther;

  const ZeroLogThemeData({
    required this.name,
    required this.background,
    required this.surface,
    required this.primary,
    required this.secondary,
    required this.text,
    required this.bubbleMine,
    required this.bubbleOther,
  });
}

const Map<ZeroLogTheme, ZeroLogThemeData> zeroLogThemes = {
  ZeroLogTheme.black: ZeroLogThemeData(
    name: 'Black & White',
    background: Color(0xFF0B0B0B),
    surface: Color(0xFF171717),
    primary: Color(0xFFE5E5E5),
    secondary: Color(0xFF9E9E9E),
    text: Color(0xFFFFFFFF),
    bubbleMine: Color(0xFF303030),
    bubbleOther: Color(0xFF1E1E1E),
  ),
  ZeroLogTheme.matrix: ZeroLogThemeData(
    name: 'Matrix',
    background: Color(0xFF000000),
    surface: Color(0xFF071407),
    primary: Color(0xFF00FF41),
    secondary: Color(0xFF00B52D),
    text: Color(0xFF00FF41),
    bubbleMine: Color(0xFF123D18),
    bubbleOther: Color(0xFF0A210E),
  ),
  ZeroLogTheme.whatsapp: ZeroLogThemeData(
    name: 'WhatsApp',
    background: Color(0xFFECE5DD),
    surface: Color(0xFFFFFFFF),
    primary: Color(0xFF075E54),
    secondary: Color(0xFF25D366),
    text: Color(0xFF111111),
    bubbleMine: Color(0xFFD9FDD3),
    bubbleOther: Color(0xFFFFFFFF),
  ),
  ZeroLogTheme.pink: ZeroLogThemeData(
    name: 'Pink',
    background: Color(0xFFFFEAF2),
    surface: Color(0xFFFFF5F8),
    primary: Color(0xFFE91E63),
    secondary: Color(0xFFFF80AB),
    text: Color(0xFF171717),
    bubbleMine: Color(0xFFFFB6CF),
    bubbleOther: Color(0xFFFFD9E5),
  ),
  ZeroLogTheme.grey: ZeroLogThemeData(
    name: 'Grey / GPT',
    background: Color(0xFF212121),
    surface: Color(0xFF2F2F2F),
    primary: Color(0xFF10A37F),
    secondary: Color(0xFF8E8E8E),
    text: Color(0xFFF5F5F5),
    bubbleMine: Color(0xFF3A3A3A),
    bubbleOther: Color(0xFF2B2B2B),
  ),
  ZeroLogTheme.midnight: ZeroLogThemeData(
    name: 'Midnight',
    background: Color(0xFF08111F),
    surface: Color(0xFF101D30),
    primary: Color(0xFF64B5F6),
    secondary: Color(0xFF42A5F5),
    text: Color(0xFFF3F7FF),
    bubbleMine: Color(0xFF183B5C),
    bubbleOther: Color(0xFF12263D),
  ),
};

class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  static const _key = 'zerolog_theme';

  ZeroLogTheme current = ZeroLogTheme.matrix;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final index = prefs.getInt(_key);

    if (index != null && index >= 0 && index < ZeroLogTheme.values.length) {
      current = ZeroLogTheme.values[index];
    }
  }

  Future<void> setTheme(ZeroLogTheme theme) async {
    current = theme;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(_key, theme.index);

    notifyListeners();
  }

  ZeroLogThemeData get data => zeroLogThemes[current]!;
}

// ============================================================
// APP
// ============================================================

class MatrixZeroApp extends StatefulWidget {
  const MatrixZeroApp({super.key});

  @override
  State<MatrixZeroApp> createState() => _MatrixZeroAppState();
}

class _MatrixZeroAppState extends State<MatrixZeroApp> {
  final ThemeController _theme = ThemeController.instance;

  bool _themeLoaded = false;

  @override
  void initState() {
    super.initState();
    _theme.addListener(_onThemeChanged);
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    await _theme.load();

    if (mounted) {
      setState(() {
        _themeLoaded = true;
      });
    }
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _theme.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_themeLoaded) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final t = _theme.data;

    return MaterialApp(
      title: 'ZeroLog',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness:
            ThemeData.estimateBrightnessForColor(t.background) ==
                Brightness.dark
            ? Brightness.dark
            : Brightness.light,
        scaffoldBackgroundColor: t.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: t.primary,
          brightness:
              ThemeData.estimateBrightnessForColor(t.background) ==
                  Brightness.dark
              ? Brightness.dark
              : Brightness.light,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: t.surface,
          foregroundColor: t.text,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: t.surface,
        ),
        useMaterial3: true,
      ),
      home: const WelcomeScreen(),
    );
  }
}

// ============================================================
// WELCOME
// ============================================================

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final List<String> _lines = [];
  Timer? _timer;

  static const List<String> _sequence = [
    'ZEROLOG',
    'PRIVATE',
    'ENCRYPTED',
    'NO LOGS',
  ];

  int _index = 0;
  late final Future<bool> _sessionRestoreFuture;

  @override
  void initState() {
    super.initState();

    _sessionRestoreFuture = _restoreSession();

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
    final theme = ThemeController.instance.data;

    return Scaffold(
      backgroundColor: theme.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shield_outlined, size: 78, color: theme.primary),
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
                      color: theme.primary,
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
                  color: theme.primary,
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

class SecureSession {
  SecureSession._();

  static const String usernameKey = 'zerolog.session.username';
  static const String passwordKey = 'zerolog.session.password';

  static const FlutterSecureStorage storage = FlutterSecureStorage();

  static Future<void> save({
    required String username,
    required String password,
  }) async {
    await storage.write(key: usernameKey, value: username);

    await storage.write(key: passwordKey, value: password);
  }

  static Future<Map<String, String>?> read() async {
    final username = await storage.read(key: usernameKey);
    final password = await storage.read(key: passwordKey);

    if (username == null ||
        username.trim().isEmpty ||
        password == null ||
        password.isEmpty) {
      return null;
    }

    return {'username': username, 'password': password};
  }

  static Future<void> clear() async {
    await storage.delete(key: usernameKey);
    await storage.delete(key: passwordKey);
  }
}

// ============================================================
// WEBSOCKET SERVICE
// ============================================================

class WsClient {
  WsClient._();

  static final WsClient instance = WsClient._();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;

  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get events => _events.stream;

  final Set<String> _onlineUsers = <String>{};

  List<String> get onlineUsers => List.unmodifiable(_onlineUsers);

  String? nickname;
  String? username;
  String? password;
  bool connected = false;

  bool _manualDisconnect = false;
  bool _connecting = false;
  int _reconnectAttempt = 0;

  final Set<String> _activeRooms = <String>{};

  final List<Map<String, dynamic>> _outgoingQueue = <Map<String, dynamic>>[];

  Future<void> onAppResumed() async {
    if (_manualDisconnect ||
        username == null ||
        username!.isEmpty ||
        password == null ||
        password!.isEmpty) {
      return;
    }

    // If Android suspended the socket, reconnect immediately.
    if (!connected || _channel == null) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _reconnectAttempt = 0;
      await _connectInternal();
      return;
    }

    requestPresence();
    _restoreActiveRooms();
  }

  void requestPresence() {
    if (!connected || _channel == null) return;

    try {
      _channel!.sink.add(jsonEncode({'type': 'getPresence'}));
    } catch (_) {
      _handleConnectionLost();
    }
  }

  void joinRoom(String room) {
    final id = room.trim();
    if (id.isEmpty) return;

    _activeRooms.add(id);

    if (connected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode({'type': 'joinRoom', 'room': id}));
      } catch (_) {
        _handleConnectionLost();
      }
    }
  }

  void leaveRoom(String room) {
    final id = room.trim();
    if (id.isEmpty) return;

    _activeRooms.remove(id);

    if (connected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode({'type': 'leaveRoom', 'room': id}));
      } catch (_) {
        _handleConnectionLost();
      }
    }
  }

  void _restoreActiveRooms() {
    if (!connected || _channel == null) return;

    for (final room in _activeRooms) {
      try {
        _channel!.sink.add(jsonEncode({'type': 'joinRoom', 'room': room}));
      } catch (_) {
        _handleConnectionLost();
        return;
      }
    }
  }

  Future<bool> connect(String username, String password) async {
    _manualDisconnect = false;
    this.username = username.trim();
    this.password = password;
    nickname = this.username;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();

    return _connectInternal();
  }

  Future<bool> _connectInternal() async {
    if (_connecting ||
        username == null ||
        username!.isEmpty ||
        password == null) {
      return connected;
    }

    _connecting = true;

    try {
      await _closeCurrent();

      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _channel = channel;

      final authCompleter = Completer<bool>();

      _subscription = channel.stream.listen(
        (raw) {
          try {
            final decoded = jsonDecode(raw.toString());

            if (decoded is Map) {
              final data = Map<String, dynamic>.from(decoded);

              if (data['type'] == 'authenticated') {
                final authenticatedName = (data['username'] ?? username ?? '')
                    .toString();

                username = authenticatedName;
                nickname = authenticatedName;
                connected = true;

                if (!authCompleter.isCompleted) {
                  authCompleter.complete(true);
                }
              }

              if (data['type'] == 'userList') {
                final raw = data['users'];

                if (raw is List) {
                  _onlineUsers
                    ..clear()
                    ..addAll(
                      raw
                          .map((e) => e.toString().trim())
                          .where((e) => e.isNotEmpty)
                          .where(
                            (e) =>
                                e.toLowerCase() !=
                                (nickname ?? '').toLowerCase(),
                          ),
                    );
                }
              }

              if (data['type'] == 'userOnline') {
                final name = (data['username'] ?? data['nick'] ?? '')
                    .toString()
                    .trim();

                if (name.isNotEmpty &&
                    name.toLowerCase() != (nickname ?? '').toLowerCase()) {
                  _onlineUsers.removeWhere(
                    (user) => user.toLowerCase() == name.toLowerCase(),
                  );
                  _onlineUsers.add(name);
                }
              }

              if (data['type'] == 'userOffline') {
                final name = (data['username'] ?? data['nick'] ?? '')
                    .toString()
                    .trim();

                if (name.isNotEmpty) {
                  _onlineUsers.removeWhere(
                    (user) => user.toLowerCase() == name.toLowerCase(),
                  );
                }
              }

              if (data['type'] == 'authError') {
                connected = false;

                if (!authCompleter.isCompleted) {
                  authCompleter.complete(false);
                }
              }

              _events.add(data);
            }
          } catch (_) {}
        },
        onError: (_) {
          connected = false;

          if (!authCompleter.isCompleted) {
            authCompleter.complete(false);
          }

          _handleConnectionLost();
        },
        onDone: () {
          connected = false;

          if (!authCompleter.isCompleted) {
            authCompleter.complete(false);
          }

          _handleConnectionLost();
        },
        cancelOnError: false,
      );

      await channel.ready;

      channel.sink.add(
        jsonEncode({
          'type': 'login',
          'username': username,
          'password': password,
        }),
      );

      final authenticated = await authCompleter.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => false,
      );

      if (!authenticated) {
        connected = false;
        await _closeCurrent();
        return false;
      }

      _reconnectAttempt = 0;
      _startHeartbeat();
      _restoreActiveRooms();
      _flushOutgoingQueue();

      _events.add({'type': 'connectionRestored'});

      return true;
    } catch (_) {
      connected = false;
      _scheduleReconnect();
      return false;
    } finally {
      _connecting = false;
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!connected || _channel == null) return;

      try {
        _channel!.sink.add(jsonEncode({'type': 'listRooms'}));
      } catch (_) {
        _handleConnectionLost();
      }
    });
  }

  void _handleConnectionLost() {
    if (_manualDisconnect) return;

    final wasConnected = connected;
    connected = false;
    _heartbeatTimer?.cancel();

    if (wasConnected) {
      _events.add({'type': 'connectionLost'});
    }

    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_manualDisconnect ||
        _connecting ||
        nickname == null ||
        nickname!.isEmpty ||
        connected) {
      return;
    }

    _reconnectTimer?.cancel();

    _reconnectAttempt++;

    final seconds = (_reconnectAttempt <= 1)
        ? 2
        : (_reconnectAttempt <= 3)
        ? 4
        : (_reconnectAttempt <= 6)
        ? 8
        : 15;

    _events.add({'type': 'reconnecting', 'seconds': seconds});

    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _connectInternal();
    });
  }

  void send(Map<String, dynamic> data) {
    if (!connected || _channel == null) {
      _outgoingQueue.add(Map<String, dynamic>.from(data));
      return;
    }

    try {
      _channel!.sink.add(jsonEncode(data));
    } catch (_) {
      _outgoingQueue.add(Map<String, dynamic>.from(data));
      _handleConnectionLost();
    }
  }

  void _flushOutgoingQueue() {
    if (!connected || _channel == null || _outgoingQueue.isEmpty) {
      return;
    }

    final pending = List<Map<String, dynamic>>.from(_outgoingQueue);

    _outgoingQueue.clear();

    for (final data in pending) {
      try {
        _channel!.sink.add(jsonEncode(data));
      } catch (_) {
        _outgoingQueue.insert(0, data);
        _handleConnectionLost();
        return;
      }
    }
  }

  Future<void> _closeCurrent() async {
    _heartbeatTimer?.cancel();

    await _subscription?.cancel();
    _subscription = null;

    try {
      await _channel?.sink.close();
    } catch (_) {}

    _channel = null;
    connected = false;
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer = null;

    await _closeCurrent();
  }
}

/// ZeroLog approved reference UI.
/// The reference image supplies the visual design.
/// Flutter supplies only transparent interaction layers.

class _ZeroLogWavePainter extends CustomPainter {
  final double progress;

  const _ZeroLogWavePainter({
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;

    for (var i = 0; i < 20; i++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = const Color(0xFF39FF88).withValues(
          alpha: 0.08 + ((1 - (i / 20)) * 0.10),
        );

      final path = Path();

      final amplitude = 2.0 + (i % 4) * 0.8;
      final y = centerY - 22 + (i * 2.3);

      for (var x = 0.0; x <= size.width; x += 3) {
        final normalized = x / size.width;
        final phase =
            (normalized * math.pi * 2.4) +
            (progress * math.pi * 2) +
            (i * 0.17);

        final wave = math.sin(phase) * amplitude;

        final pointY = y + wave;

        if (x == 0) {
          path.moveTo(x, pointY);
        } else {
          path.lineTo(x, pointY);
        }
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ZeroLogWavePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class ZeroLogReferenceLogin extends StatefulWidget {
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool loading;
  final bool obscurePassword;
  final bool registerMode;
  final VoidCallback onSubmit;
  final VoidCallback onTogglePassword;
  final VoidCallback onRegister;

  const ZeroLogReferenceLogin({
    super.key,
    required this.usernameController,
    required this.passwordController,
    required this.loading,
    required this.obscurePassword,
    required this.registerMode,
    required this.onSubmit,
    required this.onTogglePassword,
    required this.onRegister,
  });

  @override
  State<ZeroLogReferenceLogin> createState() =>
      _ZeroLogReferenceLoginState();
}

class _ZeroLogReferenceLoginState extends State<ZeroLogReferenceLogin>
    with SingleTickerProviderStateMixin {
  static const green = Color(0xFF35E57F);

  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }
  static const greenBright = Color(0xFF39FF88);
  static const fieldBg = Color(0xFF0D1410);

  InputDecoration _decoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Color(0xFF777D79),
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: Icon(
        icon,
        color: greenBright,
        size: 30,
      ),
      suffixIcon: suffix,
      filled: true,
      fillColor: fieldBg,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 21,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(
          color: Color(0xFF244F38),
          width: 1.4,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(
          color: greenBright,
          width: 1.5,
        ),
      ),
    );
  }

  Widget _usernameField() {
    return TextField(
      controller: widget.usernameController,
      enabled: !widget.loading,
      autocorrect: false,
      textInputAction: TextInputAction.next,
      keyboardType: TextInputType.text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
      cursorColor: greenBright,
      decoration: _decoration(
        hint: 'Kullanıcı adı',
        icon: Icons.person_outline_rounded,
      ),
    );
  }

  Widget _passwordField() {
    return TextField(
      controller: widget.passwordController,
      enabled: !widget.loading,
      obscureText: widget.obscurePassword,
      autocorrect: false,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => widget.onSubmit(),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
      cursorColor: greenBright,
      decoration: _decoration(
        hint: 'Şifre',
        icon: Icons.lock_outline_rounded,
        suffix: IconButton(
          onPressed: widget.loading ? null : widget.onTogglePassword,
          icon: Icon(
            widget.obscurePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: Colors.white70,
            size: 30,
          ),
        ),
      ),
    );
  }

  Future<void> _showForgotDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111613),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(
              color: Color(0xFF2DFF82),
              width: 1,
            ),
          ),
          title: const Text(
            'UNUTMASAYDIN 🤣',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'TAMAM',
                style: TextStyle(
                  color: greenBright,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _primaryButton() {
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: FilledButton(
        onPressed: widget.loading ? null : widget.onSubmit,
        style: FilledButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: widget.loading
            ? const SizedBox(
                width: 25,
                height: 25,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.black,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.registerMode ? 'HESAP OLUŞTUR' : 'GİRİŞ',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: widget.registerMode ? 18 : 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: widget.registerMode ? 1.2 : 1.8,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _registerButton() {
    return SizedBox(
      width: double.infinity,
      height: 62,
      child: OutlinedButton(
        onPressed: widget.loading ? null : widget.onRegister,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.transparent,
          side: const BorderSide(
            color: greenBright,
            width: 1.4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.registerMode
                  ? Icons.login_rounded
                  : Icons.person_add_alt_1_rounded,
              size: 28,
              color: Colors.white,
            ),
            const SizedBox(width: 14),
            Text(
              widget.registerMode
                  ? 'Giriş ekranına dön'
                  : 'Yeni hesap oluştur',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(42, 30, 42, 28),
                  child: Column(
                    children: [
                      // LOGO
                      Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(27),
                          border: Border.all(
                            color: greenBright,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: greenBright.withValues(alpha: 0.18),
                              blurRadius: 35,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Z',
                          style: TextStyle(
                            color: greenBright,
                            fontSize: 58,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),

                      const SizedBox(height: 22),

                      // BRAND
                      RichText(
                        text: const TextSpan(
                          style: TextStyle(
                            fontSize: 46,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.5,
                          ),
                          children: [
                            TextSpan(
                              text: 'Zero',
                              style: TextStyle(color: Colors.white),
                            ),
                            TextSpan(
                              text: 'Log',
                              style: TextStyle(color: greenBright),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      const Text(
                        'Gizlilik odaklı iletişim',
                        style: TextStyle(
                          color: Color(0xFF8B918D),
                          fontSize: 16,
                        ),
                      ),

                      const SizedBox(height: 12),

                      AnimatedBuilder(
                        animation: _waveController,
                        builder: (context, child) {
                          return SizedBox(
                            width: 190,
                            height: 48,
                            child: CustomPaint(
                              painter: _ZeroLogWavePainter(
                                progress: _waveController.value,
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 34),

                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Text(
                          widget.registerMode
                              ? 'Yeni hesabınızı oluşturun'
                              : '',
                          key: ValueKey(widget.registerMode),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                      ),

                      if (widget.registerMode)
                        const SizedBox(height: 16),

                      _usernameField(),

                      const SizedBox(height: 16),

                      _passwordField(),

                      if (!widget.registerMode) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed:
                                widget.loading ? null : _showForgotDialog,
                            child: const Text(
                              'Şifremi Unuttum?',
                              style: TextStyle(
                                color: greenBright,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      _primaryButton(),

                      const SizedBox(height: 16),

                      _registerButton(),

                      const SizedBox(height: 24),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.lock_outline_rounded,
                            color: greenBright,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Verileriniz uçtan uca şifrelenir.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class NicknameScreen extends StatefulWidget {
  const NicknameScreen({super.key});

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _usernameController = TextEditingController();

  final TextEditingController _passwordController = TextEditingController();

  late final AnimationController _geometryController;

  bool _loading = false;
  bool _registerMode = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();

    _geometryController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.length < 3) {
      _show('Kullanıcı adı en az 3 karakter olmalı.');
      return;
    }

    if (password.length < 8) {
      _show('Şifre en az 8 karakter olmalı.');
      return;
    }

    setState(() {
      _loading = true;
    });

    if (_registerMode) {
      await _register(username, password);
    } else {
      await _login(username, password);
    }
  }

  Future<void> _register(String username, String password) async {
    try {
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      final subscription = channel.stream.listen(
        (raw) {
          try {
            final decoded = jsonDecode(raw.toString());

            if (decoded is! Map) return;

            final data = Map<String, dynamic>.from(decoded);

            if (!mounted) return;

            if (data['type'] == 'accountRegistered') {
              channel.sink.close();
              setState(() {
                _loading = false;
                _registerMode = false;
              });

              _show('Hesap oluşturuldu. Şimdi giriş yapabilirsiniz.');
            }

            if (data['type'] == 'authError') {
              channel.sink.close();

              setState(() {
                _loading = false;
              });

              _show((data['message'] ?? 'Kayıt başarısız.').toString());
            }
          } catch (_) {}
        },
        onError: (_) {
          if (!mounted) return;

          setState(() {
            _loading = false;
          });

          _show('Sunucuya bağlanılamadı.');
        },
      );

      await channel.ready;

      channel.sink.add(
        jsonEncode({
          'type': 'registerAccount',
          'username': username,
          'password': password,
        }),
      );

      Future.delayed(const Duration(seconds: 10), () {
        subscription.cancel();
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      _show('Sunucuya bağlanılamadı.');
    }
  }

  Future<void> _login(String username, String password) async {
    setState(() {
      _loading = true;
    });

    final ok = await WsClient.instance.connect(username, password);

    if (!mounted) return;

    setState(() {
      _loading = false;
    });

    if (!ok) {
      _show(
        'Giriş başarısız. Kullanıcı adı, şifre veya hesap durumu kontrol edilmeli.',
      );
      return;
    }

    await SecureSession.save(username: username, password: password);

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            MainScreen(nickname: WsClient.instance.nickname ?? username),
      ),
    );
  }

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    _geometryController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ZeroLogReferenceLogin(
      usernameController: _usernameController,
      passwordController: _passwordController,
      loading: _loading,
      obscurePassword: _obscurePassword,
      registerMode: _registerMode,
      onSubmit: _submit,
      onTogglePassword: () {
        setState(() {
          _obscurePassword = !_obscurePassword;
        });
      },
      onRegister: () {
        setState(() {
          _registerMode = !_registerMode;
        });
      },
    );
  }
}

// ============================================================
// ZEROLOG LOGIN WAVE
// ============================================================

// ============================================================
// MAIN
// ============================================================

// ============================================================

class MainScreen extends StatefulWidget {
  final String nickname;

  const MainScreen({super.key, required this.nickname});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  late final StreamSubscription<Map<String, dynamic>> _subscription;

  final List<String> _onlineUsers = [];

  bool _connected = false;
  bool _reconnecting = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _connected = WsClient.instance.connected;

    _onlineUsers
      ..clear()
      ..addAll(WsClient.instance.onlineUsers);

    _subscription = WsClient.instance.events.listen(_handleEvent);

    WsClient.instance.requestPresence();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Android may suspend the WebSocket while the app is in background.
      // Force a presence/reconnect cycle when returning to foreground.
      WsClient.instance.onAppResumed();
    }
  }

  Future<void> _handleEvent(Map<String, dynamic> data) async {
    if (!mounted) return;

    final type = data['type'];

    if (type == 'accountDeleted') {
      await SecureSession.clear();
      await WsClient.instance.disconnect();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const NicknameScreen()),
        (route) => false,
      );
      return;
    }

    if (type == 'registered') {
      setState(() {
        _connected = data['success'] != false;
      });
    }

    if (type == 'userList') {
      final raw = data['users'];

      if (raw is List) {
        final users = raw
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .where((e) => e.toLowerCase() != widget.nickname.toLowerCase())
            .toSet()
            .toList();

        setState(() {
          _onlineUsers
            ..clear()
            ..addAll(users);
        });
      }
    }

    if (type == 'userOnline') {
      final username = (data['username'] ?? data['nick'] ?? '')
          .toString()
          .trim();

      if (username.isNotEmpty &&
          username.toLowerCase() != widget.nickname.toLowerCase()) {
        setState(() {
          if (!_onlineUsers.any(
            (user) => user.toLowerCase() == username.toLowerCase(),
          )) {
            _onlineUsers.add(username);
          }
        });
      }
    }

    if (type == 'userOffline') {
      final username = (data['username'] ?? data['nick'] ?? '')
          .toString()
          .trim();

      if (username.isNotEmpty) {
        setState(() {
          _onlineUsers.removeWhere(
            (user) => user.toLowerCase() == username.toLowerCase(),
          );
        });
      }
    }

    if (type == 'reconnecting') {
      setState(() {
        _connected = false;
        _reconnecting = true;
      });
    }

    if (type == 'connectionLost' ||
        type == 'connectionError' ||
        type == 'connectionClosed') {
      setState(() {
        _connected = false;
        _reconnecting = true;
        _onlineUsers.clear();
      });
    }

    if (type == 'connectionRestored' || type == 'registered') {
      setState(() {
        _connected = true;
        _reconnecting = false;
      });
    }

    if (type == 'callOffer') {
      final from = (data['from'] ?? '').toString();
      final to = (data['to'] ?? '').toString();

      if (from.isEmpty || to.isEmpty) return;

      if (to.toLowerCase() != widget.nickname.toLowerCase()) {
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            myNick: widget.nickname,
            targetNick: from,
            outgoing: false,
            incomingOffer: data['sdp']?.toString(),
          ),
        ),
      );
    }
  }

  void _openRoom(String room) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ChatRoomScreen(nickname: widget.nickname, roomName: room),
      ),
    );
  }

  void _openPrivate(String target) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PrivateChatScreen(myNick: widget.nickname, targetNick: target),
      ),
    );
  }

  void _call(String target) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          myNick: widget.nickname,
          targetNick: target,
          outgoing: true,
        ),
      ),
    );
  }

  Future<void> _selectTheme(ZeroLogTheme theme) async {
    await ThemeController.instance.setTheme(theme);
  }

  Future<void> _logout() async {
    await WsClient.instance.disconnect();
    await SecureSession.clear();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const NicknameScreen()),
      (route) => false,
    );
  }

  Future<void> _deleteAccount({required bool allData}) async {
    final title = allData ? 'Tüm kayıtları sil' : 'Hesabı sil';

    final message = allData
        ? 'Hesabınız, özel mesajlarınız ve odalarda gönderdiğiniz mesajlar kalıcı olarak silinecek. Bu işlem geri alınamaz.'
        : 'Hesabınız ve özel mesaj geçmişiniz kalıcı olarak silinecek. Bu işlem geri alınamaz.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    WsClient.instance.send({
      'type': allData ? 'deleteAllData' : 'deleteAccount',
    });
  }

  void _openAccountMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(widget.nickname),
                  subtitle: const Text('Hesap'),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Oturumu kapat'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _logout();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined),
                  title: const Text('Tüm kayıtları sil'),
                  subtitle: const Text('Hesap + özel mesajlar + oda mesajları'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _deleteAccount(allData: true);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.nickname),
          actions: [
            IconButton(
              tooltip: 'Hesap',
              icon: const Icon(Icons.person_outline),
              onPressed: _openAccountMenu,
            ),
            PopupMenuButton<ZeroLogTheme>(
              tooltip: 'Tema',
              icon: const Icon(Icons.palette_outlined),
              onSelected: _selectTheme,
              itemBuilder: (_) {
                return ZeroLogTheme.values.map((theme) {
                  final data = zeroLogThemes[theme]!;

                  return PopupMenuItem<ZeroLogTheme>(
                    value: theme,
                    child: Row(
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: data.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(data.name)),
                        if (ThemeController.instance.current == theme)
                          const Icon(Icons.check, size: 18),
                      ],
                    ),
                  );
                }).toList();
              },
            ),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Icon(
                  Icons.circle,
                  size: 12,
                  color: _connected
                      ? Colors.greenAccent
                      : _reconnecting
                      ? Colors.amber
                      : Colors.red,
                ),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.forum_outlined), text: 'Odalar'),
              Tab(icon: Icon(Icons.people_outline), text: 'Online'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 10),
              itemCount: rooms.length,
              itemBuilder: (_, index) {
                final room = rooms[index];

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(room),
                    subtitle: const Text('Sohbet odası'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openRoom(room),
                  ),
                );
              },
            ),
            _onlineUsers.isEmpty
                ? const Center(
                    child: Text('Şu anda çevrimiçi kullanıcı görünmüyor.'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    itemCount: _onlineUsers.length,
                    itemBuilder: (_, index) {
                      final user = _onlineUsers[index];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        child: ListTile(
                          leading: const Icon(
                            Icons.circle,
                            color: Colors.greenAccent,
                            size: 13,
                          ),
                          title: Text(user),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Mesaj',
                                icon: const Icon(Icons.chat_outlined),
                                onPressed: () => _openPrivate(user),
                              ),
                              IconButton(
                                tooltip: 'Sesli ara',
                                icon: const Icon(
                                  Icons.call,
                                  color: Colors.greenAccent,
                                ),
                                onPressed: () => _call(user),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ROOM CHAT
// ============================================================

class ChatRoomScreen extends StatefulWidget {
  final String nickname;
  final String roomName;

  const ChatRoomScreen({
    super.key,
    required this.nickname,
    required this.roomName,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _controller = TextEditingController();

  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];

  late final StreamSubscription<Map<String, dynamic>> _subscription;

  @override
  void initState() {
    super.initState();

    _subscription = WsClient.instance.events.listen(_handleEvent);

    WsClient.instance.joinRoom(widget.roomName);
  }

  void _handleEvent(Map<String, dynamic> data) {
    if (!mounted) return;

    if (data['type'] == 'roomHistory' && data['room'] == widget.roomName) {
      final history = data['messages'];

      if (history is List) {
        for (final item in history) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);

            _addMessage(
              ChatMessage(
                id:
                    (map['id'] ??
                            'legacy-${widget.roomName}-${map['ts'] ?? ''}-${map['from'] ?? map['sender'] ?? ''}-${map['text'] ?? ''}')
                        .toString(),
                sender: (map['sender'] ?? map['from'] ?? '').toString(),
                text: (map['text'] ?? '').toString(),
              ),
            );
          }
        }
      }
    }

    if (data['type'] == 'roomMessage' && data['room'] == widget.roomName) {
      _addMessage(
        ChatMessage(
          id:
              (data['id'] ??
                      'live-${data['ts'] ?? ''}-${data['from'] ?? data['sender'] ?? ''}-${data['text'] ?? ''}')
                  .toString(),
          sender: (data['sender'] ?? data['from'] ?? '').toString(),
          text: (data['text'] ?? '').toString(),
        ),
      );
    }
  }

  void _addMessage(ChatMessage message) {
    if (message.text.isEmpty) return;

    final exists = _messages.any((m) => m.id == message.id);

    if (exists) return;

    setState(() {
      _messages.add(message);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    final text = _controller.text.trim();

    if (text.isEmpty) return;

    WsClient.instance.send({
      'type': 'roomMessage',
      'room': widget.roomName,
      'text': text,
    });

    _controller.clear();
  }

  @override
  void dispose() {
    WsClient.instance.leaveRoom(widget.roomName);
    _subscription.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.roomName)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(10),
              itemCount: _messages.length,
              itemBuilder: (_, index) {
                final message = _messages[index];

                final mine =
                    message.sender.toLowerCase() ==
                    widget.nickname.toLowerCase();

                return Align(
                  alignment: mine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 500),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: mine
                          ? ThemeController.instance.data.bubbleMine
                          : ThemeController.instance.data.bubbleOther,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!mine)
                          Text(
                            message.sender,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.greenAccent,
                            ),
                          ),
                        if (!mine) const SizedBox(height: 3),
                        Text(message.text),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          MessageInput(controller: _controller, onSend: _send),
        ],
      ),
    );
  }
}

// ============================================================
// PRIVATE CHAT
// ============================================================

class PrivateChatScreen extends StatefulWidget {
  final String myNick;
  final String targetNick;

  const PrivateChatScreen({
    super.key,
    required this.myNick,
    required this.targetNick,
  });

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final TextEditingController _controller = TextEditingController();

  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];

  late final StreamSubscription<Map<String, dynamic>> _subscription;

  @override
  void initState() {
    super.initState();

    _subscription = WsClient.instance.events.listen(_handleEvent);

    WsClient.instance.send({
      'type': 'privateHistory',
      'peer': widget.targetNick,
    });
  }

  void _handleEvent(Map<String, dynamic> data) {
    if (!mounted) return;

    if (data['type'] == 'privateHistory') {
      final peer = (data['peer'] ?? data['with'] ?? data['target'] ?? '')
          .toString();

      if (peer.isNotEmpty &&
          peer.toLowerCase() != widget.targetNick.toLowerCase()) {
        return;
      }

      final list = data['messages'];

      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);

            _addMessage(
              ChatMessage(
                id:
                    (map['id'] ??
                            'private-legacy-${map['ts'] ?? ''}-${map['from'] ?? map['sender'] ?? ''}-${map['to'] ?? ''}-${map['text'] ?? ''}')
                        .toString(),
                sender: (map['sender'] ?? map['from'] ?? '').toString(),
                text: (map['text'] ?? '').toString(),
              ),
            );
          }
        }
      }
    }

    if (data['type'] == 'messageAck') {
      final clientMessageId = (data['clientMessageId'] ?? '').toString();

      if (clientMessageId.isNotEmpty) {
        final messageId = (data['messageId'] ?? '').toString();

        setState(() {
          for (var i = 0; i < _messages.length; i++) {
            final message = _messages[i];

            if (message.clientMessageId == clientMessageId) {
              _messages[i] = message.copyWith(
                id: messageId.isNotEmpty ? messageId : message.id,
                status: 'stored',
              );
              break;
            }
          }
        });
      }

      return;
    }

    if (data['type'] == 'messageDelivered') {
      final messageId = (data['messageId'] ?? '').toString();

      final clientMessageId = (data['clientMessageId'] ?? '').toString();

      setState(() {
        for (var i = 0; i < _messages.length; i++) {
          final message = _messages[i];

          final matches =
              (clientMessageId.isNotEmpty &&
                  message.clientMessageId == clientMessageId) ||
              (messageId.isNotEmpty && message.id == messageId);

          if (matches) {
            _messages[i] = message.copyWith(
              id: messageId.isNotEmpty ? messageId : message.id,
              clientMessageId: clientMessageId.isNotEmpty
                  ? clientMessageId
                  : message.clientMessageId,
              status: 'delivered',
            );
            break;
          }
        }
      });

      return;
    }

    if (data['type'] == 'pendingPrivateMessages') {
      final list = data['messages'];

      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);

            final sender = (map['sender'] ?? map['from'] ?? '').toString();

            final target = (map['to'] ?? map['target'] ?? '').toString();

            if (sender.toLowerCase() != widget.targetNick.toLowerCase() ||
                target.toLowerCase() != widget.myNick.toLowerCase()) {
              continue;
            }

            final clientMessageId = (map['clientMessageId'] ?? '').toString();

            _addMessage(
              ChatMessage(
                id:
                    (map['id'] ??
                            (clientMessageId.isNotEmpty
                                ? clientMessageId
                                : 'pending-${map['ts'] ?? ''}-$sender-${map['text'] ?? ''}'))
                        .toString(),
                sender: sender,
                text: (map['text'] ?? '').toString(),
                clientMessageId: clientMessageId,
                status: 'delivered',
              ),
            );

            WsClient.instance.send({
              'type': 'messageDelivered',
              'from': sender,
              'messageId': (map['id'] ?? '').toString(),
              'clientMessageId': clientMessageId,
            });
          }
        }
      }

      return;
    }

    if (data['type'] == 'privateMessage') {
      final sender = (data['sender'] ?? data['from'] ?? '').toString();

      final target = (data['to'] ?? data['target'] ?? '').toString();

      final isFromPeer =
          sender.toLowerCase() == widget.targetNick.toLowerCase();

      final isFromMe = sender.toLowerCase() == widget.myNick.toLowerCase();

      final validPeerTarget =
          target.isEmpty || target.toLowerCase() == widget.myNick.toLowerCase();

      final validSelfTarget =
          target.isEmpty ||
          target.toLowerCase() == widget.targetNick.toLowerCase();

      final validTarget = isFromMe ? validSelfTarget : validPeerTarget;

      if ((!isFromPeer && !isFromMe) || !validTarget) {
        return;
      }

      final clientMessageId = (data['clientMessageId'] ?? '').toString();

      _addMessage(
        ChatMessage(
          id:
              (data['id'] ??
                      (clientMessageId.isNotEmpty
                          ? clientMessageId
                          : 'private-live-${data['ts'] ?? ''}-$sender-$target-${data['text'] ?? ''}'))
                  .toString(),
          sender: sender,
          text: (data['text'] ?? '').toString(),
          clientMessageId: clientMessageId,
        ),
      );

      // Mesaj karşı cihaza ulaştığında server'a teslim bilgisi gönder.
      if (sender.toLowerCase() == widget.targetNick.toLowerCase() &&
          clientMessageId.isNotEmpty) {
        WsClient.instance.send({
          'type': 'messageDelivered',
          'from': sender,
          'messageId': (data['id'] ?? '').toString(),
          'clientMessageId': clientMessageId,
        });
      }
    }
  }

  void _addMessage(ChatMessage message) {
    if (message.text.isEmpty) return;

    final exists = _messages.any((m) => m.id == message.id);

    if (exists) return;

    setState(() {
      _messages.add(message);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    final text = _controller.text.trim();

    if (text.isEmpty) return;

    final clientMessageId =
        '${DateTime.now().microsecondsSinceEpoch}-${widget.myNick}-${widget.targetNick}';

    WsClient.instance.send({
      'type': 'privateMessage',
      'to': widget.targetNick,
      'text': text,
      'clientMessageId': clientMessageId,
    });

    _controller.clear();
  }

  @override
  void dispose() {
    _subscription.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.targetNick)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(10),
              itemCount: _messages.length,
              itemBuilder: (_, index) {
                final message = _messages[index];

                final mine =
                    message.sender.toLowerCase() == widget.myNick.toLowerCase();

                return Align(
                  alignment: mine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 500),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: mine
                          ? ThemeController.instance.data.bubbleMine
                          : ThemeController.instance.data.bubbleOther,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(message.text),
                  ),
                );
              },
            ),
          ),
          MessageInput(controller: _controller, onSend: _send),
        ],
      ),
    );
  }
}

// ============================================================
// WEBRTC CALL
// ============================================================

class CallScreen extends StatefulWidget {
  final String myNick;
  final String targetNick;
  final bool outgoing;
  final String? incomingOffer;

  const CallScreen({
    super.key,
    required this.myNick,
    required this.targetNick,
    required this.outgoing,
    this.incomingOffer,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  late final StreamSubscription<Map<String, dynamic>> _subscription;

  final List<RTCIceCandidate> _pendingIceCandidates = [];

  bool _accepted = false;
  bool _connected = false;
  bool _muted = false;
  bool _speakerOn = false;
  bool _closing = false;
  bool _remoteDescriptionSet = false;

  @override
  void initState() {
    super.initState();

    _subscription = WsClient.instance.events.listen(_handleEvent);

    if (widget.outgoing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startOutgoingCall();
      });
    }
  }

  Future<void> _createPeerConnection() async {
    if (_peerConnection != null || _closing) return;

    try {
      // Android voice communication audio session must be configured
      // before creating the WebRTC peer connection.
      await Helper.setAndroidAudioConfiguration(
        AndroidAudioConfiguration.communication,
      );

      if (_closing) return;

      final configuration = <String, dynamic>{
        'iceServers': [
          {
            'urls': [
              'stun:stun.l.google.com:19302',
              'stun:stun1.l.google.com:19302',
            ],
          },
        ],
        'sdpSemantics': 'unified-plan',
      };

      final peer = await createPeerConnection(configuration);

      if (_closing) {
        try {
          await peer.close();
        } catch (_) {}
        try {
          await peer.dispose();
        } catch (_) {}
        return;
      }

      _peerConnection = peer;

      peer.onIceCandidate = (RTCIceCandidate candidate) {
        if (_closing || candidate.candidate == null) return;

        WsClient.instance.send({
          'type': 'callIce',
          'from': widget.myNick,
          'to': widget.targetNick,
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      };

      peer.onConnectionState = (RTCPeerConnectionState state) {
        if (!mounted || _closing) return;

        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          setState(() {
            _connected = true;
          });
        } else if (state ==
                RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          setState(() {
            _connected = false;
          });
        }
      };

      // Audio only. No camera is requested.
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });

      if (_closing) {
        for (final track in stream.getTracks()) {
          try {
            await track.stop();
          } catch (_) {}
        }
        try {
          await stream.dispose();
        } catch (_) {}
        return;
      }

      _localStream = stream;

      for (final track in stream.getAudioTracks()) {
        if (_closing) break;
        await peer.addTrack(track, stream);
      }

      if (_closing) return;

      // Start with normal handset audio. Speaker can be enabled
      // explicitly from the call screen.
      try {
        await Helper.setSpeakerphoneOn(false);
      } catch (_) {}
    } catch (e) {
      // Keep the failure inside the Flutter layer instead of leaving
      // partially initialized WebRTC objects behind.
      final peer = _peerConnection;
      _peerConnection = null;

      if (peer != null) {
        try {
          await peer.close();
        } catch (_) {}
        try {
          await peer.dispose();
        } catch (_) {}
      }

      rethrow;
    }
  }

  Future<void> _startOutgoingCall() async {
    if (_closing) return;

    try {
      await _createPeerConnection();

      final peer = _peerConnection;
      if (peer == null || _closing) return;

      final offer = await peer.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });

      await peer.setLocalDescription(offer);

      if (_closing) return;

      WsClient.instance.send({
        'type': 'callOffer',
        'from': widget.myNick,
        'to': widget.targetNick,
        'sdp': offer.sdp,
      });

      if (mounted) {
        setState(() {
          _accepted = true;
        });
      }
    } catch (e) {
      if (mounted && !_closing) {
        _showError('Arama başlatılamadı.');
      }
    }
  }

  Future<void> _acceptIncoming() async {
    final incomingOffer = widget.incomingOffer;

    if (incomingOffer == null || incomingOffer.isEmpty) {
      return;
    }

    try {
      await _createPeerConnection();

      final peer = _peerConnection;
      if (peer == null || _closing) return;

      await peer.setRemoteDescription(
        RTCSessionDescription(incomingOffer, 'offer'),
      );

      _remoteDescriptionSet = true;

      await _flushPendingIceCandidates();

      final answer = await peer.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });

      await peer.setLocalDescription(answer);

      if (_closing) return;

      WsClient.instance.send({
        'type': 'callAnswer',
        'from': widget.myNick,
        'to': widget.targetNick,
        'sdp': answer.sdp,
      });

      if (mounted) {
        setState(() {
          _accepted = true;
        });
      }
    } catch (e) {
      if (mounted && !_closing) {
        _showError('Arama kabul edilemedi.');
      }
    }
  }

  void _handleEvent(Map<String, dynamic> data) {
    if (!mounted || _closing) return;

    final type = data['type'];
    final from = (data['from'] ?? '').toString();
    final to = (data['to'] ?? '').toString();

    if (from.toLowerCase() != widget.targetNick.toLowerCase()) {
      return;
    }

    if (to.isNotEmpty && to.toLowerCase() != widget.myNick.toLowerCase()) {
      return;
    }

    if (type == 'callAnswer') {
      _handleAnswer(data);
    } else if (type == 'callIce') {
      _handleIceCandidate(data);
    } else if (type == 'callEnded') {
      _finish(sendSignal: false);
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    final sdp = data['sdp']?.toString();
    final peer = _peerConnection;

    if (sdp == null || sdp.isEmpty || peer == null || _closing) {
      return;
    }

    try {
      await peer.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));

      _remoteDescriptionSet = true;
      await _flushPendingIceCandidates();
    } catch (_) {}
  }

  Future<void> _handleIceCandidate(Map<String, dynamic> data) async {
    final candidateText = data['candidate']?.toString();

    if (candidateText == null || candidateText.isEmpty || _closing) {
      return;
    }

    final ice = RTCIceCandidate(
      candidateText,
      data['sdpMid']?.toString(),
      data['sdpMLineIndex'] is int ? data['sdpMLineIndex'] as int : null,
    );

    final peer = _peerConnection;

    if (peer == null || !_remoteDescriptionSet) {
      _pendingIceCandidates.add(ice);
      return;
    }

    try {
      await peer.addCandidate(ice);
    } catch (_) {}
  }

  Future<void> _flushPendingIceCandidates() async {
    final peer = _peerConnection;

    if (peer == null ||
        !_remoteDescriptionSet ||
        _pendingIceCandidates.isEmpty) {
      return;
    }

    final pending = List<RTCIceCandidate>.from(_pendingIceCandidates);

    _pendingIceCandidates.clear();

    for (final candidate in pending) {
      try {
        await peer.addCandidate(candidate);
      } catch (_) {}
    }
  }

  void _toggleMute() {
    final stream = _localStream;
    if (stream == null) return;

    final nextMuted = !_muted;

    for (final track in stream.getAudioTracks()) {
      track.enabled = !nextMuted;
    }

    if (mounted) {
      setState(() {
        _muted = nextMuted;
      });
    }
  }

  Future<void> _toggleSpeaker() async {
    if (_closing) return;

    final next = !_speakerOn;

    try {
      await Helper.setSpeakerphoneOn(next);

      if (!mounted) return;

      setState(() {
        _speakerOn = next;
      });
    } catch (_) {
      if (mounted) {
        _showError('Ses çıkışı değiştirilemedi.');
      }
    }
  }

  void _reject() {
    if (_closing) return;

    WsClient.instance.send({
      'type': 'callEnd',
      'from': widget.myNick,
      'to': widget.targetNick,
    });

    _finish(sendSignal: false);
  }

  Future<void> _finish({bool sendSignal = true}) async {
    if (_closing) return;

    _closing = true;

    if (sendSignal) {
      WsClient.instance.send({
        'type': 'callEnd',
        'from': widget.myNick,
        'to': widget.targetNick,
      });
    }

    final stream = _localStream;
    _localStream = null;

    if (stream != null) {
      for (final track in stream.getTracks()) {
        try {
          track.enabled = false;
        } catch (_) {}

        try {
          await track.stop();
        } catch (_) {}
      }

      try {
        await stream.dispose();
      } catch (_) {}
    }

    final peer = _peerConnection;
    _peerConnection = null;

    if (peer != null) {
      try {
        await peer.close();
      } catch (_) {}

      try {
        await peer.dispose();
      } catch (_) {}
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _showError(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    _subscription.cancel();

    final stream = _localStream;
    _localStream = null;

    if (stream != null) {
      for (final track in stream.getTracks()) {
        try {
          track.stop();
        } catch (_) {}
      }

      try {
        stream.dispose();
      } catch (_) {}
    }

    final peer = _peerConnection;
    _peerConnection = null;

    if (peer != null) {
      try {
        peer.close();
      } catch (_) {}
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waitingIncoming = !widget.outgoing && !_accepted;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _finish();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sesli Arama'),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircleAvatar(
                  radius: 55,
                  child: Icon(Icons.person, size: 60),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.targetNick,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  waitingIncoming
                      ? 'Gelen arama'
                      : _connected
                      ? 'Bağlandı'
                      : 'Bağlanıyor...',
                ),
                const SizedBox(height: 40),
                if (waitingIncoming)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _acceptIncoming,
                        icon: const Icon(Icons.call),
                        label: const Text('Kabul Et'),
                      ),
                      const SizedBox(width: 20),
                      FilledButton.tonalIcon(
                        onPressed: _reject,
                        icon: const Icon(Icons.call_end),
                        label: const Text('Reddet'),
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filled(
                        onPressed: _toggleMute,
                        icon: Icon(_muted ? Icons.mic_off : Icons.mic),
                      ),
                      const SizedBox(width: 18),
                      IconButton.filled(
                        onPressed: _toggleSpeaker,
                        icon: Icon(
                          _speakerOn ? Icons.volume_up : Icons.volume_down,
                        ),
                      ),
                      const SizedBox(width: 18),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        onPressed: _finish,
                        icon: const Icon(Icons.call_end),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// INPUT
// ============================================================

class MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const MessageInput({
    super.key,
    required this.controller,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Mesaj yaz...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: onSend,
              icon: const Icon(Icons.send, color: Colors.greenAccent),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// MODEL
// ============================================================

class ChatMessage {
  final String id;
  final String sender;
  final String text;
  final String clientMessageId;
  final String status;

  const ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    this.clientMessageId = '',
    this.status = 'sending',
  });

  ChatMessage copyWith({
    String? id,
    String? sender,
    String? text,
    String? clientMessageId,
    String? status,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      sender: sender ?? this.sender,
      text: text ?? this.text,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      status: status ?? this.status,
    );
  }
}
