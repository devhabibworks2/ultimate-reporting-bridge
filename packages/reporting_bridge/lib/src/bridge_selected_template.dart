/// Bridge-owned selected template state.
///
/// Storage shape:
/// `{ "selectedTemplates": { "type": "...", "code": "...",
/// "systemCode": "..." } }`. Legacy storage may contain only `id` + `type`.
///
/// `systemCode` + `code` is the durable business identity.
/// `id` may be cached for runtime.
/// Legacy id-only payloads still parse; migrate them with [migrateLegacyId].
class SelectedTemplate {
  const SelectedTemplate({
    required this.id,
    required this.type,
    this.code,
    this.systemCode,
  });

  final String id;
  final String type;

  /// Durable Template Code when known. Prefer this over [id] for persistence.
  final String? code;

  /// System owning [code]. Code-based durable identity requires this scope.
  final String? systemCode;

  bool matchesType(String reportType) => type == reportType;

  bool get hasDurableIdentity {
    final normalizedCode = code?.trim();
    final normalizedSystemCode = systemCode?.trim();
    return normalizedCode != null &&
        normalizedCode.isNotEmpty &&
        normalizedSystemCode != null &&
        normalizedSystemCode.isNotEmpty;
  }

  /// Preferred durable identity for persistence and display.
  String get durableIdentity {
    final value = code?.trim();
    final system = systemCode?.trim();
    if (value != null &&
        value.isNotEmpty &&
        system != null &&
        system.isNotEmpty) {
      return '$system:$value';
    }
    if (value != null && value.isNotEmpty) return value;
    return id;
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'type': type,
      if (code != null && code!.trim().isNotEmpty) 'code': code!.trim(),
      if (systemCode != null && systemCode!.trim().isNotEmpty)
        'systemCode': systemCode!.trim(),
    };
  }

  Map<String, dynamic> toStorageMap() {
    final normalizedCode = code?.trim();
    final normalizedSystemCode = systemCode?.trim();
    if (!hasDurableIdentity) {
      throw StateError(
        'Durable template selection requires systemCode and code.',
      );
    }
    return <String, dynamic>{
      'selectedTemplates': <String, dynamic>{
        'type': type,
        'code': normalizedCode,
        'systemCode': normalizedSystemCode,
      },
    };
  }

  static SelectedTemplate? fromMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) {
      return null;
    }
    final nested = raw['selectedTemplates'];
    final source = nested is Map ? nested : raw;
    final id = source['id'];
    final type = source['type'];
    if (type == null || (id == null && source['code'] == null)) {
      return null;
    }
    final codeRaw = source['code'];
    final code = codeRaw?.toString().trim();
    final systemCodeRaw = source['systemCode'];
    final systemCode = systemCodeRaw?.toString().trim();
    return SelectedTemplate(
      id: id?.toString() ?? '',
      type: type.toString(),
      code: (code == null || code.isEmpty) ? null : code,
      systemCode: (systemCode == null || systemCode.isEmpty)
          ? null
          : systemCode,
    );
  }

  /// One-time legacy ID → Code migration against a synced catalog.
  ///
  /// Exact catalog id match → persist that item's Code.
  /// Missing id → clear (null). Never guess by name, report type, or position.
  /// Already-coded selections are re-resolved by code when still in catalog.
  static SelectedTemplate? migrateLegacyId({
    required SelectedTemplate? legacy,
    required Iterable<SelectedTemplateCatalogEntry> catalog,
    required String systemCode,
  }) {
    if (legacy == null) return null;
    final normalizedSystemCode = systemCode.trim();
    if (normalizedSystemCode.isEmpty) return null;
    final legacySystemCode = legacy.systemCode?.trim();
    if (legacySystemCode != null &&
        legacySystemCode.isNotEmpty &&
        legacySystemCode != normalizedSystemCode) {
      return null;
    }

    final existingCode = legacy.code?.trim();
    if (existingCode != null && existingCode.isNotEmpty) {
      for (final entry in catalog) {
        if (entry.systemCode == normalizedSystemCode &&
            entry.code == existingCode) {
          return SelectedTemplate(
            id: entry.id,
            type: entry.type,
            code: entry.code,
            systemCode: entry.systemCode,
          );
        }
      }
      return null;
    }

    for (final entry in catalog) {
      if (entry.systemCode == normalizedSystemCode && entry.id == legacy.id) {
        return SelectedTemplate(
          id: entry.id,
          type: entry.type,
          code: entry.code,
          systemCode: entry.systemCode,
        );
      }
    }
    return null;
  }
}

/// Minimal catalog row used by [SelectedTemplate.migrateLegacyId].
class SelectedTemplateCatalogEntry {
  const SelectedTemplateCatalogEntry({
    required this.id,
    required this.type,
    required this.code,
    required this.systemCode,
  });

  final String id;
  final String type;
  final String code;
  final String systemCode;
}
