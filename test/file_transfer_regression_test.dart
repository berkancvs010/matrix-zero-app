import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final serverSource = File('server/server.js').readAsStringSync();
  final transferSource = File('lib/file_transfer.dart').readAsStringSync();

  test('server pending-byte accounting decrements each chunk exactly once', () {
    expect(
      RegExp(
        r'session\.pendingBytes=Math\.max\(0,\(Number\(session\.pendingBytes\)\|\|0\)-sentLength\);',
      ).allMatches(serverSource).length,
      1,
    );
    expect(
      RegExp(
        r'reliablePendingTotalBytes=Math\.max\(0,reliablePendingTotalBytes-sentLength\);',
      ).allMatches(serverSource).length,
      1,
    );
    expect(
      serverSource,
      contains('const RELIABLE_FILE_MAX_PENDING_BYTES=64*1024*1024;'),
    );
  });

  test('client transfer validates notification SHA and cleans invalid preparation', () {
    expect(
      transferSource,
      contains("if (_sourceSha256!.isNotEmpty && !_validSha(_sourceSha256!)) {"),
    );
    expect(transferSource, contains('await _resetTransferState();'));
    expect(transferSource, contains('return false;'));
    expect(transferSource, contains(r"RegExp(r'^[a-f0-9]{64}$')"));
    expect(transferSource, contains("!_validSha(declaredSha)"));
  });

  test('legacy file push helpers never suppress FCM from stale presence alone', () {
    expect(
      serverSource,
      contains(
        'const liveForeground=socketFor(target);\n  if(liveForeground && isForegroundActive(target))return false;',
      ),
    );
    expect(
      serverSource,
      isNot(contains(
        'if(isForegroundActive(target))return false;\n\n  const transferId=String(',
      )),
    );
  });

  test('server sends a background wake-up when presence is stale and no live socket exists', () {
    expect(
      serverSource,
      contains(
        'const pushed=await sendFcmPush(session.to,{',
      ),
    );
    expect(
      serverSource,
      contains(
        'const foreground=socketFor(session.to);',
      ),
    );
    expect(
      serverSource,
      contains(
        'if(endpoint || foreground)continue;',
      ),
    );
    expect(
      serverSource,
      isNot(contains(
        'if(isForegroundActive(session.to)){\n    return false;\n  }\n\n  const pushed=await sendFcmPush',
      )),
    );
  });

  test('terminal file failures are routed to both peers and retained if offline', () {
    expect(
      serverSource,
      contains('function failReliableFileTransfer(session,reason,sourceWs=null){'),
    );
    expect(serverSource, contains('const deliveredSender=send(sender,eventForSender);'));
    expect(serverSource, contains('const deliveredReceiver=send(receiver,eventForReceiver);'));
    expect(serverSource, contains('storeTerminalPendingFileTransfer(session.from,eventForSender);'));
    expect(serverSource, contains('storeTerminalPendingFileTransfer(session.to,eventForReceiver);'));
    expect(serverSource, contains("'fileTransferFailedAck'"));
    expect(serverSource, contains('terminalUntil'));
  });

  test('stale sockets cannot win reliable file routing', () {
    expect(serverSource, contains('recipient.isAlive!==false'));
    expect(serverSource, contains('ws.isAlive===false'));
    expect(serverSource, contains('session.receiverWs.isAlive!==false'));
    expect(serverSource, contains('entry.ws.isAlive!==false'));
  });

  test('native notification queue uses peek then acknowledge', () {
    final mainSource = File(
      'android/app/src/main/kotlin/com/zerolog/app/MainActivity.kt',
    ).readAsStringSync();
    final pushSource = File('lib/push_service.dart').readAsStringSync();

    expect(mainSource, contains('"ackPendingMessageIntent"'));
    expect(mainSource, contains('put("__queueKey", queueKey)'));
    expect(mainSource, contains('append(from)'));
    expect(mainSource, contains('append(to)'));
    expect(mainSource, contains('if (itemKey == ackKey)'));
    expect(pushSource, contains('ackPendingMessageIntent'));
    expect(pushSource, contains('final stored = await storeNotificationPayload'));
    expect(pushSource, contains('if (!acknowledged)'));
    expect(pushSource, contains('pendingNotificationQueueKey'));
    expect(pushSource, contains('if (queue.length > 100)'));
    expect(pushSource, contains('_notificationIdentity'));
    expect(pushSource, contains('ackPendingMessageIntent'));
  });

  test('release build version is bumped for V27', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: 1.0.9+22'));
  });

  test('outgoing/in-app-accepted transfers keep the process foreground-priority', () {
    // V23 fix: nothing previously protected the process while a transfer
    // was in flight, so fully swiping the app away (as opposed to just
    // backgrounding it) killed the send mid-flight and left it stuck on
    // "Gönderim bekliyor" forever.
    expect(transferSource, contains("MethodChannel _keepAliveChannel = MethodChannel('zerolog/system');"));
    expect(transferSource, contains('_startKeepAlive()'));
    expect(transferSource, contains('_stopKeepAlive()'));
    expect(transferSource, contains("invokeMethod('startFileTransferForegroundService')"));
    expect(transferSource, contains("invokeMethod('stopFileTransferForegroundService')"));

    final mainActivitySource = File(
      'android/app/src/main/kotlin/com/zerolog/app/MainActivity.kt',
    ).readAsStringSync();
    expect(mainActivitySource, contains('FileTransferForegroundService.EXTRA_KEEPALIVE, true'));

    final serviceSource = File(
      'android/app/src/main/kotlin/com/zerolog/app/FileTransferForegroundService.kt',
    ).readAsStringSync();
    expect(serviceSource, contains('const val EXTRA_KEEPALIVE = "keepAlive"'));
    expect(serviceSource, contains('keepAliveRefCount'));

    final manifestSource = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifestSource, contains('android:stopWithTask="false"'));
  });

  test('failure is retained until both peers acknowledge or terminal TTL expires', () {
    expect(serverSource, contains('session.failureAcks={sender:false,receiver:false};'));
    expect(serverSource, contains('if(failedSession.failureAcks.sender===true && failedSession.failureAcks.receiver===true)'));
    expect(serverSource, contains('deliverTerminalFileFailures(ws,account.username);'));
    expect(transferSource, contains("'type': 'fileTransferFailedAck'"));
  });

  test('login has IP plus username rate limiting', () {
    expect(serverSource, contains('LOGIN_RATE_MAX_FAILURES=5;'));
    expect(serverSource, contains('function loginRateKey(ws,username)'));
    expect(serverSource, contains("code:'LOGIN_RATE_LIMITED'"));
  });


  test('server failure paths use the durable terminal failure handler', () {
    expect(
      serverSource,
      isNot(contains(
        "send(ws,{\n      type:'fileTransferFailed',\n      transferId,\n      reason:'Alıcı bağlantısı çok uzun süre kurulamadı.',",
      )),
    );
    expect(
      RegExp(
        r"failReliableFileTransfer\(\s*session,\s*'Alıcı bağlantısı çok uzun süre kurulamadı\.',\s*ws,\s*\)",
      ).allMatches(serverSource).length,
      greaterThanOrEqualTo(3),
    );
    expect(
      serverSource,
      contains('session.pendingChunks=[];'),
    );
    expect(
      serverSource,
      contains('reliablePendingTotalBytes=Math.max('),
    );
  });

  test('accepted transfers retain ACCEPT when the sender socket is unavailable', () {
    expect(
      serverSource,
      contains("const acceptForSender={\n      type:'fileTransferAccept',"),
    );
    expect(
      serverSource,
      contains('const deliveredAccept=send(sender,acceptForSender);'),
    );
    expect(
      serverSource,
      contains(
        'if(!deliveredAccept){\n      storePendingFileTransfer(session.from,acceptForSender);',
      ),
    );
    expect(
      serverSource,
      contains('[FILE_TRANSFER] ACCEPT transfer='),
    );
    expect(
      serverSource,
      contains("if(session.state==='accepted' && isSender){"),
    );
  });

  test('server relay queue deduplicates retransmitted chunk sequences', () {
    expect(
      serverSource,
      contains('function reliableFileFrameSequence(buffer){'),
    );
    expect(
      serverSource,
      contains('if(reliableFileFrameSequence(pending)===seq)return true;'),
    );
    expect(
      serverSource,
      contains('Never enqueue the same sequence twice'),
    );
  });

  test('background wake retry is faster than receiver connection timeout', () {
    expect(serverSource, contains('now-lastPush<60000'));
    expect(transferSource, contains('Duration(seconds: 180)'));
  });

  test('client ACCEPT path is observable and active-chat offers are not dropped', () {
    expect(transferSource, contains('ACCEPT_RECEIVED transfer='));
    expect(transferSource, contains('ACCEPT_REJECTED reason=transfer_id_mismatch'));
    expect(transferSource, contains('SEND_START_REQUEST transfer='));
    expect(transferSource, contains('SEND_START_BLOCKED transfer='));
    expect(transferSource, contains('CHUNK_SEND_ATTEMPT transfer='));
    expect(transferSource, contains('CHUNK_SENT transfer='));
    final mainSource = File('lib/main_screen.dart').readAsStringSync();
    expect(mainSource, contains('BACKGROUND_ACCEPT_REQUEST transfer='));
    expect(mainSource, contains('Reuse the shared transfer object'));
  });


