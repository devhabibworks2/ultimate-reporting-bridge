import 'dart:io';

import 'bridge_cache_namespace.dart';
import 'bridge_identity_context.dart';
import 'bridge_runtime_error.dart';
import 'bridge_template_cache.dart';
import 'bridge_template_default.dart';
import 'bridge_template_query.dart';
import 'bridge_template_sync.dart';

/// Owns Presenter template transport for one API source.
class PresenterServerGateway {
  PresenterServerGateway({
    required Uri apiBaseUrl,
    Uri? cacheIdentityBaseUrl,
    required this.bridgeRoot,
    Map<String, String> headers = const <String, String>{},
    HttpClient Function()? httpClientFactory,
    Duration timeout = const Duration(seconds: 8),
    bool closeClientAfterRequest = true,
  }) : apiBaseUrl = normalizeBridgeApiBaseUrl(apiBaseUrl),
       cacheIdentityBaseUrl = normalizeBridgeApiBaseUrl(
         cacheIdentityBaseUrl ?? apiBaseUrl,
       ),
       _headers = filterPresenterBridgeHeaders(headers),
       _httpClientFactory = httpClientFactory,
       _timeout = timeout,
       _closeClientAfterRequest = closeClientAfterRequest,
       _templateSync = PresenterTemplateSyncService(
         httpClientFactory: httpClientFactory,
         timeout: timeout,
         closeClientAfterRequest: closeClientAfterRequest,
       );

  final Uri apiBaseUrl;
  final Uri cacheIdentityBaseUrl;
  final Directory bridgeRoot;
  final Map<String, String> _headers;
  final HttpClient Function()? _httpClientFactory;
  final Duration _timeout;
  final bool _closeClientAfterRequest;
  final PresenterTemplateSyncService _templateSync;

  PresenterServerGateway copyWithApiBaseUrl(Uri value) =>
      PresenterServerGateway(
        apiBaseUrl: value,
        cacheIdentityBaseUrl: value,
        bridgeRoot: bridgeRoot,
        headers: _headers,
        httpClientFactory: _httpClientFactory,
        timeout: _timeout,
        closeClientAfterRequest: _closeClientAfterRequest,
      );

  Future<TemplateSyncSummary> syncTemplates({
    required TemplateQueryRequest query,
    Map<String, String>? headers,
  }) async {
    final effectiveHeaders = filterPresenterBridgeHeaders(headers ?? _headers);
    final cache = await _queryTemplateCache(query, effectiveHeaders);
    return _templateSync.queryTemplatesToCache(
      apiBase: apiBaseUrl,
      headers: effectiveHeaders,
      cache: cache,
      request: query,
    );
  }

  Future<List<CachedTemplate>> listTemplates({
    required TemplateQueryRequest query,
    Map<String, String>? headers,
  }) async {
    final effectiveHeaders = filterPresenterBridgeHeaders(headers ?? _headers);
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

  Future<List<TemplateDefaultHint>> listTemplateDefaults({
    required TemplateQueryRequest query,
    Map<String, String>? headers,
  }) async {
    final effectiveHeaders = filterPresenterBridgeHeaders(headers ?? _headers);
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
    return metadata.defaultTemplates;
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
}
