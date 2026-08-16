import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  test('exports open system and report type helpers', () {
    expect(UrbSystem.motakamelTransactions.value, 'motakamel_transactions');
    expect(UrbReportType.salesInvoice.value, 'sales_invoice');
    expect(UrbReportType.salesReturn.value, 'sales_return');
  });

  test('enforces independent action policy values', () {
    const policy = ReportActionPolicy(
      canPrintPdf: false,
      canSavePdf: true,
      canSharePdf: false,
    );

    expect(policy.allows(ReportAction.printPdf), isFalse);
    expect(policy.allows(ReportAction.savePdf), isTrue);
    expect(policy.allows(ReportAction.sharePdf), isFalse);
  });

  test('keeps Print hidden by default for compatibility', () {
    const features = BridgeUiFeatures();
    expect(features.showPrint, isFalse);
    expect(features.showSavePdf, isTrue);
    expect(features.showSharePdf, isTrue);
    expect(features.showDevelopmentSupport, isTrue);
  });

  test(
    'development support can be explicitly disabled and survives policy restriction',
    () {
      const features = BridgeUiFeatures(showDevelopmentSupport: false);
      final restricted = features.restrictTo(const ReportActionPolicy());

      expect(restricted.showDevelopmentSupport, isFalse);
    },
  );

  test('supports current and future Android print modes', () {
    const current = AndroidPrintConfiguration.systemPrintManager();
    final future = AndroidPrintConfiguration.externalApp(
      configuration: AndroidExternalPrinterConfiguration(
        installUri: Uri.parse('https://example.invalid/printer'),
      ),
    );

    expect(current.mode, AndroidPrintMode.systemPrintManager);
    expect(current.externalApp, isNull);
    expect(future.mode, AndroidPrintMode.externalApp);
    expect(future.externalApp?.packageName, 'com.Ultimate.Printer');
    expect(future.externalApp?.action, 'com.Ultimate.Printer.PRINT_PDF_V1');
  });
}
