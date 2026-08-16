import 'package:reporting_bridge/reporting_bridge.dart'
    show snapshotTemplateQueryExtra;

import 'report_contract_values.dart';

/// Fixed Ultimate Printer V1 transport constants.
///
/// Native Android owns FileProvider staging and the final `content://` Intent.
/// Flutter supplies PDF bytes and selected-template document metadata only.
const String ultimatePrinterPackageName = 'com.Ultimate.Printer';
const String ultimatePrinterAction = 'com.Ultimate.Printer.PRINT_PDF_V1';
const String ultimatePrinterMimeType = 'application/pdf';

/// Bridge-owned print context keys that Host [HostExternalPrintRequest.extra]
/// must not supply.
const Set<String> reservedHostExternalPrintExtraKeys = <String>{
  'system',
  'reportType',
  'templateId',
  'userId',
  'branchId',
  'systemUnit',
  'customType',
  'language',
  'language_code',
  'layout',
  'size',
  'unit',
  'orientation',
  'width',
  'height',
};

/// Host-owned external print options.
///
/// Final language/layout/size/unit/orientation/dimensions come from the
/// selected template metadata. Native Android owns content-URI staging.
final class HostExternalPrintRequest {
  HostExternalPrintRequest({
    this.documentTitle,
    Map<String, Object?> extra = const <String, Object?>{},
  }) : extra = _snapshotHostExtra(extra);

  final String? documentTitle;
  final Map<String, Object?> extra;
}

Map<String, Object?> _snapshotHostExtra(Map<String, Object?> raw) {
  final reserved =
      raw.keys
          .where(reservedHostExternalPrintExtraKeys.contains)
          .toList(growable: false)
        ..sort();
  if (reserved.isNotEmpty) {
    throw ArgumentError.value(
      raw,
      'extra',
      'Contains reserved Bridge print keys: ${reserved.join(', ')}',
    );
  }
  return snapshotTemplateQueryExtra(raw);
}

/// Resolves the print document title from Host → report name → template name.
String resolveExternalPrintDocumentTitle({
  HostExternalPrintRequest? hostPrint,
  String? reportName,
  required String templateName,
}) {
  final hostTitle = hostPrint?.documentTitle?.trim();
  if (hostTitle != null && hostTitle.isNotEmpty) return hostTitle;
  final name = reportName?.trim();
  if (name != null && name.isNotEmpty) return name;
  return templateName;
}

/// Maps canonical `ar`/`en` to the legacy external printer integer values.
///
/// Returns `null` when [languageCode] is not a supported canonical language.
int? legacyExternalLanguageValue(String languageCode) {
  try {
    return ReportLanguage.parseCanonical(languageCode).legacyExternalValue;
  } on ArgumentError {
    return null;
  }
}
