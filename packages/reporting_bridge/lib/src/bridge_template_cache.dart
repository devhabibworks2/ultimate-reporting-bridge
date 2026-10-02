import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'bridge_contract.dart';
import 'bridge_runtime_error.dart';
import 'bridge_selected_template.dart';
import 'bridge_semantic_version.dart';
import 'bridge_template_default.dart';

class CachedTemplate {
  const CachedTemplate({
    required this.type,
    required this.document,
    this.systemId,
    this.systemCode,
    this.code,
    this.name,
    this.description,
    this.publishedVersionNo,
    this.metadata = const <String, dynamic>{},
    this.compatibility = const <String, dynamic>{},
    this.version,
    this.minPresenterVersion,
    this.minBridgeVersion,
    int? minPresenterDevVersion,
    int? maxPresenterDevVersion,
  }) : _legacyMinPresenterDevVersion = minPresenterDevVersion,
       _legacyMaxPresenterDevVersion = maxPresenterDevVersion;

  final String type;
  final Map<String, dynamic> document;
  final int? systemId;
  final String? systemCode;
  final String? code;
  final String? name;
  final String? description;
  final int? publishedVersionNo;
  final Map<String, dynamic> metadata;
  final Map<String, dynamic> compatibility;
  final String? version;
  final String? minPresenterVersion;
  final String? minBridgeVersion;
  final int? _legacyMinPresenterDevVersion;
  final int? _legacyMaxPresenterDevVersion;

  SelectedTemplate get selectedTemplate =>
      SelectedTemplate(type: type, code: templateCode, systemCode: systemCode);

  String get effectiveMinPresenterVersion {
    final canonical = minPresenterVersion?.trim();
    if (canonical != null && canonical.isNotEmpty) return canonical;
    final legacy = _legacyMinPresenterDevVersion;
    return legacy == null ? '0.0.0' : '$legacy.0.0';
  }

  @Deprecated('Use minPresenterVersion')
  int get minPresenterDevVersion {
    final legacy = _legacyMinPresenterDevVersion;
    if (legacy != null) return legacy;
    return BridgeSemanticVersion.tryParse(minPresenterVersion)?.major ?? 1;
  }

  @Deprecated('Use semantic version compatibility')
  int? get maxPresenterDevVersion => _legacyMaxPresenterDevVersion;

  String get templateName {
    final explicit = name?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;

    final meta = document['meta'];
    if (meta is Map) {
      final value = meta['name']?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return templateCode;
  }

  String? get durableTemplateCode {
    final explicit = code?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;

    final meta = document['meta'];
    if (meta is Map) {
      final value = meta['code']?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String get templateCode {
    final durable = durableTemplateCode;
    if (durable != null) return durable;
    throw const BridgeRuntimeException(
      BridgeRuntimeErrorCodes.templateDocumentInvalid,
      'Cached template requires a non-empty TemplateCode.',
    );
  }

  String get searchableMetadata {
    final values = <String>[templateCode, templateName, type];
    final explicitDescription = description?.trim();
    if (explicitDescription != null && explicitDescription.isNotEmpty) {
      values.add(explicitDescription);
    }
    final meta = document['meta'];
    if (meta is Map) {
      final description = meta['description']?.toString().trim();
      if (description != null && description.isNotEmpty) {
        values.add(description);
      }
      final tags = meta['tags'];
      if (tags is List) {
        values.addAll(
          tags
              .map((value) => value?.toString().trim())
              .whereType<String>()
              .where((value) => value.isNotEmpty),
        );
      }
    }
    return values.join(' ').toLowerCase();
  }

  bool isCompatibleWith({
    required String presenterVersion,
    String bridgeVersion = BridgeContract.implementationVersion,
  }) {
    final presenterCompatible = _meetsMinimumVersion(
      current: presenterVersion,
      minimum: effectiveMinPresenterVersion,
    );
    final bridgeCompatible = _meetsMinimumVersion(
      current: bridgeVersion,
      minimum: minBridgeVersion,
    );
    final currentDev = BridgeSemanticVersion.tryParse(presenterVersion)?.major;
    final belowLegacyMax =
        _legacyMaxPresenterDevVersion == null ||
        (currentDev != null && currentDev <= _legacyMaxPresenterDevVersion);
    return presenterCompatible && bridgeCompatible && belowLegacyMax;
  }

  @Deprecated('Use isCompatibleWith with semantic versions')
  bool isCompatibleWithPresenter(int presenterDevVersion) {
    return isCompatibleWith(presenterVersion: '$presenterDevVersion.0.0');
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': type,
      'document': document,
      if (systemId != null) 'systemId': systemId,
      if (systemCode != null) 'systemCode': systemCode,
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (publishedVersionNo != null) 'publishedVersionNo': publishedVersionNo,
      if (metadata.isNotEmpty) 'metadata': metadata,
      'compatibility': <String, dynamic>{
        ...compatibility,
        'type': type,
        if (version != null) 'version': version,
        if (effectiveMinPresenterVersion != '0.0.0')
          'minPresenterVersion': effectiveMinPresenterVersion,
        if (minBridgeVersion != null) 'minBridgeVersion': minBridgeVersion,
      },
    };
  }

  static CachedTemplate fromMap(
    Map<dynamic, dynamic> raw, {
    String? systemCode,
  }) {
    // Backend 'id' is intentionally parse-only/opaque. It is tolerated here
    // for wire compatibility but never retained as Bridge template identity.
    raw['id'];
    final type = raw['type'] ?? raw['reportType'];
    final document = raw['document'];
    if (type == null || document is! Map) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.templateDocumentInvalid,
        'Cached template requires type/reportType and document.',
      );
    }
    final code =
        _stringOrNull(raw['code']) ??
        (document['meta'] is Map
            ? _stringOrNull((document['meta'] as Map)['code'])
            : null);
    if (code == null) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.templateDocumentInvalid,
        'Cached template requires a non-empty TemplateCode.',
      );
    }

    final compatibility = raw['compatibility'];
    final compatibilityMap = compatibility is Map
        ? compatibility
        : const <String, dynamic>{};

    return CachedTemplate(
      type: type.toString(),
      document: _stringMap(document),
      systemId: _nullablePositiveInt(raw['systemId']),
      systemCode: systemCode ?? _stringOrNull(raw['systemCode']),
      code: code,
      name: _stringOrNull(raw['name']),
      description: _stringOrNull(raw['description']),
      publishedVersionNo: _nullablePositiveInt(raw['publishedVersionNo']),
      metadata: raw['metadata'] is Map
          ? _stringMap(raw['metadata'] as Map)
          : const <String, dynamic>{},
      compatibility: _stringMap(compatibilityMap),
      version: _stringOrNull(compatibilityMap['version']),
      minPresenterVersion: _stringOrNull(
        compatibilityMap['minPresenterVersion'],
      ),
      minBridgeVersion: _stringOrNull(compatibilityMap['minBridgeVersion']),
    );
  }
}

