import 'package:flutter_test/flutter_test.dart';
import 'package:monopoly_banking/app.dart';

void main() {
  testWidgets('MonopolyApp loads', (WidgetTester tester) async {
    await tester.pumpWidget(const MonopolyApp());
    expect(find.byType(MonopolyApp), findsOneWidget);
  });
}
