import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:reporting_bridge_flutter/src/flow/report_flow_controller_impl.dart';
import 'package:reporting_bridge_flutter/src/flow/report_flow_runtime.dart';

import '../test_open_request.dart';

void main() {
  test(
    'stale saved selection requires explicit reselection without auto substitute',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'urb-template-code-stale-',
      );
      addTearDown(() async {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });

      final preferences = _StalePreferenceStore();
      final bridge = _SingleTemplateBridgeClient(root);
      final controller = ReportFlowControllerImpl(
        request: buildTestOpenRequest(
          system: 'legacy_system_1',
          reportType: 'sales_invoice',
          entryPolicy: ReportEntryPolicy.smart,
        ),
        runtime: ReportFlowRuntime(
          connection: ReportServerConnection(
            endpoints: ReportServerEndpoints.deployed(
              Uri.parse('https://example.test'),
            ),
            cacheRoot: root,
          ),
          bridgeClient: bridge,
          preferences: preferences,
          filePlatform: _NoopFilePlatform(),
          surfaceBinding: PresenterSurfaceBinding(),
        ),
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.value.stage, ReportFlowStage.selectingTemplate);
      expect(controller.value.selectedTemplateId, isNull);
      expect(controller.value.committedTemplateId, isNull);
      expect(controller.value.presenterLaunch, isNull);
      expect(bridge.prepareCalls, 0);
    },
  );
}

CachedTemplate _template() => const CachedTemplate(
  id: '17',
  type: 'sales_invoice',
  systemId: 1,
  systemCode: 'legacy_system_1',
  code: 'INV-A5-AR',
  name: 'Invoice A5 Arabic',
  version: '1.0.0',
  document: <String, dynamic>{
    'schemaVersion': '1.0.0',
    'meta': <String, dynamic>{
      'name': 'Invoice A5 Arabic',
      'family': 'sales_invoice',
      'code': 'INV-A5-AR',
      'systemCode': 'legacy_system_1',
    },
    'page': <String, dynamic>{
      'layout': 'Pages',
      'size': 'A5',
      'unit': 'mm',
      'orientation': 'portrait',
      'language': 'ar',
      'direction': 'rtl',
      'width': 148,
      'height': 210,
    },
    'styleTokens': <String, dynamic>{},
    'assets': <dynamic>[],
    'layers': <dynamic>[],
    'elements': <dynamic>[],
  },
);

class _SingleTemplateBridgeClient extends ReportingBridgeClient {
  _SingleTemplateBridgeClient(Directory root)
    : super(
        apiBaseUrl: Uri.parse('https://example.test/UltimateReport/backend/'),
        presenterEntryUrl: Uri.parse(
          'https://example.test/UltimateReport/apps/presenter/index.html',
        ),
        bridgeRoot: root,
      );

  int prepareCalls = 0;

  @override
  Future<List<CachedTemplate>> listTemplates({
    String? systemCode,
    int? systemId,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async => <CachedTemplate>[_template()];

  @override
  Future<TemplateSyncSummary> syncTemplates({
    String? systemCode,
    int? systemId,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async => const TemplateSyncSummary(
    syncedCount: 1,
    listCount: 1,
    errors: <String>[],
  );

  @override
  Future<ReportingBridgeStatus> getStatus() async => ReportingBridgeStatus(
    apiBaseUrl: apiBaseUrl.toString(),
    presenterCached: true,
    templateCount: 1,
  );

  @override
  Future<PresenterSessionLaunch> prepareSession(
    PresenterSessionRequest request,
  ) async {
    prepareCalls += 1;
    return const PresenterSessionLaunch(
      presenterUrl: 'https://presenter.test/session',
      sessionId: 'session',
      presenterVersion: '1.0.0',
      presenterDevVersion: 1,
    );
  }

  @override
  Future<void> dispose() async {}
}

class _StalePreferenceStore implements ReportFlowPreferenceStore {
  ReportFlowPreferences? value = const ReportFlowPreferences(
    templateId: 'missing-legacy-id',
    mode: PresenterModePreference.online,
  );

  @override
  Future<ReportFlowPreferences?> load(ReportPreferenceScope scope) async =>
      value;

  @override
  Future<void> save(
    ReportPreferenceScope scope,
    ReportFlowPreferences preferences,
  ) async {
    value = preferences;
  }

  @override
  Future<void> remove(ReportPreferenceScope scope) async {
    value = null;
  }

  @override
  Future<void> removeSelectedTemplate(ReportPreferenceScope scope) async {
    final current = value;
    if (current == null) return;
    value = ReportFlowPreferences(mode: current.mode);
  }
}

class _NoopFilePlatform implements ReportFilePlatform {
  @override
  Future<bool> savePdf(Uint8List bytes, String filename) async => true;

  @override
  Future<void> sharePdf(Uint8List bytes, String filename) async {}
}
