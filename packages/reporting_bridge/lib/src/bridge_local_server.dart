import 'dart:io';

import 'bridge_runtime_error.dart';

class PortPolicy {
  const PortPolicy({this.preferredPort = 0});

  final int preferredPort;
}

class LocalServerHandle {
  const LocalServerHandle({
    required this.port,
    required this.baseUrl,
    required this.presenterUrl,
    required this.stop,
  });

  final int port;
  final String baseUrl;
  final String presenterUrl;
  final Future<void> Function() stop;
}

class LocalPresenterServer {
  LocalPresenterServer({
    required this.presenterRoot,
    required this.runtimeRoot,
  });

  final Directory presenterRoot;
  final Directory runtimeRoot;
  static const String _presenterRoutePrefix = '/UltimateReport/apps/presenter/';
  HttpServer? _server;
  final Set<String> _sessionIds = <String>{};
  bool _servePresenter = false;
  Uri? _proxyPresenterUrl;
  HttpClient? _proxyClient;

  Future<LocalServerHandle> start({
    required String sessionId,
    PortPolicy portPolicy = const PortPolicy(),
  }) async {
    return _start(
      sessionId: sessionId,
      portPolicy: portPolicy,
      servePresenter: true,
    );
  }

  Future<LocalServerHandle> startRuntimeOnly({
    required String sessionId,
    PortPolicy portPolicy = const PortPolicy(),
  }) async {
    return _start(
      sessionId: sessionId,
      portPolicy: portPolicy,
      servePresenter: false,
    );
  }

