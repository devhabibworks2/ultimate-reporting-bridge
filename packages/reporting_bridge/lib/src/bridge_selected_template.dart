/// Bridge-owned selected template state.
///
/// Storage shape:
/// `{ "selectedTemplates": { "id": "...", "type": "...", "code": "..." } }`.
///
/// `code` is the durable business identity. `id` may be cached for runtime.
/// Legacy id-only payloads still parse; migrate them with [migrateLegacyId].
class SelectedTemplate {
  const SelectedTemplate({
    required this.id,
    required this.type,
    this.code,
  });

  final String id;
  final String type;

  /// Durable Template Code when known. Prefer this over [id] for persistence.
  final String? code;

  bool matchesType(String reportType) => type == reportType;

  /// Preferred durable identity for persistence and display.
  String get durableIdentity {
    final value = code?.trim();
    if (value != null && value.isNotEmpty) return value;
    return id;
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'type': type,
      if (code != null && code!.trim().isNotEmpty) 'code': code!.trim(),
    };
  }

  Map<String, dynamic> toStorageMap() {
    return <String, dynamic>{'selectedTemplates': toMap()};
  }

  static SelectedTemplate? fromMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) {
      return null;
    }
    final nested = raw['selectedTemplates'];
    final source = nested is Map ? nested : raw;
    final id = source['id'];
    final type = source['type'];
    if (id == null || type == null) {
      return null;
    }
    final codeRaw = source['code'];
    final code = codeRaw?.toString().trim();
    return SelectedTemplate(
      id: id.toString(),
      type: type.toString(),
      code: (code == null || code.isEmpty) ? null : code,
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
  }) {
    if (legacy == null) return null;

    final existingCode = legacy.code?.trim();
    if (existingCode != null && existingCode.isNotEmpty) {
      for (final entry in catalog) {
        if (entry.code == existingCode && entry.type == legacy.type) {
          return SelectedTemplate(
            id: entry.id,
            type: entry.type,
            code: entry.code,
          );
        }
      }
      return null;
    }

    for (final entry in catalog) {
      if (entry.id == legacy.id && entry.type == legacy.type) {
        return SelectedTemplate(
          id: entry.id,
          type: entry.type,
          code: entry.code,
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
  });

  final String id;
  final String type;
  final String code;
}
