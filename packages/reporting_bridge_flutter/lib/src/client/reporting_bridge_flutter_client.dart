import 'dart:typed_data';

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
import '../headless/headless_report_render_runner.dart';
import '../headless/in_app_headless_presenter_surface.dart';
import '../logging/bridge_diagnostics.dart';
import '../persistence/report_flow_preference_store.dart';
import '../platform/bridge_platform_adapters.dart';
import '../platform/presenter_surface_binding.dart';
import '../presenter/presenter_warmup.dart';
import '../presenter/presenter_warmup_coordinator.dart';
import '../presenter/report_resource_preparation_service.dart';
import '../printing/thermal_printer_controller.dart';
import '../ui/bridge_ui_config.dart';
import '../ui/report_flow_screen.dart';
import 'report_server_connection.dart';

@visibleForTesting
PageRoute<T> buildReportFlowRouteForTesting<T>({
  required WidgetBuilder builder,
}) => _buildReportFlowRoute<T>(builder: builder);

PageRoute<T> _buildReportFlowRoute<T>({required WidgetBuilder builder}) =>
    PageRouteBuilder<T>(
      opaque: true,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    );

abstract interface class ReportingBridgeFlutterClient {
  BridgeUiConfig get ui;
  bool get hasActiveFlow;

  Future<void> probeEndpoints();
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

  Future<Uint8List> generateReportPdfHeadless(ReportOpenRequest request);

  Future<PresenterWarmupResult> warmUpPresenter(
    ReportOpenRequest request, {
    bool refreshResources = false,
    bool warmHeadlessSurface = false,
  });

  @Deprecated('Use warmUpPresenter instead.')
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
        const UnsupportedReportSupportSharePlatform(),
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
    _warmupCoordinator = PresenterWarmupCoordinator(
      warmSurface: _ensureSurfaceWarm,
      resolveMode: _resolveWarmupMode,
      refreshResources: _refreshWarmupResources,
    );
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
  late final PresenterWarmupCoordinator _warmupCoordinator;

  @override
  final BridgeUiConfig ui;

  ReportFlowController? _activeController;
  bool _disposed = false;
  bool _surfaceReady = false;
  Future<bool>? _surfaceWarmupFuture;

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
        surfaceBinding: PresenterSurfaceBinding(
          diagnostics: _connection.diagnostics,
        ),
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
        _buildReportFlowRoute<ReportResult>(
          builder: (_) => ReportFlowScreen(controller: controller, ui: ui),
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
    _ensureHeadlessFlowAvailable();
    await _ensureSurfaceWarm();
    return HeadlessReportPrintRunner(
      createController: () => createController(request),
      surfaceFactory: _headlessPresenterSurfaceFactory,
    ).run(onProgress: onProgress, onTiming: onTiming);
  }

  @override
  Future<Uint8List> generateReportPdfHeadless(ReportOpenRequest request) async {
    _ensureHeadlessFlowAvailable();
    await _ensureSurfaceWarm();
    return HeadlessReportRenderRunner(
      createController: () => createController(request),
      surfaceFactory: _headlessPresenterSurfaceFactory,
    ).run<Uint8List>(
      consume: (controller) async {
        final pdf = await controller.presenterSurface.exportPdf();
        return Uint8List.fromList(pdf.bytes);
      },
    );
  }

  @override
  Future<PresenterWarmupResult> warmUpPresenter(
    ReportOpenRequest request, {
    bool refreshResources = false,
    bool warmHeadlessSurface = false,
  }) {
    return _warmupCoordinator.warmUp(
      request,
      refreshResources: refreshResources,
      warmHeadlessSurface: warmHeadlessSurface,
    );
  }

  @override
  @Deprecated('Use warmUpPresenter(..., warmHeadlessSurface: true).')
  Future<HeadlessPrintWarmupResult> warmUpHeadlessPrinting(
    ReportOpenRequest request, {
    bool refreshResources = false,
  }) async {
    final result = await warmUpPresenter(
      request,
      refreshResources: refreshResources,
      warmHeadlessSurface: true,
    );
    return HeadlessPrintWarmupResult(
      webViewReady: result.surfaceStatus == PresenterWarmupSurfaceStatus.ready,
      resourcesRefreshed:
          result.resourceStatus == PresenterWarmupResourceStatus.refreshed,
      presenterMode: result.presenterMode?.name,
      diagnostic: result.diagnostic,
    );
  }

  void _ensureHeadlessFlowAvailable() {
    if (_disposed) {
      throw const ReportFlowFailure(code: ReportFlowFailureCode.disposed);
    }
    if (_activeController != null) {
      throw const ReportFlowFailure(
        code: ReportFlowFailureCode.flowAlreadyActive,
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

  Future<PresenterModePreference> _resolveWarmupMode(
    ReportOpenRequest request,
  ) async {
    final saved = await _preferences.load(_preferenceScopeFor(request));
    return request.presenterMode ??
        saved?.mode ??
        PresenterModePreference.online;
  }

  Future<void> _refreshWarmupResources(
    ReportOpenRequest request,
    PresenterModePreference mode,
  ) async {
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
      await ReportResourcePreparationService(
        bridgeClient: refreshClient,
      ).prepare(request.templateSyncRequest, mode: mode);
    } finally {
      await refreshClient.dispose();
    }
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
    _warmupCoordinator.dispose();
    await _managedHeadlessSurface?.shutdown();
    _surfaceReady = false;
    await _bridgeClient.dispose();
    _thermalPrinterSettings?.dispose();
    _managedPrintDispose?.call();
  }
}
