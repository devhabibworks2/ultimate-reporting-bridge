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
  String? _activeSessionId;
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
    if (_server != null) {
      await stop();
    }

    final activeSessionId = _validatedSessionId(sessionId);
    if (servePresenter &&
        !await File('${presenterRoot.path}/index.html').exists()) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.offlineAssetsNotReady,
        'Cached Presenter index.html is required before localhost serving.',
      );
    }

    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        portPolicy.preferredPort,
      );
      _server = server;
      _activeSessionId = activeSessionId;
      _servePresenter = servePresenter;
      server.listen(_handleRequest);
      final baseUrl = 'http://127.0.0.1:${server.port}';
      return LocalServerHandle(
        port: server.port,
        baseUrl: baseUrl,
        presenterUrl: servePresenter
            ? '$baseUrl/UltimateReport/apps/presenter/index.html?sessionId=$activeSessionId'
            : baseUrl,
        stop: stop,
      );
    } on Object catch (error) {
      await stop();
      throw BridgeRuntimeException(
        BridgeRuntimeErrorCodes.localhostServerUnavailable,
        'Failed to start local Presenter server: $error',
      );
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _activeSessionId = null;
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

  File? _resolveFile(String path) {
    if (path.startsWith('/runtime/')) {
      final relative = path.substring('/runtime/'.length);
      final separator = relative.indexOf('/');
      final activeSessionId = _activeSessionId;
      if (activeSessionId == null ||
          separator <= 0 ||
          relative.substring(0, separator) != activeSessionId) {
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
    if (relativePath.isEmpty ||
        relativePath.contains('\\') ||
        relativePath.split('/').contains('..')) {
      return null;
    }
    return File('${root.path}/$relativePath');
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
