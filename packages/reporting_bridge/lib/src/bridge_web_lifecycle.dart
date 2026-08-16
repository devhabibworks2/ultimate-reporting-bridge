import 'dart:convert';

import 'bridge_web_channel.dart';

enum PresenterWebLifecycleState { connected, loading, ready, failed }

class PresenterWebLifecycleEvent {
  const PresenterWebLifecycleEvent({
    required this.state,
    required this.name,
    required this.payload,
    required this.contractVersion,
    this.sessionId,
  });

  final PresenterWebLifecycleState state;
  final String name;
  final Map<String, dynamic> payload;
  final int contractVersion;
  final String? sessionId;

  static PresenterWebLifecycleEvent? tryParse(Object? raw) {
    Object? decoded = raw;
    if (raw is String) {
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        return null;
      }
    }
    if (decoded is! Map) return null;
    final map = decoded.map((key, value) => MapEntry(key.toString(), value));
    if (map['channel'] != bridgeWebMessageChannel ||
        map['method'] != BridgeWebMethods.presenterLifecycle) {
      return null;
    }
    final event = map['event']?.toString() ?? '';
    final state = switch (event) {
      'onPresenterReady' => PresenterWebLifecycleState.connected,
      'onRenderStarted' => PresenterWebLifecycleState.loading,
      'onRenderCompleted' => PresenterWebLifecycleState.ready,
      'onRenderFailed' => PresenterWebLifecycleState.failed,
      _ => null,
    };
    if (state == null) return null;
    final rawPayload = map['payload'];
    final payload = rawPayload is Map
        ? rawPayload.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    final rawVersion = map['contractVersion'] ?? payload['contractVersion'];
    final contractVersion = rawVersion is int
        ? rawVersion
        : int.tryParse(rawVersion?.toString() ?? '');
    if (contractVersion == null || contractVersion <= 0) return null;
    final sessionId = payload['sessionId']?.toString().trim();
    return PresenterWebLifecycleEvent(
      state: state,
      name: event,
      payload: Map<String, dynamic>.unmodifiable(payload),
      contractVersion: contractVersion,
      sessionId: sessionId == null || sessionId.isEmpty ? null : sessionId,
    );
  }
}
