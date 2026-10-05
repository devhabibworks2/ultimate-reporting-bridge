import '../flow/report_flow_controller.dart';
import '../flow/report_flow_state.dart';
import '../platform/bridge_platform_adapters.dart';
import '../printing/thermal_printer_models.dart';
import 'headless_presenter_surface.dart';
import 'headless_report_print_progress.dart';
import 'headless_report_render_runner.dart';

final class HeadlessReportPrintRunner {
  HeadlessReportPrintRunner({
    required ReportFlowController Function() createController,
    required HeadlessPresenterSurfaceFactory surfaceFactory,
  }) : _createController = createController,
       _surfaceFactory = surfaceFactory;

  final ReportFlowController Function() _createController;
  final HeadlessPresenterSurfaceFactory _surfaceFactory;

  Future<ReportPrintResult> run({
    HeadlessReportPrintProgressCallback? onProgress,
    HeadlessReportPrintTimingCallback? onTiming,
  }) async {
    final totalWatch = Stopwatch()..start();
    var stageWatch = Stopwatch()..start();
    var printStarted = false;

    void timing(HeadlessReportPrintTimingStage stage) {
      _emitTiming(
        HeadlessReportPrintTiming(
          stage: stage,
          stageElapsed: stageWatch.elapsed,
          totalElapsed: totalWatch.elapsed,
        ),
        onTiming,
      );
      stageWatch = Stopwatch()..start();
    }

    _emit(
      const HeadlessReportPrintProgress(
        phase: HeadlessReportPrintPhase.preparingReport,
      ),
      onProgress,
    );

    return HeadlessReportRenderRunner(
      createController: _createController,
      surfaceFactory: _surfaceFactory,
    ).run<ReportPrintResult>(
      onControllerChange: (controller) {
        _handleControllerChange(
          controller: controller,
          onProgress: onProgress,
          printStarted: printStarted,
        );
      },
      onStage: (stage, controller) {
        switch (stage) {
          case HeadlessReportRenderStage.initialized:
            timing(HeadlessReportPrintTimingStage.preparingTemplate);
          case HeadlessReportRenderStage.sessionReady:
            timing(HeadlessReportPrintTimingStage.preparingSession);
            _emit(
              HeadlessReportPrintProgress(
                phase: HeadlessReportPrintPhase.loadingPresenter,
                fraction: controller.value.webViewLoadProgress,
              ),
              onProgress,
            );
          case HeadlessReportRenderStage.surfaceStarted:
            timing(HeadlessReportPrintTimingStage.startingWebView);
          case HeadlessReportRenderStage.outputReady:
            timing(HeadlessReportPrintTimingStage.rendering);
        }
      },
      consume: (controller) async {
        printStarted = true;
        _emit(
          const HeadlessReportPrintProgress(
            phase: HeadlessReportPrintPhase.generatingPdf,
          ),
          onProgress,
        );
        final result = await controller.printPdf();
        timing(HeadlessReportPrintTimingStage.generatingPdf);
        _emit(
          const HeadlessReportPrintProgress(
            phase: HeadlessReportPrintPhase.completed,
          ),
          onProgress,
        );
        timing(HeadlessReportPrintTimingStage.completed);
        return result;
      },
    );
  }

  void _handleControllerChange({
    required ReportFlowController controller,
    required HeadlessReportPrintProgressCallback? onProgress,
    required bool printStarted,
  }) {
    final printProgress = controller.value.printProgress;
    if (printProgress != null) {
      _emit(_mapThermal(printProgress), onProgress);
      return;
    }
    if (printStarted) return;
    _emit(_phaseFromState(controller.value), onProgress);
  }

  HeadlessReportPrintProgress _phaseFromState(ReportFlowState state) {
    if (state.webViewLoadProgress < 1 &&
        state.renderStatus != PresenterRenderStatus.ready) {
      return HeadlessReportPrintProgress(
        phase: HeadlessReportPrintPhase.loadingPresenter,
        fraction: state.webViewLoadProgress,
      );
    }
    return const HeadlessReportPrintProgress(
      phase: HeadlessReportPrintPhase.renderingReport,
    );
  }

  HeadlessReportPrintProgress _mapThermal(ThermalPrintProgress progress) {
    return HeadlessReportPrintProgress(
      phase: switch (progress.phase) {
        ThermalPrintPhase.preparing =>
          HeadlessReportPrintPhase.preparingPrinter,
        ThermalPrintPhase.connecting =>
          HeadlessReportPrintPhase.connectingPrinter,
        ThermalPrintPhase.rasterizing => HeadlessReportPrintPhase.rasterizing,
        ThermalPrintPhase.transmitting => HeadlessReportPrintPhase.transmitting,
        ThermalPrintPhase.printing => HeadlessReportPrintPhase.sendingToPrinter,
      },
      current: progress.pageIndex ?? progress.copyIndex,
      total: progress.pageCount ?? progress.copyCount,
      bytesSent: progress.bytesSent,
      totalBytes: progress.totalBytes,
    );
  }

  void _emit(
    HeadlessReportPrintProgress progress,
    HeadlessReportPrintProgressCallback? onProgress,
  ) {
    if (onProgress == null) return;
    try {
      onProgress(progress);
    } catch (_) {
      // Host progress callbacks must not fail the print operation.
    }
  }

  void _emitTiming(
    HeadlessReportPrintTiming timing,
    HeadlessReportPrintTimingCallback? onTiming,
  ) {
    if (onTiming == null) return;
    try {
      onTiming(timing);
    } catch (_) {
      // Host diagnostics must not fail the print operation.
    }
  }
}
