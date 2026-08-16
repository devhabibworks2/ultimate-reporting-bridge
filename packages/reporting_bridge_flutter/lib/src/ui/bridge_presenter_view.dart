import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:reporting_bridge/reporting_bridge.dart';

import '../flow/report_flow_controller.dart';
import '../flow/report_flow_failure.dart';
import '../platform/presenter_surface_binding.dart';

class BridgePresenterView extends StatefulWidget {
  const BridgePresenterView({
    super.key,
    required this.launch,
    required this.templateName,
    required this.controller,
    required this.surfaceBinding,
  });

  final PresenterSessionLaunch launch;
  final String templateName;
  final ReportFlowController controller;
  final PresenterSurfaceBinding surfaceBinding;

  @override
  State<BridgePresenterView> createState() => _BridgePresenterViewState();
}

class _BridgePresenterViewState extends State<BridgePresenterView> {
  @override
  void didUpdateWidget(covariant BridgePresenterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.launch.sessionId != widget.launch.sessionId ||
        !identical(oldWidget.surfaceBinding, widget.surfaceBinding)) {
      oldWidget.surfaceBinding.detachSession(oldWidget.launch.sessionId);
    }
  }

  @override
  void dispose() {
    widget.surfaceBinding.detachSession(widget.launch.sessionId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      key: ValueKey<String>('presenter-${widget.launch.sessionId}'),
      initialUrlRequest: URLRequest(url: WebUri(widget.launch.presenterUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: false,
        // The embedded Presenter owns report pan/zoom through its
        // InteractiveViewer. Native WebView zoom would create a second scale
        // authority around that surface and can make gestures inconsistent.
        supportZoom: false,
        useShouldOverrideUrlLoading: true,
      ),
      onWebViewCreated: (webController) {
        webController.addJavaScriptHandler(
          handlerName: 'urbReportingBridge',
          callback: (args) {
            if (args.isNotEmpty) {
              widget.surfaceBinding.acceptMessage(args.first);
            }
            return null;
          },
        );
        widget.surfaceBinding.attach(
          sessionId: widget.launch.sessionId,
          templateName: widget.templateName,
          evaluateJavaScript: (source) =>
              webController.evaluateJavascript(source: source),
          reload: webController.reload,
          onLifecycle: (event) {
            switch (event.state) {
              case PresenterWebLifecycleState.connected:
                widget.controller.presenterProtocolDetected(
                  event.contractVersion,
                );
                return;
              case PresenterWebLifecycleState.loading:
                widget.controller.presenterLoadStarted();
                widget.controller.presenterProtocolDetected(
                  event.contractVersion,
                );
                return;
              case PresenterWebLifecycleState.ready:
                widget.controller.presenterProtocolDetected(
                  event.contractVersion,
                );
                widget.controller.completePresenterRender(
                  sessionId: event.sessionId,
                );
                return;
              case PresenterWebLifecycleState.failed:
                widget.controller.presenterProtocolDetected(
                  event.contractVersion,
                );
                widget.controller.dispatchPresenterRenderFailure(
                  ReportFlowFailure.presenterRenderPayload(event.payload),
                  sessionId: event.sessionId,
                );
                return;
            }
          },
        );
      },
      onLoadStart: (_, __) => widget.controller.presenterLoadStarted(),
      onProgressChanged: (_, progress) =>
          widget.controller.presenterLoadProgress(progress / 100),
      onReceivedError: (_, request, error) {
        if (request.isForMainFrame != true) return;
        widget.controller.failPresenterRender(error.description);
      },
      onReceivedHttpError: (_, request, response) {
        if (request.isForMainFrame != true) return;
        if (request.url.toString().contains('favicon')) return;
        widget.controller.failPresenterRender(
          'HTTP ${response.statusCode} while loading ${request.url}',
        );
      },
    );
  }
}
