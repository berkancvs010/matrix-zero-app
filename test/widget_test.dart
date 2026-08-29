import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:matrix_zero/main.dart';

void main() {
  testWidgets('Welcome ekranı açılıyor', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        home: WelcomeScreen(),
      ),
    );

    // SharedPreferences ve WelcomeScreen'in async başlangıcını bekle.
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('ZEROLOG'), findsOneWidget);
  });
}
