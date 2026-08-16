import 'package:reporting_bridge/reporting_bridge.dart';

import '../contracts/report_contract_values.dart';
import '../contracts/template_compatibility_constraints.dart';
import '../platform/bridge_platform_adapters.dart';
import 'urb_identifiers.dart';

final class ReportTemplateMetadata {
  const ReportTemplateMetadata({
    required this.reportType,
    required this.layout,
    required this.size,
    required this.unit,
    required this.orientation,
    required this.language,
    required this.width,
    required this.height,
    required this.direction,
  });

  final UrbReportTypeCode reportType;
  final ReportLayout layout;
  final ReportPageSize size;
  final ReportMeasurementUnit unit;
  final ReportOrientation orientation;
  final ReportLanguage language;
  final double width;
  final double height;
  final String direction;

  bool get isThermal => layout == ReportLayout.thermal;
  bool get hasPrintableDimensions =>
      width.isFinite && height.isFinite && width > 0 && height > 0;

  factory ReportTemplateMetadata.fromTemplate(CachedTemplate template) {
    final document = template.document;
    final page = _map(document['page']);
    final meta = _map(document['meta']);

    final familyRaw = _text(meta['family']);
    if (familyRaw == null) {
      throw ArgumentError.value(
        meta['family'],
        'meta.family',
        'Report family is required.',
      );
    }
    final reportType = UrbReportType.parseCanonical(familyRaw);

    final layoutRaw = _text(page['layout']);
    if (layoutRaw == null) {
      throw ArgumentError.value(
        page['layout'],
        'page.layout',
        'Page layout is required.',
      );
    }
    final layout = ReportLayout.parseCanonical(layoutRaw);

    final sizeRaw = _text(page['size']);
    if (sizeRaw == null) {
      throw ArgumentError.value(
        page['size'],
        'page.size',
        'Page size is required.',
      );
    }
    final size = ReportPageSize.parseCanonical(sizeRaw);

    final unitRaw = _text(page['unit']);
    if (unitRaw == null) {
      throw ArgumentError.value(
        page['unit'],
        'page.unit',
        'Page unit is required.',
      );
    }
    final unit = ReportMeasurementUnit.parseCanonical(unitRaw);

    final orientationRaw = _text(page['orientation']);
    if (orientationRaw == null) {
      throw ArgumentError.value(
        page['orientation'],
        'page.orientation',
        'Page orientation is required.',
      );
    }
    final orientation = ReportOrientation.parseCanonical(orientationRaw);

    final languageRaw = _text(page['language']);
    if (languageRaw == null) {
      throw ArgumentError.value(
        page['language'],
        'page.language',
        'Page language is required.',
      );
    }
    final language = ReportLanguage.parseCanonical(languageRaw);

    final width = _number(page['width']);
    final height = _number(page['height']);
    _validateDimensions(
      layout: layout,
      size: size,
      orientation: orientation,
      width: width,
      height: height,
    );

    return ReportTemplateMetadata(
      reportType: reportType,
      layout: layout,
      size: size,
      unit: unit,
      orientation: orientation,
      language: language,
      width: width,
      height: height,
      direction: _requireDirection(page),
    );
  }

