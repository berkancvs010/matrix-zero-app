import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current.path;

  String source(String relativePath) =>
      File('$root/$relativePath').readAsStringSync();

  test('outgoing call advertises video mode in the invite', () {
    final call = source('lib/call_screen.dart');
    expect(call, contains("'type': 'callInvite'"));
    expect(call, contains("'video': _videoEnabled"));
  });

  test('callEnd is sent before slow native/WebRTC cleanup', () {
    final call = source('lib/call_screen.dart');
    final signal = call.indexOf("'type': 'callEnd'");
    final cleanup = call.indexOf('stopCallForegroundService');
    expect(signal, greaterThanOrEqualTo(0));
    expect(cleanup, greaterThan(signal));
    expect(call, contains('Navigator.of(context).pop();\n      return;'));
  });

  test('app-wide privacy lock is mounted and authentication is serialized', () {
    final shell = source('lib/app_shell.dart');
    final gate = source('lib/app_lock_gate.dart');
    final privacy = source('lib/privacy_lock.dart');
    expect(shell, contains('AppLockGate(child:'));
    expect(gate, contains('_lockNavigatorKey'));
    expect(gate, contains('MaterialPageRoute<void>'));
    expect(gate, contains('final dialogContext = _lockNavigatorKey.currentState?.context;'));
    expect(privacy, contains('authenticationInProgress'));
    expect(privacy, contains('stickyAuth: false'));
    expect(privacy, contains('biometricOnly: true'));
  });

  test('native ringtone remains the single call sound owner', () {
    final push = source('lib/push_service.dart');
    expect(push, contains('callChannelId'));
    expect(push, contains('playSound: false'));
    expect(push, contains('Ringtone playback is owned by the native service.'));
  });

  test('call cleanup stops incoming ringtone and clears pending state', () {
    final call = source('lib/call_screen.dart');
    expect(call, contains('ZeroLogPushService.cancelIncomingCallNotification();'));
    expect(call, contains('ZeroLogPushService.clearPendingCall();'));
  });

  test('signaling disconnect terminates the local call instead of leaving a stale UI', () {
    final call = source('lib/call_screen.dart');
    expect(call, contains("type == 'connectionLost'"));
    expect(call, contains("type == 'connectionError'"));
    expect(call, contains("type == 'connectionClosed'"));
    expect(call, contains("_finish(sendSignal: false)"));
  });

  test('in-app version is read from the installed Android package', () {
    final push = source('lib/push_service.dart');
    final native = source('android/app/src/main/kotlin/com/zerolog/app/MainActivity.kt');
    expect(push, contains("invokeMethod<dynamic>('getAppVersion')"));
    expect(native, contains('"getAppVersion"'));
    expect(native, contains('packageInfo.longVersionCode'));
  });

  test('native FCM suppresses duplicate call UI while app is foreground', () {
    final native = source(
      'android/app/src/main/kotlin/com/zerolog/app/ZeroLogFirebaseMessagingService.kt',
    );
    expect(native, contains('Suppressing native call notification: app is foreground'));
    expect(native, contains('ActivityManager.getMyMemoryState(processInfo)'));
    expect(native, contains('IMPORTANCE_FOREGROUND'));
  });

  test('server ends calls when the primary signaling socket disappears', () {
    final server = source('server/server.js');
    expect(server, contains('function endCallsForDisconnectedUser(nick)'));
    expect(server, contains('endCallsForDisconnectedUser(nick);'));
    expect(server, contains("type:'callEnded'"));
  });
  test('native call notification is not suppressed while the device is locked', () {
    final native = source(
      'android/app/src/main/kotlin/com/zerolog/app/ZeroLogFirebaseMessagingService.kt',
    );
    expect(native, contains('KeyguardManager'));
    expect(native, contains('val deviceLocked = keyguardManager?.isKeyguardLocked == true'));
    expect(native, contains('if (foreground && !deviceLocked)'));
    expect(native, contains('setTimeoutAfter(60_000L)'));

    final server = source('server/server.js');
    expect(
      server,
      contains("priority:'high',\n          // The signaling call itself expires after 60 seconds."),
    );
    expect(server, contains('ttl:60000'));
    expect(server, contains('if(callNotificationsEnabled(to)){'));
  });

  test('WebSocket reconnect ignores stale socket callbacks', () {
    final networking = source('lib/networking.dart');
    expect(networking, contains('int _connectionGeneration = 0;'));
    expect(networking, contains('final connectionGeneration = ++_connectionGeneration;'));
    expect(
      networking,
      contains('if (connectionGeneration != _connectionGeneration) return;'),
    );
  });

  test('WebRTC call cannot remain stuck forever after acceptance', () {
    final call = source('lib/call_screen.dart');
    expect(call, contains('_callConnectionTimeoutTimer'));
    expect(call, contains('Duration(seconds: 45)'));
    expect(call, contains('acceptance -> peer creation -> offer'));
    expect(call, contains('[CALL][WEBRTC] connection timeout'));
    expect(call, contains('Duration(seconds: 12)'));
    expect(call, contains('[CALL][WEBRTC] connection did not recover'));
  });

  test('reconnect cannot remain blocked by a dead WebSocket close', () {
    final networking = source('lib/networking.dart');
    expect(networking, contains("sink.close().timeout(const Duration(seconds: 2))"));
    expect(networking, contains('socket close timed out; forcing local cleanup'));
  });

  test('connection banner follows the live WebSocket state', () {
    final main = source('lib/main_screen.dart');
    expect(main, contains('if (WsClient.instance.connected)'));
    expect(main, contains('authoritative transport state'));
  });

  test('call watchdog starts before the offer is available', () {
    final call = source('lib/call_screen.dart');
    expect(call, contains('Cover the whole acceptance -> peer creation -> offer -> answer path'));
    expect(call, contains('Cover the whole acceptance -> peer creation'));
  });

  test('PIN auto-submits the first complete PIN and later failures require explicit submit', () {
    final privacy = source('lib/privacy_lock.dart');
    expect(privacy, contains('var autoSubmitPending = true;'));
    expect(privacy, contains('onChanged: (value)'));
    expect(privacy, contains('value.trim().length != 6'));
    expect(privacy, contains('autoSubmitPending = false;'));
    expect(privacy, contains('onSubmitted: (_) async'));
    expect(privacy, contains('var verifyingPin = false;'));
    expect(privacy, contains('if (verifyingPin) return;'));
  });

  test('native cold-start incoming call preserves video mode', () {
    final native = source(
      'android/app/src/main/kotlin/com/zerolog/app/MainActivity.kt',
    );
    expect(native, contains('putBoolean("video", video)'));
    expect(native, contains('val video = if (hasCallIntent)'));
    expect(native, contains('prefs.getBoolean("video", false)'));
    expect(native, contains('"video" to video'));
  });

  test('connection recovery cannot leave the chats banner stuck', () {
    final networking = source('lib/networking.dart');
    final main = source('lib/main_screen.dart');
    expect(
      networking,
      contains('final connectionGeneration = ++_connectionGeneration;'),
    );
    expect(networking, contains('_scheduleReconnect();'));
    expect(main, contains('if (WsClient.instance.connected)'));
    expect(
      main,
      contains("_reconnecting ? 'Bağlantı yeniden kuruluyor…' : 'Bağlanıyor…'"),
    );
  });

  test('PIN first complete entry auto-submits but failed entry needs explicit confirmation', () {
    final privacy = source('lib/privacy_lock.dart');
    expect(privacy, contains('var autoSubmitPending = true;'));
    expect(
      privacy,
      contains('unawaited(verifyEnteredPin(setState, dialogContext));'),
    );
    expect(privacy, contains('autoSubmitPending = false;'));
    expect(privacy, contains('onSubmitted: (_) async'));
    expect(privacy, contains("label: const Text('Doğrula')"));
  });

  test('call acceptance has a watchdog before SDP offer and a recovery grace timer', () {
    final call = source('lib/call_screen.dart');
    expect(call, contains('_startCallConnectionWatchdog();'));
    expect(call, contains('Duration(seconds: 45)'));
    expect(call, contains('Duration(seconds: 12)'));
    expect(call, contains('_finish(sendSignal: false)'));
  });

}
