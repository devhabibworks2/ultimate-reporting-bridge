import 'dart:async';

import 'package:reporting_bridge/reporting_bridge.dart';

import '../flow/report_flow_controller.dart';
import '../flow/report_flow_failure.dart';
import '../flow/report_flow_state.dart';
import '../platform/bridge_platform_adapters.dart';
import '../printing/thermal_printer_models.dart';
import 'headless_presenter_surface.dart';
import 'headless_report_print_progress.dart';

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
  }) async {
    _emit(
      const HeadlessReportPrintProgress(
        phase: HeadlessReportPrintPhase.preparingReport,
      ),
      onProgress,
    );

    final controller = _createController();
    HeadlessPresenterSurface? surface;
    var printStarted = false;

    void listener() {
      _handleControllerChange(
        controller: controller,
        onProgress: onProgress,
        printStarted: printStarted,
      );
    }

    controller.addListener(listener);
    try {
      await controller.initialize();
      if (controller.value.failure != null) {
        throw controller.value.failure!;
      }
      final launch = _requireLaunch(controller);
      final template =
          controller.value.committedTemplate ??
          controller.value.selectedTemplate!;

      _emit(
        HeadlessReportPrintProgress(
          phase: HeadlessReportPrintPhase.loadingPresenter,
          fraction: controller.value.webViewLoadProgress,
        ),
        onProgress,
      );

      surface = _surfaceFactory();
      await surface.start(
        launch: launch,
        templateName: template.templateName,
        controller: controller,
        surfaceBinding: controller.presenterSurface,
      );

      await _waitForOutputReady(controller);

      printStarted = true;
      _emit(
        const HeadlessReportPrintProgress(
          phase: HeadlessReportPrintPhase.generatingPdf,
        ),
        onProgress,
      );
      final result = await controller.printPdf();
      _emit(
        const HeadlessReportPrintProgress(
          phase: HeadlessReportPrintPhase.completed,
        ),
        onProgress,
      );
      return result;
    } finally {
      controller.removeListener(listener);
      await surface?.dispose();
      await controller.dispose();
    }
  }

  PresenterSessionLaunch _requireLaunch(ReportFlowController controller) {
    final state = controller.value;
    final launch = state.presenterLaunch;
    final template = state.committedTemplate ?? state.selectedTemplate;
    if (launch != null && template != null) {
      return launch;
    }
    if (state.templates.isEmpty) {
      throw const ReportFlowFailure(
        code: ReportFlowFailureCode.noCompatibleTemplates,
      );
    }
    if (state.entryFallbackReason == ReportEntryFallbackReason.noSavedDefault ||
        state.entryFallbackReason ==
            ReportEntryFallbackReason.invalidSavedTemplate ||
        state.stage == ReportFlowStage.selectingTemplate ||
        launch == null ||
        template == null) {
      throw const ReportFlowFailure(
        code: ReportFlowFailureCode.templateSelectionRequired,
      );
    }
    throw const ReportFlowFailure(
      code: ReportFlowFailureCode.previewPreparationFailed,
    );
  }

  Future<void> _waitForOutputReady(ReportFlowController controller) {
    if (controller.value.failure != null) {
      return Future<void>.error(controller.value.failure!);
    }
    if (controller.outputReady) {
      return Future<void>.value();
    }

    final ready = Completer<void>();
    void listener() {
      final failure = controller.value.failure;
      if (failure != null) {
        controller.removeListener(listener);
        if (!ready.isCompleted) {
          ready.completeError(failure);
        }
        return;
      }
      if (controller.outputReady) {
        controller.removeListener(listener);
        if (!ready.isCompleted) {
          ready.complete();
        }
      }
    }

    controller.addListener(listener);
    listener();
    return ready.future;
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
        ThermalPrintPhase.printing => HeadlessReportPrintPhase.sendingToPrinter,
      },
      current: progress.pageIndex ?? progress.copyIndex,
      total: progress.pageCount ?? progress.copyCount,
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
}
