import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:reporting_bridge_flutter/src/flow/report_flow_controller_impl.dart';
import 'package:reporting_bridge_flutter/src/flow/report_flow_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test_open_request.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('customType case identity', () {
    test('case variants produce different selected-template identities', () {
      const upper = ReportPreferenceScope(
        connectionKey: 'deployed|https://one.example',
        system: 'legacy_system_1',
        reportType: 'sales_invoice',
        customType: 'POS_Invoice',
      );
      const lower = ReportPreferenceScope(
        connectionKey: 'deployed|https://one.example',
        system: 'legacy_system_1',
        reportType: 'sales_invoice',
        customType: 'pos_invoice',
      );
      expect(
        upper.selectedTemplateStorageToken,
        isNot(lower.selectedTemplateStorageToken),
      );
    });

    test('trimming surrounding whitespace keeps the same identity', () {
      const trimmed = ReportPreferenceScope(
        connectionKey: 'deployed|https://one.example',
        system: 'legacy_system_1',
        reportType: 'sales_invoice',
        customType: 'POS_Invoice',
      );
      const padded = ReportPreferenceScope(
        connectionKey: 'deployed|https://one.example',
        system: 'legacy_system_1',
        reportType: 'sales_invoice',
        customType: ' POS_Invoice ',
      );
      expect(
        trimmed.selectedTemplateStorageToken,
        padded.selectedTemplateStorageToken,
      );
    });
  });

  group('legacy migration via final ReportOpenRequest flow', () {
    late Directory root;
    late ReportServerConnection connection;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      root = Directory.systemTemp.createTempSync('urb-pref-flow-');
      connection = ReportServerConnection(
        endpoints: ReportServerEndpoints.deployed(
          Uri.parse('https://legacy.example'),
        ),
        cacheRoot: root,
      );
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    Future<void> expectMigrates({
      required Map<String, Object> seeded,
      required String templateId,
      required PresenterModePreference mode,
      String system = 'legacy_system_7',
    }) async {
      SharedPreferences.setMockInitialValues(seeded);
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesReportFlowPreferenceStore(prefs);
      final bridge = _CatalogBridge(root, templateId: templateId);
      final controller = _openController(
        connection: connection,
        bridge: bridge,
        preferences: store,
        system: system,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.value.selectedTemplateId, templateId);
      expect(controller.value.selectedMode, mode);
    }

    test('V1 migrates when systemCode is legacy_system_<id>', () async {
      final source = connection.endpoints.apiBaseUrl.origin;
      await expectMigrates(
        seeded: <String, Object>{
          'erp_host.report_defaults.v1': jsonEncode(<String, dynamic>{
            '${Uri.encodeComponent(source)}|7|sales_invoice': <String, dynamic>{
              'templateId': 'v1-template',
              'mode': 'offline',
            },
          }),
        },
        templateId: 'v1-template',
        mode: PresenterModePreference.offline,
      );
    });

    test('V2 migrates when systemCode is legacy_system_<id>', () async {
      final source = connection.endpoints.apiBaseUrl.origin;
      await expectMigrates(
        seeded: <String, Object>{
          'erp_host.report_defaults.v2': jsonEncode(<String, dynamic>{
            '${Uri.encodeComponent(source)}|7|sales_invoice': <String, dynamic>{
              'templateId': 'v2-template',
              'mode': 'online',
            },
          }),
        },
        templateId: 'v2-template',
        mode: PresenterModePreference.online,
      );
    });

    test('V3 migrates when systemCode is legacy_system_<id>', () async {
      final scope = ReportPreferenceScope(
        connectionKey: connection.preferenceSourceKey,
        system: 'legacy_system_7',
        reportType: 'sales_invoice',
      );
      await expectMigrates(
        seeded: <String, Object>{
          'urb.reporting_bridge.default.v3.${scope.legacyV3StorageToken}':
              jsonEncode(<String, dynamic>{
                'templateId': 'v3-template',
                'mode': 'offline',
              }),
        },
        templateId: 'v3-template',
        mode: PresenterModePreference.offline,
      );
    });

    test('V4 migrates through final Host flow', () async {
      final scope = ReportPreferenceScope(
        connectionKey: connection.preferenceSourceKey,
        system: 'legacy_system_7',
        reportType: 'sales_invoice',
      );
      await expectMigrates(
        seeded: <String, Object>{
          'urb.reporting_bridge.default.v4.${scope.storageToken}': jsonEncode(
            <String, dynamic>{'templateId': 'v4-template', 'mode': 'offline'},
          ),
        },
        templateId: 'v4-template',
        mode: PresenterModePreference.offline,
      );
    });

    test(
      'non-legacy systemCode does not silently adopt numeric V1 records',
      () async {
        // Canonical Host code `motakamel_transactions` has no deterministic
        // V1–V3 numeric mapping authority in-repo (docs example id=3 vs test
        // fixtures id=7). Migration must ignore numeric V1 records.
        final source = connection.endpoints.apiBaseUrl.origin;
        SharedPreferences.setMockInitialValues(<String, Object>{
          'erp_host.report_defaults.v1': jsonEncode(<String, dynamic>{
            '${Uri.encodeComponent(source)}|7|sales_invoice': <String, dynamic>{
              'templateId': 'foreign-template',
              'mode': 'offline',
            },
          }),
        });
        final prefs = await SharedPreferences.getInstance();
        final store = SharedPreferencesReportFlowPreferenceStore(prefs);
        final bridge = _CatalogBridge(
          root,
          templateId: 'foreign-template',
          extraTemplateIds: const <String>['other-a', 'other-b'],
        );
        final controller = _openController(
          connection: connection,
          bridge: bridge,
          preferences: store,
          system: UrbSystem.motakamelTransactions.value,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        expect(controller.value.selectedTemplateId, isNull);
        final scope = ReportPreferenceScope(
          connectionKey: connection.preferenceSourceKey,
          system: UrbSystem.motakamelTransactions.value,
          reportType: 'sales_invoice',
        );
        expect(await store.load(scope), isNull);
        expect(
          prefs.getKeys().where((key) => key.contains('selected_template.v5.')),
          isEmpty,
        );
      },
    );

    test('new writes remain V5 only', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesReportFlowPreferenceStore(prefs);
      final scope = ReportPreferenceScope(
        connectionKey: connection.preferenceSourceKey,
        system: 'legacy_system_1',
        reportType: 'sales_invoice',
      );
      await store.save(
        scope,
        const ReportFlowPreferences(
          templateId: 'fresh',
          mode: PresenterModePreference.online,
        ),
      );
      expect(
        prefs.getKeys().where((key) => key.contains('selected_template.v5.')),
        isNotEmpty,
      );
      expect(
        prefs.getKeys().where(
          (key) =>
              key.contains('default.v4.') ||
              key.contains('default.v3.') ||
              key == 'erp_host.report_defaults.v2' ||
              key == 'erp_host.report_defaults.v1',
        ),
        isEmpty,
      );
    });
  });

  group('request-scoped catalog absence preserves persisted identity', () {
    test('preserves saved selection and independent offline mode', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final root = Directory.systemTemp.createTempSync('urb-mode-iso-');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final connection = ReportServerConnection(
        endpoints: ReportServerEndpoints.deployed(
          Uri.parse('https://example.test'),
        ),
        cacheRoot: root,
      );
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesReportFlowPreferenceStore(prefs);
      final scope = ReportPreferenceScope(
        connectionKey: connection.preferenceSourceKey,
        system: 'legacy_system_1',
        reportType: 'sales_invoice',
      );
      await store.save(
        scope,
        const ReportFlowPreferences(
          templateId: 'gone-template',
          mode: PresenterModePreference.offline,
        ),
      );

      final bridge = _CatalogBridge(root, templateId: 'alive');
      final controller = _openController(
        connection: connection,
        bridge: bridge,
        preferences: store,
        system: 'legacy_system_1',
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(controller.value.selectedTemplateId, isNot('gone-template'));
      expect(controller.value.selectedMode, PresenterModePreference.offline);
      expect(
        prefs.getString(
          'urb.reporting_bridge.presenter_mode.v1.${scope.presenterModeStorageToken}',
        ),
        contains('offline'),
      );
      expect(
        prefs.getString(
          'urb.reporting_bridge.selected_template.v5.${scope.selectedTemplateStorageToken}',
        ),
        contains('gone-template'),
      );
    });
  });
}

