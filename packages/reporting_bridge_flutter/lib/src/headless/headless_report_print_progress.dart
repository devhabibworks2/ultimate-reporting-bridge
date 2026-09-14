enum HeadlessReportPrintPhase {
  preparingReport,
  loadingPresenter,
  renderingReport,
  generatingPdf,
  preparingPrinter,
  connectingPrinter,
  sendingToPrinter,
  completed,
}

final class HeadlessReportPrintProgress {
  const HeadlessReportPrintProgress({
    required this.phase,
    this.fraction,
    this.current,
    this.total,
  }) : assert(fraction == null || (fraction >= 0 && fraction <= 1));

  final HeadlessReportPrintPhase phase;
  final double? fraction;
  final int? current;
  final int? total;
}

typedef HeadlessReportPrintProgressCallback =
    void Function(HeadlessReportPrintProgress progress);
