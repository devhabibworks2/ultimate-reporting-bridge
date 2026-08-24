import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:reporting_bridge/reporting_bridge.dart';

import '../contracts/report_open_request.dart';
import '../persistence/report_flow_preference_store.dart';
import '../platform/presenter_surface_binding.dart';
import '../support/report_support_package.dart';
import '../ui/bridge_ui_features.dart';
import 'report_flow_controller.dart';
import 'report_flow_event.dart';
import 'report_flow_failure.dart';
import 'report_flow_runtime.dart';
import 'report_flow_state.dart';
import 'report_result.dart';
import 'report_template_metadata.dart';

class ReportFlowControllerImpl
    implements
        ReportFlowController,
        ReportFlowStructuredFailureController,
        ReportFlowSupportController {
  ReportFlowControllerImpl({
    required this.request,
    required ReportFlowRuntime runtime,
    BridgeUiFeatures features = const BridgeUiFeatures(),
    this.renderTimeout = const Duration(seconds: 30),
    VoidCallback? onDisposed,
  }) : _runtime = runtime,
       _features = features,
       _onDisposed = onDisposed,
       _value = ReportFlowState.initial(
         request.presenterMode ?? PresenterModePreference.online,
       );

  final ReportFlowRuntime _runtime;
  final BridgeUiFeatures _features;
  final VoidCallback? _onDisposed;
  final Duration renderTimeout;
  final _ReportFlowNotifier _notifier = _ReportFlowNotifier();
  final StreamController<ReportFlowEvent> _events =
      StreamController<ReportFlowEvent>.broadcast(sync: true);

  @override
  final ReportOpenRequest request;

  late final ReportPreferenceScope _scope = ReportPreferenceScope(
    connectionKey: _runtime.connection.preferenceSourceKey,
    system: request.templateSyncRequest.systemCode.value,
    reportType: request.reportType.value,
    branchId: request.selectedTemplateCriteria.identity.branchId,
    userId: request.selectedTemplateCriteria.identity.userId,
    systemUnit: request.selectedTemplateCriteria.identity.systemUnit,
    language: request.compatibility.language?.value,
    layout: request.compatibility.layout?.value,
    size: request.compatibility.size?.value,
    customType: request.selectedTemplateCriteria.customType,
  );

  ReportFlowState _value;
  bool _disposed = false;
  bool _initialized = false;
  bool _presenterWasOpened = false;
  Future<void>? _previewPreparationFuture;
  Future<ReportResult>? _closeFuture;
  Timer? _renderWatchdog;
  ReportFlowPreferences? _persistedPreferences;

  @override
  ReportFlowState get value => _value;

  @override
  Stream<ReportFlowEvent> get events => _events.stream;

  @override
  PresenterSurfaceBinding get presenterSurface => _runtime.surfaceBinding;

  @override
  void addListener(VoidCallback listener) => _notifier.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _notifier.removeListener(listener);

  @override
  Future<void> initialize() async {
    _ensureActive();
    if (_initialized) return;
    _initialized = true;
    _set(
      _value.copyWith(stage: ReportFlowStage.initializing, clearFailure: true),
    );

    try {
      ReportFlowPreferences? stored;
      try {
        stored = await _runtime.preferences.load(_scope);
      } catch (error) {
        _addEvent(
          ReportFlowEvent(
            type: ReportFlowEventType.failure,
            failure: ReportFlowFailure(
              code: ReportFlowFailureCode.persistenceFailed,
              diagnostic: error.toString(),
            ),
          ),
        );
      }

      _persistedPreferences = stored;
      final mode =
          request.presenterMode ??
          stored?.mode ??
          PresenterModePreference.online;
      final catalog = await _runtime.bridgeClient.listTemplates();
      var templates = _compatibleTemplates(catalog);
      var presenterCached = false;
      PresenterCacheManifest? presenterManifest;
      try {
        final status = await _runtime.bridgeClient.getStatus();
        presenterCached = status.presenterCached;
        presenterManifest = status.presenterManifest;
      } catch (_) {
        // Online setup can continue even when local cache status is unavailable.
      }

      final requestedTemplateId =
          request.initialTemplateId ?? stored?.templateId;
      var candidate = _validTemplateId(templates, requestedTemplateId);
      final requiresAuthoritativeTemplateResolution =
          templates.isEmpty ||
          (stored != null &&
              request.initialTemplateId == null &&
              requestedTemplateId != null &&
              candidate == null);

      _set(
        _value.copyWith(
          stage: ReportFlowStage.preparingResources,
          templates: templates,
          templateCatalogCount: catalog.length,
          selectedTemplateId:
              candidate ?? (templates.length == 1 ? templates.single.id : null),
          clearSelectedTemplate: candidate == null && templates.length != 1,
          selectedMode: mode,
          committedTemplateId: candidate,
          committedMode: mode,
          templateSync: templates.isEmpty
              ? ReportOperationStatus.idle
              : ReportOperationStatus.succeeded,
          presenterSync: presenterCached
              ? ReportOperationStatus.succeeded
              : ReportOperationStatus.idle,
          presenterCached: presenterCached,
          presenterManifest: presenterManifest,
          presenterDownloadProgress: presenterCached ? 1 : 0,
          entryFallbackReason:
              request.entryPolicy == ReportEntryPolicy.alwaysPrepare
              ? ReportEntryFallbackReason.entryPolicy
              : null,
          clearFailure: true,
        ),
      );
      _addEvent(const ReportFlowEvent(type: ReportFlowEventType.initialized));

      if (requiresAuthoritativeTemplateResolution) {
        final synchronized = await _synchronizeTemplatesForEntry();
        if (_disposed || !synchronized) return;
        templates = _value.templates;
        candidate = _validTemplateId(templates, requestedTemplateId);
      }

      final storedTemplateId = stored?.templateId?.trim();
      // Every workflow catalog lookup is scoped by the active
      // TemplateSyncRequest filter/extra. Absence from that result proves only
      // that the saved template is unavailable for this request; it does not
      // prove the template was globally deleted. Preserve the V5 selection
      // until a separate global existence/tombstone authority can prove that.
      final storedTemplateUnavailableForRequest =
          stored != null &&
          storedTemplateId != null &&
          storedTemplateId.isNotEmpty &&
          candidate == null &&
          request.initialTemplateId == null;

      // Do not auto-adopt another eligible template when the saved template is
      // unavailable for the current request.
      final selected = storedTemplateUnavailableForRequest
          ? null
          : (candidate ?? (templates.length == 1 ? templates.single.id : null));
      final fallbackReason = switch (request.entryPolicy) {
        ReportEntryPolicy.alwaysPrepare =>
          ReportEntryFallbackReason.entryPolicy,
        ReportEntryPolicy.alwaysSelectTemplate =>
          templates.isEmpty
              ? ReportEntryFallbackReason.noCompatibleTemplates
              : null,
        ReportEntryPolicy.smart when requestedTemplateId == null =>
          ReportEntryFallbackReason.noSavedDefault,
        ReportEntryPolicy.smart
            when mode == PresenterModePreference.offline && !presenterCached =>
          ReportEntryFallbackReason.offlinePresenterUnavailable,
        ReportEntryPolicy.smart when storedTemplateUnavailableForRequest =>
          ReportEntryFallbackReason.noCompatibleTemplates,
        ReportEntryPolicy.smart when candidate == null && selected == null =>
          ReportEntryFallbackReason.noCompatibleTemplates,
        ReportEntryPolicy.smart => null,
      };
      _set(
        _value.copyWith(
          stage: ReportFlowStage.preparingResources,
          templates: templates,
          templateCatalogCount: requiresAuthoritativeTemplateResolution
              ? _value.templateCatalogCount
              : catalog.length,
          selectedTemplateId: selected,
          clearSelectedTemplate: selected == null,
          selectedMode: mode,
          committedTemplateId: selected,
          committedMode: mode,
          templateSync: templates.isEmpty
              ? ReportOperationStatus.idle
              : ReportOperationStatus.succeeded,
          presenterSync: presenterCached
              ? ReportOperationStatus.succeeded
              : ReportOperationStatus.idle,
          presenterCached: presenterCached,
          presenterManifest: presenterManifest,
          presenterDownloadProgress: presenterCached ? 1 : 0,
          entryFallbackReason: fallbackReason,
          clearFailure: true,
        ),
      );

      if (request.entryPolicy == ReportEntryPolicy.alwaysSelectTemplate &&
          _value.templates.isNotEmpty) {
        openTemplateSelection();
      } else if (request.entryPolicy == ReportEntryPolicy.smart &&
          storedTemplateUnavailableForRequest &&
          _value.templates.isNotEmpty) {
        openTemplateSelection();
      } else if (request.entryPolicy == ReportEntryPolicy.smart &&
          fallbackReason == null) {
        await preparePreview();
      }
    } catch (error) {
      _failFrom(error, ReportFlowFailureCode.unknown);
    }
  }

  @override
  Future<void> syncTemplates() async {
    _ensureActive();
    if (_operationInProgress ||
        _value.stage != ReportFlowStage.preparingResources) {
      return;
    }
    final returnStage = _resourceReturnStage();
    final preservePreviewFailure =
        _value.resourceOrigin == ResourcePreparationOrigin.previewRecovery;
    _set(
      _value.copyWith(
        stage: returnStage,
        templateSync: ReportOperationStatus.running,
        clearTemplateSyncFailure: true,
        clearFailure: !preservePreviewFailure,
      ),
    );
    try {
      final synchronized = await _synchronizeTemplateCatalog();
      final templates = synchronized.compatibleTemplates;
      final selected =
          _validTemplateId(templates, _value.selectedTemplateId) ??
          _validTemplateId(templates, request.initialTemplateId) ??
          (templates.length == 1 ? templates.single.id : null);
      _set(
        _value.copyWith(
          stage: returnStage,
          templates: templates,
          templateCatalogCount: synchronized.catalogCount,
          selectedTemplateId: selected,
          clearSelectedTemplate: selected == null,
          templateSync: ReportOperationStatus.succeeded,
          templatesSyncedAt: DateTime.now(),
          entryFallbackReason: templates.isEmpty
              ? ReportEntryFallbackReason.noCompatibleTemplates
              : null,
          clearEntryFallbackReason: templates.isNotEmpty,
          clearTemplateSyncFailure: true,
          clearFailure: !preservePreviewFailure,
        ),
      );
      _addEvent(
        const ReportFlowEvent(type: ReportFlowEventType.templatesSynchronized),
      );
    } catch (error) {
      final failure = _asFailure(
        error,
        ReportFlowFailureCode.templateSyncFailed,
      );
      _set(
        _value.copyWith(
          stage: returnStage,
          templateSync: ReportOperationStatus.failed,
          templateSyncFailure: failure,
        ),
      );
      _addEvent(
        ReportFlowEvent(type: ReportFlowEventType.failure, failure: failure),
      );
    }
  }

  Future<bool> _synchronizeTemplatesForEntry() async {
    _set(
      _value.copyWith(
        stage: ReportFlowStage.preparingResources,
        templateSync: ReportOperationStatus.running,
        clearTemplateSyncFailure: true,
        clearFailure: true,
      ),
    );
    try {
      final synchronized = await _synchronizeTemplateCatalog();
      final templates = synchronized.compatibleTemplates;
      final selected =
          _validTemplateId(templates, _value.selectedTemplateId) ??
          _validTemplateId(templates, request.initialTemplateId) ??
          (templates.length == 1 ? templates.single.id : null);
      _set(
        _value.copyWith(
          stage: ReportFlowStage.preparingResources,
          templates: templates,
          templateCatalogCount: synchronized.catalogCount,
          selectedTemplateId: selected,
          clearSelectedTemplate: selected == null,
          templateSync: ReportOperationStatus.succeeded,
          templatesSyncedAt: DateTime.now(),
          entryFallbackReason: templates.isEmpty
              ? ReportEntryFallbackReason.noCompatibleTemplates
              : null,
          clearEntryFallbackReason: templates.isNotEmpty,
          clearTemplateSyncFailure: true,
          clearFailure: true,
        ),
      );
      _addEvent(
        const ReportFlowEvent(type: ReportFlowEventType.templatesSynchronized),
      );
      return templates.isNotEmpty;
    } catch (error) {
      final failure = _asFailure(
        error,
        ReportFlowFailureCode.templateSyncFailed,
      );
      _set(
        _value.copyWith(
          stage: ReportFlowStage.preparingResources,
          templateSync: ReportOperationStatus.failed,
          entryFallbackReason: ReportEntryFallbackReason.noCompatibleTemplates,
          templateSyncFailure: failure,
        ),
      );
      _addEvent(
        ReportFlowEvent(type: ReportFlowEventType.failure, failure: failure),
      );
      return false;
    }
  }

  Future<({int catalogCount, List<CachedTemplate> compatibleTemplates})>
  _synchronizeTemplateCatalog() async {
    final sync = request.templateSyncRequest;
    final summary = await _runtime.connection.diagnostics
        .traceApi<TemplateSyncSummary>(
          operation: 'syncTemplates',
          method: 'POST',
          uri: resolveBridgeApiRoute(
            _runtime.connection.endpoints.apiBaseUrl,
            'presenter/templates/query',
          ),
          details: <String, Object?>{
            'systemCode': sync.systemCode.value,
            'currentReportType': request.reportType.value,
            'reportTypes': sync.filter.reportTypes,
            'layouts': sync.filter.layouts,
            'sizes': sync.filter.sizes,
            'languages': sync.filter.languages,
            'units': sync.filter.units,
            'orientations': sync.filter.orientations,
            'filterFingerprint': sync.filter.fingerprint,
            'hasExtra': sync.extra.isNotEmpty,
          },
          action: () => _runtime.bridgeClient.syncTemplates(),
        );
    if (summary.errors.isNotEmpty) {
      throw ReportFlowFailure(
        code: ReportFlowFailureCode.templateSyncFailed,
        diagnostic: summary.errors.join('\n'),
      );
    }
    final catalog = await _runtime.bridgeClient.listTemplates();
    return (
      catalogCount: catalog.length,
      compatibleTemplates: _compatibleTemplates(catalog),
    );
  }

  @override
  Future<void> syncPresenter() => _syncPresenter();

  Future<void> _syncPresenter({
    bool allowDuringPreviewPreparation = false,
  }) async {
    _ensureActive();
    if (_value.resourcesBusy ||
        (!allowDuringPreviewPreparation &&
            (_previewPreparationFuture != null ||
                _value.stage != ReportFlowStage.preparingResources))) {
      return;
    }
    final returnStage = _resourceReturnStage();
    _set(
      _value.copyWith(
        stage: returnStage,
        presenterSync: ReportOperationStatus.running,
        presenterDownloadProgress: 0,
        clearPresenterSyncFailure: true,
        clearFailure: true,
      ),
    );
    try {
      final explicitManifest = _runtime.connection.bundleManifestUrl?.trim();
      final manifestUri =
          explicitManifest != null && explicitManifest.isNotEmpty
          ? Uri.parse(explicitManifest)
          : resolveBridgeApiRoute(
              _runtime.connection.endpoints.apiBaseUrl,
              'presenter/bundles/manifest',
            );
      final manifest = await _runtime.connection.diagnostics
          .traceApi<PresenterCacheManifest>(
            operation: 'syncPresenter',
            method: 'GET',
            uri: manifestUri,
            details: <String, Object?>{'includesBundleDownload': true},
            action: () => _runtime.bridgeClient.syncPresenter(
              onProgress: (progress) {
                if (_disposed) return;
                _set(_value.copyWith(presenterDownloadProgress: progress));
              },
            ),
          );
      _set(
        _value.copyWith(
          stage: returnStage,
          presenterSync: ReportOperationStatus.succeeded,
          presenterCached: true,
          presenterManifest: manifest,
          presenterDownloadProgress: 1,
          clearPresenterSyncFailure: true,
          clearFailure: true,
        ),
      );
      _addEvent(
        const ReportFlowEvent(type: ReportFlowEventType.presenterSynchronized),
      );
    } catch (error) {
      final failure = _asFailure(
        error,
        ReportFlowFailureCode.presenterSyncFailed,
      );
      _set(
        _value.copyWith(
          stage: returnStage,
          presenterSync: ReportOperationStatus.failed,
          presenterSyncFailure: failure,
        ),
      );
      _addEvent(
        ReportFlowEvent(type: ReportFlowEventType.failure, failure: failure),
      );
    }
  }

  @override
  Future<void> continueFromPreparation() async {
    _ensureActive();
    if (_value.resourcesBusy ||
        _value.stage != ReportFlowStage.preparingResources) {
      return;
    }

    if (_value.templates.isEmpty) {
      await syncTemplates();
      if (_value.templates.isEmpty) return;
    }
    if (_value.selectedMode == PresenterModePreference.offline &&
        !_value.presenterCached) {
      await syncPresenter();
      if (!_value.presenterCached) return;
    }

    if (_value.resourceOrigin == ResourcePreparationOrigin.reportSettings) {
      _set(
        _value.copyWith(
          stage: ReportFlowStage.editingSettings,
          clearFailure: true,
        ),
      );
      return;
    }
    if (_value.resourceOrigin == ResourcePreparationOrigin.previewRecovery) {
      if (_value.selectedTemplate == null) {
        openTemplateSelection(origin: TemplateSelectionOrigin.previewRecovery);
        return;
      }
      _set(_value.copyWith(stage: ReportFlowStage.failed));
      await preparePreview();
      return;
    }
    openTemplateSelection();
  }

  @override
  void openTemplateSelection({
    TemplateSelectionOrigin origin = TemplateSelectionOrigin.initialSetup,
  }) {
    _ensureActive();
    if (_operationInProgress || _value.templates.isEmpty) return;
    final draft = origin == TemplateSelectionOrigin.reportSettings
        ? (_value.settingsDraft ??
              ReportSettingsDraft(
                templateId:
                    _value.committedTemplateId ?? _value.selectedTemplateId,
                mode: _value.committedMode ?? _value.selectedMode,
              ))
        : _value.settingsDraft;
    final draftTemplateId = switch (origin) {
      TemplateSelectionOrigin.reportSettings => _validTemplateId(
        _value.templates,
        draft?.templateId,
      ),
      TemplateSelectionOrigin.previewRecovery => _validTemplateId(
        _value.templates,
        _value.committedTemplateId ?? _value.selectedTemplateId,
      ),
      TemplateSelectionOrigin.initialSetup => _value.selectedTemplateId,
    };
    _set(
      _value.copyWith(
        stage: ReportFlowStage.selectingTemplate,
        selectionOrigin: origin,
        selectedTemplateId: draftTemplateId,
        clearSelectedTemplate: draftTemplateId == null,
        settingsDraft: draft,
        clearFailure: origin != TemplateSelectionOrigin.previewRecovery,
      ),
    );
  }

  @override
  void openResourcePreparation(ResourcePreparationOrigin origin) {
    _ensureActive();
    if (_operationInProgress) return;
    _set(
      _value.copyWith(
        stage: ReportFlowStage.preparingResources,
        resourceOrigin: origin,
        clearFailure: origin != ResourcePreparationOrigin.previewRecovery,
      ),
    );
  }

  @override
  void returnFromResourcePreparation() {
    _ensureActive();
    if (_operationInProgress ||
        _value.stage != ReportFlowStage.preparingResources ||
        _value.resourceOrigin == ResourcePreparationOrigin.initialSetup) {
      return;
    }
    final recovery =
        _value.resourceOrigin == ResourcePreparationOrigin.previewRecovery;
    _set(
      _value.copyWith(
        stage: _value.resourceOrigin == ResourcePreparationOrigin.reportSettings
            ? ReportFlowStage.editingSettings
            : recovery
            ? ReportFlowStage.failed
            : ReportFlowStage.previewing,
        clearFailure: !recovery,
      ),
    );
  }

  @override
  void backToPreparation() {
    _ensureActive();
    if (_operationInProgress ||
        _value.stage != ReportFlowStage.selectingTemplate) {
      return;
    }
    if (_value.selectionOrigin == TemplateSelectionOrigin.reportSettings) {
      final draft = _value.settingsDraft;
      final draftTemplateId = _validTemplateId(
        _value.templates,
        draft?.templateId,
      );
      _set(
        _value.copyWith(
          stage: ReportFlowStage.editingSettings,
          selectedTemplateId: draftTemplateId,
          clearSelectedTemplate: draftTemplateId == null,
          selectedMode: draft?.mode ?? _value.selectedMode,
          clearFailure: true,
        ),
      );
    } else if (_value.selectionOrigin ==
        TemplateSelectionOrigin.previewRecovery) {
      final committed = _validTemplateId(
        _value.templates,
        _value.committedTemplateId,
      );
      _set(
        _value.copyWith(
          stage: ReportFlowStage.failed,
          selectedTemplateId: committed,
          clearSelectedTemplate: committed == null,
        ),
      );
    } else {
      openResourcePreparation(ResourcePreparationOrigin.initialSetup);
    }
  }

  @override
  void selectTemplate(String templateId) {
    _ensureActive();
    if (_operationInProgress ||
        (_value.stage != ReportFlowStage.selectingTemplate &&
            _value.stage != ReportFlowStage.editingSettings) ||
        _validTemplateId(_value.templates, templateId) == null) {
      return;
    }
    final draft = _value.stage == ReportFlowStage.editingSettings
        ? (_value.settingsDraft ??
                  ReportSettingsDraft(
                    templateId: _value.selectedTemplateId,
                    mode: _value.selectedMode,
                  ))
              .copyWith(templateId: templateId)
        : _value.settingsDraft;
    _set(
      _value.copyWith(
        selectedTemplateId: templateId,
        settingsDraft: draft,
        clearFailure:
            _value.selectionOrigin != TemplateSelectionOrigin.previewRecovery,
      ),
    );
  }

  @override
  void confirmTemplateSelection() {
    _ensureActive();
    if (_operationInProgress ||
        _value.stage != ReportFlowStage.selectingTemplate ||
        _value.selectionOrigin != TemplateSelectionOrigin.reportSettings ||
        _value.selectedTemplate == null) {
      return;
    }
    _set(
      _value.copyWith(
        stage: ReportFlowStage.editingSettings,
        settingsDraft:
            (_value.settingsDraft ??
                    ReportSettingsDraft(
                      templateId: _value.selectedTemplateId,
                      mode: _value.selectedMode,
                    ))
                .copyWith(templateId: _value.selectedTemplateId),
        clearFailure: true,
      ),
    );
  }

  @override
  void selectMode(PresenterModePreference mode) {
    _ensureActive();
    if (_operationInProgress ||
        (_value.stage != ReportFlowStage.preparingResources &&
            _value.stage != ReportFlowStage.editingSettings)) {
      return;
    }
    final settingsContext =
        _value.stage == ReportFlowStage.editingSettings ||
        (_value.stage == ReportFlowStage.preparingResources &&
            _value.resourceOrigin == ResourcePreparationOrigin.reportSettings);
    final draft = settingsContext
        ? (_value.settingsDraft ??
                  ReportSettingsDraft(
                    templateId: _value.selectedTemplateId,
                    mode: _value.selectedMode,
                  ))
              .copyWith(mode: mode)
        : _value.settingsDraft;
    _set(
      _value.copyWith(
        selectedMode: mode,
        settingsDraft: draft,
        clearFailure: true,
      ),
    );
  }

  @override
  void editSettings() {
    _ensureActive();
    if (_operationInProgress ||
        _value.presenterLaunch == null ||
        (_value.stage != ReportFlowStage.previewing &&
            _value.stage != ReportFlowStage.failed)) {
      return;
    }
    _cancelRenderWatchdog();
    _set(
      _value.copyWith(
        stage: ReportFlowStage.editingSettings,
        committedTemplateId:
            _value.committedTemplateId ?? _value.selectedTemplateId,
        committedMode: _value.committedMode ?? _value.selectedMode,
        settingsDraft: ReportSettingsDraft(
          templateId: _value.committedTemplateId ?? _value.selectedTemplateId,
          mode: _value.committedMode ?? _value.selectedMode,
        ),
        clearFailure: true,
      ),
    );
  }

  @override
  Future<void> commitSettings() async {
    _ensureActive();
    if (_value.stage != ReportFlowStage.editingSettings) return;
    final draft = _value.settingsDraft;
    if (draft != null) {
      _set(
        _value.copyWith(
          selectedTemplateId: draft.templateId,
          selectedMode: draft.mode,
        ),
      );
    }
    if (_value.selectedTemplate == null) {
      _emitFailure(ReportFlowFailureCode.noCompatibleTemplates);
      return;
    }
    await preparePreview();
  }

  @override
  void cancelSettings() {
    _ensureActive();
    final selectingFromSettings =
        _value.stage == ReportFlowStage.selectingTemplate &&
        _value.selectionOrigin == TemplateSelectionOrigin.reportSettings;
    if (_operationInProgress ||
        (_value.stage != ReportFlowStage.editingSettings &&
            !selectingFromSettings)) {
      return;
    }
    final committedTemplate = _validTemplateId(
      _value.templates,
      _value.committedTemplateId,
    );
    final committedMode = _value.committedMode ?? _value.selectedMode;
    _set(
      _value.copyWith(
        stage: _value.presenterLaunch == null
            ? ReportFlowStage.selectingTemplate
            : ReportFlowStage.previewing,
        selectedTemplateId: committedTemplate,
        clearSelectedTemplate: committedTemplate == null,
        selectedMode: committedMode,
        clearSettingsDraft: true,
        clearFailure: true,
      ),
    );
  }

  @override
  Future<void> preparePreview() {
    _ensureActive();
    final running = _previewPreparationFuture;
    if (running != null) return running;
    final allowedStage =
        (_value.stage == ReportFlowStage.preparingResources &&
            request.entryPolicy == ReportEntryPolicy.smart &&
            _value.entryFallbackReason == null) ||
        _value.stage == ReportFlowStage.selectingTemplate ||
        _value.stage == ReportFlowStage.editingSettings ||
        _value.stage == ReportFlowStage.failed;
    if (!allowedStage) return Future<void>.value();
    if (_value.resourcesBusy || _value.exportAction != null) {
      return Future<void>.error(
        const ReportFlowFailure(
          code: ReportFlowFailureCode.operationInProgress,
        ),
      );
    }

    late final Future<void> future;
    future = _preparePreview().whenComplete(() {
      if (identical(_previewPreparationFuture, future)) {
        _previewPreparationFuture = null;
      }
    });
    _previewPreparationFuture = future;
    return future;
  }

  Future<void> _preparePreview() async {
    final template = _value.selectedTemplate;
    if (template == null) {
      _emitFailure(ReportFlowFailureCode.noCompatibleTemplates);
      return;
    }

    if (_value.selectedMode == PresenterModePreference.offline &&
        !_value.presenterCached) {
      try {
        final status = await _runtime.bridgeClient.getStatus();
        if (_disposed) return;
        if (status.presenterCached) {
          _set(
            _value.copyWith(
              presenterCached: true,
              presenterSync: ReportOperationStatus.succeeded,
              presenterDownloadProgress: 1,
            ),
          );
        }
      } catch (_) {
        // A missing local status is handled by Presenter synchronization below.
      }
      if (!_value.presenterCached) {
        await _syncPresenter(allowDuringPreviewPreparation: true);
        if (_disposed || !_value.presenterCached) return;
      }
    }

    final previousLaunch = _value.presenterLaunch;
    final previousPreference = _persistedPreferences;
    final replacing = previousLaunch != null;
    if (!replacing) {
      _cancelRenderWatchdog();
      _runtime.surfaceBinding.detach();
    }
    _set(
      _value.copyWith(
        stage: replacing
            ? ReportFlowStage.editingSettings
            : ReportFlowStage.preparingPreview,
        previewLoad: ReportOperationStatus.running,
        renderStatus: replacing
            ? _value.renderStatus
            : PresenterRenderStatus.loading,
        webViewLoadProgress: replacing ? _value.webViewLoadProgress : 0,
        presenterProtocolReady: replacing
            ? _value.presenterProtocolReady
            : false,
        clearPresenterProtocolVersion: !replacing,
        clearPresenterLaunch: !replacing,
        clearFailure: true,
      ),
    );
    try {
      final sessionRequest = PresenterSessionRequest(
        reportType: request.reportType.value,
        reportName: request.reportName?.trim().isNotEmpty == true
            ? request.reportName!.trim()
            : request.reportType.value,
        mode: _value.selectedMode.sessionMode,
        seedData: request.seedData,
        template: template,
        locale: _normalizedLocale(request.localeOverride),
        direction: _normalizedLocale(request.localeOverride) == 'ar'
            ? 'rtl'
            : 'ltr',
        sessionId: request.requestId,
      );
      final launch = replacing
          ? await _runtime.bridgeClient.prepareReplacementSession(
              sessionRequest,
            )
          : await _runtime.bridgeClient.prepareSession(sessionRequest);
      if (_disposed) {
        if (replacing) {
          await _discardReplacementSilently();
        } else {
          await _stopSessionSilently();
        }
        return;
      }
      try {
        await _persistSelection();
      } catch (error) {
        try {
          if (replacing) {
            await _runtime.bridgeClient.discardReplacementSession();
          } else {
            await _runtime.bridgeClient.stopSession();
          }
        } catch (cleanupError) {
          _addEvent(
            ReportFlowEvent(
              type: ReportFlowEventType.cleanupWarning,
              failure: ReportFlowFailure(
                code: ReportFlowFailureCode.cleanupFailed,
                diagnostic: cleanupError.toString(),
              ),
            ),
          );
        }
        throw ReportFlowFailure(
          code: ReportFlowFailureCode.persistenceFailed,
          diagnostic: error.toString(),
        );
      }

      if (_disposed) {
        await _restorePreferenceSilently(previousPreference);
        if (replacing) {
          await _discardReplacementSilently();
        } else {
          await _stopSessionSilently();
        }
        return;
      }

      if (replacing) {
        try {
          await _runtime.bridgeClient.commitReplacementSession();
        } catch (error, stackTrace) {
          Object failure = error;
          StackTrace failureStackTrace = stackTrace;
          try {
            await _restorePreference(previousPreference);
          } catch (rollbackError, rollbackStackTrace) {
            failure = ReportFlowFailure(
              code: ReportFlowFailureCode.persistenceFailed,
              diagnostic:
                  'Replacement commit failed: $error. '
                  'Preference rollback failed: $rollbackError',
            );
            failureStackTrace = rollbackStackTrace;
          }
          await _discardReplacementSilently();
          Error.throwWithStackTrace(failure, failureStackTrace);
        }
      }

      if (_disposed) {
        await _restorePreferenceSilently(previousPreference);
        await _stopSessionSilently();
        return;
      }

      _presenterWasOpened = true;
      _set(
        _value.copyWith(
          stage: ReportFlowStage.previewing,
          presenterLaunch: launch,
          committedTemplateId: template.id,
          committedMode: _value.selectedMode,
          clearSettingsDraft: true,
          previewLoad: ReportOperationStatus.running,
          renderStatus: PresenterRenderStatus.loading,
          webViewLoadProgress: 0,
          presenterProtocolReady: false,
          clearPresenterProtocolVersion: true,
          clearFailure: true,
        ),
      );
      _addEvent(
        const ReportFlowEvent(type: ReportFlowEventType.previewPrepared),
      );
    } catch (error) {
      if (previousLaunch != null) {
        final failure = _asFailure(
          error,
          ReportFlowFailureCode.previewPreparationFailed,
        );
        _set(
          _value.copyWith(
            stage: ReportFlowStage.editingSettings,
            presenterLaunch: previousLaunch,
            previewLoad: ReportOperationStatus.failed,
            failure: failure,
          ),
        );
        _addEvent(
          ReportFlowEvent(type: ReportFlowEventType.failure, failure: failure),
        );
      } else {
        _failFrom(
          error,
          ReportFlowFailureCode.previewPreparationFailed,
          clearPresenterLaunch: true,
        );
      }
    }
  }

  Future<void> _discardReplacementSilently() async {
    try {
      await _runtime.bridgeClient.discardReplacementSession();
    } catch (error) {
      _addEvent(
        ReportFlowEvent(
          type: ReportFlowEventType.cleanupWarning,
          failure: ReportFlowFailure(
            code: ReportFlowFailureCode.cleanupFailed,
            diagnostic: error.toString(),
          ),
        ),
      );
    }
  }

  @override
  void presenterLoadStarted() {
    if (!_acceptPresenterCallback()) return;
    final restartWatchdog =
        _value.renderStatus == PresenterRenderStatus.failed ||
        _renderWatchdog == null;
    _set(
      _value.copyWith(
        stage: ReportFlowStage.previewing,
        previewLoad: ReportOperationStatus.running,
        renderStatus: PresenterRenderStatus.loading,
        webViewLoadProgress: 0,
        presenterProtocolReady: false,
        clearPresenterProtocolVersion: true,
        clearFailure: true,
      ),
    );
    if (restartWatchdog) {
      _startRenderWatchdog();
    }
  }

  @override
  void presenterLoadProgress(double progress) {
    if (!_acceptPresenterCallback()) return;
    final normalized = progress.clamp(0, 1).toDouble();
    _set(_value.copyWith(webViewLoadProgress: normalized));
    if (normalized >= 1) {
      _activateLegacyPresenterPageLoaded();
    }
  }

  @override
  void presenterProtocolDetected(int contractVersion) {
    if (!_acceptPresenterCallback() || contractVersion <= 0) return;
    _set(
      _value.copyWith(
        presenterProtocolReady:
            contractVersion == BridgeContract.payloadVersion,
        presenterProtocolVersion: contractVersion,
      ),
    );
  }

  @override
  void completePresenterRender({String? sessionId}) {
    if (!_acceptPresenterCallback(sessionId: sessionId)) return;
    if (!_value.presenterProtocolReady) {
      _failPresenterCompatibility(
        'Presenter lifecycle contract was not acknowledged.',
        rendered: true,
      );
      return;
    }
    _cancelRenderWatchdog();
    _set(
      _value.copyWith(
        stage: ReportFlowStage.previewing,
        previewLoad: ReportOperationStatus.succeeded,
        renderStatus: PresenterRenderStatus.ready,
        webViewLoadProgress: 1,
        clearFailure: true,
      ),
    );
    _addEvent(const ReportFlowEvent(type: ReportFlowEventType.previewReady));
  }

  @override
  void failPresenterRender(String diagnostic, {String? sessionId}) {
    failPresenterRenderFailure(
      ReportFlowFailure(
        code: ReportFlowFailureCode.renderFailed,
        diagnostic: diagnostic,
      ),
      sessionId: sessionId,
    );
  }

  @override
  void failPresenterRenderFailure(
    ReportFlowFailure failure, {
    String? sessionId,
  }) {
    if (!_acceptPresenterCallback(sessionId: sessionId)) return;
    _cancelRenderWatchdog();
    final renderFailure = failure.code == ReportFlowFailureCode.renderFailed
        ? failure
        : ReportFlowFailure(
            code: ReportFlowFailureCode.renderFailed,
            diagnostic: failure.diagnostic,
            technicalCode: failure.technicalCode,
            technicalCategory: failure.technicalCategory,
            technicalPath: failure.technicalPath,
            details: failure.details,
          );
    if (_activateLegacyPresenterFallback(renderFailure)) return;
    _set(
      _value.copyWith(
        stage: ReportFlowStage.failed,
        previewLoad: ReportOperationStatus.failed,
        renderStatus: PresenterRenderStatus.failed,
        failure: renderFailure,
      ),
    );
    _addEvent(
      ReportFlowEvent(
        type: ReportFlowEventType.failure,
        failure: renderFailure,
      ),
    );
  }

  @override
  Future<void> savePdf() => _export(ReportExportAction.save);

  @override
  Future<void> sharePdf() => _export(ReportExportAction.share);

  /// Marks a Save/Share/Print output action as the single busy authority.
  @protected
  void beginOutputAction(ReportExportAction action) {
    _ensureActive();
    if (_value.exportAction != null) {
      throw const ReportFlowFailure(
        code: ReportFlowFailureCode.exportInProgress,
      );
    }
    _set(_value.copyWith(exportAction: action, clearFailure: true));
  }

  /// Clears the flow-level output busy state.
  @protected
  void endOutputAction() {
    if (!_disposed) _set(_value.copyWith(clearExportAction: true));
  }

  /// Emits a flow event from derived controllers (e.g. Print lifecycle).
  @protected
  void emitFlowEvent(ReportFlowEvent event) => _addEvent(event);

  Future<void> _export(ReportExportAction action) async {
    _ensureActive();
    if (_value.exportAction != null) {
      throw const ReportFlowFailure(
        code: ReportFlowFailureCode.exportInProgress,
      );
    }
    if (!_exportReady) {
      throw const ReportFlowFailure(
        code: ReportFlowFailureCode.exportUnavailable,
      );
    }
    beginOutputAction(action);
    try {
      final pdf = await _runtime.surfaceBinding.exportPdf();
      if (action == ReportExportAction.save) {
        final saved = await _runtime.filePlatform.savePdf(
          pdf.bytes,
          pdf.filename,
        );
        if (!saved) {
          _addEvent(
            const ReportFlowEvent(
              type: ReportFlowEventType.exportCancelled,
              detail: 'save',
            ),
          );
          return;
        }
      } else {
        await _runtime.filePlatform.sharePdf(pdf.bytes, pdf.filename);
      }
      _addEvent(
        ReportFlowEvent(
          type: ReportFlowEventType.exportCompleted,
          detail: action.name,
        ),
      );
    } catch (error) {
      _emitFailure(
        ReportFlowFailureCode.exportFailed,
        diagnostic: error.toString(),
        stage: ReportFlowStage.previewing,
      );
    } finally {
      endOutputAction();
    }
  }

  @override
  Future<void> shareDevelopmentSupportPackage({
    Rect? sharePositionOrigin,
  }) async {
    _ensureActive();
    if (!_features.showDevelopmentSupport) {
      throw const ReportFlowFailure(
        code: ReportFlowFailureCode.developmentSupportFailed,
        diagnostic: 'Development-support export is disabled by Host policy.',
      );
    }
    if (_operationInProgress ||
        _value.exportAction != null ||
        _value.supportBusy) {
      throw const ReportFlowFailure(
        code: ReportFlowFailureCode.operationInProgress,
      );
    }

    _set(_value.copyWith(supportShare: ReportOperationStatus.running));
    try {
      final template = _value.committedTemplate ?? _value.selectedTemplate;
      if (template == null) {
        throw const ReportFlowFailure(
          code: ReportFlowFailureCode.developmentSupportFailed,
          diagnostic:
              'A selected template is required to create a URB package.',
        );
      }
      final package = const ReportSupportPackageBuilder().build(
        seedData: request.seedData,
        template: template,
        failure: _value.failure,
        systemCode: request.templateSyncRequest.systemCode.value,
        reportType: request.reportType.value,
        reportName: request.reportName,
        requestId: request.requestId,
        userId: request.selectedTemplateCriteria.identity.userId,
        branchId: request.selectedTemplateCriteria.identity.branchId,
        systemUnit: request.selectedTemplateCriteria.identity.systemUnit,
        customType: request.selectedTemplateCriteria.customType,
        presenterMode: _value.selectedMode,
        locale: request.localeOverride,
        presenterLaunch: _value.presenterLaunch,
        presenterManifest: _value.presenterManifest,
      );
      await _runtime.supportSharePlatform.shareArchive(
        package.bytes,
        package.filename,
        sharePositionOrigin: sharePositionOrigin,
      );
      if (!_disposed) {
        _set(_value.copyWith(supportShare: ReportOperationStatus.succeeded));
      }
    } catch (error) {
      if (!_disposed) {
        _set(_value.copyWith(supportShare: ReportOperationStatus.failed));
      }
      if (error is ReportFlowFailure) rethrow;
      throw ReportFlowFailure(
        code: ReportFlowFailureCode.developmentSupportFailed,
        diagnostic: error.toString(),
      );
    }
  }

  @override
  Future<void> clearCachedResources() async {
    _ensureActive();
    if (_value.stage != ReportFlowStage.editingSettings ||
        _operationInProgress ||
        _value.exportAction != null ||
        _value.supportBusy) {
      throw const ReportFlowFailure(
        code: ReportFlowFailureCode.operationInProgress,
      );
    }

    _set(_value.copyWith(cacheMaintenance: ReportOperationStatus.running));
    Object? firstError;
    try {
      await _runtime.bridgeClient.clearTemplateCache();
    } catch (error) {
      firstError = error;
    }
    try {
      await _runtime.bridgeClient.clearPresenterCache();
    } catch (error) {
      firstError ??= error;
    }

    _cancelRenderWatchdog();
    _presenterWasOpened = false;
    _runtime.surfaceBinding.detach();
    if (!_disposed) {
      _set(
        _value.copyWith(
          stage: ReportFlowStage.preparingResources,
          templates: const <CachedTemplate>[],
          templateCatalogCount: 0,
          templateSync: ReportOperationStatus.idle,
          presenterSync: ReportOperationStatus.idle,
          cacheMaintenance: firstError == null
              ? ReportOperationStatus.succeeded
              : ReportOperationStatus.failed,
          previewLoad: ReportOperationStatus.idle,
          renderStatus: PresenterRenderStatus.idle,
          presenterDownloadProgress: 0,
          webViewLoadProgress: 0,
          presenterProtocolReady: false,
          presenterCached: false,
          resourceOrigin: ResourcePreparationOrigin.reportSettings,
          clearPresenterLaunch: true,
          clearPresenterProtocolVersion: true,
          clearTemplatesSyncedAt: true,
          clearPresenterManifest: true,
          clearTemplateSyncFailure: true,
          clearPresenterSyncFailure: true,
          clearFailure: true,
        ),
      );
    }

    if (firstError != null) {
      throw ReportFlowFailure(
        code: ReportFlowFailureCode.cacheClearFailed,
        diagnostic: firstError.toString(),
      );
    }
  }

  @override
  Future<void> retry() async {
    _ensureActive();
    if (_operationInProgress) return;
    switch (_value.failure?.code) {
      case ReportFlowFailureCode.templateSyncFailed:
      case ReportFlowFailureCode.noCompatibleTemplates:
        await syncTemplates();
        return;
      case ReportFlowFailureCode.presenterSyncFailed:
        await syncPresenter();
        return;
      case ReportFlowFailureCode.previewLoadFailed:
      case ReportFlowFailureCode.presenterIncompatible:
      case ReportFlowFailureCode.renderTimedOut:
      case ReportFlowFailureCode.renderFailed:
        _cancelRenderWatchdog();
        presenterLoadStarted();
        await _runtime.surfaceBinding.reload();
        return;
      case ReportFlowFailureCode.previewPreparationFailed:
        await preparePreview();
        return;
      case ReportFlowFailureCode.persistenceFailed:
        await commitSettings();
        return;
      default:
        _initialized = false;
        await initialize();
        return;
    }
  }

  @override
  Future<ReportResult> close() {
    _ensureActive();
    final running = _closeFuture;
    if (running != null) return running;
    if (_value.exportAction != null) {
      return Future<ReportResult>.error(
        const ReportFlowFailure(code: ReportFlowFailureCode.exportInProgress),
      );
    }
    if (_operationInProgress || _value.busy) {
      return Future<ReportResult>.error(
        const ReportFlowFailure(
          code: ReportFlowFailureCode.operationInProgress,
        ),
      );
    }

    final future = _close();
    _closeFuture = future;
    return future;
  }

  Future<ReportResult> _close() async {
    _cancelRenderWatchdog();
    final hadPresenterSession = _presenterWasOpened;
    _set(_value.copyWith(stage: ReportFlowStage.closing, clearFailure: true));
    ReportFlowFailure? warning;
    try {
      await _runtime.bridgeClient.stopSession();
    } catch (error) {
      warning = ReportFlowFailure(
        code: ReportFlowFailureCode.cleanupFailed,
        diagnostic: error.toString(),
      );
      _addEvent(
        ReportFlowEvent(
          type: ReportFlowEventType.cleanupWarning,
          failure: warning,
        ),
      );
    }
    _runtime.surfaceBinding.detach();
    _set(
      _value.copyWith(
        stage: ReportFlowStage.closed,
        cleanupWarning: warning,
        clearPresenterLaunch: true,
      ),
    );
    return hadPresenterSession
        ? ReportClosed(cleanupWarning: warning)
        : const ReportCancelled();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    final closing = _closeFuture;
    if (closing != null) {
      try {
        await closing;
      } catch (_) {
        // Continue terminal disposal even if an external close failed.
      }
    }
    _disposed = true;
    _cancelRenderWatchdog();
    final previewPreparation = _previewPreparationFuture;
    if (previewPreparation != null) {
      try {
        await previewPreparation;
      } catch (_) {
        // Terminal disposal owns cleanup regardless of preparation outcome.
      }
    }
    if (closing == null) {
      await _stopSessionSilently();
    }
    _runtime.surfaceBinding.dispose();
    await _events.close();
    _notifier.dispose();
    _onDisposed?.call();
  }

  void _startRenderWatchdog() {
    _cancelRenderWatchdog();
    final sessionId = _value.presenterLaunch?.sessionId;
    if (sessionId == null || renderTimeout <= Duration.zero) return;
    _renderWatchdog = Timer(renderTimeout, () {
      _renderWatchdog = null;
      if (_disposed ||
          _value.stage != ReportFlowStage.previewing ||
          _value.presenterLaunch?.sessionId != sessionId ||
          _value.renderStatus != PresenterRenderStatus.loading) {
        return;
      }
      if (!_value.presenterProtocolReady) {
        _failPresenterCompatibility(
          'Presenter protocol ${_value.presenterProtocolVersion ?? 'unknown'} '
          'is incompatible with ${BridgeContract.payloadVersion}.',
        );
        return;
      }
      final failure = const ReportFlowFailure(
        code: ReportFlowFailureCode.renderTimedOut,
      );
      if (_activateLegacyPresenterFallback(failure)) return;
      _set(
        _value.copyWith(
          stage: ReportFlowStage.failed,
          previewLoad: ReportOperationStatus.failed,
          renderStatus: PresenterRenderStatus.failed,
          failure: failure,
        ),
      );
      _addEvent(
        ReportFlowEvent(type: ReportFlowEventType.failure, failure: failure),
      );
    });
  }

  void _cancelRenderWatchdog() {
    _renderWatchdog?.cancel();
    _renderWatchdog = null;
  }

  void _failPresenterCompatibility(String diagnostic, {bool rendered = false}) {
    _cancelRenderWatchdog();
    final failure = ReportFlowFailure(
      code: ReportFlowFailureCode.presenterIncompatible,
      diagnostic: diagnostic,
    );
    if (_activateLegacyPresenterFallback(failure, rendered: rendered)) return;
    _set(
      _value.copyWith(
        stage: ReportFlowStage.failed,
        previewLoad: ReportOperationStatus.failed,
        renderStatus: PresenterRenderStatus.failed,
        failure: failure,
      ),
    );
    _addEvent(
      ReportFlowEvent(type: ReportFlowEventType.failure, failure: failure),
    );
  }

  Future<void> _stopSessionSilently() async {
    try {
      await _runtime.bridgeClient.stopSession();
    } catch (_) {
      // Terminal disposal and cancellation remain deterministic.
    }
  }

  bool _acceptPresenterCallback({String? sessionId}) {
    if (!_matchesSession(sessionId)) return false;
    return _value.stage == ReportFlowStage.previewing ||
        _value.stage == ReportFlowStage.failed;
  }

  bool _activateLegacyPresenterPageLoaded() {
    if (!_features.allowLegacyPresenterFallback ||
        _value.stage != ReportFlowStage.previewing ||
        _value.presenterLaunch == null ||
        _value.presenterProtocolReady ||
        _value.renderStatus != PresenterRenderStatus.loading ||
        _value.webViewLoadProgress < 1) {
      return false;
    }
    _cancelRenderWatchdog();
    _set(
      _value.copyWith(
        previewLoad: ReportOperationStatus.succeeded,
        renderStatus: PresenterRenderStatus.ready,
        webViewLoadProgress: 1,
        clearFailure: true,
      ),
    );
    _addEvent(const ReportFlowEvent(type: ReportFlowEventType.previewReady));
    return true;
  }

  bool _activateLegacyPresenterFallback(
    ReportFlowFailure failure, {
    bool rendered = false,
  }) {
    if (!_features.allowLegacyPresenterFallback ||
        _value.presenterLaunch == null ||
        (!rendered && _value.webViewLoadProgress < 1)) {
      return false;
    }
    _cancelRenderWatchdog();
    _set(
      _value.copyWith(
        stage: ReportFlowStage.previewing,
        previewLoad: ReportOperationStatus.succeeded,
        renderStatus: PresenterRenderStatus.ready,
        webViewLoadProgress: 1,
        failure: failure,
      ),
    );
    _addEvent(
      ReportFlowEvent(type: ReportFlowEventType.failure, failure: failure),
    );
    return true;
  }

  bool get _exportReady =>
      _value.exportReady ||
      (_features.allowLegacyPresenterFallback &&
          _value.stage == ReportFlowStage.previewing &&
          _value.presenterLaunch != null &&
          _value.renderStatus == PresenterRenderStatus.ready &&
          _value.webViewLoadProgress >= 1 &&
          _value.exportAction == null);

  bool get _operationInProgress =>
      _previewPreparationFuture != null ||
      _value.resourcesBusy ||
      _value.supportBusy;

  ReportFlowStage _resourceReturnStage() => switch (_value.stage) {
    ReportFlowStage.editingSettings => ReportFlowStage.editingSettings,
    ReportFlowStage.selectingTemplate => ReportFlowStage.selectingTemplate,
    _ => ReportFlowStage.preparingResources,
  };

  ReportFlowFailure _asFailure(Object error, ReportFlowFailureCode fallback) {
    if (error is ReportFlowFailure) return error;
    if (error is BridgeRuntimeException) {
      return ReportFlowFailure(
        code: fallback,
        diagnostic: error.message,
        technicalCode: error.code,
      );
    }
    return ReportFlowFailure(
      code: fallback,
      diagnostic: error.toString(),
      technicalCategory: error.runtimeType.toString(),
    );
  }

  List<CachedTemplate> _compatibleTemplates(List<CachedTemplate> templates) {
    return filterEligibleTemplates(
      templates,
      reportType: request.reportType.value,
      constraints: request.compatibility,
    );
  }

  String? _validTemplateId(List<CachedTemplate> templates, String? candidate) {
    final id = candidate?.trim();
    if (id == null || id.isEmpty) return null;
    for (final template in templates) {
      if (template.id == id) return id;
    }
    return null;
  }

  Future<void> _persistSelection() async {
    final template = _value.selectedTemplate;
    if (template == null) {
      throw const ReportFlowFailure(
        code: ReportFlowFailureCode.noCompatibleTemplates,
      );
    }
    final preferences = ReportFlowPreferences(
      templateId: template.id,
      mode: _value.selectedMode,
    );
    await _runtime.preferences.save(_scope, preferences);
    _persistedPreferences = preferences;
  }

  Future<void> _restorePreference(
    ReportFlowPreferences? previousPreference,
  ) async {
    if (previousPreference == null) {
      await _runtime.preferences.remove(_scope);
    } else {
      await _runtime.preferences.save(_scope, previousPreference);
    }
    _persistedPreferences = previousPreference;
  }

  Future<void> _restorePreferenceSilently(
    ReportFlowPreferences? previousPreference,
  ) async {
    try {
      await _restorePreference(previousPreference);
    } catch (error) {
      _addEvent(
        ReportFlowEvent(
          type: ReportFlowEventType.cleanupWarning,
          failure: ReportFlowFailure(
            code: ReportFlowFailureCode.cleanupFailed,
            diagnostic: 'Preference rollback failed: $error',
          ),
        ),
      );
    }
  }

  bool _matchesSession(String? sessionId) {
    if (_disposed) return false;
    final current = _value.presenterLaunch?.sessionId;
    return current != null && (sessionId == null || sessionId == current);
  }

  String _normalizedLocale(String? value) => value == 'ar' ? 'ar' : 'en';

  void _failFrom(
    Object error,
    ReportFlowFailureCode fallback, {
    bool clearPresenterLaunch = false,
  }) {
    final failure = error is ReportFlowFailure
        ? error
        : ReportFlowFailure(code: fallback, diagnostic: error.toString());
    _set(
      _value.copyWith(
        stage: ReportFlowStage.failed,
        failure: failure,
        clearPresenterLaunch: clearPresenterLaunch,
      ),
    );
    _addEvent(
      ReportFlowEvent(type: ReportFlowEventType.failure, failure: failure),
    );
  }

  void _emitFailure(
    ReportFlowFailureCode code, {
    String? diagnostic,
    ReportFlowStage stage = ReportFlowStage.failed,
  }) {
    final failure = ReportFlowFailure(code: code, diagnostic: diagnostic);
    _set(_value.copyWith(stage: stage, failure: failure));
    _addEvent(
      ReportFlowEvent(type: ReportFlowEventType.failure, failure: failure),
    );
  }

  void _addEvent(ReportFlowEvent event) {
    final failure = event.failure;
    if (failure != null) {
      _runtime.connection.diagnostics.flowFailure(
        operation: _value.stage.name,
        code: failure.code.name,
        diagnostic: failure.diagnostic,
        details: <String, Object?>{'event': event.type.name},
      );
    }
    if (!_events.isClosed) _events.add(event);
  }

  void _set(ReportFlowState next) {
    if (_disposed) return;
    _value = next;
    _notifier.notify();
  }

  void _ensureActive() {
    if (_disposed) {
      throw const ReportFlowFailure(code: ReportFlowFailureCode.disposed);
    }
  }
}

class _ReportFlowNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
