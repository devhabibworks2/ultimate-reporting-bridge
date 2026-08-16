import 'dart:async';

import 'bridge_runtime_error.dart';
import 'bridge_template_sync.dart';

enum BridgeHeaderOperation {
  probeApi,
  fetchSystems,
  syncTemplates,
  listTemplates,
  syncPresenter,
  prepareSession,
}

class BridgeHeaderContext {
  const BridgeHeaderContext({
    required this.operation,
    required this.apiBaseUrl,
    this.systemCode,
    this.systemId,
    this.branchId,
    this.userId,
    this.systemUnit,
    this.reportType,
    this.sessionId,
  });

  final BridgeHeaderOperation operation;
  final Uri apiBaseUrl;
  final String? systemCode;
  final int? systemId;
  final String? branchId;
  final String? userId;
  final String? systemUnit;
  final String? reportType;
  final String? sessionId;
}

typedef BridgeHeadersProvider =
    FutureOr<Map<String, String>> Function(BridgeHeaderContext context);

Future<Map<String, String>> resolveBridgeHeaders({
  required BridgeHeaderContext context,
  BridgeHeadersProvider? provider,
  Map<String, String> fallback = const <String, String>{},
}) async {
  final raw = provider == null ? fallback : await provider(context);
  for (final entry in raw.entries) {
    if (_containsLineBreak(entry.key) || _containsLineBreak(entry.value)) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Bridge header names and values must not contain line breaks.',
      );
    }
  }
  return Map<String, String>.unmodifiable(filterPresenterBridgeHeaders(raw));
}

bool _containsLineBreak(String value) =>
    value.contains('\r') || value.contains('\n');
