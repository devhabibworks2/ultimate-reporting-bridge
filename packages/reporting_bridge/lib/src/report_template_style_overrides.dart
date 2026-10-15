import 'dart:convert';

/// Optional caller-selected color and font token values for one report.
///
/// Values are snapshotted as JSON and deeply made immutable. This DTO does not
/// validate token names or values; Presenter owns their semantic validation.
final class ReportTemplateStyleOverrides {
  ReportTemplateStyleOverrides({
    Map<String, Object?> color = const <String, Object?>{},
    Map<String, Object?> font = const <String, Object?>{},
  }) : color = _snapshotStyleGroup(color, 'color'),
       font = _snapshotStyleGroup(font, 'font');

  final Map<String, Object?> color;
  final Map<String, Object?> font;

  bool get isEmpty => color.isEmpty && font.isEmpty;
}

Map<String, Object?> _snapshotStyleGroup(
  Map<String, Object?> value,
  String fieldName,
) {
  late final Object? decoded;
  try {
    decoded = jsonDecode(jsonEncode(value));
  } on JsonUnsupportedObjectError catch (error) {
    throw ArgumentError.value(value, fieldName, error.toString());
  }
  if (decoded is! Map<String, dynamic>) {
    throw ArgumentError.value(value, fieldName, 'Must be a JSON object.');
  }
  return _freezeStyleMap(decoded);
}

Map<String, Object?> _freezeStyleMap(Map<String, dynamic> value) =>
    Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final entry in value.entries)
        entry.key: _freezeStyleValue(entry.value),
    });

Object? _freezeStyleValue(Object? value) {
  if (value is Map<String, dynamic>) return _freezeStyleMap(value);
  if (value is List) {
    return List<Object?>.unmodifiable(value.map<Object?>(_freezeStyleValue));
  }
  return value;
}

/// Returns a per-session JSON copy of [document] with the supplied style
/// token leaves applied. The source document is never modified.
///
/// This helper performs only mechanical map merging. Token names and values
/// remain the Presenter's responsibility to validate.
Map<String, dynamic> applyReportTemplateStyleOverrides({
  required Map<String, dynamic> document,
  required ReportTemplateStyleOverrides overrides,
}) {
  if (overrides.isEmpty) return document;

  final copy = _copyStyleDocument(document);
  final Object? rawStyleTokens = copy['styleTokens'];
  final Map<String, dynamic> styleTokens;
  if (!copy.containsKey('styleTokens')) {
    styleTokens = <String, dynamic>{};
    copy['styleTokens'] = styleTokens;
  } else if (rawStyleTokens is Map) {
    styleTokens = Map<String, dynamic>.from(rawStyleTokens);
    copy['styleTokens'] = styleTokens;
  } else {
    throw ArgumentError.value(
      rawStyleTokens,
      'document.styleTokens',
      'Must be a JSON object to apply style overrides.',
    );
  }

  _applyStyleGroup(styleTokens, 'color', overrides.color);
  _applyStyleGroup(styleTokens, 'font', overrides.font);
  return copy;
}

Map<String, dynamic> _copyStyleDocument(Map<String, dynamic> document) {
  late final Object? decoded;
  try {
    decoded = jsonDecode(jsonEncode(document));
  } on JsonUnsupportedObjectError catch (error) {
    throw ArgumentError.value(document, 'document', error.toString());
  }
  if (decoded is! Map) {
    throw ArgumentError.value(document, 'document', 'Must be a JSON object.');
  }
  return Map<String, dynamic>.from(decoded);
}

void _applyStyleGroup(
  Map<String, dynamic> styleTokens,
  String groupName,
  Map<String, Object?> leaves,
) {
  if (leaves.isEmpty) return;

  final Object? rawGroup = styleTokens[groupName];
  final Map<String, dynamic> group;
  if (!styleTokens.containsKey(groupName)) {
    group = <String, dynamic>{};
    styleTokens[groupName] = group;
  } else if (rawGroup is Map) {
    group = Map<String, dynamic>.from(rawGroup);
    styleTokens[groupName] = group;
  } else {
    throw ArgumentError.value(
      rawGroup,
      'document.styleTokens.$groupName',
      'Must be a JSON object to apply style overrides.',
    );
  }

  for (final entry in leaves.entries) {
    group[entry.key] = jsonDecode(jsonEncode(entry.value));
  }
}
