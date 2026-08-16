import 'dart:convert';
import 'dart:io';

import 'bridge_cache_namespace.dart';
import 'bridge_config.dart';
import 'bridge_contract.dart';
import 'bridge_local_server.dart';
import 'bridge_presenter_cache.dart';
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
    required this.onlinePresenterUrl,
    required Uri apiBaseUrl,
    this.bundleManifestUrl,
    Map<String, String> headers = const <String, String>{},
  }) : apiBaseUrl = _withTrailingSlash(apiBaseUrl),
       _headers = filterPresenterBridgeHeaders(headers);

  final PresenterCacheService presenterCache;
  final RuntimeSessionStorage runtimeStorage;
  final Uri onlinePresenterUrl;
  final Uri apiBaseUrl;
  final String? bundleManifestUrl;
  final Map<String, String> _headers;

  LocalPresenterServer? _localServer;
  LocalServerHandle? _localHandle;
  String? _activeSessionId;
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
    final file = presenterCache.manifestFile;
    if (!await file.exists()) {
      _cachedManifest = null;
      return null;
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        _cachedManifest = null;
        return null;
      }
      final manifestUri = Uri.tryParse(
        decoded['manifestUrl']?.toString().trim() ?? '',
      );
      if (manifestUri != _expectedManifestUri()) {
        _cachedManifest = null;
        return null;
      }

      final presenterVersion = decoded['presenterVersion']?.toString().trim();
      final bundleVersion = decoded['bundleVersion']?.toString().trim();
      final devVersion = int.tryParse(decoded['devVersion']?.toString() ?? '');
      if (presenterVersion == null ||
          BridgeSemanticVersion.tryParse(presenterVersion) == null ||
          bundleVersion == null ||
          bundleVersion.isEmpty ||
          devVersion == null) {
        _cachedManifest = null;
        return null;
      }

      final manifest = PresenterCacheManifest(
        presenterVersion: presenterVersion,
        bundleVersion: bundleVersion,
        devVersion: devVersion,
        rootPath: presenterCache.presenterRoot.path,
        updatedAt: DateTime.tryParse(decoded['updatedAt']?.toString() ?? ''),
        syncedAt: DateTime.tryParse(decoded['syncedAt']?.toString() ?? ''),
      );
      _cachedManifest = manifest;
      return manifest;
    } on FormatException {
      _cachedManifest = null;
      return null;
    } on FileSystemException {
      return _cachedManifest;
    }
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
        'Template ${request.template.id} belongs to '
        '${request.template.type}; expected $reportType.',
      );
    }

    final cachedManifest = request.mode == PresenterSessionMode.offline
        ? await loadCachedManifest()
        : null;
    final cachedPresenterReady = request.mode == PresenterSessionMode.offline
        ? await presenterCache.isReady()
        : false;
    if (request.mode == PresenterSessionMode.offline &&
        (cachedManifest == null || !cachedPresenterReady)) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.offlineAssetsNotReady,
        'Offline mode requires a complete, compatible Presenter bundle.',
      );
    }

    final remoteManifest = request.mode == PresenterSessionMode.online
        ? await presenterCache.fetchRemoteManifest(
            bundleManifestUrl: bundleManifestUrl,
            apiBaseUrl: apiBaseUrl.toString(),
            headers: effectiveHeaders,
          )
        : null;
    final presenterVersion = request.mode == PresenterSessionMode.offline
        ? _requiredCachedPresenterVersion(cachedManifest!)
        : remoteManifest!.presenterVersion;
    final presenterDevVersion = request.mode == PresenterSessionMode.offline
        ? cachedManifest!.devVersion
        : remoteManifest!.devVersion;

    if (!request.template.isCompatibleWith(
      presenterVersion: presenterVersion,
      bridgeVersion: BridgeContract.implementationVersion,
    )) {
      throw BridgeRuntimeException(
        BridgeRuntimeErrorCodes.presenterVersionTooOld,
        'Template ${request.template.id} requires Presenter '
        '${request.template.minPresenterVersion ?? 'any'} and Bridge '
        '${request.template.minBridgeVersion ?? 'any'}; current versions are '
        '$presenterVersion and ${BridgeContract.implementationVersion}.',
      );
    }

    final previousServer = _localServer;
    final previousHandle = _localHandle;
    final previousSessionId = _activeSessionId;
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
        seedData: request.seedData,
        templateDocument: request.template.document,
        selectedTemplate: request.template.selectedTemplate,
        branding: request.branding,
        apiHeaders: request.apiHeaders,
      ),
    );
    final candidateServer = LocalPresenterServer(
      presenterRoot: presenterCache.presenterRoot,
      runtimeRoot: runtimeStorage.runtimeRoot,
    );
    LocalServerHandle? candidateHandle;

    try {
      if (request.mode == PresenterSessionMode.offline) {
        await presenterCache.normalizeCachedPresenterForOffline();
      }
      candidateHandle = request.mode == PresenterSessionMode.offline
          ? await candidateServer.start(sessionId: runtimeSession.sessionId)
          : await candidateServer.startRuntimeOnly(
              sessionId: runtimeSession.sessionId,
            );

      final launch = PresenterSessionLaunch(
        presenterUrl: request.mode == PresenterSessionMode.offline
            ? _withPresenterLocale(
                candidateHandle.presenterUrl,
                locale: request.locale,
                direction: request.direction,
              )
            : _onlineSessionUrl(
                sessionId: runtimeSession.sessionId,
                runtimeBaseUrl: candidateHandle.baseUrl,
                locale: request.locale,
                direction: request.direction,
              ),
        sessionId: runtimeSession.sessionId,
        presenterVersion: presenterVersion,
        presenterDevVersion: presenterDevVersion,
        presenterManifest: cachedManifest,
      );
      if (deferReplacementCommit && previousSessionId != null) {
        _stagedSession = _StagedPresenterSession(
          server: candidateServer,
          handle: candidateHandle,
          sessionId: runtimeSession.sessionId,
        );
        return launch;
      }
      _localServer = candidateServer;
      _localHandle = candidateHandle;
      _activeSessionId = runtimeSession.sessionId;
      await _cleanupReplacedSession(
        server: previousServer,
        handle: previousHandle,
        sessionId: previousSessionId,
      );
      return launch;
    } catch (error, stackTrace) {
      try {
        await candidateHandle?.stop();
        await candidateServer.stop();
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
    await _cleanupReplacedSession(
      server: previousServer,
      handle: previousHandle,
      sessionId: previousSessionId,
    );
  }

  Future<void> discardStaged() async {
    final staged = _stagedSession;
    if (staged == null) return;
    _stagedSession = null;
    try {
      await staged.handle.stop();
      await staged.server.stop();
    } finally {
      await runtimeStorage.deleteRuntimeSession(staged.sessionId);
    }
  }

  Future<void> _cleanupReplacedSession({
    required LocalPresenterServer? server,
    required LocalServerHandle? handle,
    required String? sessionId,
  }) async {
    try {
      await handle?.stop();
      await server?.stop();
    } catch (_) {}
    if (sessionId != null && sessionId != _activeSessionId) {
      try {
        await runtimeStorage.deleteRuntimeSession(sessionId);
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    await discardStaged();
    final handle = _localHandle;
    final sessionId = _activeSessionId;
    _localHandle = null;
    _activeSessionId = null;

    Object? failure;
    StackTrace? failureStackTrace;
    try {
      await handle?.stop();
    } catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
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

  String _onlineSessionUrl({
    required String sessionId,
    required String runtimeBaseUrl,
    required String locale,
    required String direction,
  }) {
    final base = onlinePresenterUrl
        .replace(
          queryParameters: <String, String>{
            ...onlinePresenterUrl.queryParameters,
            'sessionId': sessionId,
            'runtimeBaseUrl': runtimeBaseUrl,
          },
        )
        .toString();
    return _withPresenterLocale(base, locale: locale, direction: direction);
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

  Uri? _expectedManifestUri() {
    final explicit = bundleManifestUrl?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return Uri.tryParse(explicit);
    }
    return resolveBridgeApiRoute(apiBaseUrl, 'presenter/bundles/manifest');
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
  });

  final LocalPresenterServer server;
  final LocalServerHandle handle;
  final String sessionId;
}

Uri _withTrailingSlash(Uri value) =>
    value.path.endsWith('/') ? value : value.replace(path: '${value.path}/');
