import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:matrix_zero/main.dart';

void main() {
  testWidgets('Welcome ekranı açılıyor', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: WelcomeScreen(),
      ),
    );

    expect(find.text('ZEROLOG'), findsOneWidget);
  });
}
