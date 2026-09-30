import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:reporting_bridge/reporting_bridge.dart';

import '../flow/report_flow_controller.dart';
import '../headless/headless_presenter_surface.dart';
import '../headless/in_app_headless_presenter_surface.dart';
import '../platform/presenter_surface_binding.dart';
import 'bridge_pdf_view.dart';

typedef BridgePdfViewBuilder =
    Widget Function(BuildContext context, Uint8List bytes);

class BridgePresenterView extends StatefulWidget {
  const BridgePresenterView({
    super.key,
    required this.launch,
    required this.templateName,
    required this.controller,
    required this.surfaceBinding,
    @visibleForTesting this.headlessSurfaceFactory,
    @visibleForTesting this.pdfViewBuilder,
  });

  final PresenterSessionLaunch launch;
  final String templateName;
  final ReportFlowController controller;
  final PresenterSurfaceBinding surfaceBinding;

  @visibleForTesting
  final HeadlessPresenterSurfaceFactory? headlessSurfaceFactory;

  @visibleForTesting
  final BridgePdfViewBuilder? pdfViewBuilder;

  @override
  State<BridgePresenterView> createState() => _BridgePresenterViewState();
}

class _BridgePresenterViewState extends State<BridgePresenterView> {
  late HeadlessPresenterSurface _surface;
  int _surfaceGeneration = 0;
  Object? _surfaceError;

  @override
  void initState() {
    super.initState();
    _surface = _createSurface();
    unawaited(_startSurface(_surface, ++_surfaceGeneration));
  }

  @override
  void didUpdateWidget(covariant BridgePresenterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.launch.sessionId == widget.launch.sessionId &&
        oldWidget.launch.presenterUrl == widget.launch.presenterUrl &&
        oldWidget.launch.presenterVersion == widget.launch.presenterVersion &&
        oldWidget.launch.presenterDevVersion ==
            widget.launch.presenterDevVersion &&
        identical(oldWidget.surfaceBinding, widget.surfaceBinding) &&
        identical(oldWidget.controller, widget.controller) &&
        oldWidget.templateName == widget.templateName) {
      return;
    }

    oldWidget.surfaceBinding.detach();
    final previous = _surface;
    _surface = _createSurface();
    final generation = ++_surfaceGeneration;
    _surfaceError = null;
    unawaited(_replaceSurface(previous, _surface, generation));
  }

  HeadlessPresenterSurface _createSurface() =>
      widget.headlessSurfaceFactory?.call() ?? InAppHeadlessPresenterSurface();

  Future<void> _replaceSurface(
    HeadlessPresenterSurface previous,
    HeadlessPresenterSurface next,
    int generation,
  ) async {
    await _shutdownSurface(previous);
    if (!mounted || generation != _surfaceGeneration) {
      await _shutdownSurface(next);
      return;
    }
    await _startSurface(next, generation);
  }

  Future<void> _startSurface(
    HeadlessPresenterSurface surface,
    int generation,
  ) async {
    try {
      await surface.start(
        launch: widget.launch,
        templateName: widget.templateName,
        controller: widget.controller,
        surfaceBinding: widget.surfaceBinding,
      );
      if (!mounted ||
          generation != _surfaceGeneration ||
          _surfaceError == null) {
        return;
      }
      setState(() {
        _surfaceError = null;
      });
    } catch (error) {
      if (!mounted || generation != _surfaceGeneration) return;
      setState(() {
        _surfaceError = error;
      });
    }
  }

  Future<void> _shutdownSurface(HeadlessPresenterSurface surface) =>
      surface is WarmableHeadlessPresenterSurface
      ? surface.shutdown()
      : surface.dispose();

  @override
  Widget build(BuildContext context) {
    final surfaceError = _surfaceError;
    if (surfaceError != null) {
      return const Center(
        key: Key('bridge-presenter-runtime-error'),
        child: Text('Report preview unavailable'),
      );
    }

    final cachedPdf = widget.surfaceBinding.cachedPdf;
    if (cachedPdf == null) {
      return const Center(
        key: Key('bridge-pdf-loading'),
        child: CircularProgressIndicator(),
      );
    }

    final builder = widget.pdfViewBuilder;
    if (builder != null) {
      return builder(context, cachedPdf.bytes);
    }
    return BridgePdfView(bytes: cachedPdf.bytes);
  }

  @override
  void dispose() {
    _surfaceGeneration += 1;
    widget.surfaceBinding.detachSession(widget.launch.sessionId);
    unawaited(_shutdownSurface(_surface));
    super.dispose();
  }
}
