import 'package:flutter/foundation.dart';

/// Severity for Bridge diagnostic records.
enum BridgeLogLevel { debug, info, warning, error }

/// Stable diagnostic channel names exposed to Host developers.
enum BridgeLogCategory { api, flow, print, persistence, presenter, lifecycle }

typedef BridgeLogSink = void Function(BridgeLogRecord record);
typedef BridgeLogPrinter = void Function(String line);

/// One structured Bridge diagnostic record.
///
/// Bridge-owned API diagnostics intentionally exclude request/response bodies
/// and header values. Hosts may add application-specific context in their own
/// sink when that is safe for their environment.
final class BridgeLogRecord {
  BridgeLogRecord({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.event,
    required this.message,
    Map<String, Object?> details = const <String, Object?>{},
    this.error,
    this.stackTrace,
  }) : details = Map<String, Object?>.unmodifiable(details);

  final DateTime timestamp;
  final BridgeLogLevel level;
  final BridgeLogCategory category;
  final String event;
  final String message;
  final Map<String, Object?> details;
  final Object? error;
  final StackTrace? stackTrace;

  String toConsoleLine() {
    final buffer = StringBuffer()
      ..write('[URB][Bridge]')
      ..write('[${category.name.toUpperCase()}]')
      ..write('[${level.name.toUpperCase()}] ')
      ..write(event)
      ..write(' - ')
      ..write(_sanitizeConsoleText(message));
    if (details.isNotEmpty) {
      final keys = details.keys.toList()..sort();
      buffer
        ..write(' {')
        ..write(
          keys.map((key) => '$key=${_consoleValue(details[key])}').join(', '),
        )
        ..write('}');
    }
    final capturedError = error;
    if (capturedError != null) {
      buffer
        ..write(' errorType=${capturedError.runtimeType}')
        ..write(' error=${_safeErrorSummary(capturedError)}');
    }
    return buffer.toString();
  }
}

/// Opt-in diagnostics for API, flow, and print operations.
///
/// Diagnostics are disabled by default. Use [BridgeDiagnostics.console] for a
/// ready-to-use development trace, or provide a structured [BridgeLogSink].
/// Diagnostic callback failures are swallowed and never change report flow.
final class BridgeDiagnostics {
  const BridgeDiagnostics({
    this.sink,
    this.minimumLevel = BridgeLogLevel.debug,
    this.logApiRequests = true,
    this.logFlowErrors = true,
    this.logPrintActions = true,
  });

  const BridgeDiagnostics.disabled()
    : sink = null,
      minimumLevel = BridgeLogLevel.error,
      logApiRequests = false,
      logFlowErrors = false,
      logPrintActions = false;

  factory BridgeDiagnostics.console({
    BridgeLogLevel minimumLevel = BridgeLogLevel.debug,
    bool logApiRequests = true,
    bool logFlowErrors = true,
    bool logPrintActions = true,
    BridgeLogPrinter? printer,
  }) {
    final BridgeLogPrinter output = printer ?? (line) => debugPrint(line);
    return BridgeDiagnostics(
      minimumLevel: minimumLevel,
      logApiRequests: logApiRequests,
      logFlowErrors: logFlowErrors,
      logPrintActions: logPrintActions,
      sink: (record) => output(record.toConsoleLine()),
    );
  }

  final BridgeLogSink? sink;
  final BridgeLogLevel minimumLevel;
  final bool logApiRequests;
  final bool logFlowErrors;
  final bool logPrintActions;

  bool get enabled => sink != null;

