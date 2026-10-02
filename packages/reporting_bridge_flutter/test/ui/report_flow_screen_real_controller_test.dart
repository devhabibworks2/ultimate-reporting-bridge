import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
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
      final surface = PresenterSurfaceBinding(
        exportTransport: PresenterWebExportTransport(
          correlationIdFactory: () => 'real-controller-ready',
        ),
      );
      final controller = ReportFlowControllerImpl(
        request: buildTestOpenRequest(
          system: 'legacy_system_1',
          reportType: 'sales_invoice',
          presenterMode: PresenterModePreference.online,
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
          surfaceBinding: surface,
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
      final preparedLaunch = controller.value.presenterLaunch!;
      surface.attach(
        sessionId: preparedLaunch.sessionId,
        templateName: controller.value.selectedTemplate!.templateName,
        evaluateJavaScript: (_) async {
          surface.acceptMessage(<String, dynamic>{
            'channel': bridgeWebMessageChannel,
            'method': BridgeWebMethods.exportPdf,
            'correlationId': 'real-controller-ready',
            'type': 'result',
            'ok': true,
            'base64': base64Encode(<int>[1, 2, 3]),
            'filename': 'report.pdf',
            'byteLength': 3,
          });
          return null;
        },
        reload: () async {},
        onLifecycle: (_) {},
      );

      controller.presenterLoadStarted();
      controller.presenterProtocolDetected(BridgeContract.payloadVersion);
      await controller.completePresenterRender(
        sessionId: controller.value.presenterLaunch?.sessionId,
      );
      expect(controller.value.stage, ReportFlowStage.previewing);
      final launch = controller.value.presenterLaunch;

      controller.editSettings();
      controller.openTemplateSelection(
        origin: TemplateSelectionOrigin.reportSettings,
      );
      controller.selectTemplate('t2');

      expect(controller.value.settingsDraft?.templateCode, 't1');
      expect(controller.value.selectedTemplateCode, 't2');

      controller.cancelSettings();

      expect(controller.value.stage, ReportFlowStage.previewing);
      expect(controller.value.settingsDraft, isNull);
      expect(controller.value.selectedTemplateCode, 't1');
      expect(controller.value.selectedMode, PresenterModePreference.online);
      expect(controller.value.presenterLaunch, same(launch));

      await controller.dispose().timeout(const Duration(seconds: 10));
    },
  );

  testWidgets(
    'viewer failure keeps cached PDF authoritative for Save Share and Print',
    (tester) async {
      final root = Directory.systemTemp.createTempSync(
        'urb-viewer-failure-output-authority-',
      );
      final bridge = _UiBridgeClient(root, <CachedTemplate>[_template('t1')]);
      final filePlatform = _RecordingFilePlatform();
      final printPlatform = _RecordingPrintPlatform();
      var presenterExportCalls = 0;
      const correlationId = 'viewer-failure-ready';
      final surface = PresenterSurfaceBinding(
        exportTransport: PresenterWebExportTransport(
          correlationIdFactory: () => correlationId,
        ),
      );
      final controller = ReportFlowControllerImpl(
        request: buildTestOpenRequest(
          system: 'legacy_system_1',
          reportType: 'sales_invoice',
          presenterMode: PresenterModePreference.online,
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
          filePlatform: filePlatform,
          printPlatform: printPlatform,
          surfaceBinding: surface,
        ),
        renderTimeout: Duration.zero,
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

      surface.attach(
        sessionId: launch.sessionId,
        templateName: controller.value.selectedTemplate!.templateName,
        evaluateJavaScript: (_) async {
          presenterExportCalls += 1;
          surface.acceptMessage(<String, dynamic>{
            'channel': bridgeWebMessageChannel,
            'method': BridgeWebMethods.exportPdf,
            'correlationId': correlationId,
            'type': 'result',
            'ok': true,
            'base64': base64Encode(<int>[1, 2, 3, 4]),
            'filename': 'report.pdf',
            'byteLength': 4,
          });
          return null;
        },
        reload: () async {},
        onLifecycle: (_) {},
      );

      controller.presenterLoadStarted();
      controller.presenterProtocolDetected(BridgeContract.payloadVersion);
      await controller.completePresenterRender(sessionId: launch.sessionId);

      final cached = surface.cachedPdf;
      expect(cached, isNotNull);
      expect(controller.outputReady, isTrue);
      expect(presenterExportCalls, 1);

      final viewerFailure = Exception('viewer failed');
      Object? reportedViewerFailure;
      await tester.pumpWidget(
        MaterialApp(
          home: BridgePdfView(
            bytes: cached!.bytes,
            documentFactory: (_) async => throw viewerFailure,
            onViewerError: (error) => reportedViewerFailure = error,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(reportedViewerFailure, same(viewerFailure));
      expect(surface.cachedPdf, same(cached));
      expect(controller.outputReady, isTrue);

      await controller.savePdf();
      await controller.sharePdf();
      final printResult = await controller.printPdf();

      expect(printResult.isSubmitted, isTrue);
      expect(presenterExportCalls, 1);
      expect(filePlatform.savedBytes, same(cached.bytes));
      expect(filePlatform.sharedBytes, same(cached.bytes));
      expect(printPlatform.printedBytes, orderedEquals(cached.bytes));
      expect(surface.cachedPdf, same(cached));
      expect(controller.outputReady, isTrue);
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
          presenterMode: PresenterModePreference.online,
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

CachedTemplate _template(String code) => CachedTemplate(
  type: 'sales_invoice',
  systemId: 1,
  code: code,
  name: 'Template $code',
  version: '1.0.0',
  document: <String, dynamic>{
    'schemaVersion': '1.0.0',
    'meta': <String, dynamic>{
      'name': 'Invoice',
      'family': 'sales_invoice',
      'code': code,
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
  Future<List<TemplateDefaultHint>> listTemplateDefaults({
    required String systemCode,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async => const <TemplateDefaultHint>[];

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
    value = ReportFlowPreferences(templateCode: null, mode: value!.mode);
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

class _RecordingFilePlatform implements ReportFilePlatform {
  Uint8List? savedBytes;
  Uint8List? sharedBytes;

  @override
  Future<bool> savePdf(Uint8List bytes, String filename) async {
    savedBytes = bytes;
    return true;
  }

  @override
  Future<void> sharePdf(Uint8List bytes, String filename) async {
    sharedBytes = bytes;
  }
}

class _RecordingPrintPlatform implements ReportPrintPlatform {
  Uint8List? printedBytes;

  @override
  Future<ReportPrintResult> printPdf(ReportPrintRequest request) async {
    printedBytes = request.pdfBytes;
    return const ReportPrintResult.submitted();
  }
}
