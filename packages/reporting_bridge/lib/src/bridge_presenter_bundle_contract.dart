abstract final class PresenterBundleContract {
  static const String presenterEntryFile = 'presenter.js';
  static const String presenterManifestFile = 'presenter-manifest.json';
  static const String resourceManifestFile = 'resource-manifest.json';

  static const List<String> requiredFontFiles = <String>[
    'fonts/Cairo-Regular.ttf',
    'fonts/Cairo-Medium.ttf',
    'fonts/Cairo-Bold.ttf',
    'fonts/NotoSansArabic-Regular.ttf',
    'fonts/NotoSansArabic-Medium.ttf',
    'fonts/NotoSansArabic-Bold.ttf',
    'fonts/NotoSansMono-Regular.ttf',
    'fonts/NotoSansMono-Medium.ttf',
    'fonts/NotoSansMono-Bold.ttf',
  ];

  static const List<String> requiredResourceFiles = <String>[
    ...requiredFontFiles,
    'icons/MaterialIcons-Regular.ttf',
  ];

  static const List<String> requiredRuntimeFiles = <String>[presenterEntryFile];

  static const List<String> requiredFiles = <String>[
    'index.html',
    presenterEntryFile,
    presenterManifestFile,
    resourceManifestFile,
    ...requiredResourceFiles,
  ];

  static const List<String> requiredJavaScriptMarkers = <String>[
    'base64Chunk',
    'urbReportingBridge',
    'presenterLifecycle',
    'onPresenterReady',
    'onRenderStarted',
    'onRenderCompleted',
    'onRenderFailed',
    'exportPdf',
  ];
}
