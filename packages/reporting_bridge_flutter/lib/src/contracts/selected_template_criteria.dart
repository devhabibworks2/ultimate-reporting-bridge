import '../flow/urb_identifiers.dart';
import 'report_identity.dart';

final class SelectedTemplateCriteria {
  SelectedTemplateCriteria({
    required this.reportType,
    ReportIdentity identity = const ReportIdentity(),
    String? customType,
  }) : identity = ReportIdentity.normalized(
         userId: identity.userId,
         branchId: identity.branchId,
         systemUnit: identity.systemUnit,
       ),
       customType = _trimmedOrNull(customType);

  final UrbReportTypeCode reportType;
  final ReportIdentity identity;
  final String? customType;

  String? get userId => identity.userId;
  String? get branchId => identity.branchId;
  String? get systemUnit => identity.systemUnit;
}

String? _trimmedOrNull(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
