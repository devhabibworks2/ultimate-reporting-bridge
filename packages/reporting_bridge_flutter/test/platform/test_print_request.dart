import 'dart:typed_data';

import 'package:reporting_bridge_flutter/src/platform/bridge_platform_adapters.dart';

ReportPrintRequest testPrintRequest({
  Uint8List? pdfBytes,
  String languageCode = 'ar',
  Map<String, Object?> extra = const <String, Object?>{},
}) => ReportPrintRequest(
  pdfBytes: pdfBytes ?? Uint8List.fromList(<int>[37, 80, 68, 70]),
  filename: 'invoice.pdf',
  jobId: 'job-42',
  documentTitle: 'Invoice 42',
  document: ReportPrintDocumentMetadata(
    unit: 'mm',
    layout: 'pages',
    size: 'a4',
    width: 210,
    height: 297,
    orientation: 'portrait',
    languageCode: languageCode,
  ),
  extra: extra,
);
