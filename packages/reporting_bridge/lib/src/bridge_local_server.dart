import 'dart:io';
import 'dart:typed_data';

import 'bridge_presenter_resource_cache.dart';
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
    this.resourceCacheStore,
  });

  final Directory presenterRoot;
  final Directory runtimeRoot;
  final PresenterResourceCacheStore? resourceCacheStore;
  static const String _presenterRoutePrefix = '/UltimateReport/apps/presenter/';
  HttpServer? _server;
  final Set<String> _sessionIds = <String>{};
  bool _servePresenter = false;

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

  Future<LocalServerHandle> _start({
    required String sessionId,
    required PortPolicy portPolicy,
    required bool servePresenter,
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
        _replaceRouting(servePresenter: servePresenter);
      }
    } else if (existing != null &&
        !_isCompatibleReuse(
          server: existing,
          portPolicy: portPolicy,
          servePresenter: servePresenter,
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
        server.listen(_handleRequest);
      }

      _sessionIds.add(activeSessionId);
      final baseUrl = 'http://127.0.0.1:${server.port}';
      return LocalServerHandle(
        port: server.port,
        baseUrl: baseUrl,
        presenterUrl: servePresenter
            ? '$baseUrl/UltimateReport/apps/presenter/index.html?sessionId=$activeSessionId'
            : baseUrl,
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

  void _replaceRouting({required bool servePresenter}) {
    _servePresenter = servePresenter;
  }

  bool _isCompatibleReuse({
    required HttpServer server,
    required PortPolicy portPolicy,
    required bool servePresenter,
  }) {
    if (portPolicy.preferredPort != 0 &&
        portPolicy.preferredPort != server.port) {
      return false;
    }
    return _servePresenter == servePresenter;
  }

  Future<void> releaseSession(String sessionId) async {
    _sessionIds.remove(_validatedSessionId(sessionId));
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _sessionIds.clear();
    _servePresenter = false;
    await server?.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    _addCommonHeaders(request.response);
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }
    late final String path;
    try {
      path = Uri.decodeComponent(request.uri.path);
    } on FormatException {
      await _sendNotFound(request);
      return;
    }

    if (path.startsWith('/runtime/')) {
      final segments = path.split('/');
      if (segments.length >= 4 && segments[3] == 'resource-cache') {
        await _handleResourceCacheRequest(request, segments);
        return;
      }
    }

    if (request.method != 'GET' && request.method != 'HEAD') {
      await _sendMethodNotAllowed(request);
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

  Future<void> _handleResourceCacheRequest(
    HttpRequest request,
    List<String> segments,
  ) async {
    if (segments.length < 3 || !_sessionIds.contains(segments[2])) {
      await _sendNotFound(request);
      return;
    }
    if (segments.length != 5 || segments[4].isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final key = segments[4];
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(key)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final store = resourceCacheStore;
    if (store == null) {
      await _sendNotFound(request);
      return;
    }

    if (request.method == 'GET') {
      final bytes = await store.read(key);
      if (bytes == null) {
        await _sendNotFound(request);
        return;
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.binary
        ..contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
      return;
    }
    if (request.method != 'PUT') {
      await _sendMethodNotAllowed(request);
      return;
    }

    const maxEntryBytes = 5 * 1024 * 1024;
    final body = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in request) {
      length += chunk.length;
      if (length > maxEntryBytes) {
        request.response.statusCode = HttpStatus.requestEntityTooLarge;
        await request.response.close();
        return;
      }
      body.add(chunk);
    }
    try {
      await store.write(key, body.takeBytes());
    } on ArgumentError {
      request.response.statusCode = HttpStatus.requestEntityTooLarge;
      await request.response.close();
      return;
    }
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
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
    request.response.headers.set('Allow', 'GET, HEAD, PUT, OPTIONS');
    await request.response.close();
  }

  void _addCommonHeaders(HttpResponse response) {
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, HEAD, PUT, OPTIONS')
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
