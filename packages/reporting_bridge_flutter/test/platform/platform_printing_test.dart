import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/src/contracts/external_printer_contract.dart';
import 'package:reporting_bridge_flutter/src/platform/platform_printing.dart';

void main() {
  test(
    'platform_printing re-exports Android configuration and print types',
    () {
      const system = AndroidPrintConfiguration.systemPrintManager();
      final external = AndroidPrintConfiguration.externalApp(
        configuration: AndroidExternalPrinterConfiguration(
          installUri: Uri.parse('https://example.test/install'),
        ),
      );

      expect(system.mode, AndroidPrintMode.systemPrintManager);
      expect(external.externalApp?.packageName, ultimatePrinterPackageName);
      expect(external.externalApp?.action, ultimatePrinterAction);
      expect(external.externalApp?.mimeType, ultimatePrinterMimeType);

      const metadata = ReportPrintDocumentMetadata(
        unit: 'mm',
        layout: 'Thermal',
        size: '80mm',
        width: 80,
        height: 220,
        orientation: 'portrait',
        languageCode: 'ar',
      );
      expect(metadata.legacyLanguage, 1);
      expect(
        const UnsupportedReportPrintPlatform(),
        isA<ReportPrintPlatform>(),
      );
    },
  );

  test('legacy language mapping remains ar→1 and en→2', () {
    expect(
      const ReportPrintDocumentMetadata(
        unit: 'mm',
        layout: 'Pages',
        size: 'A4',
        width: 210,
        height: 297,
        orientation: 'portrait',
        languageCode: 'ar',
      ).legacyLanguage,
      1,
    );
    expect(
      const ReportPrintDocumentMetadata(
        unit: 'mm',
        layout: 'Pages',
        size: 'A4',
        width: 210,
        height: 297,
        orientation: 'portrait',
        languageCode: 'en',
      ).legacyLanguage,
      2,
    );
  });
}
