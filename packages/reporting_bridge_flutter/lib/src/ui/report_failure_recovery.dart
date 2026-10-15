import '../flow/report_flow_failure.dart';

enum ReportRecoveryKind { invalidStyle, templates, presenterResources, generic }

ReportRecoveryKind classifyReportRecovery(ReportFlowFailure failure) {
  final path = failure.technicalPath;
  if (failure.code == ReportFlowFailureCode.renderFailed &&
      path != null &&
      (path.startsWith('styleTokens.color.') ||
          path.startsWith('styleTokens.font.'))) {
    return ReportRecoveryKind.invalidStyle;
  }

  return switch (failure.code) {
    ReportFlowFailureCode.templateSyncFailed ||
    ReportFlowFailureCode.noCompatibleTemplates => ReportRecoveryKind.templates,
    ReportFlowFailureCode.presenterIncompatible ||
    ReportFlowFailureCode.presenterSyncFailed =>
      ReportRecoveryKind.presenterResources,
    _ => ReportRecoveryKind.generic,
  };
}
