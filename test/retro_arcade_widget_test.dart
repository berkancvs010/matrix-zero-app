import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_zero/main.dart';

void main() {
  const games = [
    'Piksel Macerası',
    'Tank Arenası',
    'Uzay Savunması',
    'Yılan',
    'Tuğla Kırıcı',
    'Raket Düellosu',
    'Blok Düşürme',
    'Reversi',
    'Mayın Tarlası',
    'Sayı Birleştirme',
  ];

  for (final title in games) {
    testWidgets('$title açılır ve ilk frame hatasız çizilir', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RetroArcadePage()));
      await tester.pump(const Duration(milliseconds: 50));

      final gameTile = find.text(title);
      var scrollAttempts = 0;
      while (gameTile.evaluate().isEmpty && scrollAttempts < 8) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -420));
        await tester.pumpAndSettle();
        scrollAttempts++;
      }
      expect(gameTile, findsWidgets);
      await tester.ensureVisible(gameTile);
      await tester.pumpAndSettle();
      await tester.tap(gameTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.text(title).last, findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
