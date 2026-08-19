import 'package:reporting_bridge/reporting_bridge.dart';

import '../flow/json_object_snapshot.dart';
import '../flow/report_action_policy.dart';
import '../flow/urb_identifiers.dart';
import '../ui/bridge_ui_features.dart';
import 'external_printer_contract.dart';
import 'selected_template_criteria.dart';
import 'template_compatibility_constraints.dart';
import 'template_sync_request.dart';

enum PresenterModePreference { online, offline }

enum ReportEntryPolicy { smart, alwaysPrepare, alwaysSelectTemplate }

extension PresenterModePreferenceX on PresenterModePreference {
  PresenterSessionMode get sessionMode => switch (this) {
    PresenterModePreference.online => PresenterSessionMode.online,
    PresenterModePreference.offline => PresenterSessionMode.offline,
  };
}

/// Host entry request for opening one report through the Bridge.
///
/// Print options on [externalPrint] are Host-owned title/extra only.
/// Final printer language/layout/size/unit/orientation/dimensions come from
/// the selected template metadata at print time.
final class ReportOpenRequest {
  ReportOpenRequest({
    required Map<String, dynamic> seedData,
    required this.selectedTemplateCriteria,
    required this.templateSyncRequest,
    this.compatibility = const TemplateCompatibilityConstraints(),
    String? reportName,
    String? requestId,
    String? initialTemplateId,
    this.presenterMode,
    this.entryPolicy = ReportEntryPolicy.smart,
    String? localeOverride,
    this.featuresOverride,
    this.actionPolicy = const ReportActionPolicy(),
    this.externalPrint,
    this.directPrintAfterSave = false,
  }) : seedData = snapshotJsonObject(seedData),
       reportName = _trimmedOrNull(reportName),
       requestId = _trimmedOrNull(requestId),
       initialTemplateId = _trimmedOrNull(initialTemplateId),
       localeOverride = _normalizedLocale(localeOverride) {
    final selectionIdentity = selectedTemplateCriteria.identity;
    final syncIdentity = templateSyncRequest.identity;
    if (selectionIdentity != syncIdentity) {
      throw ArgumentError(
        'selectedTemplateCriteria.identity and '
        'templateSyncRequest.identity must be equal '
        '(selection=$selectionIdentity, sync=$syncIdentity).',
      );
    }
  }

  final Map<String, dynamic> seedData;
  final SelectedTemplateCriteria selectedTemplateCriteria;
  final TemplateSyncRequest templateSyncRequest;
  final TemplateCompatibilityConstraints compatibility;

  UrbReportTypeCode get reportType => selectedTemplateCriteria.reportType;

  final String? reportName;
  final String? requestId;
  final String? initialTemplateId;
  final PresenterModePreference? presenterMode;
  final ReportEntryPolicy entryPolicy;
  final String? localeOverride;
  final BridgeUiFeatures? featuresOverride;
  final ReportActionPolicy actionPolicy;
  final HostExternalPrintRequest? externalPrint;
  final bool directPrintAfterSave;

  ReportOpenRequest copyWith({
    BridgeUiFeatures? featuresOverride,
    ReportActionPolicy? actionPolicy,
    ReportEntryPolicy? entryPolicy,
    String? localeOverride,
    bool? directPrintAfterSave,
  }) => ReportOpenRequest(
    seedData: seedData,
    selectedTemplateCriteria: selectedTemplateCriteria,
    templateSyncRequest: templateSyncRequest,
    compatibility: compatibility,
    reportName: reportName,
    requestId: requestId,
    initialTemplateId: initialTemplateId,
    presenterMode: presenterMode,
    entryPolicy: entryPolicy ?? this.entryPolicy,
    localeOverride: localeOverride ?? this.localeOverride,
    featuresOverride: featuresOverride ?? this.featuresOverride,
    actionPolicy: actionPolicy ?? this.actionPolicy,
    externalPrint: externalPrint,
    directPrintAfterSave: directPrintAfterSave ?? this.directPrintAfterSave,
  );
}

String? _trimmedOrNull(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String? _normalizedLocale(String? value) {
  final normalized = _trimmedOrNull(value)?.toLowerCase();
  if (normalized == null) return null;
  final language = normalized.split(RegExp('[-_]')).first;
  if (language == 'ar' || language == 'en') return language;
  throw ArgumentError.value(
    value,
    'localeOverride',
    'Supported locale overrides are ar and en (with optional region tags).',
  );
}
