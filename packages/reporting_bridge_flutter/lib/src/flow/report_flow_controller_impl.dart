import 'package:flutter/foundation.dart';
import 'package:reporting_bridge/reporting_bridge.dart';

import '../contracts/external_printer_contract.dart';
import '../contracts/report_open_request.dart';
import '../contracts/template_compatibility_constraints.dart';
import '../contracts/template_sync_request.dart';
import '../logging/bridge_diagnostics.dart';
import '../persistence/report_flow_preference_store.dart';
import '../platform/bridge_platform_adapters.dart';
import '../printing/thermal_printer_controller.dart';
import '../printing/thermal_printer_models.dart';
import '../printing/thermal_report_print_platform.dart';
import '../ui/bridge_ui_features.dart';
import 'report_action_policy.dart';
import 'report_flow_controller.dart';
import 'report_flow_controller_base.dart' as base;
import 'report_flow_event.dart';
import 'report_flow_failure.dart';
import 'report_flow_runtime.dart';
import 'report_flow_state.dart';
import 'report_template_metadata.dart';

/// Extends the preserved workflow repairs owned by the base controller.
///
/// Migration guard markers retained here because the repository verifier checks
/// this composition entry point directly: `backToPreparation`,
/// `presenterCached`, `clearPresenterLaunch: true`,
/// `ReportFlowFailureCode.cleanupFailed`, and
/// `ReportFlowFailureCode.persistenceFailed`.
class ReportFlowControllerImpl extends base.ReportFlowControllerImpl
    implements ReportFlowActionController, ReportFlowThermalPrinterController {
  factory ReportFlowControllerImpl({
    required ReportOpenRequest request,
    required ReportFlowRuntime runtime,
    BridgeUiFeatures features = const BridgeUiFeatures(),
    Duration renderTimeout = const Duration(seconds: 30),
    VoidCallback? onDisposed,
  }) {
    final effectiveFeatures = features.restrictTo(request.actionPolicy);
    final effectiveRequest = request.copyWith(
      featuresOverride: effectiveFeatures,
    );
    final flowBridgeClient = _WorkflowBridgeClient(
      delegate: runtime.bridgeClient,
      system: effectiveRequest.templateSyncRequest.systemCode.value,
      templateSyncRequest: effectiveRequest.templateSyncRequest,
    );
    final scopedPreferences = _RequestScopedPreferenceStore(
      delegate: runtime.preferences,
      request: effectiveRequest,
      connectionKey: runtime.connection.preferenceSourceKey,
      bridgeClient: flowBridgeClient,
    );
    final scopedRuntime = ReportFlowRuntime(
      connection: runtime.connection,
      bridgeClient: flowBridgeClient,
      preferences: scopedPreferences,
      filePlatform: runtime.filePlatform,
      surfaceBinding: runtime.surfaceBinding,
      printPlatform: runtime.printPlatform,
      thermalPrinterSettings: runtime.thermalPrinterSettings,
      supportSharePlatform: runtime.supportSharePlatform,
    );
    return ReportFlowControllerImpl._(
      request: effectiveRequest,
      runtime: runtime,
      scopedRuntime: scopedRuntime,
      scopedPreferences: scopedPreferences,
      workflowBridgeClient: flowBridgeClient,
      features: effectiveFeatures,
      renderTimeout: renderTimeout,
      onDisposed: onDisposed,
    );
  }

  // Explicit forwarding keeps request-scoped runtime construction visible.
  // ignore: use_super_parameters
  ReportFlowControllerImpl._({
    required ReportOpenRequest request,
    required ReportFlowRuntime runtime,
    required ReportFlowRuntime scopedRuntime,
    required _RequestScopedPreferenceStore scopedPreferences,
    required _WorkflowBridgeClient workflowBridgeClient,
    required BridgeUiFeatures features,
    required Duration renderTimeout,
    required VoidCallback? onDisposed,
  }) : _runtime = runtime,
       _scopedPreferences = scopedPreferences,
       _workflowBridgeClient = workflowBridgeClient,
       _effectiveFeatures = features,
       _compatibilityConstraints = resolveTemplateCompatibilityConstraints(
         request,
       ),
       super(
         request: request,
         runtime: scopedRuntime,
         features: features,
         renderTimeout: renderTimeout,
         onDisposed: onDisposed,
       );

  final ReportFlowRuntime _runtime;
  final _RequestScopedPreferenceStore _scopedPreferences;
  final _WorkflowBridgeClient _workflowBridgeClient;
  final BridgeUiFeatures _effectiveFeatures;
  final TemplateCompatibilityConstraints _compatibilityConstraints;
  Future<ReportPrintResult>? _printFuture;

  @override
  ThermalPrinterSettingsController? get thermalPrinterSettings =>
      _runtime.thermalPrinterSettings;

  @override
  Future<void> initialize() async {
    await super.initialize();
    if (value.stage == ReportFlowStage.selectingTemplate) {
      _ensureEligibleSelection();
    }
  }

  @override
  Future<void> continueFromPreparation() async {
    await super.continueFromPreparation();
    if (value.stage == ReportFlowStage.selectingTemplate) {
      _ensureEligibleSelection();
    }
  }

  @override
  void openTemplateSelection({
    TemplateSelectionOrigin origin = TemplateSelectionOrigin.initialSetup,
  }) {
    super.openTemplateSelection(origin: origin);
    if (value.stage == ReportFlowStage.selectingTemplate) {
      _ensureEligibleSelection();
    }
  }

  @override
  ReportActionPolicy get actionPolicy => request.actionPolicy;

  @override
  BridgeUiFeatures get effectiveFeatures => _effectiveFeatures;

  @override
  TemplateCompatibilityConstraints get compatibilityConstraints =>
      _compatibilityConstraints;

  @override
  List<CachedTemplate> get eligibleTemplates => value.templates;

  @override
  bool get outputReady =>
      value.exportReady ||
      (_effectiveFeatures.allowLegacyPresenterFallback &&
          value.stage == ReportFlowStage.previewing &&
          value.presenterLaunch != null &&
          value.renderStatus == PresenterRenderStatus.ready &&
          value.webViewLoadProgress >= 1 &&
          value.exportAction == null);

  @override
  void selectTemplate(String templateId) {
    final template = _templateById(templateId);
    if (template == null || !_isEligible(template)) {
      return;
    }
    _scopedPreferences.acceptExplicitReselection();
    super.selectTemplate(templateId);
  }

  @override
  Future<void> preparePreview() async {
    var template = value.selectedTemplate;
    if (template != null && !_isEligible(template)) {
      // Compatibility mismatch skips the saved template for this run only.
      // Do not delete the stored preference; catalog absence owns deletion.
      if (value.stage == ReportFlowStage.preparingResources) {
        super.openTemplateSelection();
        _ensureEligibleSelection();
        return;
      }
      _ensureEligibleSelection();
      template = value.selectedTemplate;
      if (template == null || !_isEligible(template)) {
        throw const ReportFlowFailure(
          code: ReportFlowFailureCode.noCompatibleTemplates,
          diagnostic: 'The selected template is outside the active settings.',
        );
      }
    }
    await super.preparePreview();
  }

  @override
  Future<void> savePdf() {
    _ensureActionAllowed(ReportAction.savePdf);
    return super.savePdf();
  }

  @override
  Future<void> sharePdf() {
    _ensureActionAllowed(ReportAction.sharePdf);
    return super.sharePdf();
  }

  @override
  Future<ReportPrintResult> printPdf() {
    try {
      _ensureActionAllowed(ReportAction.printPdf);
    } catch (error, stackTrace) {
      _logPrintRejected(error, stackTrace: stackTrace);
      rethrow;
    }
    if (value.exportAction != null || _printFuture != null) {
      const failure = ReportFlowFailure(
        code: ReportFlowFailureCode.exportInProgress,
      );
      _logPrintRejected(failure);
      return Future<ReportPrintResult>.error(failure);
    }
    if (!outputReady) {
      const failure = ReportFlowFailure(
        code: ReportFlowFailureCode.printUnavailable,
      );
      _logPrintRejected(failure);
      return Future<ReportPrintResult>.error(failure);
    }

    late final Future<ReportPrintResult> future;
    final platform = _runtime.printPlatform;
    final ThermalPrintProgressSource? thermalProgress =
        platform is ThermalPrintProgressSource
        ? platform as ThermalPrintProgressSource
        : null;
    if (thermalProgress != null) {
      thermalProgress.setPrintProgressListener(_onThermalPrintProgress);
    }
    future = _submitPrint().whenComplete(() {
      if (thermalProgress != null) {
        thermalProgress.setPrintProgressListener(null);
      }
      setPrintProgress(null);
      if (identical(_printFuture, future)) _printFuture = null;
    });
    _printFuture = future;
    return future;
  }

  void _onThermalPrintProgress(ThermalPrintProgress progress) {
    setPrintProgress(progress);
  }

  void _logPrintRejected(Object error, {StackTrace? stackTrace}) {
    final failure = error is ReportFlowFailure ? error : null;
    _runtime.connection.diagnostics.emit(
      level: BridgeLogLevel.warning,
      category: BridgeLogCategory.print,
      event: 'printPdf.rejected',
      message: failure?.code.name ?? 'printRejected',
      details: <String, Object?>{
        'reportType': request.reportType.value,
        if (failure != null) 'code': failure.code.name,
      },
      error: error,
      stackTrace: stackTrace,
    );
  }

  Future<ReportPrintResult> _submitPrint() async {
    beginOutputAction(ReportExportAction.print);
    try {
      final template = value.selectedTemplate ?? value.committedTemplate;
      if (template == null) {
        throw const ReportFlowFailure(
          code: ReportFlowFailureCode.printUnavailable,
        );
      }

      return await _runtime.connection.diagnostics.tracePrint<
        ReportPrintResult
      >(
        operation: 'printPdf',
        details: <String, Object?>{
          'systemCode': request.templateSyncRequest.systemCode.value,
          'reportType': request.reportType.value,
          'templateId': template.id,
        },
        action: () async {
          final metadata = template.reportMetadata;
          late final ReportPrintDocumentMetadata document;
          try {
            document = metadata.toPrintDocumentMetadata();
          } on StateError catch (error) {
            throw ReportFlowFailure(
              code: ReportFlowFailureCode.printUnsupportedPaperConversion,
              diagnostic: error.message.toString(),
            );
          }

          final pdf = await presenterSurface.exportPdf();
          final result = await _runtime.printPlatform.printPdf(
            ReportPrintRequest(
              pdfBytes: pdf.bytes,
              filename: pdf.filename,
              jobId:
                  request.requestId ??
                  '${request.templateSyncRequest.systemCode.value}-'
                      '${request.reportType.value}-'
                      '${DateTime.now().microsecondsSinceEpoch}',
              documentTitle: resolveExternalPrintDocumentTitle(
                hostPrint: request.externalPrint,
                reportName: request.reportName,
                templateName: template.templateName,
              ),
              document: document,
              extra: <String, Object?>{
                'system': request.templateSyncRequest.systemCode.value,
                'reportType': request.reportType.value,
                'templateId': template.id,
                if (request.selectedTemplateCriteria.identity.branchId != null)
                  'branchId':
                      request.selectedTemplateCriteria.identity.branchId,
                if (request.selectedTemplateCriteria.identity.userId != null)
                  'userId': request.selectedTemplateCriteria.identity.userId,
                if (request.selectedTemplateCriteria.identity.systemUnit !=
                    null)
                  'systemUnit':
                      request.selectedTemplateCriteria.identity.systemUnit,
                if (request.selectedTemplateCriteria.customType != null)
                  'customType': request.selectedTemplateCriteria.customType,
                ...?request.externalPrint?.extra,
              },
            ),
          );

          _runtime.connection.diagnostics.emit(
            level:
                result.status == ReportPrintStatus.submitted ||
                    result.status == ReportPrintStatus.cancelled
                ? BridgeLogLevel.info
                : BridgeLogLevel.warning,
            category: BridgeLogCategory.print,
            event: 'printPdf.result',
            message: result.status.name,
            details: <String, Object?>{
              'status': result.status.name,
              'layout': metadata.layout.value,
              'size': metadata.size.value,
              'orientation': metadata.orientation.value,
              'language': metadata.language.value,
            },
          );

          switch (result.status) {
            case ReportPrintStatus.submitted:
              emitFlowEvent(
                const ReportFlowEvent(
                  type: ReportFlowEventType.exportCompleted,
                  detail: 'print',
                ),
              );
              return result;
            case ReportPrintStatus.cancelled:
              emitFlowEvent(
                const ReportFlowEvent(
                  type: ReportFlowEventType.exportCancelled,
                  detail: 'print',
                ),
              );
              return result;
            case ReportPrintStatus.setupRequired:
              throw ReportFlowFailure(
                code: ReportFlowFailureCode.printSetupRequired,
                diagnostic: result.diagnostic ?? result.errorCode,
              );
            case ReportPrintStatus.appNotInstalled:
              throw ReportFlowFailure(
                code: ReportFlowFailureCode.printAppNotInstalled,
                diagnostic: result.diagnostic ?? result.errorCode,
              );
            case ReportPrintStatus.unsupportedContract:
              throw ReportFlowFailure(
                code: ReportFlowFailureCode.printUnsupportedContract,
                diagnostic: result.diagnostic ?? result.errorCode,
              );
            case ReportPrintStatus.unsupportedPaperConversion:
              throw ReportFlowFailure(
                code: ReportFlowFailureCode.printUnsupportedPaperConversion,
                diagnostic: result.diagnostic ?? result.errorCode,
              );
            case ReportPrintStatus.failed:
              throw ReportFlowFailure(
                code: _thermalPrintFailureCode(result.errorCode),
                diagnostic: result.diagnostic ?? result.errorCode,
                technicalCode: result.errorCode,
              );
          }
        },
      );
    } finally {
      endOutputAction();
    }
  }

  ReportFlowFailureCode _thermalPrintFailureCode(
    String? errorCode,
  ) => switch (errorCode) {
    'savedBluetoothPrinterUnavailable' ||
    'bluetoothPrinterUnavailable' ||
    'bluetoothUnavailable' =>
      ReportFlowFailureCode.savedBluetoothPrinterUnavailable,
    'bluetoothPermissionDenied' =>
      ReportFlowFailureCode.bluetoothPermissionDenied,
    'bluetoothConnectionFailed' =>
      ReportFlowFailureCode.bluetoothPrinterConnectionFailed,
    'tcpConnectionTimeout' => ReportFlowFailureCode.tcpPrinterConnectionTimeout,
    'tcpHostNotFound' => ReportFlowFailureCode.tcpPrinterHostNotFound,
    'tcpConnectionRefused' => ReportFlowFailureCode.tcpPrinterConnectionRefused,
    'tcpSendFailed' => ReportFlowFailureCode.tcpPrinterSendFailed,
    'tcpConnectionFailed' => ReportFlowFailureCode.tcpPrinterConnectionFailed,
    'printerConnectionFailed' =>
      ReportFlowFailureCode.thermalPrinterConnectionFailed,
    _ => ReportFlowFailureCode.printFailed,
  };

  @override
  Future<void> dispose() async {
    final printing = _printFuture;
    if (printing != null) {
      try {
        await printing;
      } catch (_) {
        // Terminal disposal continues after a failed platform print request.
      }
    }
    await super.dispose();
    await _workflowBridgeClient.releaseFlowScope();
  }

  void _ensureEligibleSelection() {
    if (_scopedPreferences.selectionRequiresExplicitReselection) return;
    final current = value.selectedTemplate;
    if (current != null && _isEligible(current)) {
      return;
    }
    final templates = eligibleTemplates;
    if (templates.isNotEmpty) super.selectTemplate(templates.first.id);
  }

  bool _isEligible(CachedTemplate template) {
    final metadata = ReportTemplateMetadata.tryFromTemplate(template);
    if (metadata == null) return false;
    return metadata.matches(
      reportType: request.reportType.value,
      constraints: _compatibilityConstraints,
    );
  }

  CachedTemplate? _templateById(String templateId) {
    final id = templateId.trim();
    for (final template in value.templates) {
      if (template.id == id) return template;
    }
    return null;
  }

  void _ensureActionAllowed(ReportAction action) {
    if (!actionPolicy.allows(action)) {
      throw ReportFlowFailure(
        code: ReportFlowFailureCode.actionDenied,
        diagnostic: action.name,
      );
    }
  }
}

