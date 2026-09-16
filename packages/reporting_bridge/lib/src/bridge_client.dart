import 'dart:io';

import 'bridge_cache_namespace.dart';
import 'bridge_headers.dart';
import 'bridge_http_fetch.dart';
import 'bridge_identity_context.dart';
import 'bridge_presenter_cache.dart';
import 'bridge_presenter_server.dart';
import 'bridge_presenter_session.dart';
import 'bridge_runtime_error.dart';
import 'bridge_runtime_storage.dart';
import 'bridge_template_cache.dart';
import 'bridge_template_query.dart';
import 'bridge_template_sync.dart';

class ReportingBridgeStatus {
  const ReportingBridgeStatus({
    required this.apiBaseUrl,
    required this.presenterCached,
    required this.templateCount,
    this.presenterManifest,
  });

  final String apiBaseUrl;
  final bool presenterCached;
  final int templateCount;
  final PresenterCacheManifest? presenterManifest;
}

/// High-level Bridge client for one Report Server and one local cache root.
///
/// It owns endpoint probing, systems/templates transport, Presenter downloads,
/// cache namespaces, runtime-session coordination, and lifecycle cleanup. Host
/// applications provide selected domain values and map the returned Bridge
/// models to their UI models.
class ReportingBridgeClient {
  ReportingBridgeClient({
    required Uri apiBaseUrl,
    Uri? cacheIdentityBaseUrl,
    required this.presenterEntryUrl,
    required this.bridgeRoot,
    this.bundleManifestUrl,
    Map<String, String> headers = const <String, String>{},
    BridgeHeadersProvider? headersProvider,
    BridgeIdentityContext? identityContext,
    HttpClient Function()? httpClientFactory,
    Duration timeout = const Duration(seconds: 8),
  }) : apiBaseUrl = _withTrailingSlash(apiBaseUrl),
       _staticHeaders = filterPresenterBridgeHeaders(headers),
       _headersProvider = headersProvider,
       _identityContext = identityContext ?? BridgeIdentityContext() {
    final sharedHttpClient = (httpClientFactory ?? HttpClient.new)();
    sharedHttpClient.connectionTimeout = timeout;
    _sharedHttpClient = sharedHttpClient;
    HttpClient sharedHttpClientFactory() => sharedHttpClient;
    _http = BridgeHttpFetch(
      httpClientFactory: sharedHttpClientFactory,
      timeout: timeout,
      closeClientAfterRequest: false,
    );
    _presenterCache = PresenterCacheService(
      presenterRoot: Directory('${bridgeRoot.path}/presenter'),
      httpClientFactory: sharedHttpClientFactory,
      closeClientAfterRequest: false,
    );
    _serverGateway = PresenterServerGateway(
      apiBaseUrl: apiBaseUrl,
      cacheIdentityBaseUrl: cacheIdentityBaseUrl ?? apiBaseUrl,
      bridgeRoot: bridgeRoot,
      headers: headers,
      httpClientFactory: sharedHttpClientFactory,
      timeout: timeout,
      closeClientAfterRequest: false,
    );
    _sessionCoordinator = PresenterSessionCoordinator(
      presenterCache: _presenterCache,
      runtimeStorage: RuntimeSessionStorage(
        runtimeRoot: Directory('${bridgeRoot.path}/runtime'),
      ),
      onlinePresenterUrl: presenterEntryUrl,
      apiBaseUrl: this.apiBaseUrl,
      bundleManifestUrl: bundleManifestUrl,
      headers: _staticHeaders,
    );
  }

  final Uri apiBaseUrl;
  final Uri presenterEntryUrl;
  final Directory bridgeRoot;
  final String? bundleManifestUrl;
  final Map<String, String> _staticHeaders;
  final BridgeHeadersProvider? _headersProvider;
  late final HttpClient _sharedHttpClient;
  late final BridgeHttpFetch _http;
  late final PresenterCacheService _presenterCache;
  late final PresenterServerGateway _serverGateway;
  late final PresenterSessionCoordinator _sessionCoordinator;

  BridgeIdentityContext _identityContext;
  TemplateQueryRequest? _lastTemplateQuery;
  Future<PresenterCacheManifest>? _presenterSyncInFlight;
  final List<void Function(double)> _progressListeners =
      <void Function(double)>[];
  double _lastProgress = 0;
  bool _disposed = false;

  BridgeIdentityContext get identityContext => _identityContext;

  Future<void> updateIdentityContext(BridgeIdentityContext value) async {
    _ensureActive();
    if (value == _identityContext) return;
    await _sessionCoordinator.stop();
    _identityContext = value;
    _lastTemplateQuery = null;
  }

