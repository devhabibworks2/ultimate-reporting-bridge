import 'dart:async';

import 'package:reporting_bridge/reporting_bridge.dart';

import '../logging/bridge_diagnostics.dart';
import '../ui/presenter_export_support.dart';

typedef PresenterLifecycleCallback =
    void Function(PresenterWebLifecycleEvent event);

class PresenterSurfaceBinding {
  PresenterSurfaceBinding({
    PresenterWebExportTransport? exportTransport,
    PresenterPdfExportCache? cache,
    BridgeDiagnostics diagnostics = const BridgeDiagnostics.disabled(),
  }) : _exportTransport = exportTransport ?? PresenterWebExportTransport(),
       _cache = cache ?? PresenterPdfExportCache(),
       _diagnostics = diagnostics;

  final PresenterWebExportTransport _exportTransport;
  final PresenterPdfExportCache _cache;
  final BridgeDiagnostics _diagnostics;
  Stopwatch? _previewWatch;
  Duration _lastTimingElapsed = Duration.zero;
  String? _timingSessionId;
  Future<Object?> Function(String source)? _evaluateJavaScript;
  Future<void> Function()? _reload;
  PresenterLifecycleCallback? _lifecycleCallback;
  String? _sessionId;
  String? _templateName;

  void beginPreviewTiming(String sessionId) {
    _previewWatch?.stop();
    _previewWatch = Stopwatch()..start();
    _lastTimingElapsed = Duration.zero;
    _timingSessionId = sessionId;
    _markPreviewTiming('surfaceStart');
  }

  void markViewerOpenStarted() => _markPreviewTiming('viewerOpenStarted');

  void markViewerDocumentLoaded() => _markPreviewTiming('viewerDocumentLoaded');

  void markViewerFirstFrame() {
    _markPreviewTiming('viewerFirstFrame');
    _previewWatch?.stop();
  }

  void _markPreviewTiming(String stage) {
    final watch = _previewWatch;
    final sessionId = _timingSessionId;
    if (watch == null || sessionId == null) return;
    final elapsed = watch.elapsed;
    final stageElapsed = elapsed - _lastTimingElapsed;
    _lastTimingElapsed = elapsed;
    _diagnostics.emit(
      level: BridgeLogLevel.debug,
      category: BridgeLogCategory.presenter,
      event: 'previewTiming.$stage',
      message: 'Preview timing stage',
      details: <String, Object?>{
        'sessionId': sessionId,
        'elapsedUs': elapsed.inMicroseconds,
        'stageUs': stageElapsed.inMicroseconds,
      },
    );
  }

  bool get attached => _evaluateJavaScript != null;
  PresenterCachedPdf? get cachedPdf => _cache.value;

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
      if (lifecycle.sessionId == null || lifecycle.sessionId == current) {
        switch (lifecycle.name) {
          case 'onPresenterReady':
            _markPreviewTiming('presenterReady');
          case 'onRenderStarted':
            _markPreviewTiming('renderStarted');
          case 'onRenderCompleted':
            _markPreviewTiming('renderCompleted');
          case 'onRenderFailed':
            _markPreviewTiming('renderFailed');
        }
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
      _markPreviewTiming('exportStarted');
      final result = await _exportTransport.exportPdf(
        evaluateJavaScript: (source) async {
          await evaluate(source);
        },
      );
      _markPreviewTiming('exportCompleted');
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
