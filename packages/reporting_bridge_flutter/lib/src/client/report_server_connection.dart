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
    this.allowInvalidServerCertificates = false,
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

  /// Opt-in for development servers with expired, self-signed, or incomplete
  /// HTTPS certificate chains. Only the configured API and Presenter origins
  /// are exempted. This weakens TLS authentication and must not be enabled
  /// when transmitting sensitive credentials over untrusted networks.
  final bool allowInvalidServerCertificates;

  /// True only for an explicitly opted-in HTTPS API or Presenter origin.
  /// Host and port must both match; unrelated or redirected hosts are denied.
  bool acceptsInvalidCertificateFor(String host, int port) {
    if (!allowInvalidServerCertificates) return false;
    bool matches(Uri uri) =>
        uri.scheme == 'https' &&
        uri.host.toLowerCase() == host.toLowerCase() &&
        uri.port == port;
    return matches(endpoints.apiBaseUrl) ||
        matches(endpoints.presenterEntryUrl);
  }

  /// Preserves custom transport injection. Otherwise, optionally overrides
  /// TLS verification only for the configured Report Server endpoints.
  HttpClient Function()? get resolvedHttpClientFactory {
    if (httpClientFactory != null || !allowInvalidServerCertificates) {
      return httpClientFactory;
    }
    return () =>
        HttpClient()
          ..badCertificateCallback = (_, host, port) =>
              acceptsInvalidCertificateFor(host, port);
  }

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
