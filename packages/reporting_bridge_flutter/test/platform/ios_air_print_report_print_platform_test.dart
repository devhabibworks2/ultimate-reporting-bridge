import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/src/platform/bridge_platform_adapters.dart';
import 'package:reporting_bridge_flutter/src/platform/ios_air_print_report_print_platform.dart';

import 'test_print_request.dart';

void main() {
  test('returns typed failure when AirPrint is unavailable', () async {
    final client = _FakeIosAirPrintClient()..available = false;
    final platform = IosAirPrintReportPrintPlatform(client: client);

    final result = await platform.printPdf(testPrintRequest());

    expect(result.status, ReportPrintStatus.failed);
    expect(result.errorCode, 'airPrintUnavailable');
    expect(client.printCalls, 0);
  });

  test('maps AirPrint cancellation', () async {
    final client = _FakeIosAirPrintClient()..submitted = false;
    final platform = IosAirPrintReportPrintPlatform(client: client);

    final result = await platform.printPdf(testPrintRequest());

    expect(result.status, ReportPrintStatus.cancelled);
    expect(client.printCalls, 1);
  });

  test(
    'maps AirPrint submission and forwards authoritative PDF bytes',
    () async {
      final client = _FakeIosAirPrintClient();
      final platform = IosAirPrintReportPrintPlatform(client: client);
      final request = testPrintRequest();

      final result = await platform.printPdf(request);

      expect(result.status, ReportPrintStatus.submitted);
      expect(client.receivedBytes, request.pdfBytes);
      expect(client.receivedTitle, request.documentTitle);
    },
  );

  test('maps AirPrint exception to typed failure', () async {
    final client = _FakeIosAirPrintClient()..failure = StateError('printer');
    final platform = IosAirPrintReportPrintPlatform(client: client);

    final result = await platform.printPdf(testPrintRequest());

    expect(result.status, ReportPrintStatus.failed);
    expect(result.errorCode, 'airPrintFailed');
    expect(result.diagnostic, contains('printer'));
  });
}

final class _FakeIosAirPrintClient implements IosAirPrintClient {
  bool available = true;
  bool submitted = true;
  Object? failure;
  int printCalls = 0;
  Uint8List? receivedBytes;
  String? receivedTitle;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> printPdf({
    required Uint8List pdfBytes,
    required String documentTitle,
  }) async {
    printCalls += 1;
    receivedBytes = pdfBytes;
    receivedTitle = documentTitle;
    final error = failure;
    if (error != null) throw error;
    return submitted;
  }
}
