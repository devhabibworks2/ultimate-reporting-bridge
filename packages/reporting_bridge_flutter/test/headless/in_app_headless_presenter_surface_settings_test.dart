import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/src/headless/in_app_headless_presenter_surface.dart';

void main() {
  test(
    'hidden Presenter WebView enables JS, disables zoom, and leaves navigation override unset',
    () async {
      final platform = _CapturingHeadlessWebViewPlatform();
      InAppWebViewPlatform.instance = platform;

      final surface = InAppHeadlessPresenterSurface();
      await surface.warmUp();

      final params = platform.lastHeadlessParams;
      expect(params, isNotNull);
      final settings = params!.initialSettings;
      expect(settings, isNotNull);
      expect(settings!.javaScriptEnabled, isTrue);
      expect(settings.supportZoom, isFalse);
      // Preserve 9548ec4: do not restore donor useShouldOverrideUrlLoading: true.
      expect(settings.useShouldOverrideUrlLoading, isNot(true));
      expect(params.shouldOverrideUrlLoading, isNull);

      await surface.shutdown();
    },
  );
}

class _CapturingHeadlessWebViewPlatform extends InAppWebViewPlatform {
  PlatformHeadlessInAppWebViewCreationParams? lastHeadlessParams;

  @override
  PlatformHeadlessInAppWebView createPlatformHeadlessInAppWebView(
    PlatformHeadlessInAppWebViewCreationParams params,
  ) {
    lastHeadlessParams = params;
    return _FakePlatformHeadlessInAppWebView(params);
  }

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    return _UnusedPlatformInAppWebViewWidget(params);
  }
}

class _FakePlatformHeadlessInAppWebView extends PlatformHeadlessInAppWebView {
  _FakePlatformHeadlessInAppWebView(super.params) : super.implementation();

  @override
  String get id => 'headless-test';

  @override
  PlatformInAppWebViewController? get webViewController => null;

  @override
  Future<void> run() async {}

  @override
  bool isRunning() => false;

  @override
  Future<void> dispose() async {}
}

class _UnusedPlatformInAppWebViewWidget extends PlatformInAppWebViewWidget {
  _UnusedPlatformInAppWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) {
    throw UnimplementedError();
  }

  @override
  void dispose() {}
}