ReportFlowControllerImpl _openController({
  required ReportServerConnection connection,
  required ReportingBridgeClient bridge,
  required ReportFlowPreferenceStore preferences,
  required String system,
}) {
  return ReportFlowControllerImpl(
    request: buildTestOpenRequest(
      system: system,
      reportType: 'sales_invoice',
      entryPolicy: ReportEntryPolicy.smart,
    ),
    features: const BridgeUiFeatures(),
    runtime: ReportFlowRuntime(
      connection: connection,
      bridgeClient: bridge,
      preferences: preferences,
      filePlatform: const _NoopFiles(),
      surfaceBinding: PresenterSurfaceBinding(),
    ),
  );
}

final class _CatalogBridge extends ReportingBridgeClient {
  _CatalogBridge(
    Directory root, {
    required String templateId,
    List<String> extraTemplateIds = const <String>[],
  }) : templates = <CachedTemplate>[
         _pagesTemplate(templateId),
         for (final id in extraTemplateIds) _pagesTemplate(id),
       ],
       super(
         apiBaseUrl: Uri.parse(
           'https://legacy.example/UltimateReport/backend/api/',
         ),
         presenterEntryUrl: Uri.parse(
           'https://legacy.example/UltimateReport/apps/presenter/',
         ),
         bridgeRoot: root,
       );

