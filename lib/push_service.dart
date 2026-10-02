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
  static const String pendingNotificationQueueKey =
      'zerolog.pending_notification_queue';

  static String? _currentToken;
  static bool _notificationsInitialized = false;

  static Future<void> Function(Map<String, dynamic>)? _incomingCallHandler;

  // Serialize Flutter-side pending-call mutations. Without this guard, an
  // older callStatus can read call A, yield on SharedPreferences, and then
  // remove the pending record after a newer call B has already replaced it.
  static Future<void> _pendingCallMutation = Future<void>.value();

  static Future<T> _withPendingCallMutation<T>(
    Future<T> Function() operation,
  ) {
    final previous = _pendingCallMutation;
    final next = previous.then((_) => operation());
    _pendingCallMutation = next.then<void>(
      (_) {},
      onError: (_, _) {},
    );
    return next;
  }

  static String? get currentToken => _currentToken;

  static void setIncomingCallHandler(
    Future<void> Function(Map<String, dynamic>)? handler,
  ) {
    _incomingCallHandler = handler;
  }

  static Future<bool> storeNotificationPayload(String payload) async {
    if (payload.trim().isEmpty) return false;

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return false;

      final type = decoded['type']?.toString();
      final prefs = await SharedPreferences.getInstance();

      if (type == 'callInvite') {
        return await _withPendingCallMutation<bool>(
          () => prefs.setString(pendingCallKey, payload),
        );
      }

      if (type != 'privateMessage' && type != 'privateFileMessage') {
        return false;
      }

      final rawQueue =
          prefs.getString(pendingNotificationQueueKey) ?? '[]';
      List<dynamic> queue;
      try {
        final decodedQueue = jsonDecode(rawQueue);
        queue = decodedQueue is List ? List<dynamic>.from(decodedQueue) : <dynamic>[];
      } catch (_) {
        queue = <dynamic>[];
      }

      final decodedMap = Map<String, dynamic>.from(decoded);
      final identity = _notificationIdentity(decodedMap);
      if (identity.isNotEmpty) {
        queue.removeWhere(
          (item) =>
              item is Map &&
              _notificationIdentity(Map<String, dynamic>.from(item)) == identity,
        );
      }

      queue.add(decodedMap);
      if (queue.length > 100) {
        queue = queue.sublist(queue.length - 100);
      }

      final ok = await prefs.setString(
        pendingNotificationQueueKey,
        jsonEncode(queue),
      );

      // Migrate/clear the legacy single-slot value only after the new queue
      // has been durably written.
      if (ok) {
        await prefs.remove(pendingNotificationKey);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  static String _notificationIdentity(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    final fileId = data['fileId']?.toString() ?? '';
    final id = data['id']?.toString() ?? '';
    final clientMessageId = data['clientMessageId']?.toString() ?? '';
    if (type == 'privateFileMessage' && fileId.isNotEmpty) {
      return '$type|$fileId';
    }
    final messageId = id.isNotEmpty ? id : clientMessageId;
    return messageId.isEmpty ? '' : '$type|$messageId';
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

      zeroLog('[PERMISSIONS] startup permission flow completed');
    } catch (e) {
      zeroLog('[PERMISSIONS] startup permission flow failed: $e');
    }
  }

  static Future<void> requestMiuiCallPermissionSetup() async {
    try {
      final result = await _systemChannel.invokeMethod<bool>(
        'requestMiuiCallPermissionSetup',
      );

      zeroLog('[PERMISSIONS] MIUI call permission setup result=$result');
    } catch (e) {
      zeroLog('[PERMISSIONS] MIUI call permission setup failed: $e');
    }
  }

  static Future<void> requestFullScreenIntentPermission() async {
    try {
      final granted = await _systemChannel.invokeMethod<bool>(
        'requestFullScreenIntentPermission',
      );

      zeroLog('[PERMISSIONS] full-screen intent granted=$granted');
    } catch (e) {
      zeroLog('[PERMISSIONS] full-screen intent permission failed: $e');
    }
  }

  static Future<bool> requestCallPermissions({bool video = false}) async {
    try {
      final granted = await _systemChannel.invokeMethod<bool>(
        'requestCallPermissions',
        <String, dynamic>{'video': video},
      );

      zeroLog('[PERMISSIONS] call permissions granted=$granted video=$video');

      return granted == true;
    } catch (e) {
      zeroLog('[PERMISSIONS] call permission failed: $e');
      return false;
    }
  }

  static Future<void> startCallForegroundService({bool video = false}) async {
    try {
      await _systemChannel.invokeMethod(
        'startCallForegroundService',
        <String, dynamic>{'video': video},
      );
    } catch (e) {
      zeroLog('[CALL] foreground service start failed: $e');
    }
  }

  static Future<void> stopCallForegroundService() async {
    try {
      await _systemChannel.invokeMethod('stopCallForegroundService');
    } catch (e) {
      zeroLog('[CALL] foreground service stop failed: $e');
    }
  }

  static Future<void> startOutgoingCallTone() async {
    try {
      await _systemChannel.invokeMethod('startOutgoingCallTone');
    } catch (e) {
      zeroLog('[CALL] outgoing tone start failed: $e');
    }
  }

  static Future<void> clearCallLockScreen() async {
    try {
      await _systemChannel.invokeMethod('clearCallLockScreen');
    } catch (e) {
      zeroLog('[CALL] clear lock-screen state failed: $e');
    }
  }

  /// True while an incoming/outgoing CallScreen is on screen. Set by
  /// CallScreen's initState()/dispose(). Used by the app-wide privacy
  /// lock gate to avoid throwing a PIN/biometric prompt over an active
  /// call, which would block the user from using it.
  static bool callScreenActive = false;

  /// Read-only check for a call that has been signalled (e.g. via the
  /// native full-screen incoming-call intent) but whose CallScreen has
  /// not finished mounting yet. Used by the same app-wide lock gate to
  /// avoid a race where the lock prompt appears for the brief moment
  /// between the app resuming and the call screen being pushed.
  static Future<bool> hasPendingCall() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(pendingCallKey);
      return raw != null && raw.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Keeps the device screen on for the duration of an active call
  /// (audio or video), independent of the lock-screen bypass flags used
  /// only for the incoming-call ringing UI. Call with `true` as soon as
  /// the call screen appears and with `false` once it is disposed, or the
  /// display will time out mid-call the same way it would on any other
  /// idle screen.
  static Future<void> setCallScreenAwake(bool awake) async {
    try {
      await _systemChannel.invokeMethod('setCallScreenAwake', {
        'awake': awake,
      });
    } catch (e) {
      zeroLog('[CALL] set screen-awake state failed: $e');
    }
  }

  static Future<void> stopOutgoingCallTone() async {
    try {
      await _systemChannel.invokeMethod('stopOutgoingCallTone');
    } catch (e) {
      zeroLog('[CALL] outgoing tone stop failed: $e');
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
        // Notification permission is requested once here. Full-screen call
        // intent permission is handled by our native bridge below so the
        // Android 14+ settings flow cannot be triggered twice.
        await android.requestNotificationsPermission();
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

        zeroLog('[FCM] getToken attempt $attempt returned empty');
      } catch (e) {
        zeroLog('[FCM] getToken attempt $attempt failed: $e');
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
    final video = data['video'] == true ||
        data['video']?.toString().toLowerCase() == 'true';

    return {
      'type': 'callInvite',
      'from': from,
      'to': to,
      'callId': callId,
      'video': video,
    };
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

            zeroLog(
              '[FCM][native-intent] incoming call forwarded '
              'to Flutter callId=$callId',
            );
          }
        }
      } catch (e) {
        zeroLog('[FCM][native-intent] incoming call callback failed: $e');
      }

      return null;
    });

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
          await storeNotificationPayload(jsonEncode(normalized));

          zeroLog(
            '[FCM][native-intent] pending incoming call stored '
            'callId=${normalized['callId']}',
          );
        }
      }
    } catch (e) {
      zeroLog('[FCM][native-intent] bridge failed: $e');
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

        zeroLog(
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

    zeroLog('[FCM] permission=${settings.authorizationStatus}');

    final token = await _getFcmTokenWithRetry();

    _currentToken = token;

    if (token == null || token.isEmpty) {
      zeroLog('[FCM] ERROR: registration token could not be obtained');
    } else {
      zeroLog('[FCM] token acquired length=${token.length}');
    }

    _messaging.onTokenRefresh
        .listen((newToken) {
          _currentToken = newToken;

          zeroLog('[FCM] token_refresh length=${newToken.length}');

          WsClient.instance.updateFcmToken(newToken);
        })
        .onError((error) {
          zeroLog('[FCM] token refresh error: $error');
        });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final type = message.data['type'];

      zeroLog(
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
        await cancelIncomingCallNotification(
          callId: message.data['callId']?.toString(),
        );
        await clearPendingCall(callId: message.data['callId']?.toString());
      } else if (type == 'privateMessage') {
        // Private message notifications have a single authority: the native
        // FirebaseMessagingService. This prevents duplicate notifications
        // when a data-only FCM arrives while Flutter is foregrounded.
        zeroLog('[FCM] private message notification handled by native service');
      } else if (type == 'privateFileMessage') {
        // File-transfer notifications have a single authority: the native
        // FirebaseMessagingService. It runs for foreground/background/terminated
        // delivery and uses the same stable notification id as completion.
        // Do not create a second Dart notification here.
        zeroLog('[FCM] private file notification handled by native service');
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      zeroLog(
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
      zeroLog(
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
    final video = data['video'] == true ||
        data['video']?.toString().toLowerCase() == 'true';

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
      'video': video,
    });

    await _notifications.show(
      id: callNotificationId,
      title: video ? 'Gelen ZeroLog görüntülü çağrısı' : 'Gelen ZeroLog sesli çağrısı',
      body: '$from sizi arıyor',
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }

  static Future<void> showCallStatusNotification(RemoteMessage message) async {
    // Kept as a compatibility wrapper for existing callers.
    // callStatus is a lifecycle/control event, not a user notification.
    await cancelIncomingCallNotification(
      callId: message.data['callId']?.toString(),
    );
    await clearPendingCall(callId: message.data['callId']?.toString());
  }

  // Legacy compatibility helper. File-transfer notifications are owned by the
  // native FCM service; this method is intentionally not called by onMessage.
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
      zeroLog('[FCM] private file notification failed: $e');
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
        zeroLog(
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
      zeroLog('[FCM] private message notification failed: $e');
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
      zeroLog('[CALL] native incoming tone start failed: $e');
    }
  }

  static Future<void> cancelIncomingCallNotification({String? callId}) async {
    try {
      await _initializeNotifications(requestPermissions: false);
      await _notifications.cancel(id: callNotificationId);
    } catch (_) {}

    try {
      await _systemChannel.invokeMethod(
        'cancelIncomingCallNotification',
        <String, dynamic>{'callId': callId?.trim() ?? ''},
      );
    } catch (e) {
      zeroLog('[CALL] native incoming notification stop failed: $e');
    }
  }

  /// Clears only the matching pending call. A late status for an older call
  /// must never remove a newer incoming call waiting on the lock screen.
  static Future<void> clearPendingCall({String? callId}) async {
    final expected = callId?.trim() ?? '';
    if (expected.isEmpty) return;

    await _withPendingCallMutation<void>(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(pendingCallKey);
        if (raw == null || raw.isEmpty) return;

        final decoded = jsonDecode(raw);
        if (decoded is Map &&
            decoded['callId']?.toString().trim() == expected) {
          await prefs.remove(pendingCallKey);
        }
      } catch (_) {}
    });
  }

  static Future<void> pullPendingNativeMessage() async {
    const maxDrainItems = 100;

    try {
      for (var i = 0; i < maxDrainItems; i++) {
        final nativeMessage = await _systemChannel.invokeMethod<dynamic>(
          'getPendingMessageIntent',
        );

        if (nativeMessage is! Map) {
          break;
        }

        final data = Map<String, dynamic>.from(nativeMessage);
        if (data['type'] == '__queue_skip__') {
          continue;
        }

        if (data['type'] == 'privateMessage' ||
            data['type'] == 'privateFileMessage') {
          final stored = await storeNotificationPayload(jsonEncode(data));
          if (!stored) {
            // Leave the native queue item untouched. A later app-start drain
            // can retry it without losing the notification.
            break;
          }

          final queueKey = data['__queueKey']?.toString().trim() ?? '';
          if (queueKey.isNotEmpty) {
            final acknowledged = await _systemChannel.invokeMethod<bool>(
                  'ackPendingMessageIntent',
                  <String, dynamic>{'queueKey': queueKey},
                ) ??
                false;
            if (!acknowledged) {
              break;
            }
          }
        }
      }
    } catch (e) {
      zeroLog('[FCM][native-message] pull failed: $e');
    }
  }

  static Future<Map<String, dynamic>?> takePendingNotification() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawQueue =
          prefs.getString(pendingNotificationQueueKey) ?? '[]';

      try {
        final decodedQueue = jsonDecode(rawQueue);
        if (decodedQueue is List && decodedQueue.isNotEmpty) {
          final queue = List<dynamic>.from(decodedQueue);
          final first = queue.removeAt(0);
          final ok = await prefs.setString(
            pendingNotificationQueueKey,
            jsonEncode(queue),
          );
          if (!ok) return null;
          if (first is Map) {
            return Map<String, dynamic>.from(first);
          }
        }
      } catch (_) {}

      // Backward compatibility for payloads written by older builds.
      final legacy = prefs.getString(pendingNotificationKey);
      if (legacy != null && legacy.isNotEmpty) {
        final decoded = jsonDecode(legacy);
        if (decoded is Map) {
          await prefs.remove(pendingNotificationKey);
          return Map<String, dynamic>.from(decoded);
        }
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

      final decoded = jsonDecode(raw);

      if (decoded is Map) {
        // Keep the pending record until the CallScreen reaches a terminal
        // path and clears this exact callId. Consuming it here can race with
        // a newer callInvite that arrives while the UI is opening.
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
