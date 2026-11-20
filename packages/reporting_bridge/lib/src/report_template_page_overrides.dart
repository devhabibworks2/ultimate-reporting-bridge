import 'dart:convert';

import 'bridge_runtime_error.dart';

/// The canonical layout of a session-local template page.
enum BridgePageLayout {
  pages('Pages'),
  thermal('Thermal');

  const BridgePageLayout(this.value);
  final String value;
}

/// Page size as stored in a canonical URB TemplateDocument.
enum BridgePageSize {
  a4('A4'),
  a5('A5'),
  letter('Letter'),
  thermal80('80mm'),
  thermal58('58mm'),
  custom('custom');

  const BridgePageSize(this.value);
  final String value;
}

enum BridgePageOrientation {
  portrait('portrait'),
  landscape('landscape');

  const BridgePageOrientation(this.value);
  final String value;
}

enum BridgePageDirection {
  ltr('ltr'),
  rtl('rtl');

  const BridgePageDirection(this.value);
  final String value;
}

/// Optional page properties of a single Presenter session. The source
/// TemplateDocument, published copy, and template-selection metadata remain
/// unchanged. Width/height are millimeters, NOT device pixels.
///
/// On Thermal templates, the PDF height is content-driven, not [heightMm].
/// Supplying a Thermal height override is explicitly unsupported.
final class ReportTemplatePageOverrides {
  const ReportTemplatePageOverrides({
    this.layout,
    this.size,
    this.orientation,
    this.widthMm,
    this.heightMm,
    this.direction,
  });

  final BridgePageLayout? layout;
  final BridgePageSize? size;
  final BridgePageOrientation? orientation;
  final double? widthMm;
  final double? heightMm;
  final BridgePageDirection? direction;

  bool get isEmpty =>
      layout == null &&
      size == null &&
      orientation == null &&
      widthMm == null &&
      heightMm == null &&
      direction == null;
}

/// Copies a document and atomically applies a coherent effective page tuple.
///
/// Does not select or persist templates. Call only AFTER checking the original
/// template's eligibility. Errors have a stable Bridge code and a field path.
Map<String, dynamic> applyReportTemplatePageOverrides({
  required Map<String, dynamic> document,
  required ReportTemplatePageOverrides overrides,
}) {
  if (overrides.isEmpty) return document;

  final originalPage = document['page'];
  if (originalPage is! Map) {
    _reject('page', 'Template page must be a JSON object.');
  }
  final source = Map<String, dynamic>.from(originalPage as Map);
  // Direction-only is a surgical runtime change. Keep even legacy authoring
  // dimensions exactly as they were; never silently normalize A4 geometry.
  if (overrides.direction != null &&
      overrides.layout == null && overrides.size == null &&
      overrides.orientation == null && overrides.widthMm == null &&
      overrides.heightMm == null) {
    return _snapshotWithPage(document, <String, dynamic>{
      ...source, 'direction': overrides.direction!.value,
    });
  }
  if (source['unit'] != 'mm') {
    _reject('page.unit', 'Page overrides require millimeters.');
  }

  final sourceLayout = source['layout']?.toString();
  final sourceSize = source['size']?.toString();
  final sourceOrientation = source['orientation']?.toString();
  final layout = overrides.layout?.value ?? sourceLayout;
  var size = overrides.size?.value ?? sourceSize;
  var orientation = overrides.orientation?.value ?? sourceOrientation;
  final direction = overrides.direction?.value ?? source['direction'];

  if (layout != 'Pages' && layout != 'Thermal') {
    _reject('page.layout', 'Expected Pages or Thermal.');
  }
  if (direction != 'rtl' && direction != 'ltr') {
    _reject('page.direction', 'Expected rtl or ltr.');
  }
  final switchingLayout = layout != sourceLayout;
  if (switchingLayout && overrides.size == null) {
    _reject('page.size', 'Changing layout requires an explicit compatible page size.');
  }

  if (layout == 'Thermal') {
    if (overrides.heightMm != null) {
      _reject('page.height', 'Thermal PDF height is content-driven; a fixed-height override is not supported.');
    }
    if (size != '80mm' && size != '58mm') {
      _reject('page.size', 'Thermal currently supports only 58mm and 80mm.');
    }
    if (switchingLayout && overrides.orientation == null) {
      orientation = 'portrait';
    }
    if (orientation != 'portrait') {
      _reject('page.orientation', 'Thermal requires portrait orientation.');
    }
    final width = size == '80mm' ? 80.0 : 58.0;
    _checkOptionalDimension(overrides.widthMm, 'page.width');
    if (overrides.widthMm != null && !_approx(overrides.widthMm!, width)) {
      _reject('page.width', '$size paper width must be $width mm.');
    }
    final height = _number(source['height']);
    if (!height.isFinite || height <= 0) {
      _reject('page.height', 'Thermal serialized compatibility height must be positive.');
    }
    _checkMargins(source['margins'], width, height, thermal: true);
    return _snapshotWithPage(document, <String, dynamic>{
      ...source,
      'layout': 'Thermal',
      'size': size,
      'orientation': 'portrait',
      'width': width,
      'height': height,
      'direction': direction,
    });
  }

  if (orientation != 'portrait' && orientation != 'landscape') {
    _reject('page.orientation', 'Expected portrait or landscape.');
  }
  final sourceWidth = _number(source['width']);
  final sourceHeight = _number(source['height']);
  _checkOptionalDimension(overrides.widthMm, 'page.width');
  _checkOptionalDimension(overrides.heightMm, 'page.height');
  final requestedDimensions =
      overrides.widthMm != null || overrides.heightMm != null;

  // Supplying two custom dimensions without a size is an explicit request to
  // change the physical sheet, not an instruction to mislabel it as A4/A5.
  if (overrides.size == null && requestedDimensions &&
      size != 'custom' && !switchingLayout) {
    if (overrides.widthMm == null || overrides.heightMm == null) {
      _reject('page.width', 'Changing a named preset requires widthMm and heightMm together.');
    }
    final candidate = _namedDimensions(size, orientation);
    if (candidate == null ||
        !_approx(overrides.widthMm!, candidate.$1) ||
        !_approx(overrides.heightMm!, candidate.$2)) {
      size = 'custom';
    }
  }

  late final double width;
  late final double height;
  if (size == 'custom') {
    final previouslyCustom = sourceLayout == 'Pages' && sourceSize == 'custom';
    if (!previouslyCustom &&
        (overrides.widthMm == null || overrides.heightMm == null)) {
      _reject('page.width', 'Switching to custom Pages requires both widthMm and heightMm.');
    }
    width = overrides.widthMm ?? sourceWidth;
    height = overrides.heightMm ?? sourceHeight;
  } else {
    final expected = _namedDimensions(size, orientation);
    if (expected == null) {
      _reject('page.size', 'Pages supports A4, A5, Letter, or custom.');
    }
    width = expected!.$1;
    height = expected.$2;
    if (overrides.widthMm != null && !_approx(overrides.widthMm!, width)) {
      _reject('page.width', 'Explicit width contradicts $size $orientation ($width mm).');
    }
    if (overrides.heightMm != null && !_approx(overrides.heightMm!, height)) {
      _reject('page.height', 'Explicit height contradicts $size $orientation ($height mm).');
    }
  }

  if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
    _reject('page.width', 'Width and height must be finite positive mm values.');
  }
  _checkMargins(source['margins'], width, height, thermal: false);
  return _snapshotWithPage(document, <String, dynamic>{
    ...source,
    'layout': 'Pages',
    'size': size,
    'orientation': orientation,
    'width': width,
    'height': height,
    'direction': direction,
  });
}

