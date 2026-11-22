import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/src/platform/bridge_platform_adapters.dart';
import 'package:reporting_bridge_flutter/src/platform/windows_system_report_print_platform.dart';

import 'test_print_request.dart';

void main() {
  test('rejects empty PDF without invoking native printing', () async {
    final client = _FakeWindowsPrintClient();
    final source = testPrintRequest();
    final request = ReportPrintRequest(
      pdfBytes: Uint8List(0),
      filename: source.filename,
      jobId: source.jobId,
      documentTitle: source.documentTitle,
      document: source.document,
    );

    final result = await WindowsSystemReportPrintPlatform(
      client: client,
    ).printPdf(request);

    expect(result.status, ReportPrintStatus.failed);
    expect(result.errorCode, 'emptyPdf');
    expect(client.availabilityCalls, 0);
    expect(client.printCalls, 0);
  });

  test(
    'returns typed failure without opening dialog if Windows cannot print',
    () async {
      final client = _FakeWindowsPrintClient()..available = false;
      final result = await WindowsSystemReportPrintPlatform(
        client: client,
      ).printPdf(testPrintRequest());

      expect(result.status, ReportPrintStatus.failed);
      expect(result.errorCode, 'windowsPrintUnavailable');
      expect(client.printCalls, 0);
    },
  );

  test(
    'forwards authoritative PDF bytes and title into Windows print dialog',
    () async {
      final client = _FakeWindowsPrintClient();
      final request = testPrintRequest();
      final result = await WindowsSystemReportPrintPlatform(
        client: client,
      ).printPdf(request);

      expect(result.status, ReportPrintStatus.submitted);
      expect(client.receivedBytes, orderedEquals(request.pdfBytes));
      expect(client.receivedTitle, request.documentTitle);
      expect(client.printCalls, 1);
    },
  );

  test(
    'Windows print dialog cancellation is not reported as an error',
    () async {
      final client = _FakeWindowsPrintClient()..submitted = false;
      final result = await WindowsSystemReportPrintPlatform(
        client: client,
      ).printPdf(testPrintRequest());

      expect(result.status, ReportPrintStatus.cancelled);
      expect(client.printCalls, 1);
    },
  );

  test('native Windows printing failure is typed without throwing', () async {
    final client = _FakeWindowsPrintClient()
      ..failure = StateError('printer failed');
    final result = await WindowsSystemReportPrintPlatform(
      client: client,
    ).printPdf(testPrintRequest());

    expect(result.status, ReportPrintStatus.failed);
    expect(result.errorCode, 'windowsPrintFailed');
    expect(result.diagnostic, contains('printer failed'));
  });
}

final class _FakeWindowsPrintClient implements WindowsPrintClient {
  bool available = true;
  bool submitted = true;
  Object? failure;
  int availabilityCalls = 0;
  int printCalls = 0;
  Uint8List? receivedBytes;
  String? receivedTitle;

  @override
  Future<bool> isAvailable() async {
    availabilityCalls++;
    return available;
  }

  @override
  Future<bool> printPdf({
    required Uint8List pdfBytes,
    required String documentTitle,
  }) async {
    printCalls++;
    receivedBytes = pdfBytes;
    receivedTitle = documentTitle;
    if (failure != null) throw failure!;
    return submitted;
  }
}
