import 'package:reporting_bridge/reporting_bridge.dart';

import '../contracts/report_open_request.dart';
import 'report_flow_failure.dart';

enum ReportFlowStage {
  initializing,
  preparingResources,
  selectingTemplate,
  preparingPreview,
  previewing,
  editingSettings,
  failed,
  closing,
  closed,
}

enum ReportFlowPage {
  bootstrap,
  resourcePreparation,
  templateSelection,
  reportSettings,
  preview,
  closing,
}

enum ResourcePreparationOrigin { initialSetup, reportSettings, previewRecovery }

enum TemplateSelectionOrigin { initialSetup, reportSettings, previewRecovery }

enum ReportEntryFallbackReason {
  noSavedDefault,
  invalidSavedTemplate,
  offlinePresenterUnavailable,
  noCompatibleTemplates,
  entryPolicy,
}

class ReportSettingsDraft {
  const ReportSettingsDraft({required this.templateId, required this.mode});

  final String? templateId;
  final PresenterModePreference mode;

  ReportSettingsDraft copyWith({
    String? templateId,
    PresenterModePreference? mode,
  }) => ReportSettingsDraft(
    templateId: templateId ?? this.templateId,
    mode: mode ?? this.mode,
  );
}

enum ReportOperationStatus { idle, running, succeeded, failed }

enum PresenterRenderStatus { idle, loading, ready, failed }

enum ReportExportAction { save, share, print }

class ReportFlowState {
  const ReportFlowState({
    required this.stage,
    required this.selectedMode,
    this.templates = const <CachedTemplate>[],
    this.templateCatalogCount = 0,
    this.selectedTemplateId,
    this.committedTemplateId,
    this.committedMode,
    this.presenterLaunch,
    this.templateSync = ReportOperationStatus.idle,
    this.presenterSync = ReportOperationStatus.idle,
    this.supportShare = ReportOperationStatus.idle,
    this.cacheMaintenance = ReportOperationStatus.idle,
    this.previewLoad = ReportOperationStatus.idle,
    this.renderStatus = PresenterRenderStatus.idle,
    this.exportAction,
    this.failure,
    this.templateSyncFailure,
    this.presenterSyncFailure,
    this.cleanupWarning,
    this.presenterDownloadProgress = 0,
    this.webViewLoadProgress = 0,
    this.presenterProtocolReady = false,
    this.presenterProtocolVersion,
    this.presenterCached = false,
    this.templatesSyncedAt,
    this.presenterManifest,
    this.resourceOrigin = ResourcePreparationOrigin.initialSetup,
    this.selectionOrigin = TemplateSelectionOrigin.initialSetup,
    this.entryFallbackReason,
    this.settingsDraft,
  });

  factory ReportFlowState.initial(PresenterModePreference mode) =>
      ReportFlowState(
        stage: ReportFlowStage.initializing,
        selectedMode: mode,
        committedMode: mode,
      );

  final ReportFlowStage stage;
  final List<CachedTemplate> templates;

  /// Number of templates cached for the active system/query scope before
  /// current-report eligibility filtering is applied.
  final int templateCatalogCount;

  final String? selectedTemplateId;
  final PresenterModePreference selectedMode;
  final String? committedTemplateId;
  final PresenterModePreference? committedMode;
  final PresenterSessionLaunch? presenterLaunch;
  final ReportOperationStatus templateSync;
  final ReportOperationStatus presenterSync;
  final ReportOperationStatus supportShare;
  final ReportOperationStatus cacheMaintenance;
  final ReportOperationStatus previewLoad;
  final PresenterRenderStatus renderStatus;
  final ReportExportAction? exportAction;
  final ReportFlowFailure? failure;

  /// Resource-scoped synchronization failures stay attached to their owning
  /// cards instead of competing for the global report-flow failure slot.
  final ReportFlowFailure? templateSyncFailure;
  final ReportFlowFailure? presenterSyncFailure;

  final ReportFlowFailure? cleanupWarning;
  final double presenterDownloadProgress;
  final double webViewLoadProgress;
  final bool presenterProtocolReady;
  final int? presenterProtocolVersion;
  final bool presenterCached;
  final DateTime? templatesSyncedAt;
  final PresenterCacheManifest? presenterManifest;
  final ResourcePreparationOrigin resourceOrigin;
  final TemplateSelectionOrigin selectionOrigin;
  final ReportEntryFallbackReason? entryFallbackReason;
  final ReportSettingsDraft? settingsDraft;

  ReportFlowPage get page => switch (stage) {
    ReportFlowStage.initializing => ReportFlowPage.bootstrap,
    ReportFlowStage.preparingResources => ReportFlowPage.resourcePreparation,
    ReportFlowStage.selectingTemplate => ReportFlowPage.templateSelection,
    ReportFlowStage.editingSettings => ReportFlowPage.reportSettings,
    ReportFlowStage.preparingPreview ||
    ReportFlowStage.previewing ||
    ReportFlowStage.failed =>
      presenterLaunch == null
          ? ReportFlowPage.bootstrap
          : ReportFlowPage.preview,
    ReportFlowStage.closing || ReportFlowStage.closed => ReportFlowPage.closing,
  };

  bool get resourcesBusy =>
      templateSync == ReportOperationStatus.running ||
      presenterSync == ReportOperationStatus.running;

  bool get supportBusy =>
      supportShare == ReportOperationStatus.running ||
      cacheMaintenance == ReportOperationStatus.running;

  bool get busy => switch (stage) {
    ReportFlowStage.initializing ||
    ReportFlowStage.preparingPreview ||
    ReportFlowStage.closing => true,
    ReportFlowStage.preparingResources => resourcesBusy,
    _ => resourcesBusy || supportBusy || exportAction != null,
  };

