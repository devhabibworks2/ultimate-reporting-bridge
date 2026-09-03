class BridgeRuntimeException implements Exception {
  const BridgeRuntimeException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'BridgeRuntimeException($code): $message';
}

abstract final class BridgeRuntimeErrorCodes {
  static const String offlineAssetsNotReady = 'OFFLINE_ASSETS_NOT_READY';
  static const String noTemplateAvailable = 'NO_TEMPLATE_AVAILABLE';
  static const String presenterVersionTooOld = 'PRESENTER_VERSION_TOO_OLD';
  static const String templateVersionTooOld = 'TEMPLATE_VERSION_TOO_OLD';
  static const String localhostServerUnavailable =
      'LOCALHOST_SERVER_UNAVAILABLE';
  static const String runtimeSessionInvalid = 'RUNTIME_SESSION_INVALID';
  static const String runtimeFileWriteFailed = 'RUNTIME_FILE_WRITE_FAILED';
  static const String templateDocumentInvalid = 'TEMPLATE_DOCUMENT_INVALID';
  static const String staleTemplateSelection = 'STALE_TEMPLATE_SELECTION';
}
