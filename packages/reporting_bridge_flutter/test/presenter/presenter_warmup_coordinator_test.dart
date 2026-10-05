import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:reporting_bridge_flutter/src/presenter/presenter_warmup_coordinator.dart';

void main() {
  test('resource-only warm-up never warms the headless surface', () async {
    var surfaceCalls = 0;
    var resourceCalls = 0;
    final coordinator = PresenterWarmupCoordinator(
      warmSurface: () async {
        surfaceCalls += 1;
        return true;
      },
      resolveMode: (request) async =>
          request.presenterMode ?? PresenterModePreference.online,
      refreshResources: (request, mode) async {
        resourceCalls += 1;
      },
    );

    final result = await coordinator.warmUp(_request(), refreshResources: true);

    expect(surfaceCalls, 0);
    expect(resourceCalls, 1);
    expect(result.surfaceStatus, PresenterWarmupSurfaceStatus.skipped);
    expect(result.resourceStatus, PresenterWarmupResourceStatus.refreshed);
  });

  test('surface-only warm-up never refreshes resources', () async {
    var surfaceCalls = 0;
    var resourceCalls = 0;
    final coordinator = PresenterWarmupCoordinator(
      warmSurface: () async {
        surfaceCalls += 1;
        return true;
      },
      resolveMode: (request) async => PresenterModePreference.online,
      refreshResources: (request, mode) async {
        resourceCalls += 1;
      },
    );

    final result = await coordinator.warmUp(
      _request(),
      warmHeadlessSurface: true,
    );

    expect(surfaceCalls, 1);
    expect(resourceCalls, 0);
    expect(result.surfaceStatus, PresenterWarmupSurfaceStatus.ready);
    expect(result.resourceStatus, PresenterWarmupResourceStatus.skipped);
  });

  test('equivalent resource warm-ups deduplicate while in flight', () async {
    var resourceCalls = 0;
    final gate = Completer<void>();
    final coordinator = PresenterWarmupCoordinator(
      warmSurface: () async => true,
      resolveMode: (request) async => PresenterModePreference.online,
      refreshResources: (request, mode) async {
        resourceCalls += 1;
        await gate.future;
      },
    );
    final request = _request(extra: const <String, Object?>{'b': 2, 'a': 1});

    final first = coordinator.warmUp(request, refreshResources: true);
    final second = coordinator.warmUp(request, refreshResources: true);
    await Future<void>.delayed(Duration.zero);
    expect(resourceCalls, 1);
    gate.complete();
    await Future.wait(<Future<PresenterWarmupResult>>[first, second]);
  });

  test('non-equivalent resource requests never share refresh work', () async {
    var resourceCalls = 0;
    final gates = <Completer<void>>[Completer<void>(), Completer<void>()];
    final coordinator = PresenterWarmupCoordinator(
      warmSurface: () async => true,
      resolveMode: (request) async => PresenterModePreference.online,
      refreshResources: (request, mode) async {
        final index = resourceCalls++;
        await gates[index].future;
      },
    );

    final first = coordinator.warmUp(
      _request(extra: const <String, Object?>{'tenant': 'A'}),
      refreshResources: true,
    );
    final second = coordinator.warmUp(
      _request(extra: const <String, Object?>{'tenant': 'B'}),
      refreshResources: true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(resourceCalls, 2);
    for (final gate in gates) {
      gate.complete();
    }
    await Future.wait(<Future<PresenterWarmupResult>>[first, second]);
  });
}

ReportOpenRequest _request({
  Map<String, Object?> extra = const <String, Object?>{},
}) {
  const identity = ReportIdentity(
    userId: 'u1',
    branchId: 'b1',
    systemUnit: 'unit1',
  );
  return ReportOpenRequest(
    seedData: const <String, dynamic>{'id': 1},
    presenterMode: PresenterModePreference.online,
    selectedTemplateCriteria: SelectedTemplateCriteria(
      reportType: UrbReportType.salesInvoice,
      identity: identity,
    ),
    templateSyncRequest: TemplateSyncRequest(
      systemCode: UrbSystem.motakamelTransactions,
      identity: identity,
      filter: TemplateSyncFilter(reportTypes: <String>['sales_invoice']),
      extra: extra,
    ),
  );
}
