import 'package:reporting_bridge/reporting_bridge.dart'
    show TemplateSyncFilter, snapshotTemplateQueryExtra;

import '../flow/urb_identifiers.dart';
import 'report_identity.dart';

final class TemplateSyncRequest {
  TemplateSyncRequest({
    required this.systemCode,
    ReportIdentity identity = const ReportIdentity(),
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) : identity = ReportIdentity.normalized(
         userId: identity.userId,
         branchId: identity.branchId,
         systemUnit: identity.systemUnit,
       ),
       filter = filter ?? TemplateSyncFilter(),
       extra = snapshotTemplateQueryExtra(extra);

  final UrbSystemCode systemCode;
  final ReportIdentity identity;
  final TemplateSyncFilter filter;
  final Map<String, Object?> extra;
}
