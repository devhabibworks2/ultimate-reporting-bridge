enum ReportFlowFailureCode {
  flowAlreadyActive,
  noCompatibleTemplates,
  templateSelectionRequired,
  templateSyncFailed,
  presenterSyncFailed,
  previewPreparationFailed,
  previewLoadFailed,
  presenterIncompatible,
  renderTimedOut,
  renderFailed,
  persistenceFailed,
  actionDenied,
  exportUnavailable,
  exportInProgress,
  operationInProgress,
  exportFailed,
  developmentSupportFailed,
  cacheClearFailed,
  printUnavailable,
  printSetupRequired,
  printAppNotInstalled,
  printUnsupportedContract,
  printUnsupportedPaperConversion,
  savedBluetoothPrinterUnavailable,
  bluetoothPermissionDenied,
  bluetoothPrinterConnectionFailed,
  tcpPrinterConnectionTimeout,
  tcpPrinterHostNotFound,
  tcpPrinterConnectionRefused,
  tcpPrinterSendFailed,
  tcpPrinterConnectionFailed,
  thermalPrinterConnectionFailed,
  printFailed,
  cleanupFailed,
  disposed,
  unknown,
}

class ReportFlowFailure implements Exception {
  const ReportFlowFailure({
    required this.code,
    this.diagnostic,
    this.technicalCode,
    this.technicalCategory,
    this.technicalPath,
    this.details = const <String, Object?>{},
  });

  factory ReportFlowFailure.presenterRenderPayload(
    Map<String, dynamic> payload,
  ) {
    String? text(Object? value) {
      final normalized = value?.toString().trim();
      return normalized == null || normalized.isEmpty ? null : normalized;
    }

    final message =
        text(payload['message']) ??
        text(payload['error']) ??
        'Presenter render failed.';
    final source = text(payload['source']);
    final sessionId = text(payload['sessionId']);

    return ReportFlowFailure(
      code: ReportFlowFailureCode.renderFailed,
      diagnostic: message,
      technicalCode: text(payload['code']),
      technicalCategory: text(payload['category']),
      technicalPath: text(payload['path']),
      details: <String, Object?>{
        if (source != null) 'source': source,
        if (sessionId != null) 'sessionId': sessionId,
      },
    );
  }

  final ReportFlowFailureCode code;

  /// Technical diagnostic suitable for a details surface or logs.
  ///
  /// User-facing primary copy remains localized by ReportFlowStrings.
  final String? diagnostic;

  /// Optional source-specific stable code, such as the Presenter failure code
  /// or a Bridge runtime error code.
  final String? technicalCode;

  /// Optional source-specific failure category.
  final String? technicalCategory;

  /// Optional source path for document/render failures.
  final String? technicalPath;

  /// Small, allow-listed diagnostic context. Do not place secrets, headers,
  /// credentials, or arbitrary untrusted payloads here.
  final Map<String, Object?> details;

  bool get hasTechnicalDetails =>
      diagnostic != null ||
      technicalCode != null ||
      technicalCategory != null ||
      technicalPath != null ||
      details.isNotEmpty;

  @override
  String toString() => 'ReportFlowFailure(${code.name})';
}