  void emit({
    required BridgeLogLevel level,
    required BridgeLogCategory category,
    required String event,
    required String message,
    Map<String, Object?> details = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    final output = sink;
    if (output == null || level.index < minimumLevel.index) return;
    if (category == BridgeLogCategory.api && !logApiRequests) return;
    if (category == BridgeLogCategory.flow && !logFlowErrors) return;
    if (category == BridgeLogCategory.print && !logPrintActions) return;
    try {
      output(
        BridgeLogRecord(
          timestamp: DateTime.now().toUtc(),
          level: level,
          category: category,
          event: event,
          message: message,
          details: details,
          error: error,
          stackTrace: stackTrace,
        ),
      );
    } catch (_) {
      // Diagnostics must never change Bridge behavior.
    }
  }

  Future<T> traceApi<T>({
    required String operation,
    required String method,
    required Uri uri,
    required Future<T> Function() action,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    final safeUri = safeBridgeLogUri(uri);
    return trace<T>(
      category: BridgeLogCategory.api,
      operation: operation,
      message: '$method $safeUri',
      details: <String, Object?>{'method': method, 'uri': safeUri, ...details},
      action: action,
      enabledForCategory: logApiRequests,
    );
  }

  Future<T> tracePrint<T>({
    required String operation,
    required Future<T> Function() action,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    return trace<T>(
      category: BridgeLogCategory.print,
      operation: operation,
      message: 'Print operation',
      details: details,
      action: action,
      enabledForCategory: logPrintActions,
    );
  }

  Future<T> trace<T>({
    required BridgeLogCategory category,
    required String operation,
    required String message,
    required Future<T> Function() action,
    Map<String, Object?> details = const <String, Object?>{},
    bool enabledForCategory = true,
  }) async {
    if (!enabled || !enabledForCategory) return action();
    final stopwatch = Stopwatch()..start();
    emit(
      level: BridgeLogLevel.debug,
      category: category,
      event: '$operation.start',
      message: message,
      details: details,
    );
    try {
      final value = await action();
      stopwatch.stop();
      emit(
        level: BridgeLogLevel.info,
        category: category,
        event: '$operation.success',
        message: message,
        details: <String, Object?>{
          ...details,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      return value;
    } catch (error, stackTrace) {
      stopwatch.stop();
      emit(
        level: BridgeLogLevel.error,
        category: category,
        event: '$operation.error',
        message: message,
        details: <String, Object?>{
          ...details,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
        error: error,
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void flowFailure({
    required String operation,
    required String code,
    String? diagnostic,
    Map<String, Object?> details = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!logFlowErrors) return;
    emit(
      level: BridgeLogLevel.error,
      category: BridgeLogCategory.flow,
      event: '$operation.failure',
      message: diagnostic == null || diagnostic.isEmpty
          ? code
          : '$code: $diagnostic',
      details: <String, Object?>{'code': code, ...details},
      error: error,
      stackTrace: stackTrace,
    );
  }
}

/// Returns a URI safe for diagnostics.
///
/// User-info, fragments, and query values are omitted. Query names are kept so
/// developers can identify request shape without leaking values.
String safeBridgeLogUri(Uri uri) {
  final queryNames = uri.queryParametersAll.keys.toList()..sort();
  final base = Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  ).toString();
  if (queryNames.isEmpty) return base;
  final safeQuery = queryNames
      .map((key) => '${Uri.encodeQueryComponent(key)}=<redacted>')
      .join('&');
  return '$base?$safeQuery';
}

String _sanitizeConsoleText(String value) {
  var sanitized = value.replaceAllMapped(RegExp(r'https?://[^\s)\]]+'), (
    match,
  ) {
    final raw = match.group(0)!;
    final parsed = Uri.tryParse(raw);
    return parsed == null ? raw : safeBridgeLogUri(parsed);
  });
  sanitized = sanitized.replaceAll(
    RegExp(r'\bBearer\s+[A-Za-z0-9._~+\-/]+=*', caseSensitive: false),
    'Bearer <redacted>',
  );
  sanitized = sanitized.replaceAllMapped(
    RegExp(
      r'\b(authorization|password|passwd|token|access_token|refresh_token|'
      r'api[_-]?key|secret)\s*[:=]\s*([^\s,;]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=<redacted>',
  );
  return sanitized.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _safeErrorSummary(Object error) =>
    _sanitizeConsoleText(error.toString());

String _consoleValue(Object? value) {
  if (value == null) return 'null';
  if (value is String) return _sanitizeConsoleText(value);
  if (value is Iterable) {
    final items = value.map((item) => _sanitizeConsoleText(item.toString()));
    return '[${items.join(',')}]';
  }
  if (value is Map) return '{keys:${value.keys.join(',')}}';
  return _sanitizeConsoleText(value.toString());
}
