import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'file_transfer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';


part 'app_bootstrap.dart';
part 'push_service.dart';
part 'theme.dart';
part 'app_shell.dart';
part 'welcome.dart';
part 'networking.dart';
part 'login.dart';
part 'nickname.dart';
part 'main_screen.dart';
part 'chat_room.dart';
part 'private_chat.dart';
part 'call_screen.dart';
part 'message_input.dart';
part 'models.dart';
part 'profile_controller.dart';


@pragma('vm:entry-point')
Future<void> zerologBackgroundTransferMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    'zerolog/background_transfer',
  );
  StreamSubscription<Map<String, dynamic>>? backgroundEventsSub;

  try {

    final raw = await channel.invokeMethod<dynamic>(
      'getPendingTransfer',
    );

    if (raw is! Map) {
      await channel.invokeMethod<dynamic>('stopService');
      return;
    }

    final data = Map<String, dynamic>.from(raw);

    final sender =
        (data['sender'] ?? '').toString().trim();

    final recipient =
        (data['recipient'] ?? '').toString().trim();

    final transferId =
        (data['fileId'] ?? '').toString().trim();

    final fileName =
        (data['fileName'] ?? 'received_file').toString().trim();

    final fileSize =
        int.tryParse(
          (data['fileSize'] ?? '').toString(),
        ) ??
        0;

    if (sender.isEmpty ||
        recipient.isEmpty ||
        transferId.isEmpty ||
        fileSize <= 0) {
      await channel.invokeMethod<dynamic>('stopService');
      return;
    }

    final prefs =
        await SharedPreferences.getInstance();

    final autoAccept =
        prefs.getBool(
              'zerolog.notifications.auto_accept_files',
            ) ??
            true;

    if (!autoAccept) {
      await channel.invokeMethod<dynamic>('stopService');
      return;
    }

    final session = await SecureSession.read();

    if (session == null) {
      await channel.invokeMethod<dynamic>('stopService');
      return;
    }

    final username =
        session['username']!.trim();

    if (username.isEmpty ||
        username.toLowerCase() !=
            recipient.toLowerCase()) {
      await channel.invokeMethod<dynamic>('stopService');
      return;
    }

    FileTransfer.backgroundTransferMode = true;

    final ws = WsClient.instance;

    // WsClient.events is a broadcast stream and does not replay events.
    // The server can deliver pending file-transfer signaling immediately
    // after authentication, so capture file events BEFORE connect().
    final pendingFileEvents = <Map<String, dynamic>>[];
    var transferReady = false;

    backgroundEventsSub = ws.events.listen((event) {
      final type = event['type']?.toString();

      final isFileSignal =
          type == 'fileTransferOffer' ||
          type == 'fileTransferAnswer' ||
          type == 'fileTransferIce' ||
          type == 'fileTransferAccept' ||
          type == 'fileTransferReject' ||
          type == 'fileTransferComplete' ||
          type == 'fileTransferFailed';

      if (!isFileSignal) return;

      if (!transferReady) {
        pendingFileEvents.add(
          Map<String, dynamic>.from(event),
        );
        return;
      }

      final currentTransfer = FileTransfer.shared(
        ws: ws,
        me: username,
        peer: sender,
        turnUsername: ws.turnUsername,
        turnPassword: ws.turnPassword,
        turnUrls: ws.turnUrls,
      );

      unawaited(
        currentTransfer.handleExternalEvent(
          Map<String, dynamic>.from(event),
        ),
      );
    });

    final connected = await ws.connect(
      session['username']!,
      session['password']!,
      backgroundTransfer: true,
      backgroundTransferId: transferId,
    );

    if (!connected) {
      await backgroundEventsSub.cancel();
      await channel.invokeMethod<dynamic>('stopService');
      return;
    }

    try {
      if (!ws.turnCredentialsReady.isCompleted) {
        await ws.turnCredentialsReady.future.timeout(
          const Duration(seconds: 10),
        );
      }
    } catch (_) {
      // TURN alınamazsa STUN fallback kullanılacak.
    }

    final transfer = FileTransfer.shared(
      ws: ws,
      me: username,
      peer: sender,
      turnUsername: ws.turnUsername,
      turnPassword: ws.turnPassword,
      turnUrls: ws.turnUrls,
    );

    final prepared =
        await transfer.prepareIncomingFromNotification(
      transferId: transferId,
      fileName: fileName,
      fileSize: fileSize,
      sender: sender,
    );

    if (!prepared) {
      await backgroundEventsSub.cancel();
      await channel.invokeMethod<dynamic>('stopService');
      return;
    }

    await transfer.acceptIncoming(transferId);

    // ACCEPT has been sent. The receive-side WebRTC state is now ready.
    // Replay signaling events captured during authentication.
    transferReady = true;

    final capturedEvents =
        List<Map<String, dynamic>>.from(pendingFileEvents);

    pendingFileEvents.clear();

    for (final event in capturedEvents) {
      await transfer.handleExternalEvent(event);
    }

  } catch (e, stack) {
    debugPrint('[BG_TRANSFER] $e');
    debugPrint('$stack');

    try {
      await channel.invokeMethod<dynamic>(
        'stopService',
      );
    } catch (_) {}
  }
}

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
