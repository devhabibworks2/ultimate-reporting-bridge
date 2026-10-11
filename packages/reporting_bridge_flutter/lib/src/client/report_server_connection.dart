import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';

import '../logging/bridge_diagnostics.dart';

class ReportServerConnection {
  const ReportServerConnection({
    required this.endpoints,
    required this.cacheRoot,
    this.bundleManifestUrl,
    this.thumbnailTenantId,
    this.headers = const <String, String>{},
    this.headersProvider,
    this.httpClientFactory,
    this.diagnostics = const BridgeDiagnostics.disabled(),
  });

  final ReportServerEndpoints endpoints;
  final Directory cacheRoot;
  final String? bundleManifestUrl;

  /// Optional additional customer/tenant cache isolation. Existing Hosts do
  /// not need to provide this: thumbnail GETs use existing authorization and
  /// caching is scoped to the resolved credential/customer when available.
  final String? thumbnailTenantId;
  final Map<String, String> headers;
  final BridgeHeadersProvider? headersProvider;
  final HttpClient Function()? httpClientFactory;
  final BridgeDiagnostics diagnostics;

  String get preferenceSourceKey => <String>[
    endpoints.profile.name,
    endpoints.serverUrl.toString(),
    endpoints.cacheIdentityBaseUrl.toString(),
    endpoints.presenterEntryUrl.toString(),
    '${endpoints.localBackendPort}',
    '${endpoints.localPresenterPort}',
  ].join('|');
}
