import 'dart:typed_data';

import 'package:printing/printing.dart';

import 'bridge_platform_adapters.dart';

abstract interface class IosAirPrintClient {
  Future<bool> isAvailable();

  Future<bool> printPdf({
    required Uint8List pdfBytes,
    required String documentTitle,
  });
}

final class PrintingIosAirPrintClient implements IosAirPrintClient {
  const PrintingIosAirPrintClient();

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

final class IosAirPrintReportPrintPlatform implements ReportPrintPlatform {
  const IosAirPrintReportPrintPlatform({
    IosAirPrintClient client = const PrintingIosAirPrintClient(),
  }) : _client = client;

  final IosAirPrintClient _client;

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
          errorCode: 'airPrintUnavailable',
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
        errorCode: 'airPrintFailed',
        diagnostic: error.toString(),
      );
    }
  }
}
