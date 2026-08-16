import 'bridge_runtime_error.dart';

enum ReportServerProfile { deployed, localDevelopment }

extension ReportServerProfileX on ReportServerProfile {
  static ReportServerProfile? tryParse(Object? value) {
    final raw = value?.toString();
    for (final profile in ReportServerProfile.values) {
      if (profile.name == raw) return profile;
    }
    return null;
  }
}

/// Canonical endpoint set derived from one Ultimate Report server URL.
class ReportServerEndpoints {
  const ReportServerEndpoints._({
    required this.profile,
    required this.serverUrl,
    required this.apiBaseUrl,
    required this.presenterEntryUrl,
    required this.localBackendPort,
    required this.localPresenterPort,
  });

  static const String deployedApiPath = '/UltimateReport/backend/api/';
  static const String legacyDeployedApiPath = '/UltimateReport/backend/';
  static const String presenterPath =
      '/UltimateReport/apps/presenter/index.html';
  static const int defaultLocalBackendPort = 8000;
  static const int defaultLocalPresenterPort = 8080;

  final ReportServerProfile profile;
  final Uri serverUrl;
  final Uri apiBaseUrl;
  final Uri presenterEntryUrl;
  final int localBackendPort;
  final int localPresenterPort;

  /// Stable pre-canonicalization source used only for cache/preference identity.
  /// Network requests must use [apiBaseUrl].
  Uri get cacheIdentityBaseUrl => switch (profile) {
    ReportServerProfile.deployed => serverUrl.replace(
      path: legacyDeployedApiPath,
    ),
    ReportServerProfile.localDevelopment => Uri(
      scheme: serverUrl.scheme,
      host: serverUrl.host,
      port: localBackendPort,
      path: '/',
    ),
  };

  factory ReportServerEndpoints.resolve({
    required Uri serverUrl,
    required ReportServerProfile profile,
    int localBackendPort = defaultLocalBackendPort,
    int localPresenterPort = defaultLocalPresenterPort,
  }) {
    return switch (profile) {
      ReportServerProfile.deployed => ReportServerEndpoints.deployed(serverUrl),
      ReportServerProfile.localDevelopment =>
        ReportServerEndpoints.localDevelopment(
          serverUrl,
          backendPort: localBackendPort,
          presenterPort: localPresenterPort,
        ),
    };
  }

  factory ReportServerEndpoints.deployed(Uri value) {
    final server = normalizeServerUrl(value);
    return ReportServerEndpoints._(
      profile: ReportServerProfile.deployed,
      serverUrl: server,
      apiBaseUrl: server.replace(path: deployedApiPath),
      presenterEntryUrl: server.replace(path: presenterPath),
      localBackendPort: defaultLocalBackendPort,
      localPresenterPort: defaultLocalPresenterPort,
    );
  }

  factory ReportServerEndpoints.localDevelopment(
    Uri value, {
    int backendPort = defaultLocalBackendPort,
    int presenterPort = defaultLocalPresenterPort,
  }) {
    _validatePort(backendPort, 'Local backend');
    _validatePort(presenterPort, 'Local Presenter');
    final normalized = normalizeServerUrl(value);
    final server = Uri(scheme: normalized.scheme, host: normalized.host);
    return ReportServerEndpoints._(
      profile: ReportServerProfile.localDevelopment,
      serverUrl: server,
      apiBaseUrl: Uri(
        scheme: server.scheme,
        host: server.host,
        port: backendPort,
        path: deployedApiPath,
      ),
      presenterEntryUrl: Uri(
        scheme: server.scheme,
        host: server.host,
        port: presenterPort,
        path: presenterPath,
      ),
      localBackendPort: backendPort,
      localPresenterPort: presenterPort,
    );
  }

  static Uri parseServerUrl(String value) {
    final parsed = Uri.tryParse(value.trim());
    if (parsed == null) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Report Server URL is invalid.',
      );
    }
    return normalizeServerUrl(parsed);
  }

  static Uri parseDeployedServerUrl(String value) => parseServerUrl(value);

  static Uri normalizeServerUrl(Uri value) {
    if (!value.hasScheme ||
        value.host.isEmpty ||
        (value.scheme != 'http' && value.scheme != 'https') ||
        value.userInfo.isNotEmpty) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Report Server URL must be an absolute HTTP or HTTPS URL without credentials.',
      );
    }
    return Uri.parse('${value.scheme}://${value.authority}');
  }

  static Uri? inferDeployedServerUrl(Object? value) {
    final parsed = value is Uri
        ? value
        : Uri.tryParse(value?.toString().trim() ?? '');
    if (parsed == null ||
        !parsed.hasScheme ||
        parsed.host.isEmpty ||
        (parsed.scheme != 'http' && parsed.scheme != 'https') ||
        parsed.userInfo.isNotEmpty) {
      return null;
    }
    return Uri.parse('${parsed.scheme}://${parsed.authority}');
  }

  static void _validatePort(int value, String label) {
    if (value < 1 || value > 65535) {
      throw BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        '$label port must be between 1 and 65535.',
      );
    }
  }
}
