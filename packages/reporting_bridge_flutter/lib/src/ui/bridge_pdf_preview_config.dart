/// Immutable PDF preview scale policy for Bridge PDF viewers.
final class BridgePdfPreviewConfig {
  const BridgePdfPreviewConfig({
    this.minScale = 0.6,
    this.maxScale = 8.0,
    this.initialScale = 0.8,
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
