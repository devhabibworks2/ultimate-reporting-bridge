/// Presenter → host: export finished successfully.
class BridgeExportCompleted {
  const BridgeExportCompleted({
    required this.contractVersion,
    required this.correlationId,
    required this.kind,
    this.byteLength,
  });

  final int contractVersion;
  final String correlationId;

  /// `printPdf` | `shareImage`
  final String kind;
  final int? byteLength;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'contractVersion': contractVersion,
      'correlationId': correlationId,
      'kind': kind,
      if (byteLength != null) 'byteLength': byteLength,
    };
  }
}

/// Presenter → host: failure surfaced to user / bridge consumer.
class BridgeErrorCallback {
  const BridgeErrorCallback({
    required this.contractVersion,
    required this.correlationId,
    required this.message,
    this.code,
  });

  final int contractVersion;
  final String correlationId;
  final String message;
  final String? code;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'contractVersion': contractVersion,
      'correlationId': correlationId,
      'message': message,
      if (code != null) 'code': code,
    };
  }
}
