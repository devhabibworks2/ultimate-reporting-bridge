import 'package:flutter/foundation.dart';
import 'package:reporting_bridge/reporting_bridge.dart';

import '../persistence/report_flow_preference_store.dart';
import '../persistence/thermal_printer_settings_store.dart';
import '../platform/bridge_platform_adapters.dart';
import '../printing/thermal_pdf_artifact_store.dart';
import '../printing/thermal_printer_controller.dart';
import '../printing/thermal_printer_native_client.dart';
import '../printing/thermal_report_print_platform.dart';
import '../ui/bridge_ui_config.dart';
import 'report_server_connection.dart';
import 'reporting_bridge_flutter_client.dart';

class ReportingBridgeFlutter {
  const ReportingBridgeFlutter({
    required this.connection,
    this.ui = const BridgeUiConfig.inheritHost(),
    this.preferences,
    this.filePlatform = const DefaultReportFilePlatform(),
    ReportPrintPlatform? printPlatform,
    this.supportSharePlatform = const SharePlusReportSupportSharePlatform(),
  }) : _printPlatformOverride = printPlatform;

  final ReportServerConnection connection;
  final BridgeUiConfig ui;
  final ReportFlowPreferenceStore? preferences;
  final ReportFilePlatform filePlatform;

  /// An optional host print gateway. A supplied value always overrides the
  /// managed Android thermal implementation.
  final ReportPrintPlatform? _printPlatformOverride;

  ReportPrintPlatform get printPlatform =>
      _printPlatformOverride ?? const UnsupportedReportPrintPlatform();

  /// User-initiated native share boundary for development-support archives.
  final ReportSupportSharePlatform supportSharePlatform;

  Future<ReportingBridgeFlutterClient> createClient() async {
    await connection.cacheRoot.create(recursive: true);
    final preferenceStore =
        preferences ??
        await SharedPreferencesReportFlowPreferenceStore.create();
    final client = ReportingBridgeClient(
      apiBaseUrl: connection.endpoints.apiBaseUrl,
      cacheIdentityBaseUrl: connection.endpoints.cacheIdentityBaseUrl,
      presenterEntryUrl: connection.endpoints.presenterEntryUrl,
      bridgeRoot: connection.cacheRoot,
      bundleManifestUrl: connection.bundleManifestUrl,
      headers: connection.headers,
      headersProvider: connection.headersProvider,
      httpClientFactory: connection.httpClientFactory,
    );
    var effectivePrintPlatform = _printPlatformOverride;
    ThermalPrinterSettingsController? thermalPrinterSettings;
    if (effectivePrintPlatform == null &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      final store = await SharedPreferencesThermalPrinterSettingsStore.create();
      final nativeClient = PigeonThermalPrinterNativeClient();
      final thermalPlatform = ThermalReportPrintPlatform(
        settingsStore: store,
        artifactStore: await ThermalPdfArtifactStore.create(),
        nativeClient: nativeClient,
      );
      thermalPrinterSettings = ThermalPrinterSettingsController(
        settingsStore: store,
        nativeClient: nativeClient,
        availabilitySink: thermalPlatform,
        testPlatform: thermalPlatform,
      );
      await thermalPrinterSettings.ensureLoaded();
      effectivePrintPlatform = thermalPlatform;
    }
    return DefaultReportingBridgeFlutterClient(
      connection: connection,
      bridgeClient: client,
      preferences: preferenceStore,
      filePlatform: filePlatform,
      printPlatform:
          effectivePrintPlatform ?? const UnsupportedReportPrintPlatform(),
      thermalPrinterSettings: thermalPrinterSettings,
      managedPrintDispose: effectivePrintPlatform is ThermalReportPrintPlatform
          ? effectivePrintPlatform.dispose
          : null,
      supportSharePlatform: supportSharePlatform,
      ui: ui,
    );
  }
}
