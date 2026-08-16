import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  test('unsupported print gateway fails closed', () async {
    const gateway = UnsupportedReportPrintPlatform();
    final result = await gateway.printPdf(
      ReportPrintRequest(
        pdfBytes: Uint8List.fromList(<int>[37, 80, 68, 70]),
        filename: 'report.pdf',
        jobId: 'job-1',
        documentTitle: 'Report',
        document: const ReportPrintDocumentMetadata(
          unit: 'mm',
          layout: 'Pages',
          size: 'A4',
          width: 210,
          height: 297,
          orientation: 'portrait',
          languageCode: 'ar',
        ),
      ),
    );

    expect(result.status, ReportPrintStatus.failed);
    expect(result.errorCode, 'platformUnsupported');
  });

  test('print request snapshots PDF bytes', () {
    final bytes = Uint8List.fromList(<int>[1, 2, 3]);
    final request = ReportPrintRequest(
      pdfBytes: bytes,
      filename: 'report.pdf',
      jobId: 'job-1',
      documentTitle: 'Report',
      document: const ReportPrintDocumentMetadata(
        unit: 'mm',
        layout: 'Thermal',
        size: '80mm',
        width: 80,
        height: 200,
        orientation: 'portrait',
        languageCode: 'en',
      ),
    );

    bytes[0] = 9;
    expect(request.pdfBytes, <int>[1, 2, 3]);
  });
}