  bool get templatesReady => templates.isNotEmpty;

  bool get presenterReadyForSelectedMode =>
      selectedMode == PresenterModePreference.online || presenterCached;

  bool get preparationReady =>
      templatesReady && presenterReadyForSelectedMode && !resourcesBusy;

  bool get exportReady =>
      stage == ReportFlowStage.previewing &&
      presenterLaunch != null &&
      presenterProtocolReady &&
      renderStatus == PresenterRenderStatus.ready &&
      exportAction == null;

  CachedTemplate? get selectedTemplate {
    final id = selectedTemplateId;
    if (id == null) return null;
    for (final template in templates) {
      if (template.id == id) return template;
    }
    return null;
  }

  CachedTemplate? get committedTemplate {
    final id = committedTemplateId;
    if (id == null) return null;
    for (final template in templates) {
      if (template.id == id) return template;
    }
    return null;
  }

  ReportFlowState copyWith({
    ReportFlowStage? stage,
    List<CachedTemplate>? templates,
    int? templateCatalogCount,
    String? selectedTemplateId,
    PresenterModePreference? selectedMode,
    String? committedTemplateId,
    PresenterModePreference? committedMode,
    PresenterSessionLaunch? presenterLaunch,
    ReportOperationStatus? templateSync,
    ReportOperationStatus? presenterSync,
    ReportOperationStatus? supportShare,
    ReportOperationStatus? cacheMaintenance,
    ReportOperationStatus? previewLoad,
    PresenterRenderStatus? renderStatus,
    ReportExportAction? exportAction,
    ReportFlowFailure? failure,
    ReportFlowFailure? templateSyncFailure,
    ReportFlowFailure? presenterSyncFailure,
    ReportFlowFailure? cleanupWarning,
    double? presenterDownloadProgress,
    double? webViewLoadProgress,
    bool? presenterProtocolReady,
    int? presenterProtocolVersion,
    bool? presenterCached,
    DateTime? templatesSyncedAt,
    PresenterCacheManifest? presenterManifest,
    ResourcePreparationOrigin? resourceOrigin,
    TemplateSelectionOrigin? selectionOrigin,
    ReportEntryFallbackReason? entryFallbackReason,
    ReportSettingsDraft? settingsDraft,
    bool clearSelectedTemplate = false,
    bool clearPresenterLaunch = false,
    bool clearExportAction = false,
    bool clearFailure = false,
    bool clearTemplateSyncFailure = false,
    bool clearPresenterSyncFailure = false,
    bool clearCleanupWarning = false,
    bool clearPresenterProtocolVersion = false,
    bool clearTemplatesSyncedAt = false,
    bool clearPresenterManifest = false,
    bool clearEntryFallbackReason = false,
    bool clearSettingsDraft = false,
  }) => ReportFlowState(
    stage: stage ?? this.stage,
    templates: templates ?? this.templates,
    templateCatalogCount: templateCatalogCount ?? this.templateCatalogCount,
    selectedTemplateId: clearSelectedTemplate
        ? null
        : (selectedTemplateId ?? this.selectedTemplateId),
    selectedMode: selectedMode ?? this.selectedMode,
    committedTemplateId: committedTemplateId ?? this.committedTemplateId,
    committedMode: committedMode ?? this.committedMode,
    presenterLaunch: clearPresenterLaunch
        ? null
        : (presenterLaunch ?? this.presenterLaunch),
    templateSync: templateSync ?? this.templateSync,
    presenterSync: presenterSync ?? this.presenterSync,
    supportShare: supportShare ?? this.supportShare,
    cacheMaintenance: cacheMaintenance ?? this.cacheMaintenance,
    previewLoad: previewLoad ?? this.previewLoad,
    renderStatus: renderStatus ?? this.renderStatus,
    exportAction: clearExportAction
        ? null
        : (exportAction ?? this.exportAction),
    failure: clearFailure ? null : (failure ?? this.failure),
    templateSyncFailure: clearTemplateSyncFailure
        ? null
        : (templateSyncFailure ?? this.templateSyncFailure),
    presenterSyncFailure: clearPresenterSyncFailure
        ? null
        : (presenterSyncFailure ?? this.presenterSyncFailure),
    cleanupWarning: clearCleanupWarning
        ? null
        : (cleanupWarning ?? this.cleanupWarning),
    presenterDownloadProgress:
        presenterDownloadProgress ?? this.presenterDownloadProgress,
    webViewLoadProgress: webViewLoadProgress ?? this.webViewLoadProgress,
    presenterProtocolReady:
        presenterProtocolReady ?? this.presenterProtocolReady,
    presenterProtocolVersion: clearPresenterProtocolVersion
        ? null
        : (presenterProtocolVersion ?? this.presenterProtocolVersion),
    presenterCached: presenterCached ?? this.presenterCached,
    templatesSyncedAt: clearTemplatesSyncedAt
        ? null
        : (templatesSyncedAt ?? this.templatesSyncedAt),
    presenterManifest: clearPresenterManifest
        ? null
        : (presenterManifest ?? this.presenterManifest),
    resourceOrigin: resourceOrigin ?? this.resourceOrigin,
    selectionOrigin: selectionOrigin ?? this.selectionOrigin,
    entryFallbackReason: clearEntryFallbackReason
        ? null
        : (entryFallbackReason ?? this.entryFallbackReason),
    settingsDraft: clearSettingsDraft
        ? null
        : (settingsDraft ?? this.settingsDraft),
  );
}
