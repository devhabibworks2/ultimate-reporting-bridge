import 'dart:io';

import 'bridge_cache_namespace.dart';
import 'bridge_http_fetch.dart';
import 'bridge_identity_context.dart';
import 'bridge_runtime_error.dart';
import 'bridge_template_cache.dart';
import 'bridge_template_query.dart';
import 'bridge_template_sync.dart';

class PresenterSystem {
  const PresenterSystem({
    required this.id,
    required this.code,
    required this.name,
    this.description,
  });

  final int id;
  final String code;
  final String name;
  final String? description;

  factory PresenterSystem.fromMap(Map<dynamic, dynamic> raw) {
    final id = int.tryParse(raw['id']?.toString() ?? '');
    final code = raw['code']?.toString().trim() ?? '';
    final name = raw['name']?.toString().trim() ?? '';
    final description = raw['description']?.toString().trim();
    if (id == null || id <= 0 || code.isEmpty || name.isEmpty) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'System requires a positive id, non-empty code, and non-empty name.',
      );
    }
    return PresenterSystem(
      id: id,
      code: code,
      name: name,
      description: description == null || description.isEmpty
          ? null
          : description,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id,
    'code': code,
    'name': name,
    if (description != null) 'description': description,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PresenterSystem &&
          other.id == id &&
          other.code == code &&
          other.name == name &&
          other.description == description;

  @override
  int get hashCode => Object.hash(id, code, name, description);
}

/// Owns Presenter systems and template transport for one API source.
class PresenterServerGateway {
  PresenterServerGateway({
    required Uri apiBaseUrl,
    Uri? cacheIdentityBaseUrl,
    required this.bridgeRoot,
    Map<String, String> headers = const <String, String>{},
    HttpClient Function()? httpClientFactory,
    Duration timeout = const Duration(seconds: 8),
  }) : apiBaseUrl = normalizeBridgeApiBaseUrl(apiBaseUrl),
       cacheIdentityBaseUrl = normalizeBridgeApiBaseUrl(
         cacheIdentityBaseUrl ?? apiBaseUrl,
       ),
       _headers = filterPresenterBridgeHeaders(headers),
       _httpClientFactory = httpClientFactory,
       _timeout = timeout,
       _http = BridgeHttpFetch(
         httpClientFactory: httpClientFactory,
         timeout: timeout,
       ),
       _templateSync = PresenterTemplateSyncService(
         httpClientFactory: httpClientFactory,
         timeout: timeout,
       );

  static const String _systemsPath = 'presenter/systems';

  final Uri apiBaseUrl;
  final Uri cacheIdentityBaseUrl;
  final Directory bridgeRoot;
  final Map<String, String> _headers;
  final HttpClient Function()? _httpClientFactory;
  final Duration _timeout;
  final BridgeHttpFetch _http;
  final PresenterTemplateSyncService _templateSync;

  PresenterServerGateway copyWithApiBaseUrl(Uri value) =>
      PresenterServerGateway(
        apiBaseUrl: value,
        cacheIdentityBaseUrl: value,
        bridgeRoot: bridgeRoot,
        headers: _headers,
        httpClientFactory: _httpClientFactory,
        timeout: _timeout,
      );

  Future<List<PresenterSystem>> fetchSystems({
    Map<String, String>? headers,
  }) async {
    final uri = resolveBridgeApiRoute(apiBaseUrl, _systemsPath);
    final payload = await _http.getJsonObject(
      uri,
      headers: filterPresenterBridgeHeaders(headers ?? _headers),
      notValidJsonMessage: 'Response from $uri is not valid JSON.',
    );
    if (payload['success'] != true) {
      throw BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Presenter systems response not successful: $uri',
      );
    }