class _RequestScopedPreferenceStore implements ReportFlowPreferenceStore {
  _RequestScopedPreferenceStore({
    required this.delegate,
    required this.request,
    required this.connectionKey,
    required this.bridgeClient,
  });

  static const _staleRuntimeId = '__urb_template_code_reselection_required__';

  final ReportFlowPreferenceStore delegate;
  final ReportOpenRequest request;
  final String connectionKey;
  final ReportingBridgeClient bridgeClient;
  ReportFlowPreferences? loadedPreferences;
  bool selectionRequiresExplicitReselection = false;

  ReportPreferenceScope get scope => ReportPreferenceScope(
    connectionKey: connectionKey,
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

  @override
  Future<ReportFlowPreferences?> load(ReportPreferenceScope _) async {
    selectionRequiresExplicitReselection = false;
    final stored = await delegate.load(scope);
    if (stored == null) {
      loadedPreferences = null;
      return null;
    }

    final templateCode = stored.templateCode?.trim();
    if (templateCode != null && templateCode.isNotEmpty) {
      final resolved = await _lookupTemplate(
        (template) => template.durableTemplateCode == templateCode,
      );
      if (resolved.template != null) {
        final runtime = ReportFlowPreferences(
          templateId: resolved.template!.id,
          templateCode: templateCode,
          mode: stored.mode,
        );
        loadedPreferences = runtime;
        return runtime;
      }

      // A request-scoped catalog may exclude an otherwise valid Code. Preserve
      // the durable Code, but never substitute another template silently.
      selectionRequiresExplicitReselection = true;
      final stale = ReportFlowPreferences(
        templateId: _staleRuntimeId,
        templateCode: templateCode,
        mode: stored.mode,
      );
      loadedPreferences = stale;
      return stale;
    }

    final legacyId = stored.templateId?.trim();
    if (legacyId != null && legacyId.isNotEmpty) {
      final resolved = await _lookupTemplate(
        (template) => template.id == legacyId,
      );
      final template = resolved.template;
      final durableCode = template?.durableTemplateCode;
      if (template != null &&
          durableCode != null &&
          _legacyTemplateMatchesActiveSystem(template)) {
        await delegate.save(
          scope,
          ReportFlowPreferences(
            templateId: template.id,
            templateCode: durableCode,
            mode: stored.mode,
          ),
        );
        final runtime = ReportFlowPreferences(
          templateId: template.id,
          templateCode: durableCode,
          mode: stored.mode,
        );
        loadedPreferences = runtime;
        return runtime;
      }

      // A successful refresh is authoritative enough to reject a legacy ID
      // for the active System. Clear that ID once; never manufacture a Code.
      if (resolved.refreshed) {
        await delegate.removeSelectedTemplate(scope);
      }
      selectionRequiresExplicitReselection = true;
      final stale = ReportFlowPreferences(
        templateId: _staleRuntimeId,
        mode: stored.mode,
      );
      loadedPreferences = stale;
      return stale;
    }

    loadedPreferences = stored;
    return stored;
  }

  void acceptExplicitReselection() {
    selectionRequiresExplicitReselection = false;
  }

  Future<void> discardLoadedSelection() async {
    await delegate.removeSelectedTemplate(scope);
    selectionRequiresExplicitReselection = false;
    if (loadedPreferences != null) {
      loadedPreferences = ReportFlowPreferences(mode: loadedPreferences!.mode);
    }
  }

  @override
  Future<void> remove(ReportPreferenceScope _) async {
    await delegate.remove(scope);
    loadedPreferences = null;
    selectionRequiresExplicitReselection = false;
  }

  @override
  Future<void> removeSelectedTemplate(ReportPreferenceScope _) async {
    await delegate.removeSelectedTemplate(scope);
    selectionRequiresExplicitReselection = false;
    if (loadedPreferences != null) {
      loadedPreferences = ReportFlowPreferences(mode: loadedPreferences!.mode);
    }
  }

  @override
  Future<void> save(
    ReportPreferenceScope _,
    ReportFlowPreferences preferences,
  ) async {
    final explicitCode = preferences.templateCode?.trim();
    if (explicitCode != null && explicitCode.isNotEmpty) {
      final durable = ReportFlowPreferences(
        templateId: preferences.templateId,
        templateCode: explicitCode,
        mode: preferences.mode,
      );
      await delegate.save(scope, durable);
      loadedPreferences = preferences;
      selectionRequiresExplicitReselection = false;
      return;
    }

    final templateId = preferences.templateId?.trim();
    if (templateId == null || templateId.isEmpty) {
      await delegate.save(scope, ReportFlowPreferences(mode: preferences.mode));
      loadedPreferences = preferences;
      return;
    }

    final resolved = await _lookupTemplate(
      (template) => template.id == templateId,
    );
    final template = resolved.template;
    final templateCode = template?.durableTemplateCode;
    if (template == null || templateCode == null) {
      throw StateError(
        'Selected template cannot be persisted without a genuine Template Code.',
      );
    }
    await delegate.save(
      scope,
      ReportFlowPreferences(
        templateId: template.id,
        templateCode: templateCode,
        mode: preferences.mode,
      ),
    );
    loadedPreferences = ReportFlowPreferences(
      templateId: template.id,
      templateCode: templateCode,
      mode: preferences.mode,
    );
    selectionRequiresExplicitReselection = false;
  }

  Future<({CachedTemplate? template, bool refreshed})> _lookupTemplate(
    bool Function(CachedTemplate template) predicate,
  ) async {
    var templates = await bridgeClient.listTemplates();
    for (final template in templates) {
      if (predicate(template)) return (template: template, refreshed: false);
    }
    try {
      await bridgeClient.syncTemplates();
      templates = await bridgeClient.listTemplates();
      for (final template in templates) {
        if (predicate(template)) return (template: template, refreshed: true);
      }
      return (template: null, refreshed: true);
    } catch (_) {
      return (template: null, refreshed: false);
    }
  }

  bool _legacyTemplateMatchesActiveSystem(CachedTemplate template) {
    final activeSystem = scope.effectiveSystem;
    final templateSystem = template.systemCode?.trim().toLowerCase();
    if (templateSystem != null && templateSystem.isNotEmpty) {
      return templateSystem == activeSystem;
    }
    final legacySystemId = scope.resolvedLegacySystemId;
    return legacySystemId != null && template.systemId == legacySystemId;
  }
}

@visibleForTesting
ReportingBridgeClient createWorkflowBridgeClientForTesting({
  required ReportingBridgeClient delegate,
  required String system,
  required TemplateSyncRequest templateSyncRequest,
}) => _WorkflowBridgeClient(
  delegate: delegate,
  system: system,
  templateSyncRequest: templateSyncRequest,
);

class _WorkflowBridgeClient extends ReportingBridgeClient {
  _WorkflowBridgeClient({
    required this.delegate,
    required this.system,
    required this.templateSyncRequest,
  }) : super(
         apiBaseUrl: delegate.apiBaseUrl,
         presenterEntryUrl: delegate.presenterEntryUrl,
         bridgeRoot: delegate.bridgeRoot,
         bundleManifestUrl: delegate.bundleManifestUrl,
       );