/// Returns the dimensions of known Pages presets in millimeters.
(double, double)? _namedDimensions(String? size, String? orientation) {
  final sides = switch (size) {
    'A4' => (210.0, 297.0),
    'A5' => (148.0, 210.0),
    'Letter' => (215.9, 279.4),
    _ => null,
  };
  if (sides == null) return null;
  return orientation == 'landscape'
      ? (sides.$2, sides.$1)
      : sides;
}

Map<String, dynamic> _snapshotWithPage(
  Map<String, dynamic> document,
  Map<String, dynamic> page,
) {
  final decoded = jsonDecode(jsonEncode(document));
  if (decoded is! Map<String, dynamic>) {
    _reject('document', 'Template must be a JSON object.');
  }
  final pageCopy = jsonDecode(jsonEncode(page)) as Map<String, dynamic>;
  return Map<String, dynamic>.from(decoded as Map<String, dynamic>)
    ..['page'] = pageCopy;
}

void _checkOptionalDimension(double? value, String path) {
  if (value != null && (!value.isFinite || value <= 0)) {
    _reject(path, 'Must be a finite positive number in millimeters.');
  }
}

void _checkMargins(Object? raw, double width, double height, {required bool thermal}) {
  if (raw == null) return;
  if (raw is! Map) _reject('page.margins', 'Expected a margins object.');
  final margins = raw as Map;
  final top = _number(margins['top'] ?? 0);
  final bottom = _number(margins['bottom'] ?? 0);
  final left = _number(margins['left'] ?? 0);
  final right = _number(margins['right'] ?? 0);
  if ([top, bottom, left, right].any((x) => !x.isFinite || x < 0)) {
    _reject('page.margins', 'Margins must be finite and non-negative.');
  }
  if (left + right >= width || (!thermal && top + bottom >= height)) {
    _reject('page.margins', 'Margins exceed the printable page dimensions.');
  }
}

double _number(Object? raw) =>
    raw is num ? raw.toDouble() : (double.tryParse(raw?.toString() ?? '') ?? double.nan);

bool _approx(double actual, double expected) => (actual - expected).abs() < 0.05;

Never _reject(String path, String message) => throw BridgeRuntimeException(
  BridgeRuntimeErrorCodes.templatePageOverrideInvalid,
  '$path: $message',
);