  List<CachedTemplate> templates;

  @override
  Future<TemplateSyncSummary> syncTemplates({
    String? systemCode,
    int? systemId,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async => TemplateSyncSummary(
    syncedCount: templates.length,
    listCount: templates.length,
    errors: const <String>[],
  );

  @override
  Future<List<CachedTemplate>> listTemplates({
    String? systemCode,
    int? systemId,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async => templates;

  @override
  Future<ReportingBridgeStatus> getStatus() async => ReportingBridgeStatus(
    apiBaseUrl: apiBaseUrl.toString(),
    presenterCached: true,
    templateCount: templates.length,
  );

  @override
  Future<void> updateIdentityContext(BridgeIdentityContext identity) async {}

  @override
  Future<void> clearIdentityContext() async {}
}

CachedTemplate _pagesTemplate(String id) => CachedTemplate(
  id: id,
  type: 'sales_invoice',
  systemId: 7,
  code: 'legacy_system_7',
  name: id,
  document: <String, dynamic>{
    'schemaVersion': '1.0.0',
    'meta': const <String, dynamic>{
      'name': 'Invoice',
      'family': 'sales_invoice',
    },
    'page': const <String, dynamic>{
      'layout': 'Pages',
      'size': 'A4',
      'unit': 'mm',
      'orientation': 'portrait',
      'language': 'en',
      'direction': 'ltr',
      'width': 210,
      'height': 297,
    },
    'styleTokens': const <String, dynamic>{},
    'assets': const <dynamic>[],
    'layers': const <dynamic>[],
    'elements': const <dynamic>[],
  },
);

final class _NoopFiles implements ReportFilePlatform {
  const _NoopFiles();

  @override
  Future<bool> savePdf(bytes, String filename) async => true;

  @override
  Future<void> sharePdf(bytes, String filename) async {}
}
