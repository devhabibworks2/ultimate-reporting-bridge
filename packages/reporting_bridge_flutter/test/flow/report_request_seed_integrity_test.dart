import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  test('ReportOpenRequest takes a deep immutable snapshot of seed data', () {
    final source = <String, dynamic>{
      'header': <String, dynamic>{'number': 'INV-1'},
      'rows': <dynamic>[
        <String, dynamic>{'quantity': 2},
      ],
    };

    final request = ReportOpenRequest(
      seedData: source,
      selectedTemplateCriteria: SelectedTemplateCriteria(
        reportType: UrbReportType.salesInvoice,
      ),
      templateSyncRequest: TemplateSyncRequest(
        systemCode: UrbSystem.motakamelTransactions,
      ),
    );

    (source['header'] as Map<String, dynamic>)['number'] = 'MUTATED';
    (source['rows'] as List<dynamic>).add(<String, dynamic>{'quantity': 9});

    expect(request.reportType, UrbReportType.salesInvoice);
    expect(
      (request.seedData['header'] as Map<String, dynamic>)['number'],
      'INV-1',
    );
    expect(request.seedData['rows'], hasLength(1));
    expect(
      () => (request.seedData['header'] as Map<String, dynamic>)['number'] =
          'changed',
      throwsUnsupportedError,
    );
    expect(
      () => (request.seedData['rows'] as List<dynamic>).add('changed'),
      throwsUnsupportedError,
    );
  });

  test('ReportOpenRequest normalizes optional identity and locale values', () {
    final request = ReportOpenRequest(
      seedData: const <String, dynamic>{'id': 1},
      selectedTemplateCriteria: SelectedTemplateCriteria(
        reportType: UrbReportType.salesInvoice,
      ),
      templateSyncRequest: TemplateSyncRequest(
        systemCode: UrbSystem.motakamelTransactions,
      ),
      reportName: '  Invoice report  ',
      requestId: '  request-1  ',
      initialTemplateId: '  template-1  ',
      localeOverride: 'ar-YE',
    );

    expect(request.reportName, 'Invoice report');
    expect(request.requestId, 'request-1');
    expect(request.initialTemplateId, 'template-1');
    expect(request.localeOverride, 'ar');

    final enUs = ReportOpenRequest(
      seedData: const <String, dynamic>{'id': 1},
      selectedTemplateCriteria: SelectedTemplateCriteria(
        reportType: UrbReportType.salesInvoice,
      ),
      templateSyncRequest: TemplateSyncRequest(
        systemCode: UrbSystem.motakamelTransactions,
      ),
      localeOverride: 'en_US',
    );
    expect(enUs.localeOverride, 'en');

    expect(
      () => ReportOpenRequest(
        seedData: const <String, dynamic>{'id': 1},
        selectedTemplateCriteria: SelectedTemplateCriteria(
          reportType: UrbReportType.salesInvoice,
        ),
        templateSyncRequest: TemplateSyncRequest(
          systemCode: UrbSystem.motakamelTransactions,
        ),
        localeOverride: 'fr',
      ),
      throwsA(isA<ArgumentError>()),
    );

    final empty = ReportOpenRequest(
      seedData: const <String, dynamic>{'id': 1},
      selectedTemplateCriteria: SelectedTemplateCriteria(
        reportType: UrbReportType.salesInvoice,
      ),
      templateSyncRequest: TemplateSyncRequest(
        systemCode: UrbSystem.motakamelTransactions,
      ),
      reportName: '   ',
      requestId: '',
      initialTemplateId: '	',
    );
    expect(empty.reportName, isNull);
    expect(empty.requestId, isNull);
    expect(empty.initialTemplateId, isNull);
  });

  test('ReportOpenRequest rejects non-JSON seed values', () {
    expect(
      () => ReportOpenRequest(
        seedData: <String, dynamic>{'invalid': Object()},
        selectedTemplateCriteria: SelectedTemplateCriteria(
          reportType: UrbReportType.salesInvoice,
        ),
        templateSyncRequest: TemplateSyncRequest(
          systemCode: UrbSystem.motakamelTransactions,
        ),
      ),
      throwsA(anything),
    );
  });
}
