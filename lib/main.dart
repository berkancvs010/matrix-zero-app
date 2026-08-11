import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

enum ZeroLogTheme {
  black,
  matrix,
  whatsapp,
  pink,
  grey,
  midnight,
}

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

  static final ThemeController instance =
      ThemeController._();

  static const _key = 'zerolog_theme';

  ZeroLogTheme current = ZeroLogTheme.matrix;

  Future<void> load() async {
    final prefs =
        await SharedPreferences.getInstance();

    final index =
        prefs.getInt(_key);

    if (index != null &&
        index >= 0 &&
        index < ZeroLogTheme.values.length) {
      current =
          ZeroLogTheme.values[index];
    }
  }

  Future<void> setTheme(
    ZeroLogTheme theme,
  ) async {
    current = theme;

    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setInt(
      _key,
      theme.index,
    );

    notifyListeners();
  }

  ZeroLogThemeData get data =>
      zeroLogThemes[current]!;
}

// ============================================================
// APP
// ============================================================

class MatrixZeroApp extends StatefulWidget {
  const MatrixZeroApp({super.key});

  @override
  State<MatrixZeroApp> createState() =>
      _MatrixZeroAppState();
}

class _MatrixZeroAppState
    extends State<MatrixZeroApp> {
  final ThemeController _theme =
      ThemeController.instance;

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
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final t = _theme.data;

    return MaterialApp(
      title: 'ZeroLog',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness:
            ThemeData.estimateBrightnessForColor(
                  t.background,
                ) ==
                Brightness.dark
            ? Brightness.dark
            : Brightness.light,
        scaffoldBackgroundColor:
            t.background,
        colorScheme:
            ColorScheme.fromSeed(
          seedColor: t.primary,
          brightness:
              ThemeData.estimateBrightnessForColor(
                    t.background,
                  ) ==
                  Brightness.dark
              ? Brightness.dark
              : Brightness.light,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: t.surface,
          foregroundColor: t.text,
        ),
        inputDecorationTheme:
            InputDecorationTheme(
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
  State<WelcomeScreen> createState() =>
      _WelcomeScreenState();
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

  @override
  void initState() {
    super.initState();
    _showNext();
  }

  void _showNext() {
    if (!mounted) return;

    setState(() {
      _lines.add(_sequence[_index]);
      _index++;
    });

    if (_index >= _sequence.length) {
      _timer = Timer(
        const Duration(milliseconds: 900),
        _openLogin,
      );
      return;
    }

    _timer = Timer(
      const Duration(milliseconds: 550),
      _showNext,
    );
  }

  void _openLogin() {
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, animation, secondaryAnimation) =>
            const NicknameScreen(),
        transitionDuration:
            const Duration(milliseconds: 450),
        transitionsBuilder:
            (_, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
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
    final theme =
        ThemeController.instance.data;

    return Scaffold(
      backgroundColor: theme.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              Icon(
                Icons.shield_outlined,
                size: 78,
                color: theme.primary,
              ),
              const SizedBox(height: 30),
              ..._lines.map(
                (line) => Padding(
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 5,
                  ),
                  child: Text(
                    line,
                    style: TextStyle(
                      fontSize:
                          line == 'ZEROLOG'
                              ? 30
                              : 17,
                      fontWeight:
                          line == 'ZEROLOG'
                              ? FontWeight.bold
                              : FontWeight.w500,
                      letterSpacing:
                          line == 'ZEROLOG'
                              ? 5
                              : 3,
                      color: theme.primary,
                      fontFamily:
                          'monospace',
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

  String? nickname;
  String? username;
  String? password;
  bool connected = false;

  bool _manualDisconnect = false;
  bool _connecting = false;
  int _reconnectAttempt = 0;

  final Set<String> _activeRooms = <String>{};

  final List<Map<String, dynamic>> _outgoingQueue =
      <Map<String, dynamic>>[];

  void joinRoom(String room) {
    final id = room.trim();
    if (id.isEmpty) return;

    _activeRooms.add(id);

    if (connected && _channel != null) {
      try {
        _channel!.sink.add(
          jsonEncode({
            'type': 'joinRoom',
            'room': id,
          }),
        );
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
        _channel!.sink.add(
          jsonEncode({
            'type': 'leaveRoom',
            'room': id,
          }),
        );
      } catch (_) {
        _handleConnectionLost();
      }
    }
  }

  void _restoreActiveRooms() {
    if (!connected || _channel == null) return;

    for (final room in _activeRooms) {
      try {
        _channel!.sink.add(
          jsonEncode({
            'type': 'joinRoom',
            'room': room,
          }),
        );
      } catch (_) {
        _handleConnectionLost();
        return;
      }
    }
  }

  Future<bool> connect(
    String username,
    String password,
  ) async {
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

      final channel = WebSocketChannel.connect(
        Uri.parse(wsUrl),
      );

      _channel = channel;

      final authCompleter =
          Completer<bool>();

      _subscription = channel.stream.listen(
        (raw) {
          try {
            final decoded = jsonDecode(
              raw.toString(),
            );

            if (decoded is Map) {
              final data =
                  Map<String, dynamic>.from(
                decoded,
              );

              if (data['type'] ==
                  'authenticated') {
                final authenticatedName =
                    (data['username'] ??
                            username ??
                            '')
                        .toString();

                username =
                    authenticatedName;
                nickname =
                    authenticatedName;
                connected = true;

                if (!authCompleter.isCompleted) {
                  authCompleter.complete(true);
                }
              }

              if (data['type'] ==
                  'authError') {
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

      final authenticated =
          await authCompleter.future.timeout(
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

      _events.add({
        'type': 'connectionRestored',
      });

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

    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) {
        if (!connected || _channel == null) return;

        try {
          _channel!.sink.add(
            jsonEncode({
              'type': 'listRooms',
            }),
          );
        } catch (_) {
          _handleConnectionLost();
        }
      },
    );
  }

  void _handleConnectionLost() {
    if (_manualDisconnect) return;

    final wasConnected = connected;
    connected = false;
    _heartbeatTimer?.cancel();

    if (wasConnected) {
      _events.add({
        'type': 'connectionLost',
      });
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
            : 8;

    _events.add({
      'type': 'reconnecting',
      'seconds': seconds,
    });

    _reconnectTimer = Timer(
      Duration(seconds: seconds),
      () {
        _connectInternal();
      },
    );
  }

  void send(Map<String, dynamic> data) {
    if (!connected || _channel == null) {
      _outgoingQueue.add(
        Map<String, dynamic>.from(data),
      );
      return;
    }

    try {
      _channel!.sink.add(
        jsonEncode(data),
      );
    } catch (_) {
      _outgoingQueue.add(
        Map<String, dynamic>.from(data),
      );
      _handleConnectionLost();
    }
  }

  void _flushOutgoingQueue() {
    if (!connected || _channel == null || _outgoingQueue.isEmpty) {
      return;
    }

    final pending =
        List<Map<String, dynamic>>.from(_outgoingQueue);

    _outgoingQueue.clear();

    for (final data in pending) {
      try {
        _channel!.sink.add(
          jsonEncode(data),
        );
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

// ============================================================
// NICKNAME
// ============================================================

class NicknameScreen extends StatefulWidget {
  const NicknameScreen({super.key});

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
  final TextEditingController _usernameController =
      TextEditingController();

  final TextEditingController _passwordController =
      TextEditingController();

  bool _loading = false;
  bool _registerMode = false;
  bool _obscurePassword = true;

  Future<void> _submit() async {
    final username =
        _usernameController.text.trim();
    final password =
        _passwordController.text;

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
      await _register(
        username,
        password,
      );
    } else {
      await _login(
        username,
        password,
      );
    }
  }

  Future<void> _register(
    String username,
    String password,
  ) async {
    try {
      final channel =
          WebSocketChannel.connect(
        Uri.parse(wsUrl),
      );

      final subscription =
          channel.stream.listen(
        (raw) {
          try {
            final decoded =
                jsonDecode(raw.toString());

            if (decoded is! Map) return;

            final data =
                Map<String, dynamic>.from(
              decoded,
            );

            if (!mounted) return;

            if (data['type'] ==
                'accountRegistered') {
              channel.sink.close();
              setState(() {
                _loading = false;
                _registerMode = false;
              });

              _show(
                'Hesap oluşturuldu. Şimdi giriş yapabilirsiniz.',
              );
            }

            if (data['type'] ==
                'authError') {
              channel.sink.close();

              setState(() {
                _loading = false;
              });

              _show(
                (data['message'] ??
                        'Kayıt başarısız.')
                    .toString(),
              );
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

      Future.delayed(
        const Duration(seconds: 10),
        () {
          subscription.cancel();
        },
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      _show('Sunucuya bağlanılamadı.');
    }
  }

  Future<void> _login(
    String username,
    String password,
  ) async {
    setState(() {
      _loading = true;
    });

    final ok =
        await WsClient.instance.connect(
      username,
      password,
    );

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

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MainScreen(
          nickname:
              WsClient.instance.nickname ??
                  username,
        ),
      ),
    );
  }

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ZERO LOG'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(
              maxWidth: 480,
            ),
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 72,
                  color: ThemeController.instance.data.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'ZeroLog',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: ThemeController.instance.data.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _registerMode
                      ? 'Yeni hesabını oluştur'
                      : 'Gizli iletişim alanına giriş yap',
                  textAlign:
                      TextAlign.center,
                ),
                const SizedBox(height: 28),
                TextField(
                  controller:
                      _usernameController,
                  enabled: !_loading,
                  textInputAction:
                      TextInputAction.next,
                  autocorrect: false,
                  decoration:
                      const InputDecoration(
                    labelText:
                        'Kullanıcı adı',
                    prefixIcon:
                        Icon(Icons.person_outline),
                    border:
                        OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller:
                      _passwordController,
                  enabled: !_loading,
                  obscureText:
                      _obscurePassword,
                  onSubmitted:
                      (_) => _submit(),
                  decoration:
                      InputDecoration(
                    labelText: 'Şifre',
                    prefixIcon:
                        const Icon(
                      Icons.lock_outline,
                    ),
                    suffixIcon:
                        IconButton(
                      onPressed: () {
                        setState(() {
                          _obscurePassword =
                              !_obscurePassword;
                        });
                      },
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                    ),
                    border:
                        const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed:
                        _loading
                            ? null
                            : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            _registerMode
                                ? 'HESAP OLUŞTUR'
                                : 'GİRİŞ YAP',
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () {
                          setState(() {
                            _registerMode =
                                !_registerMode;
                          });
                        },
                  child: Text(
                    _registerMode
                        ? 'Zaten hesabım var'
                        : 'Yeni hesap oluştur',
                  ),
                ),
                const SizedBox(height: 30),
                const Text(
                  'ZeroLog • Gizlilik odaklı iletişim',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                  ),
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
// MAIN
// ============================================================

class MainScreen extends StatefulWidget {
  final String nickname;

  const MainScreen({
    super.key,
    required this.nickname,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late final StreamSubscription<Map<String, dynamic>>
      _subscription;

  final List<String> _onlineUsers = [];

  bool _connected = false;
  bool _reconnecting = false;

  @override
  void initState() {
    super.initState();

    _connected = WsClient.instance.connected;

    _subscription =
        WsClient.instance.events.listen(_handleEvent);

  }

  void _handleEvent(Map<String, dynamic> data) {
    if (!mounted) return;

    final type = data['type'];

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
            .where(
              (e) =>
                  e.toLowerCase() !=
                  widget.nickname.toLowerCase(),
            )
            .toSet()
            .toList();

        setState(() {
          _onlineUsers
            ..clear()
            ..addAll(users);
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

    if (type == 'connectionRestored' ||
        type == 'registered') {
      setState(() {
        _connected = true;
        _reconnecting = false;
      });
    }

    if (type == 'callOffer') {
      final from = (data['from'] ?? '').toString();
      final to = (data['to'] ?? '').toString();

      if (from.isEmpty || to.isEmpty) return;

      if (to.toLowerCase() !=
          widget.nickname.toLowerCase()) {
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
        builder: (_) => ChatRoomScreen(
          nickname: widget.nickname,
          roomName: room,
        ),
      ),
    );
  }

  void _openPrivate(String target) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrivateChatScreen(
          myNick: widget.nickname,
          targetNick: target,
        ),
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

  Future<void> _selectTheme(
    ZeroLogTheme theme,
  ) async {
    await ThemeController.instance.setTheme(theme);
  }

  @override
  void dispose() {
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
                        Expanded(
                          child: Text(data.name),
                        ),
                        if (ThemeController.instance.current ==
                            theme)
                          const Icon(
                            Icons.check,
                            size: 18,
                          ),
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
              Tab(
                icon: Icon(Icons.forum_outlined),
                text: 'Odalar',
              ),
              Tab(
                icon: Icon(Icons.people_outline),
                text: 'Online',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView.builder(
              padding: const EdgeInsets.symmetric(
                vertical: 10,
              ),
              itemCount: rooms.length,
              itemBuilder: (_, index) {
                final room = rooms[index];

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text('${index + 1}'),
                    ),
                    title: Text(room),
                    subtitle:
                        const Text('Sohbet odası'),
                    trailing:
                        const Icon(Icons.chevron_right),
                    onTap: () => _openRoom(room),
                  ),
                );
              },
            ),
            _onlineUsers.isEmpty
                ? const Center(
                    child: Text(
                      'Şu anda çevrimiçi kullanıcı görünmüyor.',
                    ),
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(
                      vertical: 10,
                    ),
                    itemCount: _onlineUsers.length,
                    itemBuilder: (_, index) {
                      final user =
                          _onlineUsers[index];

                      return Card(
                        margin:
                            const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        child: ListTile(
                          leading:
                              const Icon(
                            Icons.circle,
                            color:
                                Colors.greenAccent,
                            size: 13,
                          ),
                          title: Text(user),
                          trailing: Row(
                            mainAxisSize:
                                MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Mesaj',
                                icon: const Icon(
                                  Icons.chat_outlined,
                                ),
                                onPressed: () =>
                                    _openPrivate(user),
                              ),
                              IconButton(
                                tooltip: 'Sesli ara',
                                icon: const Icon(
                                  Icons.call,
                                  color:
                                      Colors.greenAccent,
                                ),
                                onPressed: () =>
                                    _call(user),
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
  State<ChatRoomScreen> createState() =>
      _ChatRoomScreenState();
}

class _ChatRoomScreenState
    extends State<ChatRoomScreen> {
  final TextEditingController _controller =
      TextEditingController();

  final ScrollController _scrollController =
      ScrollController();

  final List<ChatMessage> _messages = [];

  late final StreamSubscription<
      Map<String, dynamic>> _subscription;

  @override
  void initState() {
    super.initState();

    _subscription =
        WsClient.instance.events.listen(_handleEvent);

    WsClient.instance.joinRoom(widget.roomName);
  }

  void _handleEvent(Map<String, dynamic> data) {
    if (!mounted) return;

    if (data['type'] == 'roomHistory' &&
        data['room'] == widget.roomName) {
      final history = data['messages'];

      if (history is List) {
        for (final item in history) {
          if (item is Map) {
            final map =
                Map<String, dynamic>.from(item);

            _addMessage(
              ChatMessage(
                id: (map['id'] ??
                        'legacy-${widget.roomName}-${map['ts'] ?? ''}-${map['from'] ?? map['sender'] ?? ''}-${map['text'] ?? ''}')
                    .toString(),
                sender:
                    (map['sender'] ??
                            map['from'] ??
                            '')
                        .toString(),
                text:
                    (map['text'] ?? '')
                        .toString(),
              ),
            );
          }
        }
      }
    }

    if (data['type'] == 'roomMessage' &&
        data['room'] == widget.roomName) {
      _addMessage(
        ChatMessage(
          id: (data['id'] ??
                  'live-${data['ts'] ?? ''}-${data['from'] ?? data['sender'] ?? ''}-${data['text'] ?? ''}')
              .toString(),
          sender:
              (data['sender'] ??
                      data['from'] ??
                      '')
                  .toString(),
          text:
              (data['text'] ?? '').toString(),
        ),
      );
    }
  }

  void _addMessage(ChatMessage message) {
    if (message.text.isEmpty) return;

    final exists = _messages.any(
      (m) => m.id == message.id,
    );

    if (exists) return;

    setState(() {
      _messages.add(message);
    });

    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position
                .maxScrollExtent,
            duration:
                const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      },
    );
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
      appBar: AppBar(
        title: Text(widget.roomName),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(10),
              itemCount: _messages.length,
              itemBuilder: (_, index) {
                final message =
                    _messages[index];

                final mine =
                    message.sender.toLowerCase() ==
                        widget.nickname.toLowerCase();

                return Align(
                  alignment: mine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints:
                        const BoxConstraints(
                      maxWidth: 500,
                    ),
                    margin:
                        const EdgeInsets.symmetric(
                      vertical: 4,
                    ),
                    padding:
                        const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: mine
                          ? ThemeController.instance
                              .data
                              .bubbleMine
                          : ThemeController.instance
                              .data
                              .bubbleOther,
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        if (!mine)
                          Text(
                            message.sender,
                            style:
                                const TextStyle(
                              fontSize: 11,
                              color:
                                  Colors.greenAccent,
                            ),
                          ),
                        if (!mine)
                          const SizedBox(height: 3),
                        Text(message.text),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          MessageInput(
            controller: _controller,
            onSend: _send,
          ),
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
  State<PrivateChatScreen> createState() =>
      _PrivateChatScreenState();
}

class _PrivateChatScreenState
    extends State<PrivateChatScreen> {
  final TextEditingController _controller =
      TextEditingController();

  final ScrollController _scrollController =
      ScrollController();

  final List<ChatMessage> _messages = [];

  late final StreamSubscription<
      Map<String, dynamic>> _subscription;

  @override
  void initState() {
    super.initState();

    _subscription =
        WsClient.instance.events.listen(_handleEvent);

    WsClient.instance.send({
      'type': 'privateHistory',
      'peer': widget.targetNick,
    });
  }

  void _handleEvent(Map<String, dynamic> data) {
    if (!mounted) return;

    if (data['type'] == 'privateHistory') {
      final peer =
          (data['peer'] ??
                  data['with'] ??
                  data['target'] ??
                  '')
              .toString();

      if (peer.isNotEmpty &&
          peer.toLowerCase() !=
              widget.targetNick.toLowerCase()) {
        return;
      }

      final list = data['messages'];

      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            final map =
                Map<String, dynamic>.from(item);

            _addMessage(
              ChatMessage(
                id: (map['id'] ??
                        'private-legacy-${map['ts'] ?? ''}-${map['from'] ?? map['sender'] ?? ''}-${map['to'] ?? ''}-${map['text'] ?? ''}')
                    .toString(),
                sender:
                    (map['sender'] ??
                            map['from'] ??
                            '')
                        .toString(),
                text:
                    (map['text'] ?? '')
                        .toString(),
              ),
            );
          }
        }
      }
    }

    if (data['type'] == 'privateMessage') {
      final sender =
          (data['sender'] ??
                  data['from'] ??
                  '')
              .toString();

      final target =
          (data['to'] ??
                  data['target'] ??
                  '')
              .toString();

      final isFromPeer =
          sender.toLowerCase() ==
              widget.targetNick.toLowerCase();

      final isFromMe =
          sender.toLowerCase() ==
              widget.myNick.toLowerCase();

      final validPeerTarget =
          target.isEmpty ||
          target.toLowerCase() ==
              widget.myNick.toLowerCase();

      final validSelfTarget =
          target.isEmpty ||
          target.toLowerCase() ==
              widget.targetNick.toLowerCase();

      final validTarget =
          isFromMe
              ? validSelfTarget
              : validPeerTarget;

      if ((!isFromPeer && !isFromMe) || !validTarget) {
        return;
      }

      _addMessage(
        ChatMessage(
          id: (data['id'] ??
                  'private-live-${data['ts'] ?? ''}-$sender-$target-${data['text'] ?? ''}')
              .toString(),
          sender: sender,
          text:
              (data['text'] ?? '').toString(),
        ),
      );
    }
  }

  void _addMessage(ChatMessage message) {
    if (message.text.isEmpty) return;

    final exists = _messages.any(
      (m) => m.id == message.id,
    );

    if (exists) return;

    setState(() {
      _messages.add(message);
    });

    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position
                .maxScrollExtent,
            duration:
                const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      },
    );
  }

  void _send() {
    final text = _controller.text.trim();

    if (text.isEmpty) return;

    WsClient.instance.send({
      'type': 'privateMessage',
      'to': widget.targetNick,
      'text': text,
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
      appBar: AppBar(
        title: Text(widget.targetNick),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(10),
              itemCount: _messages.length,
              itemBuilder: (_, index) {
                final message =
                    _messages[index];

                final mine =
                    message.sender.toLowerCase() ==
                        widget.myNick.toLowerCase();

                return Align(
                  alignment: mine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints:
                        const BoxConstraints(
                      maxWidth: 500,
                    ),
                    margin:
                        const EdgeInsets.symmetric(
                      vertical: 4,
                    ),
                    padding:
                        const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: mine
                          ? ThemeController.instance
                              .data
                              .bubbleMine
                          : ThemeController.instance
                              .data
                              .bubbleOther,
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                    child: Text(message.text),
                  ),
                );
              },
            ),
          ),
          MessageInput(
            controller: _controller,
            onSend: _send,
          ),
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
  final RTCVideoRenderer _remoteRenderer =
      RTCVideoRenderer();
  late final Future<void> _remoteRendererReady;

  late final StreamSubscription<
      Map<String, dynamic>> _subscription;
  StreamSubscription<int>? _proximitySubscription;

  bool _accepted = false;
  bool _connected = false;
  bool _muted = false;
  bool _speakerOn = false;
  bool _closing = false;

  final List<RTCIceCandidate> _pendingIceCandidates = [];
  bool _remoteDescriptionSet = false;

  @override
  void initState() {
    super.initState();

    _remoteRendererReady =
        _remoteRenderer.initialize();

    _subscription =
        WsClient.instance.events.listen(_handleEvent);

    _initProximitySensor();

    if (widget.outgoing) {
      _startOutgoingCall();
    }
  }

  Future<void> _initProximitySensor() async {
    try {
      final available =
          await ProximitySensor.isProximitySensorAvailable();

      if (!available || !mounted || _closing) {
        return;
      }

      await ProximitySensor.setProximityScreenOff(true);

      _proximitySubscription =
          ProximitySensor.events.listen((event) {});
    } catch (_) {}
  }

  Future<void> _createPeerConnection() async {
    if (_peerConnection != null) return;

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

    _peerConnection =
        await createPeerConnection(configuration);

    _peerConnection!.onIceCandidate =
        (RTCIceCandidate candidate) {
      if (candidate.candidate == null) return;

      WsClient.instance.send({
        'type': 'callIce',
        'from': widget.myNick,
        'to': widget.targetNick,
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    // Karşı taraftan gelen ses track'ini kabul et.
    _peerConnection!.onTrack =
        (RTCTrackEvent event) async {
      if (event.track.kind != 'audio') {
        return;
      }

      event.track.enabled = true;

      if (event.streams.isNotEmpty) {
        try {
          await _remoteRendererReady;
          await _remoteRenderer.setSrcObject(
            stream: event.streams.first,
          );
          await _remoteRenderer.setVolume(1.0);
        } catch (_) {}
      }
    };

    _peerConnection!.onIceConnectionState =
        (RTCIceConnectionState state) {};

    _peerConnection!.onConnectionState =
        (RTCPeerConnectionState state) {
      if (!mounted) return;

      if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() {
          _connected = true;
        });
      }

      if (state ==
              RTCPeerConnectionState
                  .RTCPeerConnectionStateFailed ||
          state ==
              RTCPeerConnectionState
                  .RTCPeerConnectionStateDisconnected ||
          state ==
              RTCPeerConnectionState
                  .RTCPeerConnectionStateClosed) {
        setState(() {
          _connected = false;
        });
      }
    };

    _localStream =
        await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });

    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(
        track,
        _localStream!,
      );
    }
  }

  Future<void> _startOutgoingCall() async {
    try {
      await _createPeerConnection();

      final offer =
          await _peerConnection!.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });

      await _peerConnection!.setLocalDescription(
        offer,
      );

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
    } catch (_) {
      if (mounted) {
        _showError('Arama başlatılamadı.');
      }
    }
  }

  Future<void> _acceptIncoming() async {
    if (widget.incomingOffer == null) {
      return;
    }

    try {
      await _createPeerConnection();

      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(
          widget.incomingOffer!,
          'offer',
        ),
      );

      final answer =
          await _peerConnection!.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });

      await _peerConnection!.setLocalDescription(
        answer,
      );

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
    } catch (_) {
      if (mounted) {
        _showError('Arama kabul edilemedi.');
      }
    }
  }

  void _handleEvent(Map<String, dynamic> data) {
    if (!mounted) return;

    final type = data['type'];
    final from = (data['from'] ?? '').toString();
    final to = (data['to'] ?? '').toString();

    if (from.toLowerCase() !=
            widget.targetNick.toLowerCase() &&
        type != 'answer') {
      return;
    }

    if (to.isNotEmpty &&
        to.toLowerCase() !=
            widget.myNick.toLowerCase()) {
      return;
    }

    if (type == 'callAnswer') {
      _handleAnswer(data);
    }

    if (type == 'callIce') {
      _handleIceCandidate(data);
    }

    if (type == 'callEnded') {
      _finish(sendSignal: false);
    }
  }

  Future<void> _handleAnswer(
      Map<String, dynamic> data) async {
    final sdp = data['sdp']?.toString();

    if (sdp == null || _peerConnection == null) {
      return;
    }

    try {
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(
          sdp,
          'answer',
        ),
      );

      _remoteDescriptionSet = true;
      await _flushPendingIceCandidates();
    } catch (_) {}
  }

  Future<void> _handleIceCandidate(
      Map<String, dynamic> data) async {
    if (_peerConnection == null) return;

    final candidate =
        data['candidate']?.toString();

    if (candidate == null ||
        candidate.isEmpty) {
      return;
    }

    final ice = RTCIceCandidate(
      candidate,
      data['sdpMid']?.toString(),
      data['sdpMLineIndex'] is int
          ? data['sdpMLineIndex'] as int
          : null,
    );

    if (!_remoteDescriptionSet) {
      _pendingIceCandidates.add(ice);
      return;
    }

    try {
      await _peerConnection!.addCandidate(ice);
    } catch (_) {}
  }

  Future<void> _flushPendingIceCandidates() async {
    if (_peerConnection == null ||
        !_remoteDescriptionSet ||
        _pendingIceCandidates.isEmpty) {
      return;
    }

    final pending =
        List<RTCIceCandidate>.from(_pendingIceCandidates);

    _pendingIceCandidates.clear();

    for (final candidate in pending) {
      try {
        await _peerConnection!.addCandidate(candidate);
      } catch (_) {}
    }
  }

  void _toggleMute() {
    final stream = _localStream;

    if (stream == null) return;

    final tracks = stream.getAudioTracks();

    for (final track in tracks) {
      track.enabled = !track.enabled;
    }

    setState(() {
      _muted = !_muted;
    });
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerOn;

    try {
      await Helper.setSpeakerphoneOn(next);

      if (!mounted) return;

      setState(() {
        _speakerOn = next;
      });
    } catch (_) {
      _showError('Ses çıkışı değiştirilemedi.');
    }
  }

  void _reject() {
    WsClient.instance.send({
      'type': 'callEnd',
      'from': widget.myNick,
      'to': widget.targetNick,
    });

    _finish(sendSignal: false);
  }

  Future<void> _finish({
    bool sendSignal = true,
  }) async {
    if (_closing) return;

    _closing = true;

    try {
      await _proximitySubscription?.cancel();
    } catch (_) {}

    _proximitySubscription = null;

    try {
      await ProximitySensor.setProximityScreenOff(false);
    } catch (_) {}

    if (sendSignal) {
      WsClient.instance.send({
        'type': 'callEnd',
        'from': widget.myNick,
        'to': widget.targetNick,
      });
    }

    // Mikrofonu fiziksel olarak durdur.
    final stream = _localStream;

    if (stream != null) {
      // Önce peer connection üzerindeki sender track'lerini ayır.
      try {
        final senders =
            await _peerConnection?.getSenders() ??
                <RTCRtpSender>[];

        for (final sender in senders) {
          try {
            await sender.replaceTrack(null);
          } catch (_) {}
        }
      } catch (_) {}

      // Ardından mikrofon track'ini gerçekten durdur ve dispose et.
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

    try {
      await _peerConnection?.close();
    } catch (_) {}

    try {
      await _peerConnection?.dispose();
    } catch (_) {}

    try {
      await _remoteRenderer.setSrcObject(
        stream: null,
      );
    } catch (_) {}

    try {
      await _remoteRenderer.dispose();
    } catch (_) {}

    _localStream = null;
    _peerConnection = null;

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _showError(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  void dispose() {
    _subscription.cancel();

    _proximitySubscription?.cancel();
    _proximitySubscription = null;

    ProximitySensor.setProximityScreenOff(false);

    if (!_closing) {
      final stream = _localStream;

      if (stream != null) {
        for (final track in stream.getTracks()) {
          try {
            track.enabled = false;
            track.stop();
          } catch (_) {}
        }

        try {
          stream.dispose();
        } catch (_) {}
      }

      try {
        _peerConnection?.close();
      } catch (_) {}
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waitingIncoming =
        !widget.outgoing && !_accepted;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult:
          (didPop, result) {
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
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                const CircleAvatar(
                  radius: 55,
                  child: Icon(
                    Icons.person,
                    size: 60,
                  ),
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
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed:
                            _acceptIncoming,
                        icon: const Icon(
                          Icons.call,
                        ),
                        label:
                            const Text('Kabul Et'),
                      ),
                      const SizedBox(width: 20),
                      FilledButton.tonalIcon(
                        onPressed: _reject,
                        icon: const Icon(
                          Icons.call_end,
                        ),
                        label:
                            const Text('Reddet'),
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      IconButton.filled(
                        onPressed: _toggleMute,
                        icon: Icon(
                          _muted
                              ? Icons.mic_off
                              : Icons.mic,
                        ),
                      ),
                      const SizedBox(width: 18),
                      IconButton.filled(
                        onPressed: _toggleSpeaker,
                        icon: Icon(
                          _speakerOn
                              ? Icons.volume_up
                              : Icons.volume_down,
                        ),
                      ),
                      const SizedBox(width: 18),
                      IconButton.filled(
                        style:
                            IconButton.styleFrom(
                          backgroundColor:
                              Colors.red,
                        ),
                        onPressed: _finish,
                        icon: const Icon(
                          Icons.call_end,
                        ),
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
        padding:
            const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction:
                    TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration:
                    const InputDecoration(
                  hintText: 'Mesaj yaz...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: onSend,
              icon: const Icon(
                Icons.send,
                color: Colors.greenAccent,
              ),
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

  const ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
  });
}