test('message persistence is asynchronous and serialized per file', () {
  final saveStart = serverSource.indexOf('function save(file,data){');
  final sendStart = serverSource.indexOf('function send(ws,data){');
  expect(saveStart, greaterThanOrEqualTo(0));
  expect(sendStart, greaterThan(saveStart));

  final saveSource = serverSource.substring(saveStart, sendStart);
  expect(saveSource, contains('saveQueues'));
  expect(saveSource, contains('await fs.promises.writeFile('));
  expect(saveSource, contains('await fs.promises.rename(temp,target);'));
  expect(saveSource, isNot(contains('fs.writeFileSync')));
  expect(saveSource, isNot(contains('fs.renameSync')));
});

test('authenticated private and room messages have a shared per-user flood limit', () {
  expect(serverSource, contains('const MESSAGE_RATE_WINDOW_MS=10*1000;'));
  expect(serverSource, contains('const MESSAGE_RATE_MAX=20;'));
  expect(serverSource, contains('function messageRateCheck(username){'));
  expect(serverSource, contains("type:'messageRateLimited'"));
  expect(serverSource, contains("case 'privateMessage'"));
  expect(serverSource, contains("case 'roomMessage'"));

  final privateStart = serverSource.indexOf("case 'privateMessage'");
  final roomStart = serverSource.indexOf("case 'roomMessage'");
  expect(privateStart, greaterThanOrEqualTo(0));
  expect(roomStart, greaterThanOrEqualTo(0));
  expect(serverSource.indexOf('messageRateCheck(me)', privateStart),
      greaterThanOrEqualTo(privateStart));
  expect(serverSource.indexOf('messageRateCheck(me)', roomStart),
      greaterThanOrEqualTo(roomStart));
});

