import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:reporting_bridge_flutter/src/headless/headless_report_print_runner.dart';

void main() {
  test('waits for initialization and render before calling printPdf', () async {
    final order = <String>[];
    final controller = _FakeHeadlessController(
      onInitialize: () async {
        order.add('initialize');
      },
      onPrintPdf: () async {
        order.add('printPdf');
        return const ReportPrintResult.submitted();
      },
    );
    final surface = _FakeHeadlessSurface(
      onStart: (started) async {
        order.add('surface.start');
        expect(controller.printPdfCalls, 0);
        await Future<void>.delayed(Duration.zero);
        started.markOutputReady();
        order.add('render.ready');
      },
    );

    final result = await HeadlessReportPrintRunner(
      createController: () => controller,
      surfaceFactory: () => surface,
    ).run();

    expect(result.status, ReportPrintStatus.submitted);
    expect(controller.printPdfCalls, 1);
    expect(order, <String>[
      'initialize',
      'surface.start',
      'render.ready',
      'printPdf',
    ]);
  });

  test(
    'invokes controller.printPdf exactly once and forwards the result',
    () async {
      const expected = ReportPrintResult.submitted();
      final controller = _FakeHeadlessController(
        onPrintPdf: () async => expected,
      );
      final surface = _FakeHeadlessSurface(
        onStart: (started) async => started.markOutputReady(),
      );

      final result = await HeadlessReportPrintRunner(
        createController: () => controller,
        surfaceFactory: () => surface,
      ).run();

      expect(identical(result, expected), isTrue);
      expect(controller.printPdfCalls, 1);
    },
  );

  test(
    'fails with templateSelectionRequired when no selected compatible template',
    () async {
      final controller = _FakeHeadlessController(
        initialState: ReportFlowState(
          stage: ReportFlowStage.selectingTemplate,
          selectedMode: PresenterModePreference.online,
          templates: <CachedTemplate>[_template()],
          entryFallbackReason: ReportEntryFallbackReason.noSavedDefault,
        ),
        autoPrepareLaunch: false,
      );
      final surface = _FakeHeadlessSurface();

      await expectLater(
        HeadlessReportPrintRunner(
          createController: () => controller,
          surfaceFactory: () => surface,
        ).run(),
        throwsA(
          isA<ReportFlowFailure>().having(
            (failure) => failure.code,
            'code',
            ReportFlowFailureCode.templateSelectionRequired,
          ),
        ),
      );
      expect(controller.printPdfCalls, 0);
      expect(surface.startCalls, 0);
      expect(controller.disposeCalls, 1);
      expect(surface.disposeCalls, 0);
    },
  );

  test('disposes surface and controller after success', () async {
    final controller = _FakeHeadlessController();
    final surface = _FakeHeadlessSurface(
      onStart: (started) async => started.markOutputReady(),
    );

    await HeadlessReportPrintRunner(
      createController: () => controller,
      surfaceFactory: () => surface,
    ).run();

    expect(surface.disposeCalls, 1);
    expect(controller.disposeCalls, 1);
  });

  test('disposes surface and controller after print failure', () async {
    final controller = _FakeHeadlessController(
      onPrintPdf: () async {
        throw const ReportFlowFailure(code: ReportFlowFailureCode.printFailed);
      },
    );
    final surface = _FakeHeadlessSurface(
      onStart: (started) async => started.markOutputReady(),
    );

    await expectLater(
      HeadlessReportPrintRunner(
        createController: () => controller,
        surfaceFactory: () => surface,
      ).run(),
      throwsA(
        isA<ReportFlowFailure>().having(
          (failure) => failure.code,
          'code',
          ReportFlowFailureCode.printFailed,
        ),
      ),
    );
    expect(surface.disposeCalls, 1);
    expect(controller.disposeCalls, 1);
  });

  test(
    'onProgress and onTiming callback exceptions never fail the print',
    () async {
      final controller = _FakeHeadlessController();
      final surface = _FakeHeadlessSurface(
        onStart: (started) async => started.markOutputReady(),
      );

      final result =
          await HeadlessReportPrintRunner(
            createController: () => controller,
            surfaceFactory: () => surface,
          ).run(
            onProgress: (_) {
              throw StateError('progress callback must not fail print');
            },
            onTiming: (_) {
              throw StateError('timing callback must not fail print');
            },
          );

      expect(result.status, ReportPrintStatus.submitted);
      expect(controller.printPdfCalls, 1);
    },
  );
}

final class _FakeHeadlessSurface implements HeadlessPresenterSurface {
  _FakeHeadlessSurface({this.onStart});

  final Future<void> Function(_FakeHeadlessController started)? onStart;
  int startCalls = 0;
  int disposeCalls = 0;

