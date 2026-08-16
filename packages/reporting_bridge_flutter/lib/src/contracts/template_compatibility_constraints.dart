import 'report_contract_values.dart';

/// Host-supplied template compatibility filters for the active report request.
///
/// [customType] is intentionally absent: Host custom types are selection and
/// persistence identity ([SelectedTemplateCriteria.customType] / V5 scope),
/// not a runtime template-document compatibility dimension.
final class TemplateCompatibilityConstraints {
  const TemplateCompatibilityConstraints({
    this.language,
    this.layout,
    this.size,
    this.unit,
    this.orientation,
  });

  final ReportLanguage? language;
  final ReportLayout? layout;
  final ReportPageSize? size;
  final ReportMeasurementUnit? unit;
  final ReportOrientation? orientation;
}
