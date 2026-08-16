import 'dart:convert';
import 'dart:io';

import 'bridge_identity_context.dart';
import 'bridge_template_cache.dart';
import 'bridge_template_query.dart';

Uri normalizeBridgeApiBaseUrl(Uri value) {
  final path = value.path.isEmpty
      ? '/'
      : value.path.endsWith('/')
      ? value.path
      : '${value.path}/';
  return value.replace(
    scheme: value.scheme.toLowerCase(),
    host: value.host.toLowerCase(),
    path: path,
    fragment: '',
  );
}

/// Resolve a logical API route against either the canonical API base
/// (`.../api/`) or a historical backend/root base used by older callers.
Uri resolveBridgeApiRoute(Uri apiBaseUrl, String relativePath) {
  final base = normalizeBridgeApiBaseUrl(apiBaseUrl);
  var route = relativePath.trim();
  while (route.startsWith('/')) {
    route = route.substring(1);
  }
  if (route.isEmpty) return base;
  return base.path.endsWith('/api/')
      ? base.resolve(route)
      : base.resolve('api/$route');
}

bool sameBridgeApiBaseUrl(String? raw, Uri value) {
  final parsed = Uri.tryParse(raw?.trim() ?? '');
  if (parsed == null) return false;
  final left = normalizeBridgeApiBaseUrl(parsed);
  final right = normalizeBridgeApiBaseUrl(value);
  if (left == right) return true;
  const compatiblePaths = <String>{
    '/',
    '/UltimateReport/backend/',
    '/UltimateReport/backend/api/',
  };
  return left.scheme == right.scheme &&
      left.host == right.host &&
      left.port == right.port &&
      left.query == right.query &&
      compatiblePaths.contains(left.path) &&
      compatiblePaths.contains(right.path);
}

String bridgeTemplateCacheNamespace(Uri apiBaseUrl) {
  final bytes = utf8.encode(normalizeBridgeApiBaseUrl(apiBaseUrl).toString());

  // Preserve the existing FNV-1a 64-bit namespace while avoiding integer
  // literals and intermediate values that dart2js cannot represent exactly.
  var high = 0xcbf29ce4;
  var low = 0x84222325;
  for (final byte in bytes) {
    low = (low ^ byte).toUnsigned(32);
    final lowProduct = low * 0x1b3;
    final carry = lowProduct ~/ 0x100000000;
    final shiftedLow = (low * 0x100).toUnsigned(32);
    low = lowProduct.toUnsigned(32);
    high = (high * 0x1b3 + carry + shiftedLow).toUnsigned(32);
  }

  final highHex = high.toRadixString(16).padLeft(8, '0');
  final lowHex = low.toRadixString(16).padLeft(8, '0');
  return '$highHex$lowHex';
}

String? bridgeTenantIdFromHeaders(Map<String, String> headers) {
  return _headerValue(headers, 'X-Tenant-Id');
}

String? bridgeHeaderValue(Map<String, String> headers, String approvedName) {
  return _headerValue(headers, approvedName);
}

final class BridgeTemplateCacheScope {
  BridgeTemplateCacheScope({
    required Uri apiBaseUrl,
    required String systemCode,
    required TemplateSyncFilter filter,
    required Map<String, Object?> extra,
    BridgeIdentityContext? identity,
    String? tenantId,
  }) : apiBaseUrl = normalizeBridgeApiBaseUrl(apiBaseUrl),
       systemCode = _requiredCanonicalSystemCode(systemCode),
       identity = identity ?? BridgeIdentityContext(),
       tenantId = _trimmedOrNull(tenantId),
       filterFingerprint = filter.fingerprint,
       extraFingerprint = canonicalJsonFingerprint(extra);

  final Uri apiBaseUrl;
  final String? tenantId;
  final BridgeIdentityContext identity;
  final String systemCode;
  final String filterFingerprint;
  final String extraFingerprint;

  Map<String, Object?> toCanonicalJson() => <String, Object?>{
    'tenantId': tenantId ?? '',
    'branchId': identity.branchId ?? '',
    'userId': identity.userId ?? '',
    'systemUnit': identity.systemUnit ?? '',
    'systemCode': systemCode,
    'filterFingerprint': filterFingerprint,
    'extraFingerprint': extraFingerprint,
  };

  String get namespace => canonicalJsonFingerprint(toCanonicalJson());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BridgeTemplateCacheScope &&
          other.apiBaseUrl == apiBaseUrl &&
          other.namespace == namespace;

  @override
  int get hashCode => Object.hash(apiBaseUrl, namespace);
}

Directory bridgeTemplateCacheDirectoryForApi({
  required Directory bridgeRoot,
  required Uri apiBaseUrl,
}) {
  // Deprecated base-URL-only location retained for migration compatibility.
  return Directory(
    '${bridgeRoot.path}/templates/${bridgeTemplateCacheNamespace(apiBaseUrl)}',
  );
}

Directory bridgeTemplateScopedApiDirectory({
  required Directory bridgeRoot,
  required Uri apiBaseUrl,
}) {
  return Directory(
    '${bridgeRoot.path}/templates/scoped/'
    '${bridgeTemplateCacheNamespace(apiBaseUrl)}',
  );
}