  Future<LocalServerHandle> startProxy({
    required String sessionId,
    required Uri presenterUrl,
    PortPolicy portPolicy = const PortPolicy(),
  }) async {
    if (!presenterUrl.path.startsWith(_presenterRoutePrefix)) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.localhostServerUnavailable,
        'Online Presenter URL must use the deployment-aligned Presenter route.',
      );
    }
    return _start(
      sessionId: sessionId,
      portPolicy: portPolicy,
      servePresenter: false,
      proxyPresenterUrl: presenterUrl,
    );
  }

  Future<LocalServerHandle> _start({
    required String sessionId,
    required PortPolicy portPolicy,
    required bool servePresenter,
    Uri? proxyPresenterUrl,
  }) async {
    final activeSessionId = _validatedSessionId(sessionId);
    if (servePresenter &&
        !await File('${presenterRoot.path}/index.html').exists()) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.offlineAssetsNotReady,
        'Cached Presenter index.html is required before localhost serving.',
      );
    }

    final existing = _server;
    if (existing != null && _sessionIds.isEmpty) {
      if (portPolicy.preferredPort != 0 &&
          portPolicy.preferredPort != existing.port) {
        await stop();
      } else {
        _replaceRouting(
          servePresenter: servePresenter,
          proxyPresenterUrl: proxyPresenterUrl,
        );
      }
    } else if (existing != null &&
        !_isCompatibleReuse(
          server: existing,
          portPolicy: portPolicy,
          servePresenter: servePresenter,
          proxyPresenterUrl: proxyPresenterUrl,
        )) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.localhostServerUnavailable,
        'Existing localhost Presenter server uses incompatible routing.',
      );
    }

    var createdServer = false;
    try {
      var server = _server;
      if (server == null) {
        server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          portPolicy.preferredPort,
        );
        createdServer = true;
        _server = server;
        _servePresenter = servePresenter;
        _proxyPresenterUrl = proxyPresenterUrl;
        _proxyClient = proxyPresenterUrl == null ? null : HttpClient();
        server.listen(_handleRequest);
      }

      _sessionIds.add(activeSessionId);
      final baseUrl = 'http://127.0.0.1:${server.port}';
      final proxyLaunchUrl = proxyPresenterUrl == null
          ? null
          : Uri.parse(baseUrl).replace(
              path: proxyPresenterUrl.path,
              query: proxyPresenterUrl.hasQuery
                  ? proxyPresenterUrl.query
                  : null,
            );
      return LocalServerHandle(
        port: server.port,
        baseUrl: baseUrl,
        presenterUrl: servePresenter
            ? '$baseUrl/UltimateReport/apps/presenter/index.html?sessionId=$activeSessionId'
            : proxyLaunchUrl?.toString() ?? baseUrl,
        stop: () => releaseSession(activeSessionId),
      );
    } on Object catch (error) {
      _sessionIds.remove(activeSessionId);
      if (createdServer) {
        await stop();
      }
      if (error is BridgeRuntimeException) rethrow;
      throw BridgeRuntimeException(
        BridgeRuntimeErrorCodes.localhostServerUnavailable,
        'Failed to start local Presenter server: $error',
      );
    }
  }

  void _replaceRouting({
    required bool servePresenter,
    required Uri? proxyPresenterUrl,
  }) {
    final oldProxyClient = _proxyClient;
    _servePresenter = servePresenter;
    _proxyPresenterUrl = proxyPresenterUrl;
    _proxyClient = proxyPresenterUrl == null ? null : HttpClient();
    oldProxyClient?.close(force: true);
  }

  bool _isCompatibleReuse({
    required HttpServer server,
    required PortPolicy portPolicy,
    required bool servePresenter,
    required Uri? proxyPresenterUrl,
  }) {
    if (portPolicy.preferredPort != 0 &&
        portPolicy.preferredPort != server.port) {
      return false;
    }
    if (_servePresenter != servePresenter) return false;
    final currentProxy = _proxyPresenterUrl;
    if (currentProxy == null || proxyPresenterUrl == null) {
      return currentProxy == null && proxyPresenterUrl == null;
    }
    return currentProxy == proxyPresenterUrl;
  }

  Future<void> releaseSession(String sessionId) async {
    _sessionIds.remove(_validatedSessionId(sessionId));
  }

  Future<void> stop() async {
    final server = _server;
    final proxyClient = _proxyClient;
    _server = null;
    _sessionIds.clear();
    _servePresenter = false;
    _proxyPresenterUrl = null;
    _proxyClient = null;
    proxyClient?.close(force: true);
    await server?.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    _addCommonHeaders(request.response);
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      await _sendMethodNotAllowed(request);
      return;
    }

    late final String path;
    try {
      path = Uri.decodeComponent(request.uri.path);
    } on FormatException {
      await _sendNotFound(request);
      return;
    }

    if (_proxyPresenterUrl != null && path.startsWith(_presenterRoutePrefix)) {
      final relative = path.substring(_presenterRoutePrefix.length);
      if (!_isSafeRelativePath(relative.isEmpty ? 'index.html' : relative)) {
        await _sendNotFound(request);
        return;
      }
      await _proxyPresenterRequest(request, relative);
      return;
    }

    final file = _resolveFile(path);
    if (file == null || !await file.exists()) {
      await _sendNotFound(request);
      return;
    }
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.file) {
      await _sendNotFound(request);
      return;
    }

    request.response.headers.contentType = _contentType(file.path);
    if (request.method == 'HEAD') {
      request.response.contentLength = await file.length();
      await request.response.close();
      return;
    }
    await file.openRead().pipe(request.response);
  }

  Future<void> _proxyPresenterRequest(
    HttpRequest request,
    String relativePath,
  ) async {
    final proxyBase = _proxyPresenterUrl;
    final client = _proxyClient;
    if (proxyBase == null || client == null) {
      await _sendNotFound(request);
      return;
    }

    final target = proxyBase
        .resolve(relativePath.isEmpty ? 'index.html' : relativePath)
        .replace(query: request.uri.hasQuery ? request.uri.query : null);
    try {
      final upstreamRequest = await client.openUrl(request.method, target);
      final upstreamResponse = await upstreamRequest.close();
      request.response.statusCode = upstreamResponse.statusCode;
      final contentType = upstreamResponse.headers.contentType;
      if (contentType != null) {
        request.response.headers.contentType = contentType;
      }
      if (request.method == 'HEAD') {
        await upstreamResponse.drain<void>();
        await request.response.close();
        return;
      }
      await upstreamResponse.pipe(request.response);
    } on Object {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
    }
  }

  File? _resolveFile(String path) {
    if (path.startsWith('/runtime/')) {
      final relative = path.substring('/runtime/'.length);
      final separator = relative.indexOf('/');
      if (separator <= 0 ||
          !_sessionIds.contains(relative.substring(0, separator))) {
        return null;
      }
      return _safeFile(root: runtimeRoot, relativePath: relative);
    }

    if (!_servePresenter) return null;
    if (path == '/' || path == '/UltimateReport/apps/presenter/') {
      return File('${presenterRoot.path}/index.html');
    }
    if (path.startsWith(_presenterRoutePrefix)) {
      final relative = path.substring(_presenterRoutePrefix.length);
      return _safeFile(
        root: presenterRoot,
        relativePath: relative.isEmpty ? 'index.html' : relative,
      );
    }
    if (path.startsWith('/')) {
      return _safeFile(root: presenterRoot, relativePath: path.substring(1));
    }
    return null;
  }

  File? _safeFile({required Directory root, required String relativePath}) {
    if (!_isSafeRelativePath(relativePath)) return null;
    return File('${root.path}/$relativePath');
  }

  bool _isSafeRelativePath(String relativePath) {
    return relativePath.isNotEmpty &&
        !relativePath.contains('\\') &&
        !relativePath.split('/').contains('..');
  }

  Future<void> _sendNotFound(HttpRequest request) async {
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  Future<void> _sendMethodNotAllowed(HttpRequest request) async {
    request.response.statusCode = HttpStatus.methodNotAllowed;
    request.response.headers.set('Allow', 'GET, HEAD, OPTIONS');
    await request.response.close();
  }

  void _addCommonHeaders(HttpResponse response) {
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS')
      ..set('Access-Control-Allow-Headers', '*')
      ..set('Cache-Control', 'no-store');
  }

  ContentType _contentType(String path) {
    if (path.endsWith('.html')) {
      return ContentType.html;
    }
    if (path.endsWith('.json')) {
      return ContentType.json;
    }
    if (path.endsWith('.js')) {
      return ContentType('application', 'javascript', charset: 'utf-8');
    }
    if (path.endsWith('.css')) {
      return ContentType('text', 'css', charset: 'utf-8');
    }
    if (path.endsWith('.png')) {
      return ContentType('image', 'png');
    }
    if (path.endsWith('.svg')) {
      return ContentType('image', 'svg+xml', charset: 'utf-8');
    }
    if (path.endsWith('.wasm')) {
      return ContentType('application', 'wasm');
    }
    return ContentType.binary;
  }
}

String _validatedSessionId(String value) {
  final sessionId = value.trim();
  if (sessionId.isEmpty ||
      sessionId == '.' ||
      sessionId == '..' ||
      !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(sessionId)) {
    throw const BridgeRuntimeException(
      BridgeRuntimeErrorCodes.runtimeSessionInvalid,
      'Runtime session ID is invalid.',
    );
  }
  return sessionId;
}
