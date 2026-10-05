import 'package:flutter/material.dart';

import '../localization/report_flow_strings.dart';
import 'bridge_pdf_preview_config.dart';

enum ReportPreviewLoadingStage {
  preparingData,
  preparingReport,
  openingPreview,
}

class ReportPreviewLoadingOverlay extends StatefulWidget {
  const ReportPreviewLoadingOverlay({
    super.key,
    required this.stage,
    required this.strings,
    this.previewConfig = const BridgePdfPreviewConfig(),
    this.onClose,
  });

  final ReportPreviewLoadingStage stage;
  final ReportFlowStrings strings;
  final BridgePdfPreviewConfig previewConfig;
  final VoidCallback? onClose;

  @override
  State<ReportPreviewLoadingOverlay> createState() =>
      _ReportPreviewLoadingOverlayState();
}

class _ReportPreviewLoadingOverlayState
    extends State<ReportPreviewLoadingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _shimmer.stop();
    } else if (_shimmer.status == AnimationStatus.dismissed) {
      _shimmer.forward();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  String get _stageLabel => switch (widget.stage) {
    ReportPreviewLoadingStage.preparingData =>
      widget.strings.preparingDataStage,
    ReportPreviewLoadingStage.preparingReport =>
      widget.strings.preparingReportStage,
    ReportPreviewLoadingStage.openingPreview =>
      widget.strings.openingPreviewStage,
  };

  Widget _buildStageLabel(bool reducedMotion) =>
      _ReportStageLabel(label: _stageLabel, reducedMotion: reducedMotion);

  Widget _buildSkeleton(bool reducedMotion) =>
      _ReportSkeleton(animation: _shimmer, animate: !reducedMotion);

  Widget _buildCompactLayout(bool reducedMotion) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
        child: Column(
          children: <Widget>[
            _buildStageLabel(reducedMotion),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = constraints.maxWidth < 360
                      ? constraints.maxWidth
                      : 360.0;
                  final widthFromHeight =
                      constraints.maxHeight * bridgePdfA4AspectRatio;
                  final width = widthFromHeight < maxWidth
                      ? widthFromHeight
                      : maxWidth;
                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: width,
                      child: AspectRatio(
                        aspectRatio: bridgePdfA4AspectRatio,
                        child: _buildSkeleton(reducedMotion),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // In very short landscape viewports the real PDF is taller than the
        // viewport. Keep the loading page below the status header rather than
        // letting the header obscure it.
        if (constraints.maxHeight < 500) {
          return _buildCompactLayout(reducedMotion);
        }

        final pageRect = bridgePdfInitialPageRect(
          viewport: Size(
            constraints.maxWidth,
            MediaQuery.sizeOf(context).height,
          ),
          config: widget.previewConfig,
        );

        final stageAreaHeight = (pageRect.top - 12).clamp(
          0.0,
          constraints.maxHeight,
        );

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: <Widget>[
            Positioned(
              left: pageRect.left,
              top: 0,
              width: pageRect.width,
              height: stageAreaHeight,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _buildStageLabel(reducedMotion),
              ),
            ),
            Positioned.fromRect(
              rect: pageRect,
              child: _buildSkeleton(reducedMotion),
            ),
          ],
        );
      },
    );
  }
}

class _ReportStageLabel extends StatelessWidget {
  const _ReportStageLabel({required this.label, required this.reducedMotion});

  final String label;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final contentDirection = Directionality.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      key: const ValueKey<String>('bridge-loading-status'),
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: AnimatedSwitcher(
          duration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          child: SizedBox(
            key: ValueKey<String>('bridge-loading-stage-$label'),
            width: double.infinity,
            child: Directionality(
              textDirection: contentDirection,
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.62),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ReportPreviewCloseButton extends StatelessWidget {
  const ReportPreviewCloseButton({
    super.key,
    required this.strings,
    required this.onPressed,
  });

  final ReportFlowStrings strings;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: strings.close,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: 48,
          child: IconButton(
            key: const ValueKey<String>('bridge-report-close'),
            tooltip: strings.close,
            onPressed: onPressed,
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: scheme.onSurfaceVariant,
              minimumSize: const Size.square(48),
              fixedSize: const Size.square(48),
              shape: const RoundedRectangleBorder(),
            ),
            icon: Container(
              key: const ValueKey<String>('bridge-loading-close-visual'),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(13),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.close, size: 27),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportSkeleton extends StatelessWidget {
  const _ReportSkeleton({required this.animation, required this.animate});

  final Animation<double> animation;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final highlight = scheme.surfaceContainerLow;

    Widget block({required double height, required double radius}) =>
        _SkeletonBlock(
          height: height,
          radius: radius,
          base: base,
          highlight: highlight,
          animation: animation,
          animate: animate,
        );

    return Container(
      key: const ValueKey<String>('bridge-report-skeleton'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 280,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              block(height: 42, radius: 9),
              const SizedBox(height: 14),
              FractionallySizedBox(
                widthFactor: 0.72,
                alignment: AlignmentDirectional.centerStart,
                child: block(height: 10, radius: 99),
              ),
              const SizedBox(height: 8),
              FractionallySizedBox(
                widthFactor: 0.46,
                alignment: AlignmentDirectional.centerStart,
                child: block(height: 10, radius: 99),
              ),
              const SizedBox(height: 20),
              block(height: 132, radius: 9),
              const SizedBox(height: 18),
              block(height: 78, radius: 9),
              const Spacer(),
              block(height: 34, radius: 9),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    required this.height,
    required this.radius,
    required this.base,
    required this.highlight,
    required this.animation,
    required this.animate,
  });

  final double height;
  final double radius;
  final Color base;
  final Color highlight;
  final Animation<double> animation;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    Widget paint(double t) => Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: animate ? null : base,
        gradient: animate
            ? LinearGradient(
                begin: Alignment(-1.8 + 3.6 * t, 0),
                end: Alignment(-0.8 + 3.6 * t, 0),
                colors: <Color>[base, highlight, base],
                stops: const <double>[0, 0.5, 1],
              )
            : null,
      ),
    );

    if (!animate) return paint(0);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => paint(animation.value),
    );
  }
}
