import 'dart:typed_data';

import 'package:printing/printing.dart';

import 'bridge_platform_adapters.dart';

/// Native Windows print dialog boundary, separated for testability.
abstract interface class WindowsPrintClient {
  Future<bool> isAvailable();

  Future<bool> printPdf({
    required Uint8List pdfBytes,
    required String documentTitle,
  });
}

final class PrintingWindowsPrintClient implements WindowsPrintClient {
  const PrintingWindowsPrintClient();

  @override
  Future<bool> isAvailable() async => (await Printing.info()).canPrint;

  @override
  Future<bool> printPdf({
    required Uint8List pdfBytes,
    required String documentTitle,
  }) => Printing.layoutPdf(
    name: documentTitle,
    dynamicLayout: false,
    onLayout: (_) async => pdfBytes,
  );
}

/// Uses the system print dialog and reports user cancellation distinctly.
final class WindowsSystemReportPrintPlatform implements ReportPrintPlatform {
  const WindowsSystemReportPrintPlatform({
    WindowsPrintClient client = const PrintingWindowsPrintClient(),
  }) : _client = client;

  final WindowsPrintClient _client;

  @override
  Future<ReportPrintResult> printPdf(ReportPrintRequest request) async {
    if (request.pdfBytes.isEmpty) {
      return const ReportPrintResult(
        status: ReportPrintStatus.failed,
        errorCode: 'emptyPdf',
      );
    }
    try {
      if (!await _client.isAvailable()) {
        return const ReportPrintResult(
          status: ReportPrintStatus.failed,
          errorCode: 'windowsPrintUnavailable',
        );
      }
      final submitted = await _client.printPdf(
        pdfBytes: request.pdfBytes,
        documentTitle: request.documentTitle,
      );
      return submitted
          ? const ReportPrintResult.submitted()
          : const ReportPrintResult.cancelled();
    } catch (error) {
      return ReportPrintResult(
        status: ReportPrintStatus.failed,
        errorCode: 'windowsPrintFailed',
        diagnostic: error.toString(),
      );
    }
  }
}
