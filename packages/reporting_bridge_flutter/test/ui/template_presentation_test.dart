import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:reporting_bridge_flutter/src/localization/report_flow_strings.dart';

void main() {
  test('presentation consumes typed metadata without raw page/meta parsing', () {
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
    final template = CachedTemplate(
      id: 't1',
      type: 'sales_invoice',
      name: 'Sales Invoice A4',
      version: '2.1.0',
      document: const <String, dynamic>{
        // Intentionally incomplete raw document — presentation must not parse it.
        'meta': <String, dynamic>{'description': 'should-not-be-read'},
        'page': <String, dynamic>{'size': 'should-not-be-read'},
      },
    );
    final strings = ReportFlowStrings(const Locale('en'));

    final presented = TemplatePresentationMetadata.fromReportMetadata(
      metadata,
      template: template,
      strings: strings,
    );

    expect(presented.reportType, UrbReportType.salesInvoice);
    expect(presented.layout, ReportLayout.pages);
    expect(presented.size, ReportPageSize.a4);
    expect(presented.orientation, ReportOrientation.portrait);
    expect(presented.width, 210);
    expect(presented.height, 297);
    expect(presented.reportTypeLabel, 'Sales Invoice');
    expect(presented.languageLabel, 'Arabic');
    expect(presented.layoutLabel, 'Pages');
    expect(presented.sizeLabel, 'A4');
    expect(presented.orientationLabel, 'Portrait');
    expect(presented.versionLabel, 'Version 2.1.0');
    expect(presented.description, 'Ready report template');
  });

  test('localized Arabic labels retain thermal size and orientation', () {
    final metadata = ReportTemplateMetadata(
      reportType: UrbReportType.receiptVoucher,
      layout: ReportLayout.thermal,
      size: ReportPageSize.thermal80,
      unit: ReportMeasurementUnit.mm,
      orientation: ReportOrientation.portrait,
      language: ReportLanguage.en,
      width: 80,
      height: 200,
      direction: 'ltr',
    );
    final presented = TemplatePresentationMetadata.fromReportMetadata(
      metadata,
      template: CachedTemplate(
        id: 't2',
        type: 'receipt_voucher',
        name: 'Receipt',
        version: '1.0.0',
        document: const <String, dynamic>{},
      ),
      strings: ReportFlowStrings(const Locale('ar')),
    );

    expect(presented.reportTypeLabel, 'سند قبض');
    expect(presented.languageLabel, 'الإنجليزية');
    expect(presented.layoutLabel, 'حراري');
    expect(presented.sizeLabel, '٨٠ مم');
    expect(presented.orientationLabel, 'عمودي');
  });

  test('custom size label preserves exact authored dimensions', () {
    final presented = TemplatePresentationMetadata.fromReportMetadata(
      ReportTemplateMetadata(
        reportType: UrbReportType.report,
        layout: ReportLayout.pages,
        size: ReportPageSize.custom,
        unit: ReportMeasurementUnit.mm,
        orientation: ReportOrientation.landscape,
        language: ReportLanguage.en,
        width: 123.5,
        height: 88,
        direction: 'ltr',
      ),
      template: CachedTemplate(
        id: 'custom',
        type: 'report',
        name: 'Custom',
        document: const <String, dynamic>{},
      ),
      strings: ReportFlowStrings(const Locale('en')),
    );

    expect(presented.sizeLabel, '123.5 × 88 mm');
    expect(presented.thumbnailSizeLabel, '123.5×88mm');
    expect(presented.orientationLabel, 'Landscape');
  });

  test('thumbnail resolver maps all canonical families deterministically', () {
    final expected = <UrbReportTypeCode, TemplateThumbnailFamily>{
      UrbReportType.salesInvoice: TemplateThumbnailFamily.salesInvoice,
      UrbReportType.salesReturn: TemplateThumbnailFamily.salesReturn,
      UrbReportType.customerOrder: TemplateThumbnailFamily.customerOrder,
      UrbReportType.receiptVoucher: TemplateThumbnailFamily.receiptVoucher,
      UrbReportType.paymentVoucher: TemplateThumbnailFamily.paymentVoucher,
      UrbReportType.quotation: TemplateThumbnailFamily.quotation,
      UrbReportType.accountStatement: TemplateThumbnailFamily.accountStatement,
      UrbReportType.report: TemplateThumbnailFamily.report,
    };

    final iconCodePoints = <int>{};
    for (final entry in expected.entries) {
      final spec = TemplateThumbnailSpec.resolve(
        reportType: entry.key,
        layout: ReportLayout.pages,
        size: ReportPageSize.a4,
        orientation: ReportOrientation.portrait,
        width: 210,
        height: 297,
      );
      expect(spec.family, entry.value);
      iconCodePoints.add(spec.familyIcon.codePoint);
    }

    expect(iconCodePoints, hasLength(expected.length));
    expect(
      TemplateThumbnailSpec.resolve(
        reportType: const UrbReportTypeCode('future_family'),
        layout: ReportLayout.pages,
        size: ReportPageSize.custom,
        orientation: ReportOrientation.portrait,
        width: 100,
        height: 180,
      ).family,
      TemplateThumbnailFamily.fallback,
    );
  });

  test('family, layout, size, and orientation remain independent', () {
    final portraitPages = TemplateThumbnailSpec.resolve(
      reportType: UrbReportType.salesInvoice,
      layout: ReportLayout.pages,
      size: ReportPageSize.a4,
      orientation: ReportOrientation.portrait,
      width: 210,
      height: 297,
    );
    final landscapePages = TemplateThumbnailSpec.resolve(
      reportType: UrbReportType.salesInvoice,
      layout: ReportLayout.pages,
      size: ReportPageSize.a4,
      orientation: ReportOrientation.landscape,
      width: 297,
      height: 210,
    );
    final thermal = TemplateThumbnailSpec.resolve(
      reportType: UrbReportType.salesInvoice,
      layout: ReportLayout.thermal,
      size: ReportPageSize.thermal80,
      orientation: ReportOrientation.portrait,
      width: 80,
      height: 220,
    );

    expect(portraitPages.family, landscapePages.family);
    expect(portraitPages.family, thermal.family);
    expect(portraitPages.layoutShape, TemplateThumbnailLayoutShape.pages);
    expect(thermal.layoutShape, TemplateThumbnailLayoutShape.thermal);
    expect(portraitPages.size, ReportPageSize.a4);
    expect(thermal.size, ReportPageSize.thermal80);
    expect(portraitPages.orientation, ReportOrientation.portrait);
    expect(landscapePages.orientation, ReportOrientation.landscape);
  });

  testWidgets(
    'preview encodes family, layout, size, and orientation in the thumbnail',
    (WidgetTester tester) async {
      Future<TemplatePresentationMetadata> pumpPreview({
        required UrbReportTypeCode reportType,
        required ReportLayout layout,
        required ReportPageSize size,
        required ReportOrientation orientation,
        required double pageWidth,
        required double pageHeight,
        required String locale,
      }) async {
        final metadata = ReportTemplateMetadata(
          reportType: reportType,
          layout: layout,
          size: size,
          unit: ReportMeasurementUnit.mm,
          orientation: orientation,
          language: ReportLanguage.en,
          width: pageWidth,
          height: pageHeight,
          direction: 'ltr',
        );
        final presented = TemplatePresentationMetadata.fromReportMetadata(
          metadata,
          template: CachedTemplate(
            id: 'preview',
            type: reportType.value,
            name: 'Preview',
            document: const <String, dynamic>{},
          ),
          strings: ReportFlowStrings(Locale(locale)),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Center(child: TemplatePreview(metadata: presented)),
          ),
        );
        await tester.pumpAndSettle();
        return presented;
      }

      await pumpPreview(
        reportType: UrbReportType.salesInvoice,
        layout: ReportLayout.pages,
        size: ReportPageSize.a4,
        orientation: ReportOrientation.portrait,
        pageWidth: 210,
        pageHeight: 297,
        locale: 'en',
      );
      const familyKey = ValueKey<String>('template-family-salesInvoice');
      const portraitKey = ValueKey<String>('template-layout-pages-portrait');
      expect(find.byKey(familyKey), findsOneWidget);
      expect(find.byKey(portraitKey), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('template-layout-thermal')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('template-size-A4')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('template-orientation-portrait')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(portraitKey),
          matching: find.byKey(familyKey),
        ),
        findsOneWidget,
      );
      final portraitSize = tester.getSize(find.byKey(portraitKey));
      expect(portraitSize.height, greaterThan(portraitSize.width));

      await pumpPreview(
        reportType: UrbReportType.salesInvoice,
        layout: ReportLayout.pages,
        size: ReportPageSize.a4,
        orientation: ReportOrientation.landscape,
        pageWidth: 297,
        pageHeight: 210,
        locale: 'en',
      );
      const landscapeKey = ValueKey<String>('template-layout-pages-landscape');
      expect(find.byKey(landscapeKey), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('template-orientation-landscape')),
        findsNothing,
      );
      final landscapeSize = tester.getSize(find.byKey(landscapeKey));
      expect(landscapeSize.width, greaterThan(landscapeSize.height));

      await pumpPreview(
        reportType: UrbReportType.receiptVoucher,
        layout: ReportLayout.thermal,
        size: ReportPageSize.thermal80,
        orientation: ReportOrientation.portrait,
        pageWidth: 80,
        pageHeight: 220,
        locale: 'ar',
      );
      const thermalFamilyKey = ValueKey<String>(
        'template-family-receiptVoucher',
      );
      const thermalKey = ValueKey<String>('template-layout-thermal');
      expect(find.byKey(thermalFamilyKey), findsOneWidget);
      expect(find.byKey(thermalKey), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('template-size-80mm')),
        findsOneWidget,
      );
      expect(find.text('٨٠مم'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(thermalKey),
          matching: find.byKey(thermalFamilyKey),
        ),
        findsOneWidget,
      );
      final thermal80Width = tester.getSize(find.byKey(thermalKey)).width;
      expect(thermal80Width, lessThan(portraitSize.width * 0.7));
      expect(
        find.byKey(const ValueKey<String>('template-thermal-perforation-top')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('template-thermal-perforation-bottom'),
        ),
        findsOneWidget,
      );

      await pumpPreview(
        reportType: UrbReportType.receiptVoucher,
        layout: ReportLayout.thermal,
        size: ReportPageSize.thermal58,
        orientation: ReportOrientation.portrait,
        pageWidth: 58,
        pageHeight: 220,
        locale: 'en',
      );
      final thermal58Width = tester.getSize(find.byKey(thermalKey)).width;
      expect(thermal58Width, lessThan(thermal80Width));
      expect(
        find.byKey(const ValueKey<String>('template-size-58mm')),
        findsOneWidget,
      );

      await pumpPreview(
        reportType: UrbReportType.report,
        layout: ReportLayout.pages,
        size: ReportPageSize.custom,
        orientation: ReportOrientation.landscape,
        pageWidth: 123.5,
        pageHeight: 88,
        locale: 'en',
      );
      expect(
        find.byKey(const ValueKey<String>('template-size-custom')),
        findsOneWidget,
      );
      expect(find.text('123.5×88mm'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact custom thumbnail removes the overlay badge safely', (
    WidgetTester tester,
  ) async {
    final metadata = TemplatePresentationMetadata.fromReportMetadata(
      ReportTemplateMetadata(
        reportType: UrbReportType.report,
        layout: ReportLayout.pages,
        size: ReportPageSize.custom,
        unit: ReportMeasurementUnit.mm,
        orientation: ReportOrientation.landscape,
        language: ReportLanguage.en,
        width: 123.5,
        height: 88,
        direction: 'ltr',
      ),
      template: CachedTemplate(
        id: 'compact-custom',
        type: 'report',
        name: 'Compact custom',
        document: const <String, dynamic>{},
      ),
      strings: ReportFlowStrings(const Locale('en')),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: TemplatePreview(metadata: metadata, width: 64, height: 80),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('template-orientation-landscape')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('template-size-custom')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('template-layout-pages-landscape')),
      findsOneWidget,
    );
    expect(find.text('123.5×88mm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'all canonical families fit safely in landscape Pages thumbnails',
    (WidgetTester tester) async {
      const families = <UrbReportTypeCode>[
        UrbReportType.salesInvoice,
        UrbReportType.salesReturn,
        UrbReportType.customerOrder,
        UrbReportType.receiptVoucher,
        UrbReportType.paymentVoucher,
        UrbReportType.quotation,
        UrbReportType.accountStatement,
        UrbReportType.report,
      ];

      for (final reportType in families) {
        final metadata = TemplatePresentationMetadata.fromReportMetadata(
          ReportTemplateMetadata(
            reportType: reportType,
            layout: ReportLayout.pages,
            size: ReportPageSize.a4,
            unit: ReportMeasurementUnit.mm,
            orientation: ReportOrientation.landscape,
            language: ReportLanguage.en,
            width: 297,
            height: 210,
            direction: 'ltr',
          ),
          template: CachedTemplate(
            id: reportType.value,
            type: reportType.value,
            name: reportType.value,
            document: const <String, dynamic>{},
          ),
          strings: ReportFlowStrings(const Locale('en')),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Center(child: TemplatePreview(metadata: metadata)),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: reportType.value);
        expect(
          find.byKey(
            ValueKey<String>(
              'template-family-${metadata.thumbnailSpec.family.name}',
            ),
          ),
          findsOneWidget,
        );
      }
    },
  );

  test('Arabic Sales Return label uses canonical مردود wording', () {
    final strings = ReportFlowStrings(const Locale('ar'));
    expect(strings.reportTypeLabel(UrbReportType.salesReturn), 'مردود مبيعات');
  });

  testWidgets(
    'Pages thumbnail orientation follows authoritative metadata when dimensions disagree',
    (WidgetTester tester) async {
      Future<Size> pump({
        required ReportOrientation orientation,
        required double width,
        required double height,
      }) async {
        final metadata = TemplatePresentationMetadata.fromReportMetadata(
          ReportTemplateMetadata(
            reportType: UrbReportType.salesInvoice,
            layout: ReportLayout.pages,
            size: ReportPageSize.custom,
            unit: ReportMeasurementUnit.mm,
            orientation: orientation,
            language: ReportLanguage.en,
            width: width,
            height: height,
            direction: 'ltr',
          ),
          template: CachedTemplate(
            id: 'orientation-authority-${orientation.value}',
            type: UrbReportType.salesInvoice.value,
            name: 'Orientation authority',
            document: const <String, dynamic>{},
          ),
          strings: ReportFlowStrings(const Locale('en')),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Center(child: TemplatePreview(metadata: metadata)),
          ),
        );
        await tester.pumpAndSettle();
        return tester.getSize(
          find.byKey(
            ValueKey<String>('template-layout-pages-${orientation.value}'),
          ),
        );
      }

      final portrait = await pump(
        orientation: ReportOrientation.portrait,
        width: 297,
        height: 210,
      );
      expect(portrait.height, greaterThan(portrait.width));

      final landscape = await pump(
        orientation: ReportOrientation.landscape,
        width: 210,
        height: 297,
      );
      expect(landscape.width, greaterThan(landscape.height));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'redesigned preview uses the larger card footprint and a full bottom size badge',
    (WidgetTester tester) async {
      final metadata = TemplatePresentationMetadata.fromReportMetadata(
        ReportTemplateMetadata(
          reportType: UrbReportType.receiptVoucher,
          layout: ReportLayout.thermal,
          size: ReportPageSize.thermal80,
          unit: ReportMeasurementUnit.mm,
          orientation: ReportOrientation.portrait,
          language: ReportLanguage.ar,
          width: 80,
          height: 220,
          direction: 'rtl',
        ),
        template: CachedTemplate(
          id: 'mobile-preview',
          type: 'receipt_voucher',
          name: 'Mobile preview',
          document: const <String, dynamic>{},
        ),
        strings: ReportFlowStrings(const Locale('ar')),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: TemplatePreview(metadata: metadata)),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(TemplatePreview)), const Size(92, 116));
      final badgeRect = tester.getRect(
        find.byKey(const ValueKey<String>('template-size-80mm')),
      );
      expect(badgeRect.width, greaterThan(70));
      expect(
        find.byKey(const ValueKey<String>('template-layout-thermal')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
