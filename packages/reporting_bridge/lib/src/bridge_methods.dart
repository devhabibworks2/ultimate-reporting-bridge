/// Method names on [BridgeContract.channelName].
///
/// **Host → presenter:** host invokes these on Flutter.
/// **Presenter → host:** Flutter invokes these on the host.
abstract final class BridgeMethods {
  /// Host pushes boot context (seed, token, hints). Invoked once per session ideally.
  static const String applyBoot = 'applyBoot';

  static const String initializeBridge = 'initializeBridge';
  static const String setBrandConfig = 'setBrandConfig';
  static const String setServerConfig = 'setServerConfig';
  static const String setApiHeaders = 'setApiHeaders';
  static const String setActionsUiState = 'setActionsUiState';
  static const String syncPresenterSite = 'syncPresenterSite';
  static const String syncTemplates = 'syncTemplates';
  static const String openReportSetup = 'openReportSetup';
  static const String getAvailableTemplates = 'getAvailableTemplates';
  static const String getSeedData = 'getSeedData';
  static const String getSelectedTemplate = 'getSelectedTemplate';
  static const String setSelectedTemplate = 'setSelectedTemplate';
  static const String clearSelectedTemplate = 'clearSelectedTemplate';
  static const String setReportName = 'setReportName';
  static const String setReportType = 'setReportType';
  static const String setSeedData = 'setSeedData';
  static const String prepareRuntimeSession = 'prepareRuntimeSession';
  static const String rebuildReport = 'rebuildReport';
  static const String openPreview = 'openPreview';
  static const String savePdf = 'savePdf';
  static const String sharePdf = 'sharePdf';
  static const String printPdf = 'printPdf';
  static const String shareImage = 'shareImage';
  static const String clearRuntimeSession = 'clearRuntimeSession';
  static const String clearTemplateCache = 'clearTemplateCache';
  static const String clearPresenterCache = 'clearPresenterCache';
  static const String getBridgeStatus = 'getBridgeStatus';
  static const String disposeBridge = 'disposeBridge';

  /// Host pushes inline template document + runtime data (0 HTTP calls).
  static const String applyInlineSession = 'applyInlineSession';

  static const String onBridgeReady = 'onBridgeReady';
  static const String onModeChanged = 'onModeChanged';
  static const String onReportSetupRequired = 'onReportSetupRequired';
  static const String onReportSetupStarted = 'onReportSetupStarted';
  static const String onReportSetupCompleted = 'onReportSetupCompleted';
  static const String onRuntimeSessionPrepared = 'onRuntimeSessionPrepared';
  static const String onPreviewOpened = 'onPreviewOpened';
  static const String onWarnings = 'onWarnings';
  static const String onExportCompleted = 'onExportCompleted';
  static const String onError = 'onError';
}
