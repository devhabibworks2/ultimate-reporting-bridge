import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import '../test_open_request.dart';
import 'package:reporting_bridge_flutter/src/flow/report_flow_controller_impl.dart';
import 'package:reporting_bridge_flutter/src/flow/report_flow_runtime.dart';

void main() {
  late Directory root;
  late ReportServerConnection connection;
  late _FakeBridgeClient bridge;
  late MemoryReportFlowPreferenceStore preferences;

  setUp(() {
    root = Directory.systemTemp.createTempSync('urb-t04-controller-');
    connection = ReportServerConnection(
      endpoints: ReportServerEndpoints.deployed(
        Uri.parse('https://example.test'),
      ),
      cacheRoot: root,
    );
    bridge = _FakeBridgeClient(root);
    preferences = MemoryReportFlowPreferenceStore();
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('direct controller calls cannot bypass read-only policy', () async {
    final fixture = _createController(
      connection: connection,
      bridge: bridge,
      preferences: preferences,
      policy: const ReportActionPolicy.readOnly(),
    );
    addTearDown(fixture.controller.dispose);
    await _ready(fixture);

    expect(
      fixture.controller.effectiveFeatures.hasVisibleOutputAction,
      isFalse,
    );
    expect(fixture.controller.value.stage, ReportFlowStage.previewing);
    expect(
      fixture.controller.savePdf,
      throwsA(_failure(ReportFlowFailureCode.actionDenied)),
    );
    expect(
      fixture.controller.sharePdf,
      throwsA(_failure(ReportFlowFailureCode.actionDenied)),
    );
    expect(
      fixture.controller.printPdf,
      throwsA(_failure(ReportFlowFailureCode.actionDenied)),
    );
  });

  test('print uses selected-template metadata and injected gateway', () async {
    final printPlatform = _FakePrintPlatform();
    final fixture = _createController(
      connection: connection,
      bridge: bridge,
      preferences: preferences,
      printPlatform: printPlatform,
      policy: const ReportActionPolicy(canPrintPdf: true),
    );
    addTearDown(fixture.controller.dispose);
    await _ready(fixture);

    final result = await fixture.controller.printPdf();

    expect(result.status, ReportPrintStatus.submitted);
    expect(printPlatform.calls, 1);
    final request = printPlatform.lastRequest!;
    expect(request.extra['system'], 'motakamel_transactions');
    expect(request.extra['reportType'], 'sales_invoice');
    expect(request.extra['templateId'], 'thermal-en');
    expect(request.document.unit, 'mm');
    expect(request.document.layout, 'Thermal');
    expect(request.document.size, '80mm');
    expect(request.document.width, 80);
    expect(request.document.height, 220);
    expect(request.document.orientation, 'portrait');
    expect(request.document.languageCode, 'en');
    expect(bridge.lastSessionRequest?.locale, 'en');
    expect(bridge.lastSessionRequest?.direction, 'ltr');
  });

  test('duplicate and cross-action output submissions are blocked', () async {
    final barrier = Completer<ReportPrintResult>();
    final printPlatform = _FakePrintPlatform(barrier: barrier);
    final fixture = _createController(
      connection: connection,
      bridge: bridge,
      preferences: preferences,
      printPlatform: printPlatform,
      policy: const ReportActionPolicy(),
    );
    addTearDown(fixture.controller.dispose);
    await _ready(fixture);

    final first = fixture.controller.printPdf();
    await Future<void>.delayed(Duration.zero);

    expect(fixture.controller.value.exportAction, ReportExportAction.print);
    await expectLater(
      fixture.controller.printPdf(),
      throwsA(_failure(ReportFlowFailureCode.exportInProgress)),
    );
    expect(
      fixture.controller.savePdf,
      throwsA(_failure(ReportFlowFailureCode.exportInProgress)),
    );
    expect(
      fixture.controller.sharePdf,
      throwsA(_failure(ReportFlowFailureCode.exportInProgress)),
    );

    barrier.complete(const ReportPrintResult.submitted());
    expect((await first).status, ReportPrintStatus.submitted);
    expect(fixture.controller.value.exportAction, isNull);
    expect(printPlatform.calls, 1);
  });

  test(
    'ineligible saved thermal selection is skipped without deleting preference',
    () async {
      final scope = ReportPreferenceScope(
        connectionKey: connection.preferenceSourceKey,
        system: 'motakamel_transactions',
        reportType: 'sales_invoice',
        userId: 'user-a',
      );
      await preferences.save(
        scope,
        const ReportFlowPreferences(
          templateId: 'thermal-landscape',
          mode: PresenterModePreference.online,
          language: 'en',
          layout: 'thermal',
          size: '80mm',
        ),
      );
      bridge.templates = <CachedTemplate>[
        _template('thermal-landscape', orientation: 'landscape'),
        _template('thermal-en'),
      ];
      final fixture = _createController(
        connection: connection,
        bridge: bridge,
        preferences: preferences,
        userId: 'user-a',
        entryPolicy: ReportEntryPolicy.smart,
      );
      addTearDown(fixture.controller.dispose);

      await fixture.controller.initialize();

      expect((await preferences.load(scope))?.templateId, 'thermal-landscape');
      expect(fixture.controller.value.stage, ReportFlowStage.selectingTemplate);
      expect(fixture.controller.value.selectedTemplateId, 'thermal-en');
    },
  );

  test('request compatibility constraints filter eligible templates', () async {
    bridge.templates = <CachedTemplate>[
      _pagesTemplate('pages-ar'),
      _template('thermal-en'),
    ];
    final fixture = _createController(
      connection: connection,
      bridge: bridge,
      preferences: preferences,
      entryPolicy: ReportEntryPolicy.alwaysPrepare,
      compatibility: const TemplateCompatibilityConstraints(
        language: ReportLanguage.en,
        layout: ReportLayout.thermal,
        size: ReportPageSize.thermal80,
      ),
    );
    addTearDown(fixture.controller.dispose);
    await fixture.controller.initialize();
    await fixture.controller.continueFromPreparation();

    expect(
      fixture.controller.compatibilityConstraints.language,
      ReportLanguage.en,
    );
    expect(
      fixture.controller.eligibleTemplates.map((template) => template.id),
      <String>['thermal-en'],
    );
    expect(fixture.controller.value.selectedTemplateId, 'thermal-en');
  });
}

_ControllerFixture _createController({
  required ReportServerConnection connection,
  required _FakeBridgeClient bridge,
  required MemoryReportFlowPreferenceStore preferences,
  ReportActionPolicy policy = const ReportActionPolicy(),
  ReportPrintPlatform? printPlatform,
  String? userId,
  ReportEntryPolicy entryPolicy = ReportEntryPolicy.alwaysPrepare,
  TemplateCompatibilityConstraints compatibility =
      const TemplateCompatibilityConstraints(),
}) {
  final surface = PresenterSurfaceBinding(
    exportTransport: PresenterWebExportTransport(
      correlationIdFactory: () => 't04-export',
    ),
  );
  final controller = ReportFlowControllerImpl(
    request: buildTestOpenRequest(
      system: 'motakamel_transactions',
      reportType: 'sales_invoice',
      reportName: 'Invoice',
      localeOverride: 'ar',
      userId: userId,
      entryPolicy: entryPolicy,
      actionPolicy: policy,
      compatibility: compatibility,
      featuresOverride: const BridgeUiFeatures(
        showPrint: true,
        showSavePdf: true,
        showSharePdf: true,
      ),
    ),
    features: const BridgeUiFeatures(
      showPrint: true,
      showSavePdf: true,
      showSharePdf: true,
    ),
    runtime: ReportFlowRuntime(
      connection: connection,
      bridgeClient: bridge,
      preferences: preferences,
      filePlatform: _FakeFilePlatform(),
      surfaceBinding: surface,
      printPlatform: printPlatform ?? _FakePrintPlatform(),
    ),
  );
  return _ControllerFixture(controller: controller, surface: surface);
}

Future<void> _ready(_ControllerFixture fixture) async {
  await fixture.controller.initialize();
  if (fixture.controller.value.stage == ReportFlowStage.preparingResources) {
    await fixture.controller.continueFromPreparation();
  }
  if (fixture.controller.value.stage == ReportFlowStage.selectingTemplate) {
    fixture.controller.selectTemplate('thermal-en');
    await fixture.controller.preparePreview();
  }
  final launch = fixture.controller.value.presenterLaunch!;
  fixture.surface.attach(
    sessionId: launch.sessionId,
    templateName: fixture.controller.value.selectedTemplate!.templateName,
    evaluateJavaScript: (_) async {
      fixture.surface.acceptMessage(<String, dynamic>{
        'channel': bridgeWebMessageChannel,
        'method': BridgeWebMethods.exportPdf,
        'correlationId': 't04-export',
        'type': 'result',
        'ok': true,
        'base64': base64Encode(<int>[1, 2, 3]),
        'filename': 'invoice.pdf',
        'byteLength': 3,
      });
      return null;
    },
    reload: () async {},
    onLifecycle: (_) {},
  );
  fixture.controller.presenterProtocolDetected(BridgeContract.payloadVersion);
  fixture.controller.completePresenterRender(sessionId: launch.sessionId);
  expect(fixture.controller.outputReady, isTrue);
}

Matcher _failure(ReportFlowFailureCode code) =>
    isA<ReportFlowFailure>().having((failure) => failure.code, 'code', code);

class _ControllerFixture {
  const _ControllerFixture({required this.controller, required this.surface});

  final ReportFlowControllerImpl controller;
  final PresenterSurfaceBinding surface;
}

class _FakePrintPlatform implements ReportPrintPlatform {
  _FakePrintPlatform({this.barrier});

  final Completer<ReportPrintResult>? barrier;
  int calls = 0;
  ReportPrintRequest? lastRequest;

  @override
  Future<ReportPrintResult> printPdf(ReportPrintRequest request) {
    calls += 1;
    lastRequest = request;
    return barrier?.future ??
        Future<ReportPrintResult>.value(const ReportPrintResult.submitted());
  }
}

class _FakeFilePlatform implements ReportFilePlatform {
  @override
  Future<bool> savePdf(Uint8List bytes, String filename) async => true;

  @override
  Future<void> sharePdf(Uint8List bytes, String filename) async {}
}

class _FakeBridgeClient extends ReportingBridgeClient {
  _FakeBridgeClient(Directory root)
    : super(
        apiBaseUrl: Uri.parse('https://example.test/UltimateReport/backend/'),
        presenterEntryUrl: Uri.parse(
          'https://example.test/UltimateReport/apps/presenter/index.html',
        ),
        bridgeRoot: root,
      );

  List<CachedTemplate> templates = <CachedTemplate>[_template('thermal-en')];
  int prepareCalls = 0;
  PresenterSessionRequest? lastSessionRequest;

  @override
  Future<List<CachedTemplate>> listTemplates({
    String? systemCode,
    int? systemId,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async => templates;

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
  Future<ReportingBridgeStatus> getStatus() async => ReportingBridgeStatus(
    apiBaseUrl: apiBaseUrl.toString(),
    presenterCached: true,
    templateCount: templates.length,
  );

  @override
  Future<PresenterSessionLaunch> prepareSession(
    PresenterSessionRequest request,
  ) async {
    prepareCalls += 1;
    lastSessionRequest = request;
    return PresenterSessionLaunch(
      presenterUrl: 'https://presenter.test/session-$prepareCalls',
      sessionId: 'session-$prepareCalls',
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

CachedTemplate _template(String id, {String orientation = 'portrait'}) =>
    CachedTemplate(
      id: id,
      type: 'sales_invoice',
      systemId: 1,
      name: id,
      document: <String, dynamic>{
        'schemaVersion': '1.0.0',
        'meta': const <String, dynamic>{
          'name': 'Thermal invoice',
          'family': 'sales_invoice',
          'systemCode': 'motakamel_transactions',
        },
        'page': <String, dynamic>{
          'unit': 'mm',
          'layout': 'Thermal',
          'size': '80mm',
          'width': orientation == 'portrait' ? 80 : 220,
          'height': orientation == 'portrait' ? 220 : 80,
          'orientation': orientation,
          'language': 'en',
          'direction': 'ltr',
        },
        'styleTokens': const <String, dynamic>{},
        'assets': const <dynamic>[],
        'layers': const <dynamic>[],
        'elements': const <dynamic>[],
      },
    );

CachedTemplate _pagesTemplate(String id) => CachedTemplate(
  id: id,
  type: 'sales_invoice',
  systemId: 1,
  name: id,
  document: const <String, dynamic>{
    'schemaVersion': '1.0.0',
    'meta': <String, dynamic>{
      'name': 'A4 invoice',
      'family': 'sales_invoice',
      'systemCode': 'motakamel_transactions',
    },
    'page': <String, dynamic>{
      'unit': 'mm',
      'layout': 'Pages',
      'size': 'A4',
      'width': 210,
      'height': 297,
      'orientation': 'portrait',
      'language': 'ar',
      'direction': 'rtl',
    },
    'styleTokens': <String, dynamic>{},
    'assets': <dynamic>[],
    'layers': <dynamic>[],
    'elements': <dynamic>[],
  },
);
