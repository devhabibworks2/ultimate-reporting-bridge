import 'dart:async';

import 'package:reporting_bridge/reporting_bridge.dart';

import '../ui/presenter_export_support.dart';

typedef PresenterLifecycleCallback =
    void Function(PresenterWebLifecycleEvent event);

class PresenterSurfaceBinding {
  PresenterSurfaceBinding({
    PresenterWebExportTransport? exportTransport,
    PresenterPdfExportCache? cache,
  }) : _exportTransport = exportTransport ?? PresenterWebExportTransport(),
       _cache = cache ?? PresenterPdfExportCache();

  final PresenterWebExportTransport _exportTransport;
  final PresenterPdfExportCache _cache;
  Future<Object?> Function(String source)? _evaluateJavaScript;
  Future<void> Function()? _reload;
  PresenterLifecycleCallback? _lifecycleCallback;
  String? _sessionId;
  String? _templateName;

  bool get attached => _evaluateJavaScript != null;

  void attach({
    required String sessionId,
    required String templateName,
    required Future<Object?> Function(String source) evaluateJavaScript,
    required Future<void> Function() reload,
    required PresenterLifecycleCallback onLifecycle,
  }) {
    _sessionId = sessionId;
    _templateName = templateName;
    _evaluateJavaScript = evaluateJavaScript;
    _reload = reload;
    _lifecycleCallback = onLifecycle;
    _cache.bindSession(sessionId);
  }

  bool acceptMessage(Object? message) {
    final lifecycle = PresenterWebLifecycleEvent.tryParse(message);
    if (lifecycle != null) {
      final current = _sessionId;
      if (current != null && lifecycle.sessionId == current) {
        _lifecycleCallback?.call(lifecycle);
      }
      return true;
    }
    return _exportTransport.acceptMessage(message);
  }

  Future<PresenterCachedPdf> exportPdf() {
    final evaluate = _evaluateJavaScript;
    final sessionId = _sessionId;
    if (evaluate == null || sessionId == null) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Presenter surface is not attached.',
      );
    }
    return _cache.resolve(() async {
      final result = await _exportTransport.exportPdf(
        evaluateJavaScript: (source) async {
          await evaluate(source);
        },
      );
      return PresenterCachedPdf(
        bytes: result.bytes,
        filename: buildPresenterPdfFilename(
          templateName: _templateName ?? 'report',
          timestamp: DateTime.now(),
          bridgeFilename: result.filename,
        ),
      );
    });
  }

  Future<void> reload() async {
    _cache.clear();
    await _reload?.call();
  }

  void detachSession(String sessionId) {
    if (_sessionId == sessionId) detach();
  }

  void detach() {
    _evaluateJavaScript = null;
    _reload = null;
    _lifecycleCallback = null;
    _sessionId = null;
    _templateName = null;
    _cache.clear();
  }

  void dispose() {
    detach();
    _exportTransport.dispose();
  }
}
