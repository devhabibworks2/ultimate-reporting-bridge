/// Bridge-owned selected template state.
///
/// Storage shape must stay:
/// `{ "selectedTemplates": { "id": "...", "type": "..." } }`.
class SelectedTemplate {
  const SelectedTemplate({required this.id, required this.type});

  final String id;
  final String type;

  bool matchesType(String reportType) => type == reportType;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{'id': id, 'type': type};
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
    return SelectedTemplate(id: id.toString(), type: type.toString());
  }
}
