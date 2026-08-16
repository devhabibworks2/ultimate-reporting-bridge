import 'bridge_contract.dart';

/// Host-owned branding passed through Bridge to Presenter/runtime sessions.
class BrandConfig {
  const BrandConfig({
    this.primaryColor,
    this.logoUrl,
    this.logoAsset,
    this.extra = const <String, dynamic>{},
  });

  final String? primaryColor;
  final String? logoUrl;
  final String? logoAsset;
  final Map<String, dynamic> extra;

  static BrandConfig? fromMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) {
      return null;
    }
    return BrandConfig(
      primaryColor: raw['primaryColor'] as String?,
      logoUrl: raw['logoUrl'] as String?,
      logoAsset: raw['logoAsset'] as String?,
      extra: _stringMap(raw['extra']) ?? const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (primaryColor != null) 'primaryColor': primaryColor,
      if (logoUrl != null) 'logoUrl': logoUrl,
      if (logoAsset != null) 'logoAsset': logoAsset,
      if (extra.isNotEmpty) 'extra': extra,
    };
  }
}

/// Backend/Presenter endpoint settings supplied by Host or Bridge setup.
class ServerConfig {
  const ServerConfig({
    this.presenterUrl,
    this.apiBaseUrl,
    this.bundleManifestUrl,
    this.extra = const <String, dynamic>{},
  });

  final String? presenterUrl;
  final String? apiBaseUrl;
  final String? bundleManifestUrl;
  final Map<String, dynamic> extra;

  static ServerConfig? fromMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) {
      return null;
    }
    return ServerConfig(
      presenterUrl: raw['presenterUrl'] as String?,
      apiBaseUrl: raw['apiBaseUrl'] as String?,
      bundleManifestUrl: raw['bundleManifestUrl'] as String?,
      extra: _stringMap(raw['extra']) ?? const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (presenterUrl != null) 'presenterUrl': presenterUrl,
      if (apiBaseUrl != null) 'apiBaseUrl': apiBaseUrl,
      if (bundleManifestUrl != null) 'bundleManifestUrl': bundleManifestUrl,
      if (extra.isNotEmpty) 'extra': extra,
    };
  }
}

/// Privileged custom API headers supplied by Host.
///
/// Use [toRedactedMap] for status/debug payloads. Do not expose [toMap] to
/// Presenter JavaScript or logs.
class ApiHeaderConfig {
  const ApiHeaderConfig(this.values);

  final Map<String, String> values;

  bool get isEmpty => values.isEmpty;
  bool get isNotEmpty => values.isNotEmpty;

  static ApiHeaderConfig? fromMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) {
      return null;
    }
    final parsed = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && key.trim().isNotEmpty && value is String) {
        parsed[key] = value;
      }
    }
    return ApiHeaderConfig(Map<String, String>.unmodifiable(parsed));
  }

  Map<String, dynamic> toMap() => Map<String, String>.from(values);

  Map<String, dynamic> toRedactedMap() {
    return <String, dynamic>{
      'present': values.isNotEmpty,
      'redactedKeys': values.keys.toList(growable: false)..sort(),
    };
  }
}

/// Host action visibility/enabled state. Host owns business action UI.
class ActionsUiState {
  const ActionsUiState({
    this.canPreview = true,
    this.canSavePdf = true,
    this.canSharePdf = true,
    this.canPrintPdf = true,
    this.canShareImage = true,
  });

  final bool canPreview;
  final bool canSavePdf;
  final bool canSharePdf;
  final bool canPrintPdf;
  final bool canShareImage;

  static ActionsUiState? fromMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) {
      return null;
    }
    return ActionsUiState(
      canPreview: raw['canPreview'] as bool? ?? true,
      canSavePdf: raw['canSavePdf'] as bool? ?? true,
      canSharePdf: raw['canSharePdf'] as bool? ?? true,
      canPrintPdf: raw['canPrintPdf'] as bool? ?? true,
      canShareImage: raw['canShareImage'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'canPreview': canPreview,
      'canSavePdf': canSavePdf,
      'canSharePdf': canSharePdf,
      'canPrintPdf': canPrintPdf,
      'canShareImage': canShareImage,
    };
  }
}

/// Full Host -> Bridge initialization/config payload.
class BridgeConfig {
  const BridgeConfig({
    required this.contractVersion,
    this.reportType,
    this.reportName,
    this.locale,
    this.direction,
    this.mode,
    this.branding,
    this.server,
    this.actionsUiState,
    this.apiHeaders,
  });

  final int contractVersion;
  final String? reportType;
  final String? reportName;
  final String? locale;
  final String? direction;
  final String? mode;
  final BrandConfig? branding;
  final ServerConfig? server;
  final ActionsUiState? actionsUiState;
  final ApiHeaderConfig? apiHeaders;

  static BridgeConfig fromMap(Map<dynamic, dynamic> raw) {
    final version = raw['contractVersion'];
    final server =
        ServerConfig.fromMap(_map(raw['serverConfig'])) ??
        ServerConfig(
          presenterUrl: raw['presenterUrl'] as String?,
          apiBaseUrl: raw['apiBaseUrl'] as String?,
        );
    return BridgeConfig(
      contractVersion: version is int ? version : BridgeContract.payloadVersion,
      reportType: (raw['type'] ?? raw['reportType']) as String?,
      reportName: raw['reportName'] as String?,
      locale: raw['locale'] as String?,
      direction: raw['direction'] as String?,
      mode: raw['mode'] as String?,
      branding: BrandConfig.fromMap(_map(raw['branding'])),
      server: server,
      actionsUiState: ActionsUiState.fromMap(_map(raw['actionsUiState'])),
      apiHeaders: ApiHeaderConfig.fromMap(_map(raw['apiHeaders'])),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'contractVersion': contractVersion,
      if (reportType != null) 'type': reportType,
      if (reportName != null) 'reportName': reportName,
      if (locale != null) 'locale': locale,
      if (direction != null) 'direction': direction,
      if (mode != null) 'mode': mode,
      if (branding != null) 'branding': branding!.toMap(),
      if (server != null) 'serverConfig': server!.toMap(),
      if (actionsUiState != null) 'actionsUiState': actionsUiState!.toMap(),
      if (apiHeaders != null) 'apiHeaders': apiHeaders!.toMap(),
    };
  }

  Map<String, dynamic> toRedactedStatusMap() {
    return <String, dynamic>{
      'contractVersion': contractVersion,
      if (reportType != null) 'type': reportType,
      if (reportName != null) 'reportName': reportName,
      if (locale != null) 'locale': locale,
      if (direction != null) 'direction': direction,
      if (mode != null) 'mode': mode,
      if (branding != null) 'branding': branding!.toMap(),
      if (server != null) 'serverConfig': server!.toMap(),
      if (actionsUiState != null) 'actionsUiState': actionsUiState!.toMap(),
      if (apiHeaders != null) 'apiHeaders': apiHeaders!.toRedactedMap(),
    };
  }
}

Map<dynamic, dynamic>? _map(Object? value) {
  if (value is Map) {
    return value;
  }
  return null;
}

Map<String, dynamic>? _stringMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return <String, dynamic>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}
