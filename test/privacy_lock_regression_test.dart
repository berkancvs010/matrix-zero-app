import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('native biometric pause is not mistaken for leaving the app', () {
    final gate = read('lib/app_lock_gate.dart');
    expect(gate, contains('_privacyAuthCausedLifecyclePause ='));
    expect(gate, contains('ZeroLogPrivacyLock.authenticationInProgress'));
    expect(gate, contains('if (_privacyAuthCausedLifecyclePause)'));
    expect(gate, contains('_privacyAuthCausedLifecyclePause = false;'));
    expect(gate, contains('HeroControllerScope.none('));
  });

  test('PIN controllers outlive the dialog reverse transition', () {
    final privacy = read('lib/privacy_lock.dart');
    expect(
      privacy,
      contains('static Future<T?> _showDialogAndWaitForRemoval<T>'),
    );
    expect(privacy, contains('await route.completed;'));
    expect(privacy, contains('_showDialogAndWaitForRemoval<bool>('));
    expect(privacy, contains('final pinFocusNode = FocusNode();'));
    expect(privacy, contains('autofocus: false'));
  });

  test(
    'privacy entry is serialized and surfaces failures instead of going blank',
    () {
      final main = read('lib/main_screen.dart');
      expect(main, contains('bool _openingPrivacySettings = false;'));
      expect(main, contains('if (_openingPrivacySettings) return;'));
      expect(main, contains('Gizlilik bölümü açılamadı:'));
      expect(main, contains('_openingPrivacySettings = false;'));
    },
  );

  test(
    'removing the PIN clears biometric state and notifies the lock gate',
    () {
      final privacy = read('lib/privacy_lock.dart');
      final start = privacy.indexOf('static Future<void> removeLock()');
      final end = privacy.indexOf('static Future<bool> changePin(', start);
      final removeLock = privacy.substring(start, end);
      expect(removeLock, contains('await _storage.delete(key: _hashKey)'));
      expect(removeLock, contains('await _storage.delete(key: _biometricKey)'));
      expect(removeLock, contains('_notifyConfigurationChanged()'));
    },
  );
}
