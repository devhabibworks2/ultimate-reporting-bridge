import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:reporting_bridge/reporting_bridge.dart';

import '../flow/report_flow_controller.dart';
import '../flow/report_flow_failure.dart';
import '../platform/presenter_surface_binding.dart';
import 'headless_presenter_surface.dart';

final class InAppHeadlessPresenterSurface
    implements WarmableHeadlessPresenterSurface {
  HeadlessInAppWebView? _webView;
  InAppWebViewController? _webController;
  ReportFlowController? _controller;
  PresenterSurfaceBinding? _surfaceBinding;
  PresenterSessionLaunch? _launch;
  String? _templateName;

  @override
  Future<void> warmUp() async {
    if (_webView != null) return;
    await _createWebView(URLRequest(url: WebUri('about:blank')));
  }

  @override
  Future<void> start({
    required PresenterSessionLaunch launch,
    required String templateName,
    required ReportFlowController controller,
    required PresenterSurfaceBinding surfaceBinding,
  }) async {
    await dispose();
    _launch = launch;
    _templateName = templateName;
    _controller = controller;
    _surfaceBinding = surfaceBinding;
    final webController = _webController;
    if (webController != null) {
      _attach(webController);
      await webController.loadUrl(
        urlRequest: URLRequest(url: WebUri(launch.presenterUrl)),
      );
      return;
    }
    await _createWebView(URLRequest(url: WebUri(launch.presenterUrl)));
  }

  Future<void> _createWebView(URLRequest initialRequest) async {
    final webView = HeadlessInAppWebView(
      initialSize: const Size(-1, -1),
      initialUrlRequest: initialRequest,
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        supportZoom: false,
      ),
      onWebViewCreated: (webController) {
        _webController = webController;
        _attach(webController);
      },
      onLoadStart: (_, __) => _controller?.presenterLoadStarted(),
      onProgressChanged: (_, progress) =>
          _controller?.presenterLoadProgress(progress / 100),
      onReceivedError: (_, request, error) {
        if (request.isForMainFrame != true) return;
        _controller?.failPresenterRender(error.description);
      },
      onReceivedHttpError: (_, request, response) {
        if (request.isForMainFrame != true) return;
        if (request.url.toString().contains('favicon')) return;
        _controller?.failPresenterRender(
          'HTTP ${response.statusCode} while loading ${request.url}',
        );
      },
    );
    _webView = webView;
    await webView.run();
  }

  void _attach(InAppWebViewController webController) {
    final launch = _launch;
    final templateName = _templateName;
    final controller = _controller;
    final surfaceBinding = _surfaceBinding;
    if (launch == null ||
        templateName == null ||
        controller == null ||
        surfaceBinding == null) {
      return;
    }

    webController.removeJavaScriptHandler(handlerName: 'urbReportingBridge');
    webController.addJavaScriptHandler(
      handlerName: 'urbReportingBridge',
      callback: (args) {
        if (args.isNotEmpty) surfaceBinding.acceptMessage(args.first);
        return null;
      },
    );
    surfaceBinding.attach(
      sessionId: launch.sessionId,
      templateName: templateName,
      evaluateJavaScript: (source) =>
          webController.evaluateJavascript(source: source),
      reload: webController.reload,
      onLifecycle: (event) => _handleLifecycle(event, controller),
    );
  }

  void _handleLifecycle(
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

  @override
  Future<void> dispose() async {
    _surfaceBinding?.detach();
    _launch = null;
    _templateName = null;
    _controller = null;
    _surfaceBinding = null;
  }

  @override
  Future<void> shutdown() async {
    await dispose();
    final webView = _webView;
    _webView = null;
    _webController = null;
    if (webView != null) await webView.dispose();
  }
}
