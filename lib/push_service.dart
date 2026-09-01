part of 'main.dart';

class ZeroLogPushService {
  ZeroLogPushService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const String callChannelId = 'zerolog_calls_v9';
  static const String messageChannelId = 'zerolog_messages_v5';
  static const String fileChannelId = 'zerolog_files_v1';
  static const int callNotificationId = 9001;
  static const int messageNotificationId = 9002;
  static const String pendingCallKey = 'zerolog.pending_call';
  static const String pendingNotificationKey = 'zerolog.pending_notification';

  static String? _currentToken;
  static bool _notificationsInitialized = false;

  static Future<void> Function(Map<String, dynamic>)? _incomingCallHandler;

  static String? get currentToken => _currentToken;

  static void setIncomingCallHandler(
    Future<void> Function(Map<String, dynamic>)? handler,
  ) {
    _incomingCallHandler = handler;
  }

  static Future<void> storeNotificationPayload(String payload) async {
    if (payload.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(payload);

      if (decoded is! Map) return;

      final type = decoded['type']?.toString();
      final prefs = await SharedPreferences.getInstance();

      if (type == 'callInvite') {
        await prefs.setString(pendingCallKey, payload);
      } else if (type == 'privateMessage' || type == 'privateFileMessage') {
        await prefs.setString(pendingNotificationKey, payload);
      }
    } catch (_) {}
  }

  static void setCurrentToken(String token) {
    final clean = token.trim();
    if (clean.isEmpty) return;
    _currentToken = clean;
  }

  static const MethodChannel _systemChannel = MethodChannel('zerolog/system');

  static Future<void> requestStartupPermissions() async {
    try {
      await _systemChannel.invokeMethod('requestStartupPermissions');

      debugPrint('[PERMISSIONS] startup permission flow completed');
    } catch (e) {
      debugPrint('[PERMISSIONS] startup permission flow failed: $e');
    }
  }

  static Future<void> requestMiuiCallPermissionSetup() async {
    try {
      final result = await _systemChannel.invokeMethod<bool>(
        'requestMiuiCallPermissionSetup',
      );

      debugPrint('[PERMISSIONS] MIUI call permission setup result=$result');
    } catch (e) {
      debugPrint('[PERMISSIONS] MIUI call permission setup failed: $e');
    }
  }

  static Future<void> requestFullScreenIntentPermission() async {
    try {
      final granted = await _systemChannel.invokeMethod<bool>(
        'requestFullScreenIntentPermission',
      );

      debugPrint('[PERMISSIONS] full-screen intent granted=$granted');
    } catch (e) {
      debugPrint('[PERMISSIONS] full-screen intent permission failed: $e');
    }
  }

  static Future<bool> requestCallPermissions() async {
    try {
      final granted = await _systemChannel.invokeMethod<bool>(
        'requestCallPermissions',
      );

      debugPrint('[PERMISSIONS] call microphone granted=$granted');

      return granted == true;
    } catch (e) {
      debugPrint('[PERMISSIONS] call permission failed: $e');
      return false;
    }
  }

  static Future<void> startOutgoingCallTone() async {
    try {
      await _systemChannel.invokeMethod('startOutgoingCallTone');
    } catch (e) {
      debugPrint('[CALL] outgoing tone start failed: $e');
    }
  }

  static Future<void> clearCallLockScreen() async {
    try {
      await _systemChannel.invokeMethod('clearCallLockScreen');
    } catch (e) {
      debugPrint('[CALL] clear lock-screen state failed: $e');
    }
  }

  static Future<void> stopOutgoingCallTone() async {
    try {
      await _systemChannel.invokeMethod('stopOutgoingCallTone');
    } catch (e) {
      debugPrint('[CALL] outgoing tone stop failed: $e');
    }
  }

