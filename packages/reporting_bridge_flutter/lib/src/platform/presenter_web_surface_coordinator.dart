import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:reporting_bridge/reporting_bridge.dart';

import '../flow/report_flow_controller.dart';
import '../flow/report_flow_failure.dart';
import 'presenter_surface_binding.dart';

final class PresenterWebSurfaceCoordinator {
  const PresenterWebSurfaceCoordinator();

  void attach({
    required InAppWebViewController webController,
    required String sessionId,
    required String templateName,
    required ReportFlowController controller,
    required PresenterSurfaceBinding surfaceBinding,
  }) {
    webController.addJavaScriptHandler(
      handlerName: 'urbReportingBridge',
      callback: (args) {
        if (args.isNotEmpty) {
          surfaceBinding.acceptMessage(args.first);
        }
        return null;
      },
    );
    surfaceBinding.attach(
      sessionId: sessionId,
      templateName: templateName,
      evaluateJavaScript: (source) =>
          webController.evaluateJavascript(source: source),
      reload: webController.reload,
      onLifecycle: (event) => handleLifecycle(event, controller),
    );
  }

  void handleLifecycle(
    PresenterWebLifecycleEvent event,
    ReportFlowController controller,
  ) {
    switch (event.state) {
      case PresenterWebLifecycleState.connected:
        controller.presenterProtocolDetected(event.contractVersion);
        return;
      case PresenterWebLifecycleState.loading:
        controller.presenterLoadStarted();
        controller.presenterProtocolDetected(event.contractVersion);
        return;
      case PresenterWebLifecycleState.ready:
        controller.presenterProtocolDetected(event.contractVersion);
        controller.completePresenterRender(sessionId: event.sessionId);
        return;
      case PresenterWebLifecycleState.failed:
        controller.presenterProtocolDetected(event.contractVersion);
        controller.dispatchPresenterRenderFailure(
          ReportFlowFailure.presenterRenderPayload(event.payload),
          sessionId: event.sessionId,
        );
        return;
    }
  }

  void handleLoadStart(ReportFlowController controller) {
    controller.presenterLoadStarted();
  }

  void handleProgress(ReportFlowController controller, int progress) {
    controller.presenterLoadProgress(progress / 100);
  }

  void handleReceivedError(
    ReportFlowController controller,
    WebResourceRequest request,
    WebResourceError error,
  ) {
    if (request.isForMainFrame != true) return;
    controller.failPresenterRender(error.description);
  }

  void handleReceivedHttpError(
    ReportFlowController controller,
    WebResourceRequest request,
    WebResourceResponse response,
  ) {
    if (request.isForMainFrame != true) return;
    if (request.url.toString().contains('favicon')) return;
    controller.failPresenterRender(
      'HTTP ${response.statusCode} while loading ${request.url}',
    );
  }
}