  static ReportTemplateMetadata? tryFromTemplate(CachedTemplate template) {
    try {
      return ReportTemplateMetadata.fromTemplate(template);
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  }

  bool matches({
    required String reportType,
    TemplateCompatibilityConstraints constraints =
        const TemplateCompatibilityConstraints(),
  }) {
    if (this.reportType.value != reportType.trim()) return false;
    if (constraints.language != null && constraints.language != language) {
      return false;
    }
    if (constraints.layout != null && constraints.layout != layout) {
      return false;
    }
    if (constraints.size != null && constraints.size != size) {
      return false;
    }
    if (constraints.unit != null && constraints.unit != unit) {
      return false;
    }
    if (constraints.orientation != null &&
        constraints.orientation != orientation) {
      return false;
    }
    return true;
  }

  ReportPrintDocumentMetadata toPrintDocumentMetadata() {
    if (!hasPrintableDimensions) {
      throw StateError('Template page dimensions are unavailable.');
    }
    return ReportPrintDocumentMetadata(
      unit: unit.value,
      layout: layout.value,
      size: size.value,
      width: width,
      height: height,
      orientation: orientation.value,
      languageCode: language.value,
    );
  }
}

extension CachedTemplateReportMetadata on CachedTemplate {
  ReportTemplateMetadata get reportMetadata =>
      ReportTemplateMetadata.fromTemplate(this);
}

List<CachedTemplate> filterEligibleTemplates(
  Iterable<CachedTemplate> templates, {
  required String reportType,
  TemplateCompatibilityConstraints constraints =
      const TemplateCompatibilityConstraints(),
}) => List<CachedTemplate>.unmodifiable(
  templates.where((template) {
    final metadata = ReportTemplateMetadata.tryFromTemplate(template);
    if (metadata == null) return false;
    return metadata.matches(reportType: reportType, constraints: constraints);
  }),
);

String _requireDirection(Map<dynamic, dynamic> page) {
  final direction = _text(page['direction']);
  if (direction == 'rtl' || direction == 'ltr') return direction!;
  throw ArgumentError.value(
    page['direction'],
    'page.direction',
    'Page direction must be an explicit canonical value (ltr|rtl).',
  );
}

void _validateDimensions({
  required ReportLayout layout,
  required ReportPageSize size,
  required ReportOrientation orientation,
  required double width,
  required double height,
}) {
  if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
    throw ArgumentError(
      'page.width and page.height must be finite positive numbers.',
    );
  }
  if (layout == ReportLayout.thermal &&
      orientation != ReportOrientation.portrait) {
    throw ArgumentError.value(
      orientation.value,
      'page.orientation',
      'Thermal layout requires portrait orientation.',
    );
  }

  switch (size) {
    case ReportPageSize.custom:
      return;
    case ReportPageSize.thermal80:
      if (!_approx(width, 80)) {
        throw ArgumentError.value(
          width,
          'page.width',
          '80mm size requires width 80.',
        );
      }
      return;
    case ReportPageSize.thermal58:
      if (!_approx(width, 58)) {
        throw ArgumentError.value(
          width,
          'page.width',
          '58mm size requires width 58.',
        );
      }
      return;
    case ReportPageSize.a4:
      _expectPreset(
        width: width,
        height: height,
        orientation: orientation,
        shortSide: 210,
        longSide: 297,
        label: 'A4',
      );
      return;
    case ReportPageSize.a5:
      _expectPreset(
        width: width,
        height: height,
        orientation: orientation,
        shortSide: 148,
        longSide: 210,
        label: 'A5',
      );
      return;
    case ReportPageSize.letter:
      _expectPreset(
        width: width,
        height: height,
        orientation: orientation,
        shortSide: 215.9,
        longSide: 279.4,
        label: 'Letter',
      );
      return;
  }
}

void _expectPreset({
  required double width,
  required double height,
  required ReportOrientation orientation,
  required double shortSide,
  required double longSide,
  required String label,
}) {
  final expectedWidth = orientation == ReportOrientation.portrait
      ? shortSide
      : longSide;
  final expectedHeight = orientation == ReportOrientation.portrait
      ? longSide
      : shortSide;
  if (!_approx(width, expectedWidth) || !_approx(height, expectedHeight)) {
    throw ArgumentError(
      'page dimensions must match $label ${orientation.value} '
      '($expectedWidth x $expectedHeight).',
    );
  }
}

bool _approx(double actual, double expected) =>
    (actual - expected).abs() < 0.05;

Map<dynamic, dynamic> _map(Object? value) =>
    value is Map ? value : const <dynamic, dynamic>{};

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

double _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? double.nan;
}