  static Future<void> _initializeNotifications({
    required bool requestPermissions,
  }) async {
    if (_notificationsInitialized) return;

    const androidSettings = AndroidInitializationSettings('ic_launcher');

    await _notifications.initialize(
      settings: const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: (response) async {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;

        await storeNotificationPayload(payload);
      },
      onDidReceiveBackgroundNotificationResponse: _notificationTapBackground,
    );

    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (android != null) {
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          callChannelId,
          'Gelen çağrılar',
          description: 'ZeroLog sesli arama bildirimleri',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
      );

      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          messageChannelId,
          'Mesajlar',
          description: 'ZeroLog özel mesaj bildirimleri',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
      );

      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          fileChannelId,
          'Dosyalar',
          description: 'ZeroLog fotoğraf ve dosya bildirimleri',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
      );

      if (requestPermissions) {
        await android.requestNotificationsPermission();
        await android.requestFullScreenIntentPermission();
      }
    }

    _notificationsInitialized = true;

    if (requestPermissions) {
      try {
        final launchDetails = await _notifications
            .getNotificationAppLaunchDetails();

        if (launchDetails?.didNotificationLaunchApp == true) {
          final payload = launchDetails?.notificationResponse?.payload;

          if (payload != null && payload.isNotEmpty) {}
        }
      } catch (_) {}
    }
  }

  static Future<String?> _getFcmTokenWithRetry() async {
    for (var attempt = 1; attempt <= 5; attempt++) {
      try {
        final token = await _messaging.getToken().timeout(
          const Duration(seconds: 10),
        );

        if (token != null && token.trim().isNotEmpty) {
          return token.trim();
        }

        debugPrint('[FCM] getToken attempt $attempt returned empty');
      } catch (e) {
        debugPrint('[FCM] getToken attempt $attempt failed: $e');
      }

      if (attempt < 5) {
        await Future.delayed(Duration(seconds: attempt));
      }
    }

    return null;
  }

  static Map<String, dynamic> _normalizeCallData(Map<String, dynamic> data) {
    final from = (data['from'] ?? data['caller'] ?? '').toString().trim();
    final to = (data['to'] ?? data['callee'] ?? '').toString().trim();
    final callId = (data['callId'] ?? '').toString().trim();

    return {'type': 'callInvite', 'from': from, 'to': to, 'callId': callId};
  }

  static Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Android full-screen incoming-call Activity -> Flutter bridge.
    // Cold start durumunda event pending-call olarak saklanır;
    // MainScreen hazır olduğunda mevcut pending-call akışı bunu tüketir.
    _systemChannel.setMethodCallHandler((call) async {
      if (call.method != 'incomingCallIntent') {
        return null;
      }

      try {
        final arguments = call.arguments;

        if (arguments is Map) {
          final normalized = _normalizeCallData(
            Map<String, dynamic>.from(arguments),
          );

          final from = normalized['from'].toString();
          final to = normalized['to'].toString();
          final callId = normalized['callId'].toString();

          if (from.isNotEmpty && to.isNotEmpty && callId.isNotEmpty) {
            await storeNotificationPayload(jsonEncode(normalized));

            final handler = _incomingCallHandler;

            if (handler != null) {
              await handler(normalized);
            }

            debugPrint(
              '[FCM][native-intent] incoming call forwarded '
              'to Flutter callId=$callId',
            );
          }
        }
      } catch (e) {
        debugPrint('[FCM][native-intent] incoming call callback failed: $e');
      }

      return null;
    });

    // Android native runtime permissions:
    // notification + microphone.
    // This runs immediately when the application starts.
    await requestStartupPermissions();

    // Xiaomi / Android 11 (MIUI) çağrı izin kurulumunu başlangıçta kontrol et.
    await requestMiuiCallPermissionSetup();

    await _initializeNotifications(requestPermissions: true);

    // Android 14+ çağrı bildiriminin gerçek tam ekran olarak
    // açılabilmesi için USE_FULL_SCREEN_INTENT iznini kontrol et.
    // İzin zaten varsa hiçbir ayar ekranı açılmaz.
    await requestFullScreenIntentPermission();

    // Android MainActivity üzerinden gelen full-screen çağrı intent'ini
    // Flutter pending-call akışına aktar.
    try {
      final nativeCall = await _systemChannel.invokeMethod<dynamic>(
        'getIncomingCallIntent',
      );

      if (nativeCall is Map) {
        final normalized = _normalizeCallData(
          Map<String, dynamic>.from(nativeCall),
        );

        if (normalized['from'].toString().isNotEmpty &&
            normalized['to'].toString().isNotEmpty &&
            normalized['callId'].toString().isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(pendingCallKey, jsonEncode(normalized));

          debugPrint(
            '[FCM][native-intent] pending incoming call stored '
            'callId=${normalized['callId']}',
          );
        }
      }
    } catch (e) {
      debugPrint('[FCM][native-intent] bridge failed: $e');
    }

    // Native Android message PendingIntent -> Flutter pending notification
    final nativeMessage = await _systemChannel.invokeMethod<dynamic>(
      'getPendingMessageIntent',
    );

    if (nativeMessage is Map) {
      final data = Map<String, dynamic>.from(nativeMessage);

      if (data['type'] == 'privateMessage' ||
          data['type'] == 'privateFileMessage') {
        await storeNotificationPayload(jsonEncode(data));

        debugPrint(
          '[FCM][native-message] pending notification stored '
          'type=${data['type']}',
        );
      }
    }

    await _messaging.setAutoInitEnabled(true);

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint('[FCM] permission=${settings.authorizationStatus}');

    final token = await _getFcmTokenWithRetry();

    _currentToken = token;

    if (token == null || token.isEmpty) {
      debugPrint('[FCM] ERROR: registration token could not be obtained');
    } else {
      debugPrint('[FCM] token acquired length=${token.length}');
    }

    _messaging.onTokenRefresh
        .listen((newToken) {
          _currentToken = newToken;

          debugPrint('[FCM] token_refresh length=${newToken.length}');

          WsClient.instance.updateFcmToken(newToken);
        })
        .onError((error) {
          debugPrint('[FCM] token refresh error: $error');
        });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final type = message.data['type'];

      debugPrint(
        '[FCM][foreground] '
        'messageId=${message.messageId} '
        'type=$type',
      );

      if (type == 'callInvite') {
        final callData = _normalizeCallData(
          Map<String, dynamic>.from(message.data),
        );

        WsClient.instance.emitExternalEvent(callData);
      } else if (type == 'callStatus') {
        // Lifecycle/control event only. Stop any local incoming-call state;
        // never create a status notification for call termination.
        await cancelIncomingCallNotification();
        await clearPendingCall();
      } else if (type == 'privateMessage') {
        await showPrivateMessageNotification(message);
      } else if (type == 'privateFileMessage') {
        await showPrivateFileNotification(message);
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      debugPrint(
        '[FCM][opened] '
        'messageId=${message.messageId} '
        'type=${message.data['type']}',
      );

      final data = Map<String, dynamic>.from(message.data);

      if (data['type'] == 'callInvite') {
        final callData = _normalizeCallData(data);
        await storeNotificationPayload(jsonEncode(callData));
      } else if (data['type'] == 'privateMessage' ||
          data['type'] == 'privateFileMessage') {
        await storeNotificationPayload(jsonEncode(data));
      }
    });

    final initialMessage = await _messaging.getInitialMessage();

    if (initialMessage != null) {
      debugPrint(
        '[FCM][initial] '
        'messageId=${initialMessage.messageId} '
        'type=${initialMessage.data['type']}',
      );

      final data = Map<String, dynamic>.from(initialMessage.data);

      if (data['type'] == 'callInvite') {
        final callData = _normalizeCallData(data);
        await storeNotificationPayload(jsonEncode(callData));
      } else if (data['type'] == 'privateMessage' ||
          data['type'] == 'privateFileMessage') {
        await storeNotificationPayload(jsonEncode(data));
      }
    }
  }

  static Future<void> showIncomingCallNotification(
    Map<String, dynamic> data,
  ) async {
    await _initializeNotifications(requestPermissions: false);

    final from = (data['from'] ?? data['caller'] ?? '').toString().trim();
    final to = (data['to'] ?? data['callee'] ?? '').toString().trim();
    final callId = (data['callId'] ?? '').toString().trim();

    if (from.isEmpty || to.isEmpty || callId.isEmpty) {
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      callChannelId,
      'Gelen çağrılar',
      channelDescription: 'ZeroLog gelen sesli arama',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
    );

    final payload = jsonEncode({
      'type': 'callInvite',
      'from': from,
      'to': to,
      'callId': callId,
    });

    await _notifications.show(
      id: callNotificationId,
      title: 'Gelen ZeroLog çağrısı',
      body: '$from sizi arıyor',
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }

  static Future<void> showCallStatusNotification(RemoteMessage message) async {
    // Kept as a compatibility wrapper for existing callers.
    // callStatus is a lifecycle/control event, not a user notification.
    await cancelIncomingCallNotification();
    await clearPendingCall();
  }

  static Future<void> showPrivateFileNotification(
    RemoteMessage message,
  ) async {
    try {
      await _initializeNotifications(requestPermissions: false);

      final from = (
        message.data['from'] ??
        message.data['sender'] ??
        ''
      ).toString().trim();

      final fileId = (
        message.data['fileId'] ??
        message.data['transferId'] ??
        ''
      ).toString().trim();

      final fileName = (
        message.data['fileName'] ??
        'Dosya'
      ).toString().trim();

      final to = (
        message.data['to'] ??
        message.data['recipient'] ??
        ''
      ).toString().trim();

      if (from.isEmpty || fileId.isEmpty) return;

      await storeNotificationPayload(jsonEncode({
        'type': 'privateFileMessage',
        'from': from,
        'sender': from,
        'to': to,
        'recipient': to,
        'fileId': fileId,
        'transferId': fileId,
        'fileName': fileName,
        'fileSize': message.data['fileSize'] ?? '0',
      }));

      final activePeer = WsClient.instance.activePrivateChatPeer;

      if (activePeer != null &&
          activePeer.trim().isNotEmpty &&
          activePeer.trim().toLowerCase() == from.toLowerCase()) {
        return;
      }

      const androidDetails = AndroidNotificationDetails(
        fileChannelId,
        'Dosyalar',
        channelDescription: 'ZeroLog dosya ve fotoğraf bildirimleri',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        showWhen: true,
      );

      final payload = jsonEncode({
        'type': 'privateFileMessage',
        'from': from,
        'sender': from,
        'to': to,
        'recipient': to,
        'fileId': fileId,
        'transferId': fileId,
        'fileName': fileName,
        'fileSize': message.data['fileSize'] ?? '0',
      });

      await _notifications.show(
        id: _stableNotificationId('file_$fileId'),
        title: from,
        body: '$fileName gönderiyor',
        notificationDetails: const NotificationDetails(
          android: androidDetails,
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('[FCM] private file notification failed: $e');
    }
  }

  static Future<void> showPrivateMessageNotification(
    RemoteMessage message,
  ) async {
    try {
      await _initializeNotifications(requestPermissions: false);

      final from = (message.data['from'] ?? message.notification?.title ?? '')
          .toString()
          .trim();

      final text = (message.data['text'] ?? message.notification?.body ?? '')
          .toString()
          .trim();

      if (from.isEmpty || text.isEmpty) return;
      // Kullanıcı zaten bu kişiyle özel sohbet ekranındaysa,
      // aynı mesaj için ayrıca bildirim üretme.
      final activePeer = WsClient.instance.activePrivateChatPeer;

      if (activePeer != null &&
          activePeer.trim().isNotEmpty &&
          activePeer.trim().toLowerCase() == from.toLowerCase()) {
        debugPrint(
          "[FCM] private message notification suppressed: active chat with $from",
        );
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final messagePreview =
          prefs.getBool('zerolog.chat.message_preview') ?? true;

      final notificationText = messagePreview
          ? text
          : 'Yeni bir ZeroLog mesajı';

      const androidDetails = AndroidNotificationDetails(
        messageChannelId,
        'Mesajlar',
        channelDescription: 'ZeroLog özel mesaj bildirimleri',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        showWhen: true,
      );

      final payload = jsonEncode({
        'type': 'privateMessage',
        'from': (message.data['from'] ?? message.data['sender'] ?? from)
            .toString()
            .trim(),
        'sender': (message.data['sender'] ?? message.data['from'] ?? from)
            .toString()
            .trim(),
        'to': (message.data['to'] ?? message.data['recipient'] ?? '')
            .toString()
            .trim(),
        'recipient': (message.data['recipient'] ?? message.data['to'] ?? '')
            .toString()
            .trim(),
        'text': text,
        'id': (message.data['id'] ?? message.data['messageId'] ?? '')
            .toString(),
        'messageId': (message.data['messageId'] ?? message.data['id'] ?? '')
            .toString(),
        'clientMessageId': (message.data['clientMessageId'] ?? '').toString(),
      });

      final notificationKey = (message.data['messageId'] ??
              message.data['id'] ??
              message.data['clientMessageId'] ??
              '${from}_${message.messageId ?? DateTime.now().millisecondsSinceEpoch}')
          .toString();
      final notificationId = _stableNotificationId(notificationKey);

      await _notifications.show(
        id: notificationId,
        title: from,
        body: notificationText,
        notificationDetails: const NotificationDetails(android: androidDetails),
        payload: payload,
      );
    } catch (e) {
      debugPrint('[FCM] private message notification failed: $e');
    }
  }


  static int _stableNotificationId(String value) {
    var hash = 0;
    for (final codeUnit in value.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }

    // Reserve low IDs for call/system notifications.
    return 10000 + (hash % 20000);
  }

  static Future<void> startIncomingCallTone() async {
    try {
      await _systemChannel.invokeMethod('startIncomingCallTone');
    } catch (e) {
      debugPrint('[CALL] native incoming tone start failed: $e');
    }
  }

  static Future<void> cancelIncomingCallNotification() async {
    try {
      await _initializeNotifications(requestPermissions: false);
      await _notifications.cancel(id: callNotificationId);
    } catch (_) {}

    try {
      await _systemChannel.invokeMethod('stopIncomingCallTone');
    } catch (e) {
      debugPrint('[CALL] native incoming tone stop failed: $e');
    }
  }

  static Future<void> clearPendingCall() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(pendingCallKey);
    } catch (_) {}
  }

  static Future<void> pullPendingNativeMessage() async {
    try {
      final nativeMessage = await _systemChannel.invokeMethod<dynamic>(
        'getPendingMessageIntent',
      );

      if (nativeMessage is Map) {
        final data = Map<String, dynamic>.from(nativeMessage);

        if (data['type'] == 'privateMessage' ||
            data['type'] == 'privateFileMessage') {
          await storeNotificationPayload(jsonEncode(data));
        }
      }
    } catch (e) {
      debugPrint('[FCM][native-message] pull failed: $e');
    }
  }

  static Future<Map<String, dynamic>?> takePendingNotification() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(pendingNotificationKey);

      if (raw == null || raw.isEmpty) {
        return null;
      }

      await prefs.remove(pendingNotificationKey);

      final decoded = jsonDecode(raw);

      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}

    return null;
  }

  static Future<Map<String, dynamic>?> takePendingCall() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(pendingCallKey);

      if (raw == null || raw.isEmpty) {
        return null;
      }

      await prefs.remove(pendingCallKey);

      final decoded = jsonDecode(raw);

      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}

    return null;
  }
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
  mivi,
  obsidianGold,
  platinum,
  emerald,
}
