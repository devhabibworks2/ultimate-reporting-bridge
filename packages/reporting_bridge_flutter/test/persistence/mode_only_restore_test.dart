import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:reporting_bridge_flutter/src/flow/report_flow_controller_impl.dart';
import 'package:reporting_bridge_flutter/src/flow/report_flow_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test_open_request.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late ReportServerConnection connection;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    root = Directory.systemTemp.createTempSync('urb-mode-only-');
    connection = ReportServerConnection(
      endpoints: ReportServerEndpoints.deployed(
        Uri.parse('https://example.test'),
      ),
      cacheRoot: root,
    );
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> expectModeOnlyRestore({
    required PresenterModePreference mode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final store = SharedPreferencesReportFlowPreferenceStore(prefs);
    final scope = ReportPreferenceScope(
      connectionKey: connection.preferenceSourceKey,
      system: 'legacy_system_1',
      reportType: 'sales_invoice',
    );

    await store.save(scope, ReportFlowPreferences(templateId: 'T', mode: mode));

    await store.removeSelectedTemplate(scope);
    expect(
      prefs.getString(
        'urb.reporting_bridge.selected_template.v5.${scope.selectedTemplateStorageToken}',
      ),
      isNull,
    );
    expect(
      prefs.getString(
        'urb.reporting_bridge.presenter_mode.v1.${scope.presenterModeStorageToken}',
      ),
      contains(mode.name),
    );

    final bridge = _CatalogBridge(root, templateIds: <String>['alive']);
    final controller = ReportFlowControllerImpl(
      request: buildTestOpenRequest(
        system: 'legacy_system_1',
        entryPolicy: ReportEntryPolicy.smart,
      ),
      runtime: ReportFlowRuntime(
        connection: connection,
        bridgeClient: bridge,
        preferences: SharedPreferencesReportFlowPreferenceStore(prefs),
        filePlatform: const _NoopFiles(),
        surfaceBinding: PresenterSurfaceBinding(),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    expect(controller.value.selectedMode, mode);
    expect(controller.value.selectedTemplateId, isNot('T'));
    expect(
      controller.value.stage,
      anyOf(
        ReportFlowStage.preparingResources,
        ReportFlowStage.selectingTemplate,
        ReportFlowStage.previewing,
      ),
    );

    final reloaded = await store.load(scope);
    expect(reloaded?.templateId, isNull);
    expect(reloaded?.mode, mode);
  }

  test('mode-only save clears an existing V5 selected-template key', () async {
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
        templateId: 'stale-template',
        mode: PresenterModePreference.online,
      ),
    );
    await store.save(
      scope,
      const ReportFlowPreferences(
        templateId: null,
        mode: PresenterModePreference.offline,
      ),
    );

    expect(
      prefs.getString(
        'urb.reporting_bridge.selected_template.v5.${scope.selectedTemplateStorageToken}',
      ),
      isNull,
    );
    final reloaded = await store.load(scope);
    expect(reloaded?.templateId, isNull);
    expect(reloaded?.mode, PresenterModePreference.offline);
  });

  test('mode-only preferences round-trip and copyWith can clear template', () {
    const selected = ReportFlowPreferences(
      templateId: 'T',
      mode: PresenterModePreference.online,
    );
    final modeOnly = selected.copyWith(
      clearTemplateId: true,
      mode: PresenterModePreference.offline,
    );

    expect(modeOnly.templateId, isNull);
    expect(modeOnly.mode, PresenterModePreference.offline);
    final decoded = ReportFlowPreferences.fromJson(modeOnly.toJson());
    expect(decoded?.templateId, isNull);
    expect(decoded?.mode, PresenterModePreference.offline);
  });

  test('mode-only offline restores on a new controller', () async {
    await expectModeOnlyRestore(mode: PresenterModePreference.offline);
  });

  test('mode-only online restores on a new controller', () async {
    await expectModeOnlyRestore(mode: PresenterModePreference.online);
  });
}

final class _CatalogBridge extends ReportingBridgeClient {
  _CatalogBridge(Directory root, {required List<String> templateIds})
    : templates = <CachedTemplate>[
        for (final id in templateIds) _pagesTemplate(id),
      ],
      super(
        apiBaseUrl: Uri.parse(
          'https://example.test/UltimateReport/backend/api/',
        ),
        presenterEntryUrl: Uri.parse(
          'https://example.test/UltimateReport/apps/presenter/',
        ),
        bridgeRoot: root,
      );

  final List<CachedTemplate> templates;

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
  systemId: 1,
  name: id,
  document: const <String, dynamic>{
    'schemaVersion': '1.0.0',
    'meta': <String, dynamic>{'name': 'Invoice', 'family': 'sales_invoice'},
    'page': <String, dynamic>{
      'layout': 'Pages',
      'size': 'A4',
      'unit': 'mm',
      'orientation': 'portrait',
      'language': 'ar',
      'direction': 'rtl',
      'width': 210,
      'height': 297,
    },
    'styleTokens': <String, dynamic>{},
    'assets': <dynamic>[],
    'layers': <dynamic>[],
    'elements': <dynamic>[],
  },
);

class _NoopFiles implements ReportFilePlatform {
  const _NoopFiles();

  @override
  Future<bool> savePdf(Uint8List bytes, String filename) async => true;

  @override
  Future<void> sharePdf(Uint8List bytes, String filename) async {}
}
