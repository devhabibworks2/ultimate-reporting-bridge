import 'package:flutter/foundation.dart';
import 'package:reporting_bridge/reporting_bridge.dart';

import '../persistence/report_flow_preference_store.dart';
import '../persistence/thermal_printer_settings_store.dart';
import '../platform/android_print_configuration.dart';
import '../platform/android_report_print_platform.dart';
import '../platform/bridge_platform_adapters.dart';
import '../platform/ios_air_print_report_print_platform.dart';
import '../platform/ios_print_configuration.dart';
import '../platform/managed_print_platform.dart';
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
    this.androidPrintConfiguration = const AndroidPrintConfiguration.escPos(),
    this.iosPrintMode = IosPrintMode.airPrint,
    this.supportSharePlatform = const SharePlusReportSupportSharePlatform(),
  }) : _printPlatformOverride = printPlatform;

  final ReportServerConnection connection;
  final BridgeUiConfig ui;
  final ReportFlowPreferenceStore? preferences;
  final ReportFilePlatform filePlatform;

  /// Optional host-injected print gateway. When present it bypasses all
  /// managed Android/iOS print composition.
  final ReportPrintPlatform? _printPlatformOverride;

  /// Compatibility getter for hosts that inspect the configured override.
  ReportPrintPlatform get printPlatform =>
      _printPlatformOverride ?? const UnsupportedReportPrintPlatform();

  final AndroidPrintConfiguration androidPrintConfiguration;
  final IosPrintMode iosPrintMode;

  /// User-initiated native share boundary for development-support archives.
  final ReportSupportSharePlatform supportSharePlatform;

  Future<ReportingBridgeFlutterClient> createClient() async {
    await connection.cacheRoot.create(recursive: true);
    final preferenceStore =
        preferences ??
        await SharedPreferencesReportFlowPreferenceStore.create();
    final managedPrint = await resolveManagedPrintPlatform(
      override: _printPlatformOverride,
      effectivePlatform: kIsWeb ? null : defaultTargetPlatform,
      androidConfiguration: androidPrintConfiguration,
      iosPrintMode: iosPrintMode,
      thermalFactory: (configuration) async {
        final settingsStore =
            await SharedPreferencesThermalPrinterSettingsStore.create();
        final nativeClient = PigeonThermalPrinterNativeClient();
        final thermalPlatform = ThermalReportPrintPlatform(
          settingsStore: settingsStore,
          artifactStore: await ThermalPdfArtifactStore.create(),
          nativeClient: nativeClient,
        );
        final thermalPrinterSettings = ThermalPrinterSettingsController(
          settingsStore: settingsStore,
          nativeClient: nativeClient,
          availabilitySink: thermalPlatform,
          testPlatform: thermalPlatform,
        );
        await thermalPrinterSettings.ensureLoaded();
        return ManagedPrintPlatformResources(
          platform: thermalPlatform,
          thermalPrinterSettings: thermalPrinterSettings,
          dispose: thermalPlatform.dispose,
        );
      },
      androidFactory: (configuration) async {
        final platform = AndroidReportPrintPlatform(
          configuration: configuration,
        );
        return ManagedPrintPlatformResources(
          platform: platform,
          dispose: platform.dispose,
        );
      },
      iosFactory: (mode) async {
        return switch (mode) {
          IosPrintMode.airPrint => const ManagedPrintPlatformResources(
            platform: IosAirPrintReportPrintPlatform(),
          ),
        };
      },
    );
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
    return DefaultReportingBridgeFlutterClient(
      connection: connection,
      bridgeClient: client,
      preferences: preferenceStore,
      filePlatform: filePlatform,
      printPlatform: managedPrint.platform,
      thermalPrinterSettings: managedPrint.thermalPrinterSettings,
      managedPrintDispose: managedPrint.dispose,
      supportSharePlatform: supportSharePlatform,
      ui: ui,
    );
  }
}
