import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('V5 selected-template identity', () {
    test('language/layout/size/server do not change the selection token', () {
      const base = ReportPreferenceScope(
        connectionKey: 'deployed|https://one.example',
        system: 'motakamel_transactions',
        reportType: 'sales_invoice',
        userId: '42',
        branchId: '01',
        systemUnit: 'MAIN',
        customType: 'demo_a',
        language: 'ar',
        layout: 'Pages',
        size: 'A4',
      );
      const differentLanguage = ReportPreferenceScope(
        connectionKey: 'deployed|https://one.example',
        system: 'motakamel_transactions',
        reportType: 'sales_invoice',
        userId: '42',
        branchId: '01',
        systemUnit: 'MAIN',
        customType: 'demo_a',
        language: 'en',
        layout: 'Pages',
        size: 'A4',
      );
      const differentLayout = ReportPreferenceScope(
        connectionKey: 'deployed|https://one.example',
        system: 'motakamel_transactions',
        reportType: 'sales_invoice',
        userId: '42',
        branchId: '01',
        systemUnit: 'MAIN',
        customType: 'demo_a',
        language: 'ar',
        layout: 'Thermal',
        size: 'A4',
      );
      const differentSize = ReportPreferenceScope(
        connectionKey: 'deployed|https://one.example',
        system: 'motakamel_transactions',
        reportType: 'sales_invoice',
        userId: '42',
        branchId: '01',
        systemUnit: 'MAIN',
        customType: 'demo_a',
        language: 'ar',
        layout: 'Pages',
        size: '80mm',
      );
      const differentServer = ReportPreferenceScope(
        connectionKey: 'deployed|https://two.example',
        system: 'other_system',
        reportType: 'sales_invoice',
        userId: '42',
        branchId: '01',
        systemUnit: 'MAIN',
        customType: 'demo_a',
        language: 'ar',
        layout: 'Pages',
        size: 'A4',
      );

      expect(
        base.selectedTemplateStorageToken,
        differentLanguage.selectedTemplateStorageToken,
      );
      expect(
        base.selectedTemplateStorageToken,
        differentLayout.selectedTemplateStorageToken,
      );
      expect(
        base.selectedTemplateStorageToken,
        differentSize.selectedTemplateStorageToken,
      );
      expect(
        base.selectedTemplateStorageToken,
        differentServer.selectedTemplateStorageToken,
      );
    });

    test('user/branch/systemUnit/customType change the selection token', () {
      const base = ReportPreferenceScope(
        connectionKey: 'deployed|https://one.example',
        reportType: 'sales_invoice',
        userId: '42',
        branchId: '01',
        systemUnit: 'MAIN',
        customType: 'demo_a',
      );
      expect(
        base.selectedTemplateStorageToken,
        isNot(
          const ReportPreferenceScope(
            connectionKey: 'deployed|https://one.example',
            reportType: 'sales_invoice',
            userId: '99',
            branchId: '01',
            systemUnit: 'MAIN',
            customType: 'demo_a',
          ).selectedTemplateStorageToken,
        ),
      );
      expect(
        base.selectedTemplateStorageToken,
        isNot(
          const ReportPreferenceScope(
            connectionKey: 'deployed|https://one.example',
            reportType: 'sales_invoice',
            userId: '42',
            branchId: '02',
            systemUnit: 'MAIN',
            customType: 'demo_a',
          ).selectedTemplateStorageToken,
        ),
      );
      expect(
        base.selectedTemplateStorageToken,
        isNot(
          const ReportPreferenceScope(
            connectionKey: 'deployed|https://one.example',
            reportType: 'sales_invoice',
            userId: '42',
            branchId: '01',
            systemUnit: 'ALT',
            customType: 'demo_a',
          ).selectedTemplateStorageToken,
        ),
      );
      expect(
        base.selectedTemplateStorageToken,
        isNot(
          const ReportPreferenceScope(
            connectionKey: 'deployed|https://one.example',
            reportType: 'sales_invoice',
            userId: '42',
            branchId: '01',
            systemUnit: 'MAIN',
            customType: 'demo_b',
          ).selectedTemplateStorageToken,
        ),
      );
    });
  });

  test('presenter mode stays independently scoped by server/system', () async {
    final store = await SharedPreferencesReportFlowPreferenceStore.create();
    const first = ReportPreferenceScope(
      connectionKey: 'deployed|https://one.example',
      system: 'system_a',
      reportType: 'sales_invoice',
      userId: '42',
    );
    const second = ReportPreferenceScope(
      connectionKey: 'deployed|https://two.example',
      system: 'system_b',
      reportType: 'sales_invoice',
      userId: '42',
    );

    await store.save(
      first,
      const ReportFlowPreferences(
        templateId: 'shared-template',
        mode: PresenterModePreference.online,
      ),
    );
    await store.save(
      second,
      const ReportFlowPreferences(
        templateId: 'shared-template',
        mode: PresenterModePreference.offline,
      ),
    );

    expect((await store.load(first))?.mode, PresenterModePreference.online);
    expect((await store.load(second))?.mode, PresenterModePreference.offline);
    expect(
      first.selectedTemplateStorageToken,
      second.selectedTemplateStorageToken,
    );
    expect(
      first.presenterModeStorageToken,
      isNot(second.presenterModeStorageToken),
    );
  });

  test(
    'migrates V4 into V5 selected-template + mode without deleting V4',
    () async {
      const scope = ReportPreferenceScope(
        connectionKey: 'deployed|https://legacy.example',
        systemId: 7,
        reportType: 'invoice',
        language: 'ar',
        layout: 'pages',
        size: 'a4',
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'urb.reporting_bridge.default.v4.${scope.storageToken}':
            jsonEncode(<String, dynamic>{
              'templateId': 'v4-template',
              'mode': 'offline',
              'language': 'ar',
              'layout': 'pages',
              'size': 'a4',
            }),
      });
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesReportFlowPreferenceStore(preferences);

      final migrated = await store.load(scope);

      expect(migrated?.templateId, 'v4-template');
      expect(migrated?.mode, PresenterModePreference.offline);
      expect(
        preferences.getString(
          'urb.reporting_bridge.selected_template.v5.${scope.selectedTemplateStorageToken}',
        ),
        jsonEncode(<String, dynamic>{'templateId': 'v4-template'}),
      );
      expect(
        preferences.getString(
          'urb.reporting_bridge.presenter_mode.v1.${scope.presenterModeStorageToken}',
        ),
        jsonEncode(<String, dynamic>{'mode': 'offline'}),
      );
      expect(
        preferences.getString(
          'urb.reporting_bridge.default.v4.${scope.storageToken}',
        ),
        isNotNull,
      );
    },
  );

  test('concurrent scoped writes preserve distinct report defaults', () async {
    final preferences = await SharedPreferences.getInstance();
    final firstStore = SharedPreferencesReportFlowPreferenceStore(preferences);
    final secondStore = SharedPreferencesReportFlowPreferenceStore(preferences);
    const firstScope = ReportPreferenceScope(
      connectionKey: 'deployed|https://one.example',
      systemId: 1,
      reportType: 'invoice',
    );
    const secondScope = ReportPreferenceScope(
      connectionKey: 'deployed|https://two.example',
      systemId: 2,
      reportType: 'voucher',
    );

    await Future.wait<void>(<Future<void>>[
      firstStore.save(
        firstScope,
        const ReportFlowPreferences(
          templateId: 'invoice-template',
          mode: PresenterModePreference.online,
        ),
      ),
      secondStore.save(
        secondScope,
        const ReportFlowPreferences(
          templateId: 'voucher-template',
          mode: PresenterModePreference.offline,
        ),
      ),
    ]);

    expect((await firstStore.load(firstScope))?.templateId, 'invoice-template');
    expect(
      (await secondStore.load(secondScope))?.templateId,
      'voucher-template',
    );
    expect(
      (await secondStore.load(secondScope))?.mode,
      PresenterModePreference.offline,
    );
  });

  test(
    'remove clears one selected-template identity without touching another',
    () async {
      final store = SharedPreferencesReportFlowPreferenceStore(
        await SharedPreferences.getInstance(),
      );
      const first = ReportPreferenceScope(
        connectionKey: 'deployed|first',
        systemId: 1,
        reportType: 'invoice',
        customType: 'a',
      );
      const second = ReportPreferenceScope(
        connectionKey: 'deployed|second',
        systemId: 1,
        reportType: 'invoice',
        customType: 'b',
      );
      const value = ReportFlowPreferences(
        templateId: 'template',
        mode: PresenterModePreference.online,
      );

      await store.save(first, value);
      await store.save(second, value);
      await store.remove(first);

      expect(await store.load(first), isNull);
      expect((await store.load(second))?.templateId, 'template');
    },
  );

  test('migrates a matching v2 map entry into V5 storage', () async {
    const source = 'https://legacy.example/UltimateReport/backend';
    SharedPreferences.setMockInitialValues(<String, Object>{
      'erp_host.report_defaults.v2': jsonEncode(<String, dynamic>{
        '${Uri.encodeComponent(source)}|7|invoice': <String, dynamic>{
          'templateId': 'legacy-template',
          'runMode': 'offline',
        },
      }),
    });
    final store = SharedPreferencesReportFlowPreferenceStore(
      await SharedPreferences.getInstance(),
    );
    const scope = ReportPreferenceScope(
      connectionKey:
          'deployed|https://legacy.example|https://legacy.example/UltimateReport/backend/',
      systemId: 7,
      reportType: 'invoice',
    );

    final migrated = await store.load(scope);
    final secondRead = await store.load(scope);

    expect(migrated?.templateId, 'legacy-template');
    expect(migrated?.mode, PresenterModePreference.offline);
    expect(secondRead?.templateId, 'legacy-template');
  });

  test('migrates a matching v1 map entry into V5 storage', () async {
    const source = 'https://legacy-v1.example';
    SharedPreferences.setMockInitialValues(<String, Object>{
      'erp_host.report_defaults.v1': jsonEncode(<String, dynamic>{
        '${Uri.encodeComponent(source)}|7|invoice': <String, dynamic>{
          'templateId': 'legacy-v1-template',
          'runMode': 'offline',
        },
      }),
    });
    final store = SharedPreferencesReportFlowPreferenceStore(
      await SharedPreferences.getInstance(),
    );
    const scope = ReportPreferenceScope(
      connectionKey:
          'deployed|https://legacy-v1.example|https://legacy-v1.example/api|https://legacy-v1.example/presenter|8000|8080',
      systemId: 7,
      reportType: 'invoice',
    );

    final migrated = await store.load(scope);

    expect(migrated?.templateId, 'legacy-v1-template');
    expect(migrated?.mode, PresenterModePreference.offline);
  });

  test('migrates matching standalone template and mode settings', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'erp_host.server_url': 'https://standalone.example/',
      'erp_host.server_profile': 'deployed',
      'erp_host.system_id': 9,
      'erp_host.report_type': 'report',
      'erp_host.template_id': 'standalone-template',
      'erp_host.run_mode': 'offline',
    });
    final store = SharedPreferencesReportFlowPreferenceStore(
      await SharedPreferences.getInstance(),
    );
    const scope = ReportPreferenceScope(
      connectionKey:
          'deployed|https://standalone.example|https://standalone.example/api|https://standalone.example/presenter|8000|8080',
      systemId: 9,
      reportType: 'report',
    );

    final migrated = await store.load(scope);

    expect(migrated?.templateId, 'standalone-template');
    expect(migrated?.mode, PresenterModePreference.offline);
  });

  test('does not migrate defaults from another server profile', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'erp_host.report_defaults.v2': jsonEncode(<String, dynamic>{
        '${Uri.encodeComponent('deployed:https://profile.example')}|7|invoice':
            <String, dynamic>{
              'templateId': 'deployed-template',
              'runMode': 'online',
            },
      }),
    });
    final store = SharedPreferencesReportFlowPreferenceStore(
      await SharedPreferences.getInstance(),
    );
    const scope = ReportPreferenceScope(
      connectionKey:
          'localDevelopment|https://profile.example|http://profile.example:8000/api|http://profile.example:8080|8000|8080',
      systemId: 7,
      reportType: 'invoice',
    );

    expect(await store.load(scope), isNull);
  });
}
