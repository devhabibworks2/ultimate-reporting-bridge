import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/src/flow/report_flow_failure.dart';
import 'package:reporting_bridge_flutter/src/localization/report_flow_strings.dart';

void main() {
  test('English output and policy messages are localized', () {
    const strings = ReportFlowStrings(Locale('en'));

    expect(strings.print, 'Print');
    expect(strings.documentSettings, 'Document settings');
    expect(strings.printSubmitted, 'Report submitted for printing.');
    expect(
      strings.failure(
        const ReportFlowFailure(code: ReportFlowFailureCode.actionDenied),
      ),
      'This action is denied by the report policy.',
    );
  });

  test('Arabic output and policy messages are localized', () {
    const strings = ReportFlowStrings(Locale('ar'));

    expect(strings.print, 'طباعة');
    expect(strings.documentSettings, 'إعدادات المستند');
    expect(strings.printSubmitted, 'تم إرسال التقرير للطباعة.');
    expect(
      strings.failure(
        const ReportFlowFailure(code: ReportFlowFailureCode.actionDenied),
      ),
      'هذه العملية غير مسموح بها وفق سياسة التقرير.',
    );
  });
}
