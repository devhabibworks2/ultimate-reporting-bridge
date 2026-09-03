import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../contracts/report_open_request.dart';

class ReportPreferenceScope {
  const ReportPreferenceScope({
    required this.connectionKey,
    this.system = '',
    this.systemId,
    required this.reportType,
    this.tenantId,
    this.branchId,
    this.userId,
    this.systemUnit,
    this.language,
    this.layout,
    this.size,
    this.customType,
  });

  final String connectionKey;
  final String system;
  final int? systemId;
  final String reportType;
  final String? tenantId;
  final String? branchId;
  final String? userId;
  final String? systemUnit;
  final String? language;
  final String? layout;
  final String? size;
  final String? customType;

  String get effectiveSystem {
    final code = system.trim().toLowerCase();
    if (code.isNotEmpty) return code;
    return 'legacy_system_${systemId ?? 0}';
  }

  /// Durable selected-template identity is System-scoped.
  ///
  /// [customType] is developer-defined identity: trim only, never case-fold.
  String get selectedTemplateCanonical => <String>[
    'system=${_scopePart(effectiveSystem)}',
    'report=${_scopePart(reportType.toLowerCase())}',
    'user=${_scopePart(userId)}',
    'branch=${_scopePart(branchId)}',
    'systemUnit=${_scopePart(systemUnit)}',
    'customType=${_scopePart(customType)}',
  ].join('|');

  String get selectedTemplateStorageToken => base64Url
      .encode(utf8.encode(selectedTemplateCanonical))
      .replaceAll('=', '');

  /// V5 selected-template key retained for one-way migration reads only.
  String get legacySelectedTemplateV5Canonical => <String>[
    'report=${_scopePart(reportType.toLowerCase())}',
    'user=${_scopePart(userId)}',
    'branch=${_scopePart(branchId)}',
    'systemUnit=${_scopePart(systemUnit)}',
    'customType=${_scopePart(customType)}',
  ].join('|');

  String get legacySelectedTemplateV5StorageToken => base64Url
      .encode(utf8.encode(legacySelectedTemplateV5Canonical))
      .replaceAll('=', '');

  /// Presenter-mode operational identity: connection + system + report + identity.
  String get presenterModeCanonical => <String>[
    'source=${_scopePart(connectionKey)}',
    'system=${_scopePart(effectiveSystem)}',
    'report=${_scopePart(reportType.toLowerCase())}',
    'user=${_scopePart(userId)}',
    'branch=${_scopePart(branchId)}',
    'systemUnit=${_scopePart(systemUnit)}',
    'customType=${_scopePart(customType)}',
  ].join('|');

  String get presenterModeStorageToken =>
      base64Url.encode(utf8.encode(presenterModeCanonical)).replaceAll('=', '');

  /// Legacy V4 combined key retained for migration reads only.
  String get canonical => <String>[
    'source=${_scopePart(connectionKey)}',
    'tenant=${_scopePart(tenantId)}',
    'branch=${_scopePart(branchId)}',
    'user=${_scopePart(userId)}',
    'systemUnit=${_scopePart(systemUnit)}',
    'system=${_scopePart(effectiveSystem)}',
    'report=${_scopePart(reportType.toLowerCase())}',
    'language=${_scopePart(language?.toLowerCase())}',
    'layout=${_scopePart(layout?.toLowerCase())}',
    'size=${_scopePart(size?.toLowerCase())}',
    'customType=${_scopePart(customType?.toLowerCase())}',
  ].join('|');

  String get storageToken =>
      base64Url.encode(utf8.encode(canonical)).replaceAll('=', '');

  /// Deterministic numeric system id for V1–V3 migration only.
  int? get resolvedLegacySystemId {
    if (systemId != null) return systemId;
    final match = RegExp(
      r'^legacy_system_(\d+)$',
    ).firstMatch(system.trim().toLowerCase());
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  String? get legacyV3StorageToken {
    final id = resolvedLegacySystemId;
    if (id == null) return null;
    final legacyCanonical = '$connectionKey|$id|$reportType';
    return base64Url.encode(utf8.encode(legacyCanonical)).replaceAll('=', '');
  }
}

class ReportFlowPreferences {
  const ReportFlowPreferences({
    this.templateId,
    this.templateCode,
    required this.mode,
    this.language,
    this.layout,
    this.size,
    this.customType,
  });

  /// Transient/runtime or legacy template id. Never written as V6 durable identity.
  final String? templateId;

  /// Permanent business identity used by durable selected-template storage.
  final String? templateCode;
  final PresenterModePreference mode;
  final String? language;
  final String? layout;
  final String? size;
  final String? customType;

