import 'bridge_platform_adapters.dart';

enum ReportPrintActionAccess { hidden, denied, allowed }

final class ReportPrintInvocationGate {
  const ReportPrintInvocationGate();

  Future<ReportPrintResult> invoke({
    required ReportPrintActionAccess access,
    required ReportPrintPlatform platform,
    required ReportPrintRequest request,
  }) {
    return switch (access) {
      ReportPrintActionAccess.hidden => Future<ReportPrintResult>.value(
        const ReportPrintResult(
          status: ReportPrintStatus.failed,
          errorCode: 'printActionHidden',
        ),
      ),
      ReportPrintActionAccess.denied => Future<ReportPrintResult>.value(
        const ReportPrintResult(
          status: ReportPrintStatus.failed,
          errorCode: 'printActionDenied',
        ),
      ),
      ReportPrintActionAccess.allowed => platform.printPdf(request),
    };
  }
}
