import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import '../test_open_request.dart';
import 'package:reporting_bridge_flutter/src/flow/report_flow_controller_impl.dart';
import 'package:reporting_bridge_flutter/src/flow/report_flow_runtime.dart';

void main() {
  test(
    'Settings template Cancel uses the real controller return contract',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'urb-flow-screen-real-controller-',
      );
      final bridge = _UiBridgeClient(root, <CachedTemplate>[
        _template('t1'),
        _template('t2'),
      ]);
      final preferences = _UiPreferenceStore();
      final controller = ReportFlowControllerImpl(
        request: buildTestOpenRequest(
          system: 'legacy_system_1',
          reportType: 'sales_invoice',
          entryPolicy: ReportEntryPolicy.alwaysPrepare,
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
          filePlatform: _UiFilePlatform(),
          surfaceBinding: PresenterSurfaceBinding(),
        ),
        renderTimeout: Duration.zero,
      );

      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });

      await controller.initialize().timeout(const Duration(seconds: 10));

      await controller.continueFromPreparation().timeout(
        const Duration(seconds: 10),
      );
      controller.selectTemplate('t1');

      await controller.preparePreview().timeout(const Duration(seconds: 10));

      controller.presenterLoadStarted();
      controller.presenterProtocolDetected(BridgeContract.payloadVersion);
      controller.completePresenterRender(
        sessionId: controller.value.presenterLaunch?.sessionId,
      );
      expect(controller.value.stage, ReportFlowStage.previewing);
      final launch = controller.value.presenterLaunch;

      controller.editSettings();
      controller.openTemplateSelection(
        origin: TemplateSelectionOrigin.reportSettings,
      );
      controller.selectTemplate('t2');

      expect(controller.value.settingsDraft?.templateId, 't1');
      expect(controller.value.selectedTemplateId, 't2');

      controller.cancelSettings();

      expect(controller.value.stage, ReportFlowStage.previewing);
      expect(controller.value.settingsDraft, isNull);
      expect(controller.value.selectedTemplateId, 't1');
      expect(controller.value.selectedMode, PresenterModePreference.online);
      expect(controller.value.presenterLaunch, same(launch));

      await controller.dispose().timeout(const Duration(seconds: 10));
    },
  );

  test(
    'render failure retry keeps the Presenter surface reload contract',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'urb-flow-retry-surface-',
      );
      final bridge = _UiBridgeClient(root, <CachedTemplate>[_template('t1')]);
      final controller = ReportFlowControllerImpl(
        request: buildTestOpenRequest(
          system: 'legacy_system_1',
          reportType: 'sales_invoice',
          entryPolicy: ReportEntryPolicy.alwaysPrepare,
        ),
        runtime: ReportFlowRuntime(
          connection: ReportServerConnection(
            endpoints: ReportServerEndpoints.deployed(
              Uri.parse('https://example.test'),
            ),
            cacheRoot: root,
          ),
          bridgeClient: bridge,
          preferences: _UiPreferenceStore(),
          filePlatform: _UiFilePlatform(),
          surfaceBinding: PresenterSurfaceBinding(),
        ),
      );
      addTearDown(() async {
        await controller.dispose();
        if (root.existsSync()) root.deleteSync(recursive: true);
      });

      await controller.initialize();
      await controller.continueFromPreparation();
      controller.selectTemplate('t1');
      await controller.preparePreview();
      final launch = controller.value.presenterLaunch!;
      var reloads = 0;
      controller.presenterSurface.attach(
        sessionId: launch.sessionId,
        templateName: controller.value.selectedTemplate!.templateName,
        evaluateJavaScript: (_) async => null,
        reload: () async {
          reloads += 1;
        },
        onLifecycle: (_) {},
      );

      controller.failPresenterRender(
        'render failed',
        sessionId: launch.sessionId,
      );
      expect(controller.value.stage, ReportFlowStage.failed);
      expect(controller.presenterSurface.attached, isTrue);

      await controller.retry();

      expect(reloads, 1);
      expect(controller.presenterSurface.attached, isTrue);
      expect(controller.value.renderStatus, PresenterRenderStatus.loading);
    },
  );
}

CachedTemplate _template(String id) => CachedTemplate(
  id: id,
  type: 'sales_invoice',
  systemId: 1,
  code: 'CODE-$id',
  name: 'Template $id',
  version: '1.0.0',
  document: <String, dynamic>{
    'schemaVersion': '1.0.0',
    'meta': <String, dynamic>{
      'name': 'Invoice',
      'family': 'sales_invoice',
      'code': 'CODE-$id',
    },
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

class _UiBridgeClient extends ReportingBridgeClient {
  _UiBridgeClient(Directory root, this.templates)
    : super(
        apiBaseUrl: Uri.parse('https://example.test/backend/'),
        presenterEntryUrl: Uri.parse('https://example.test/presenter/'),
        bridgeRoot: root,
      );

  final List<CachedTemplate> templates;

  @override
  Future<List<CachedTemplate>> listTemplates({
    String? systemCode,
    int? systemId,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async => List<CachedTemplate>.unmodifiable(templates);

  @override
  Future<ReportingBridgeStatus> getStatus() async => ReportingBridgeStatus(
    apiBaseUrl: apiBaseUrl.toString(),
    presenterCached: false,
    templateCount: templates.length,
  );

  @override
  Future<PresenterSessionLaunch> prepareSession(
    PresenterSessionRequest request,
  ) async {
    final sessionId = request.sessionId ?? 'ui-test-session';
    return PresenterSessionLaunch(
      presenterUrl: 'https://example.test/presenter/?sessionId=$sessionId',
      sessionId: sessionId,
      presenterVersion: '1.0.0',
      presenterDevVersion: 1,
    );
  }

  @override
  Future<PresenterSessionLaunch> prepareReplacementSession(
    PresenterSessionRequest request,
  ) => prepareSession(request);

  @override
  Future<void> commitReplacementSession() async {}

  @override
  Future<void> discardReplacementSession() async {}

  @override
  Future<void> stopSession() async {}
}

class _UiPreferenceStore implements ReportFlowPreferenceStore {
  ReportFlowPreferences? value;

  @override
  Future<ReportFlowPreferences?> load(ReportPreferenceScope scope) async =>
      value;

  @override
  Future<void> remove(ReportPreferenceScope scope) async {
    value = null;
  }

  @override
  Future<void> removeSelectedTemplate(ReportPreferenceScope scope) async {
    if (value == null) return;
    value = ReportFlowPreferences(templateId: null, mode: value!.mode);
  }

  @override
  Future<void> save(
    ReportPreferenceScope scope,
    ReportFlowPreferences preferences,
  ) async {
    value = preferences;
  }
}

class _UiFilePlatform implements ReportFilePlatform {
  @override
  Future<bool> savePdf(Uint8List bytes, String filename) async => true;

  @override
  Future<void> sharePdf(Uint8List bytes, String filename) async {}
}
