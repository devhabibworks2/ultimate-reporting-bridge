import 'package:reporting_bridge/reporting_bridge.dart';

import '../contracts/report_open_request.dart';
import '../contracts/template_sync_request.dart';

abstract interface class ReportResourcePreparationOperations {
  Future<TemplateSyncSummary> syncTemplates(TemplateSyncRequest request);

  Future<PresenterCacheManifest> syncPresenter({
    void Function(double progress)? onProgress,
  });
}

final class ReportResourcePreparationResult {
  const ReportResourcePreparationResult({
    required this.templateSummary,
    this.presenterManifest,
  });

  final TemplateSyncSummary templateSummary;
  final PresenterCacheManifest? presenterManifest;
}

final class ReportResourcePreparationService
    implements ReportResourcePreparationOperations {
  const ReportResourcePreparationService({
    required ReportingBridgeClient bridgeClient,
  }) : _bridgeClient = bridgeClient;

  final ReportingBridgeClient _bridgeClient;

  @override
  Future<TemplateSyncSummary> syncTemplates(TemplateSyncRequest request) async {
    final identity = request.identity;
    await _bridgeClient.updateIdentityContext(
      BridgeIdentityContext(
        userId: identity.userId,
        branchId: identity.branchId,
        systemUnit: identity.systemUnit,
      ),
    );
    return _bridgeClient.syncTemplates(
      systemCode: request.systemCode.value,
      filter: request.filter,
      extra: request.extra,
    );
  }

  @override
  Future<PresenterCacheManifest> syncPresenter({
    void Function(double progress)? onProgress,
  }) {
    return _bridgeClient.syncPresenter(onProgress: onProgress);
  }

  Future<ReportResourcePreparationResult> prepare(
    TemplateSyncRequest request, {
    required PresenterModePreference mode,
    void Function(double progress)? onPresenterProgress,
  }) async {
    final templateSummary = await syncTemplates(request);
    PresenterCacheManifest? presenterManifest;
    if (mode == PresenterModePreference.offline) {
      presenterManifest = await syncPresenter(onProgress: onPresenterProgress);
    }
    return ReportResourcePreparationResult(
      templateSummary: templateSummary,
      presenterManifest: presenterManifest,
    );
  }
}