final class TemplateCatalogMetadata {
  TemplateCatalogMetadata({
    required this.catalogRevision,
    required this.systemCode,
    this.systemName,
    this.systemDescription,
    required this.filterFingerprint,
    required this.extraFingerprint,
    this.systemId,
    this.appliedFilter = const <String, dynamic>{},
    this.defaultTemplates = const <TemplateDefaultHint>[],
    DateTime? cachedAt,
  }) : cachedAt = (cachedAt ?? DateTime.now().toUtc()).toUtc();

  final String catalogRevision;
  final String? systemCode;
  final String? systemName;
  final String? systemDescription;
  final String? filterFingerprint;
  final String? extraFingerprint;
  final int? systemId;
  final Map<String, dynamic> appliedFilter;
  final List<TemplateDefaultHint> defaultTemplates;
  final DateTime cachedAt;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'catalogRevision': catalogRevision,
    if (systemCode != null) 'systemCode': systemCode,
    if (systemName != null) 'systemName': systemName,
    if (systemDescription != null) 'systemDescription': systemDescription,
    if (filterFingerprint != null) 'filterFingerprint': filterFingerprint,
    if (extraFingerprint != null) 'extraFingerprint': extraFingerprint,
    if (systemId != null) 'systemId': systemId,
    if (appliedFilter.isNotEmpty) 'appliedFilter': appliedFilter,
    'defaultTemplates': defaultTemplates
        .map((value) => value.toMap())
        .toList(growable: false),
    'cachedAt': cachedAt.toIso8601String(),
  };

  static TemplateCatalogMetadata? fromMap(Map<dynamic, dynamic> raw) {
    final revision = _stringOrNull(raw['catalogRevision']);
    final cachedAt = DateTime.tryParse(raw['cachedAt']?.toString() ?? '');
    if (revision == null || cachedAt == null) return null;

    final rawDefaults = raw['defaultTemplates'];
    final List<TemplateDefaultHint> defaults;
    if (rawDefaults == null) {
      defaults = const <TemplateDefaultHint>[];
    } else if (rawDefaults is! List) {
      return null;
    } else {
      final parsed = <TemplateDefaultHint>[];
      final reportTypes = <String>{};
      for (final item in rawDefaults) {
        if (item is! Map) return null;
        final hint = TemplateDefaultHint.tryFromMap(item);
        if (hint == null) return null;
        if (!reportTypes.add(hint.reportType)) return null;
        parsed.add(hint);
      }
      defaults = List<TemplateDefaultHint>.unmodifiable(parsed);
    }

    return TemplateCatalogMetadata(
      catalogRevision: revision,
      systemCode: _stringOrNull(raw['systemCode']),
      systemName: _stringOrNull(raw['systemName']),
      systemDescription: _stringOrNull(raw['systemDescription']),
      filterFingerprint: _stringOrNull(raw['filterFingerprint']),
      extraFingerprint: _stringOrNull(raw['extraFingerprint']),
      systemId: _nullablePositiveInt(raw['systemId']),
      appliedFilter: raw['appliedFilter'] is Map
          ? _stringMap(raw['appliedFilter'] as Map)
          : const <String, dynamic>{},
      defaultTemplates: defaults,
      cachedAt: cachedAt,
    );
  }
}

