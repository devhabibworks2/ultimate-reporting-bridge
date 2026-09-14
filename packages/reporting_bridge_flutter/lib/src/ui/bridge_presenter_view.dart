import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:reporting_bridge/reporting_bridge.dart';

import '../flow/report_flow_controller.dart';
import '../platform/presenter_surface_binding.dart';
import '../platform/presenter_web_surface_coordinator.dart';

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
  static const _coordinator = PresenterWebSurfaceCoordinator();

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
        _coordinator.attach(
          webController: webController,
          sessionId: widget.launch.sessionId,
          templateName: widget.templateName,
          controller: widget.controller,
          surfaceBinding: widget.surfaceBinding,
        );
      },
      onLoadStart: (_, __) => _coordinator.handleLoadStart(widget.controller),
      onProgressChanged: (_, progress) =>
          _coordinator.handleProgress(widget.controller, progress),
      onReceivedError: (_, request, error) {
        _coordinator.handleReceivedError(widget.controller, request, error);
      },
      onReceivedHttpError: (_, request, response) {
        _coordinator.handleReceivedHttpError(
          widget.controller,
          request,
          response,
        );
      },
    );
  }
}
