import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'bridge_runtime_error.dart';
import 'bridge_web_channel.dart';

class PresenterWebExportResult {
  const PresenterWebExportResult({
    required this.bytes,
    required this.filename,
    required this.correlationId,
  });

  final Uint8List bytes;
  final String filename;
  final String correlationId;
}

typedef PresenterJavaScriptEvaluator =
    Future<void> Function(String javaScriptSource);

/// Owns the correlated Presenter WebView PDF-export protocol.
///
/// Hosts provide only a JavaScript evaluator and forward raw callback payloads.
/// This transport owns request envelopes, correlation IDs, timeouts, callback
/// validation, chunk assembly, size limits, base64 decoding, and safe filenames.
class PresenterWebExportTransport {
  PresenterWebExportTransport({
    this.timeout = const Duration(seconds: 25),
    this.maxChunkCount = 4096,
    this.maxByteLength = 100 * 1024 * 1024,
    String Function()? correlationIdFactory,
  }) : _correlationIdFactory =
           correlationIdFactory ?? _defaultCorrelationIdFactory {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
    if (maxChunkCount <= 0) {
      throw ArgumentError.value(
        maxChunkCount,
        'maxChunkCount',
        'Must be positive.',
      );
    }
    if (maxByteLength <= 0) {
      throw ArgumentError.value(
        maxByteLength,
        'maxByteLength',
        'Must be positive.',
      );
    }
  }

  final Duration timeout;
  final int maxChunkCount;
  final int maxByteLength;
  final String Function() _correlationIdFactory;
  final Map<String, _PendingExport> _pending = <String, _PendingExport>{};

  bool _disposed = false;

  int get maxBase64Length => ((maxByteLength + 2) ~/ 3) * 4;
  bool get hasPendingExport => _pending.isNotEmpty;

  Future<PresenterWebExportResult> exportPdf({
    required PresenterJavaScriptEvaluator evaluateJavaScript,
  }) async {
    if (_disposed) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Presenter WebView export transport is disposed.',
      );
    }

    final correlationId = _correlationIdFactory().trim();
    if (correlationId.isEmpty || _pending.containsKey(correlationId)) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Presenter export correlation ID is invalid or already active.',
      );
    }

    final completer = Completer<PresenterWebExportResult>();
    final pending = _PendingExport(completer: completer);
    _pending[correlationId] = pending;
    pending.timer = Timer(timeout, () {
      _completeError(
        correlationId,
        'Timed out waiting for Presenter PDF export.',
      );
    });

    final payload = <String, dynamic>{
      'channel': bridgeWebMessageChannel,
      'method': BridgeWebMethods.exportPdf,
      'correlationId': correlationId,
    };
    final source =
        'window.postMessage(${jsonEncode(payload)}, window.location.origin);';

    try {
      await evaluateJavaScript(source);
    } catch (error, stackTrace) {
      _removePending(correlationId);
      Error.throwWithStackTrace(
        BridgeRuntimeException(
          BridgeRuntimeErrorCodes.runtimeSessionInvalid,
          'Failed to send Presenter PDF export request: $error',
        ),
        stackTrace,
      );
    }

    return completer.future;
  }

  /// Accepts a callback payload from Presenter.
  ///
  /// Returns `true` only when the payload belongs to an active export call.
  bool acceptMessage(Object? rawPayload) {
    final message = _decodeMessage(rawPayload);
    if (message == null ||
        message['channel'] != bridgeWebMessageChannel ||
        message['method'] != BridgeWebMethods.exportPdf) {
      return false;
    }

    final correlationId = message['correlationId']?.toString().trim() ?? '';
    final pending = _pending[correlationId];
    if (correlationId.isEmpty || pending == null) return false;

    final type = message['type']?.toString();
    if (type == 'chunk') {
      _acceptChunk(correlationId, pending, message);
      return true;
    }
    if (type == 'result') {
      _acceptResult(correlationId, message);
      return true;
    }
    return false;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final correlationId in _pending.keys.toList(growable: false)) {
      _completeError(
        correlationId,
        'Presenter WebView export transport was disposed.',
      );
    }
  }

  void _acceptChunk(
    String correlationId,
    _PendingExport pending,
    Map<String, dynamic> message,
  ) {
    final chunkCount = _asInt(message['chunkCount']);
    final chunkIndex = _asInt(message['chunkIndex']);
    final chunk = message['base64Chunk'];
    final byteLength = _asInt(message['byteLength']);
    final filename = _safePdfFilename(message['filename']?.toString());

    if (message['ok'] == false) {
      _completeError(
        correlationId,
        message['error']?.toString() ?? 'Presenter PDF export failed.',
      );
      return;
    }
    if (chunkCount == null ||
        chunkCount <= 0 ||
        chunkCount > maxChunkCount ||
        chunkIndex == null ||
        chunkIndex < 0 ||
        chunkIndex >= chunkCount ||
        chunk is! String ||
        chunk.length > maxBase64Length ||
        (byteLength != null &&
            (byteLength < 0 || byteLength > maxByteLength))) {
      _completeError(correlationId, 'Invalid Presenter PDF export chunk.');
      return;
    }

    final accumulator = pending.accumulator;
    if (accumulator == null) {
      pending.accumulator = _ChunkAccumulator(
        filename: filename,
        chunkCount: chunkCount,
        byteLength: byteLength,
      );
    } else if (!accumulator.matches(
      filename: filename,
      chunkCount: chunkCount,
      byteLength: byteLength,
    )) {
      _completeError(
        correlationId,
        'Presenter PDF export chunk metadata changed during transfer.',
      );
      return;
    }

    final active = pending.accumulator!;
    if (!active.accept(
      index: chunkIndex,
      chunk: chunk,
      maxEncodedLength: maxBase64Length,
    )) {
      _completeError(
        correlationId,
        'Presenter PDF export chunk content is invalid or inconsistent.',
      );
      return;
    }
    if (!active.isComplete) return;

    _completeDecoded(
      correlationId: correlationId,
      filename: active.filename,
      base64Payload: active.join(),
      expectedByteLength: active.byteLength,
    );
  }

  void _acceptResult(String correlationId, Map<String, dynamic> message) {
    if (message['ok'] != true) {
      _completeError(
        correlationId,
        message['error']?.toString() ?? 'Presenter PDF export failed.',
      );
      return;
    }

    final payload = message['base64'];
    if (payload is! String || payload.isEmpty) {
      _completeError(
        correlationId,
        'Presenter PDF export did not return bytes.',
      );
      return;
    }

    _completeDecoded(
      correlationId: correlationId,
      filename: _safePdfFilename(message['filename']?.toString()),
      base64Payload: payload,
      expectedByteLength: _asInt(message['byteLength']),
    );
  }

  void _completeDecoded({
    required String correlationId,
    required String filename,
    required String base64Payload,
    required int? expectedByteLength,
  }) {
    if (base64Payload.length > maxBase64Length) {
      _completeError(
        correlationId,
        'Presenter PDF export exceeds the allowed size.',
      );
      return;
    }
    if (expectedByteLength != null &&
        (expectedByteLength < 0 || expectedByteLength > maxByteLength)) {
      _completeError(
        correlationId,
        'Presenter PDF export byte length is invalid.',
      );
      return;
    }

    late final Uint8List bytes;
    try {
      bytes = base64Decode(base64Payload);
    } on FormatException {
      _completeError(
        correlationId,
        'Presenter PDF export returned invalid base64.',
      );
      return;
    }

    if (bytes.length > maxByteLength ||
        (expectedByteLength != null && expectedByteLength != bytes.length)) {
      _completeError(
        correlationId,
        'Presenter PDF export byte length does not match.',
      );
      return;
    }

    final pending = _removePending(correlationId);
    if (pending == null || pending.completer.isCompleted) return;
    pending.completer.complete(
      PresenterWebExportResult(
        bytes: bytes,
        filename: filename,
        correlationId: correlationId,
      ),
    );
  }

  void _completeError(String correlationId, String message) {
    final pending = _removePending(correlationId);
    if (pending == null || pending.completer.isCompleted) return;
    pending.completer.completeError(
      BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        message,
      ),
    );
  }

  _PendingExport? _removePending(String correlationId) {
    final pending = _pending.remove(correlationId);
    pending?.timer?.cancel();
    return pending;
  }
}