  @override
  Future<void> start({
    required PresenterSessionLaunch launch,
    required String templateName,
    required ReportFlowController controller,
    required PresenterSurfaceBinding surfaceBinding,
  }) async {
    startCalls += 1;
    final fake = controller as _FakeHeadlessController;
    await onStart?.call(fake);
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }
}

final class _FakeHeadlessController extends ChangeNotifier
    implements ReportFlowController, ReportFlowActionController {
  _FakeHeadlessController({
    ReportFlowState? initialState,
    this.autoPrepareLaunch = true,
    this.onInitialize,
    this.onPrintPdf,
  }) : _state =
           initialState ??
           ReportFlowState(
             stage: ReportFlowStage.initializing,
             selectedMode: PresenterModePreference.online,
           );

  final bool autoPrepareLaunch;
  final Future<void> Function()? onInitialize;
  final Future<ReportPrintResult> Function()? onPrintPdf;

  late ReportFlowState _state;
  final PresenterSurfaceBinding _surfaceBinding = PresenterSurfaceBinding();
  final StreamController<ReportFlowEvent> _events =
      StreamController<ReportFlowEvent>.broadcast();

  int printPdfCalls = 0;
  int disposeCalls = 0;
  bool _outputReady = false;

  @override
  ReportFlowState get value => _state;

  @override
  ReportOpenRequest get request => ReportOpenRequest(
    seedData: const <String, dynamic>{'id': 1},
    reportName: 'Invoice',
    entryPolicy: ReportEntryPolicy.smart,
    selectedTemplateCriteria: SelectedTemplateCriteria(
      reportType: UrbReportType.salesInvoice,
    ),
    templateSyncRequest: TemplateSyncRequest(
      systemCode: UrbSystem.motakamelTransactions,
    ),
  );

  @override
  Stream<ReportFlowEvent> get events => _events.stream;

  @override
  PresenterSurfaceBinding get presenterSurface => _surfaceBinding;

  @override
  BridgeUiFeatures get effectiveFeatures =>
      const BridgeUiFeatures(showPrint: true);

  @override
  TemplateCompatibilityConstraints get compatibilityConstraints =>
      request.compatibility;

  @override
  List<CachedTemplate> get eligibleTemplates => _state.templates;

  @override
  bool get outputReady => _outputReady;

  void markOutputReady() {
    _outputReady = true;
    _state = _state.copyWith(
      stage: ReportFlowStage.previewing,
      renderStatus: PresenterRenderStatus.ready,
      presenterProtocolReady: true,
    );
    notifyListeners();
  }

  @override
  Future<void> initialize() async {
    await onInitialize?.call();
    if (!autoPrepareLaunch) {
      notifyListeners();
      return;
    }
    final template = _template();
    _state = ReportFlowState(
      stage: ReportFlowStage.previewing,
      selectedMode: PresenterModePreference.online,
      templates: <CachedTemplate>[template],
      selectedTemplateCode: template.templateCode,
      committedTemplateCode: template.templateCode,
      presenterLaunch: const PresenterSessionLaunch(
        presenterUrl: 'https://presenter.test/session-1',
        sessionId: 'session-1',
        presenterVersion: '1.0.0',
        presenterDevVersion: 1,
      ),
      renderStatus: PresenterRenderStatus.loading,
      presenterProtocolReady: false,
    );
    notifyListeners();
  }

  @override
  Future<ReportPrintResult> printPdf() async {
    printPdfCalls += 1;
    return onPrintPdf?.call() ?? const ReportPrintResult.submitted();
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await _events.close();
    super.dispose();
  }

  @override
  Future<void> syncTemplates() async {}

  @override
  Future<void> syncPresenter() async {}

  @override
  Future<void> continueFromPreparation() async {}

  @override
  void backToPreparation() {}

  @override
  void openTemplateSelection({
    TemplateSelectionOrigin origin = TemplateSelectionOrigin.initialSetup,
  }) {}

  @override
  void openResourcePreparation(ResourcePreparationOrigin origin) {}

  @override
  void returnFromResourcePreparation() {}

  @override
  void confirmTemplateSelection() {}

  @override
  void selectTemplate(String templateId) {}

  @override
  void selectMode(PresenterModePreference mode) {}

  @override
  void editSettings() {}

  @override
  Future<void> commitSettings() async {}

  @override
  void cancelSettings() {}

  @override
  Future<void> preparePreview() async {}

  @override
  void presenterLoadStarted() {}

  @override
  void presenterLoadProgress(double progress) {}

  @override
  void presenterProtocolDetected(int contractVersion) {}

  @override
  Future<void> completePresenterRender({String? sessionId}) async {}

  @override
  void failPresenterRender(String diagnostic, {String? sessionId}) {}

  @override
  Future<void> savePdf() async {}

  @override
  Future<void> sharePdf() async {}

  @override
  Future<void> retry() async {}

  @override
  Future<ReportResult> close() async => const ReportCancelled();
}

CachedTemplate _template() => CachedTemplate(
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
