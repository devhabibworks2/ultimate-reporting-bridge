import 'dart:collection';
import 'dart:convert';

Map<String, dynamic> snapshotJsonObject(Map<String, dynamic> source) {
  final encoded = jsonEncode(source);
  final decoded = jsonDecode(encoded);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Report seed data must be a JSON object.');
  }
  return _freezeMap(decoded);
}

Map<String, dynamic> _freezeMap(Map<String, dynamic> source) =>
    UnmodifiableMapView<String, dynamic>(
      source.map(
        (key, value) => MapEntry<String, dynamic>(key, _freezeValue(value)),
      ),
    );

Object? _freezeValue(Object? value) => switch (value) {
  Map<String, dynamic> map => _freezeMap(map),
  List<dynamic> list => List<dynamic>.unmodifiable(
    list.map<Object?>(_freezeValue),
  ),
  _ => value,
};
