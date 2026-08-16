import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_host/main.dart';

void main() {
  testWidgets('shows open report action', (WidgetTester tester) async {
    await tester.pumpWidget(const MinimalHostApp());
    expect(find.text('Minimal Host'), findsOneWidget);
    expect(find.text('Open report'), findsOneWidget);
  });
}
