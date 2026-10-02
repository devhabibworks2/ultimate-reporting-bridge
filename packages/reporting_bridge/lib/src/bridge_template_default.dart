final class TemplateDefaultHint {
  const TemplateDefaultHint({
    required this.reportType,
    required this.templateCode,
    required this.selectionReason,
  });

  final String reportType;
  final String templateCode;
  final String selectionReason;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'reportType': reportType,
    'templateCode': templateCode,
    'selectionReason': selectionReason,
  };

  static TemplateDefaultHint? tryFromMap(Map<dynamic, dynamic> raw) {
    final reportType = _trimmed(raw['reportType']);
    final templateCode = _trimmed(raw['templateCode']);
    final selectionReason = _trimmed(raw['selectionReason']);
    if (reportType == null || templateCode == null || selectionReason == null) {
      return null;
    }
    return TemplateDefaultHint(
      reportType: reportType,
      templateCode: templateCode,
      selectionReason: selectionReason,
    );
  }
}

String? _trimmed(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
