import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  test('online and offline preferences do not change seed values', () {
    final seed = <String, dynamic>{
      'ReportId': 'DocReport_Invoice',
      'rows': <dynamic>[
        <String, dynamic>{'item': 'A', 'quantity': 2},
      ],
    };

    final online = ReportOpenRequest(
      seedData: seed,
      selectedTemplateCriteria: SelectedTemplateCriteria(
        reportType: UrbReportTypeCode('invoice'),
      ),
      templateSyncRequest: TemplateSyncRequest(
        systemCode: UrbSystemCode('legacy_system_1'),
      ),
      presenterMode: PresenterModePreference.online,
    );
    final offline = ReportOpenRequest(
      seedData: seed,
      selectedTemplateCriteria: SelectedTemplateCriteria(
        reportType: UrbReportTypeCode('invoice'),
      ),
      templateSyncRequest: TemplateSyncRequest(
        systemCode: UrbSystemCode('legacy_system_1'),
      ),
      presenterMode: PresenterModePreference.offline,
    );

    expect(offline.seedData, equals(online.seedData));
    expect(
      (offline.seedData['rows'] as List<dynamic>).first,
      equals((seed['rows'] as List<dynamic>).first),
    );
  });
}
