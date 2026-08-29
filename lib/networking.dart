part of 'main.dart';

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

  void emitExternalEvent(Map<String, dynamic> data) {
    _events.add(Map<String, dynamic>.from(data));
  }

  final Set<String> _onlineUsers = <String>{};
  final Set<String> _knownUsers = <String>{};

  final Map<String, Map<String, dynamic>> _userProfiles =
      <String, Map<String, dynamic>>{};

  List<String> get onlineUsers => List.unmodifiable(_onlineUsers);
  List<String> get knownUsers => List.unmodifiable(_knownUsers);
  Map<String, Map<String, dynamic>> get userProfiles =>
      Map.unmodifiable(_userProfiles);

  Map<String, dynamic>? profileFor(String username) {
    final normalized = username.trim().toLowerCase();

    if (normalized.isEmpty) return null;

    for (final entry in _userProfiles.entries) {
      if (entry.key.trim().toLowerCase() == normalized) {
        return Map<String, dynamic>.from(entry.value);
      }
    }

    return null;
  }

  void cacheProfile(String username, Map<String, dynamic> profile) {
    final name = username.trim();

    if (name.isEmpty) return;

    // Kullanıcı adı büyük/küçük harf farkıyla tekrar cache'e girerse
    // eski kaydın kalıp yeni profil güncellemesini gölgelemesine izin verme.
    final staleKeys = _userProfiles.keys
        .where((key) => key.trim().toLowerCase() == name.toLowerCase())
        .toList(growable: false);

    for (final key in staleKeys) {
      if (key != name) {
        _userProfiles.remove(key);
      }
    }

    _userProfiles[name] = Map<String, dynamic>.from(profile);
    _events.add({'type': 'profileCacheUpdated', 'username': name, ...profile});
  }

  void clearProfileCache() {
    _userProfiles.clear();
  }

  String? nickname;
  String? username;
  String? password;
  bool connected = false;
  bool _appForeground = true;

  bool get appIsForeground => _appForeground;

  String? turnUsername;
  String? turnPassword;
  List<String> turnUrls = const [];

  final Completer<void> turnCredentialsReady = Completer<void>();

  // Aktif özel sohbet. Bildirim/mesaj akışının aynı sohbet ekranıyla
  // yarışmasını önlemek için merkezi olarak tutulur.
  String? _activePrivateChatPeer;

  String? get activePrivateChatPeer => _activePrivateChatPeer;

  void setActivePrivateChat(String? peer) {
    final value = peer?.trim();

    if (value == null || value.isEmpty) {
      _activePrivateChatPeer = null;
      return;
    }

    _activePrivateChatPeer = value;
  }

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

  void updateAppState(String state) {
    final normalized = state.trim().toLowerCase();

    if (normalized != 'foreground' && normalized != 'background') {
      return;
    }

    _appForeground = normalized == 'foreground';
    _events.add({'type': 'appStateChanged', 'state': normalized});

    if (!connected || _channel == null) return;

    try {
      _channel!.sink.add(jsonEncode({'type': 'appState', 'state': normalized}));

      debugPrint('[PRESENCE] appState=$normalized sent');
    } catch (_) {
      _handleConnectionLost();
    }
  }

  void requestPresence() {
    if (!connected || _channel == null) return;

    try {
      _channel!.sink.add(jsonEncode({'type': 'getPresence'}));
    } catch (_) {
      _handleConnectionLost();
    }
  }

  void requestUserDirectory() {
    if (!connected || _channel == null) return;

    try {
      _channel!.sink.add(jsonEncode({'type': 'getUserDirectory'}));
    } catch (_) {
      _handleConnectionLost();
    }
  }

  void requestProfile(String username) {
    final name = username.trim();

    if (name.isEmpty || !connected || _channel == null) return;

    try {
      _channel!.sink.add(jsonEncode({'type': 'getProfile', 'username': name}));
    } catch (_) {
      _handleConnectionLost();
    }
  }

  void requestPrivacySettings() {
    send({'type': 'getPrivacySettings'});
  }

  void requestNotificationSettings() {
    send({'type': 'getNotificationSettings'});
  }

  void setPrivacySettings({
    bool? presenceVisible,
    bool? privateMessagesEnabled,
  }) {
    final data = <String, dynamic>{'type': 'setPrivacySettings'};

    if (presenceVisible != null) {
      data['presenceVisible'] = presenceVisible;
    }

    if (privateMessagesEnabled != null) {
      data['privateMessagesEnabled'] = privateMessagesEnabled;
    }

    send(data);
  }

  void setNotificationSettings({
    bool? messageNotificationsEnabled,
    bool? callNotificationsEnabled,
    bool? autoAcceptFileTransfers,
  }) {
    final data = <String, dynamic>{'type': 'setNotificationSettings'};

    if (messageNotificationsEnabled != null) {
      data['messageNotificationsEnabled'] = messageNotificationsEnabled;
    }

    if (callNotificationsEnabled != null) {
      data['callNotificationsEnabled'] = callNotificationsEnabled;
    }

    if (autoAcceptFileTransfers != null) {
      data['autoAcceptFileTransfers'] = autoAcceptFileTransfers;
    }

    send(data);
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

  void updateFcmToken(String token) {
    final clean = token.trim();

    if (clean.isEmpty) return;

    send({'type': 'fcmToken', 'token': clean});
  }

  Future<bool> connect(String username, String password) async {
    _manualDisconnect = false;
    this.username = username.trim();
    this.password = password;
    nickname = this.username;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();

    // Login sırasında token yoksa FCM'den doğrudan tekrar al.
    // Böylece başlangıçtaki token alma zamanlamasına bağlı kalmayız.
    if (ZeroLogPushService.currentToken == null ||
        ZeroLogPushService.currentToken!.trim().isEmpty) {
      try {
        final token = await FirebaseMessaging.instance.getToken();

        if (token != null && token.trim().isNotEmpty) {
          ZeroLogPushService.setCurrentToken(token.trim());
          debugPrint(
            '[FCM] login-time token acquired length=${token.trim().length}',
          );
        } else {
          debugPrint('[FCM] login-time token is empty');
        }
      } catch (e) {
        debugPrint('[FCM] login-time getToken failed: $e');
      }
    }

    return _connectInternal();
  }

  Future<bool> _connectInternal() async {
    if (_manualDisconnect ||
        _connecting ||
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

              if (data['type'] == 'turnCredentials') {
                turnUsername = (data['username'] ?? '').toString().trim();
                turnPassword = (data['credential'] ?? '').toString();

                final rawUrls = data['urls'];

                if (rawUrls is List) {
                  turnUrls = rawUrls
                      .map((e) => e.toString().trim())
                      .where((e) => e.isNotEmpty)
                      .toList();
                }

                if (!turnCredentialsReady.isCompleted &&
                    turnUsername != null &&
                    turnUsername!.isNotEmpty &&
                    turnPassword != null &&
                    turnPassword!.isNotEmpty &&
                    turnUrls.isNotEmpty) {
                  turnCredentialsReady.complete();
                }
              }

              if (data['type'] == 'authenticated') {
                final authenticatedName = (data['username'] ?? username ?? '')
                    .toString();

                username = authenticatedName;
                nickname = authenticatedName;
                connected = true;

                // Yeni WebSocket bağlantısı varsayılan olarak foreground
                // kabul edilir. MainScreen lifecycle bilgisi hazır olduğunda
                // gerçek durumu tekrar gönderir.
                try {
                  _channel?.sink.add(
                    jsonEncode({'type': 'appState', 'state': _appForeground ? 'foreground' : 'background'}),
                  );
                } catch (_) {}

                final latestFcmToken = ZeroLogPushService.currentToken;

                if (latestFcmToken != null &&
                    latestFcmToken.trim().isNotEmpty) {
                  updateFcmToken(latestFcmToken);
                }

                if (!authCompleter.isCompleted) {
                  authCompleter.complete(true);
                }
              }

              if (data['type'] == 'userDirectory') {
                final raw = data['users'];

                if (raw is List) {
                  _knownUsers
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

                final profiles = data['profiles'];

                if (profiles is Map) {
                  for (final entry in profiles.entries) {
                    if (entry.value is Map) {
                      cacheProfile(
                        entry.key.toString(),
                        Map<String, dynamic>.from(entry.value as Map),
                      );
                    }
                  }
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

                final profiles = data['profiles'];

                if (profiles is Map) {
                  for (final entry in profiles.entries) {
                    if (entry.value is Map) {
                      cacheProfile(
                        entry.key.toString(),
                        Map<String, dynamic>.from(entry.value as Map),
                      );
                    }
                  }
                }
              }

              if (data['type'] == 'profileUpdated') {
                final name = (data['username'] ?? '').toString().trim();

                if (name.isNotEmpty) {
                  final profile = <String, dynamic>{
                    'type': (data['profileType'] ?? 'avatar').toString(),
                    'avatarId': data['avatarId'],
                    'about': (data['about'] ?? '').toString(),
                    'photoAvailable': data['photoAvailable'] == true,
                    'photoData': (data['photoData'] ?? '').toString(),
                  };

                  cacheProfile(name, profile);

                  if (profile['photoAvailable'] == true &&
                      (profile['photoData'] as String).isEmpty) {
                    requestProfile(name);
                  }
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

      await channel.ready.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('WebSocket bağlantı zaman aşımı'),
      );

      channel.sink.add(
        jsonEncode({
          'type': 'login',
          'username': username,
          'password': password,
          'fcmToken': ZeroLogPushService.currentToken,
        }),
      );

      final authenticated = await authCompleter.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => false,
      );

      if (!authenticated) {
        connected = false;
        await _closeCurrent();

        // Auth timeout/gecikmesi bağlantıyı tamamen kilitlemesin.
        // Bekleyen mesajlar queue'da korunur ve sonraki bağlantıda gönderilir.
        _scheduleReconnect();

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
      await _closeCurrent();
      return false;
    } finally {
      _connecting = false;
      if (!_manualDisconnect && !connected) {
        _scheduleReconnect();
      }
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!connected || _channel == null) return;

      try {
        _channel!.sink.add(
          jsonEncode({
            'type': 'appHeartbeat',
            'state': _appForeground ? 'foreground' : 'background',
          }),
        );
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

  bool _shouldQueueWhileDisconnected(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString();

    // Bunlar bağlantı koptuğunda sonradan gönderilmemeli.
    // Eski read/delivery/presence olaylarının reconnect sonrası
    // yeni mesaj durumlarını ezmesini önler.
    const transientTypes = <String>{
      'messageRead',
      'messageDelivered',
      'getPresence',
      'getUserDirectory',
      'getPrivacySettings',
      'getNotificationSettings',

      // Call signaling is real-time state. Never resurrect a stale
      // call after a reconnect.
      'callInvite',
      'callAccept',
      'callReject',
      'callTimeout',
      'callOffer',
      'callAnswer',
      'callIce',
      'callEnd',
    };

    return !transientTypes.contains(type);
  }

  void send(Map<String, dynamic> data) {
    final payload = Map<String, dynamic>.from(data);

    if (!connected || _channel == null) {
      if (_shouldQueueWhileDisconnected(payload)) {
        _outgoingQueue.add(payload);
      }
      return;
    }

    try {
      _channel!.sink.add(jsonEncode(payload));
    } catch (_) {
      if (_shouldQueueWhileDisconnected(payload)) {
        _outgoingQueue.add(payload);
      }
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

  const _ZeroLogWavePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;

    for (var i = 0; i < 20; i++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = const Color(
          0xFF39FF88,
        ).withValues(alpha: 0.08 + ((1 - (i / 20)) * 0.10));

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
