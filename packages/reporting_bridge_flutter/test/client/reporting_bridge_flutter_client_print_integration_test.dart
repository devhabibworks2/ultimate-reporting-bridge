import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  late Directory root;
  late _FakeBridgeClient bridge;
  late _FakeFilePlatform filePlatform;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('urb-client-print-');
    bridge = _FakeBridgeClient(root);
    filePlatform = _FakeFilePlatform();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'reuses one WarmableHeadlessPresenterSurface across warm-up and sequential headless prints',
    () async {
      final surface = _RecordingWarmableSurface();
      final preferences = MemoryReportFlowPreferenceStore();
      final fixture = _createClient(
        root: root,
        bridge: bridge,
        filePlatform: filePlatform,
        printPlatform: _FakePrintPlatform(),
        preferences: preferences,
        headlessPresenterSurface: surface,
      );
      addTearDown(fixture.client.dispose);
      await _seedSavedTemplate(fixture.connection, preferences);

      final warmup = await fixture.client.warmUpHeadlessPrinting(
        _request(entryPolicy: ReportEntryPolicy.smart),
      );
      expect(warmup.webViewReady, isTrue);
      expect(surface.warmUpCalls, 1);

      final first = await fixture.client.printReportHeadless(
        _request(entryPolicy: ReportEntryPolicy.smart),
      );
      final second = await fixture.client.printReportHeadless(
        _request(entryPolicy: ReportEntryPolicy.smart),
      );

      expect(first.status, ReportPrintStatus.submitted);
      expect(second.status, ReportPrintStatus.submitted);
      expect(surface.warmUpCalls, 1);
      expect(surface.startCalls, 2);
      expect(identical(surface.lastStartedSurface, surface), isTrue);
    },
  );

  test(
    'active interactive flow excludes headless flow without hidden warm-up',
    () async {
      final surface = _RecordingWarmableSurface();
      final fixture = _createClient(
        root: root,
        bridge: bridge,
        filePlatform: filePlatform,
        printPlatform: _FakePrintPlatform(),
        headlessPresenterSurface: surface,
      );
      addTearDown(fixture.client.dispose);
      final controller = fixture.client.createController(_request());
      addTearDown(controller.dispose);

      await expectLater(
        fixture.client.printReportHeadless(_request()),
        throwsA(
          isA<ReportFlowFailure>().having(
            (failure) => failure.code,
            'code',
            ReportFlowFailureCode.flowAlreadyActive,
          ),
        ),
      );
      expect(surface.warmUpCalls, 0);
      expect(surface.startCalls, 0);
    },
  );

  test(
    'headless path reaches the same injected ReportPrintPlatform as interactive',
    () async {
      final printPlatform = _FakePrintPlatform();
      final preferences = MemoryReportFlowPreferenceStore();
      final fixture = _createClient(
        root: root,
        bridge: bridge,
        filePlatform: filePlatform,
        printPlatform: printPlatform,
        preferences: preferences,
        headlessPresenterSurface: _RecordingWarmableSurface(),
      );
      addTearDown(fixture.client.dispose);
      await _seedSavedTemplate(fixture.connection, preferences);

      final result = await fixture.client.printReportHeadless(
        _request(entryPolicy: ReportEntryPolicy.smart),
      );

      expect(result.status, ReportPrintStatus.submitted);
      expect(printPlatform.calls, 1);
      expect(
        printPlatform.lastRequest?.extra['system'],
        'motakamel_transactions',
      );
    },
  );

  test('client dispose shuts down reusable headless surface once', () async {
    final surface = _RecordingWarmableSurface();
    final fixture = _createClient(
      root: root,
      bridge: bridge,
      filePlatform: filePlatform,
      printPlatform: _FakePrintPlatform(),
      headlessPresenterSurface: surface,
    );

    await fixture.client.dispose();
    await fixture.client.dispose();

    expect(surface.shutdownCalls, 1);
  });

  testWidgets(
    'report flow screen borrows client surface until client disposal',
    (tester) async {
      final surface = _RecordingWarmableSurface();
      final preferences = MemoryReportFlowPreferenceStore();
      final fixture = _createClient(
        root: root,
        bridge: bridge,
        filePlatform: filePlatform,
        printPlatform: _FakePrintPlatform(),
        preferences: preferences,
        headlessPresenterSurface: surface,
      );
      await _seedSavedTemplate(fixture.connection, preferences);
      await fixture.client.warmUpPresenter(
        _request(entryPolicy: ReportEntryPolicy.smart),
        warmPresenterSurface: true,
      );
      final initialPrint = await tester.runAsync(
        () => fixture.client.printReportHeadless(
          _request(entryPolicy: ReportEntryPolicy.smart),
        ),
      );
      expect(initialPrint!.status, ReportPrintStatus.submitted);
      final disposeCallsBeforeInteractive = surface.disposeCalls;
      final controller = fixture.client.createController(
        _request(entryPolicy: ReportEntryPolicy.smart),
      );
      await tester.runAsync(() => _ready(controller));

      await tester.pumpWidget(
        MaterialApp(
          home: ReportFlowScreen(
            controller: controller,
            ui: fixture.client.ui,
            presenterSurface: surface,
          ),
        ),
      );
      await tester.pump();
      expect(surface.startCalls, 2);
      expect(identical(surface.lastStartedSurface, surface), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {});
      expect(surface.disposeCalls, disposeCallsBeforeInteractive + 1);
      expect(surface.shutdownCalls, 0);

      final nextPrint = await tester.runAsync(
        () => fixture.client.printReportHeadless(
          _request(entryPolicy: ReportEntryPolicy.smart),
        ),
      );
      expect(nextPrint!.status, ReportPrintStatus.submitted);
      expect(surface.startCalls, 3);
      expect(identical(surface.lastStartedSurface, surface), isTrue);

      await fixture.client.dispose();
      expect(surface.shutdownCalls, 1);
    },
  );

  test(
    'background refresh uses a separate Bridge client and reports the result',
    () async {
      var httpClientFactoryCalls = 0;
      final surface = _RecordingWarmableSurface();
      final fixture = _createClient(
        root: root,
        bridge: bridge,
        filePlatform: filePlatform,
        printPlatform: _FakePrintPlatform(),
        headlessPresenterSurface: surface,
        httpClientFactory: () {
          httpClientFactoryCalls += 1;
          return HttpClient();
        },
      );
      addTearDown(fixture.client.dispose);

      final syncBefore = bridge.syncTemplatesCalls;
      final disposeBefore = bridge.disposeCalls;

      final result = await fixture.client.warmUpHeadlessPrinting(
        _request(entryPolicy: ReportEntryPolicy.smart),
        refreshResources: true,
      );

      expect(result.webViewReady, isTrue);
      // Refresh constructs a separate ReportingBridgeClient that shares only
      // connection config (including httpClientFactory), not the paid/print
      // Bridge client instance injected into DefaultReportingBridgeFlutterClient.
      expect(httpClientFactoryCalls, greaterThan(0));
      expect(bridge.syncTemplatesCalls, syncBefore);
      expect(bridge.disposeCalls, disposeBefore);
      expect(
        result.resourcesRefreshed ||
            (result.diagnostic != null && result.diagnostic!.isNotEmpty),
        isTrue,
      );
    },
  );

  test('injected print gateway reaches the created flow runtime', () async {
    final printPlatform = _FakePrintPlatform();
    final fixture = _createClient(
      root: root,
      bridge: bridge,
      filePlatform: filePlatform,
      printPlatform: printPlatform,
    );
    addTearDown(fixture.client.dispose);
    final controller = fixture.client.createController(_request());
    addTearDown(controller.dispose);
    await _ready(controller);

    final result = await controller.printPdf();

    expect(result.status, ReportPrintStatus.submitted);
    expect(printPlatform.calls, 1);
    expect(
      printPlatform.lastRequest?.extra['system'],
      'motakamel_transactions',
    );
    expect(printPlatform.lastRequest?.document.languageCode, 'en');
    expect(printPlatform.lastRequest?.document.legacyLanguage, 2);
    expect(filePlatform.saveCalls, 0);
    expect(filePlatform.shareCalls, 0);
  });

  test(
    'selected English template drives en/2 without Host language override',
    () async {
      final printPlatform = _FakePrintPlatform();
      final fixture = _createClient(
        root: root,
        bridge: bridge,
        filePlatform: filePlatform,
        printPlatform: printPlatform,
      );
      addTearDown(fixture.client.dispose);
      final controller = fixture.client.createController(
        ReportOpenRequest(
          seedData: const <String, dynamic>{'id': 1},
          reportName: 'Invoice',
          entryPolicy: ReportEntryPolicy.alwaysPrepare,
          featuresOverride: const BridgeUiFeatures(
            showPrint: true,
            showSavePdf: true,
            showSharePdf: true,
          ),
          selectedTemplateCriteria: SelectedTemplateCriteria(
            reportType: UrbReportType.salesInvoice,
          ),
          templateSyncRequest: TemplateSyncRequest(
            systemCode: UrbSystem.motakamelTransactions,
          ),
          externalPrint: HostExternalPrintRequest(
            documentTitle: 'Host Title',
            extra: <String, Object?>{'copyCount': 1},
          ),
        ),
      );
      addTearDown(controller.dispose);
      await _ready(controller);

      final result = await controller.printPdf();
      final request = printPlatform.lastRequest!;

      expect(result.status, ReportPrintStatus.submitted);
      expect(request.documentTitle, 'Host Title');
      expect(request.document.languageCode, 'en');
      expect(request.document.legacyLanguage, 2);
      expect(request.document.layout, 'Thermal');
      expect(request.document.size, '80mm');
      expect(request.extra['copyCount'], 1);
    },
  );

  test(
    'selected Arabic template drives ar/1 under Arabic compatibility',
    () async {
      bridge.templates
        ..clear()
        ..add(_arabicTemplate());
      final printPlatform = _FakePrintPlatform();
      final fixture = _createClient(
        root: root,
        bridge: bridge,
        filePlatform: filePlatform,
        printPlatform: printPlatform,
      );
      addTearDown(fixture.client.dispose);
      final controller = fixture.client.createController(
        ReportOpenRequest(
          seedData: const <String, dynamic>{'id': 1},
          reportName: 'Invoice',
          entryPolicy: ReportEntryPolicy.alwaysPrepare,
          featuresOverride: const BridgeUiFeatures(
            showPrint: true,
            showSavePdf: true,
            showSharePdf: true,
          ),
          selectedTemplateCriteria: SelectedTemplateCriteria(
            reportType: UrbReportType.salesInvoice,
          ),
          templateSyncRequest: TemplateSyncRequest(
            systemCode: UrbSystem.motakamelTransactions,
          ),
          compatibility: const TemplateCompatibilityConstraints(
            language: ReportLanguage.ar,
            layout: ReportLayout.pages,
            size: ReportPageSize.a4,
          ),
        ),
      );
      addTearDown(controller.dispose);
      await _ready(controller, templateCode: 'PAGES-AR');

      final result = await controller.printPdf();
      final request = printPlatform.lastRequest!;

      expect(result.status, ReportPrintStatus.submitted);
      expect(request.document.languageCode, 'ar');
      expect(request.document.legacyLanguage, 1);
      expect(request.document.layout, 'Pages');
      expect(request.document.size, 'A4');
    },
  );
  test('unsupported default print gateway fails closed', () async {
    final fixture = _createClient(
      root: root,
      bridge: bridge,
      filePlatform: filePlatform,
    );
    addTearDown(fixture.client.dispose);
    final controller = fixture.client.createController(_request());
    addTearDown(controller.dispose);
    await _ready(controller);

    await expectLater(
      controller.printPdf(),
      throwsA(
        isA<ReportFlowFailure>()
            .having(
              (failure) => failure.code,
              'code',
              ReportFlowFailureCode.printFailed,
            )
            .having(
              (failure) => failure.diagnostic,
              'diagnostic',
              'platformUnsupported',
            ),
      ),
    );
    expect(filePlatform.saveCalls, 0);
    expect(filePlatform.shareCalls, 0);
  });

  test(
    'hidden output controls do not authorize programmatic actions',
    () async {
      final printPlatform = _FakePrintPlatform();
      final fixture = _createClient(
        root: root,
        bridge: bridge,
        filePlatform: filePlatform,
        printPlatform: printPlatform,
      );
      addTearDown(fixture.client.dispose);
      final controller = fixture.client.createController(
        _request(
          featuresOverride: const BridgeUiFeatures(
            showPrint: false,
            showSavePdf: false,
            showSharePdf: false,
          ),
        ),
      );
      addTearDown(controller.dispose);
      await _ready(controller);

      await controller.printPdf();
      await controller.savePdf();
      await controller.sharePdf();

      expect(printPlatform.calls, 1);
      expect(filePlatform.saveCalls, 1);
      expect(filePlatform.shareCalls, 1);
    },
  );

  test(
    'headless PDF generation returns exported bytes without print save or share',
    () async {
      final printPlatform = _FakePrintPlatform();
      final preferences = MemoryReportFlowPreferenceStore();
      final fixture = _createClient(
        root: root,
        bridge: bridge,
        filePlatform: filePlatform,
        printPlatform: printPlatform,
        preferences: preferences,
        headlessPresenterSurface: _RecordingWarmableSurface(),
      );
      addTearDown(fixture.client.dispose);
      await _seedSavedTemplate(fixture.connection, preferences);

      final bytes = await fixture.client.generateReportPdfHeadless(
        _request(entryPolicy: ReportEntryPolicy.smart),
      );

      expect(bytes, Uint8List.fromList(<int>[1, 2, 3]));
      expect(printPlatform.calls, 0);
      expect(filePlatform.saveCalls, 0);
      expect(filePlatform.shareCalls, 0);
      bytes[0] = 99;
      expect(bytes, <int>[99, 2, 3]);
    },
  );

  test(
    'active interactive flow excludes headless PDF generation without hidden warm-up',
    () async {
      final surface = _RecordingWarmableSurface();
      final fixture = _createClient(
        root: root,
        bridge: bridge,
        filePlatform: filePlatform,
        printPlatform: _FakePrintPlatform(),
        headlessPresenterSurface: surface,
      );
      addTearDown(fixture.client.dispose);
      final controller = fixture.client.createController(_request());
      addTearDown(controller.dispose);

      await expectLater(
        fixture.client.generateReportPdfHeadless(_request()),
        throwsA(
          isA<ReportFlowFailure>().having(
            (failure) => failure.code,
            'code',
            ReportFlowFailureCode.flowAlreadyActive,
          ),
        ),
      );
      expect(surface.warmUpCalls, 0);
      expect(surface.startCalls, 0);
    },
  );

  test('generation and print are mutually exclusive', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final surface = _RecordingWarmableSurface(
      startEntered: entered,
      startGate: release,
    );
    final printPlatform = _FakePrintPlatform();
    final preferences = MemoryReportFlowPreferenceStore();
    final fixture = _createClient(
      root: root,
      bridge: bridge,
      filePlatform: filePlatform,
      printPlatform: printPlatform,
      preferences: preferences,
      headlessPresenterSurface: surface,
    );
    addTearDown(fixture.client.dispose);
    await _seedSavedTemplate(fixture.connection, preferences);

    final generation = fixture.client.generateReportPdfHeadless(
      _request(entryPolicy: ReportEntryPolicy.smart),
    );
    await entered.future;

    await expectLater(
      fixture.client.printReportHeadless(
        _request(entryPolicy: ReportEntryPolicy.smart),
      ),
      throwsA(
        isA<ReportFlowFailure>().having(
          (failure) => failure.code,
          'code',
          ReportFlowFailureCode.flowAlreadyActive,
        ),
      ),
    );
    expect(printPlatform.calls, 0);
    expect(surface.startCalls, 1);

    release.complete();
    expect(await generation, Uint8List.fromList(<int>[1, 2, 3]));
  });

  test('calls after dispose preserve disposed semantics', () async {
    final surface = _RecordingWarmableSurface();
    final fixture = _createClient(
      root: root,
      bridge: bridge,
      filePlatform: filePlatform,
      printPlatform: _FakePrintPlatform(),
      headlessPresenterSurface: surface,
    );

    await fixture.client.dispose();

    final warmup = await fixture.client.warmUpPresenter(
      _request(),
      refreshResources: true,
      warmHeadlessSurface: true,
    );
    expect(warmup.surfaceStatus, PresenterWarmupSurfaceStatus.failed);
    expect(warmup.resourceStatus, PresenterWarmupResourceStatus.failed);
    expect(warmup.diagnostic, contains('disposed'));

    for (final operation in <Future<Object?> Function()>[
      () => fixture.client.generateReportPdfHeadless(_request()),
      () => fixture.client.printReportHeadless(_request()),
    ]) {
      await expectLater(
        operation(),
        throwsA(
          isA<ReportFlowFailure>().having(
            (failure) => failure.code,
            'code',
            ReportFlowFailureCode.disposed,
          ),
        ),
      );
    }
    expect(surface.shutdownCalls, 1);
  });

  test(
    'headless operations propagate reusable surface warm-up failure before rendering',
    () async {
      final warmupError = StateError('warmup failed');
      final surface = _RecordingWarmableSurface(warmUpError: warmupError);
      final printPlatform = _FakePrintPlatform();
      final preferences = MemoryReportFlowPreferenceStore();
      final fixture = _createClient(
        root: root,
        bridge: bridge,
        filePlatform: filePlatform,
        printPlatform: printPlatform,
        preferences: preferences,
        headlessPresenterSurface: surface,
      );
      addTearDown(fixture.client.dispose);
      await _seedSavedTemplate(fixture.connection, preferences);

      for (final operation in <Future<Object?> Function()>[
        () => fixture.client.printReportHeadless(
          _request(entryPolicy: ReportEntryPolicy.smart),
        ),
        () => fixture.client.generateReportPdfHeadless(
          _request(entryPolicy: ReportEntryPolicy.smart),
        ),
      ]) {
        await expectLater(
          operation(),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'warmup failed',
            ),
          ),
        );
      }

      expect(surface.warmUpCalls, 2);
      expect(surface.startCalls, 0);
      expect(printPlatform.calls, 0);
      expect(filePlatform.saveCalls, 0);
      expect(filePlatform.shareCalls, 0);
    },
  );

  test('surface-only Presenter warm-up skips resource refresh', () async {
    final surface = _RecordingWarmableSurface();
    final fixture = _createClient(
      root: root,
      bridge: bridge,
      filePlatform: filePlatform,
      printPlatform: _FakePrintPlatform(),
      headlessPresenterSurface: surface,
    );
    addTearDown(fixture.client.dispose);

    final result = await fixture.client.warmUpPresenter(
      _request(),
      warmPresenterSurface: true,
    );

    expect(surface.warmUpCalls, 1);
    expect(result.surfaceStatus, PresenterWarmupSurfaceStatus.ready);
    expect(result.resourceStatus, PresenterWarmupResourceStatus.skipped);
    expect(bridge.syncTemplatesCalls, 0);
  });

  test(
    'explicit Presenter warm-up does not touch a surface during a flow',
    () async {
      final surface = _RecordingWarmableSurface();
      final fixture = _createClient(
        root: root,
        bridge: bridge,
        filePlatform: filePlatform,
        printPlatform: _FakePrintPlatform(),
        headlessPresenterSurface: surface,
      );
      addTearDown(fixture.client.dispose);
      final controller = fixture.client.createController(_request());
      addTearDown(controller.dispose);

      final result = await fixture.client.warmUpPresenter(
        _request(),
        warmPresenterSurface: true,
      );

      expect(result.surfaceStatus, PresenterWarmupSurfaceStatus.failed);
      expect(result.diagnostic, contains('flowAlreadyActive'));
      expect(surface.warmUpCalls, 0);
    },
  );

  test('surface warm-up failure leaves resource refresh independent', () async {
    final surface = _RecordingWarmableSurface();
    final fixture = _createClient(
      root: root,
      bridge: bridge,
      filePlatform: filePlatform,
      printPlatform: _FakePrintPlatform(),
      headlessPresenterSurface: surface,
      httpClientFactory: HttpClient.new,
    );
    addTearDown(fixture.client.dispose);
    final controller = fixture.client.createController(_request());
    addTearDown(controller.dispose);

    final result = await fixture.client.warmUpPresenter(
      _request(),
      refreshResources: true,
      warmPresenterSurface: true,
    );

    expect(result.surfaceStatus, PresenterWarmupSurfaceStatus.failed);
    expect(result.diagnostic, contains('flowAlreadyActive'));
    expect(result.resourceStatus, isNot(PresenterWarmupResourceStatus.skipped));
    expect(surface.warmUpCalls, 0);
  });

  test(
    'factory-only warm-up reports unavailable but final print still works',
    () async {
      final createdSurfaces = <_RecordingWarmableSurface>[];
      final preferences = MemoryReportFlowPreferenceStore();
      final printPlatform = _FakePrintPlatform();
      final fixture = _createClient(
        root: root,
        bridge: bridge,
        filePlatform: filePlatform,
        printPlatform: printPlatform,
        preferences: preferences,
        headlessPresenterSurfaceFactory: () {
          final surface = _RecordingWarmableSurface();
          createdSurfaces.add(surface);
          return surface;
        },
      );
      addTearDown(fixture.client.dispose);
      await _seedSavedTemplate(fixture.connection, preferences);

      final warmup = await fixture.client.warmUpPresenter(
        _request(entryPolicy: ReportEntryPolicy.smart),
        warmPresenterSurface: true,
      );
      expect(warmup.surfaceStatus, PresenterWarmupSurfaceStatus.failed);
      expect(warmup.diagnostic, contains('presenterSurfaceUnavailable'));
      expect(createdSurfaces, isEmpty);

      final result = await fixture.client.printReportHeadless(
        _request(entryPolicy: ReportEntryPolicy.smart),
      );

      expect(result.status, ReportPrintStatus.submitted);
      expect(printPlatform.calls, 1);
      expect(createdSurfaces, hasLength(1));
      expect(createdSurfaces.single.startCalls, 1);
    },
  );

  test('warmUpPresenter accepts generic and legacy surface options', () async {
    Future<void> verifyWarmup({
      bool warmPresenterSurface = false,
      bool warmHeadlessSurface = false,
      required bool shouldWarm,
    }) async {
      final surface = _RecordingWarmableSurface();
      final fixture = _createClient(
        root: root,
        bridge: bridge,
        filePlatform: filePlatform,
        printPlatform: _FakePrintPlatform(),
        headlessPresenterSurface: surface,
      );

      final result = await fixture.client.warmUpPresenter(
        _request(),
        warmPresenterSurface: warmPresenterSurface,
        warmHeadlessSurface: warmHeadlessSurface,
      );

      expect(surface.warmUpCalls, shouldWarm ? 1 : 0);
      expect(
        result.surfaceStatus,
        shouldWarm
            ? PresenterWarmupSurfaceStatus.ready
            : PresenterWarmupSurfaceStatus.skipped,
      );
      await fixture.client.dispose();
    }

    await verifyWarmup(warmPresenterSurface: true, shouldWarm: true);
    await verifyWarmup(warmHeadlessSurface: true, shouldWarm: true);
    await verifyWarmup(
      warmPresenterSurface: true,
      warmHeadlessSurface: true,
      shouldWarm: true,
    );
  });
}

