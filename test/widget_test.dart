import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/main.dart';

void main() {
  testWidgets('POS home screen loads', (WidgetTester tester) async {
    await tester.pumpWidget(const PosApp());
    await tester.pumpAndSettle();
    expect(find.text('POS'), findsOneWidget);
  });
}
