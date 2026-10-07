class BridgeUiFeatures {
  const BridgeUiFeatures({
    this.allowOfflineMode = true,
    this.showCurrentTemplate = true,
    this.showTemplateMetadata = true,
    this.showPrint = false,
    this.showSavePdf = true,
    this.showSharePdf = true,
    this.showSettings = true,
    this.showDevelopmentSupport = true,
  });

  final bool allowOfflineMode;
  final bool showCurrentTemplate;
  final bool showTemplateMetadata;
  final bool showPrint;
  final bool showSavePdf;
  final bool showSharePdf;
  final bool showSettings;

  /// Controls the explicit development-support action that can package
  /// report diagnostics, including seed data, for user-initiated sharing.
  ///
  /// Defaults to true by product decision. Hosts that must prohibit
  /// diagnostic data export can disable it explicitly.
  final bool showDevelopmentSupport;

  bool get hasVisibleOutputAction => showPrint || showSavePdf || showSharePdf;
}