_ClientFixture _createClient({
  required Directory root,
  required ReportingBridgeClient bridge,
  required ReportFilePlatform filePlatform,
  ReportPrintPlatform? printPlatform,
  ReportFlowPreferenceStore? preferences,
  WarmableHeadlessPresenterSurface? headlessPresenterSurface,
  HeadlessPresenterSurface Function()? headlessPresenterSurfaceFactory,
  HttpClient Function()? httpClientFactory,
}) {
  final connection = ReportServerConnection(
    endpoints: ReportServerEndpoints.deployed(
      Uri.parse('https://example.test'),
    ),
    cacheRoot: root,
    httpClientFactory: httpClientFactory,
  );
  const ui = BridgeUiConfig.inheritHost(
    features: BridgeUiFeatures(
      showPrint: true,
      showSavePdf: true,
      showSharePdf: true,
    ),
  );
  final store = preferences ?? MemoryReportFlowPreferenceStore();
  final client = printPlatform == null
      ? DefaultReportingBridgeFlutterClient(
          connection: connection,
          bridgeClient: bridge,
          preferences: store,
          filePlatform: filePlatform,
          ui: ui,
          headlessPresenterSurface: headlessPresenterSurface,
          headlessPresenterSurfaceFactory: headlessPresenterSurfaceFactory,
        )
      : DefaultReportingBridgeFlutterClient(
          connection: connection,
          bridgeClient: bridge,
          preferences: store,
          filePlatform: filePlatform,
          printPlatform: printPlatform,
          ui: ui,
          headlessPresenterSurface: headlessPresenterSurface,
          headlessPresenterSurfaceFactory: headlessPresenterSurfaceFactory,
        );
  return _ClientFixture(client, connection);
}

