import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  const base = ReportPreferenceScope(
    connectionKey: 'deployed|https://example.test/api',
    tenantId: 'tenant-a',
    branchId: 'branch-a',
    userId: 'user-a',
    systemUnit: 'sales',
    system: 'motakamel_transactions',
    reportType: 'sales_invoice',
    language: 'ar',
    layout: 'pages',
    size: 'a4',
    customType: 'standard',
  );

  test(
    'selected-template token is System-scoped and ignores presentation/source',
    () {
      expect(base.selectedTemplateCanonical, contains('report=sales_invoice'));
      expect(base.selectedTemplateCanonical, contains('user=user-a'));
      expect(base.selectedTemplateCanonical, contains('branch=branch-a'));
      expect(base.selectedTemplateCanonical, contains('systemUnit=sales'));
      expect(base.selectedTemplateCanonical, contains('customType=standard'));
      expect(base.selectedTemplateCanonical, isNot(contains('language=')));
      expect(base.selectedTemplateCanonical, isNot(contains('layout=')));
      expect(base.selectedTemplateCanonical, isNot(contains('size=')));
      expect(base.selectedTemplateCanonical, isNot(contains('source=')));
      expect(
        base.selectedTemplateCanonical,
        contains('system=motakamel_transactions'),
      );
    },
  );

  test('presenter-mode token keeps connection and system scope', () {
    expect(base.presenterModeCanonical, contains('source='));
    expect(
      base.presenterModeCanonical,
      contains('system=motakamel_transactions'),
    );
    expect(base.presenterModeCanonical, contains('report=sales_invoice'));
    expect(base.presenterModeCanonical, isNot(contains('language=')));
  });

  test('user-context rotation receives an independent preference', () async {
    final store = MemoryReportFlowPreferenceStore();
    const first = ReportFlowPreferences(
      templateCode: 'TEMPLATE-A',
      mode: PresenterModePreference.online,
    );
    const rotated = ReportPreferenceScope(
      connectionKey: 'deployed|https://example.test/api',
      tenantId: 'tenant-a',
      branchId: 'branch-a',
      userId: 'user-b',
      systemUnit: 'sales',
      system: 'motakamel_transactions',
      reportType: 'sales_invoice',
      language: 'ar',
      layout: 'pages',
      size: 'a4',
      customType: 'standard',
    );

    await store.save(base, first);

    expect((await store.load(base))?.templateCode, 'TEMPLATE-A');
    expect(await store.load(rotated), isNull);
  });

  test('preference JSON still decodes legacy selector fields', () {
    const preferences = ReportFlowPreferences(
      templateId: 'template-a',
      mode: PresenterModePreference.offline,
      language: 'ar',
      layout: 'thermal',
      size: '80mm',
      customType: 'receipt',
    );

    final decoded = ReportFlowPreferences.fromJson(preferences.toJson())!;

    expect(decoded.templateId, 'template-a');
    expect(decoded.mode, PresenterModePreference.offline);
    expect(decoded.language, 'ar');
    expect(decoded.layout, 'thermal');
    expect(decoded.size, '80mm');
    expect(decoded.customType, 'receipt');
  });
}
