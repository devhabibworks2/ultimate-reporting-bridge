import 'package:flutter/material.dart';
import 'package:reporting_bridge/reporting_bridge.dart';

import '../contracts/report_open_request.dart';
import '../flow/report_flow_controller.dart';
import '../flow/report_flow_controller_impl.dart';
import '../flow/report_flow_failure.dart';
import '../flow/report_flow_runtime.dart';
import '../flow/report_result.dart';
import '../headless/headless_presenter_surface.dart';
import '../headless/headless_report_print_progress.dart';
import '../headless/headless_report_print_runner.dart';
import '../headless/in_app_headless_presenter_surface.dart';
import '../logging/bridge_diagnostics.dart';
import '../persistence/report_flow_preference_store.dart';
import '../platform/bridge_platform_adapters.dart';
import '../platform/presenter_surface_binding.dart';
import '../printing/thermal_printer_controller.dart';
import '../ui/bridge_ui_config.dart';
import '../ui/report_flow_screen.dart';
import 'report_server_connection.dart';

abstract interface class ReportingBridgeFlutterClient {
  BridgeUiConfig get ui;
  bool get hasActiveFlow;

  Future<void> probeEndpoints();
  Future<List<PresenterSystem>> fetchSystems();

  ReportFlowController createController(ReportOpenRequest request);

  Future<ReportResult?> openReport(
    BuildContext context,
    ReportOpenRequest request,
  );

  Future<ReportPrintResult> printReportHeadless(
    ReportOpenRequest request, {
    HeadlessReportPrintProgressCallback? onProgress,
    HeadlessReportPrintTimingCallback? onTiming,
  });

  Future<HeadlessPrintWarmupResult> warmUpHeadlessPrinting(
    ReportOpenRequest request, {
    bool refreshResources = false,
  });

  Future<void> dispose();
}

