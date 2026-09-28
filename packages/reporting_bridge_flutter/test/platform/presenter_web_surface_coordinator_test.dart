import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:reporting_bridge_flutter/src/platform/presenter_web_surface_coordinator.dart';

void main() {
  late PresenterWebSurfaceCoordinator coordinator;
  late _RecordingController controller;
  late PresenterSurfaceBinding binding;
  late _FakePlatformWebViewController platformController;
  late InAppWebViewController webController;

  setUp(() {
    coordinator = const PresenterWebSurfaceCoordinator();
    controller = _RecordingController();
    binding = PresenterSurfaceBinding();
    platformController = _FakePlatformWebViewController();
    webController = InAppWebViewController.fromPlatform(
      platform: platformController,
    );
  });

  tearDown(() {
    binding.dispose();
  });

  test('attach registers JS handler that forwards messages to binding', () {
    coordinator.attach(
      webController: webController,
      sessionId: 'session-a',
      templateName: 'Invoice',
      controller: controller,
      surfaceBinding: binding,
    );

    expect(binding.attached, isTrue);
    final handler = platformController.handlers['urbReportingBridge'];
    expect(handler, isNotNull);

    final delivered = binding.acceptMessage(<String, dynamic>{
      'channel': bridgeWebMessageChannel,
      'method': BridgeWebMethods.presenterLifecycle,
      'event': 'onPresenterReady',
      'contractVersion': BridgeContract.payloadVersion,
      'payload': <String, dynamic>{'sessionId': 'session-a'},
    });
    expect(delivered, isTrue);
    expect(controller.protocolVersions, <int>[BridgeContract.payloadVersion]);

    // Handler path used by the WebView bridge.
    handler!(<dynamic>[
      <String, dynamic>{
        'channel': bridgeWebMessageChannel,
        'method': BridgeWebMethods.presenterLifecycle,
        'event': 'onRenderStarted',
        'contractVersion': BridgeContract.payloadVersion,
        'payload': <String, dynamic>{'sessionId': 'session-a'},
      },
    ]);
    expect(controller.loadStartedCalls, 1);
    expect(controller.protocolVersions, <int>[
      BridgeContract.payloadVersion,
      BridgeContract.payloadVersion,
    ]);
  });

  test('lifecycle states map like BridgePresenterView', () {
    coordinator.handleLifecycle(
      const PresenterWebLifecycleEvent(
        state: PresenterWebLifecycleState.connected,
        name: 'onPresenterReady',
        payload: <String, dynamic>{},
        contractVersion: 3,
      ),
      controller,
    );
    expect(controller.protocolVersions, <int>[3]);
    expect(controller.loadStartedCalls, 0);
    expect(controller.completeRenderSessionIds, isEmpty);

    coordinator.handleLifecycle(
      const PresenterWebLifecycleEvent(
        state: PresenterWebLifecycleState.loading,
        name: 'onRenderStarted',
        payload: <String, dynamic>{},
        contractVersion: 3,
      ),
      controller,
    );
    expect(controller.loadStartedCalls, 1);
    expect(controller.protocolVersions, <int>[3, 3]);

    coordinator.handleLifecycle(
      const PresenterWebLifecycleEvent(
        state: PresenterWebLifecycleState.ready,
        name: 'onRenderCompleted',
        payload: <String, dynamic>{'sessionId': 'ready-1'},
        contractVersion: 3,
        sessionId: 'ready-1',
      ),
      controller,
    );
    expect(controller.completeRenderSessionIds, <String?>['ready-1']);
    expect(controller.protocolVersions, <int>[3, 3, 3]);

    coordinator.handleLifecycle(
      const PresenterWebLifecycleEvent(
        state: PresenterWebLifecycleState.failed,
        name: 'onRenderFailed',
        payload: <String, dynamic>{'sessionId': 'fail-1', 'message': 'boom'},
        contractVersion: 3,
        sessionId: 'fail-1',
      ),
      controller,
    );
    expect(controller.protocolVersions, <int>[3, 3, 3, 3]);
    expect(controller.structuredFailures, isNotEmpty);
    expect(controller.structuredFailureSessionIds, <String?>['fail-1']);
  });

  test('load start and progress map to controller', () {
    coordinator.handleLoadStart(controller);
    coordinator.handleProgress(controller, 42);

    expect(controller.loadStartedCalls, 1);
    expect(controller.loadProgressValues, <double>[0.42]);
  });

  test('main-frame received error fails render; non-main-frame ignored', () {
    coordinator.handleReceivedError(
      controller,
      WebResourceRequest(
        url: WebUri('https://presenter.test/page'),
        isForMainFrame: true,
      ),
      WebResourceError(
        description: 'main failed',
        type: WebResourceErrorType.UNKNOWN,
      ),
    );
    expect(controller.failRenderDiagnostics, <String>['main failed']);

    coordinator.handleReceivedError(
      controller,
      WebResourceRequest(
        url: WebUri('https://presenter.test/asset.js'),
        isForMainFrame: false,
      ),
      WebResourceError(
        description: 'subresource failed',
        type: WebResourceErrorType.UNKNOWN,
      ),
    );
    expect(controller.failRenderDiagnostics, <String>['main failed']);
  });

  test('HTTP main-frame error fails render; favicon HTTP error ignored', () {
    coordinator.handleReceivedHttpError(
      controller,
      WebResourceRequest(
        url: WebUri('https://presenter.test/report'),
        isForMainFrame: true,
      ),
      WebResourceResponse(statusCode: 500, reasonPhrase: 'error'),
    );
    expect(
      controller.failRenderDiagnostics.single,
      contains('HTTP 500 while loading'),
    );

    coordinator.handleReceivedHttpError(
      controller,
      WebResourceRequest(
        url: WebUri('https://presenter.test/favicon.ico'),
        isForMainFrame: true,
      ),
      WebResourceResponse(statusCode: 404, reasonPhrase: 'missing'),
    );
    expect(controller.failRenderDiagnostics, hasLength(1));
  });

  test(
    'detach/re-attach drops stale session semantics and does not leak prior attachment',
    () {
      coordinator.attach(
        webController: webController,
        sessionId: 'session-a',
        templateName: 'Invoice A',
        controller: controller,
        surfaceBinding: binding,
      );

      binding.acceptMessage(<String, dynamic>{
        'channel': bridgeWebMessageChannel,
        'method': BridgeWebMethods.presenterLifecycle,
        'event': 'onPresenterReady',
        'contractVersion': BridgeContract.payloadVersion,
        'payload': <String, dynamic>{'sessionId': 'session-b'},
      });
      expect(
        controller.protocolVersions,
        isEmpty,
        reason: 'stale sessionId must not drive the attached controller',
      );

      binding.detachSession('session-a');
      expect(binding.attached, isFalse);

      final nextController = _RecordingController();
      coordinator.attach(
        webController: webController,
        sessionId: 'session-b',
        templateName: 'Invoice B',
        controller: nextController,
        surfaceBinding: binding,
      );

      binding.acceptMessage(<String, dynamic>{
        'channel': bridgeWebMessageChannel,
        'method': BridgeWebMethods.presenterLifecycle,
        'event': 'onPresenterReady',
        'contractVersion': BridgeContract.payloadVersion,
        'payload': <String, dynamic>{'sessionId': 'session-a'},
      });
      expect(controller.protocolVersions, isEmpty);
      expect(nextController.protocolVersions, isEmpty);

      binding.acceptMessage(<String, dynamic>{
        'channel': bridgeWebMessageChannel,
        'method': BridgeWebMethods.presenterLifecycle,
        'event': 'onPresenterReady',
        'contractVersion': BridgeContract.payloadVersion,
        'payload': <String, dynamic>{'sessionId': 'session-b'},
      });
      expect(controller.protocolVersions, isEmpty);
      expect(nextController.protocolVersions, <int>[
        BridgeContract.payloadVersion,
      ]);
    },
  );
}