class TemplateCacheService {
  const TemplateCacheService({required this.cacheRoot});

  static const String _catalogMetadataFileName = '.catalog.json';
  static const String _selectionFileName = '.selection.json';

  final Directory cacheRoot;

  Future<bool> get hasCatalog async {
    return (await readCatalogMetadata()) != null;
  }

  Future<TemplateCatalogMetadata?> readCatalogMetadata() async {
    final file = File('${cacheRoot.path}/$_catalogMetadataFileName');
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return TemplateCatalogMetadata.fromMap(decoded);
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> writeCatalogMetadata(TemplateCatalogMetadata metadata) async {
    await cacheRoot.create(recursive: true);
    final file = File('${cacheRoot.path}/$_catalogMetadataFileName');
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsString(jsonEncode(metadata.toMap()), flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<SelectedTemplate?> readSelectedTemplate() async {
    final file = File('${cacheRoot.path}/$_selectionFileName');
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return SelectedTemplate.fromMap(decoded);
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> writeSelectedTemplate(SelectedTemplate selection) async {
    if (!selection.hasDurableIdentity) {
      await clearSelectedTemplate();
      return;
    }
    await cacheRoot.create(recursive: true);
    final file = File('${cacheRoot.path}/$_selectionFileName');
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsString(
        jsonEncode(selection.toStorageMap()),
        flush: true,
      );
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> clearSelectedTemplate() async {
    final file = File('${cacheRoot.path}/$_selectionFileName');
    if (await file.exists()) await file.delete();
  }

  Future<SelectedTemplate?> reconcileSelectedTemplate({
    required Iterable<CachedTemplate> catalog,
    required String systemCode,
    SelectedTemplate? stored,
  }) async {
    final selection = stored ?? await readSelectedTemplate();
    if (selection == null) return null;
    final normalizedSystemCode = systemCode.trim();
    final selectionSystemCode = selection.systemCode?.trim();
    if (selectionSystemCode != null &&
        selectionSystemCode.isNotEmpty &&
        selectionSystemCode != normalizedSystemCode) {
      await clearSelectedTemplate();
      return null;
    }
    for (final template in catalog) {
      if (template.templateCode == selection.code.trim()) {
        final reconciled = SelectedTemplate(
          type: template.type,
          code: template.templateCode,
          systemCode: normalizedSystemCode.isEmpty
              ? template.systemCode
              : normalizedSystemCode,
        );
        await writeSelectedTemplate(reconciled);
        return reconciled;
      }
    }
    await clearSelectedTemplate();
    return null;
  }

  Future<void> putTemplate(CachedTemplate template) async {
    final code = template.templateCode;
    await cacheRoot.create(recursive: true);
    final file = _templateFileByCode(code);
    final temporary = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');

    try {
      await temporary.writeAsString(jsonEncode(template.toMap()), flush: true);
      if (await backup.exists()) await backup.delete();
      if (await file.exists()) await file.rename(backup.path);
      try {
        await temporary.rename(file.path);
      } catch (_) {
        if (!await file.exists() && await backup.exists()) {
          await backup.rename(file.path);
        }
        rethrow;
      }
      if (await backup.exists()) await backup.delete();
    } finally {
      if (await temporary.exists()) await temporary.delete();
      if (await backup.exists() && await file.exists()) {
        await backup.delete();
      }
    }
  }

  Future<void> clearAll() async {
    if (!await cacheRoot.exists()) return;
    await cacheRoot.delete(recursive: true);
  }

  Future<List<CachedTemplate>> listTemplates({
    String? type,
    int? systemId,
  }) async {
    if (!await cacheRoot.exists()) return const <CachedTemplate>[];

    final templates = <String, CachedTemplate>{};
    await for (final entity in cacheRoot.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      if (entity.path.endsWith('/$_catalogMetadataFileName') ||
          entity.path.endsWith('\$_catalogMetadataFileName') ||
          entity.path.endsWith('/$_selectionFileName') ||
          entity.path.endsWith('\$_selectionFileName')) {
        continue;
      }
      final template = await _readTemplateFile(entity);
      if (template == null) continue;

      final matchesType = type == null || template.type == type;
      final matchesSystem = systemId == null || template.systemId == systemId;
      if (!matchesType || !matchesSystem) continue;

      final code = template.templateCode;
      final canonical = entity.path == _templateFileByCode(code).path;
      if (canonical || !templates.containsKey(code)) {
        templates[code] = template;
      }
    }

    final result = templates.values.toList(growable: false)
      ..sort((a, b) => a.templateCode.compareTo(b.templateCode));
    return result;
  }

  Future<CachedTemplate?> getTemplateByCode(String templateCode) async {
    final code = templateCode.trim();
    if (code.isEmpty) return null;
    final file = _templateFileByCode(code);
    if (!await file.exists()) return null;
    final template = await _readTemplateFile(file);
    if (template == null || template.templateCode != code) return null;
    return template;
  }

  Future<CachedTemplate?> _readTemplateFile(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return CachedTemplate.fromMap(decoded);
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    } on BridgeRuntimeException {
      return null;
    }
  }

  File _templateFileByCode(String templateCode) {
    final digest = sha256.convert(utf8.encode(templateCode)).toString();
    return File('${cacheRoot.path}/tpl_$digest.json');
  }
}

class TemplateSelectionResult {
  const TemplateSelectionResult({
    required this.status,
    this.template,
    this.errorCode,
  });

  final String status;
  final CachedTemplate? template;
  final String? errorCode;

  bool get isReady => template != null;
}

class TemplateSelectionResolver {
  const TemplateSelectionResolver({required this.cache});

  final TemplateCacheService cache;

  Future<TemplateSelectionResult> resolveSelectedTemplate({
    required String reportType,
    required String systemCode,
    String? presenterVersion,
    int? presenterDevVersion,
    String bridgeVersion = BridgeContract.implementationVersion,
    SelectedTemplate? storedSelection,
  }) async {
    final effectivePresenterVersion =
        presenterVersion ?? '${presenterDevVersion ?? 1}.0.0';
    final metadata = await cache.readCatalogMetadata();
    final catalogMatchesSystem = metadata?.systemCode == systemCode;
    final templates = catalogMatchesSystem
        ? await cache.listTemplates(
            type: reportType,
            systemId: metadata?.systemId,
          )
        : const <CachedTemplate>[];
    final compatible = templates
        .where(
          (template) => template.isCompatibleWith(
            presenterVersion: effectivePresenterVersion,
            bridgeVersion: bridgeVersion,
          ),
        )
        .toList(growable: false);
    if (templates.isEmpty) {
      return const TemplateSelectionResult(
        status: 'no-template',
        errorCode: BridgeRuntimeErrorCodes.noTemplateAvailable,
      );
    }
    if (compatible.isEmpty) {
      return const TemplateSelectionResult(
        status: 'incompatible',
        errorCode: BridgeRuntimeErrorCodes.presenterVersionTooOld,
      );
    }
    if (storedSelection != null) {
      if (storedSelection.matchesType(reportType) &&
          storedSelection.systemCode == systemCode) {
        final storedCode = storedSelection.code.trim();
        if (storedCode.isNotEmpty) {
          for (final template in compatible) {
            if (template.templateCode == storedCode) {
              return TemplateSelectionResult(
                status: 'stored-selected',
                template: template,
              );
            }
          }
        }
      }
      return const TemplateSelectionResult(
        status: 'selection-required',
        errorCode: BridgeRuntimeErrorCodes.staleTemplateSelection,
      );
    }
    if (compatible.length == 1) {
      return TemplateSelectionResult(
        status: 'auto-selected',
        template: compatible.single,
      );
    }
    return const TemplateSelectionResult(status: 'selection-required');
  }
}

bool _meetsMinimumVersion({required String current, required String? minimum}) {
  if (minimum == null || minimum.trim().isEmpty) return true;
  final currentVersion = BridgeSemanticVersion.tryParse(current);
  final minimumVersion = BridgeSemanticVersion.tryParse(minimum);
  if (currentVersion == null || minimumVersion == null) return false;
  return currentVersion.compareTo(minimumVersion) >= 0;
}

Map<String, dynamic> _stringMap(Map<dynamic, dynamic> raw) {
  return <String, dynamic>{
    for (final entry in raw.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

String? _stringOrNull(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? _nullablePositiveInt(Object? value) {
  final parsed = int.tryParse(value?.toString() ?? '');
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}
