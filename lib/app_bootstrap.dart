part of 'main.dart';

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
    // callStatus is a lifecycle/control event.
    // Native Android FCM service owns the background call cleanup.
    // Do not create a second notification from the Flutter background isolate.
    await ZeroLogPushService.cancelIncomingCallNotification();
    await ZeroLogPushService.clearPendingCall();
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
