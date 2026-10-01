import 'package:compatibility_host_modern/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('modern host builds', (tester) async {
    await tester.pumpWidget(const CompatibilityHostModernApp());
    expect(find.text('Construct bridge'), findsOneWidget);
  });
}