test('client surfaces rejected private messages and rate limits', () {
  final privateSource = File('lib/private_chat.dart').readAsStringSync();
  final roomSource = File('lib/chat_room.dart').readAsStringSync();

  expect(privateSource, contains("data['type'] == 'messageRateLimited'"));
  expect(privateSource, contains("data['type'] == 'privateMessageRejected'"));
  expect(privateSource, contains("_markLocalMessageFailed("));
  expect(privateSource, contains("status: 'failed'"));
  expect(privateSource, contains("Gönderilemedi"));
  expect(privateSource, contains("Icons.error_outline_rounded"));
  expect(privateSource, contains("_retryFailedMessage(message)"));
  expect(serverSource, contains("type:'privateMessageRejected'"));
  expect(serverSource, contains("reason:'PRIVATE_MESSAGES_DISABLED'"));
  expect(serverSource, contains("clientMessageId,\n        reason:'PRIVATE_MESSAGES_DISABLED',"));
  expect(serverSource, contains("type:'messageRateLimited'"));
  expect(serverSource, contains("retryAfterMs:rate.retryAfterMs"));
  expect(serverSource, contains("scope:'privateMessage'"));
  expect(serverSource, contains("scope:'roomMessage'"));
  expect(roomSource, contains("data['type'] == 'messageRateLimited'"));
});

  test('file transfer callbacks are multiplexed instead of overwritten', () {
    expect(transferSource, contains('final List<_FileTransferCallbackBinding>'));
    expect(transferSource, contains('FileTransferCallbackHandle bindCallbacks('));
    expect(transferSource, contains('_callbackBindings.add('));
    expect(transferSource, contains('for (final binding in List<_FileTransferCallbackBinding>.from('));
    expect(transferSource, contains('_removeCallbackBinding'));
  });

  test('file transfer keeps the WsClient transport object, not a reconnect-bound raw socket', () {
    final networkingSource = File('lib/networking.dart').readAsStringSync();
    expect(transferSource, contains('final dynamic ws;'));
    expect(networkingSource, contains('static final WsClient instance = WsClient._();'));
    expect(transferSource, contains('ws.events.listen'));
    expect(transferSource, contains('ws.send('));
  });


test('incoming completion retry never blocks the serialized event queue', () {
  expect(transferSource, contains('bool _completionSending = false;'));
  expect(transferSource, contains('unawaited(_finishIncomingTransferAfterCommit(id, actualSha, finalFile));'));
  final handleEndStart = transferSource.indexOf('Future<void> _handleEnd(');
  final finishStart = transferSource.indexOf('Future<void> _finishIncomingTransferAfterCommit(');
  expect(handleEndStart, greaterThanOrEqualTo(0));
  expect(finishStart, greaterThan(handleEndStart));
  final handleEndSource = transferSource.substring(handleEndStart, finishStart);
  expect(handleEndSource, isNot(contains('await _sendCompletionWithRetry(')));
  expect(transferSource, contains('if (_completionSending) return;'));
});

test('invalid notification SHA cleans the partially initialized transfer state', () {
  expect(
    transferSource,
    contains("if (_sourceSha256!.isNotEmpty && !_validSha(_sourceSha256!)) {\n        await _resetTransferState();\n        return false;\n      }"),
  );
});

test('completion timeout is allowed to report a durable failure after commit', () {
  expect(transferSource, contains("_terminalEventHandled = false;\n        try {\n          if (await finalFile.exists()) await finalFile.delete();"));
  expect(transferSource, contains("'Dosya tamamlanma onayı alınamadı: \$e'"));
});

}