ReportOpenRequest _request({
  ReportEntryPolicy entryPolicy = ReportEntryPolicy.alwaysPrepare,
  BridgeUiFeatures? featuresOverride,
}) => ReportOpenRequest(
  seedData: const <String, dynamic>{'id': 1},
  reportName: 'Invoice',
  entryPolicy: entryPolicy,
  featuresOverride:
      featuresOverride ??
      const BridgeUiFeatures(
        showPrint: true,
        showSavePdf: true,
        showSharePdf: true,
      ),
  selectedTemplateCriteria: SelectedTemplateCriteria(
    reportType: UrbReportType.salesInvoice,
  ),
  templateSyncRequest: TemplateSyncRequest(
    systemCode: UrbSystem.motakamelTransactions,
  ),
);

Future<void> _seedSavedTemplate(
  ReportServerConnection connection,
  ReportFlowPreferenceStore preferences,
) {
  return preferences.save(
    ReportPreferenceScope(
      connectionKey: connection.preferenceSourceKey,
      system: 'motakamel_transactions',
      reportType: 'sales_invoice',
    ),
    const ReportFlowPreferences(
      templateCode: 'THERMAL-EN',
      mode: PresenterModePreference.online,
      language: 'en',
      layout: 'thermal',
      size: '80mm',
    ),
  );
}

