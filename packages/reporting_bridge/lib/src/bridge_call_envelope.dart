/// Optional metadata for correlated / timed bridge calls.
class BridgeCallEnvelope {
  const BridgeCallEnvelope({required this.correlationId, this.timeoutMs});

  final String correlationId;
  final int? timeoutMs;

  Duration resolveTimeout(Duration fallback) {
    if (timeoutMs == null || timeoutMs! <= 0) {
      return fallback;
    }
    return Duration(milliseconds: timeoutMs!);
  }

  Map<String, dynamic> wrap(Map<String, dynamic> payload) {
    return <String, dynamic>{
      ...payload,
      'correlationId': correlationId,
      if (timeoutMs != null) 'timeoutMs': timeoutMs,
    };
  }

  static BridgeCallEnvelope? tryParse(Map<dynamic, dynamic>? raw) {
    if (raw == null) {
      return null;
    }
    final id = raw['correlationId'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    final t = raw['timeoutMs'];
    return BridgeCallEnvelope(
      correlationId: id,
      timeoutMs: t is int ? t : null,
    );
  }
}
