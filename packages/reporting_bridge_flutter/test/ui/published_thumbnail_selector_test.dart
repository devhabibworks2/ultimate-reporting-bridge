import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:reporting_bridge_flutter/src/localization/report_flow_strings.dart';

void main() {
  const metadata = TemplatePresentationMetadata(
    reportType: UrbReportTypeCode('sales_invoice'),
    layout: ReportLayout.pages,
    size: ReportPageSize.a4,
    orientation: ReportOrientation.portrait,
    unit: ReportMeasurementUnit.mm,
    width: 210,
    height: 297,
    description: 'Ready report template',
    reportTypeLabel: 'Sales Invoice',
    languageLabel: 'English',
    layoutLabel: 'Pages',
    sizeLabel: 'A4',
    thumbnailSizeLabel: 'A4',
    orientationLabel: 'Portrait',
    version: '1',
    versionLabel: 'Version 1',
  );
  final validPng = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/2ioAAAAASUVORK5CYII=',
    ),
  );

  testWidgets('published bytes render as an image and keep the size badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TemplatePreview(
            metadata: metadata,
            publishedImageBytes: validPng,
          ),
        ),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('template-size-A4')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('template-layout-pages-portrait')),
      findsNothing,
    );
  });

  testWidgets('invalid image bytes show the existing layout silhouette', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TemplatePreview(
            metadata: metadata,
            publishedImageBytes: Uint8List.fromList(<int>[1, 2, 3]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('template-layout-pages-portrait')),
      findsOneWidget,
    );
  });

  test(
    'English and Arabic size badge strings stay supplied by localization',
    () {
      expect(
        ReportFlowStrings(
          const Locale('en'),
        ).thumbnailSizeValueLabel(ReportPageSize.a4),
        'A4',
      );
      expect(
        ReportFlowStrings(
          const Locale('ar'),
        ).thumbnailSizeValueLabel(ReportPageSize.a4),
        'A4',
      );
      expect(
        ReportFlowStrings(
          const Locale('ar'),
        ).thumbnailSizeValueLabel(ReportPageSize.thermal80),
        '٨٠مم',
      );
    },
  );
}
