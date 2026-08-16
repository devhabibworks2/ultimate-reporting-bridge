import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  test('action controller exposes immutable compatibility constraints', () {
    final request = ReportOpenRequest(
      seedData: const <String, dynamic>{'id': 1},
      selectedTemplateCriteria: SelectedTemplateCriteria(
        reportType: UrbReportType.salesInvoice,
        customType: 'receipt',
      ),
      templateSyncRequest: TemplateSyncRequest(
        systemCode: UrbSystem.motakamelTransactions,
      ),
      compatibility: const TemplateCompatibilityConstraints(
        language: ReportLanguage.en,
        layout: ReportLayout.thermal,
        size: ReportPageSize.thermal80,
      ),
    );

    final constraints = resolveTemplateCompatibilityConstraints(request);

    expect(constraints.language, ReportLanguage.en);
    expect(constraints.layout, ReportLayout.thermal);
    expect(constraints.size, ReportPageSize.thermal80);
    expect(request.selectedTemplateCriteria.customType, 'receipt');
  });

  test('ReportOpenRequest compatibility is the sole constraints authority', () {
    final open = ReportOpenRequest(
      seedData: const <String, dynamic>{'id': 1},
      selectedTemplateCriteria: SelectedTemplateCriteria(
        reportType: UrbReportType.salesInvoice,
      ),
      templateSyncRequest: TemplateSyncRequest(
        systemCode: UrbSystem.motakamelTransactions,
      ),
      compatibility: const TemplateCompatibilityConstraints(
        language: ReportLanguage.ar,
        layout: ReportLayout.pages,
        size: ReportPageSize.a4,
      ),
    );
    final constraints = resolveTemplateCompatibilityConstraints(open);
    expect(constraints.language, ReportLanguage.ar);
    expect(constraints.layout, ReportLayout.pages);
    expect(constraints.size, ReportPageSize.a4);
    expect(identical(constraints, open.compatibility), isTrue);
  });
}
