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

  const channel = MethodChannel('zerolog/background_transfer');

  try {
    final prefs = await SharedPreferences.getInstance();
    final autoAccept =
        prefs.getBool('zerolog.notifications.auto_accept_files') ?? true;

    if (!autoAccept) {
      await channel.invokeMethod<dynamic>('stopService');
      return;
    }

    final session = await SecureSession.read();
    if (session == null) {
      await channel.invokeMethod<dynamic>('stopService');
      return;
    }

    final username = session['username']!.trim();
    if (username.isEmpty) {
      await channel.invokeMethod<dynamic>('stopService');
      return;
    }

    FileTransfer.backgroundTransferMode = true;

    // Android can deliver more than one FCM wake-up while the same
    // foreground service is alive. The native service keeps a durable queue;
    // process it sequentially so every transfer gets its own authenticated
    // transfer socket. This preserves the existing single-transfer FileTransfer
    // state machine instead of introducing risky multi-transfer state into it.
    while (true) {
      final rawQueue =
          await channel.invokeMethod<dynamic>('getPendingTransfers');

      if (rawQueue is! List || rawQueue.isEmpty) {
        break;
      }

      final raw = rawQueue.first;
      if (raw is! Map) {
        break;
      }

      final data = Map<String, dynamic>.from(raw);
      final sender = (data['sender'] ?? '').toString().trim();
      final recipient = (data['recipient'] ?? '').toString().trim();
      final transferId = (data['fileId'] ?? '').toString().trim();
      final fileName =
          (data['fileName'] ?? 'received_file').toString().trim();
      final fileSize =
          int.tryParse((data['fileSize'] ?? '').toString()) ?? 0;

      if (sender.isEmpty ||
          recipient.isEmpty ||
          transferId.isEmpty ||
          fileSize <= 0 ||
          username.toLowerCase() != recipient.toLowerCase()) {
        await channel.invokeMethod<dynamic>(
          'removePendingTransfer',
          <String, dynamic>{'fileId': transferId},
        );
        continue;
      }

      final ws = WsClient.instance;
      StreamSubscription<Map<String, dynamic>>? captureSub;
      var transferReady = false;
      final pendingFileEvents = <Map<String, dynamic>>[];

      var retryLater = false;

      try {
        // The broadcast stream does not replay. Capture signaling before
        // connect because the server may replay OFFER immediately after auth.
        captureSub = ws.events.listen((event) {
          final type = event['type']?.toString();
          const fileSignals = <String>{
            'fileTransferOffer',
            'fileTransferAnswer',
            'fileTransferIce',
            'fileTransferAccept',
            'fileTransferReject',
            'fileTransferComplete',
            'fileTransferFailed',
          };

          if (!fileSignals.contains(type)) return;

          if (!transferReady) {
            pendingFileEvents.add(Map<String, dynamic>.from(event));
          }
        });

        final connected = await ws.connect(
          session['username']!,
          session['password']!,
          backgroundTransfer: true,
          backgroundTransferId: transferId,
          skipFcmToken: true,
        );

        if (!connected) {
          await captureSub.cancel();
          captureSub = null;
          // Keep the queue item. The service is START_STICKY and another
          // delivery/restart can recover it without losing the transfer.
          break;
        }

        final transfer = FileTransfer.shared(
          ws: ws,
          me: username,
          peer: sender,
          turnUsername: ws.turnUsername,
          turnPassword: ws.turnPassword,
          turnUrls: ws.turnUrls,
        );

        final done = Completer<void>();
        var terminal = false;
        String? completedLocalUri;

        transfer.bindCallbacks(
          onIncomingStatus: ({
            required String transferId,
            required String status,
            String? localUri,
          }) {
            if (status == 'completed') {
              if (localUri != null && localUri.trim().isNotEmpty) {
                completedLocalUri = localUri.trim();
              }
            }

            if ((status == 'completed' || status == 'failed') &&
                !terminal) {
              terminal = true;
              if (!done.isCompleted) done.complete();
            }
          },
        );

        await transfer.initialize();

        final prepared = await transfer.prepareIncomingFromNotification(
          transferId: transferId,
          fileName: fileName,
          fileSize: fileSize,
          sender: sender,
        );

        if (!prepared) {
          await channel.invokeMethod<dynamic>(
            'removePendingTransfer',
            <String, dynamic>{'fileId': transferId},
          );
          continue;
        }

        await transfer.acceptIncoming(transferId);

        // FileTransfer now owns chunks/end/complete. Keep the capture
        // subscription alive only until ACCEPT is sent so no early signaling
        // is lost; captured events are replayed immediately afterwards.
        await captureSub.cancel();
        captureSub = null;
        transferReady = true;

        final capturedEvents =
            List<Map<String, dynamic>>.from(pendingFileEvents);
        pendingFileEvents.clear();

        for (final event in capturedEvents) {
          await transfer.handleExternalEvent(event);
        }

        if (!terminal) {
          await done.future.timeout(
            const Duration(minutes: 5),
            onTimeout: () {},
          );
        }

        // A completed/failed transfer has reached a terminal local state.
        // Remove only this item; other queued transfers remain durable.
        await channel.invokeMethod<dynamic>(
          'removePendingTransfer',
          <String, dynamic>{'fileId': transferId},
        );

        // Keep the verified local file registration path exactly as before.
        if (completedLocalUri != null &&
            completedLocalUri!.trim().isNotEmpty) {
          try {
            await channel.invokeMethod<dynamic>(
              'registerBackgroundReceivedFile',
              <String, dynamic>{
                'fileId': transferId,
                'sourcePath': completedLocalUri,
                'fileName': fileName,
              },
            );
          } catch (e) {
            debugPrint(
              '[BG_TRANSFER] received file registration failed: $e',
            );
          }
        }
      } catch (e, stack) {
        retryLater = true;
        debugPrint('[BG_TRANSFER] transfer=$transferId error: $e');
        debugPrint('$stack');

        // Do not discard a queued transfer on a transport/process exception.
        // The server-side reliable session remains the source of truth.
      } finally {
        if (captureSub != null) {
          try {
            await captureSub.cancel();
          } catch (_) {}
        }

        try {
          await ws.disconnect();
        } catch (_) {}

        transferReady = false;
        pendingFileEvents.clear();
      }

      if (retryLater) {
        // Preserve the queue item for a later FCM/service restart instead of
        // spinning indefinitely on a broken transport.
        break;
      }
    }

    await channel.invokeMethod<void>('stopService');
  } catch (e, stack) {
    debugPrint('[BG_TRANSFER] $e');
    debugPrint('$stack');

    try {
      await channel.invokeMethod<dynamic>('stopService');
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
