import 'dart:convert';

import 'bridge_identity_context.dart';

const int kTemplateQueryExtraMaximumBytes = 16 * 1024;

final class TemplateSyncFilter {
  factory TemplateSyncFilter({
    Iterable<String>? reportTypes,
    Iterable<String>? layouts,
    Iterable<String>? sizes,
    Iterable<String>? languages,
    Iterable<String>? units,
    Iterable<String>? orientations,
  }) {
    return TemplateSyncFilter._(
      reportTypes: _normalizeFilterValues(
        reportTypes,
        'reportTypes',
        lowercase: true,
      ),
      layouts: _normalizeFilterValues(layouts, 'layouts'),
      sizes: _normalizeFilterValues(sizes, 'sizes'),
      languages: _normalizeFilterValues(languages, 'languages'),
      units: _normalizeFilterValues(units, 'units'),
      orientations: _normalizeFilterValues(orientations, 'orientations'),
    );
  }

  const TemplateSyncFilter._({
    required this.reportTypes,
    required this.layouts,
    required this.sizes,
    required this.languages,
    required this.units,
    required this.orientations,
  });

  final List<String> reportTypes;
  final List<String> layouts;
  final List<String> sizes;
  final List<String> languages;
  final List<String> units;
  final List<String> orientations;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'reportTypes': reportTypes,
    'layouts': layouts,
    'sizes': sizes,
    'languages': languages,
    'units': units,
    'orientations': orientations,
  };

  Map<String, dynamic> toCanonicalJson() => <String, dynamic>{
    'reportTypes': _sortedCopy(reportTypes),
    'layouts': _sortedCopy(layouts),
    'sizes': _sortedCopy(sizes),
    'languages': _sortedCopy(languages),
    'units': _sortedCopy(units),
    'orientations': _sortedCopy(orientations),
  };

  String get fingerprint => canonicalJsonFingerprint(toCanonicalJson());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TemplateSyncFilter && other.fingerprint == fingerprint;

  @override
  int get hashCode => fingerprint.hashCode;
}

final class TemplateQueryRequest {
  factory TemplateQueryRequest({
    required String systemCode,
    BridgeIdentityContext? identity,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    final normalizedSystemCode = systemCode.trim().toLowerCase();
    if (normalizedSystemCode.isEmpty) {
      throw ArgumentError.value(systemCode, 'systemCode', 'Must not be empty.');
    }
    if (!RegExp(
      r'^[a-z0-9]+(?:[-_][a-z0-9]+)*$',
    ).hasMatch(normalizedSystemCode)) {
      throw ArgumentError.value(
        systemCode,
        'systemCode',
        'Must be a lowercase canonical code.',
      );
    }

    return TemplateQueryRequest._(
      systemCode: normalizedSystemCode,
      identity: identity ?? BridgeIdentityContext(),
      filter: filter ?? TemplateSyncFilter(),
      extra: snapshotTemplateQueryExtra(extra),
    );
  }

  const TemplateQueryRequest._({
    required this.systemCode,
    required this.identity,
    required this.filter,
    required this.extra,
  });

  final String systemCode;
  final BridgeIdentityContext identity;
  final TemplateSyncFilter filter;
  final Map<String, Object?> extra;

  String get filterFingerprint => filter.fingerprint;

  String get extraFingerprint => canonicalJsonFingerprint(extra);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'systemCode': systemCode,
    ...identity.toJson(),
    'filter': filter.toJson(),
    'extra': extra,
  };
}

String canonicalJsonEncode(Object? value) {
  return jsonEncode(_canonicalizeJsonValue(value));
}

String canonicalJsonFingerprint(Object? value) {
  return _fnv1a64Hex(utf8.encode(canonicalJsonEncode(value)));
}

List<String> _normalizeFilterValues(
  Iterable<String>? values,
  String fieldName, {
  bool lowercase = false,
}) {
  final source = values ?? const <String>['all'];
  final normalized = <String>[];
  final seen = <String>{};
  for (final raw in source) {
    final value = raw.trim();
    if (value.isEmpty) {
      throw ArgumentError.value(raw, fieldName, 'Values must not be empty.');
    }
    final canonical = value.toLowerCase() == 'all'
        ? 'all'
        : lowercase
        ? value.toLowerCase()
        : value;
    if (seen.add(canonical)) normalized.add(canonical);
  }
  if (normalized.isEmpty) {
    throw ArgumentError.value(values, fieldName, 'Must not be empty.');
  }
  if (normalized.contains('all') && normalized.length > 1) {
    throw ArgumentError.value(
      values,
      fieldName,
      '"all" cannot be combined with another value.',
    );
  }
  return List<String>.unmodifiable(normalized);
}

/// Deep JSON-compatible snapshot of query/request `extra`.
///
/// Host-facing contracts reuse this authority so mutation of the caller's map
/// (including nested maps/lists) cannot change Bridge query semantics after
/// construction.
Map<String, Object?> snapshotTemplateQueryExtra(Map<String, Object?> raw) {
  Object? decoded;
  late final String encoded;
  try {
    encoded = jsonEncode(raw);
    decoded = jsonDecode(encoded);
  } on JsonUnsupportedObjectError catch (error) {
    throw ArgumentError.value(raw, 'extra', error.toString());
  }
  if (utf8.encode(encoded).length > kTemplateQueryExtraMaximumBytes) {
    throw ArgumentError.value(
      raw,
      'extra',
      'Encoded value exceeds $kTemplateQueryExtraMaximumBytes bytes.',
    );
  }
  if (decoded is! Map) {
    throw ArgumentError.value(raw, 'extra', 'Must be a JSON object.');
  }
  return _freezeExtraMap(<String, Object?>{
    for (final entry in decoded.entries)
      entry.key.toString(): entry.value as Object?,
  });
}

Map<String, Object?> _freezeExtraMap(Map<String, Object?> source) =>
    Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final entry in source.entries)
        entry.key: _freezeExtraValue(entry.value),
    });

Object? _freezeExtraValue(Object? value) {
  if (value is Map) {
    return _freezeExtraMap(<String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): entry.value as Object?,
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(
      value.map<Object?>((item) => _freezeExtraValue(item as Object?)),
    );
  }
  return value;
}

Object? _canonicalizeJsonValue(Object? value) {
  if (value is Map) {
    final entries =
        value.entries
            .map((entry) => MapEntry(entry.key.toString(), entry.value))
            .toList(growable: false)
          ..sort((a, b) => a.key.compareTo(b.key));
    return <String, Object?>{
      for (final entry in entries)
        entry.key: _canonicalizeJsonValue(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalizeJsonValue).toList(growable: false);
  }
  return value;
}

String _fnv1a64Hex(List<int> bytes) {
  var high = 0xcbf29ce4;
  var low = 0x84222325;
  for (final byte in bytes) {
    low = (low ^ byte).toUnsigned(32);
    final lowProduct = low * 0x1b3;
    final carry = lowProduct ~/ 0x100000000;
    final shiftedLow = (low * 0x100).toUnsigned(32);
    low = lowProduct.toUnsigned(32);
    high = (high * 0x1b3 + carry + shiftedLow).toUnsigned(32);
  }
  final highHex = high.toRadixString(16).padLeft(8, '0');
  final lowHex = low.toRadixString(16).padLeft(8, '0');
  return '$highHex$lowHex';
}

List<String> _sortedCopy(List<String> values) {
  return List<String>.of(values, growable: false)..sort();
}