Future<void> _ready(
  ReportFlowController controller, {
  String templateCode = 'THERMAL-EN',
}) async {
  await controller.initialize();
  if (controller.value.stage == ReportFlowStage.preparingResources) {
    await controller.continueFromPreparation();
  }
  if (controller.value.stage == ReportFlowStage.selectingTemplate) {
    controller.selectTemplate(templateCode);
    await controller.preparePreview();
  }

  final launch = controller.value.presenterLaunch!;
  controller.presenterSurface.attach(
    sessionId: launch.sessionId,
    templateName: controller.value.selectedTemplate!.templateName,
    evaluateJavaScript: (source) async {
      final correlationId = RegExp(
        r'"correlationId":"([^"]+)"',
      ).firstMatch(source)!.group(1)!;
      controller.presenterSurface.acceptMessage(<String, dynamic>{
        'channel': bridgeWebMessageChannel,
        'method': BridgeWebMethods.exportPdf,
        'correlationId': correlationId,
        'type': 'result',
        'ok': true,
        'base64': base64Encode(<int>[1, 2, 3]),
        'filename': 'invoice.pdf',
        'byteLength': 3,
      });
      return null;
    },
    reload: () async {},
    onLifecycle: (_) {},
  );
  controller.presenterProtocolDetected(BridgeContract.payloadVersion);
  await controller.completePresenterRender(sessionId: launch.sessionId);
  expect(controller.outputReady, isTrue);
}