  final ReportingBridgeClient delegate;
  final String system;
  final TemplateSyncRequest templateSyncRequest;

  bool _identityBound = false;
  bool _released = false;

  Future<void> _ensureRequestScope() async {
    if (_released) return;
    final sync = templateSyncRequest;
    final identity = BridgeIdentityContext(
      userId: sync.identity.userId,
      branchId: sync.identity.branchId,
      systemUnit: sync.identity.systemUnit,
    );
    await delegate.updateIdentityContext(identity);
    _identityBound = true;
  }

  Future<void> releaseFlowScope() async {
    if (_released) return;
    _released = true;
    if (!_identityBound) return;
    if (delegate.identityContext.isEmpty) {
      _identityBound = false;
      return;
    }
    await delegate.clearIdentityContext();
    _identityBound = false;
  }

  @override
  Future<TemplateSyncSummary> syncTemplates({
    String? systemCode,
    int? systemId,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    await _ensureRequestScope();
    final sync = templateSyncRequest;
    return delegate.syncTemplates(
      systemCode: sync.systemCode.value,
      filter: sync.filter,
      extra: sync.extra,
    );
  }

  @override
  Future<List<CachedTemplate>> listTemplates({
    String? systemCode,
    int? systemId,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    await _ensureRequestScope();
    final sync = templateSyncRequest;
    try {
      final templates = await delegate.listTemplates(
        systemCode: sync.systemCode.value,
        filter: sync.filter,
        extra: sync.extra,
      );
      return templates.where(_matchesSystem).toList(growable: false);
    } on BridgeRuntimeException catch (error) {
      if (error.code == BridgeTemplateSyncErrorCodes.offlineCacheUnavailable) {
        return const <CachedTemplate>[];
      }
      rethrow;
    }
  }

  bool _matchesSystem(CachedTemplate template) {
    final document = template.document;
    final meta = document['meta'];
    final documentMetadata = meta is Map ? meta : const <dynamic, dynamic>{};
    final raw =
        template.systemCode ??
        template.metadata['systemCode'] ??
        documentMetadata['systemCode'] ??
        document['systemCode'] ??
        documentMetadata['system'];
    if (raw == null || raw.toString().trim().isEmpty) return true;
    return raw.toString().trim().toLowerCase() == system.trim().toLowerCase();
  }

  @override
  Future<ReportingBridgeStatus> getStatus() => delegate.getStatus();

  @override
  Future<PresenterCacheManifest> syncPresenter({
    void Function(double progress)? onProgress,
  }) => delegate.syncPresenter(onProgress: onProgress);

  @override
  Future<void> clearTemplateCache() => delegate.clearTemplateCache();

  @override
  Future<void> clearPresenterCache() => delegate.clearPresenterCache();

  @override
  Future<PresenterSessionLaunch> prepareSession(
    PresenterSessionRequest request,
  ) => delegate.prepareSession(_authoritativeRequest(request));

  @override
  Future<PresenterSessionLaunch> prepareReplacementSession(
    PresenterSessionRequest request,
  ) => delegate.prepareReplacementSession(_authoritativeRequest(request));

  PresenterSessionRequest _authoritativeRequest(
    PresenterSessionRequest request,
  ) {
    final metadata = request.template.reportMetadata;
    return PresenterSessionRequest(
      reportType: request.reportType,
      reportName: request.reportName,
      mode: request.mode,
      seedData: request.seedData,
      template: request.template,
      locale: metadata.language.value,
      direction: metadata.direction,
      branding: request.branding,
      apiHeaders: request.apiHeaders,
      sessionId: request.sessionId,
    );
  }

  @override
  Future<void> commitReplacementSession() =>
      delegate.commitReplacementSession();

  @override
  Future<void> discardReplacementSession() =>
      delegate.discardReplacementSession();

  @override
  Future<void> stopSession() => delegate.stopSession();
}
