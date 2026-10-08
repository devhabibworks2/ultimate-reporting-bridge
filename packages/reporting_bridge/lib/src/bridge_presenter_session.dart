import 'dart:io';

import 'bridge_cache_namespace.dart';
import 'bridge_config.dart';
import 'bridge_contract.dart';
import 'bridge_image_proxy_relay.dart';
import 'bridge_local_server.dart';
import 'bridge_presenter_cache.dart';
import 'bridge_presenter_resource_cache.dart';
import 'bridge_runtime_error.dart';
import 'bridge_runtime_storage.dart';
import 'bridge_semantic_version.dart';
import 'bridge_template_cache.dart';
import 'bridge_template_sync.dart';

enum PresenterSessionMode { online, offline }

class PresenterSessionRequest {
  const PresenterSessionRequest({
    required this.reportType,
    required this.reportName,
    required this.mode,
    required this.seedData,
    required this.template,
    this.locale = 'en',
    this.direction = 'ltr',
    this.branding,
    this.apiHeaders,
    this.sessionId,
  });

  final String reportType;
  final String reportName;
  final PresenterSessionMode mode;
  final Map<String, dynamic> seedData;
  final CachedTemplate template;
  final String locale;
  final String direction;
  final BrandConfig? branding;
  final ApiHeaderConfig? apiHeaders;
  final String? sessionId;
}

class PresenterSessionLaunch {
  const PresenterSessionLaunch({
    required this.presenterUrl,
    required this.sessionId,
    required this.presenterVersion,
    required this.presenterDevVersion,
    this.presenterManifest,
  });

  final String presenterUrl;
  final String sessionId;
  final String presenterVersion;
  final int presenterDevVersion;
  final PresenterCacheManifest? presenterManifest;
}

/// Owns one active Presenter runtime session for a host application.
///
/// The coordinator writes the runtime files, starts the local runtime server,
/// composes the online or offline Presenter entry URL, and removes the active
/// runtime directory when the session is replaced or stopped.
class PresenterSessionCoordinator {
  PresenterSessionCoordinator({
    required this.presenterCache,
    required this.runtimeStorage,
    PresenterResourceCacheStore? resourceCacheStore,
    required Uri apiBaseUrl,
    this.bundleManifestUrl,
    Map<String, String> headers = const <String, String>{},
  }) : apiBaseUrl = _withTrailingSlash(apiBaseUrl),
       resourceCacheStore =
           resourceCacheStore ??
           PresenterResourceCacheStore(
             cacheRoot: Directory(
               '${runtimeStorage.runtimeRoot.parent.path}/presenter_resources',
             ),
           ),
       _headers = filterPresenterBridgeHeaders(headers);

  final PresenterCacheService presenterCache;
  final RuntimeSessionStorage runtimeStorage;
  final PresenterResourceCacheStore resourceCacheStore;
  final Uri apiBaseUrl;
  final String? bundleManifestUrl;
  final Map<String, String> _headers;

  LocalPresenterServer? _localServer;
  LocalServerHandle? _localHandle;
  String? _activeSessionId;
  PresenterSessionMode? _activeMode;
  PresenterCacheManifest? _cachedManifest;
  _StagedPresenterSession? _stagedSession;

  String? get activeSessionId => _activeSessionId;

  void rememberCachedManifest(PresenterCacheManifest manifest) {
    _cachedManifest = manifest;
  }

  void forgetCachedManifest() {
    _cachedManifest = null;
  }

  Future<PresenterCacheManifest?> loadCachedManifest() async {
    _cachedManifest = await presenterCache.readCachedManifest(
      bundleManifestUrl: bundleManifestUrl,
      apiBaseUrl: apiBaseUrl.toString(),
    );
    return _cachedManifest;
  }

