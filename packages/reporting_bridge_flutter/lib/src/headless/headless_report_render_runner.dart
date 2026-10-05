import 'dart:async';

import 'package:reporting_bridge/reporting_bridge.dart';

import '../flow/report_flow_controller.dart';
import '../flow/report_flow_failure.dart';
import '../flow/report_flow_state.dart';
import 'headless_presenter_surface.dart';

enum HeadlessReportRenderStage {
  initialized,
  sessionReady,
  surfaceStarted,
  outputReady,
}

typedef HeadlessReportRenderConsumer<T> =
    Future<T> Function(ReportFlowController controller);
typedef HeadlessReportRenderControllerChange =
    void Function(ReportFlowController controller);
typedef HeadlessReportRenderStageCallback =
    void Function(
      HeadlessReportRenderStage stage,
      ReportFlowController controller,
    );

final class HeadlessReportRenderRunner {
  HeadlessReportRenderRunner({
    required ReportFlowController Function() createController,
    required HeadlessPresenterSurfaceFactory surfaceFactory,
  }) : _createController = createController,
       _surfaceFactory = surfaceFactory;

  final ReportFlowController Function() _createController;
  final HeadlessPresenterSurfaceFactory _surfaceFactory;

  Future<T> run<T>({
    required HeadlessReportRenderConsumer<T> consume,
    HeadlessReportRenderControllerChange? onControllerChange,
    HeadlessReportRenderStageCallback? onStage,
  }) async {
    final controller = _createController();
    HeadlessPresenterSurface? surface;

    void listener() => onControllerChange?.call(controller);
    if (onControllerChange != null) {
      controller.addListener(listener);
    }

    try {
      await controller.initialize();
      onStage?.call(HeadlessReportRenderStage.initialized, controller);
      final failure = controller.value.failure;
      if (failure != null) throw failure;

      final launch = _requireLaunch(controller);
      final template =
          controller.value.committedTemplate ??
          controller.value.selectedTemplate!;
      onStage?.call(HeadlessReportRenderStage.sessionReady, controller);

      surface = _surfaceFactory();
      await surface.start(
        launch: launch,
        templateName: template.templateName,
        controller: controller,
        surfaceBinding: controller.presenterSurface,
      );
      onStage?.call(HeadlessReportRenderStage.surfaceStarted, controller);

      await _waitForOutputReady(controller);
      onStage?.call(HeadlessReportRenderStage.outputReady, controller);

      return await consume(controller);
    } finally {
      if (onControllerChange != null) {
        controller.removeListener(listener);
      }
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
    final failure = controller.value.failure;
    if (failure != null) {
      return Future<void>.error(failure);
    }
    if (controller.outputReady) {
      return Future<void>.value();
    }

    final ready = Completer<void>();
    void listener() {
      final currentFailure = controller.value.failure;
      if (currentFailure != null) {
        controller.removeListener(listener);
        if (!ready.isCompleted) ready.completeError(currentFailure);
        return;
      }
      if (controller.outputReady) {
        controller.removeListener(listener);
        if (!ready.isCompleted) ready.complete();
      }
    }

    controller.addListener(listener);
    listener();
    return ready.future.whenComplete(() {
      controller.removeListener(listener);
    });
  }
}