  ReportFlowPreferences copyWith({
    String? templateId,
    bool clearTemplateId = false,
    String? templateCode,
    bool clearTemplateCode = false,
    PresenterModePreference? mode,
    String? language,
    String? layout,
    String? size,
    String? customType,
  }) => ReportFlowPreferences(
    templateId: clearTemplateId ? null : templateId ?? this.templateId,
    templateCode: clearTemplateCode ? null : templateCode ?? this.templateCode,
    mode: mode ?? this.mode,
    language: language ?? this.language,
    layout: layout ?? this.layout,
    size: size ?? this.size,
    customType: customType ?? this.customType,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (templateId != null) 'templateId': templateId,
    if (templateCode != null) 'templateCode': templateCode,
    'mode': mode.name,
    if (language != null) 'language': language,
    if (layout != null) 'layout': layout,
    if (size != null) 'size': size,
    if (customType != null) 'customType': customType,
  };

  static ReportFlowPreferences? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final rawTemplateId = raw['templateId']?.toString().trim();
    final templateId = rawTemplateId == null || rawTemplateId.isEmpty
        ? null
        : rawTemplateId;
    final rawTemplateCode = raw['templateCode']?.toString().trim();
    final templateCode = rawTemplateCode == null || rawTemplateCode.isEmpty
        ? null
        : rawTemplateCode;
    final modeName = (raw['mode'] ?? raw['runMode'])?.toString();
    final mode = PresenterModePreference.values
        .where((value) => value.name == modeName)
        .firstOrNull;
    if (templateId == null && templateCode == null && mode == null) return null;
    return ReportFlowPreferences(
      templateId: templateId,
      templateCode: templateCode,
      mode: mode ?? PresenterModePreference.online,
      language: _optionalCode(raw['language']),
      layout: _optionalCode(raw['layout']),
      size: _optionalCode(raw['size']),
      customType: _optionalCode(raw['customType']),
    );
  }
}

abstract interface class ReportFlowPreferenceStore {
  Future<ReportFlowPreferences?> load(ReportPreferenceScope scope);
  Future<void> save(
    ReportPreferenceScope scope,
    ReportFlowPreferences preferences,
  );
  Future<void> remove(ReportPreferenceScope scope);

  /// Clears only the selected-template record.
  ///
  /// Presenter-mode preferences are intentionally preserved.
  Future<void> removeSelectedTemplate(ReportPreferenceScope scope);
}