final class _ClientFixture {
  const _ClientFixture(this.client, this.connection);

  final DefaultReportingBridgeFlutterClient client;
  final ReportServerConnection connection;
}

final class _RecordingWarmableSurface
    implements WarmableHeadlessPresenterSurface {
  _RecordingWarmableSurface({
    this.startEntered,
    this.startGate,
    this.warmUpError,
  });

  final Completer<void>? startEntered;
  final Completer<void>? startGate;
  final Object? warmUpError;
  int warmUpCalls = 0;
  int startCalls = 0;
  int disposeCalls = 0;
  int shutdownCalls = 0;
  WarmableHeadlessPresenterSurface? lastStartedSurface;

  @override
  Future<void> warmUp() async {
    warmUpCalls += 1;
    final error = warmUpError;
    if (error != null) throw error;
  }

  @override
  Future<void> start({
    required PresenterSessionLaunch launch,
    required String templateName,
    required ReportFlowController controller,
    required PresenterSurfaceBinding surfaceBinding,
  }) async {
    await Future<void>.value();
    startCalls += 1;
    lastStartedSurface = this;
    if (startEntered != null && !startEntered!.isCompleted) {
      startEntered!.complete();
    }
    if (startGate != null) {
      await startGate!.future;
    }
    surfaceBinding.attach(
      sessionId: launch.sessionId,
      templateName: templateName,
      evaluateJavaScript: (source) async {
        final correlationId = RegExp(
          r'"correlationId":"([^"]+)"',
        ).firstMatch(source)!.group(1)!;
        surfaceBinding.acceptMessage(<String, dynamic>{
          'channel': bridgeWebMessageChannel,
          'method': BridgeWebMethods.exportPdf,
          'correlationId': correlationId,
          'type': 'result',
          'ok': true,
          'base64': base64Encode(<int>[1, 2, 3]),
          'filename': 'invoice.pdf',
          'byteLength': 3,
        });
        return null;
      },
      reload: () async {},
      onLifecycle: (_) {},
    );
    controller.presenterProtocolDetected(BridgeContract.payloadVersion);
    await controller.completePresenterRender(sessionId: launch.sessionId);
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }

  @override
  Future<void> shutdown() async {
    shutdownCalls += 1;
  }
}

