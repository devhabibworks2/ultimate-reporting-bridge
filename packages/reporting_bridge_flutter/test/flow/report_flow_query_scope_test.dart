import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:reporting_bridge_flutter/src/flow/report_flow_controller_impl.dart';
import 'package:reporting_bridge_flutter/src/flow/report_flow_runtime.dart';

void main() {
  test('V2 sync and list use the exact TemplateSyncRequest scope', () async {
    final root = Directory.systemTemp.createTempSync('urb-query-scope-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    final bridge = _RecordingScopedBridgeClient(root);
    addTearDown(bridge.dispose);

    final filter = TemplateSyncFilter(
      reportTypes: <String>[UrbReportType.salesInvoice.value],
      layouts: <String>[ReportLayout.pages.value],
      sizes: <String>[ReportPageSize.a4.value],
      languages: <String>[ReportLanguage.ar.value],
      units: <String>[ReportMeasurementUnit.mm.value],
      orientations: <String>[ReportOrientation.portrait.value],
    );
    const extra = <String, Object?>{'transactionType': 'cash'};
    final open = ReportOpenRequest(
      seedData: const <String, dynamic>{'id': 1},
      selectedTemplateCriteria: SelectedTemplateCriteria(
        reportType: UrbReportType.salesInvoice,
        identity: const ReportIdentity(
          userId: '42',
          branchId: '01',
          systemUnit: 'MAIN',
        ),
      ),
      templateSyncRequest: TemplateSyncRequest(
        systemCode: UrbSystem.motakamelTransactions,
        identity: const ReportIdentity(
          userId: '42',
          branchId: '01',
          systemUnit: 'MAIN',
        ),
        filter: filter,
        extra: extra,
      ),
    );

    final controller = ReportFlowControllerImpl(
      request: open,
      features: const BridgeUiFeatures(),
      runtime: ReportFlowRuntime(
        connection: ReportServerConnection(
          endpoints: ReportServerEndpoints.deployed(
            Uri.parse('https://example.test'),
          ),
          cacheRoot: root,
        ),
        bridgeClient: bridge,
        preferences: _MemoryPreferences(),
        filePlatform: const _NoopFilePlatform(),
        surfaceBinding: PresenterSurfaceBinding(),
      ),
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.syncTemplates();

    expect(bridge.identityUpdates, isNotEmpty);
    expect(bridge.identityUpdates.last.userId, '42');
    expect(bridge.identityUpdates.last.branchId, '01');
    expect(bridge.identityUpdates.last.systemUnit, 'MAIN');

    expect(bridge.syncCalls, isNotEmpty);
    expect(bridge.listCalls, isNotEmpty);
    for (final call in <_ScopeCall>[...bridge.syncCalls, ...bridge.listCalls]) {
      expect(call.systemCode, 'motakamel_transactions');
      expect(call.systemId, isNull);
      expect(call.filter?.reportTypes, <String>['sales_invoice']);
      expect(call.filter?.layouts, <String>['Pages']);
      expect(call.filter?.sizes, <String>['A4']);
      expect(call.filter?.languages, <String>['ar']);
      expect(call.filter?.units, <String>['mm']);
      expect(call.filter?.orientations, <String>['portrait']);
      expect(call.extra, extra);
    }
  });

  test('sequential V2 flows do not leak identity or filter scope', () async {
    final root = Directory.systemTemp.createTempSync('urb-query-isolation-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    final bridge = _RecordingScopedBridgeClient(root);
    addTearDown(bridge.dispose);

    Future<ReportFlowControllerImpl> openFlow({
      required String userId,
      required String branchId,
      required String size,
    }) async {
      final identity = ReportIdentity(userId: userId, branchId: branchId);
      final open = ReportOpenRequest(
        seedData: const <String, dynamic>{'id': 1},
        selectedTemplateCriteria: SelectedTemplateCriteria(
          reportType: UrbReportType.salesInvoice,
          identity: identity,
        ),
        templateSyncRequest: TemplateSyncRequest(
          systemCode: UrbSystem.motakamelTransactions,
          identity: identity,
          filter: TemplateSyncFilter(
            reportTypes: <String>[UrbReportType.salesInvoice.value],
            sizes: <String>[size],
          ),
        ),
      );
      final controller = ReportFlowControllerImpl(
        request: open,
        features: const BridgeUiFeatures(),
        runtime: ReportFlowRuntime(
          connection: ReportServerConnection(
            endpoints: ReportServerEndpoints.deployed(
              Uri.parse('https://example.test'),
            ),
            cacheRoot: root,
          ),
          bridgeClient: bridge,
          preferences: _MemoryPreferences(),
          filePlatform: const _NoopFilePlatform(),
          surfaceBinding: PresenterSurfaceBinding(),
        ),
      );
      await controller.initialize();
      await controller.syncTemplates();
      return controller;
    }

    final flowA = await openFlow(userId: 'A', branchId: '1', size: 'A4');
    await flowA.dispose();

    final afterAIdentity = bridge.identityContext;
    expect(afterAIdentity.isEmpty, isTrue);

    final syncBeforeB = bridge.syncCalls.length;
    final listBeforeB = bridge.listCalls.length;

    final flowB = await openFlow(userId: 'B', branchId: '2', size: '80mm');
    addTearDown(flowB.dispose);

    final bSync = bridge.syncCalls.sublist(syncBeforeB);
    final bList = bridge.listCalls.sublist(listBeforeB);
    expect(bSync, isNotEmpty);
    expect(bList, isNotEmpty);
    for (final call in <_ScopeCall>[...bSync, ...bList]) {
      expect(call.filter?.sizes, <String>['80mm']);
    }
    expect(bridge.identityUpdates.last.userId, 'B');
    expect(bridge.identityUpdates.last.branchId, '2');

    await flowB.dispose();
    expect(bridge.identityContext.isEmpty, isTrue);

    await bridge.fetchSystems();
    expect(bridge.fetchSystemsCalls, 1);
    expect(bridge.identityContext.isEmpty, isTrue);
  });
}

final class _ScopeCall {
  const _ScopeCall({
    required this.systemCode,
    required this.systemId,
    required this.filter,
    required this.extra,
  });

  final String? systemCode;
  final int? systemId;
  final TemplateSyncFilter? filter;
  final Map<String, Object?> extra;
}

final class _RecordingScopedBridgeClient extends ReportingBridgeClient {
  _RecordingScopedBridgeClient(Directory root)
    : super(
        apiBaseUrl: Uri.parse('https://example.test/UltimateReport/backend/'),
        presenterEntryUrl: Uri.parse(
          'https://example.test/UltimateReport/apps/presenter/index.html',
        ),
        bridgeRoot: root,
      );

  final List<_ScopeCall> syncCalls = <_ScopeCall>[];
  final List<_ScopeCall> listCalls = <_ScopeCall>[];
  final List<BridgeIdentityContext> identityUpdates = <BridgeIdentityContext>[];
  int fetchSystemsCalls = 0;

  @override
  Future<void> updateIdentityContext(BridgeIdentityContext value) async {
    identityUpdates.add(value);
    await super.updateIdentityContext(value);
  }

  @override
  Future<List<PresenterSystem>> fetchSystems() async {
    fetchSystemsCalls += 1;
    return const <PresenterSystem>[];
  }

  @override
  Future<TemplateSyncSummary> syncTemplates({
    String? systemCode,
    int? systemId,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    syncCalls.add(
      _ScopeCall(
        systemCode: systemCode,
        systemId: systemId,
        filter: filter,
        extra: extra,
      ),
    );
    return TemplateSyncSummary(
      syncedCount: 1,
      listCount: 1,
      errors: const <String>[],
    );
  }

  @override
  Future<List<CachedTemplate>> listTemplates({
    String? systemCode,
    int? systemId,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    listCalls.add(
      _ScopeCall(
        systemCode: systemCode,
        systemId: systemId,
        filter: filter,
        extra: extra,
      ),
    );
    return <CachedTemplate>[
      CachedTemplate(
        id: 't1',
        type: 'sales_invoice',
        name: 'Invoice',
        version: '1',
        document: <String, dynamic>{
          'schemaVersion': '1.0.0',
          'meta': <String, dynamic>{
            'family': 'sales_invoice',
            'systemCode': systemCode ?? 'motakamel_transactions',
          },
          'page': <String, dynamic>{
            'layout': 'Pages',
            'size': 'A4',
            'unit': 'mm',
            'orientation': 'portrait',
            'language': 'ar',
            'width': 210,
            'height': 297,
          },
          'assets': <dynamic>[],
          'layers': <dynamic>[],
          'elements': <dynamic>[],
        },
        metadata: <String, dynamic>{
          'systemCode': systemCode ?? 'motakamel_transactions',
        },
      ),
    ];
  }

  @override
  Future<ReportingBridgeStatus> getStatus() async => ReportingBridgeStatus(
    apiBaseUrl: apiBaseUrl.toString(),
    presenterCached: true,
    templateCount: 1,
    presenterManifest: PresenterCacheManifest(
      bundleVersion: '1.0.0',
      devVersion: 1,
      rootPath: bridgeRoot.path,
      presenterVersion: '1.0.0',
    ),
  );
}

final class _MemoryPreferences implements ReportFlowPreferenceStore {
  ReportFlowPreferences? stored;

  @override
  Future<ReportFlowPreferences?> load(ReportPreferenceScope scope) async =>
      stored;

  @override
  Future<void> save(
    ReportPreferenceScope scope,
    ReportFlowPreferences preferences,
  ) async {
    stored = preferences;
  }

  @override
  Future<void> remove(ReportPreferenceScope scope) async {
    stored = null;
  }

  @override
  Future<void> removeSelectedTemplate(ReportPreferenceScope scope) async {
    if (stored == null) return;
    stored = ReportFlowPreferences(templateId: null, mode: stored!.mode);
  }
}

final class _NoopFilePlatform implements ReportFilePlatform {
  const _NoopFilePlatform();

  @override
  Future<bool> savePdf(Uint8List bytes, String filename) async => true;

  @override
  Future<void> sharePdf(Uint8List bytes, String filename) async {}
}
