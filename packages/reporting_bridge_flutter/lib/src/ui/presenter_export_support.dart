import 'dart:typed_data';

String buildPresenterPdfFilename({
  required String templateName,
  required DateTime timestamp,
  String? bridgeFilename,
}) {
  final safeTemplate = _sanitize(templateName);
  final date =
      '${timestamp.year.toString().padLeft(4, '0')}'
      '${timestamp.month.toString().padLeft(2, '0')}'
      '${timestamp.day.toString().padLeft(2, '0')}';
  final time =
      '${timestamp.hour.toString().padLeft(2, '0')}'
      '${timestamp.minute.toString().padLeft(2, '0')}'
      '${timestamp.second.toString().padLeft(2, '0')}'
      '${timestamp.millisecond.toString().padLeft(3, '0')}';
  final fallback = _sanitize(
    (bridgeFilename ?? '').replaceFirst(
      RegExp(r'\.pdf$', caseSensitive: false),
      '',
    ),
  );
  final stem = safeTemplate.isNotEmpty
      ? safeTemplate
      : (fallback.isNotEmpty ? fallback : 'report');
  return '${stem}_${date}_$time.pdf';
}

String _sanitize(String value) => value
    .trim()
    .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
    .replaceAll(RegExp(r'\s+'), '_')
    .replaceAll(RegExp(r'_+'), '_')
    .replaceAll(RegExp(r'^[._]+|[._]+$'), '');

class PresenterCachedPdf {
  const PresenterCachedPdf({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

class PresenterPdfExportCache {
  PresenterCachedPdf? _value;
  Future<PresenterCachedPdf>? _inFlight;
  String? _sessionId;
  int _generation = 0;

  void bindSession(String sessionId) {
    if (_sessionId == sessionId) return;
    _sessionId = sessionId;
    clear();
  }

  Future<PresenterCachedPdf> resolve(
    Future<PresenterCachedPdf> Function() loader,
  ) {
    final cached = _value;
    if (cached != null) return Future<PresenterCachedPdf>.value(cached);
    final running = _inFlight;
    if (running != null) return running;
    final generation = _generation;
    final future = loader();
    _inFlight = future;
    return future
        .then((value) {
          if (_generation == generation) _value = value;
          return value;
        })
        .whenComplete(() {
          if (identical(_inFlight, future)) _inFlight = null;
        });
  }

  void clear() {
    _generation += 1;
    _value = null;
    _inFlight = null;
  }
}
