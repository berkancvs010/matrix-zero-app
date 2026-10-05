import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:matrix_zero/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SuccessfulAuthPlatform extends LocalAuthPlatform {
  static Future<void> Function()? onAuthenticate;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    await onAuthenticate?.call();
    return true;
  }

  @override
  Future<List<BiometricType>> getEnrolledBiometrics() async => [
    BiometricType.fingerprint,
  ];

  @override
  Future<bool> isDeviceSupported() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    _SuccessfulAuthPlatform.onAuthenticate = null;
    LocalAuthPlatform.instance = _SuccessfulAuthPlatform();
  });

  Future<void> pumpFrames(WidgetTester tester, [int count = 8]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppLockGate(child: child!),
        home: const MainScreen(nickname: 'tester'),
      ),
    );
    await pumpFrames(tester);
  }

  Future<void> openPrivacyFromSettings(WidgetTester tester) async {
    await tester.tap(find.text('Ayarlar').last);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Gizlilik').last);
    await pumpFrames(tester);
  }

  Future<void> verifyWithPin(WidgetTester tester) async {
    expect(find.text('Gizlilik Merkezi kilitli'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '123456');
    await pumpFrames(tester);
  }

  Future<void> expectPrivacyPage(WidgetTester tester) async {
    expect(find.text('Gizlilik ve güvenlik'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  Future<void> popPrivacyRoute(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await pumpFrames(tester);
  }

  Future<void> configureTestLock({required bool biometric}) async {
    const salt = 'fixed-test-salt';
    final hash = sha256
        .convert(utf8.encode('$salt:123456:ZeroLogPrivacyLock:v1'))
        .toString();
    FlutterSecureStorage.setMockInitialValues({
      'zerolog.privacy_lock.pin_hash.v1': hash,
      'zerolog.privacy_lock.pin_salt.v1': salt,
      'zerolog.privacy_lock.biometric.v1': biometric ? '1' : '0',
    });
  }

  testWidgets(
    'PIN ile kilit açma sonrası Gizlilik ekranı açılır ve tekrar açılır',
    (tester) async {
      await configureTestLock(biometric: false);
      await pumpApp(tester);

      await verifyWithPin(tester); // app-wide lock
      await openPrivacyFromSettings(tester);
      await verifyWithPin(tester); // privacy center
      await expectPrivacyPage(tester);

      await popPrivacyRoute(tester);
      await openPrivacyFromSettings(tester);
      await verifyWithPin(tester);
      await expectPrivacyPage(tester);

      await popPrivacyRoute(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 250));
    },
  );

  testWidgets('biyometri pause/resume sonrası Gizlilik ekranı açılır', (
    tester,
  ) async {
    await configureTestLock(biometric: true);
    _SuccessfulAuthPlatform.onAuthenticate = () async {
      // local_auth's Android system prompt temporarily backgrounds the host
      // Activity; model the lifecycle pair while the auth Future is pending.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    };

    await pumpApp(tester); // biometric unlock of the app-wide gate
    await openPrivacyFromSettings(tester); // biometric unlock of privacy center
    await expectPrivacyPage(tester);

    await popPrivacyRoute(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 250));
  });
}
