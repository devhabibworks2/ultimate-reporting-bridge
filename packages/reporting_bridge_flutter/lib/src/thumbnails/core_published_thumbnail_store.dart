import 'dart:io';
import 'dart:typed_data';

import 'package:reporting_bridge/reporting_bridge.dart';

import 'native_published_thumbnail_store.dart';

/// Flutter adapter for the one core-owned, catalog-scoped plain PNG cache.
/// The catalog path is computed identically to the core Bridge query path.
final class CorePublishedThumbnailStore
    implements PublishedThumbnailImageStore {
  CorePublishedThumbnailStore({
    required this.bridgeRoot,
    required this.cacheIdentityBaseUrl,
    required this.filter,
    required this.extra,
    this.branchId,
    this.systemUnit,
  });

  final Directory bridgeRoot;
  final Uri cacheIdentityBaseUrl;
  final TemplateSyncFilter filter;
  final Map<String, Object?> extra;
  final String? branchId;
  final String? systemUnit;

  BridgeTemplateThumbnailStore _storage(TrustedThumbnailScope scope) {
    final catalogScope = BridgeTemplateCacheScope(
      apiBaseUrl: cacheIdentityBaseUrl,
      authContextDigest: scope.customerContext,
      tenantId: scope.tenantId,
      systemCode: scope.systemCode,
      identity: BridgeIdentityContext(
        userId: scope.userId,
        branchId: branchId,
        systemUnit: systemUnit,
      ),
      filter: filter,
      extra: extra,
    );
    return BridgeTemplateThumbnailStore(
      cacheRoot: bridgeTemplateCacheDirectoryForScope(
        bridgeRoot: bridgeRoot,
        scope: catalogScope,
      ),
      globalRoot: Directory('${bridgeRoot.path}/templates/scoped'),
    );
  }

  CachedTemplate _reference(
    TrustedThumbnailScope scope,
    BridgePublishedThumbnail ref,
  ) => CachedTemplate(
    type: 'published-thumbnail',
    code: scope.templateCode,
    systemCode: scope.systemCode,
    publishedVersionNo: ref.versionNo,
    publishedThumbnail: ref,
    document: const <String, dynamic>{},
  );

  @override
  Future<Uint8List?> read(
    TrustedThumbnailScope scope,
    BridgePublishedThumbnail ref,
  ) async {
    if (!scope.cacheEnabled || !ref.available) return null;
    // The canonical store never reads encrypted .bin cache entries.
    // Historical files are left untouched and may be ignored safely.
    return _storage(scope).read(_reference(scope, ref));
  }

  @override
  Future<void> write(
    TrustedThumbnailScope scope,
    BridgePublishedThumbnail ref,
    Uint8List png,
  ) async {
    if (!scope.cacheEnabled || !ref.available) return;
    await _storage(scope).write(_reference(scope, ref), png);
  }

  /// Exact file identities are versioned; replaced catalog directories drop
  /// obsolete PNGs. Never delete a whole shared catalog for one card.
  @override
  Future<void> invalidateScope(TrustedThumbnailScope scope) async {
    if (!scope.cacheEnabled) return;
    await _storage(scope).deleteTemplateImages(scope.templateCode);
  }
}
