import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:reporting_bridge_flutter/src/presenter/report_resource_preparation_service.dart';

void main() {
  late Directory root;
  late _RecordingBridge bridge;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('resource-preparation-');
    bridge = _RecordingBridge(root);
  });
  tearDown(() async {
    await bridge.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'preserves system, filter, extra, and identity without a surface',
    () async {
      final filter = TemplateSyncFilter(
        reportTypes: <String>['sales_invoice'],
        layouts: <String>['Pages'],
      );
      final request = TemplateSyncRequest(
        systemCode: UrbSystem.motakamelTransactions,
        filter: filter,
        extra: const <String, Object?>{
          'tenant': 'T1',
          'nested': <String, Object?>{'a': 1},
        },
        identity: const ReportIdentity(
          userId: 'u1',
          branchId: 'b2',
          systemUnit: 'unit3',
        ),
      );
      final result = await ReportResourcePreparationService(
        bridgeClient: bridge,
      ).prepare(request, mode: PresenterModePreference.online);

      expect(bridge.systemCode, 'motakamel_transactions');
      expect(bridge.filter, same(filter));
      expect(bridge.extra, request.extra);
      expect(bridge.identity.userId, 'u1');
      expect(bridge.identity.branchId, 'b2');
      expect(bridge.identity.systemUnit, 'unit3');
      expect(result.templateSummary.syncedCount, 1);
      expect(result.presenterManifest, isNull);
      expect(bridge.presenterSyncCalls, 0);
    },
  );

  test(
    'offline preparation syncs Presenter and returns its manifest',
    () async {
      final result =
          await ReportResourcePreparationService(bridgeClient: bridge).prepare(
            TemplateSyncRequest(systemCode: UrbSystem.motakamelTransactions),
            mode: PresenterModePreference.offline,
          );
      expect(bridge.presenterSyncCalls, 1);
      expect(result.presenterManifest?.bundleVersion, '1.2.3');
    },
  );
}

final class _RecordingBridge extends ReportingBridgeClient {
  _RecordingBridge(Directory root)
    : super(
        apiBaseUrl: Uri.parse('https://example.test/api/'),
        presenterEntryUrl: Uri.parse('https://example.test/presenter/'),
        bridgeRoot: root,
      );
  String? systemCode;
  TemplateSyncFilter? filter;
  Map<String, Object?>? extra;
  BridgeIdentityContext identity = BridgeIdentityContext();
  int presenterSyncCalls = 0;

  @override
  Future<void> updateIdentityContext(BridgeIdentityContext value) async {
    identity = value;
  }

  @override
  Future<TemplateSyncSummary> syncTemplates({
    String? systemCode,
    int? systemId,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    this.systemCode = systemCode;
    this.filter = filter;
    this.extra = extra;
    return TemplateSyncSummary(
      syncedCount: 1,
      listCount: 1,
      errors: const <String>[],
    );
  }

  @override
  Future<PresenterCacheManifest> syncPresenter({
    void Function(double progress)? onProgress,
  }) async {
    presenterSyncCalls += 1;
    return const PresenterCacheManifest(
      bundleVersion: '1.2.3',
      devVersion: 3,
      rootPath: '/tmp/presenter',
    );
  }
}
