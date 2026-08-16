import 'dart:convert';
import 'dart:io';

import 'bridge_contract.dart';
import 'bridge_runtime_error.dart';
import 'bridge_selected_template.dart';
import 'bridge_semantic_version.dart';

class CachedTemplate {
  const CachedTemplate({
    required this.id,
    required this.type,
    required this.document,
    this.systemId,
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

  final String id;
  final String type;
  final Map<String, dynamic> document;
  final int? systemId;
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

  SelectedTemplate get selectedTemplate => SelectedTemplate(id: id, type: type);

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
    return id;
  }

  String get templateCode {
    final explicit = code?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;

    final meta = document['meta'];
    if (meta is Map) {
      final value = (meta['code'] ?? meta['id'])?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return id;
  }

  String get searchableMetadata {
    final values = <String>[id, templateCode, templateName, type];
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
      'id': id,
      'type': type,
      'document': document,
      if (systemId != null) 'systemId': systemId,
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

  static CachedTemplate fromMap(Map<dynamic, dynamic> raw) {
    final id = raw['id'];
    final type = raw['type'] ?? raw['reportType'];
    final document = raw['document'];
    if (id == null || type == null || document is! Map) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.templateDocumentInvalid,
        'Cached template requires id, type/reportType, and document.',
      );
    }

    final compatibility = raw['compatibility'];
    final compatibilityMap = compatibility is Map
        ? compatibility
        : const <String, dynamic>{};

    return CachedTemplate(
      id: id.toString(),
      type: type.toString(),
      document: _stringMap(document),
      systemId: _nullablePositiveInt(raw['systemId']),
      code: _stringOrNull(raw['code']),
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
    'cachedAt': cachedAt.toIso8601String(),
  };

  static TemplateCatalogMetadata? fromMap(Map<dynamic, dynamic> raw) {
    final revision = _stringOrNull(raw['catalogRevision']);
    final cachedAt = DateTime.tryParse(raw['cachedAt']?.toString() ?? '');
    if (revision == null || cachedAt == null) return null;
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
      cachedAt: cachedAt,
    );
  }
}

class TemplateCacheService {
  const TemplateCacheService({required this.cacheRoot});

  static const String _catalogMetadataFileName = '.catalog.json';

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

  Future<void> putTemplate(CachedTemplate template) async {
    await cacheRoot.create(recursive: true);
    final file = _templateFile(template.id);
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

    final legacy = _legacyTemplateFile(template.id);
    if (legacy.path != file.path && await legacy.exists()) {
      await legacy.delete();
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
          entity.path.endsWith('\\$_catalogMetadataFileName')) {
        continue;
      }
      final template = await _readTemplateFile(entity);
      if (template == null) continue;

      final matchesType = type == null || template.type == type;
      final matchesSystem = systemId == null || template.systemId == systemId;
      if (!matchesType || !matchesSystem) continue;

      final canonical = entity.path == _templateFile(template.id).path;
      if (canonical || !templates.containsKey(template.id)) {
        templates[template.id] = template;
      }
    }

    final result = templates.values.toList(growable: false)
      ..sort((a, b) => a.id.compareTo(b.id));
    return result;
  }

  Future<CachedTemplate?> getTemplate(String id) async {
    final file = _templateFile(id);
    if (await file.exists()) {
      final template = await _readTemplateFile(file);
      if (template != null) return template;
    }

    final legacy = _legacyTemplateFile(id);
    if (!await legacy.exists()) return null;
    return _readTemplateFile(legacy);
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

  File _templateFile(String id) {
    final encoded = base64Url.encode(utf8.encode(id)).replaceAll('=', '');
    return File('${cacheRoot.path}/tpl_$encoded.json');
  }

  File _legacyTemplateFile(String id) {
    final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return File('${cacheRoot.path}/$safeId.json');
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
    String? presenterVersion,
    int? presenterDevVersion,
    String bridgeVersion = BridgeContract.implementationVersion,
    SelectedTemplate? storedSelection,
  }) async {
    final effectivePresenterVersion =
        presenterVersion ?? '${presenterDevVersion ?? 1}.0.0';
    final templates = await cache.listTemplates(type: reportType);
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
    if (storedSelection != null && storedSelection.matchesType(reportType)) {
      for (final template in compatible) {
        if (template.id == storedSelection.id) {
          return TemplateSelectionResult(
            status: 'stored-selected',
            template: template,
          );
        }
      }
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
