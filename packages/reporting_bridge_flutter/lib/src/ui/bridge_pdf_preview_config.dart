import 'dart:ui';

const double bridgePdfPreviewPagePadding = 10.0;
const double bridgePdfA4AspectRatio = 210 / 297;

/// Mirrors the initial page transform used by PdfViewPinch for the first page.
///
/// PdfViewPinch first lays a page out at fit-width inside its 10dp page
/// padding, then Bridge applies [BridgePdfPreviewConfig.initialScale] and
/// centers the scaled page on each axis when it fits.
Rect bridgePdfInitialPageRect({
  required Size viewport,
  required BridgePdfPreviewConfig config,
  double pageAspectRatio = bridgePdfA4AspectRatio,
}) {
  assert(pageAspectRatio > 0 && pageAspectRatio < double.infinity);
  if (viewport.isEmpty) return Rect.zero;

  final fitWidth = (viewport.width - bridgePdfPreviewPagePadding * 2)
      .clamp(0.0, double.infinity)
      .toDouble();
  final fitHeight = fitWidth / pageAspectRatio;
  final scale = config.initialScale;
  final width = fitWidth * scale;
  final height = fitHeight * scale;

  final left = width < viewport.width
      ? (viewport.width - width) / 2
      : bridgePdfPreviewPagePadding * scale;
  final top = height < viewport.height
      ? (viewport.height - height) / 2
      : bridgePdfPreviewPagePadding * scale;

  return Rect.fromLTWH(left, top, width, height);
}

/// Immutable PDF preview scale policy for Bridge PDF viewers.
final class BridgePdfPreviewConfig {
  const BridgePdfPreviewConfig({
    this.minScale = 0.6,
    this.maxScale = 8.0,
    this.initialScale = 0.97,
  }) : assert(minScale > 0 && minScale < double.infinity),
       assert(maxScale > 0 && maxScale < double.infinity),
       assert(initialScale > 0 && initialScale < double.infinity),
       assert(maxScale >= minScale),
       assert(initialScale >= minScale),
       assert(initialScale <= maxScale);

  final double minScale;
  final double maxScale;
  final double initialScale;
}
