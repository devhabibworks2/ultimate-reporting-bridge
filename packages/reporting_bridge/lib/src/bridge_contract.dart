/// Versioned integration contract (keep in sync with `bridge_contract.md`).
abstract final class BridgeContract {
  /// Bump when serialized field names or semantics change.
  static const int payloadVersion = 1;

  /// Semantic implementation version used by template compatibility checks.
  /// Keep aligned with the package version in `pubspec.yaml`.
  ///
  /// Presenter bundle `devVersion` is build metadata only. It must not be used
  /// instead of this semantic version or written into template compatibility.
  static const String implementationVersion = '1.0.0';

  /// Single bidirectional [MethodChannel] name (host ↔ presenter).
  static const String channelName = 'com.ultimate_report.bridge/v1';

  /// Default timeout for async host↔presenter calls unless overridden per call.
  static const Duration defaultCallTimeout = Duration(seconds: 30);
}
