import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:reporting_bridge/reporting_bridge.dart';

import '../flow/report_flow_controller.dart';
import '../platform/presenter_surface_binding.dart';
import '../platform/presenter_web_surface_coordinator.dart';
import 'headless_presenter_surface.dart';

final class InAppHeadlessPresenterSurface implements HeadlessPresenterSurface {
  InAppHeadlessPresenterSurface({
    PresenterWebSurfaceCoordinator coordinator =
        const PresenterWebSurfaceCoordinator(),
  }) : _coordinator = coordinator;

  final PresenterWebSurfaceCoordinator _coordinator;
  HeadlessInAppWebView? _webView;

  @override
  Future<void> start({
    required PresenterSessionLaunch launch,
    required String templateName,
    required ReportFlowController controller,
    required PresenterSurfaceBinding surfaceBinding,
  }) async {
    await dispose();
    final webView = HeadlessInAppWebView(
      initialSize: const Size(-1, -1),
      initialUrlRequest: URLRequest(url: WebUri(launch.presenterUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        supportZoom: false,
        useShouldOverrideUrlLoading: true,
      ),
      onWebViewCreated: (webController) {
        _coordinator.attach(
          webController: webController,
          sessionId: launch.sessionId,
          templateName: templateName,
          controller: controller,
          surfaceBinding: surfaceBinding,
        );
      },
      onLoadStart: (_, __) => _coordinator.handleLoadStart(controller),
      onProgressChanged: (_, progress) =>
          _coordinator.handleProgress(controller, progress),
      onReceivedError: (_, request, error) =>
          _coordinator.handleReceivedError(controller, request, error),
      onReceivedHttpError: (_, request, response) =>
          _coordinator.handleReceivedHttpError(controller, request, response),
    );
    _webView = webView;
    await webView.run();
  }

  @override
  Future<void> dispose() async {
    final webView = _webView;
    _webView = null;
    if (webView == null) return;
    await webView.dispose();
  }
}
