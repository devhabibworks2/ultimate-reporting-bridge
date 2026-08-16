import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:reporting_bridge_flutter/src/contracts/external_printer_contract.dart'
    as contract;
import 'package:reporting_bridge_flutter/src/platform/android_print_configuration.dart'
    as android_config;

void main() {
  group('Ultimate Printer V1 transport constants', () {
    test('exposes exact package, action, and MIME once', () {
      expect(ultimatePrinterPackageName, 'com.Ultimate.Printer');
      expect(ultimatePrinterAction, 'com.Ultimate.Printer.PRINT_PDF_V1');
      expect(ultimatePrinterMimeType, 'application/pdf');
      expect(contract.ultimatePrinterPackageName, ultimatePrinterPackageName);
      expect(contract.ultimatePrinterAction, ultimatePrinterAction);
      expect(contract.ultimatePrinterMimeType, ultimatePrinterMimeType);
    });

    test('Android configuration references the contract authority', () {
      final configuration = AndroidExternalPrinterConfiguration(
        installUri: Uri.parse('https://example.test/install'),
      );

      expect(configuration.packageName, ultimatePrinterPackageName);
      expect(configuration.action, ultimatePrinterAction);
      expect(configuration.mimeType, ultimatePrinterMimeType);
      expect(
        configuration.packageName,
        android_config.AndroidExternalPrinterConfiguration(
          installUri: Uri.parse('https://example.test/install'),
        ).packageName,
      );
    });
  });

  group('HostExternalPrintRequest', () {
    test('allows only Host-owned title and extra', () {
      final request = HostExternalPrintRequest(
        documentTitle: 'Cash Invoice',
        extra: <String, Object?>{'copyCount': 2},
      );

      expect(request.documentTitle, 'Cash Invoice');
      expect(request.extra, <String, Object?>{'copyCount': 2});
    });

    test('resolves document title Host → reportName → template name', () {
      expect(
        resolveExternalPrintDocumentTitle(
          hostPrint: HostExternalPrintRequest(documentTitle: 'Host'),
          reportName: 'Report',
          templateName: 'Template',
        ),
        'Host',
      );
      expect(
        resolveExternalPrintDocumentTitle(
          hostPrint: HostExternalPrintRequest(),
          reportName: 'Report',
          templateName: 'Template',
        ),
        'Report',
      );
      expect(
        resolveExternalPrintDocumentTitle(
          hostPrint: null,
          reportName: null,
          templateName: 'Template',
        ),
        'Template',
      );
    });
  });

  group('legacy language mapping', () {
    test('maps ar→1 and en→2', () {
      expect(legacyExternalLanguageValue('ar'), 1);
      expect(legacyExternalLanguageValue('en'), 2);
      expect(ReportLanguage.ar.legacyExternalValue, 1);
      expect(ReportLanguage.en.legacyExternalValue, 2);
      expect(legacyExternalLanguageValue('fr'), isNull);
    });

    test(
      'selected-template English metadata uses en/2 without Host language',
      () {
        final metadata = ReportTemplateMetadata(
          reportType: UrbReportType.salesInvoice,
          layout: ReportLayout.thermal,
          size: ReportPageSize.thermal80,
          unit: ReportMeasurementUnit.mm,
          orientation: ReportOrientation.portrait,
          language: ReportLanguage.en,
          width: 80,
          height: 220,
          direction: 'ltr',
        );
        final document = metadata.toPrintDocumentMetadata();

        expect(document.languageCode, 'en');
        expect(document.legacyLanguage, 2);
        expect(legacyExternalLanguageValue(document.languageCode), 2);
      },
    );

    test(
      'selected-template Arabic metadata uses ar/1 without Host language',
      () {
        final metadata = ReportTemplateMetadata(
          reportType: UrbReportType.salesInvoice,
          layout: ReportLayout.pages,
          size: ReportPageSize.a4,
          unit: ReportMeasurementUnit.mm,
          orientation: ReportOrientation.portrait,
          language: ReportLanguage.ar,
          width: 210,
          height: 297,
          direction: 'rtl',
        );
        final document = metadata.toPrintDocumentMetadata();

        expect(document.languageCode, 'ar');
        expect(document.legacyLanguage, 1);
        expect(legacyExternalLanguageValue(document.languageCode), 1);
      },
    );
  });
}
