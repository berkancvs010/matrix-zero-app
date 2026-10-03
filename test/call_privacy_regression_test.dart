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
    expect(gate, contains('currentState?.overlay?.context'));
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
}
