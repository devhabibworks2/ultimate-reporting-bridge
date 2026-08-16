import 'report_flow_failure.dart';

sealed class ReportResult {
  const ReportResult();
}

class ReportClosed extends ReportResult {
  const ReportClosed({this.cleanupWarning});
  final ReportFlowFailure? cleanupWarning;
}

class ReportCancelled extends ReportResult {
  const ReportCancelled();
}

class ReportFailed extends ReportResult {
  const ReportFailed(this.failure);
  final ReportFlowFailure failure;
}