final class _FakePlatformWebViewController
    extends PlatformInAppWebViewController {
  _FakePlatformWebViewController()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 'coord-test'),
      );

  final Map<String, JavaScriptHandlerCallback> handlers =
      <String, JavaScriptHandlerCallback>{};

  @override
  void addJavaScriptHandler({
    required String handlerName,
    required JavaScriptHandlerCallback callback,
  }) {
    handlers[handlerName] = callback;
  }

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async => null;

  @override
  Future<void> reload() async {}
}

final class _RecordingController extends ChangeNotifier
    implements ReportFlowController, ReportFlowStructuredFailureController {
  final List<int> protocolVersions = <int>[];
  final List<double> loadProgressValues = <double>[];
  final List<String?> completeRenderSessionIds = <String?>[];
  final List<String> failRenderDiagnostics = <String>[];
  final List<ReportFlowFailure> structuredFailures = <ReportFlowFailure>[];
  final List<String?> structuredFailureSessionIds = <String?>[];
  int loadStartedCalls = 0;

  final PresenterSurfaceBinding _surface = PresenterSurfaceBinding();
  final StreamController<ReportFlowEvent> _events =
      StreamController<ReportFlowEvent>.broadcast();

  @override
  ReportFlowState get value =>
      ReportFlowState.initial(PresenterModePreference.online);

  @override
  ReportOpenRequest get request => ReportOpenRequest(
    seedData: const <String, dynamic>{'id': 1},
    reportName: 'Invoice',
    entryPolicy: ReportEntryPolicy.smart,
    actionPolicy: const ReportActionPolicy(),
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
  PresenterSurfaceBinding get presenterSurface => _surface;

  @override
  void presenterProtocolDetected(int contractVersion) {
    protocolVersions.add(contractVersion);
  }

  @override
  void presenterLoadStarted() {
    loadStartedCalls += 1;
  }

  @override
  void presenterLoadProgress(double progress) {
    loadProgressValues.add(progress);
  }

  @override
  void completePresenterRender({String? sessionId}) {
    completeRenderSessionIds.add(sessionId);
  }

  @override
  void failPresenterRender(String diagnostic, {String? sessionId}) {
    failRenderDiagnostics.add(diagnostic);
  }

  @override
  void failPresenterRenderFailure(
    ReportFlowFailure failure, {
    String? sessionId,
  }) {
    structuredFailures.add(failure);
    structuredFailureSessionIds.add(sessionId);
  }

  @override
  Future<void> initialize() async {}

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
  Future<void> savePdf() async {}

  @override
  Future<void> sharePdf() async {}

  @override
  Future<void> retry() async {}

  @override
  Future<ReportResult> close() async => const ReportCancelled();

  @override
  Future<void> dispose() async {
    await _events.close();
    super.dispose();
  }
}
