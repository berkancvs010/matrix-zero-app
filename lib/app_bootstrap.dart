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
    zeroLog('[FCM] initialization failed: $e');
    zeroLog('$stack');
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
    // Native FCM service bildirimi gösterir. Teslim durumunu yalnızca
    // native HTTP receipt'e bırakma: Android/OEM süreç kapanışı nedeniyle
    // kısa ömürlü headless WebSocket ile de gerçek delivery ACK gönder.
    // Bu bağlantı primary oturumu devralmaz ve yalnızca pending mesajları
    // alıp transport katmanının messageDelivered ACK'lerini göndermesi için
    // kullanılır.
    try {
      final session = await SecureSession.read();
      if (session != null) {
        final client = WsClient.instance;
        final connected = await client.connect(
          session['username']!,
          session['password']!,
          backgroundDelivery: true,
          skipFcmToken: true,
        ).timeout(
          const Duration(seconds: 5),
          onTimeout: () => false,
        );
        if (connected) {
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        }
        await client.disconnect();
      }
    } catch (e) {
      zeroLog('[FCM][background] delivery ACK fallback failed: $e');
    }
  }

  zeroLog(
    '[FCM][background] '
    'messageId=${message.messageId} '
    'type=${message.data['type']}',
  );
}