final class _FakePrintPlatform implements ReportPrintPlatform {
  int calls = 0;
  ReportPrintRequest? lastRequest;

  @override
  Future<ReportPrintResult> printPdf(ReportPrintRequest request) async {
    calls += 1;
    lastRequest = request;
    return const ReportPrintResult.submitted();
  }
}

final class _FakeFilePlatform implements ReportFilePlatform {
  int saveCalls = 0;
  int shareCalls = 0;

  @override
  Future<bool> savePdf(Uint8List bytes, String filename) async {
    saveCalls += 1;
    return true;
  }

  @override
  Future<void> sharePdf(Uint8List bytes, String filename) async {
    shareCalls += 1;
  }
}

final class _FakeBridgeClient extends ReportingBridgeClient {
  _FakeBridgeClient(Directory root)
    : super(
        apiBaseUrl: Uri.parse('https://example.test/backend/'),
        presenterEntryUrl: Uri.parse('https://example.test/presenter/'),
        bridgeRoot: root,
      );

  final List<CachedTemplate> templates = <CachedTemplate>[_template()];
  int prepareCalls = 0;
  int syncTemplatesCalls = 0;
  int disposeCalls = 0;

  @override
  Future<List<CachedTemplate>> listTemplates({
    String? systemCode,
    int? systemId,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async => templates;

  @override
  Future<TemplateSyncSummary> syncTemplates({
    String? systemCode,
    int? systemId,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    syncTemplatesCalls += 1;
    return TemplateSyncSummary(
      syncedCount: templates.length,
      listCount: templates.length,
      errors: const <String>[],
    );
  }

  @override
  Future<ReportingBridgeStatus> getStatus() async => ReportingBridgeStatus(
    apiBaseUrl: apiBaseUrl.toString(),
    presenterCached: true,
    templateCount: templates.length,
  );

  @override
  Future<PresenterSessionLaunch> prepareSession(
    PresenterSessionRequest request,
  ) async {
    prepareCalls += 1;
    return PresenterSessionLaunch(
      presenterUrl: 'https://presenter.test/session-$prepareCalls',
      sessionId: 'session-$prepareCalls',
      presenterVersion: '1.0.0',
      presenterDevVersion: 1,
    );
  }

  @override
  Future<PresenterSessionLaunch> prepareReplacementSession(
    PresenterSessionRequest request,
  ) => prepareSession(request);

  @override
  Future<void> commitReplacementSession() async {}

  @override
  Future<void> discardReplacementSession() async {}

  @override
  Future<void> stopSession() async {}

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await super.dispose();
  }
}

CachedTemplate _template() => CachedTemplate(
  type: 'sales_invoice',
  systemId: 7,
  systemCode: 'motakamel_transactions',
  code: 'THERMAL-EN',
  name: 'Thermal invoice',
  document: const <String, dynamic>{
    'schemaVersion': '1.0.0',
    'meta': <String, dynamic>{
      'name': 'Thermal invoice',
      'family': 'sales_invoice',
      'systemCode': 'motakamel_transactions',
      'code': 'THERMAL-EN',
    },
    'page': <String, dynamic>{
      'unit': 'mm',
      'layout': 'Thermal',
      'size': '80mm',
      'width': 80,
      'height': 220,
      'orientation': 'portrait',
      'language': 'en',
      'direction': 'ltr',
    },
    'styleTokens': <String, dynamic>{},
    'assets': <dynamic>[],
    'layers': <dynamic>[],
    'elements': <dynamic>[],
  },
);

CachedTemplate _arabicTemplate() => CachedTemplate(
  type: 'sales_invoice',
  systemId: 7,
  systemCode: 'motakamel_transactions',
  code: 'PAGES-AR',
  name: 'Pages invoice AR',
  document: const <String, dynamic>{
    'schemaVersion': '1.0.0',
    'meta': <String, dynamic>{
      'name': 'Pages invoice AR',
      'family': 'sales_invoice',
      'systemCode': 'motakamel_transactions',
      'code': 'PAGES-AR',
    },
    'page': <String, dynamic>{
      'unit': 'mm',
      'layout': 'Pages',
      'size': 'A4',
      'width': 210,
      'height': 297,
      'orientation': 'portrait',
      'language': 'ar',
      'direction': 'rtl',
    },
    'styleTokens': <String, dynamic>{},
    'assets': <dynamic>[],
    'layers': <dynamic>[],
    'elements': <dynamic>[],
  },
);
