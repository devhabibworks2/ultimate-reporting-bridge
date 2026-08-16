import 'package:reporting_bridge/reporting_bridge.dart';

import '../persistence/report_flow_preference_store.dart';
import '../platform/bridge_platform_adapters.dart';
import '../ui/bridge_ui_config.dart';
import 'report_server_connection.dart';
import 'reporting_bridge_flutter_client.dart';

class ReportingBridgeFlutter {
  const ReportingBridgeFlutter({
    required this.connection,
    this.ui = const BridgeUiConfig.inheritHost(),
    this.preferences,
    this.filePlatform = const DefaultReportFilePlatform(),
    this.printPlatform = const UnsupportedReportPrintPlatform(),
    this.supportSharePlatform = const SharePlusReportSupportSharePlatform(),
  });

  final ReportServerConnection connection;
  final BridgeUiConfig ui;
  final ReportFlowPreferenceStore? preferences;
  final ReportFilePlatform filePlatform;

  /// Host-injected print gateway.
  ///
  /// Defaults to [UnsupportedReportPrintPlatform]. Android/iOS Hosts must
  /// supply their approved platform implementation; Flutter never creates
  /// content:// URIs itself.
  final ReportPrintPlatform printPlatform;

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
    return DefaultReportingBridgeFlutterClient(
      connection: connection,
      bridgeClient: client,
      preferences: preferenceStore,
      filePlatform: filePlatform,
      printPlatform: printPlatform,
      supportSharePlatform: supportSharePlatform,
      ui: ui,
    );
  }
}
