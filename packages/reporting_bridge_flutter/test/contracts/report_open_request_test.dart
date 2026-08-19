import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  test(
    'ReportOpenRequest.reportType delegates to selectedTemplateCriteria',
    () {
      final request = ReportOpenRequest(
        seedData: const <String, dynamic>{'id': 1},
        selectedTemplateCriteria: SelectedTemplateCriteria(
          reportType: UrbReportType.salesInvoice,
          identity: const ReportIdentity(userId: '42', branchId: '01'),
          customType: 'demo_system_alpha',
        ),
        templateSyncRequest: TemplateSyncRequest(
          systemCode: UrbSystem.motakamelTransactions,
          identity: const ReportIdentity(userId: '42', branchId: '01'),
          filter: TemplateSyncFilter(
            reportTypes: <String>[UrbReportType.salesInvoice.value],
            layouts: <String>[ReportLayout.pages.value],
          ),
        ),
        compatibility: const TemplateCompatibilityConstraints(
          language: ReportLanguage.ar,
          layout: ReportLayout.pages,
          size: ReportPageSize.a4,
        ),
        reportName: 'Sales Invoice',
        requestId: 'req-1',
        initialTemplateId: 'tpl-1',
        presenterMode: PresenterModePreference.online,
        entryPolicy: ReportEntryPolicy.alwaysSelectTemplate,
        localeOverride: 'ar',
        featuresOverride: const BridgeUiFeatures(showPrint: true),
        actionPolicy: const ReportActionPolicy(canSharePdf: false),
        externalPrint: HostExternalPrintRequest(
          documentTitle: 'Invoice',
          extra: <String, Object?>{'channel': 'shop'},
        ),
      );

      expect(request.reportType, UrbReportType.salesInvoice);
      expect(
        identical(
          request.reportType,
          request.selectedTemplateCriteria.reportType,
        ),
        isTrue,
      );
      expect(request.templateSyncRequest.filter, isA<TemplateSyncFilter>());
      expect(request.templateSyncRequest.filter.reportTypes, <String>[
        'sales_invoice',
      ]);
      expect(request.compatibility.layout, ReportLayout.pages);
      expect(request.featuresOverride?.showPrint, isTrue);
      expect(request.actionPolicy.canSharePdf, isFalse);
      expect(request.externalPrint?.documentTitle, 'Invoice');
    },
  );

  test(
    'directPrintAfterSave defaults false and copyWith preserves overrides',
    () {
      final identity = const ReportIdentity(userId: 'u1');
      final criteria = SelectedTemplateCriteria(
        reportType: UrbReportType.salesInvoice,
        identity: identity,
      );
      final sync = TemplateSyncRequest(
        systemCode: UrbSystem.motakamelTransactions,
        identity: identity,
      );

      final implicit = ReportOpenRequest(
        seedData: const <String, dynamic>{'id': 1},
        selectedTemplateCriteria: criteria,
        templateSyncRequest: sync,
      );
      final explicit = ReportOpenRequest(
        seedData: const <String, dynamic>{'id': 2},
        selectedTemplateCriteria: criteria,
        templateSyncRequest: sync,
        directPrintAfterSave: true,
      );

      expect(implicit.directPrintAfterSave, isFalse);
      expect(explicit.directPrintAfterSave, isTrue);
      expect(explicit.copyWith().directPrintAfterSave, isTrue);
      expect(
        explicit.copyWith(directPrintAfterSave: false).directPrintAfterSave,
        isFalse,
      );
      expect(
        implicit.copyWith(directPrintAfterSave: true).directPrintAfterSave,
        isTrue,
      );
    },
  );

  test('TemplateSyncRequest defaults filter to core TemplateSyncFilter', () {
    final sync = TemplateSyncRequest(
      systemCode: UrbSystem.motakamelTransactions,
    );
    expect(sync.filter, isA<TemplateSyncFilter>());
    expect(sync.filter.reportTypes, <String>['all']);
    expect(sync.identity, const ReportIdentity());
    expect(sync.extra, isEmpty);
  });

  test('ReportOpenRequest keeps typed sync criteria and compatibility', () {
    final open = ReportOpenRequest(
      seedData: const <String, dynamic>{'id': 9},
      selectedTemplateCriteria: SelectedTemplateCriteria(
        reportType: UrbReportType.quotation,
        identity: const ReportIdentity(
          userId: 'u1',
          branchId: 'b1',
          systemUnit: 'MAIN',
        ),
        customType: 'custom_q',
      ),
      templateSyncRequest: TemplateSyncRequest(
        systemCode: UrbSystemCode('motakamel_transactions'),
        identity: const ReportIdentity(
          userId: 'u1',
          branchId: 'b1',
          systemUnit: 'MAIN',
        ),
        filter: TemplateSyncFilter(
          reportTypes: <String>[UrbReportType.quotation.value],
          sizes: <String>[ReportPageSize.a5.value],
        ),
        extra: const <String, Object?>{'transactionType': 'cash'},
      ),
      compatibility: const TemplateCompatibilityConstraints(
        size: ReportPageSize.a5,
      ),
      externalPrint: HostExternalPrintRequest(documentTitle: 'Quote'),
    );

    expect(open.reportType.value, 'quotation');
    expect(open.templateSyncRequest.systemCode.value, 'motakamel_transactions');
    expect(open.selectedTemplateCriteria.userId, 'u1');
    expect(open.selectedTemplateCriteria.customType, 'custom_q');
    expect(open.compatibility.size, ReportPageSize.a5);
    expect(open.externalPrint?.documentTitle, 'Quote');
  });
}
