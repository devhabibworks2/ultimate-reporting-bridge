import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  late Directory root;
  late _FakeBridgeClient bridge;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('urb-public-print-');
    bridge = _FakeBridgeClient(root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('Default client wires injected print platform', () async {
    final printPlatform = _FakePrintPlatform();
    final logs = <BridgeLogRecord>[];
    final client = DefaultReportingBridgeFlutterClient(
      connection: _connection(
        root,
        diagnostics: BridgeDiagnostics(sink: logs.add),
      ),
      bridgeClient: bridge,
      preferences: MemoryReportFlowPreferenceStore(),
      filePlatform: _FakeFilePlatform(),
      printPlatform: printPlatform,
      ui: const BridgeUiConfig.inheritHost(
        features: BridgeUiFeatures(
          showPrint: true,
          showSavePdf: true,
          showSharePdf: true,
        ),
      ),
    );
    addTearDown(client.dispose);

    final controller = client.createController(_request());
    addTearDown(controller.dispose);
    await _ready(controller);

    final result = await controller.printPdf();

    expect(result.status, ReportPrintStatus.submitted);
    expect(printPlatform.calls, 1);
    expect(printPlatform.lastRequest?.extra['templateId'], 'thermal-en');
    expect(
      logs.map((record) => record.event),
      containsAll(<String>[
        'printPdf.start',
        'printPdf.result',
        'printPdf.success',
      ]),
    );
  });

  test(
    'rejected print attempts are logged without starting platform print',
    () async {
      final logs = <BridgeLogRecord>[];
      final printPlatform = _FakePrintPlatform();
      final client = DefaultReportingBridgeFlutterClient(
        connection: _connection(
          root,
          diagnostics: BridgeDiagnostics(sink: logs.add),
        ),
        bridgeClient: bridge,
        preferences: MemoryReportFlowPreferenceStore(),
        filePlatform: _FakeFilePlatform(),
        printPlatform: printPlatform,
        ui: const BridgeUiConfig.inheritHost(
          features: BridgeUiFeatures(showPrint: true),
        ),
      );
      addTearDown(client.dispose);

      final controller = client.createController(_request());
      addTearDown(controller.dispose);

      await expectLater(
        controller.printPdf(),
        throwsA(
          isA<ReportFlowFailure>().having(
            (failure) => failure.code,
            'code',
            ReportFlowFailureCode.printUnavailable,
          ),
        ),
      );

      expect(printPlatform.calls, 0);
      expect(logs, hasLength(1));
      expect(logs.single.category, BridgeLogCategory.print);
      expect(logs.single.event, 'printPdf.rejected');
      expect(logs.single.details['code'], 'printUnavailable');
    },
  );

  test('Default client defaults to unsupported print', () async {
    final client = DefaultReportingBridgeFlutterClient(
      connection: _connection(root),
      bridgeClient: bridge,
      preferences: MemoryReportFlowPreferenceStore(),
      filePlatform: _FakeFilePlatform(),
      ui: const BridgeUiConfig.inheritHost(
        features: BridgeUiFeatures(showPrint: true),
      ),
    );
    addTearDown(client.dispose);

    final controller = client.createController(_request());
    addTearDown(controller.dispose);
    await _ready(controller);

    await expectLater(
      controller.printPdf(),
      throwsA(
        isA<ReportFlowFailure>()
            .having(
              (failure) => failure.code,
              'code',
              ReportFlowFailureCode.printFailed,
            )
            .having(
              (failure) => failure.diagnostic,
              'diagnostic',
              'platformUnsupported',
            ),
      ),
    );
  });
}

ReportServerConnection _connection(
  Directory root, {
  BridgeDiagnostics diagnostics = const BridgeDiagnostics.disabled(),
}) => ReportServerConnection(
  endpoints: ReportServerEndpoints.deployed(Uri.parse('https://example.test')),
  cacheRoot: root,
  diagnostics: diagnostics,
);

ReportOpenRequest _request() => ReportOpenRequest(
  seedData: const <String, dynamic>{'id': 1},
  reportName: 'Invoice',
  entryPolicy: ReportEntryPolicy.alwaysPrepare,
  actionPolicy: const ReportActionPolicy(canPrintPdf: true),
  featuresOverride: const BridgeUiFeatures(showPrint: true),
  selectedTemplateCriteria: SelectedTemplateCriteria(
    reportType: UrbReportType.salesInvoice,
  ),
  templateSyncRequest: TemplateSyncRequest(
    systemCode: UrbSystem.motakamelTransactions,
  ),
);

Future<void> _ready(ReportFlowController controller) async {
  await controller.initialize();
  if (controller.value.stage == ReportFlowStage.preparingResources) {
    await controller.continueFromPreparation();
  }
  if (controller.value.stage == ReportFlowStage.selectingTemplate) {
    controller.selectTemplate(controller.value.templates.first.id);
    await controller.preparePreview();
  }

  final launch = controller.value.presenterLaunch!;
  controller.presenterSurface.attach(
    sessionId: launch.sessionId,
    templateName: controller.value.selectedTemplate!.templateName,
    evaluateJavaScript: (source) async {
      final correlationId = RegExp(
        r'"correlationId":"([^"]+)"',
      ).firstMatch(source)!.group(1)!;
      controller.presenterSurface.acceptMessage(<String, dynamic>{
        'channel': bridgeWebMessageChannel,
        'method': BridgeWebMethods.exportPdf,
        'correlationId': correlationId,
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
  controller.presenterProtocolDetected(BridgeContract.payloadVersion);
  controller.completePresenterRender(sessionId: launch.sessionId);
  expect(controller.outputReady, isTrue);
}

final class _FakePrintPlatform implements ReportPrintPlatform {
  int calls = 0;
  ReportPrintRequest? lastRequest;

  @override
  Future<ReportPrintResult> printPdf(ReportPrintRequest request) async {
    calls += 1;
    lastRequest = request;
    return const ReportPrintResult.submitted();
  }
}

final class _FakeFilePlatform implements ReportFilePlatform {
  @override
  Future<bool> savePdf(Uint8List bytes, String filename) async => true;

  @override
  Future<void> sharePdf(Uint8List bytes, String filename) async {}
}

final class _FakeBridgeClient extends ReportingBridgeClient {
  _FakeBridgeClient(Directory root)
    : super(
        apiBaseUrl: Uri.parse('https://example.test/backend/'),
        presenterEntryUrl: Uri.parse('https://example.test/presenter/'),
        bridgeRoot: root,
      );

  final List<CachedTemplate> templates = <CachedTemplate>[_template()];
  int prepareCalls = 0;

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

CachedTemplate _template() => CachedTemplate(
  id: 'thermal-en',
  type: 'sales_invoice',
  systemId: 7,
  systemCode: 'motakamel_transactions',
  code: 'THERMAL-EN',
  name: 'Thermal invoice',
  document: const <String, dynamic>{
    'schemaVersion': '1.0.0',
    'meta': <String, dynamic>{
      'name': 'Thermal invoice',
      'family': 'sales_invoice',
      'systemCode': 'motakamel_transactions',
      'code': 'THERMAL-EN',
    },
    'page': <String, dynamic>{
      'unit': 'mm',
      'layout': 'Thermal',
      'size': '80mm',
      'width': 80,
      'height': 220,
      'orientation': 'portrait',
      'language': 'en',
      'direction': 'ltr',
    },
    'styleTokens': <String, dynamic>{},
    'assets': <dynamic>[],
    'layers': <dynamic>[],
    'elements': <dynamic>[],
  },
);
