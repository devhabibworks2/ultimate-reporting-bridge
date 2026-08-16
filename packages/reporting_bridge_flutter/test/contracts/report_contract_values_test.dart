import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  group('UrbReportType', () {
    test('exposes exactly eight canonical report types', () {
      expect(UrbReportType.values.map((type) => type.value).toList(), <String>[
        'sales_invoice',
        'sales_return',
        'customer_order',
        'receipt_voucher',
        'payment_voucher',
        'quotation',
        'account_statement',
        'report',
      ]);
    });

    test('parseCanonical accepts only the eight values', () {
      for (final type in UrbReportType.values) {
        expect(UrbReportType.parseCanonical(type.value), type);
      }
      expect(
        () => UrbReportType.parseCanonical('invoice'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('ReportLanguage', () {
    test('canonical parser accepts ar/en and rejects legacy 1/2', () {
      expect(ReportLanguage.parseCanonical('ar'), ReportLanguage.ar);
      expect(ReportLanguage.parseCanonical('en'), ReportLanguage.en);
      expect(
        () => ReportLanguage.parseCanonical('1'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ReportLanguage.parseCanonical('2'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('legacy external parser accepts 1/2', () {
      expect(ReportLanguage.fromLegacyExternal(1), ReportLanguage.ar);
      expect(ReportLanguage.fromLegacyExternal('2'), ReportLanguage.en);
      expect(ReportLanguage.ar.legacyExternalValue, 1);
      expect(ReportLanguage.en.legacyExternalValue, 2);
    });
  });

  group('layout/size/orientation/unit', () {
    test('layout serializes Pages and Thermal only', () {
      expect(ReportLayout.pages.value, 'Pages');
      expect(ReportLayout.thermal.value, 'Thermal');
      expect(ReportLayout.parseCanonical('Pages'), ReportLayout.pages);
      expect(ReportLayout.parseCanonical('Thermal'), ReportLayout.thermal);
      expect(
        () => ReportLayout.parseCanonical('Custom'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('size serializes exact V1 preset set', () {
      expect(ReportPageSize.values.map((size) => size.value).toList(), <String>[
        'A4',
        'A5',
        'Letter',
        '80mm',
        '58mm',
        'custom',
      ]);
      expect(
        () => ReportPageSize.parseCanonical('A3'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ReportPageSize.parseCanonical('Legal'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('unit has only mm', () {
      expect(ReportMeasurementUnit.values, <ReportMeasurementUnit>[
        ReportMeasurementUnit.mm,
      ]);
      expect(ReportMeasurementUnit.mm.value, 'mm');
      expect(
        () => ReportMeasurementUnit.parseCanonical('cm'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ReportMeasurementUnit.parseCanonical('inch'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('orientation is portrait or landscape', () {
      expect(ReportOrientation.portrait.value, 'portrait');
      expect(ReportOrientation.landscape.value, 'landscape');
    });
  });
}
