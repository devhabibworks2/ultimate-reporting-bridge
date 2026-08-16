import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

ReportOpenRequest buildTestOpenRequest({
  String system = 'legacy_system_1',
  String reportType = 'sales_invoice',
  Map<String, dynamic> seedData = const <String, dynamic>{'id': 1},
  String? reportName,
  String? requestId,
  String? initialTemplateId,
  PresenterModePreference? presenterMode,
  ReportEntryPolicy entryPolicy = ReportEntryPolicy.smart,
  String? localeOverride,
  BridgeUiFeatures? featuresOverride,
  ReportActionPolicy actionPolicy = const ReportActionPolicy(),
  String? userId,
  String? branchId,
  String? systemUnit,
  String? customType,
  TemplateCompatibilityConstraints compatibility =
      const TemplateCompatibilityConstraints(),
  HostExternalPrintRequest? externalPrint,
  TemplateSyncFilter? filter,
  Map<String, Object?> extra = const <String, Object?>{},
}) {
  final identity = ReportIdentity.normalized(
    userId: userId,
    branchId: branchId,
    systemUnit: systemUnit,
  );
  return ReportOpenRequest(
    seedData: seedData,
    selectedTemplateCriteria: SelectedTemplateCriteria(
      reportType: UrbReportTypeCode(reportType),
      identity: identity,
      customType: customType,
    ),
    templateSyncRequest: TemplateSyncRequest(
      systemCode: UrbSystemCode(system),
      identity: identity,
      filter: filter ?? TemplateSyncFilter(reportTypes: <String>[reportType]),
      extra: extra,
    ),
    compatibility: compatibility,
    reportName: reportName,
    requestId: requestId,
    initialTemplateId: initialTemplateId,
    presenterMode: presenterMode,
    entryPolicy: entryPolicy,
    localeOverride: localeOverride,
    featuresOverride: featuresOverride,
    actionPolicy: actionPolicy,
    externalPrint: externalPrint,
  );
}