class DefaultReportingBridgeFlutterClient
    implements ReportingBridgeFlutterClient {
  DefaultReportingBridgeFlutterClient({
    required ReportServerConnection connection,
    required ReportingBridgeClient bridgeClient,
    required ReportFlowPreferenceStore preferences,
    required ReportFilePlatform filePlatform,
    required this.ui,
    ReportPrintPlatform printPlatform = const UnsupportedReportPrintPlatform(),
    ThermalPrinterSettingsController? thermalPrinterSettings,
    void Function()? managedPrintDispose,
    ReportSupportSharePlatform supportSharePlatform =
        const SharePlusReportSupportSharePlatform(),
    HeadlessPresenterSurfaceFactory? headlessPresenterSurfaceFactory,
    WarmableHeadlessPresenterSurface? headlessPresenterSurface,
  }) : _connection = connection,
       _bridgeClient = bridgeClient,
       _preferences = preferences,
       _filePlatform = filePlatform,
       _printPlatform = printPlatform,
       _thermalPrinterSettings = thermalPrinterSettings,
       _managedPrintDispose = managedPrintDispose,
       _supportSharePlatform = supportSharePlatform {
    assert(
      headlessPresenterSurfaceFactory == null ||
          headlessPresenterSurface == null,
      'Provide a surface or a surface factory, not both.',
    );
    final managedSurface =
        headlessPresenterSurface ??
        (headlessPresenterSurfaceFactory == null
            ? InAppHeadlessPresenterSurface()
            : null);
    _managedHeadlessSurface = managedSurface;
    _headlessPresenterSurfaceFactory =
        headlessPresenterSurfaceFactory ?? (() => managedSurface!);
  }

  final ReportServerConnection _connection;
  final ReportingBridgeClient _bridgeClient;
  final ReportFlowPreferenceStore _preferences;
  final ReportFilePlatform _filePlatform;
  final ReportPrintPlatform _printPlatform;
  final ThermalPrinterSettingsController? _thermalPrinterSettings;
  final void Function()? _managedPrintDispose;
  final ReportSupportSharePlatform _supportSharePlatform;
  late final HeadlessPresenterSurfaceFactory _headlessPresenterSurfaceFactory;
  late final WarmableHeadlessPresenterSurface? _managedHeadlessSurface;

  @override
  final BridgeUiConfig ui;

  ReportFlowController? _activeController;
  bool _disposed = false;
  bool _surfaceReady = false;
  Future<bool>? _surfaceWarmupFuture;
  Future<bool>? _resourceRefreshFuture;

  @override
  bool get hasActiveFlow => _activeController != null;

  @override
  Future<void> probeEndpoints() {
    final healthUri = resolveBridgeApiRoute(
      _connection.endpoints.apiBaseUrl,
      'health',
    );
    return _connection.diagnostics.traceApi<void>(
      operation: 'probeEndpoints',
      method: 'GET',
      uri: healthUri,
      details: <String, Object?>{
        'presenterUri': safeBridgeLogUri(
          _connection.endpoints.presenterEntryUrl,
        ),
      },
      action: _bridgeClient.probeEndpoints,
    );
  }

  @override
  Future<List<PresenterSystem>> fetchSystems() {
    return _connection.diagnostics.traceApi<List<PresenterSystem>>(
      operation: 'fetchSystems',
      method: 'GET',
      uri: resolveBridgeApiRoute(
        _connection.endpoints.apiBaseUrl,
        'presenter/systems',
      ),
      action: _bridgeClient.fetchSystems,
    );
  }

  @override
  ReportFlowController createController(ReportOpenRequest request) {
    if (_disposed) {
      throw const ReportFlowFailure(code: ReportFlowFailureCode.disposed);
    }
    if (_activeController != null) {
      throw const ReportFlowFailure(
        code: ReportFlowFailureCode.flowAlreadyActive,
      );
    }
    late final ReportFlowControllerImpl controller;
    controller = ReportFlowControllerImpl(
      request: request,
      features: request.featuresOverride ?? ui.features,
      runtime: ReportFlowRuntime(
        connection: _connection,
        bridgeClient: _bridgeClient,
        preferences: _preferences,
        filePlatform: _filePlatform,
        surfaceBinding: PresenterSurfaceBinding(),
        printPlatform: _printPlatform,
        thermalPrinterSettings: _thermalPrinterSettings,
        supportSharePlatform: _supportSharePlatform,
      ),
      onDisposed: () {
        if (identical(_activeController, controller)) {
          _activeController = null;
        }
      },
    );
    _activeController = controller;
    return controller;
  }

  @override
  Future<ReportResult?> openReport(
    BuildContext context,
    ReportOpenRequest request,
  ) async {
    final controller = createController(request);
    try {
      return await Navigator.of(context).push<ReportResult>(
        MaterialPageRoute<ReportResult>(
          builder: (_) => ReportFlowScreen(controller: controller, ui: ui),
          fullscreenDialog: true,
        ),
      );
    } finally {
      await controller.dispose();
    }
  }

  @override
  Future<ReportPrintResult> printReportHeadless(
    ReportOpenRequest request, {
    HeadlessReportPrintProgressCallback? onProgress,
    HeadlessReportPrintTimingCallback? onTiming,
  }) async {
    // Resource synchronization is deliberately background-only. A paid sale
    // must never wait for an update that can safely activate after this print.
    await _ensureSurfaceWarm();
    return HeadlessReportPrintRunner(
      createController: () => createController(request),
      surfaceFactory: _headlessPresenterSurfaceFactory,
    ).run(onProgress: onProgress, onTiming: onTiming);
  }

  @override
  Future<HeadlessPrintWarmupResult> warmUpHeadlessPrinting(
    ReportOpenRequest request, {
    bool refreshResources = false,
  }) {
    return _warmUp(request, refreshResources: refreshResources);
  }

  Future<HeadlessPrintWarmupResult> _warmUp(
    ReportOpenRequest request, {
    required bool refreshResources,
  }) async {
    if (_disposed) {
      return const HeadlessPrintWarmupResult(
        webViewReady: false,
        resourcesRefreshed: false,
        diagnostic: 'disposed',
      );
    }
    try {
      final webViewReady = await _ensureSurfaceWarm();
      if (!refreshResources) {
        return HeadlessPrintWarmupResult(
          webViewReady: webViewReady,
          resourcesRefreshed: false,
        );
      }
      final refresh = await _refreshResourcesInBackground(request);
      return HeadlessPrintWarmupResult(
        webViewReady: webViewReady,
        resourcesRefreshed: refresh.refreshed,
        presenterMode: refresh.mode?.name,
        diagnostic: refresh.diagnostic,
      );
    } catch (error) {
      return HeadlessPrintWarmupResult(
        webViewReady: false,
        resourcesRefreshed: false,
        diagnostic: error.toString(),
      );
    }
  }

  Future<bool> _ensureSurfaceWarm() {
    if (_surfaceReady) return Future<bool>.value(true);
    final ready = _surfaceWarmupFuture;
    if (ready != null) return ready;
    late final Future<bool> future;
    future =
        () async {
          await _managedHeadlessSurface?.warmUp();
          _surfaceReady = _managedHeadlessSurface != null;
          return _surfaceReady;
        }().whenComplete(() {
          if (identical(_surfaceWarmupFuture, future)) {
            _surfaceWarmupFuture = null;
          }
        });
    _surfaceWarmupFuture = future;
    return future;
  }

  Future<({bool refreshed, PresenterModePreference? mode, String? diagnostic})>
  _refreshResourcesInBackground(ReportOpenRequest request) async {
    final running = _resourceRefreshFuture;
    if (running != null) {
      final refreshed = await running;
      return (refreshed: refreshed, mode: null, diagnostic: null);
    }
    late final Future<bool> future;
    PresenterModePreference? selectedMode;
    String? diagnostic;
    future =
        () async {
          final scope = _preferenceScopeFor(request);
          final saved = await _preferences.load(scope);
          selectedMode =
              request.presenterMode ??
              saved?.mode ??
              PresenterModePreference.online;
          final identity = request.templateSyncRequest.identity;
          final refreshClient = ReportingBridgeClient(
            apiBaseUrl: _connection.endpoints.apiBaseUrl,
            cacheIdentityBaseUrl: _connection.endpoints.cacheIdentityBaseUrl,
            presenterEntryUrl: _connection.endpoints.presenterEntryUrl,
            bridgeRoot: _connection.cacheRoot,
            bundleManifestUrl: _connection.bundleManifestUrl,
            headers: _connection.headers,
            headersProvider: _connection.headersProvider,
            httpClientFactory: _connection.httpClientFactory,
          );
          try {
            await refreshClient.updateIdentityContext(
              BridgeIdentityContext(
                userId: identity.userId,
                branchId: identity.branchId,
                systemUnit: identity.systemUnit,
              ),
            );
            await refreshClient.syncTemplates(
              systemCode: request.templateSyncRequest.systemCode.value,
              filter: request.templateSyncRequest.filter,
              extra: request.templateSyncRequest.extra,
            );
            if (selectedMode == PresenterModePreference.offline) {
              await refreshClient.syncPresenter();
            }
            return true;
          } catch (error) {
            diagnostic = error.toString();
            return false;
          } finally {
            await refreshClient.dispose();
          }
        }().whenComplete(() {
          if (identical(_resourceRefreshFuture, future)) {
            _resourceRefreshFuture = null;
          }
        });
    _resourceRefreshFuture = future;
    final refreshed = await future;
    return (refreshed: refreshed, mode: selectedMode, diagnostic: diagnostic);
  }

  ReportPreferenceScope _preferenceScopeFor(ReportOpenRequest request) {
    final identity = request.selectedTemplateCriteria.identity;
    return ReportPreferenceScope(
      connectionKey: _connection.preferenceSourceKey,
      system: request.templateSyncRequest.systemCode.value,
      reportType: request.reportType.value,
      branchId: identity.branchId,
      userId: identity.userId,
      systemUnit: identity.systemUnit,
      language: request.compatibility.language?.value,
      layout: request.compatibility.layout?.value,
      size: request.compatibility.size?.value,
      customType: request.selectedTemplateCriteria.customType,
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _activeController?.dispose();
    _activeController = null;
    await _managedHeadlessSurface?.shutdown();
    _surfaceReady = false;
    await _bridgeClient.dispose();
    _thermalPrinterSettings?.dispose();
    _managedPrintDispose?.call();
  }
}