  Future<void> clearIdentityContext() {
    return updateIdentityContext(BridgeIdentityContext());
  }

  Future<void> probeEndpoints() async {
    _ensureActive();
    final headers = await _resolveHeaders(BridgeHeaderOperation.probeApi);
    await _http.getBytes(
      resolveBridgeApiRoute(apiBaseUrl, 'health'),
      headers: headers,
    );
    await _http.getBytes(presenterEntryUrl, headers: const <String, String>{});
  }

  Future<List<PresenterSystem>> fetchSystems() async {
    _ensureActive();
    final headers = await _resolveHeaders(BridgeHeaderOperation.fetchSystems);
    return _serverGateway.fetchSystems(headers: headers);
  }

  Future<TemplateSyncSummary> syncTemplates({
    String? systemCode,
    @Deprecated('Use systemCode.') int? systemId,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    _ensureActive();
    if (systemCode == null && !_identityContext.isEmpty) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'An active identity context requires systemCode synchronization. '
        'The deprecated numeric cache is anonymous-only.',
      );
    }
    final query = systemCode == null
        ? null
        : TemplateQueryRequest(
            systemCode: systemCode,
            identity: _identityContext,
            filter: filter,
            extra: extra,
          );
    if (query != null && systemId != null) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Template synchronization cannot combine systemCode and systemId.',
      );
    }
    final headers = await _resolveHeaders(
      BridgeHeaderOperation.syncTemplates,
      query: query,
      systemId: systemId,
    );
    final summary = await _serverGateway.syncTemplates(
      query: query,
      systemId: systemId,
      headers: headers,
    );
    if (query != null) _lastTemplateQuery = query;
    return summary;
  }

  Future<List<CachedTemplate>> listTemplates({
    String? systemCode,
    @Deprecated('Use systemCode.') int? systemId,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    _ensureActive();
    if (systemCode != null && systemId != null) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Template listing cannot combine systemCode and systemId.',
      );
    }

    final explicitQuery = systemCode == null
        ? null
        : TemplateQueryRequest(
            systemCode: systemCode,
            identity: _identityContext,
            filter: filter,
            extra: extra,
          );
    final query = systemId == null ? explicitQuery ?? _lastTemplateQuery : null;
    if (query == null && !_identityContext.isEmpty) {
      throw const BridgeRuntimeException(
        BridgeTemplateSyncErrorCodes.offlineCacheUnavailable,
        'No systemCode-scoped catalog is selected for the active identity.',
      );
    }
    final headers = await _resolveHeaders(
      BridgeHeaderOperation.listTemplates,
      query: query,
      systemId: systemId,
    );
    final templates = await _serverGateway.listTemplates(
      query: query,
      systemId: systemId,
      headers: headers,
    );
    if (explicitQuery != null) _lastTemplateQuery = explicitQuery;
    return templates;
  }

  Future<void> clearTemplateCache() async {
    _ensureActive();
    await _serverGateway.clearTemplates();
    _lastTemplateQuery = null;
  }

  Future<PresenterCacheManifest> syncPresenter({
    void Function(double progress)? onProgress,
  }) {
    _ensureActive();
    if (onProgress != null) {
      _progressListeners.add(onProgress);
    }

    final running = _presenterSyncInFlight;
    if (running != null) {
      if (onProgress != null) {
        _notifyProgressListener(onProgress, _lastProgress);
      }
      return running.whenComplete(() {
        if (onProgress != null) _progressListeners.remove(onProgress);
      });
    }

    _lastProgress = 0;
    _emitProgress(0);
    final future = _resolveHeaders(
      BridgeHeaderOperation.syncPresenter,
    ).then(_syncPresenter);
    _presenterSyncInFlight = future;
    return future.whenComplete(() {
      if (identical(_presenterSyncInFlight, future)) {
        _presenterSyncInFlight = null;
      }
      if (onProgress != null) _progressListeners.remove(onProgress);
    });
  }

  Future<PresenterCacheManifest> _syncPresenter(
    Map<String, String> headers,
  ) async {
    try {
      final manifest = await _presenterCache.syncPresenterSite(
        bundleManifestUrl: bundleManifestUrl,
        apiBaseUrl: apiBaseUrl.toString(),
        headers: headers,
        onProgress: _emitProgress,
      );
      _sessionCoordinator.rememberCachedManifest(manifest);
      _emitProgress(1);
      return manifest;
    } finally {
      _progressListeners.clear();
    }
  }

  Future<void> clearPresenterCache() async {
    _ensureActive();
    await _waitForPresenterSync();
    await _sessionCoordinator.stop();
    await _presenterCache.clearPresenterCache();
    _sessionCoordinator.forgetCachedManifest();
  }

  Future<ReportingBridgeStatus> getStatus() async {
    _ensureActive();
    final cachedManifest = await _sessionCoordinator.loadCachedManifest();
    final presenterFilesReady = await _presenterCache.isReady();
    final presenterCached = cachedManifest != null && presenterFilesReady;
    final templates = await _currentTemplatesForStatus();
    return ReportingBridgeStatus(
      apiBaseUrl: apiBaseUrl.toString(),
      presenterCached: presenterCached,
      templateCount: templates.length,
      presenterManifest: presenterCached ? cachedManifest : null,
    );
  }

  Future<PresenterSessionLaunch> prepareSession(
    PresenterSessionRequest request,
  ) async {
    _ensureActive();
    final headers = await _resolveHeaders(
      BridgeHeaderOperation.prepareSession,
      reportType: request.reportType,
      sessionId: request.sessionId,
    );
    return _sessionCoordinator.prepare(request, headers: headers);
  }

  Future<PresenterSessionLaunch> prepareReplacementSession(
    PresenterSessionRequest request,
  ) async {
    _ensureActive();
    final headers = await _resolveHeaders(
      BridgeHeaderOperation.prepareSession,
      reportType: request.reportType,
      sessionId: request.sessionId,
    );
    return _sessionCoordinator.prepare(
      request,
      headers: headers,
      deferReplacementCommit: true,
    );
  }

  Future<void> commitReplacementSession() {
    _ensureActive();
    return _sessionCoordinator.commitStaged();
  }

  Future<void> discardReplacementSession() {
    _ensureActive();
    return _sessionCoordinator.discardStaged();
  }

  Future<void> stopSession() {
    _ensureActive();
    return _sessionCoordinator.stop();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _waitForPresenterSync();
    _progressListeners.clear();
    await _sessionCoordinator.dispose();
    _sharedHttpClient.close(force: true);
  }

  Future<List<CachedTemplate>> _currentTemplatesForStatus() async {
    final query = _lastTemplateQuery;
    if (query == null) {
      if (!_identityContext.isEmpty) return const <CachedTemplate>[];
      return _serverGateway.listTemplates();
    }
    final headers = await _resolveHeaders(
      BridgeHeaderOperation.listTemplates,
      query: query,
    );
    try {
      return await _serverGateway.listTemplates(query: query, headers: headers);
    } on BridgeRuntimeException catch (error) {
      if (error.code == BridgeTemplateSyncErrorCodes.offlineCacheUnavailable) {
        return const <CachedTemplate>[];
      }
      rethrow;
    }
  }

  Future<Map<String, String>> _resolveHeaders(
    BridgeHeaderOperation operation, {
    TemplateQueryRequest? query,
    int? systemId,
    String? reportType,
    String? sessionId,
  }) {
    return resolveBridgeHeaders(
      context: BridgeHeaderContext(
        operation: operation,
        apiBaseUrl: apiBaseUrl,
        systemCode: query?.systemCode,
        systemId: systemId,
        branchId: query?.identity.branchId ?? _identityContext.branchId,
        userId: query?.identity.userId ?? _identityContext.userId,
        systemUnit: query?.identity.systemUnit ?? _identityContext.systemUnit,
        reportType: reportType,
        sessionId: sessionId,
      ),
      provider: _headersProvider,
      fallback: _staticHeaders,
    );
  }

  Future<void> _waitForPresenterSync() async {
    final running = _presenterSyncInFlight;
    if (running == null) return;
    try {
      await running;
    } catch (_) {
      // Cleanup must continue after a failed download.
    }
  }

  void _emitProgress(double value) {
    final next = value.clamp(0.0, 1.0).toDouble();
    if (next < _lastProgress) return;
    _lastProgress = next;
    for (final listener in _progressListeners.toList(growable: false)) {
      _notifyProgressListener(listener, next);
    }
  }

  void _notifyProgressListener(
    void Function(double progress) listener,
    double progress,
  ) {
    try {
      listener(progress);
    } catch (_) {
      // UI progress callbacks must not interrupt Bridge transport.
    }
  }

  void _ensureActive() {
    if (_disposed) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Reporting Bridge client is disposed.',
      );
    }
  }
}

Uri _withTrailingSlash(Uri value) =>
    value.path.endsWith('/') ? value : value.replace(path: '${value.path}/');