class _PendingExport {
  _PendingExport({required this.completer});

  final Completer<PresenterWebExportResult> completer;
  Timer? timer;
  _ChunkAccumulator? accumulator;
}

class _ChunkAccumulator {
  _ChunkAccumulator({
    required this.filename,
    required this.chunkCount,
    required this.byteLength,
  }) : chunks = List<String?>.filled(chunkCount, null);

  final String filename;
  final int chunkCount;
  final int? byteLength;
  final List<String?> chunks;
  int encodedLength = 0;

  bool get isComplete => chunks.every((chunk) => chunk != null);

  bool matches({
    required String filename,
    required int chunkCount,
    required int? byteLength,
  }) {
    return this.filename == filename &&
        this.chunkCount == chunkCount &&
        this.byteLength == byteLength;
  }

  bool accept({
    required int index,
    required String chunk,
    required int maxEncodedLength,
  }) {
    final existing = chunks[index];
    if (existing != null) return existing == chunk;
    if (encodedLength + chunk.length > maxEncodedLength) return false;
    chunks[index] = chunk;
    encodedLength += chunk.length;
    return true;
  }

  String join() => chunks.map((chunk) => chunk ?? '').join();
}

Map<String, dynamic>? _decodeMessage(Object? rawPayload) {
  Object? decoded = rawPayload;
  if (rawPayload is String) {
    if (rawPayload.trim().isEmpty) return null;
    try {
      decoded = jsonDecode(rawPayload);
    } on FormatException {
      return null;
    }
  }
  if (decoded is! Map) return null;
  return decoded.map((key, value) => MapEntry(key.toString(), value));
}

int? _asInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

String _safePdfFilename(String? raw) {
  var name = (raw ?? '').trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (name.isEmpty) name = 'report_preview.pdf';
  if (!name.toLowerCase().endsWith('.pdf')) name = '$name.pdf';
  return name;
}

int _correlationSequence = 0;

String _defaultCorrelationIdFactory() {
  _correlationSequence = (_correlationSequence + 1) & 0x7fffffff;
  return 'web-${DateTime.now().microsecondsSinceEpoch}-$_correlationSequence';
}
