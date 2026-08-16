import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/src/platform/bridge_platform_adapters.dart';
import 'package:reporting_bridge_flutter/src/platform/report_print_invocation_gate.dart';

import 'test_print_request.dart';

void main() {
  for (final access in <ReportPrintActionAccess>[
    ReportPrintActionAccess.hidden,
    ReportPrintActionAccess.denied,
  ]) {
    test('$access does not reach the platform adapter', () async {
      final platform = _CountingPrintPlatform();
      const gate = ReportPrintInvocationGate();

      final result = await gate.invoke(
        access: access,
        platform: platform,
        request: testPrintRequest(),
      );

      expect(platform.calls, 0);
      expect(result.status, ReportPrintStatus.failed);
      expect(
        result.errorCode,
        access == ReportPrintActionAccess.hidden
            ? 'printActionHidden'
            : 'printActionDenied',
      );
    });
  }

  test('allowed action reaches the platform adapter once', () async {
    final platform = _CountingPrintPlatform();
    const gate = ReportPrintInvocationGate();

    final result = await gate.invoke(
      access: ReportPrintActionAccess.allowed,
      platform: platform,
      request: testPrintRequest(),
    );

    expect(platform.calls, 1);
    expect(result.status, ReportPrintStatus.submitted);
  });
}

final class _CountingPrintPlatform implements ReportPrintPlatform {
  int calls = 0;

  @override
  Future<ReportPrintResult> printPdf(ReportPrintRequest request) async {
    calls += 1;
    return const ReportPrintResult.submitted();
  }
}
