import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  group('canonical PASS cases', () {
    test('Pages/A4/portrait/ar/mm', () {
      final metadata = ReportTemplateMetadata.fromTemplate(
        _canonical(
          family: 'sales_invoice',
          layout: 'Pages',
          size: 'A4',
          orientation: 'portrait',
          language: 'ar',
          width: 210,
          height: 297,
        ),
      );

      expect(metadata.reportType, UrbReportType.salesInvoice);
      expect(metadata.layout, ReportLayout.pages);
      expect(metadata.size, ReportPageSize.a4);
      expect(metadata.unit, ReportMeasurementUnit.mm);
      expect(metadata.orientation, ReportOrientation.portrait);
      expect(metadata.language, ReportLanguage.ar);
      expect(metadata.width, 210);
      expect(metadata.height, 297);
      expect(metadata.direction, 'rtl');
    });

    test('Pages/Letter/landscape/en/mm', () {
      final metadata = ReportTemplateMetadata.fromTemplate(
        _canonical(
          family: 'quotation',
          layout: 'Pages',
          size: 'Letter',
          orientation: 'landscape',
          language: 'en',
          width: 279.4,
          height: 215.9,
        ),
      );

      expect(metadata.layout, ReportLayout.pages);
      expect(metadata.size, ReportPageSize.letter);
      expect(metadata.orientation, ReportOrientation.landscape);
      expect(metadata.language, ReportLanguage.en);
      expect(metadata.direction, 'ltr');
    });

    test('Thermal/80mm/portrait/ar/mm', () {
      final metadata = ReportTemplateMetadata.fromTemplate(
        _canonical(
          family: 'receipt_voucher',
          layout: 'Thermal',
          size: '80mm',
          orientation: 'portrait',
          language: 'ar',
          width: 80,
          height: 240,
        ),
      );

      expect(metadata.layout, ReportLayout.thermal);
      expect(metadata.size, ReportPageSize.thermal80);
      expect(metadata.orientation, ReportOrientation.portrait);
    });

    test('Thermal/58mm/portrait/en/mm', () {
      final metadata = ReportTemplateMetadata.fromTemplate(
        _canonical(
          family: 'payment_voucher',
          layout: 'Thermal',
          size: '58mm',
          orientation: 'portrait',
          language: 'en',
          width: 58,
          height: 180,
        ),
      );

      expect(metadata.size, ReportPageSize.thermal58);
      expect(metadata.language, ReportLanguage.en);
    });

    test('Pages/custom with explicit dimensions', () {
      final metadata = ReportTemplateMetadata.fromTemplate(
        _canonical(
          family: 'report',
          layout: 'Pages',
          size: 'custom',
          orientation: 'portrait',
          language: 'en',
          width: 120,
          height: 180,
        ),
      );

      expect(metadata.size, ReportPageSize.custom);
      expect(metadata.width, 120);
      expect(metadata.height, 180);
      expect(metadata.direction, 'ltr');
    });

    test('Thermal/custom/portrait with explicit dimensions', () {
      final metadata = ReportTemplateMetadata.fromTemplate(
        _canonical(
          family: 'sales_return',
          layout: 'Thermal',
          size: 'custom',
          orientation: 'portrait',
          language: 'ar',
          width: 72,
          height: 200,
        ),
      );

      expect(metadata.layout, ReportLayout.thermal);
      expect(metadata.size, ReportPageSize.custom);
      expect(metadata.orientation, ReportOrientation.portrait);
    });
  });

  group('canonical REJECT cases', () {
    test('missing layout', () {
      expect(
        () => ReportTemplateMetadata.fromTemplate(
          _canonical(
            family: 'sales_invoice',
            layout: null,
            size: 'A4',
            orientation: 'portrait',
            language: 'ar',
            width: 210,
            height: 297,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        ReportTemplateMetadata.tryFromTemplate(
          _canonical(
            family: 'sales_invoice',
            layout: null,
            size: 'A4',
            orientation: 'portrait',
            language: 'ar',
            width: 210,
            height: 297,
          ),
        ),
        isNull,
      );
    });

    test('size=Thermal', () {
      expect(
        () => ReportTemplateMetadata.fromTemplate(
          _canonical(
            family: 'sales_invoice',
            layout: 'Pages',
            size: 'Thermal',
            orientation: 'portrait',
            language: 'ar',
            width: 210,
            height: 297,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('layout Custom', () {
      expect(
        () => ReportTemplateMetadata.fromTemplate(
          _canonical(
            family: 'sales_invoice',
            layout: 'Custom',
            size: 'custom',
            orientation: 'portrait',
            language: 'ar',
            width: 120,
            height: 180,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('A3', () {
      expect(
        () => ReportTemplateMetadata.fromTemplate(
          _canonical(
            family: 'sales_invoice',
            layout: 'Pages',
            size: 'A3',
            orientation: 'portrait',
            language: 'ar',
            width: 297,
            height: 420,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Legal', () {
      expect(
        () => ReportTemplateMetadata.fromTemplate(
          _canonical(
            family: 'sales_invoice',
            layout: 'Pages',
            size: 'Legal',
            orientation: 'portrait',
            language: 'en',
            width: 215.9,
            height: 355.6,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('cm/inch', () {
      expect(
        () => ReportTemplateMetadata.fromTemplate(
          _canonical(
            family: 'sales_invoice',
            layout: 'Pages',
            size: 'A4',
            orientation: 'portrait',
            language: 'ar',
            width: 210,
            height: 297,
            unit: 'cm',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ReportTemplateMetadata.fromTemplate(
          _canonical(
            family: 'sales_invoice',
            layout: 'Pages',
            size: 'A4',
            orientation: 'portrait',
            language: 'ar',
            width: 210,
            height: 297,
            unit: 'inch',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Thermal landscape', () {
      expect(
        () => ReportTemplateMetadata.fromTemplate(
          _canonical(
            family: 'sales_invoice',
            layout: 'Thermal',
            size: '80mm',
            orientation: 'landscape',
            language: 'en',
            width: 240,
            height: 80,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('custom missing width/height', () {
      expect(
        () => ReportTemplateMetadata.fromTemplate(
          _canonical(
            family: 'sales_invoice',
            layout: 'Pages',
            size: 'custom',
            orientation: 'portrait',
            language: 'en',
            width: null,
            height: null,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('missing page.language', () {
      expect(
        () => ReportTemplateMetadata.fromTemplate(
          _canonical(
            family: 'sales_invoice',
            layout: 'Pages',
            size: 'A4',
            orientation: 'portrait',
            language: null,
            width: 210,
            height: 297,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('noncanonical meta.family', () {
      expect(
        () => ReportTemplateMetadata.fromTemplate(
          _canonical(
            family: 'invoice',
            layout: 'Pages',
            size: 'A4',
            orientation: 'portrait',
            language: 'ar',
            width: 210,
            height: 297,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('does not infer Thermal from mm size', () {
      expect(
        () => ReportTemplateMetadata.fromTemplate(
          _canonical(
            family: 'sales_invoice',
            layout: null,
            size: '80mm',
            orientation: 'portrait',
            language: 'ar',
            width: 80,
            height: 200,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('does not default missing unit to mm', () {
      expect(
        () => ReportTemplateMetadata.fromTemplate(
          _canonical(
            family: 'sales_invoice',
            layout: 'Pages',
            size: 'A4',
            orientation: 'portrait',
            language: 'ar',
            width: 210,
            height: 297,
            unit: null,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('ar missing direction is rejected', () {
      expect(
        () => ReportTemplateMetadata.fromTemplate(
          _canonical(
            family: 'sales_invoice',
            layout: 'Pages',
            size: 'A4',
            orientation: 'portrait',
            language: 'ar',
            width: 210,
            height: 297,
            direction: null,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('en missing direction is rejected', () {
      expect(
        () => ReportTemplateMetadata.fromTemplate(
          _canonical(
            family: 'sales_invoice',
            layout: 'Pages',
            size: 'A4',
            orientation: 'portrait',
            language: 'en',
            width: 210,
            height: 297,
            direction: null,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('invalid direction is rejected', () {
      expect(
        () => ReportTemplateMetadata.fromTemplate(
          _canonical(
            family: 'sales_invoice',
            layout: 'Pages',
            size: 'A4',
            orientation: 'portrait',
            language: 'ar',
            width: 210,
            height: 297,
            direction: 'auto',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    for (final invalid in <String>['RTL', 'LTR', 'Rtl', 'LtR', '']) {
      test('direction $invalid is rejected without case folding', () {
        expect(
          () => ReportTemplateMetadata.fromTemplate(
            _canonical(
              family: 'sales_invoice',
              layout: 'Pages',
              size: 'A4',
              orientation: 'portrait',
              language: 'ar',
              width: 210,
              height: 297,
              direction: invalid.isEmpty ? '' : invalid,
            ),
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    }

    test('custom page with only page.customSize is rejected', () {
      expect(
        () => ReportTemplateMetadata.fromTemplate(
          CachedTemplate(
            id: 'custom-alias',
            type: 'report',
            document: <String, dynamic>{
              'schemaVersion': '1.0.0',
              'meta': const <String, dynamic>{
                'name': 'custom',
                'family': 'report',
              },
              'page': const <String, dynamic>{
                'layout': 'Pages',
                'size': 'custom',
                'unit': 'mm',
                'orientation': 'portrait',
                'language': 'en',
                'direction': 'ltr',
                'customSize': <String, dynamic>{'width': 120, 'height': 180},
              },
            },
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('runtime document customType is not parsed into metadata', () {
      final metadata = ReportTemplateMetadata.fromTemplate(
        _canonical(
          family: 'sales_invoice',
          layout: 'Pages',
          size: 'A4',
          orientation: 'portrait',
          language: 'en',
          width: 210,
          height: 297,
          customType: 'from_page',
          rootCustomType: 'from_root',
          metaCustomType: 'from_meta',
        ),
      );
      expect(metadata.reportType, UrbReportType.salesInvoice);
      expect(
        SelectedTemplateCriteria(
          reportType: UrbReportType.salesInvoice,
          customType: 'host_custom',
        ).customType,
        'host_custom',
      );
    });
  });

  test('explicit direction is accepted for ar/en', () {
    expect(
      ReportTemplateMetadata.fromTemplate(
        _canonical(
          family: 'sales_invoice',
          layout: 'Pages',
          size: 'A4',
          orientation: 'portrait',
          language: 'ar',
          width: 210,
          height: 297,
          direction: 'rtl',
        ),
      ).direction,
      'rtl',
    );
    expect(
      ReportTemplateMetadata.fromTemplate(
        _canonical(
          family: 'sales_invoice',
          layout: 'Pages',
          size: 'A4',
          orientation: 'portrait',
          language: 'en',
          width: 210,
          height: 297,
          direction: 'ltr',
        ),
      ).direction,
      'ltr',
    );
  });

  test('print metadata uses typed canonical values', () {
    final document = ReportTemplateMetadata.fromTemplate(
      _canonical(
        family: 'customer_order',
        layout: 'Pages',
        size: 'A4',
        orientation: 'landscape',
        language: 'ar',
        width: 297,
        height: 210,
      ),
    ).toPrintDocumentMetadata();

    expect(document.unit, 'mm');
    expect(document.layout, 'Pages');
    expect(document.size, 'A4');
    expect(document.width, 297);
    expect(document.height, 210);
    expect(document.orientation, 'landscape');
    expect(document.languageCode, 'ar');
  });

  test('compatibility constraints filter only matching templates', () {
    final templates = <CachedTemplate>[
      _canonical(
        id: 'pages-ar',
        family: 'sales_invoice',
        layout: 'Pages',
        size: 'A4',
        orientation: 'portrait',
        language: 'ar',
        width: 210,
        height: 297,
      ),
      _canonical(
        id: 'thermal-en',
        family: 'sales_invoice',
        layout: 'Thermal',
        size: '80mm',
        orientation: 'portrait',
        language: 'en',
        width: 80,
        height: 200,
        customType: 'receipt',
      ),
      _canonical(
        id: 'bad-family',
        family: 'invoice',
        layout: 'Pages',
        size: 'A4',
        orientation: 'portrait',
        language: 'ar',
        width: 210,
        height: 297,
      ),
    ];

    expect(
      filterEligibleTemplates(
        templates,
        reportType: UrbReportType.salesInvoice.value,
        constraints: const TemplateCompatibilityConstraints(
          language: ReportLanguage.en,
          layout: ReportLayout.thermal,
          size: ReportPageSize.thermal80,
        ),
      ).map((template) => template.id),
      <String>['thermal-en'],
    );
  });
}

CachedTemplate _canonical({
  String id = 'template',
  required String? family,
  required String? layout,
  required String? size,
  required String? orientation,
  required String? language,
  required double? width,
  required double? height,
  String? unit = 'mm',
  String? customType,
  String? metaCustomType,
  String? rootCustomType,
  Object? direction = _defaultDirection,
}) {
  final resolvedDirection = identical(direction, _defaultDirection)
      ? (language == 'ar'
            ? 'rtl'
            : language == 'en'
            ? 'ltr'
            : null)
      : direction as String?;
  final page = <String, dynamic>{
    if (unit != null) 'unit': unit,
    if (size != null) 'size': size,
    if (layout != null) 'layout': layout,
    if (orientation != null) 'orientation': orientation,
    if (language != null) 'language': language,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (resolvedDirection != null) 'direction': resolvedDirection,
    if (customType != null) 'customType': customType,
  };
  return CachedTemplate(
    id: id,
    type: family ?? 'unknown',
    document: <String, dynamic>{
      'schemaVersion': '1.0.0',
      'meta': <String, dynamic>{
        'name': id,
        if (family != null) 'family': family,
        if (metaCustomType != null) 'customType': metaCustomType,
      },
      'page': page,
      if (rootCustomType != null) 'customType': rootCustomType,
      'styleTokens': const <String, dynamic>{},
      'assets': const <dynamic>[],
      'layers': const <dynamic>[],
      'elements': const <dynamic>[],
    },
  );
}

const Object _defaultDirection = Object();
