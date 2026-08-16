/// WebView/Web embedding channel for host ↔ presenter messaging.
///
/// This is used when Presenter is running as Flutter Web inside a native
/// WebView, where `MethodChannel` is not available.
const bridgeWebMessageChannel = 'urb-bridge-web-v1';

abstract final class BridgeWebMethods {
  /// Host -> presenter: asks presenter to build a PDF from the current preview
  /// and return bytes (base64).
  static const String exportPdf = 'exportPdf';

  /// Presenter -> host: reports render lifecycle readiness.
  static const String presenterLifecycle = 'presenterLifecycle';
}
