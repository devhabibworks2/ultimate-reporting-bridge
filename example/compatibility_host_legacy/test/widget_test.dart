import 'package:compatibility_host_legacy/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('legacy host builds', (tester) async {
    await tester.pumpWidget(const CompatibilityHostLegacyApp());
    expect(find.text('Construct bridge'), findsOneWidget);
  });
}
