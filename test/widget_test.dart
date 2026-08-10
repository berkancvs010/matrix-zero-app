import 'package:flutter_test/flutter_test.dart';

import 'package:matrix_zero/main.dart';

void main() {
  testWidgets('Matrix Zero uygulaması açılıyor', (WidgetTester tester) async {
    await tester.pumpWidget(const MatrixZeroApp());

    expect(find.text('ZERO LOG'), findsOneWidget);
  });
}
