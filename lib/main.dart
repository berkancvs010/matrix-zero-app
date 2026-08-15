import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:proximity_sensor/proximity_sensor.dart';

const String wsUrl = 'wss://zerolog.giize.com:8443/ws';
final GlobalKey<NavigatorState> zeroLogNavigatorKey =
    GlobalKey<NavigatorState>();

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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  // FCM ve runtime izinleri uygulamanın giriş ekranı açılmadan
  // önce hazırlanır. Böylece login paketine güncel FCM token
  // kesin olarak dahil edilir.
  try {
    await ZeroLogPushService.initialize();
  } catch (e, stack) {
    debugPrint('[FCM] initialization failed: $e');
    debugPrint('$stack');
  }

  runApp(const MatrixZeroApp());
}

@pragma('vm:entry-point')
Future<void> _notificationTapBackground(NotificationResponse response) async {
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;

  await ZeroLogPushService.storeNotificationPayload(payload);
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();

  final type = message.data['type'];

  if (type == 'callInvite') {
    // Native FirebaseMessagingService çağrı bildirimi,
    // looping zil sesi, titreşim ve full-screen intent'i yönetiyor.
  } else if (type == 'callStatus') {
    await ZeroLogPushService.showCallStatusNotification(message);
  } else if (type == 'privateMessage') {
    // Data-only mesaj bildirimi native FCM service tarafından
    // oluşturuluyor. Burada tekrar bildirim üretme.
  }

  debugPrint(
    '[FCM][background] '
    'messageId=${message.messageId} '
    'type=${message.data['type']}',
  );
}

class ZeroLogPushService {
  ZeroLogPushService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const String callChannelId = 'zerolog_calls_v5';
  static const String messageChannelId = 'zerolog_messages_v4';
  static const int callNotificationId = 9001;
  static const int messageNotificationId = 9002;
  static const String pendingCallKey = 'zerolog.pending_call';
  static const String pendingNotificationKey = 'zerolog.pending_notification';

  static String? _currentToken;
  static bool _notificationsInitialized = false;

  static String? get currentToken => _currentToken;

  static Future<void> storeNotificationPayload(String payload) async {
    if (payload.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(payload);

      if (decoded is! Map) return;

      final type = decoded['type']?.toString();
      final prefs = await SharedPreferences.getInstance();

      if (type == 'callInvite') {
        await prefs.setString(pendingCallKey, payload);
      } else if (type == 'privateMessage') {
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

    // Android native runtime permissions:
    // notification + microphone.
    // This runs immediately when the application starts.
    await requestStartupPermissions();

    await _initializeNotifications(requestPermissions: true);

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

      if (data['type'] == 'privateMessage') {
        await storeNotificationPayload(jsonEncode(data));

        debugPrint('[FCM][native-message] pending private message stored');
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
        await showCallStatusNotification(message);
      } else if (type == 'privateMessage') {
        await showPrivateMessageNotification(message);
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
      } else if (data['type'] == 'privateMessage') {
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
      } else if (data['type'] == 'privateMessage') {
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
    try {
      await _initializeNotifications(requestPermissions: false);
      await cancelIncomingCallNotification();

      final title = (message.data['title'] ?? 'ZeroLog çağrı')
          .toString()
          .trim();

      final body = (message.data['body'] ?? '').toString().trim();

      if (body.isEmpty) return;

      const details = AndroidNotificationDetails(
        messageChannelId,
        'Mesajlar',
        channelDescription: 'ZeroLog çağrı durum bildirimleri',
        importance: Importance.high,
        priority: Priority.high,
        visibility: NotificationVisibility.public,
        playSound: true,
        enableVibration: true,
      );

      await _notifications.show(
        id: 9003,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: details),
      );
    } catch (_) {}
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

      await _notifications.show(
        id: messageNotificationId,
        title: from,
        body: notificationText,
        notificationDetails: const NotificationDetails(android: androidDetails),
        payload: payload,
      );
    } catch (e) {
      debugPrint('[FCM] private message notification failed: $e');
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

        if (data['type'] == 'privateMessage') {
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
      navigatorKey: zeroLogNavigatorKey,
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
    final theme = ThemeController.instance.data;

    if (!_welcomeShouldShow) {
      return Scaffold(
        backgroundColor: theme.background,
        body: Center(child: CircularProgressIndicator(color: theme.primary)),
      );
    }

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

  void emitExternalEvent(Map<String, dynamic> data) {
    _events.add(Map<String, dynamic>.from(data));
  }

  final Set<String> _onlineUsers = <String>{};
  final Set<String> _knownUsers = <String>{};

  List<String> get onlineUsers => List.unmodifiable(_onlineUsers);
  List<String> get knownUsers => List.unmodifiable(_knownUsers);

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

  void requestUserDirectory() {
    if (!connected || _channel == null) return;

    try {
      _channel!.sink.add(jsonEncode({'type': 'getUserDirectory'}));
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
  }) {
    final data = <String, dynamic>{'type': 'setNotificationSettings'};

    if (messageNotificationsEnabled != null) {
      data['messageNotificationsEnabled'] = messageNotificationsEnabled;
    }

    if (callNotificationsEnabled != null) {
      data['callNotificationsEnabled'] = callNotificationsEnabled;
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
  State<ZeroLogReferenceLogin> createState() => _ZeroLogReferenceLoginState();
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
      prefixIcon: Icon(icon, color: greenBright, size: 30),
      suffixIcon: suffix,
      filled: true,
      fillColor: fieldBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 21),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: Color(0xFF244F38), width: 1.4),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: greenBright, width: 1.5),
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
            side: const BorderSide(color: Color(0xFF2DFF82), width: 1),
          ),
          title: const Text(
            'UNUTMASAYDIN 🤣',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
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
          side: const BorderSide(color: greenBright, width: 1.4),
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
              widget.registerMode ? 'Giriş ekranına dön' : 'Yeni hesap oluştur',
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
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
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
                          border: Border.all(color: greenBright, width: 2),
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

                      if (widget.registerMode) const SizedBox(height: 16),

                      _usernameField(),

                      const SizedBox(height: 16),

                      _passwordField(),

                      if (!widget.registerMode) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: widget.loading
                                ? null
                                : _showForgotDialog,
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
  String? _profilePhotoPath;
  String _profileAbout = '';

  static const String _profilePhotoKey = 'zerolog.profile.photo';
  static const String _profileAboutKey = 'zerolog.profile.about';

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      _profilePhotoPath = prefs.getString(_profilePhotoKey);
      _profileAbout = prefs.getString(_profileAboutKey) ?? '';
    });
  }

  Future<void> _pickProfilePhoto() async {
    final picker = ImagePicker();

    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 900,
      maxHeight: 900,
      imageQuality: 88,
    );

