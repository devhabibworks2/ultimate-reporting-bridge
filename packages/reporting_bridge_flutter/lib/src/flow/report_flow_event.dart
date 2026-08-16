import 'report_flow_failure.dart';

enum ReportFlowEventType {
  initialized,
  templatesSynchronized,
  presenterSynchronized,
  previewPrepared,
  previewReady,
  exportCompleted,
  exportCancelled,
  cleanupWarning,
  failure,
}

class ReportFlowEvent {
  const ReportFlowEvent({required this.type, this.failure, this.detail});

  final ReportFlowEventType type;
  final ReportFlowFailure? failure;
  final String? detail;
}
