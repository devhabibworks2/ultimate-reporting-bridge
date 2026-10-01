/// Bridge-owned selected template state.
///
/// TemplateCode is the only template identity used by the Bridge.
class SelectedTemplate {
  const SelectedTemplate({
    required this.type,
    required this.code,
    this.systemCode,
  });

  final String type;
  final String code;
  final String? systemCode;

  bool matchesType(String reportType) => type == reportType;

  bool get hasDurableIdentity => code.trim().isNotEmpty;

  String get durableIdentity {
    final normalizedCode = code.trim();
    final normalizedSystemCode = systemCode?.trim();
    if (normalizedSystemCode != null && normalizedSystemCode.isNotEmpty) {
      return '$normalizedSystemCode:$normalizedCode';
    }
    return normalizedCode;
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'type': type,
    'code': code.trim(),
    if (systemCode != null && systemCode!.trim().isNotEmpty)
      'systemCode': systemCode!.trim(),
  };

  Map<String, dynamic> toStorageMap() {
    if (!hasDurableIdentity) {
      throw StateError('Durable template selection requires TemplateCode.');
    }
    return <String, dynamic>{
      'selectedTemplates': toMap(),
    };
  }

  static SelectedTemplate? fromMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) return null;
    final nested = raw['selectedTemplates'];
    final source = nested is Map ? nested : raw;
    final type = source['type']?.toString().trim();
    final code = source['code']?.toString().trim();
    if (type == null || type.isEmpty || code == null || code.isEmpty) {
      return null;
    }
    final systemCode = source['systemCode']?.toString().trim();
    return SelectedTemplate(
      type: type,
      code: code,
      systemCode:
          systemCode == null || systemCode.isEmpty ? null : systemCode,
    );
  }
}

class SelectedTemplateCatalogEntry {
  const SelectedTemplateCatalogEntry({
    required this.type,
    required this.code,
    required this.systemCode,
  });

  final String type;
  final String code;
  final String systemCode;
}
