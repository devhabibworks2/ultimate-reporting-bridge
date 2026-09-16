enum HeadlessReportPrintPhase {
  preparingReport,
  loadingPresenter,
  renderingReport,
  generatingPdf,
  preparingPrinter,
  connectingPrinter,
  rasterizing,
  transmitting,
  sendingToPrinter,
  completed,
}

final class HeadlessReportPrintProgress {
  const HeadlessReportPrintProgress({
    required this.phase,
    this.fraction,
    this.current,
    this.total,
    this.bytesSent,
    this.totalBytes,
  }) : assert(fraction == null || (fraction >= 0 && fraction <= 1));

  final HeadlessReportPrintPhase phase;
  final double? fraction;
  final int? current;
  final int? total;
  final int? bytesSent;
  final int? totalBytes;
}

typedef HeadlessReportPrintProgressCallback =
    void Function(HeadlessReportPrintProgress progress);

enum HeadlessReportPrintTimingStage {
  preparingTemplate,
  preparingSession,
  startingWebView,
  rendering,
  generatingPdf,
  rasterizing,
  connecting,
  transmitting,
  completed,
}

final class HeadlessReportPrintTiming {
  const HeadlessReportPrintTiming({
    required this.stage,
    required this.stageElapsed,
    required this.totalElapsed,
  });

  final HeadlessReportPrintTimingStage stage;
  final Duration stageElapsed;
  final Duration totalElapsed;
}

typedef HeadlessReportPrintTimingCallback =
    void Function(HeadlessReportPrintTiming timing);

final class HeadlessPrintWarmupResult {
  const HeadlessPrintWarmupResult({
    required this.webViewReady,
    required this.resourcesRefreshed,
    this.presenterMode,
    this.diagnostic,
  });

  final bool webViewReady;
  final bool resourcesRefreshed;
  final String? presenterMode;
  final String? diagnostic;
}
