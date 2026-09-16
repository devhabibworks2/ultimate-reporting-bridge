import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:reporting_bridge/reporting_bridge.dart';

import '../flow/report_flow_controller.dart';
import '../platform/presenter_surface_binding.dart';
import '../platform/presenter_web_surface_coordinator.dart';
import 'headless_presenter_surface.dart';

final class InAppHeadlessPresenterSurface
    implements WarmableHeadlessPresenterSurface {
  InAppHeadlessPresenterSurface({
    PresenterWebSurfaceCoordinator coordinator =
        const PresenterWebSurfaceCoordinator(),
  }) : _coordinator = coordinator;

  final PresenterWebSurfaceCoordinator _coordinator;
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
        useShouldOverrideUrlLoading: true,
      ),
      onWebViewCreated: (webController) {
        _webController = webController;
        _attach(webController);
      },
      onLoadStart: (_, __) {
        final controller = _controller;
        if (controller != null) _coordinator.handleLoadStart(controller);
      },
      onProgressChanged: (_, progress) {
        final controller = _controller;
        if (controller != null) {
          _coordinator.handleProgress(controller, progress);
        }
      },
      onReceivedError: (_, request, error) {
        final controller = _controller;
        if (controller != null) {
          _coordinator.handleReceivedError(controller, request, error);
        }
      },
      onReceivedHttpError: (_, request, response) {
        final controller = _controller;
        if (controller != null) {
          _coordinator.handleReceivedHttpError(controller, request, response);
        }
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
    _coordinator.attach(
      webController: webController,
      sessionId: launch.sessionId,
      templateName: templateName,
      controller: controller,
      surfaceBinding: surfaceBinding,
    );
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
    if (webView == null) return;
    await webView.dispose();
  }
}
