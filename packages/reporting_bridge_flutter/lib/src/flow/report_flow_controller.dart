import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:reporting_bridge/reporting_bridge.dart';

import '../contracts/report_open_request.dart';
import '../contracts/template_compatibility_constraints.dart';
import '../platform/bridge_platform_adapters.dart';
import '../platform/presenter_surface_binding.dart';
import '../printing/thermal_printer_controller.dart';
import '../ui/bridge_ui_features.dart';
import 'report_action_policy.dart';
import 'report_flow_event.dart';
import 'report_flow_failure.dart';
import 'report_flow_state.dart';
import 'report_result.dart';

abstract interface class ReportFlowController
    implements ValueListenable<ReportFlowState> {
  ReportOpenRequest get request;
  Stream<ReportFlowEvent> get events;
  PresenterSurfaceBinding get presenterSurface;

  Future<void> initialize();
  Future<void> syncTemplates();
  Future<void> syncPresenter();
  Future<void> continueFromPreparation();
  void backToPreparation();
  void openTemplateSelection({
    TemplateSelectionOrigin origin = TemplateSelectionOrigin.initialSetup,
  });
  void openResourcePreparation(ResourcePreparationOrigin origin);
  void returnFromResourcePreparation();
  void confirmTemplateSelection();
  void selectTemplate(String templateId);
  void selectMode(PresenterModePreference mode);
  void editSettings();
  Future<void> commitSettings();
  void cancelSettings();
  Future<void> preparePreview();
  void presenterLoadStarted();
  void presenterLoadProgress(double progress);
  void presenterProtocolDetected(int contractVersion);
  void completePresenterRender({String? sessionId});
  void failPresenterRender(String diagnostic, {String? sessionId});
  Future<void> savePdf();
  Future<void> sharePdf();
  Future<void> retry();
  Future<ReportResult> close();
  Future<void> dispose();
}

/// Optional capability for controllers that can preserve structured Presenter
/// render failures without breaking the stable [ReportFlowController] surface.
abstract interface class ReportFlowStructuredFailureController {
  void failPresenterRenderFailure(
    ReportFlowFailure failure, {
    String? sessionId,
  });
}

abstract interface class ReportFlowSupportController {
  Future<void> shareDevelopmentSupportPackage({Rect? sharePositionOrigin});
  Future<void> clearCachedResources();
}

extension ReportFlowControllerSupportActions on ReportFlowController {
  ReportFlowSupportController? get _supportController =>
      this is ReportFlowSupportController
      ? this as ReportFlowSupportController
      : null;

  bool get supportActionsAvailable => _supportController != null;

  Future<void> shareDevelopmentSupportPackage({Rect? sharePositionOrigin}) {
    final support = _supportController;
    if (support == null) {
      return Future<void>.error(
        const ReportFlowFailure(
          code: ReportFlowFailureCode.developmentSupportFailed,
          diagnostic: 'Controller does not expose development support.',
        ),
      );
    }
    return support.shareDevelopmentSupportPackage(
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  Future<void> clearCachedResources() {
    final support = _supportController;
    if (support == null) {
      return Future<void>.error(
        const ReportFlowFailure(
          code: ReportFlowFailureCode.cacheClearFailed,
          diagnostic: 'Controller does not expose cache maintenance.',
        ),
      );
    }
    return support.clearCachedResources();
  }
}

extension ReportFlowStructuredFailureDispatch on ReportFlowController {
  void dispatchPresenterRenderFailure(
    ReportFlowFailure failure, {
    String? sessionId,
  }) {
    final controller = this;
    if (controller is ReportFlowStructuredFailureController) {
      (controller as ReportFlowStructuredFailureController)
          .failPresenterRenderFailure(failure, sessionId: sessionId);
      return;
    }
    controller.failPresenterRender(
      failure.diagnostic ?? failure.code.name,
      sessionId: sessionId,
    );
  }
}

abstract interface class ReportFlowActionController {
  ReportActionPolicy get actionPolicy;
  BridgeUiFeatures get effectiveFeatures;
  TemplateCompatibilityConstraints get compatibilityConstraints;
  List<CachedTemplate> get eligibleTemplates;
  bool get outputReady;

  Future<ReportPrintResult> printPdf();
}

/// Optional access to the app-wide managed thermal-printer settings.
abstract interface class ReportFlowThermalPrinterController {
  ThermalPrinterSettingsController? get thermalPrinterSettings;
}

extension ReportFlowControllerActions on ReportFlowController {
  ReportFlowActionController? get _actions => this is ReportFlowActionController
      ? this as ReportFlowActionController
      : null;

  ReportActionPolicy get actionPolicy =>
      _actions?.actionPolicy ?? request.actionPolicy;

  BridgeUiFeatures get effectiveFeatures =>
      _actions?.effectiveFeatures ??
      request.featuresOverride?.restrictTo(actionPolicy) ??
      const BridgeUiFeatures().restrictTo(actionPolicy);

  TemplateCompatibilityConstraints get compatibilityConstraints =>
      _actions?.compatibilityConstraints ??
      resolveTemplateCompatibilityConstraints(request);

  List<CachedTemplate> get eligibleTemplates =>
      _actions?.eligibleTemplates ?? value.templates;

  bool get outputReady => _actions?.outputReady ?? value.exportReady;

  Future<ReportPrintResult> printPdf() {
    final actions = _actions;
    if (actions == null) {
      return Future<ReportPrintResult>.error(
        const ReportFlowFailure(
          code: ReportFlowFailureCode.printUnavailable,
          diagnostic: 'Controller does not expose print capabilities.',
        ),
      );
    }
    return actions.printPdf();
  }

  ThermalPrinterSettingsController? get thermalPrinterSettings =>
      this is ReportFlowThermalPrinterController
      ? (this as ReportFlowThermalPrinterController).thermalPrinterSettings
      : null;
}

TemplateCompatibilityConstraints resolveTemplateCompatibilityConstraints(
  ReportOpenRequest request,
) => request.compatibility;