    final data = unwrapBridgeEnvelopeData(payload);
    final rawItems = data['items'];
    if (rawItems is! List) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Presenter systems response missing data.items array.',
      );
    }

    final systems = <PresenterSystem>[];
    final ids = <int>{};
    for (final raw in rawItems) {
      if (raw is! Map) {
        throw const BridgeRuntimeException(
          BridgeRuntimeErrorCodes.runtimeSessionInvalid,
          'Presenter systems list contains a non-object item.',
        );
      }
      final system = PresenterSystem.fromMap(raw);
      if (!ids.add(system.id)) {
        throw BridgeRuntimeException(
          BridgeRuntimeErrorCodes.runtimeSessionInvalid,
          'Presenter systems list contains duplicate id ${system.id}.',
        );
      }
      systems.add(system);
    }
    systems.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
    return List<PresenterSystem>.unmodifiable(systems);
  }

  Future<TemplateSyncSummary> syncTemplates({
    TemplateQueryRequest? query,
    @Deprecated('Use query with systemCode.') int? systemId,
    Map<String, String>? headers,
  }) async {
    if (query != null && systemId != null) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Template synchronization cannot combine systemCode and systemId.',
      );
    }
    final effectiveHeaders = filterPresenterBridgeHeaders(headers ?? _headers);
    if (query != null) {
      final cache = await _queryTemplateCache(query, effectiveHeaders);
      return _templateSync.queryTemplatesToCache(
        apiBase: apiBaseUrl,
        headers: effectiveHeaders,
        cache: cache,
        request: query,
      );
    }

    final cache = await _legacyTemplateCache();
    return _templateSync.syncTemplatesToCache(
      apiBase: apiBaseUrl,
      headers: effectiveHeaders,
      cache: cache,
      systemId: systemId,
    );
  }

  Future<List<CachedTemplate>> listTemplates({
    TemplateQueryRequest? query,
    @Deprecated('Use query with systemCode.') int? systemId,
    Map<String, String>? headers,
  }) async {
    if (query != null && systemId != null) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Template listing cannot combine systemCode and systemId.',
      );
    }
    if (query != null) {
      final effectiveHeaders = filterPresenterBridgeHeaders(
        headers ?? _headers,
      );
      final cache = await _queryTemplateCache(query, effectiveHeaders);
      final metadata = await cache.readCatalogMetadata();
      final validCatalog =
          metadata != null &&
          metadata.systemCode == query.systemCode &&
          metadata.filterFingerprint == query.filterFingerprint &&
          metadata.extraFingerprint == query.extraFingerprint;
      if (!validCatalog) {
        throw const BridgeRuntimeException(
          BridgeTemplateSyncErrorCodes.offlineCacheUnavailable,
          'No cached template catalog is available for the current scope.',
        );
      }
      return cache.listTemplates();
    }

    final cache = await _legacyTemplateCache();
    return cache.listTemplates(systemId: systemId);
  }

  Future<void> clearTemplates() async {
    await bridgeRoot.create(recursive: true);
    await clearBridgeTemplateCachesForApi(
      bridgeRoot: bridgeRoot,
      apiBaseUrl: cacheIdentityBaseUrl,
    );
  }

  Future<TemplateCacheService> _queryTemplateCache(
    TemplateQueryRequest query,
    Map<String, String> headers,
  ) async {
    await bridgeRoot.create(recursive: true);
    final scope = BridgeTemplateCacheScope(
      apiBaseUrl: cacheIdentityBaseUrl,
      tenantId: bridgeTenantIdFromHeaders(headers),
      identity: _validatedEffectiveIdentity(query.identity, headers),
      systemCode: query.systemCode,
      filter: query.filter,
      extra: query.extra,
    );
    return TemplateCacheService(
      cacheRoot: bridgeTemplateCacheDirectoryForScope(
        bridgeRoot: bridgeRoot,
        scope: scope,
      ),
    );
  }

  BridgeIdentityContext _validatedEffectiveIdentity(
    BridgeIdentityContext identity,
    Map<String, String> headers,
  ) {
    final headerBranch = bridgeHeaderValue(headers, 'X-Branch-Id');
    if (headerBranch != null &&
        identity.branchId != null &&
        headerBranch != identity.branchId) {
      throw const BridgeRuntimeException(
        BridgeTemplateSyncErrorCodes.identityContextConflict,
        'Bridge identity branchId conflicts with X-Branch-Id.',
      );
    }

    final headerUser = bridgeHeaderValue(headers, 'X-User-Context');
    if (headerUser != null &&
        identity.userId != null &&
        headerUser != identity.userId) {
      throw const BridgeRuntimeException(
        BridgeTemplateSyncErrorCodes.identityContextConflict,
        'Bridge identity userId conflicts with X-User-Context.',
      );
    }

    return BridgeIdentityContext(
      branchId: identity.branchId ?? headerBranch,
      userId: identity.userId ?? headerUser,
      systemUnit: identity.systemUnit,
    );
  }

  Future<TemplateCacheService> _legacyTemplateCache() async {
    await bridgeRoot.create(recursive: true);
    await migrateLegacyBridgeTemplateCacheForApi(
      bridgeRoot: bridgeRoot,
      apiBaseUrl: cacheIdentityBaseUrl,
    );
    return TemplateCacheService(
      cacheRoot: bridgeAnonymousLegacyTemplateCacheDirectoryForApi(
        bridgeRoot: bridgeRoot,
        apiBaseUrl: cacheIdentityBaseUrl,
      ),
    );
  }
}