Directory bridgeTemplateCacheDirectoryForScope({
  required Directory bridgeRoot,
  required BridgeTemplateCacheScope scope,
}) {
  return Directory(
    '${bridgeTemplateScopedApiDirectory(bridgeRoot: bridgeRoot, apiBaseUrl: scope.apiBaseUrl).path}/'
    'catalog_${scope.namespace}',
  );
}

Directory bridgeAnonymousLegacyTemplateCacheDirectoryForApi({
  required Directory bridgeRoot,
  required Uri apiBaseUrl,
}) {
  return Directory(
    '${bridgeTemplateScopedApiDirectory(bridgeRoot: bridgeRoot, apiBaseUrl: apiBaseUrl).path}/'
    'anonymous_legacy',
  );
}

Future<void> migrateLegacyBridgeTemplateCacheForApi({
  required Directory bridgeRoot,
  required Uri apiBaseUrl,
}) async {
  final targetRoot = bridgeAnonymousLegacyTemplateCacheDirectoryForApi(
    bridgeRoot: bridgeRoot,
    apiBaseUrl: apiBaseUrl,
  );
  final targetCache = TemplateCacheService(cacheRoot: targetRoot);
  if (await targetCache.hasCatalog ||
      (await targetCache.listTemplates()).isNotEmpty) {
    return;
  }

  final migrated = <String, CachedTemplate>{};
  final oldApiRoot = bridgeTemplateCacheDirectoryForApi(
    bridgeRoot: bridgeRoot,
    apiBaseUrl: apiBaseUrl,
  );
  final oldApiCache = TemplateCacheService(cacheRoot: oldApiRoot);
  for (final template in await oldApiCache.listTemplates()) {
    migrated[template.id] = template;
  }

  final oldestRoot = Directory('${bridgeRoot.path}/templates');
  final source = File('${oldestRoot.path}/.api-source');
  var oldestSourceMatches = false;
  if (await source.exists()) {
    try {
      oldestSourceMatches = sameBridgeApiBaseUrl(
        await source.readAsString(),
        apiBaseUrl,
      );
    } on FileSystemException {
      oldestSourceMatches = false;
    }
  }
  if (oldestSourceMatches) {
    final oldestCache = TemplateCacheService(cacheRoot: oldestRoot);
    for (final template in await oldestCache.listTemplates()) {
      migrated.putIfAbsent(template.id, () => template);
    }
  }

  if (migrated.isEmpty) return;

  final token = DateTime.now().microsecondsSinceEpoch;
  final staging = Directory('${targetRoot.path}.migrate-$token');
  if (await staging.exists()) await staging.delete(recursive: true);

  try {
    final stagedCache = TemplateCacheService(cacheRoot: staging);
    for (final template in migrated.values) {
      await stagedCache.putTemplate(template);
    }
    await stagedCache.writeCatalogMetadata(
      TemplateCatalogMetadata(
        catalogRevision: 'legacy-migration',
        systemCode: null,
        filterFingerprint: null,
        extraFingerprint: null,
      ),
    );
    await targetRoot.parent.create(recursive: true);
    if (await targetRoot.exists()) {
      await targetRoot.delete(recursive: true);
    }
    await staging.rename(targetRoot.path);

    if (await oldApiRoot.exists()) {
      await oldApiRoot.delete(recursive: true);
    }
    if (oldestSourceMatches) {
      await for (final entity in oldestRoot.list(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.json')) {
          await entity.delete();
        }
      }
      if (await source.exists()) await source.delete();
    }
  } finally {
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}

Future<void> clearBridgeTemplateCachesForApi({
  required Directory bridgeRoot,
  required Uri apiBaseUrl,
}) async {
  final scopedRoot = bridgeTemplateScopedApiDirectory(
    bridgeRoot: bridgeRoot,
    apiBaseUrl: apiBaseUrl,
  );
  if (await scopedRoot.exists()) {
    await scopedRoot.delete(recursive: true);
  }

  final oldApiRoot = bridgeTemplateCacheDirectoryForApi(
    bridgeRoot: bridgeRoot,
    apiBaseUrl: apiBaseUrl,
  );
  if (await oldApiRoot.exists()) {
    await oldApiRoot.delete(recursive: true);
  }

  final oldestRoot = Directory('${bridgeRoot.path}/templates');
  final source = File('${oldestRoot.path}/.api-source');
  if (!await source.exists()) return;
  try {
    if (!sameBridgeApiBaseUrl(await source.readAsString(), apiBaseUrl)) return;
  } on FileSystemException {
    return;
  }
  await for (final entity in oldestRoot.list(followLinks: false)) {
    if (entity is File && entity.path.endsWith('.json')) {
      await entity.delete();
    }
  }
  if (await source.exists()) await source.delete();
}

String? _headerValue(Map<String, String> headers, String expectedName) {
  final expected = expectedName.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() != expected) continue;
    return _trimmedOrNull(entry.value);
  }
  return null;
}

String _requiredCanonicalSystemCode(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty) {
    throw ArgumentError.value(raw, 'systemCode', 'Must not be empty.');
  }
  return value;
}

String? _trimmedOrNull(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