  Future<PresenterSessionLaunch> prepare(
    PresenterSessionRequest request, {
    Map<String, String>? headers,
    bool deferReplacementCommit = false,
  }) async {
    await discardStaged();
    final effectiveHeaders = filterPresenterBridgeHeaders(headers ?? _headers);
    final reportType = request.reportType.trim();
    if (reportType.isEmpty || request.reportName.trim().isEmpty) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Presenter session requires reportType and reportName.',
      );
    }
    if (request.template.type != reportType) {
      throw BridgeRuntimeException(
        BridgeRuntimeErrorCodes.templateDocumentInvalid,
        'Template ${request.template.templateCode} belongs to '
        '${request.template.type}; expected $reportType.',
      );
    }

    final previousCachedManifest = request.mode == PresenterSessionMode.online
        ? await loadCachedManifest()
        : null;
    var cachedManifest = request.mode == PresenterSessionMode.offline
        ? await loadCachedManifest()
        : null;
    if (request.mode == PresenterSessionMode.offline &&
        cachedManifest == null) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.offlineAssetsNotReady,
        'Offline mode requires a complete, compatible Presenter bundle.',
      );
    }

    if (request.mode == PresenterSessionMode.online) {
      try {
        cachedManifest = await presenterCache.ensureCurrentPresenterSite(
          bundleManifestUrl: bundleManifestUrl,
          apiBaseUrl: apiBaseUrl.toString(),
          headers: effectiveHeaders,
        );
      } on PresenterCacheUpdateException catch (error) {
        if (error.enforceUpdate || previousCachedManifest == null) rethrow;
        cachedManifest = previousCachedManifest;
      }
      _cachedManifest = cachedManifest;
    }
    final currentManifest = cachedManifest!;
    final presenterVersion = _requiredCachedPresenterVersion(currentManifest);
    final presenterDevVersion = currentManifest.devVersion;

    if (!request.template.isCompatibleWith(
      presenterVersion: presenterVersion,
      bridgeVersion: BridgeContract.implementationVersion,
    )) {
      throw BridgeRuntimeException(
        BridgeRuntimeErrorCodes.presenterVersionTooOld,
        'Template ${request.template.templateCode} requires Presenter '
        '${request.template.minPresenterVersion ?? 'any'} and Bridge '
        '${request.template.minBridgeVersion ?? 'any'}; current versions are '
        '$presenterVersion and ${BridgeContract.implementationVersion}.',
      );
    }

    final previousServer = _localServer;
    final previousHandle = _localHandle;
    final previousSessionId = _activeSessionId;
    final previousMode = _activeMode;
    final requestedSessionId = request.sessionId;
    final replacementSessionId =
        requestedSessionId != null && requestedSessionId == previousSessionId
        ? '$requestedSessionId-${DateTime.now().microsecondsSinceEpoch}'
        : requestedSessionId;
    final runtimeSession = await runtimeStorage.prepareRuntimeSession(
      RuntimeSessionInput(
        sessionId:
            replacementSessionId ??
            'host-${DateTime.now().microsecondsSinceEpoch}',
        reportType: reportType,
        reportName: request.reportName,
        mode: request.mode.name,
        locale: request.locale,
        direction: request.direction,
        apiBaseUrl: request.mode == PresenterSessionMode.online
            ? normalizeBridgeApiBaseUrl(apiBaseUrl).removeFragment().toString()
            : null,
        seedData: request.seedData,
        templateDocument: request.template.document,
        selectedTemplate: request.template.selectedTemplate,
        branding: request.branding,
        apiHeaders: request.apiHeaders,
      ),
    );
    final canReusePreviousServer =
        previousServer != null &&
        (previousSessionId == null || previousMode == request.mode);
    final candidateServer = canReusePreviousServer
        ? previousServer
        : LocalPresenterServer(
            presenterRoot: presenterCache.presenterRoot,
            runtimeRoot: runtimeStorage.runtimeRoot,
            resourceCacheStore: resourceCacheStore,
          );
    LocalServerHandle? candidateHandle;

    try {
      await presenterCache.normalizeCachedPresenterForOffline();
      candidateHandle = await candidateServer.start(
        sessionId: runtimeSession.sessionId,
        imageProxyRelay: request.mode == PresenterSessionMode.online
            ? BridgeImageProxyRelay(
                apiBaseUrl: apiBaseUrl,
                headers: effectiveHeaders,
              )
            : null,
      );

      final launch = PresenterSessionLaunch(
        presenterUrl: _withPresenterLocale(
          candidateHandle.presenterUrl,
          locale: request.locale,
          direction: request.direction,
        ),
        sessionId: runtimeSession.sessionId,
        presenterVersion: presenterVersion,
        presenterDevVersion: presenterDevVersion,
        presenterManifest: currentManifest,
      );
      if (deferReplacementCommit && previousSessionId != null) {
        _stagedSession = _StagedPresenterSession(
          server: candidateServer,
          handle: candidateHandle,
          sessionId: runtimeSession.sessionId,
          mode: request.mode,
        );
        return launch;
      }
      _localServer = candidateServer;
      _localHandle = candidateHandle;
      _activeSessionId = runtimeSession.sessionId;
      _activeMode = request.mode;
      await _cleanupReplacedSession(
        server: previousServer,
        handle: previousHandle,
        sessionId: previousSessionId,
        retainedServer: candidateServer,
      );
      return launch;
    } catch (error, stackTrace) {
      try {
        await candidateHandle?.stop();
        if (!identical(candidateServer, previousServer)) {
          await candidateServer.stop();
        }
        await runtimeStorage.deleteRuntimeSession(runtimeSession.sessionId);
      } catch (_) {
        // Preserve the preparation failure.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> commitStaged() async {
    final staged = _stagedSession;
    if (staged == null) return;
    _stagedSession = null;
    final previousServer = _localServer;
    final previousHandle = _localHandle;
    final previousSessionId = _activeSessionId;
    _localServer = staged.server;
    _localHandle = staged.handle;
    _activeSessionId = staged.sessionId;
    _activeMode = staged.mode;
    await _cleanupReplacedSession(
      server: previousServer,
      handle: previousHandle,
      sessionId: previousSessionId,
      retainedServer: staged.server,
    );
  }

  Future<void> discardStaged() async {
    final staged = _stagedSession;
    if (staged == null) return;
    _stagedSession = null;
    try {
      await staged.handle.stop();
      if (!identical(staged.server, _localServer)) {
        await staged.server.stop();
      }
    } finally {
      await runtimeStorage.deleteRuntimeSession(staged.sessionId);
    }
  }

  Future<void> _cleanupReplacedSession({
    required LocalPresenterServer? server,
    required LocalServerHandle? handle,
    required String? sessionId,
    required LocalPresenterServer retainedServer,
  }) async {
    try {
      await handle?.stop();
      if (server != null && !identical(server, retainedServer)) {
        await server.stop();
      }
    } catch (_) {}
    if (sessionId != null && sessionId != _activeSessionId) {
      try {
        await runtimeStorage.deleteRuntimeSession(sessionId);
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    await discardStaged();
    final server = _localServer;
    final handle = _localHandle;
    final sessionId = _activeSessionId;
    _localServer = null;
    _localHandle = null;
    _activeSessionId = null;
    _activeMode = null;

    Object? failure;
    StackTrace? failureStackTrace;
    try {
      await handle?.stop();
    } catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
    }

    try {
      await server?.stop();
    } catch (error, stackTrace) {
      failure ??= error;
      failureStackTrace ??= stackTrace;
    }

    if (sessionId != null) {
      try {
        await runtimeStorage.deleteRuntimeSession(sessionId);
      } catch (error, stackTrace) {
        failure ??= error;
        failureStackTrace ??= stackTrace;
      }
    }

    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStackTrace!);
    }
  }

  Future<void> dispose() async {
    try {
      await stop();
    } finally {
      await _localServer?.stop();
      _localServer = null;
    }
  }

  String _withPresenterLocale(
    String url, {
    required String locale,
    required String direction,
  }) {
    final uri = Uri.parse(url);
    return uri
        .replace(
          queryParameters: <String, String>{
            ...uri.queryParameters,
            'locale': locale,
            'dir': direction,
          },
        )
        .toString();
  }

  String _requiredCachedPresenterVersion(PresenterCacheManifest manifest) {
    final version = manifest.presenterVersion?.trim();
    if (version == null || BridgeSemanticVersion.tryParse(version) == null) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.offlineAssetsNotReady,
        'Cached Presenter manifest is missing a semantic presenterVersion. '
        'Sync the Presenter bundle again.',
      );
    }
    return version;
  }
}

class _StagedPresenterSession {
  const _StagedPresenterSession({
    required this.server,
    required this.handle,
    required this.sessionId,
    required this.mode,
  });

  final LocalPresenterServer server;
  final LocalServerHandle handle;
  final String sessionId;
  final PresenterSessionMode mode;
}

Uri _withTrailingSlash(Uri value) =>
    value.path.endsWith('/') ? value : value.replace(path: '${value.path}/');
