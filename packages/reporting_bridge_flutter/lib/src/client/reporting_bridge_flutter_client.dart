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
  }) : _connection = connection,
       _bridgeClient = bridgeClient,
       _preferences = preferences,
       _filePlatform = filePlatform,
       _printPlatform = printPlatform,
       _thermalPrinterSettings = thermalPrinterSettings,
       _managedPrintDispose = managedPrintDispose,
       _supportSharePlatform = supportSharePlatform,
       _headlessPresenterSurfaceFactory =
           headlessPresenterSurfaceFactory ?? InAppHeadlessPresenterSurface.new;

  final ReportServerConnection _connection;
  final ReportingBridgeClient _bridgeClient;
  final ReportFlowPreferenceStore _preferences;
  final ReportFilePlatform _filePlatform;
  final ReportPrintPlatform _printPlatform;
  final ThermalPrinterSettingsController? _thermalPrinterSettings;
  final void Function()? _managedPrintDispose;
  final ReportSupportSharePlatform _supportSharePlatform;
  final HeadlessPresenterSurfaceFactory _headlessPresenterSurfaceFactory;

  @override
  final BridgeUiConfig ui;

  ReportFlowController? _activeController;
  bool _disposed = false;

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
  }) {
    return HeadlessReportPrintRunner(
      createController: () => createController(request),
      surfaceFactory: _headlessPresenterSurfaceFactory,
    ).run(onProgress: onProgress);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _activeController?.dispose();
    _activeController = null;
    await _bridgeClient.dispose();
    _thermalPrinterSettings?.dispose();
    _managedPrintDispose?.call();
  }
}
