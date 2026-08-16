import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  test('ReportOpenRequest accepts typed system and report identifiers', () {
    final request = ReportOpenRequest(
      seedData: const <String, dynamic>{},
      selectedTemplateCriteria: SelectedTemplateCriteria(
        reportType: UrbReportType.salesInvoice,
      ),
      templateSyncRequest: TemplateSyncRequest(
        systemCode: UrbSystem.motakamelTransactions,
      ),
    );

    expect(
      request.templateSyncRequest.systemCode.value,
      'motakamel_transactions',
    );
    expect(request.reportType.value, 'sales_invoice');
  });

  test('every visibility and policy combination is intersected', () {
    for (var visibility = 0; visibility < 8; visibility += 1) {
      for (var policy = 0; policy < 8; policy += 1) {
        final features = BridgeUiFeatures(
          showPrint: visibility & 1 != 0,
          showSavePdf: visibility & 2 != 0,
          showSharePdf: visibility & 4 != 0,
        );
        final actionPolicy = ReportActionPolicy(
          canPrintPdf: policy & 1 != 0,
          canSavePdf: policy & 2 != 0,
          canSharePdf: policy & 4 != 0,
        );

        final effective = features.restrictTo(actionPolicy);

        expect(effective.showPrint, visibility & 1 != 0 && policy & 1 != 0);
        expect(effective.showSavePdf, visibility & 2 != 0 && policy & 2 != 0);
        expect(effective.showSharePdf, visibility & 4 != 0 && policy & 4 != 0);
      }
    }
  });

  test('read-only policy leaves preview features without output actions', () {
    final effective = const BridgeUiFeatures(
      showPrint: true,
      showSavePdf: true,
      showSharePdf: true,
      showSettings: true,
    ).restrictTo(const ReportActionPolicy.readOnly());

    expect(effective.hasVisibleOutputAction, isFalse);
    expect(effective.showSettings, isTrue);
  });
}
