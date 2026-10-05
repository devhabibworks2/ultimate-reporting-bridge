import '../contracts/report_open_request.dart';

enum PresenterWarmupSurfaceStatus { skipped, ready, failed }

enum PresenterWarmupResourceStatus { skipped, ready, refreshed, failed }

final class PresenterWarmupResult {
  const PresenterWarmupResult({
    required this.surfaceStatus,
    required this.resourceStatus,
    this.presenterMode,
    this.diagnostic,
  });

  final PresenterWarmupSurfaceStatus surfaceStatus;
  final PresenterWarmupResourceStatus resourceStatus;
  final PresenterModePreference? presenterMode;
  final String? diagnostic;
}
