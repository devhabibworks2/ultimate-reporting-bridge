abstract final class PresenterBundleContract {
  static const List<String> assetManifestPaths = <String>[
    'assets/AssetManifest.bin',
    'assets/AssetManifest.bin.json',
    'assets/AssetManifest.json',
  ];

  static const List<String> requiredRuntimeFiles = <String>['main.dart.js'];

  static const List<String> requiredFiles = <String>[
    ...requiredRuntimeFiles,
    'flutter_bootstrap.js',
    'assets/FontManifest.json',
    'assets/fonts/MaterialIcons-Regular.otf',
    'assets/assets/fonts/Cairo-Regular.ttf',
    'assets/assets/fonts/Cairo-Medium.ttf',
    'assets/assets/fonts/Cairo-Bold.ttf',
    'assets/assets/fonts/NotoSansArabic-Regular.ttf',
    'assets/assets/fonts/NotoSansArabic-Medium.ttf',
    'assets/assets/fonts/NotoSansArabic-Bold.ttf',
    'assets/assets/fonts/NotoSansMono-Regular.ttf',
    'assets/assets/fonts/NotoSansMono-Medium.ttf',
    'assets/assets/fonts/NotoSansMono-Bold.ttf',
  ];

  static const List<String> requiredJavaScriptMarkers = <String>[
    'base64Chunk',
    'urbReportingBridge',
    'presenterLifecycle',
    'onPresenterReady',
    'onRenderStarted',
    'onRenderCompleted',
    'onRenderFailed',
  ];
}