    if (image == null) return;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_profilePhotoKey, image.path);

    if (!mounted) return;

    setState(() {
      _profilePhotoPath = image.path;
    });
  }

  Future<void> _takeProfilePhoto() async {
    final picker = ImagePicker();

    final image = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 900,
      maxHeight: 900,
      imageQuality: 88,
      preferredCameraDevice: CameraDevice.front,
    );

    if (image == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profilePhotoKey, image.path);

    if (!mounted) return;

    setState(() {
      _profilePhotoPath = image.path;
    });
  }

  Future<void> _editProfileAbout() async {
    final controller = TextEditingController(text: _profileAbout);

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final theme = ThemeController.instance.data;

        return AlertDialog(
          backgroundColor: theme.surface,
          title: const Text('Hakkında'),
          content: TextField(
            controller: controller,
            maxLines: 4,
            maxLength: 160,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Kendiniz hakkında kısa bir bilgi',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, controller.text.trim());
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result == null) return;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_profileAboutKey, result);

    if (!mounted) return;

    setState(() {
      _profileAbout = result;
    });
  }

  Widget _profileAvatar({double radius = 25}) {
    final theme = ThemeController.instance.data;

    final path = _profilePhotoPath;

    if (path != null && path.isNotEmpty) {
      final file = File(path);

      if (file.existsSync()) {
        return CircleAvatar(
          radius: radius,
          backgroundColor: theme.primary.withValues(alpha: 0.14),
          backgroundImage: FileImage(file),
        );
      }
    }

    final letter = widget.nickname.trim().isEmpty
        ? '?'
        : widget.nickname.trim().substring(0, 1).toUpperCase();

    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.primary.withValues(alpha: 0.14),
      child: Text(
        letter,
        style: TextStyle(
          color: theme.primary,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.68,
        ),
      ),
    );
  }

  Future<void> _openProfileEditor() async {
    final theme = ThemeController.instance.data;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.surface,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _profileAvatar(radius: 42),
                const SizedBox(height: 12),
                Text(
                  widget.nickname,
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Kamerayla fotoğraf çek'),
                  subtitle: const Text('Yeni profil fotoğrafı oluştur'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _takeProfilePhoto();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Profil fotoğrafı seç'),
                  subtitle: const Text('Galeriden bir fotoğraf kullan'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _pickProfilePhoto();
                  },
                ),
                if (_profilePhotoPath != null && _profilePhotoPath!.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded),
                    title: const Text('Profil fotoğrafını kaldır'),
                    subtitle: const Text('Varsayılan avatarı kullan'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove(_profilePhotoKey);
                      if (!mounted) return;
                      setState(() {
                        _profilePhotoPath = null;
                      });
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.edit_note_rounded),
                  title: const Text('Hakkında bilgisi'),
                  subtitle: Text(
                    _profileAbout.isEmpty
                        ? 'Henüz bir açıklama eklenmedi'
                        : _profileAbout,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _editProfileAbout();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  final Set<String> _handledCallIds = <String>{};

  late final StreamSubscription<Map<String, dynamic>> _subscription;

  final List<String> _onlineUsers = [];
  final List<String> _knownUsers = [];

  bool _connected = false;
  bool _reconnecting = false;

  bool _presenceVisible = true;
  bool _privateMessagesEnabled = true;
  bool _messageNotificationsEnabled = true;
  bool _callNotificationsEnabled = true;

  int _selectedIndex = 0;

  final TextEditingController _contactSearchController =
      TextEditingController();

  String _contactSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadProfileData();

    WidgetsBinding.instance.addObserver(this);

    _connected = WsClient.instance.connected;

    _onlineUsers
      ..clear()
      ..addAll(WsClient.instance.onlineUsers);

    _knownUsers
      ..clear()
      ..addAll(WsClient.instance.knownUsers);

    _subscription = WsClient.instance.events.listen(_handleEvent);
    WsClient.instance.requestPrivacySettings();
    WsClient.instance.requestNotificationSettings();

    WsClient.instance.requestPresence();
    WsClient.instance.requestUserDirectory();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ZeroLogPushService.pullPendingNativeMessage();
      await _openPendingIncomingCall();
      await _openPendingPrivateMessage();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Android may suspend the WebSocket while the app is in background.
      // Force a presence/reconnect cycle when returning to foreground.
      WsClient.instance.onAppResumed();

      Future<void>.delayed(const Duration(milliseconds: 250), () async {
        if (!mounted) return;

        await ZeroLogPushService.pullPendingNativeMessage();
        await _openPendingIncomingCall();
        await _openPendingPrivateMessage();
      });
    }
  }

  Future<void> _handleEvent(Map<String, dynamic> data) async {
    if (!mounted) return;

    final type = data['type'];

    if (type == 'privacySettings') {
      final presenceVisible = data['presenceVisible'];
      final privateMessagesEnabled = data['privateMessagesEnabled'];

      if (presenceVisible is bool || privateMessagesEnabled is bool) {
        setState(() {
          if (presenceVisible is bool) {
            _presenceVisible = presenceVisible;
          }

          if (privateMessagesEnabled is bool) {
            _privateMessagesEnabled = privateMessagesEnabled;
          }
        });
      }
    }

    if (type == 'notificationSettings') {
      final messageNotificationsEnabled = data['messageNotificationsEnabled'];
      final callNotificationsEnabled = data['callNotificationsEnabled'];

      if (messageNotificationsEnabled is bool ||
          callNotificationsEnabled is bool) {
        setState(() {
          if (messageNotificationsEnabled is bool) {
            _messageNotificationsEnabled = messageNotificationsEnabled;
          }

          if (callNotificationsEnabled is bool) {
            _callNotificationsEnabled = callNotificationsEnabled;
          }
        });
      }
    }

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

    if (type == 'userDirectory') {
      final raw = data['users'];

      if (raw is List) {
        final users =
            raw
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .where((e) => e.toLowerCase() != widget.nickname.toLowerCase())
                .toSet()
                .toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        setState(() {
          _knownUsers
            ..clear()
            ..addAll(users);
        });
      }
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

    if (type == 'callInvite') {
      final from = (data['from'] ?? data['caller'] ?? '').toString().trim();
      final to = (data['to'] ?? data['callee'] ?? '').toString().trim();
      final callId = (data['callId'] ?? '').toString().trim();

      if (from.isEmpty || to.isEmpty || callId.isEmpty) {
        return;
      }

      if (to.toLowerCase() != widget.nickname.toLowerCase()) {
        return;
      }

      if (_handledCallIds.contains(callId)) {
        return;
      }

      _handledCallIds.add(callId);

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            myNick: widget.nickname,
            targetNick: from,
            outgoing: false,
            callId: callId,
          ),
        ),
      );
      return;
    }

    // Eski/uyumluluk akışı: doğrudan offer gelirse de kabul et.
    if (type == 'callOffer') {
      final from = (data['from'] ?? '').toString();
      final to = (data['to'] ?? '').toString();

      if (from.isEmpty || to.isEmpty) return;

      if (to.toLowerCase() != widget.nickname.toLowerCase()) {
        return;
      }

      final callId = (data['callId'] ?? '').toString().trim();

      if (callId.isNotEmpty && _handledCallIds.contains(callId)) {
        return;
      }

      if (callId.isNotEmpty) {
        _handledCallIds.add(callId);
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            myNick: widget.nickname,
            targetNick: from,
            outgoing: false,
            callId: callId.isEmpty ? null : callId,
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
    final callId =
        '${DateTime.now().millisecondsSinceEpoch}-${widget.nickname}';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          myNick: widget.nickname,
          targetNick: target,
          outgoing: true,
          callId: callId,
        ),
      ),
    );
  }

  Future<void> _openPendingPrivateMessage() async {
    final data = await ZeroLogPushService.takePendingNotification();

    if (!mounted || data == null) return;

    if ((data['type'] ?? '').toString() != 'privateMessage') return;

    final from = (data['from'] ?? data['sender'] ?? '').toString().trim();
    final to = (data['to'] ?? data['target'] ?? '').toString().trim();

    if (from.isEmpty) return;

    if (to.isNotEmpty && to.toLowerCase() != widget.nickname.toLowerCase()) {
      return;
    }

    if (from.toLowerCase() == widget.nickname.toLowerCase()) return;

    // Bildirimde gönderen rumuz kesin olarak hedef sohbetin kendisidir.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PrivateChatScreen(myNick: widget.nickname, targetNick: from),
      ),
    );
  }

  Future<void> _openPendingIncomingCall() async {
    final data = await ZeroLogPushService.takePendingCall();

    if (!mounted || data == null) return;

    final from = (data['from'] ?? data['caller'] ?? '').toString().trim();
    final to = (data['to'] ?? data['callee'] ?? '').toString().trim();
    final callId = (data['callId'] ?? '').toString().trim();

    if (from.isEmpty ||
        to.isEmpty ||
        callId.isEmpty ||
        to.toLowerCase() != widget.nickname.toLowerCase()) {
      return;
    }

    if (_handledCallIds.contains(callId)) return;

    _handledCallIds.add(callId);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          myNick: widget.nickname,
          targetNick: from,
          outgoing: false,
          callId: callId,
        ),
      ),
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription.cancel();
    _contactSearchController.dispose();
    super.dispose();
  }

  Widget _avatar(String name, {bool online = false}) {
    final theme = ThemeController.instance.data;
    final letter = name.trim().isEmpty
        ? '?'
        : name.trim().substring(0, 1).toUpperCase();

    final isMyProfile =
        name.trim().toLowerCase() == widget.nickname.trim().toLowerCase();

    final profilePath = isMyProfile ? _profilePhotoPath : null;

    final profileFile = profilePath == null || profilePath.isEmpty
        ? null
        : File(profilePath);

    return Stack(
      children: [
        CircleAvatar(
          radius: 25,
          backgroundColor: theme.primary.withValues(alpha: 0.14),
          backgroundImage: profileFile != null && profileFile.existsSync()
              ? FileImage(profileFile)
              : null,
          child: profileFile != null && profileFile.existsSync()
              ? null
              : Text(
                  letter,
                  style: TextStyle(
                    color: theme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
        ),
        if (online)
          Positioned(
            right: 0,
            bottom: 1,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: Colors.greenAccent,
                shape: BoxShape.circle,
                border: Border.all(color: theme.background, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _connectionBanner() {
    final theme = ThemeController.instance.data;

    if (_connected && !_reconnecting) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _reconnecting ? 'Bağlantı yeniden kuruluyor…' : 'Bağlanıyor…',
            style: TextStyle(color: theme.text, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildChatsPage() {
    final theme = ThemeController.instance.data;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
      children: [
        _connectionBanner(),

        // Hızlı yeni sohbet
        Material(
          color: theme.surface,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () {
              setState(() {
                _selectedIndex = 1;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.primary.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.search_rounded,
                      color: theme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Yeni sohbet başlat',
                          style: TextStyle(
                            color: theme.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Rumuz veya kullanıcı ara',
                          style: TextStyle(
                            color: theme.text.withValues(alpha: 0.48),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 15,
                    color: theme.text.withValues(alpha: 0.32),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 22),

        // Özel sohbetler
        Row(
          children: [
            Expanded(
              child: Text(
                'Özel sohbetler',
                style: TextStyle(
                  color: theme.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              'Güvenli',
              style: TextStyle(
                color: theme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        if (_knownUsers.isEmpty)
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: theme.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.forum_outlined,
                    color: theme.primary,
                    size: 27,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Henüz özel sohbet yok',
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Bir kişi arayarak güvenli sohbet başlatabilirsiniz.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.text.withValues(alpha: 0.48),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          )
        else
          ..._knownUsers.take(8).map((user) {
            final online = _onlineUsers.any(
              (u) => u.toLowerCase() == user.toLowerCase(),
            );

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: theme.surface,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _openPrivate(user),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        _avatar(user, online: online),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.text,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    online
                                        ? Icons.circle
                                        : Icons.circle_outlined,
                                    size: 8,
                                    color: online
                                        ? theme.primary
                                        : theme.text.withValues(alpha: 0.30),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    online ? 'Çevrimiçi' : 'Çevrimdışı',
                                    style: TextStyle(
                                      color: theme.text.withValues(alpha: 0.48),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Ara',
                          onPressed: () => _call(user),
                          icon: Icon(Icons.call_outlined, color: theme.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

        const SizedBox(height: 18),

        // Odalar
        Row(
          children: [
            Expanded(
              child: Text(
                'Sohbet odaları',
                style: TextStyle(
                  color: theme.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: theme.primary.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${rooms.length}',
                style: TextStyle(
                  color: theme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        ...rooms.map(
          (room) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: theme.surface,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _openRoom(room),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: theme.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(
                          Icons.tag_rounded,
                          color: theme.primary,
                          size: 23,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Text(
                          room,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: theme.text.withValues(alpha: 0.30),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContactsPage() {
    final theme = ThemeController.instance.data;
    final query = _contactSearchQuery.trim().toLowerCase();

    final filteredUsers = query.isEmpty
        ? _knownUsers
        : _knownUsers
              .where((user) => user.toLowerCase().contains(query))
              .toList();

    final exactUser = query.isEmpty
        ? null
        : _knownUsers.cast<String?>().firstWhere(
            (user) => user!.toLowerCase() == query,
            orElse: () => null,
          );

    Widget quickAction({
      required IconData icon,
      required String title,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Material(
          color: theme.surface,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 17),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: theme.primary.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: theme.primary, size: 21),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    title,
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
      children: [
        Text(
          'Kişiler',
          style: TextStyle(
            color: theme.text,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Güvenli bir şekilde yeni bir sohbet başlatın.',
          style: TextStyle(
            color: theme.text.withValues(alpha: 0.48),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 18),

        Material(
          color: theme.surface,
          borderRadius: BorderRadius.circular(20),
          child: TextField(
            controller: _contactSearchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Rumuz ara',
              hintStyle: TextStyle(color: theme.text.withValues(alpha: 0.40)),
              prefixIcon: Icon(Icons.search_rounded, color: theme.primary),
              suffixIcon: query.isNotEmpty
                  ? IconButton(
                      tooltip: 'Temizle',
                      icon: Icon(
                        Icons.close_rounded,
                        color: theme.text.withValues(alpha: 0.45),
                      ),
                      onPressed: () {
                        _contactSearchController.clear();
                        setState(() => _contactSearchQuery = '');
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 17,
              ),
            ),
            onChanged: (value) {
              setState(() => _contactSearchQuery = value);
            },
          ),
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            quickAction(
              icon: Icons.person_search_rounded,
              title: 'Rumuz bul',
              onTap: () {
                FocusScope.of(context).requestFocus(FocusNode());
              },
            ),
            const SizedBox(width: 9),
            quickAction(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Yeni sohbet',
              onTap: () {
                setState(() => _selectedIndex = 1);
              },
            ),
            const SizedBox(width: 9),
            quickAction(
              icon: Icons.call_outlined,
              title: 'Arama başlat',
              onTap: () {
                setState(() => _selectedIndex = 2);
              },
            ),
          ],
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(4, 25, 4, 10),
          child: Row(
            children: [
              Text(
                query.isEmpty ? 'Kişileriniz' : 'Arama sonuçları',
                style: TextStyle(
                  color: theme.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (filteredUsers.isNotEmpty)
                Text(
                  '${filteredUsers.length}',
                  style: TextStyle(
                    color: theme.text.withValues(alpha: 0.40),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),

        if (filteredUsers.isEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.fromLTRB(24, 30, 24, 30),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.person_search_rounded,
                  size: 34,
                  color: theme.text.withValues(alpha: 0.28),
                ),
                const SizedBox(height: 12),
                Text(
                  query.isEmpty
                      ? 'Henüz kişi bulunmuyor'
                      : 'Kullanıcı bulunamadı',
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  query.isEmpty
                      ? 'Bir rumuz arayarak yeni bir sohbet başlatabilirsiniz.'
                      : 'Farklı bir rumuz deneyin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.text.withValues(alpha: 0.45),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          )
        else
          ...(exactUser != null ? [exactUser] : filteredUsers).map(
            _contactResultCard,
          ),
      ],
    );
  }

  Widget _contactResultCard(String user) {
    final theme = ThemeController.instance.data;
    final online = _onlineUsers.any(
      (u) => u.toLowerCase() == user.toLowerCase(),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openPrivate(user),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                _avatar(user, online: online),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: online
                                  ? theme.primary
                                  : theme.text.withValues(alpha: 0.25),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            online ? 'Çevrimiçi' : 'Çevrimdışı',
                            style: TextStyle(
                              color: theme.text.withValues(alpha: 0.48),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Mesaj',
                  onPressed: () => _openPrivate(user),
                  icon: Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: theme.primary,
                    size: 20,
                  ),
                ),
                IconButton(
                  tooltip: 'Ara',
                  onPressed: online ? () => _call(user) : null,
                  icon: Icon(
                    Icons.call_rounded,
                    color: online
                        ? theme.primary
                        : theme.text.withValues(alpha: 0.22),
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCallsPage() {
    final theme = ThemeController.instance.data;

    final onlineUsers = _knownUsers
        .where(
          (user) => _onlineUsers.any(
            (online) => online.toLowerCase() == user.toLowerCase(),
          ),
        )
        .take(8)
        .toList();

    final recentUsers = _knownUsers.take(5).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
      children: [
        Text(
          'Çağrılar',
          style: TextStyle(
            color: theme.text,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Güvenli sesli görüşmelerinizi yönetin.',
          style: TextStyle(
            color: theme.text.withValues(alpha: 0.48),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 18),

        Material(
          color: theme.surface,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: theme.primary.withValues(alpha: 0.11),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.call_rounded,
                    color: theme.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Güvenli arama',
                        style: TextStyle(
                          color: theme.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'ZeroLog üzerinden sesli görüşme başlatın.',
                        style: TextStyle(
                          color: theme.text.withValues(alpha: 0.48),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.lock_rounded, size: 17, color: theme.primary),
              ],
            ),
          ),
        ),

        const SizedBox(height: 18),

        Text(
          'Hızlı arama',
          style: TextStyle(
            color: theme.text,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),

        if (onlineUsers.isEmpty)
          Material(
            color: theme.surface,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(
                    Icons.person_off_outlined,
                    color: theme.text.withValues(alpha: 0.32),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Şu anda çevrimiçi kişi bulunmuyor.',
                      style: TextStyle(
                        color: theme.text.withValues(alpha: 0.52),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...onlineUsers.map(
            (user) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: theme.surface,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _call(user),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        _avatar(user, online: true),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.text,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: theme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Çevrimiçi',
                                    style: TextStyle(
                                      color: theme.text.withValues(alpha: 0.46),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: theme.primary.withValues(alpha: 0.10),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.call_rounded,
                            color: theme.primary,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

        if (recentUsers.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Kişiler',
            style: TextStyle(
              color: theme.text,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          ...recentUsers.map((user) {
            final online = _onlineUsers.any(
              (onlineUser) => onlineUser.toLowerCase() == user.toLowerCase(),
            );

            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Material(
                color: theme.surface,
                borderRadius: BorderRadius.circular(18),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 2,
                  ),
                  leading: _avatar(user, online: online),
                  title: Text(
                    user,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    online ? 'Çevrimiçi' : 'Çevrimdışı',
                    style: TextStyle(
                      color: theme.text.withValues(alpha: 0.43),
                      fontSize: 12,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Ara',
                    onPressed: online ? () => _call(user) : null,
                    icon: Icon(
                      Icons.call_outlined,
                      color: online
                          ? theme.primary
                          : theme.text.withValues(alpha: 0.20),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildSettingsPage() {
    final theme = ThemeController.instance.data;

    Widget sectionTitle(String text) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 9),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            color: theme.text.withValues(alpha: 0.42),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      );
    }

    Widget tile({
      required IconData icon,
      required String title,
      String? subtitle,
      VoidCallback? onTap,
      Widget? trailing,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Material(
          color: theme.surface,
          borderRadius: BorderRadius.circular(19),
          child: InkWell(
            borderRadius: BorderRadius.circular(19),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(
                      color: theme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: theme.primary, size: 21),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: theme.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.text.withValues(alpha: 0.45),
                              fontSize: 11.5,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  trailing ??
                      Icon(
                        Icons.chevron_right_rounded,
                        color: theme.text.withValues(alpha: 0.28),
                      ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
      children: [
        Material(
          color: theme.surface,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: _openProfileEditor,
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Row(
                children: [
                  Stack(
                    children: [
                      _profileAvatar(radius: 25),
                      Positioned(
                        right: 0,
                        bottom: 1,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.background,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _profileAbout.trim().isEmpty
                              ? 'Profilini düzenle'
                              : _profileAbout.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.text.withValues(alpha: 0.48),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.edit_outlined,
                    color: theme.text.withValues(alpha: 0.32),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        Row(
          children: [
            Expanded(
              child: _profileSummaryCard(
                icon: Icons.verified_user_outlined,
                title: 'Hesap',
                value: 'ZeroLog hesabı',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _profileSummaryCard(
                icon: Icons.info_outline_rounded,
                title: 'Hakkında',
                value: _profileAbout.trim().isEmpty
                    ? 'Eklenmedi'
                    : 'Düzenlendi',
              ),
            ),
          ],
        ),

        sectionTitle('Görünüm'),

        tile(
          icon: Icons.palette_outlined,
          title: 'Tema',
          subtitle: zeroLogThemes[ThemeController.instance.current]!.name,
          onTap: () async {
            await showModalBottomSheet<void>(
              context: context,
              backgroundColor: theme.surface,
              showDragHandle: true,
              builder: (sheetContext) {
                return SafeArea(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      Text(
                        'Tema seç',
                        style: TextStyle(
                          color: theme.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...ZeroLogTheme.values.map((value) {
                        final selected =
                            ThemeController.instance.current == value;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          leading: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: zeroLogThemes[value]!.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          title: Text(
                            zeroLogThemes[value]!.name,
                            style: TextStyle(
                              color: theme.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          trailing: selected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: theme.primary,
                                )
                              : null,
                          onTap: () async {
                            await ThemeController.instance.setTheme(value);
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                            if (mounted) {
                              setState(() {});
                            }
                          },
                        );
                      }),
                    ],
                  ),
                );
              },
            );
          },
        ),

        tile(
          icon: Icons.notifications_none_rounded,
          title: 'Bildirimler',
          subtitle: 'Mesaj ve çağrı bildirimlerini yönet',
          onTap: _openNotificationSettings,
        ),

        tile(
          icon: Icons.shield_outlined,
          title: 'Gizlilik',
          subtitle: 'Çevrimiçi görünürlüğü ve özel mesajları yönet',
          onTap: _openPrivacySettings,
        ),

        sectionTitle('Uygulama'),

        tile(
          icon: Icons.tune_rounded,
          title: 'Sohbet tercihleri',
          subtitle: 'Mesajlaşma ve sohbet davranışlarını düzenle',
          onTap: _openChatPreferences,
        ),

        tile(
          icon: Icons.storage_outlined,
          title: 'Depolama ve veriler',
          subtitle: 'Profil ve yerel uygulama verilerini yönet',
          onTap: () async {
            final prefs = await SharedPreferences.getInstance();

            if (!mounted) return;

            await showModalBottomSheet<void>(
              context: context,
              backgroundColor: theme.surface,
              showDragHandle: true,
              builder: (sheetContext) {
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Depolama ve veriler',
                          style: TextStyle(
                            color: theme.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'ZeroLog bu cihazda tuttuğu yerel tercihleri burada yönetir.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.text.withValues(alpha: 0.48),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ListTile(
                          leading: Icon(
                            Icons.account_circle_outlined,
                            color: theme.primary,
                          ),
                          title: const Text('Profil verileri'),
                          subtitle: Text(
                            (_profilePhotoPath != null &&
                                        _profilePhotoPath!.isNotEmpty) ||
                                    _profileAbout.trim().isNotEmpty
                                ? 'Profil bilgileri kayıtlı'
                                : 'Ek profil verisi bulunmuyor',
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.cleaning_services_outlined),
                          title: const Text('Profil verilerini temizle'),
                          subtitle: const Text(
                            'Profil fotoğrafı ve hakkında bilgisini kaldır',
                          ),
                          onTap: () async {
                            final confirmed = await showDialog<bool>(
                              context: sheetContext,
                              builder: (dialogContext) {
                                return AlertDialog(
                                  title: const Text(
                                    'Profil verileri silinsin mi?',
                                  ),
                                  content: const Text(
                                    'Profil fotoğrafı ve hakkında bilgisi '
                                    'bu cihazdan kaldırılacak.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, false),
                                      child: const Text('İptal'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, true),
                                      child: const Text('Temizle'),
                                    ),
                                  ],
                                );
                              },
                            );

                            if (confirmed != true) return;

                            await prefs.remove(_profilePhotoKey);
                            await prefs.remove(_profileAboutKey);

                            if (!mounted) return;

                            setState(() {
                              _profilePhotoPath = null;
                              _profileAbout = '';
                            });

                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Profil verileri temizlendi.'),
                                ),
                              );
                            }
                          },
                        ),
                        ListTile(
                          leading: const Icon(
                            Icons.settings_backup_restore_rounded,
                          ),
                          title: const Text('Sohbet tercihlerini sıfırla'),
                          subtitle: const Text(
                            'Mesajlaşma ayarlarını varsayılana döndür',
                          ),
                          onTap: () async {
                            await prefs.remove('zerolog.chat.enter_to_send');
                            await prefs.remove('zerolog.chat.message_preview');
                            await prefs.remove('zerolog.chat.auto_focus');

                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Sohbet tercihleri sıfırlandı.',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),

        tile(
          icon: Icons.info_outline_rounded,
          title: 'ZeroLog hakkında',
          subtitle: 'Sürüm, geliştirici ve uygulama bilgileri',
          onTap: _openAboutPage,
        ),

        tile(
          icon: Icons.menu_book_outlined,
          title: 'Açık kaynak lisansları',
          subtitle: 'ZeroLog içinde kullanılan açık kaynak bileşenler',
          onTap: () {
            showLicensePage(
              context: context,
              applicationName: 'ZeroLog',
              applicationVersion: '1.0.6',
              applicationLegalese:
                  'Bu program BerkanCVS tarafından hazırlanmıştır.',
            );
          },
        ),

        const SizedBox(height: 18),

        Center(
          child: Text(
            'ZeroLog • Güvenli iletişim',
            style: TextStyle(
              color: theme.text.withValues(alpha: 0.28),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  void _openAboutPage() {
    final theme = ThemeController.instance.data;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) {
          return Scaffold(
            backgroundColor: theme.background,
            appBar: AppBar(
              backgroundColor: theme.background,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              title: const Text('ZeroLog hakkında'),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: theme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.shield_rounded,
                      color: theme.primary,
                      size: 46,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Text(
                    'ZeroLog',
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'Güvenli iletişim',
                    style: TextStyle(
                      color: theme.text.withValues(alpha: 0.48),
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                Material(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Uygulama hakkında',
                          style: TextStyle(
                            color: theme.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Bu program BerkanCVS tarafından hazırlanmıştır. '
                          'Yazılımda emeği geçen İlay Kayra’ya sonsuz '
                          'teşekkürlerimi sunarım.',
                          style: TextStyle(
                            color: theme.text.withValues(alpha: 0.62),
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Material(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(20),
                  child: ListTile(
                    leading: Icon(
                      Icons.system_update_outlined,
                      color: theme.primary,
                    ),
                    title: Text(
                      'Sürüm',
                      style: TextStyle(
                        color: theme.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'ZeroLog 1.0.6',
                      style: TextStyle(
                        color: theme.text.withValues(alpha: 0.48),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Material(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(20),
                  child: ListTile(
                    leading: Icon(
                      Icons.menu_book_outlined,
                      color: theme.primary,
                    ),
                    title: Text(
                      'Açık kaynak lisansları',
                      style: TextStyle(
                        color: theme.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'ZeroLog içinde kullanılan bileşenler',
                      style: TextStyle(
                        color: theme.text.withValues(alpha: 0.48),
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: theme.text.withValues(alpha: 0.28),
                    ),
                    onTap: () {
                      showLicensePage(
                        context: context,
                        applicationName: 'ZeroLog',
                        applicationVersion: '1.0.6',
                        applicationLegalese:
                            'Bu program BerkanCVS tarafından hazırlanmıştır.',
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _profileSummaryCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    final theme = ThemeController.instance.data;

    return Material(
      color: theme.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 13, 10, 13),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: theme.primary, size: 18),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: theme.text.withValues(alpha: 0.45),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsSectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = ThemeController.instance.data;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 14, 10, 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: theme.primary, size: 21),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: theme.text.withValues(alpha: 0.46),
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: theme.primary.withValues(alpha: 0.48),
              thumbColor: WidgetStatePropertyAll(theme.primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsInfoCard({
    required IconData icon,
    required String title,
    required String text,
  }) {
    final theme = ThemeController.instance.data;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.primary.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.primary.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.primary, size: 19),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  text,
                  style: TextStyle(
                    color: theme.text.withValues(alpha: 0.48),
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openChatPreferences() async {
    final theme = ThemeController.instance.data;
    final prefs = await SharedPreferences.getInstance();

    bool enterToSend = prefs.getBool('zerolog.chat.enter_to_send') ?? true;
    bool messagePreview = prefs.getBool('zerolog.chat.message_preview') ?? true;
    bool autoFocus = prefs.getBool('zerolog.chat.auto_focus') ?? true;

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (context, setPageState) {
            Future<void> save(String key, bool value) async {
              await prefs.setBool(key, value);
            }

            return Scaffold(
              backgroundColor: theme.background,
              appBar: AppBar(
                backgroundColor: theme.background,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                title: const Text('Sohbet tercihleri'),
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(
                    'Mesajlaşma deneyimi',
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Sohbet ekranının davranışını kullanımınıza göre ayarlayın.',
                    style: TextStyle(
                      color: theme.text.withValues(alpha: 0.46),
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _settingsSectionCard(
                    icon: Icons.keyboard_return_rounded,
                    title: 'Enter ile gönder',
                    subtitle: 'Klavyedeki Enter tuşu mesajı doğrudan göndersin',
                    value: enterToSend,
                    onChanged: (value) {
                      setPageState(() => enterToSend = value);
                      save('zerolog.chat.enter_to_send', value);
                    },
                  ),
                  _settingsSectionCard(
                    icon: Icons.visibility_outlined,
                    title: 'Bildirim önizlemesi',
                    subtitle: 'Mesaj bildirimlerinde mesaj içeriğini göster',
                    value: messagePreview,
                    onChanged: (value) {
                      setPageState(() => messagePreview = value);
                      save('zerolog.chat.message_preview', value);
                    },
                  ),
                  _settingsSectionCard(
                    icon: Icons.keyboard_alt_outlined,
                    title: 'Sohbet açıldığında klavye',
                    subtitle:
                        'Yeni sohbet açıldığında mesaj alanına otomatik odaklan',
                    value: autoFocus,
                    onChanged: (value) {
                      setPageState(() => autoFocus = value);
                      save('zerolog.chat.auto_focus', value);
                    },
                  ),
                  _settingsInfoCard(
                    icon: Icons.tune_rounded,
                    title: 'Tercihler cihazınızda saklanır',
                    text:
                        'Bu seçenekler uygulamayı yeniden açtığınızda korunur.',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _openNotificationSettings() {
    final theme = ThemeController.instance.data;

    var messageEnabled = _messageNotificationsEnabled;
    var callEnabled = _callNotificationsEnabled;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (context, setPageState) {
            return Scaffold(
              backgroundColor: theme.background,
              appBar: AppBar(
                backgroundColor: theme.background,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                title: const Text('Bildirimler'),
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                children: [
                  Text(
                    'Bildirim tercihleri',
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'ZeroLog size nasıl ulaşacağını kontrol edin.',
                    style: TextStyle(
                      color: theme.text.withValues(alpha: 0.46),
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 20),

                  _settingsSectionCard(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'Mesaj bildirimleri',
                    subtitle: 'Özel mesaj geldiğinde bildirim göster',
                    value: messageEnabled,
                    onChanged: (value) {
                      setPageState(() => messageEnabled = value);
                      _messageNotificationsEnabled = value;

                      WsClient.instance.setNotificationSettings(
                        messageNotificationsEnabled: value,
                      );
                    },
                  ),

                  _settingsSectionCard(
                    icon: Icons.call_outlined,
                    title: 'Çağrı bildirimleri',
                    subtitle: 'Gelen sesli çağrıları bildirim olarak göster',
                    value: callEnabled,
                    onChanged: (value) {
                      setPageState(() => callEnabled = value);
                      _callNotificationsEnabled = value;

                      WsClient.instance.setNotificationSettings(
                        callNotificationsEnabled: value,
                      );
                    },
                  ),

                  _settingsInfoCard(
                    icon: Icons.lock_outline_rounded,
                    title: 'Bildirimler güvenli şekilde yönetilir',
                    text:
                        'Tercihleriniz ZeroLog hesabınızla senkronize edilir. '
                        'Çağrı bildirimleri kilit ekranında da gösterilebilir.',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    WsClient.instance.requestNotificationSettings();
  }

  void _openPrivacySettings() {
    final theme = ThemeController.instance.data;

    var presenceVisible = _presenceVisible;
    var privateMessagesEnabled = _privateMessagesEnabled;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (context, setPageState) {
            return Scaffold(
              backgroundColor: theme.background,
              appBar: AppBar(
                backgroundColor: theme.background,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                title: const Text('Gizlilik'),
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                children: [
                  Text(
                    'Gizlilik ve güvenlik',
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Kimlerin sizi görebileceğini ve size ulaşabileceğini seçin.',
                    style: TextStyle(
                      color: theme.text.withValues(alpha: 0.46),
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 20),

                  _settingsSectionCard(
                    icon: Icons.visibility_outlined,
                    title: 'Çevrimiçi durum',
                    subtitle: 'Çevrimiçi olduğunuzu diğer kullanıcılar görsün',
                    value: presenceVisible,
                    onChanged: (value) {
                      setPageState(() => presenceVisible = value);
                      _presenceVisible = value;

                      WsClient.instance.setPrivacySettings(
                        presenceVisible: value,
                      );
                    },
                  ),

                  _settingsSectionCard(
                    icon: Icons.lock_outline_rounded,
                    title: 'Özel mesajlar',
                    subtitle:
                        'Diğer kullanıcıların size mesaj göndermesine izin ver',
                    value: privateMessagesEnabled,
                    onChanged: (value) {
                      setPageState(() => privateMessagesEnabled = value);
                      _privateMessagesEnabled = value;

                      WsClient.instance.setPrivacySettings(
                        privateMessagesEnabled: value,
                      );
                    },
                  ),

                  const SizedBox(height: 8),

                  Material(
                    color: theme.surface,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _deleteAccount(allData: true),
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: theme.text.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                Icons.delete_outline_rounded,
                                color: theme.text.withValues(alpha: 0.62),
                              ),
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Verilerimi sil',
                                    style: TextStyle(
                                      color: theme.text,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Hesap ve kayıtları kalıcı olarak yönet',
                                    style: TextStyle(
                                      color: theme.text.withValues(alpha: 0.45),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: theme.text.withValues(alpha: 0.30),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  _settingsInfoCard(
                    icon: Icons.shield_outlined,
                    title: 'Kontrol sizde',
                    text:
                        'Gizlilik tercihleri hesabınıza kaydedilir. '
                        'Çevrimiçi durumunu kapattığınızda diğer kullanıcılar '
                        'sizi çevrimiçi listesinde göremez.',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    WsClient.instance.requestPrivacySettings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.instance.data;

    final pages = [
      _buildChatsPage(),
      _buildContactsPage(),
      _buildCallsPage(),
      _buildSettingsPage(),
    ];

    const titles = ['Sohbetler', 'Kişiler', 'Çağrılar', 'Ayarlar'];

    const selectedIcons = [
      Icons.chat_bubble_rounded,
      Icons.people_rounded,
      Icons.call_rounded,
      Icons.settings_rounded,
    ];

    const unselectedIcons = [
      Icons.chat_bubble_outline_rounded,
      Icons.people_outline_rounded,
      Icons.call_outlined,
      Icons.settings_outlined,
    ];

    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 13),
              decoration: BoxDecoration(
                color: theme.background,
                border: Border(
                  bottom: BorderSide(color: theme.text.withValues(alpha: 0.06)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titles[_selectedIndex],
                          style: TextStyle(
                            color: theme.text,
                            fontSize: 26,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                          ),
                        ),
                        if (_selectedIndex == 0) ...[
                          const SizedBox(height: 5),
                          Text(
                            'Özel ve güvenli iletişim',
                            style: TextStyle(
                              color: theme.text.withValues(alpha: 0.48),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: theme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.text.withValues(alpha: 0.07),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        widget.nickname.isEmpty
                            ? 'Z'
                            : widget.nickname.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          color: theme.primary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(index: _selectedIndex, children: pages),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: theme.surface,
          border: Border(
            top: BorderSide(color: theme.text.withValues(alpha: 0.06)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
            child: Row(
              children: List.generate(4, (index) {
                final selected = _selectedIndex == index;

                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (_selectedIndex == index) return;

                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? theme.primary.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            selected
                                ? selectedIcons[index]
                                : unselectedIcons[index],
                            size: 22,
                            color: selected
                                ? theme.primary
                                : theme.text.withValues(alpha: 0.48),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            titles[index],
                            style: TextStyle(
                              color: selected
                                  ? theme.primary
                                  : theme.text.withValues(alpha: 0.48),
                              fontSize: 10,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
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
  final FocusNode _messageFocusNode = FocusNode();

  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];

  late final StreamSubscription<Map<String, dynamic>> _subscription;

  @override
  void initState() {
    super.initState();

    _subscription = WsClient.instance.events.listen(_handleEvent);

    WsClient.instance.joinRoom(widget.roomName);
    _applyAutoFocusPreference();
  }

  Future<void> _applyAutoFocusPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final autoFocus = prefs.getBool('zerolog.chat.auto_focus') ?? true;

    if (!autoFocus || !mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _messageFocusNode.requestFocus();
    });
  }

  Future<void> _handleEvent(Map<String, dynamic> data) async {
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
      _scrollToBottom();

      // Android klavyeyi açtıktan sonra viewInsets/layout yeniden hesaplanır.
      // Bu ikinci scroll, son mesajın klavye altında kalmasını engeller.
      Future.delayed(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        _scrollToBottom();
      });
    });
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;

    _scrollController.animateTo(
      position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
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
    _messageFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.instance.data;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.tag_rounded, color: theme.primary, size: 21),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.roomName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Topluluk odası',
                    style: TextStyle(
                      color: theme.text.withValues(alpha: 0.42),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.forum_outlined,
                            size: 46,
                            color: theme.text.withValues(alpha: 0.24),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Oda henüz boş',
                            style: TextStyle(
                              color: theme.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'İlk mesajı siz gönderin.',
                            style: TextStyle(
                              color: theme.text.withValues(alpha: 0.45),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
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
                          constraints: const BoxConstraints(maxWidth: 330),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                          decoration: BoxDecoration(
                            color: mine ? theme.bubbleMine : theme.bubbleOther,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(mine ? 18 : 5),
                              bottomRight: Radius.circular(mine ? 5 : 18),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!mine) ...[
                                Text(
                                  message.sender,
                                  style: TextStyle(
                                    color: theme.primary,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                              ],
                              Text(
                                message.text,
                                style: TextStyle(
                                  color: theme.text,
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
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
            focusNode: _messageFocusNode,
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
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final FocusNode _messageFocusNode = FocusNode();

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

    _applyAutoFocusPreference();
  }

  Future<void> _applyAutoFocusPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final autoFocus = prefs.getBool('zerolog.chat.auto_focus') ?? true;

    if (!autoFocus || !mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _messageFocusNode.requestFocus();
    });
  }

  Future<void> _handleEvent(Map<String, dynamic> data) async {
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
        final historyMessages = <ChatMessage>[];

        for (final item in list) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);

            final messageId = (map['id'] ?? '').toString();
            final clientMessageId =
                (map['clientMessageId'] ?? '').toString();

            final sender = (map['sender'] ?? map['from'] ?? '').toString();

            final messageStatus =
                sender.toLowerCase() == widget.myNick.toLowerCase()
                    ? ((map['read'] == true)
                        ? 'read'
                        : (map['delivered'] == true)
                            ? 'delivered'
                            : 'stored')
                    : 'read';

            final message = ChatMessage(
              id:
                  (messageId.isNotEmpty
                          ? messageId
                          : (clientMessageId.isNotEmpty
                              ? clientMessageId
                              : 'private-legacy-${map['ts'] ?? ''}-$sender-${map['to'] ?? ''}-${map['text'] ?? ''}'))
                      .toString(),
              sender: sender,
              text: (map['text'] ?? '').toString(),
              clientMessageId: clientMessageId,
              status: messageStatus,
            );

            if (message.text.isEmpty) continue;

            final exists = _messages.any(
              (m) => m.id == message.id,
            );

            if (!exists) {
              historyMessages.add(message);
            }
          }
        }

        if (historyMessages.isNotEmpty && mounted) {
          setState(() {
            _messages.addAll(historyMessages);
          });

          // Geçmiş mesajları animasyonla tek tek akıtma.
          // Liste doğrudan son mesaja konumlanır.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_scrollController.hasClients) return;

            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          });
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

    if (data['type'] == 'messageRead') {
      final messageId = (data['messageId'] ?? '').toString();
      final clientMessageId =
          (data['clientMessageId'] ?? '').toString();

      if (messageId.isEmpty && clientMessageId.isEmpty) {
        return;
      }

      if (!mounted) return;

      setState(() {
        for (var i = 0; i < _messages.length; i++) {
          final message = _messages[i];

          final matches =
              (clientMessageId.isNotEmpty &&
                  message.clientMessageId == clientMessageId) ||
              (messageId.isNotEmpty &&
                  message.id == messageId);

          if (matches) {
            _messages[i] = message.copyWith(
              id: messageId.isNotEmpty ? messageId : message.id,
              clientMessageId: clientMessageId.isNotEmpty
                  ? clientMessageId
                  : message.clientMessageId,
              status: 'read',
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

            final sender =
                (map['sender'] ?? map['from'] ?? '').toString();
            final target =
                (map['to'] ?? map['target'] ?? '').toString();

            if (sender.toLowerCase() !=
                    widget.targetNick.toLowerCase() ||
                target.toLowerCase() != widget.myNick.toLowerCase()) {
              continue;
            }

            final messageId = (map['id'] ?? '').toString();
            final clientMessageId =
                (map['clientMessageId'] ?? '').toString();

            _addMessage(
              ChatMessage(
                id:
                    (messageId.isNotEmpty
                            ? messageId
                            : (clientMessageId.isNotEmpty
                                ? clientMessageId
                                : 'pending-${map['ts'] ?? ''}-$sender-${map['text'] ?? ''}'))
                        .toString(),
                sender: sender,
                text: (map['text'] ?? '').toString(),
                clientMessageId: clientMessageId,
                status: 'read',
              ),
            );

            // Offline gelen mesaj sohbet ekranında gösterildiği anda
            // teslim edilmiş ve okunmuş kabul edilir.
            WsClient.instance.send({
              'type': 'messageDelivered',
              'from': sender,
              'messageId': messageId,
              'clientMessageId': clientMessageId,
            });

            WsClient.instance.send({
              'type': 'messageRead',
              'from': sender,
              'messageId': messageId,
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

      // Aktif özel sohbet açık olduğu için mesaj hem teslim
      // hem de okunmuş kabul edilir.
      if (sender.toLowerCase() == widget.targetNick.toLowerCase()) {
        final messageId = (data['id'] ?? '').toString();

        WsClient.instance.send({
          'type': 'messageDelivered',
          'from': sender,
          'messageId': messageId,
          'clientMessageId': clientMessageId,
        });

        WsClient.instance.send({
          'type': 'messageRead',
          'from': sender,
          'messageId': messageId,
          'clientMessageId': clientMessageId,
        });
      }
    }
  }

  void _addMessage(ChatMessage message) {
    if (message.text.isEmpty) return;

    final exists = _messages.any(
      (m) =>
          m.id == message.id ||
          (message.clientMessageId.isNotEmpty &&
              m.clientMessageId.isNotEmpty &&
              m.clientMessageId == message.clientMessageId),
    );

    if (exists) return;

    setState(() {
      _messages.add(message);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );

      // Klavye açıkken Android'in yeniden layout hesaplamasını bekle.
      Future.delayed(const Duration(milliseconds: 120), () {
        if (!_scrollController.hasClients) return;

        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      });
    });
  }

  void _send() {
    final text = _controller.text.trim();

    if (text.isEmpty) return;

    final clientMessageId =
        '${DateTime.now().microsecondsSinceEpoch}-${widget.myNick}-${widget.targetNick}';

    // Mesajı sunucudan geri gelmesini beklemeden gönderen ekranda göster.
    // clientMessageId sayesinde daha sonra gelen messageAck aynı mesajı günceller.
    _addMessage(
      ChatMessage(
        id: clientMessageId,
        sender: widget.myNick,
        text: text,
        clientMessageId: clientMessageId,
        status: 'sending',
      ),
    );

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
    _messageFocusNode.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.instance.data;
    final online = WsClient.instance.onlineUsers.any(
      (u) => u.toLowerCase() == widget.targetNick.toLowerCase(),
    );

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            _chatAvatar(widget.targetNick, online: online),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.targetNick,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    online ? 'Çevrimiçi' : 'Çevrimdışı',
                    style: TextStyle(
                      color: online
                          ? theme.primary
                          : theme.text.withValues(alpha: 0.42),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sesli ara',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CallScreen(
                    myNick: widget.myNick,
                    targetNick: widget.targetNick,
                    outgoing: true,
                  ),
                ),
              );
            },
            icon: Icon(Icons.call_rounded, color: theme.primary),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _emptyPrivateChat(theme)
                : ListView.builder(
                    controller: _scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                    itemCount: _messages.length,
                    itemBuilder: (_, index) {
                      final message = _messages[index];
                      final mine =
                          message.sender.toLowerCase() ==
                          widget.myNick.toLowerCase();

                      return _modernMessageBubble(
                        message,
                        mine: mine,
                        theme: theme,
                      );
                    },
                  ),
          ),
          MessageInput(
            controller: _controller,
            onSend: _send,
            focusNode: _messageFocusNode,
          ),
        ],
      ),
    );
  }

  Widget _chatAvatar(String name, {required bool online}) {
    final theme = ThemeController.instance.data;
    final letter = name.trim().isEmpty
        ? '?'
        : name.trim().substring(0, 1).toUpperCase();

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: theme.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              letter,
              style: TextStyle(
                color: theme.primary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: online ? theme.primary : theme.text.withValues(alpha: 0.22),
            shape: BoxShape.circle,
            border: Border.all(color: theme.background, width: 2),
          ),
        ),
      ],
    );
  }

  Widget _emptyPrivateChat(ZeroLogThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: theme.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 34,
                color: theme.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Özel sohbet',
              style: TextStyle(
                color: theme.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              '${widget.targetNick} ile güvenli şekilde mesajlaşmaya başlayın.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.text.withValues(alpha: 0.48),
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modernMessageBubble(
    ChatMessage message, {
    required bool mine,
    required ZeroLogThemeData theme,
  }) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 9),
        decoration: BoxDecoration(
          color: mine ? theme.bubbleMine : theme.bubbleOther,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 5),
            bottomRight: Radius.circular(mine ? 5 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!mine) ...[
              Text(
                message.sender,
                style: TextStyle(
                  color: theme.primary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
            ],
            Text(
              message.text,
              style: TextStyle(color: theme.text, fontSize: 14, height: 1.35),
            ),
            if (mine && message.status.isNotEmpty) ...[
              const SizedBox(height: 3),
              Icon(
                message.status == 'read'
                    ? Icons.done_all_rounded
                    : message.status == 'delivered'
                        ? Icons.done_all_rounded
                        : Icons.done_rounded,
                size: 14,
                color: message.status == 'read'
                    ? theme.primary
                    : theme.primary.withValues(alpha: 0.78),
              ),
            ],
          ],
        ),
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
  final String? callId;
  final String? incomingOffer;

  const CallScreen({
    super.key,
    required this.myNick,
    required this.targetNick,
    required this.outgoing,
    this.callId,
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

  Timer? _outgoingTimeoutTimer;

  StreamSubscription<int>? _proximitySubscription;
  bool _proximityScreenOffEnabled = false;

  Future<void> _initProximitySensor() async {
    if (_proximitySubscription != null ||
        _proximityScreenOffEnabled ||
        _closing ||
        !mounted) {
      return;
    }

    try {
      // Proximity ekran kontrolünü yalnızca aktif aramada başlat.
      await ProximitySensor.setProximityScreenOff(true);

      if (!mounted || _closing) {
        try {
          await ProximitySensor.setProximityScreenOff(false);
        } catch (_) {}
        return;
      }

      _proximityScreenOffEnabled = true;

      _proximitySubscription = ProximitySensor.events.listen((value) {
        if (!mounted || _closing) return;

        // 0 = uzak, >0 = yakın.
        // Ekran kontrolünü proximity_sensor'ın kendi mekanizması yapar.
        final isNear = value > 0;

        if (isNear) {
          // Telefon kulağa yaklaştırıldı.
        } else {
          // Telefon kulaktan uzaklaştırıldı.
        }
      });
    } catch (_) {}
  }

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
          'callId': widget.callId,
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

    // Mikrofon iznini ve proximity sensörünü çağrı tuşuna
    // basıldığı anda hazırla. Karşı tarafın cevap vermesini bekleme.
    final microphoneGranted = await ZeroLogPushService.requestCallPermissions();

    if (!microphoneGranted) {
      if (mounted && !_closing) {
        _showError('Mikrofon izni gerekli.');
      }
      return;
    }

    if (!_closing && mounted) {
      await _initProximitySensor();
    }

    await ZeroLogPushService.startOutgoingCallTone();

    final callId = widget.callId;
    if (callId == null || callId.isEmpty) {
      if (mounted) {
        _showError('Arama kimliği oluşturulamadı.');
      }
      return;
    }

    WsClient.instance.send({
      'type': 'callInvite',
      'from': widget.myNick,
      'to': widget.targetNick,
      'callId': callId,
    });

    _outgoingTimeoutTimer?.cancel();
    _outgoingTimeoutTimer = Timer(const Duration(seconds: 60), () {
      if (_closing || !widget.outgoing) return;

      ZeroLogPushService.stopOutgoingCallTone();

      WsClient.instance.send({
        'type': 'callTimeout',
        'from': widget.myNick,
        'to': widget.targetNick,
        'callId': widget.callId,
      });

      if (mounted) {
        _showError('Cevap yok. Arama sonlandırıldı.');
      }

      _finish(sendSignal: false);
    });
  }

  Future<void> _startOutgoingOffer() async {
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
        'callId': widget.callId,
        'sdp': offer.sdp,
      });

      if (mounted) {
        setState(() {
          _accepted = true;
        });

        await _initProximitySensor();
      }
    } catch (_) {
      if (mounted && !_closing) {
        _showError('Arama başlatılamadı.');
      }
    }
  }

  Future<void> _acceptIncoming() async {
    if (_closing) return;

    final granted = await ZeroLogPushService.requestCallPermissions();

    if (!granted) {
      if (mounted) {
        _showError('Arama için mikrofon izni gerekiyor.');
      }
      await _finish(sendSignal: false);
      return;
    }

    final incomingOffer = widget.incomingOffer;

    try {
      if (incomingOffer == null || incomingOffer.isEmpty) {
        WsClient.instance.send({
          'type': 'callAccept',
          'from': widget.myNick,
          'to': widget.targetNick,
          'callId': widget.callId,
        });

        if (mounted) {
          setState(() {
            _accepted = true;
          });

          await _initProximitySensor();
        }

        await ZeroLogPushService.cancelIncomingCallNotification();
        return;
      }

      await _handleIncomingOffer(incomingOffer);
    } catch (_) {
      if (mounted && !_closing) {
        _showError('Arama kabul edilemedi.');
      }
    }
  }

  Future<void> _handleIncomingOffer(String incomingOffer) async {
    if (_closing) return;

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
        'callId': widget.callId,
        'sdp': answer.sdp,
      });

      if (mounted) {
        setState(() {
          _accepted = true;
        });

        await _initProximitySensor();
      }

      await ZeroLogPushService.cancelIncomingCallNotification();
    } catch (_) {
      if (mounted && !_closing) {
        _showError('Arama kabul edilemedi.');
      }
    }
  }

  Future<void> _handleEvent(Map<String, dynamic> data) async {
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

    if (type == 'callAccepted') {
      ZeroLogPushService.clearPendingCall();
      ZeroLogPushService.cancelIncomingCallNotification();
      ZeroLogPushService.clearCallLockScreen();
      if (widget.outgoing) {
        _outgoingTimeoutTimer?.cancel();
        _outgoingTimeoutTimer = null;

        await ZeroLogPushService.stopOutgoingCallTone();

        _startOutgoingOffer();
      }
    } else if (type == 'callRejected') {
      ZeroLogPushService.clearPendingCall();
      ZeroLogPushService.cancelIncomingCallNotification();
      ZeroLogPushService.clearCallLockScreen();
      _outgoingTimeoutTimer?.cancel();
      _outgoingTimeoutTimer = null;

      await ZeroLogPushService.stopOutgoingCallTone();

      if (mounted) {
        _showError('Arama reddedildi.');
      }

      await Future.delayed(const Duration(milliseconds: 700));

      if (!_closing) {
        _finish(sendSignal: false);
      }
    } else if (type == 'callAnswer') {
      _handleAnswer(data);
    } else if (type == 'callOffer') {
      if (!widget.outgoing && _accepted) {
        final sdp = data['sdp']?.toString();

        if (sdp != null && sdp.isNotEmpty) {
          _handleIncomingOffer(sdp);
        }
      }
    } else if (type == 'callIce') {
      _handleIceCandidate(data);
    } else if (type == 'callTimeout') {
      ZeroLogPushService.clearPendingCall();
      ZeroLogPushService.cancelIncomingCallNotification();
      ZeroLogPushService.clearCallLockScreen();
      _outgoingTimeoutTimer?.cancel();
      _outgoingTimeoutTimer = null;

      await ZeroLogPushService.stopOutgoingCallTone();

      if (!_closing) {
        _finish(sendSignal: false);
      }
    } else if (type == 'callEnded') {
      ZeroLogPushService.clearPendingCall();
      ZeroLogPushService.cancelIncomingCallNotification();
      ZeroLogPushService.clearCallLockScreen();
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
      'type': 'callReject',
      'from': widget.myNick,
      'to': widget.targetNick,
      'callId': widget.callId,
    });

    _finish(sendSignal: false);
  }

  Future<void> _finish({bool sendSignal = true}) async {
    if (_closing) return;

    _closing = true;

    _outgoingTimeoutTimer?.cancel();
    _outgoingTimeoutTimer = null;

    await ZeroLogPushService.stopOutgoingCallTone();
    await ZeroLogPushService.cancelIncomingCallNotification();
    await ZeroLogPushService.clearCallLockScreen();

    await _proximitySubscription?.cancel();
    _proximitySubscription = null;

    if (_proximityScreenOffEnabled) {
      try {
        await ProximitySensor.setProximityScreenOff(false);
      } catch (_) {}
      _proximityScreenOffEnabled = false;
    }

    if (sendSignal) {
      WsClient.instance.send({
        'type': 'callEnd',
        'from': widget.myNick,
        'to': widget.targetNick,
        'callId': widget.callId,
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
    _outgoingTimeoutTimer?.cancel();
    _outgoingTimeoutTimer = null;

    ZeroLogPushService.stopOutgoingCallTone();
    ZeroLogPushService.clearCallLockScreen();

    _subscription.cancel();
    _proximitySubscription?.cancel();

    if (_proximityScreenOffEnabled) {
      ProximitySensor.setProximityScreenOff(false);
      _proximityScreenOffEnabled = false;
    }

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
    final theme = ThemeController.instance.data;
    final waitingIncoming = !widget.outgoing && !_accepted;

    final status = waitingIncoming
        ? 'Gelen çağrı'
        : _connected
        ? 'Bağlandı'
        : widget.outgoing
        ? 'Aranıyor…'
        : 'Bağlanıyor…';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        backgroundColor: theme.background,
        appBar: AppBar(
          backgroundColor: theme.background,
          elevation: 0,
          automaticallyImplyLeading: false,
          centerTitle: true,
          title: Text(
            'Şifreli Bağlantı',
            style: TextStyle(
              color: theme.text,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              children: [
                const Spacer(),

                Container(
                  width: 116,
                  height: 116,
                  decoration: BoxDecoration(
                    color: theme.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.primary.withValues(alpha: 0.18),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: theme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          widget.targetNick.isEmpty
                              ? '?'
                              : widget.targetNick
                                    .trim()
                                    .substring(0, 1)
                                    .toUpperCase(),
                          style: TextStyle(
                            color: theme.primary,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  widget.targetNick,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),

                const SizedBox(height: 9),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _connected
                            ? theme.primary
                            : theme.text.withValues(alpha: 0.30),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      status,
                      style: TextStyle(
                        color: theme.text.withValues(alpha: 0.52),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 38),

                if (waitingIncoming)
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 56,
                          child: FilledButton.icon(
                            onPressed: _acceptIncoming,
                            icon: const Icon(Icons.call_rounded),
                            label: const Text(
                              'Kabul Et',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 56,
                          child: FilledButton.tonalIcon(
                            onPressed: _reject,
                            icon: const Icon(Icons.call_end_rounded),
                            label: const Text(
                              'Reddet',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _callControl(
                        theme,
                        icon: _muted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        label: _muted ? 'Sessiz' : 'Mikrofon',
                        active: _muted,
                        onTap: _toggleMute,
                      ),
                      const SizedBox(width: 16),
                      _callControl(
                        theme,
                        icon: _speakerOn
                            ? Icons.volume_up_rounded
                            : Icons.volume_down_rounded,
                        label: _speakerOn ? 'Hoparlör' : 'Kulaklık',
                        active: _speakerOn,
                        onTap: _toggleSpeaker,
                      ),
                      const SizedBox(width: 16),
                      _callControl(
                        theme,
                        icon: Icons.call_end_rounded,
                        label: 'Bitir',
                        destructive: true,
                        onTap: _finish,
                      ),
                    ],
                  ),

                const Spacer(),

                if (!waitingIncoming)
                  Text(
                    _connected
                        ? 'Görüşme güvenli bağlantı üzerinden devam ediyor.'
                        : 'Bağlantı kuruluyor, lütfen bekleyin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.text.withValues(alpha: 0.32),
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _callControl(
    ZeroLogThemeData theme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    bool destructive = false,
  }) {
    final foreground = destructive
        ? theme.text
        : active
        ? theme.primary
        : theme.text;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: destructive
              ? theme.text.withValues(alpha: 0.12)
              : active
              ? theme.primary.withValues(alpha: 0.14)
              : theme.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 58,
              height: 58,
              child: Icon(icon, color: foreground, size: 23),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          style: TextStyle(
            color: theme.text.withValues(alpha: 0.46),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// INPUT
// ============================================================

class MessageInput extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final FocusNode? focusNode;

  const MessageInput({
    super.key,
    required this.controller,
    required this.onSend,
    this.focusNode,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  bool _enterToSend = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      _enterToSend = prefs.getBool('zerolog.chat.enter_to_send') ?? true;
    });
  }

  void _handleSubmitted(String value) {
    if (!_enterToSend) return;
    if (value.trim().isEmpty) return;

    widget.onSend();
  }

  Future<void> _openAttachmentMenu() async {
    final theme = ThemeController.instance.data;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.surface,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Ek seçenekler',
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: Icon(
                    Icons.photo_library_outlined,
                    color: theme.primary,
                  ),
                  title: const Text('Galeri'),
                  subtitle: const Text('Galeriden fotoğraf seç'),
                  onTap: () async {
                    Navigator.pop(sheetContext);

                    final picker = ImagePicker();

                    await picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 1600,
                      maxHeight: 1600,
                      imageQuality: 88,
                    );
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.camera_alt_outlined,
                    color: theme.primary,
                  ),
                  title: const Text('Kamera'),
                  subtitle: const Text('Kamera ile fotoğraf çek'),
                  onTap: () async {
                    Navigator.pop(sheetContext);

                    final picker = ImagePicker();

                    await picker.pickImage(
                      source: ImageSource.camera,
                      maxWidth: 1600,
                      maxHeight: 1600,
                      imageQuality: 88,
                    );
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.emoji_emotions_outlined,
                    color: theme.primary,
                  ),
                  title: const Text('Emoji'),
                  subtitle: const Text('Mesaja emoji ekle'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openEmojiPicker();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openEmojiPicker() async {
    final theme = ThemeController.instance.data;

    const emojis = [
      '😀',
      '😂',
      '😍',
      '🥰',
      '😎',
      '🤔',
      '😢',
      '😡',
      '👍',
      '👎',
      '❤️',
      '🔥',
      '🎉',
      '👏',
      '🙏',
      '💯',
      '🚀',
      '🔒',
      '😊',
      '😉',
      '😄',
      '😁',
      '🤣',
      '😇',
    ];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.surface,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: GridView.builder(
              shrinkWrap: true,
              itemCount: emojis.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemBuilder: (_, index) {
                final emoji = emojis[index];

                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    final value = widget.controller.text;
                    final selection = widget.controller.selection;

                    final start = selection.start >= 0
                        ? selection.start
                        : value.length;
                    final end = selection.end >= 0
                        ? selection.end
                        : value.length;

                    final newText = value.replaceRange(start, end, emoji);

                    widget.controller.value = TextEditingValue(
                      text: newText,
                      selection: TextSelection.collapsed(
                        offset: start + emoji.length,
                      ),
                    );

                    Navigator.pop(sheetContext);

                    widget.focusNode?.requestFocus();
                  },
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 27)),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.instance.data;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 5, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(23),
                  border: Border.all(
                    color: theme.text.withValues(alpha: 0.055),
                  ),
                ),
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  minLines: 1,
                  maxLines: 5,
                  onSubmitted: _handleSubmitted,
                  textInputAction: _enterToSend
                      ? TextInputAction.send
                      : TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: 'Mesaj yaz…',
                    hintStyle: TextStyle(
                      color: theme.text.withValues(alpha: 0.38),
                      fontSize: 13.5,
                    ),
                    prefixIcon: IconButton(
                      tooltip: 'Ek seçenekler',
                      onPressed: _openAttachmentMenu,
                      icon: Icon(
                        Icons.add_rounded,
                        color: theme.text.withValues(alpha: 0.42),
                      ),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(0, 12, 14, 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                tooltip: 'Gönder',
                onPressed: widget.onSend,
                icon: Icon(
                  Icons.arrow_upward_rounded,
                  color: theme.background,
                  size: 22,
                ),
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