class SharedPreferencesReportFlowPreferenceStore
    implements ReportFlowPreferenceStore {
  SharedPreferencesReportFlowPreferenceStore(this._preferences);

  static const _selectedTemplatePrefix =
      'urb.reporting_bridge.selected_template.v6.';
  static const _legacySelectedTemplateV5Prefix =
      'urb.reporting_bridge.selected_template.v5.';
  static const _presenterModePrefix = 'urb.reporting_bridge.presenter_mode.v1.';
  static const _legacyV4Prefix = 'urb.reporting_bridge.default.v4.';
  static const _legacyV3Prefix = 'urb.reporting_bridge.default.v3.';
  static const _legacyV2MapKey = 'erp_host.report_defaults.v2';
  static const _legacyV1MapKey = 'erp_host.report_defaults.v1';
  static const _legacyTemplateIdKey = 'erp_host.template_id';
  static const _legacyRunModeKey = 'erp_host.run_mode';
  static const _legacyServerUrlKey = 'erp_host.server_url';
  static const _legacyServerProfileKey = 'erp_host.server_profile';
  static const _legacySystemIdKey = 'erp_host.system_id';
  static const _legacyReportTypeKey = 'erp_host.report_type';
  static Future<void> _serial = Future<void>.value();

  final SharedPreferences _preferences;

  static Future<SharedPreferencesReportFlowPreferenceStore> create() async =>
      SharedPreferencesReportFlowPreferenceStore(
        await SharedPreferences.getInstance(),
      );

  String _selectedKey(ReportPreferenceScope scope) =>
      '$_selectedTemplatePrefix${scope.selectedTemplateStorageToken}';

  String _legacySelectedV5Key(ReportPreferenceScope scope) =>
      '$_legacySelectedTemplateV5Prefix${scope.legacySelectedTemplateV5StorageToken}';

  String _modeKey(ReportPreferenceScope scope) =>
      '$_presenterModePrefix${scope.presenterModeStorageToken}';

  @override
  Future<ReportFlowPreferences?> load(ReportPreferenceScope scope) =>
      _synchronized(() async {
        final selectedCode = _decodeSelectedCode(
          _preferences.getString(_selectedKey(scope)),
          expectedSystemCode: scope.effectiveSystem,
        );
        final mode = _decodeMode(_preferences.getString(_modeKey(scope)));
        if (selectedCode != null) {
          return ReportFlowPreferences(
            templateCode: selectedCode,
            mode: mode ?? PresenterModePreference.online,
          );
        }

        // V5 stored a runtime/cache ID without System. It is returned only as
        // migration input; the controller must resolve it against the active
        // System catalog before any V6 durable write can occur.
        final legacyV5Id = _decodeLegacySelectedId(
          _preferences.getString(_legacySelectedV5Key(scope)),
        );
        if (legacyV5Id != null) {
          return ReportFlowPreferences(
            templateId: legacyV5Id,
            mode: mode ?? PresenterModePreference.online,
          );
        }

        final legacy = await _loadLegacy(scope);
        if (legacy != null) {
          await _writeMode(scope, legacy.mode);
          return legacy;
        }
        if (mode != null) {
          return ReportFlowPreferences(mode: mode);
        }
        return null;
      });

  @override
  Future<void> save(
    ReportPreferenceScope scope,
    ReportFlowPreferences preferences,
  ) => _synchronized(() => _writeV6(scope, preferences));

  @override
  Future<void> remove(ReportPreferenceScope scope) => _synchronized(() async {
    await _preferences.remove(_selectedKey(scope));
    await _preferences.remove(_legacySelectedV5Key(scope));
    await _preferences.remove(_modeKey(scope));
  });

  @override
  Future<void> removeSelectedTemplate(ReportPreferenceScope scope) =>
      _synchronized(() async {
        await _preferences.remove(_selectedKey(scope));
        await _preferences.remove(_legacySelectedV5Key(scope));
      });

  Future<void> _writeV6(
    ReportPreferenceScope scope,
    ReportFlowPreferences preferences,
  ) async {
    final templateCode = preferences.templateCode?.trim();
    if (templateCode != null && templateCode.isNotEmpty) {
      await _preferences.setString(
        _selectedKey(scope),
        jsonEncode(<String, dynamic>{
          'systemCode': scope.effectiveSystem,
          'templateCode': templateCode,
        }),
      );
      // A genuine V6 Code supersedes any old ID record.
      await _preferences.remove(_legacySelectedV5Key(scope));
    } else if (preferences.templateId == null) {
      await _preferences.remove(_selectedKey(scope));
    }
    await _writeMode(scope, preferences.mode);
  }

  Future<void> _writeMode(
    ReportPreferenceScope scope,
    PresenterModePreference mode,
  ) => _preferences.setString(
    _modeKey(scope),
    jsonEncode(<String, dynamic>{'mode': mode.name}),
  );

  Future<ReportFlowPreferences?> _loadLegacy(
    ReportPreferenceScope scope,
  ) async {
    final v4 = _decode(
      _preferences.getString('$_legacyV4Prefix${scope.storageToken}'),
    );
    if (v4 != null) return v4;

    final legacyV3Token = scope.legacyV3StorageToken;
    if (legacyV3Token != null) {
      final legacyV3 = _decode(
        _preferences.getString('$_legacyV3Prefix$legacyV3Token'),
      );
      if (legacyV3 != null) return legacyV3;
    }

    return _legacyMatch(scope);
  }

  ReportFlowPreferences? _legacyMatch(ReportPreferenceScope scope) {
    if (scope.resolvedLegacySystemId == null) return null;
    for (final key in const <String>[_legacyV2MapKey, _legacyV1MapKey]) {
      final match = _legacyMapMatch(
        scope: scope,
        raw: _preferences.getString(key),
      );
      if (match != null) return match;
    }
    return _legacyStandaloneMatch(scope);
  }

  static ReportFlowPreferences? _legacyMapMatch({
    required ReportPreferenceScope scope,
    required String? raw,
  }) {
    final expectedSystemId = scope.resolvedLegacySystemId;
    if (expectedSystemId == null) return null;
    if (raw == null || raw.trim().isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    for (final entry in decoded.entries) {
      final parts = entry.key.toString().split('|');
      if (parts.length != 3) continue;
      final systemId = int.tryParse(parts[1]);
      if (systemId != expectedSystemId || parts[2] != scope.reportType) {
        continue;
      }
      final source = Uri.decodeComponent(parts[0]);
      if (!_sameLegacySource(scope.connectionKey, source)) continue;
      final value = ReportFlowPreferences.fromJson(entry.value);
      if (value != null) return value;
    }
    return null;
  }

  ReportFlowPreferences? _legacyStandaloneMatch(ReportPreferenceScope scope) {
    final templateId = _preferences.getString(_legacyTemplateIdKey)?.trim();
    if (templateId == null || templateId.isEmpty) return null;
    if (_preferences.getInt(_legacySystemIdKey) !=
        scope.resolvedLegacySystemId) {
      return null;
    }
    if (_preferences.getString(_legacyReportTypeKey) != scope.reportType) {
      return null;
    }
    final profile = _preferences.getString(_legacyServerProfileKey)?.trim();
    final serverUrl = _preferences.getString(_legacyServerUrlKey)?.trim();
    if (profile == null ||
        serverUrl == null ||
        !_sameLegacySource(scope.connectionKey, '$profile:$serverUrl')) {
      return null;
    }
    final modeName = _preferences.getString(_legacyRunModeKey);
    final mode = PresenterModePreference.values
        .where((value) => value.name == modeName)
        .firstOrNull;
    return ReportFlowPreferences(
      templateId: templateId,
      mode: mode ?? PresenterModePreference.online,
    );
  }

  static bool _sameLegacySource(String connectionKey, String legacySource) {
    var source = legacySource.trim().replaceFirst(RegExp(r'/$'), '');
    final connectionParts = connectionKey.split('|');
    if (connectionParts.isEmpty) return false;
    final activeProfile = connectionParts.first;
    for (final profile in const <String>['deployed', 'localDevelopment']) {
      final prefix = '$profile:';
      if (source.startsWith(prefix)) {
        if (profile != activeProfile) return false;
        source = source.substring(prefix.length);
        break;
      }
    }
    source = source.replaceFirst(RegExp(r'/$'), '');
    if (source.isEmpty) return false;
    for (final part in connectionParts.skip(1)) {
      final candidate = part.trim().replaceFirst(RegExp(r'/$'), '');
      if (candidate == source ||
          candidate.startsWith('$source/') ||
          source.startsWith('$candidate/')) {
        return true;
      }
    }
    return false;
  }

  static String? _decodeSelectedCode(
    String? raw, {
    required String expectedSystemCode,
  }) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final systemCode = decoded['systemCode']?.toString().trim().toLowerCase();
      if (systemCode != expectedSystemCode.trim().toLowerCase()) return null;
      final templateCode = decoded['templateCode']?.toString().trim();
      return templateCode == null || templateCode.isEmpty ? null : templateCode;
    } on FormatException {
      return null;
    }
  }

  static String? _decodeLegacySelectedId(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final templateId = decoded['templateId']?.toString().trim();
      return templateId == null || templateId.isEmpty ? null : templateId;
    } on FormatException {
      return null;
    }
  }

  static PresenterModePreference? _decodeMode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final modeName = decoded['mode']?.toString();
      return PresenterModePreference.values
          .where((value) => value.name == modeName)
          .firstOrNull;
    } on FormatException {
      return null;
    }
  }

  static ReportFlowPreferences? _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return ReportFlowPreferences.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  static Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _serial = _serial.catchError((Object _) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

class MemoryReportFlowPreferenceStore implements ReportFlowPreferenceStore {
  final Map<String, ReportFlowPreferences> _selected =
      <String, ReportFlowPreferences>{};
  final Map<String, PresenterModePreference> _modes =
      <String, PresenterModePreference>{};

  @override
  Future<ReportFlowPreferences?> load(ReportPreferenceScope scope) async {
    final selected = _selected[scope.selectedTemplateCanonical];
    final mode = _modes[scope.presenterModeCanonical];
    if (selected != null) {
      return selected.copyWith(mode: mode ?? selected.mode);
    }
    if (mode != null) {
      return ReportFlowPreferences(mode: mode);
    }
    return null;
  }

  @override
  Future<void> remove(ReportPreferenceScope scope) async {
    _selected.remove(scope.selectedTemplateCanonical);
    _modes.remove(scope.presenterModeCanonical);
  }

  @override
  Future<void> removeSelectedTemplate(ReportPreferenceScope scope) async {
    _selected.remove(scope.selectedTemplateCanonical);
  }

  @override
  Future<void> save(
    ReportPreferenceScope scope,
    ReportFlowPreferences preferences,
  ) async {
    final templateId = preferences.templateId?.trim();
    final templateCode = preferences.templateCode?.trim();
    if ((templateId != null && templateId.isNotEmpty) ||
        (templateCode != null && templateCode.isNotEmpty)) {
      _selected[scope.selectedTemplateCanonical] = preferences;
    } else {
      _selected.remove(scope.selectedTemplateCanonical);
    }
    _modes[scope.presenterModeCanonical] = preferences.mode;
  }
}

String _scopePart(Object? value) {
  final text = value?.toString().trim() ?? '';
  return Uri.encodeComponent(text.isEmpty ? '-' : text);
}

String? _optionalCode(Object? value) {
  final text = value?.toString().trim().toLowerCase();
  return text == null || text.isEmpty ? null : text;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
