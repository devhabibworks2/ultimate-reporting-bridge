import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:reporting_bridge_flutter/src/flow/report_flow_controller_impl.dart';
import 'package:reporting_bridge_flutter/src/flow/report_flow_runtime.dart';
import '../test_open_request.dart';

void main() {
  late Directory root;
  late _FakeBridgeClient bridge;
  late _FakePreferenceStore preferences;

  setUp(() {
    root = Directory.systemTemp.createTempSync('urb-flow-controller-');
    bridge = _FakeBridgeClient(root);
    preferences = _FakePreferenceStore();
  });

  tearDown(() async {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  ReportFlowControllerImpl createController({
    List<CachedTemplate>? templates,
    PresenterModePreference? mode,
    ReportFilePlatform? filePlatform,
    ReportSupportSharePlatform? supportSharePlatform,
    PresenterSurfaceBinding? surfaceBinding,
    Duration renderTimeout = const Duration(seconds: 30),
    BridgeUiFeatures features = const BridgeUiFeatures(),
    ReportEntryPolicy entryPolicy = ReportEntryPolicy.alwaysPrepare,
    int systemId = 1,
  }) {
    bridge.templates = templates ?? <CachedTemplate>[_template('t1')];
    return ReportFlowControllerImpl(
      renderTimeout: renderTimeout,
      features: features,
      request: buildTestOpenRequest(
        system: 'legacy_system_$systemId',
        reportType: 'sales_invoice',
        presenterMode: mode,
        entryPolicy: entryPolicy,
      ),
      runtime: ReportFlowRuntime(
        connection: ReportServerConnection(
          endpoints: ReportServerEndpoints.deployed(
            Uri.parse('https://example.test'),
          ),
          cacheRoot: root,
        ),
        bridgeClient: bridge,
        preferences: preferences,
        filePlatform: filePlatform ?? _FakeFilePlatform(),
        supportSharePlatform:
            supportSharePlatform ??
            const UnsupportedReportSupportSharePlatform(),
        surfaceBinding: surfaceBinding ?? PresenterSurfaceBinding(),
      ),
    );
  }

  test('initialize opens Preparation and online mode can continue', () async {
    final controller = createController();
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.value.stage, ReportFlowStage.preparingResources);
    expect(controller.value.templatesReady, isTrue);
    expect(controller.value.presenterCached, isTrue);
    expect(controller.value.preparationReady, isTrue);

    await controller.continueFromPreparation();
    expect(controller.value.stage, ReportFlowStage.selectingTemplate);
  });

  test('smart entry opens Preview for a valid online default', () async {
    preferences.valuesBySystem['legacy_system_1'] = const ReportFlowPreferences(
      templateId: 't1',
      mode: PresenterModePreference.online,
    );
    final controller = createController(entryPolicy: ReportEntryPolicy.smart);
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.value.stage, ReportFlowStage.previewing);
    expect(controller.value.presenterLaunch, isNotNull);
    expect(bridge.prepareCalls, 1);
  });

  test(
    'smart entry opens Preview for a valid offline default and ready bundle',
    () async {
      preferences.valuesBySystem['legacy_system_1'] =
          const ReportFlowPreferences(
            templateId: 't1',
            mode: PresenterModePreference.offline,
          );
      final controller = createController(entryPolicy: ReportEntryPolicy.smart);
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.value.stage, ReportFlowStage.previewing);
      expect(controller.value.selectedMode, PresenterModePreference.offline);
      expect(bridge.presenterSyncCalls, 0);
    },
  );

  test(
    'smart offline entry falls back without downloading Presenter',
    () async {
      preferences.valuesBySystem['legacy_system_1'] =
          const ReportFlowPreferences(
            templateId: 't1',
            mode: PresenterModePreference.offline,
          );
      bridge.presenterCached = false;
      final controller = createController(entryPolicy: ReportEntryPolicy.smart);
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.value.stage, ReportFlowStage.preparingResources);
      expect(
        controller.value.entryFallbackReason,
        ReportEntryFallbackReason.offlinePresenterUnavailable,
      );
      expect(bridge.presenterSyncCalls, 0);
    },
  );

  test(
    'smart entry synchronizes an empty cache before validating a saved default',
    () async {
      preferences.valuesBySystem['legacy_system_1'] =
          const ReportFlowPreferences(
            templateId: 't1',
            mode: PresenterModePreference.online,
          );
      final controller = createController(
        templates: const <CachedTemplate>[],
        entryPolicy: ReportEntryPolicy.smart,
      );
      bridge.templatesAfterSync = <CachedTemplate>[_template('t1')];
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(bridge.templateSyncCalls, 1);
      expect(controller.value.stage, ReportFlowStage.previewing);
      expect(controller.value.selectedTemplateId, 't1');
      expect(preferences.valuesBySystem['legacy_system_1']?.templateId, 't1');
    },
  );

  test(
    'failed cold-cache synchronization preserves the saved default',
    () async {
      preferences.valuesBySystem['legacy_system_1'] =
          const ReportFlowPreferences(
            templateId: 't1',
            mode: PresenterModePreference.online,
          );
      bridge.failTemplateSync = true;
      final controller = createController(
        templates: const <CachedTemplate>[],
        entryPolicy: ReportEntryPolicy.smart,
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.value.stage, ReportFlowStage.preparingResources);
      expect(controller.value.templateSync, ReportOperationStatus.failed);
      expect(preferences.valuesBySystem['legacy_system_1']?.templateId, 't1');
    },
  );

  test(
    'scoped catalog absence preserves saved default without global deletion authority',
    () async {
      preferences.valuesBySystem
        ..['legacy_system_1'] = const ReportFlowPreferences(
          templateId: 'removed',
          mode: PresenterModePreference.online,
        )
        ..['legacy_system_2'] = const ReportFlowPreferences(
          templateId: 'other',
          mode: PresenterModePreference.online,
        );
      final controller = createController(entryPolicy: ReportEntryPolicy.smart);
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.value.stage, ReportFlowStage.selectingTemplate);
      expect(bridge.templateSyncCalls, 1);
      expect(
        controller.value.entryFallbackReason,
        ReportEntryFallbackReason.noCompatibleTemplates,
      );
      expect(
        preferences.valuesBySystem['legacy_system_1']?.templateId,
        'removed',
      );
      expect(
        preferences.valuesBySystem['legacy_system_1']?.mode,
        PresenterModePreference.online,
      );
      expect(
        preferences.valuesBySystem['legacy_system_2']?.templateId,
        'other',
      );
      // Sole compatible alternative may be visually preselected as a draft in
      // Template Selection. That must not commit, persist, or auto-open Preview.
      expect(controller.value.selectedTemplateId, 't1');
      expect(controller.value.committedTemplateId, isNull);
      expect(controller.value.presenterLaunch, isNull);
      expect(bridge.prepareCalls, 0);
    },
  );

  test(
    'compatibility mismatch skips saved template without deleting preference',
    () async {
      preferences.valuesBySystem['legacy_system_1'] =
          const ReportFlowPreferences(
            templateId: 't_a4',
            mode: PresenterModePreference.online,
          );
      bridge.templates = <CachedTemplate>[
        _sizedTemplate('t_a4', 'A4'),
        _sizedTemplate('t_80', '80mm'),
      ];
      final controller = ReportFlowControllerImpl(
        features: const BridgeUiFeatures(),
        request: buildTestOpenRequest(
          system: 'legacy_system_1',
          reportType: 'sales_invoice',
          entryPolicy: ReportEntryPolicy.smart,
          compatibility: const TemplateCompatibilityConstraints(
            size: ReportPageSize.thermal80,
          ),
        ),
        runtime: ReportFlowRuntime(
          connection: ReportServerConnection(
            endpoints: ReportServerEndpoints.deployed(
              Uri.parse('https://example.test'),
            ),
            cacheRoot: root,
          ),
          bridgeClient: bridge,
          preferences: preferences,
          filePlatform: _FakeFilePlatform(),
          surfaceBinding: PresenterSurfaceBinding(),
        ),
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(preferences.valuesBySystem['legacy_system_1']?.templateId, 't_a4');
      expect(controller.value.selectedTemplateId, isNot('t_a4'));
    },
  );

  test('entry policy can force Preparation or Template Selection', () async {
    preferences.valuesBySystem['legacy_system_1'] = const ReportFlowPreferences(
      templateId: 't1',
      mode: PresenterModePreference.online,
    );
    final preparation = createController(
      entryPolicy: ReportEntryPolicy.alwaysPrepare,
    );
    await preparation.initialize();
    expect(preparation.value.stage, ReportFlowStage.preparingResources);
    await preparation.dispose();

    final selection = createController(
      entryPolicy: ReportEntryPolicy.alwaysSelectTemplate,
    );
    await selection.initialize();
    expect(selection.value.stage, ReportFlowStage.selectingTemplate);
    await selection.dispose();
  });

  test(
    'offline Preparation synchronizes Presenter before continuing',
    () async {
      bridge.presenterCached = false;
      final controller = createController(
        mode: PresenterModePreference.offline,
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      expect(controller.value.preparationReady, isFalse);

      await controller.continueFromPreparation();

      expect(bridge.presenterSyncCalls, 1);
      expect(controller.value.presenterCached, isTrue);
      expect(controller.value.stage, ReportFlowStage.selectingTemplate);
    },
  );

  test('template synchronization failure stays on Preparation', () async {
    bridge.failTemplateSync = true;
    final controller = createController(templates: const <CachedTemplate>[]);
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.value.stage, ReportFlowStage.preparingResources);
    expect(controller.value.templateSync, ReportOperationStatus.failed);
    expect(controller.value.failure, isNull);
    expect(
      controller.value.templateSyncFailure?.code,
      ReportFlowFailureCode.templateSyncFailed,
    );
  });

  test(
    'template summary errors are surfaced on the template resource',
    () async {
      bridge.templateSyncErrors = const <String>[
        'PUBLISHED_TEMPLATE_INVALID: template t-bad is invalid',
      ];
      final controller = createController(templates: const <CachedTemplate>[]);
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.value.stage, ReportFlowStage.preparingResources);
      expect(controller.value.templateSync, ReportOperationStatus.failed);
      expect(controller.value.failure, isNull);
      expect(
        controller.value.templateSyncFailure?.code,
        ReportFlowFailureCode.templateSyncFailed,
      );
      expect(
        controller.value.templateSyncFailure?.diagnostic,
        contains('PUBLISHED_TEMPLATE_INVALID'),
      );
    },
  );

  test(
    'system-wide template update caches other families without transport failure',
    () async {
      final controller = ReportFlowControllerImpl(
        features: const BridgeUiFeatures(),
        request: buildTestOpenRequest(
          system: 'legacy_system_1',
          reportType: 'sales_invoice',
          entryPolicy: ReportEntryPolicy.alwaysPrepare,
          filter: TemplateSyncFilter(),
        ),
        runtime: ReportFlowRuntime(
          connection: ReportServerConnection(
            endpoints: ReportServerEndpoints.deployed(
              Uri.parse('https://example.test'),
            ),
            cacheRoot: root,
          ),
          bridgeClient: bridge,
          preferences: preferences,
          filePlatform: _FakeFilePlatform(),
          surfaceBinding: PresenterSurfaceBinding(),
        ),
      );
      bridge.templates = const <CachedTemplate>[];
      bridge.templatesAfterSync = <CachedTemplate>[
        _familyTemplate('receipt-only', 'receipt_voucher'),
      ];
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(bridge.templateSyncCalls, 1);
      expect(controller.value.templateSync, ReportOperationStatus.succeeded);
      expect(controller.value.templateCatalogCount, 1);
      expect(controller.value.templates, isEmpty);
      expect(controller.value.templateSyncFailure, isNull);
      expect(
        controller.value.entryFallbackReason,
        ReportEntryFallbackReason.noCompatibleTemplates,
      );
      expect(controller.value.preparationReady, isFalse);
    },
  );

  test(
    'later report family reuses the system-wide cached catalog without another sync',
    () async {
      bridge.templates = const <CachedTemplate>[];
      bridge.templatesAfterSync = <CachedTemplate>[
        _familyTemplate('invoice', 'sales_invoice'),
        _familyTemplate('receipt', 'receipt_voucher'),
      ];

      ReportFlowControllerImpl controllerFor(String reportType) =>
          ReportFlowControllerImpl(
            features: const BridgeUiFeatures(),
            request: buildTestOpenRequest(
              system: 'legacy_system_1',
              reportType: reportType,
              entryPolicy: ReportEntryPolicy.alwaysPrepare,
              filter: TemplateSyncFilter(),
            ),
            runtime: ReportFlowRuntime(
              connection: ReportServerConnection(
                endpoints: ReportServerEndpoints.deployed(
                  Uri.parse('https://example.test'),
                ),
                cacheRoot: root,
              ),
              bridgeClient: bridge,
              preferences: preferences,
              filePlatform: _FakeFilePlatform(),
              surfaceBinding: PresenterSurfaceBinding(),
            ),
          );

      final invoice = controllerFor('sales_invoice');
      addTearDown(invoice.dispose);
      await invoice.initialize();
      expect(bridge.templateSyncCalls, 1);
      expect(invoice.value.templateCatalogCount, 2);
      expect(invoice.value.templates.map((item) => item.id), <String>[
        'invoice',
      ]);

      bridge.templatesAfterSync = null;
      final receipt = controllerFor('receipt_voucher');
      addTearDown(receipt.dispose);
      await receipt.initialize();

      expect(bridge.templateSyncCalls, 1);
      expect(receipt.value.templateCatalogCount, 2);
      expect(receipt.value.templates.map((item) => item.id), <String>[
        'receipt',
      ]);
      expect(receipt.value.templateSync, ReportOperationStatus.succeeded);
    },
  );

  test('selection can return to Preparation without losing choices', () async {
    final controller = createController();
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.continueFromPreparation();
    controller.backToPreparation();

    expect(controller.value.stage, ReportFlowStage.preparingResources);
    expect(controller.value.selectedTemplateId, 't1');
    expect(controller.value.selectedMode, PresenterModePreference.online);
  });

  test('Settings template Cancel discards the pending selection', () async {
    final controller = createController(
      templates: <CachedTemplate>[_template('t1'), _template('t2')],
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.continueFromPreparation();
    controller.selectTemplate('t1');
    await controller.preparePreview();

    controller.editSettings();
    controller.openTemplateSelection(
      origin: TemplateSelectionOrigin.reportSettings,
    );
    controller.selectTemplate('t2');
    expect(controller.value.selectedTemplateId, 't2');
    expect(controller.value.settingsDraft?.templateId, 't1');

    controller.backToPreparation();

    expect(controller.value.stage, ReportFlowStage.editingSettings);
    expect(controller.value.selectedTemplateId, 't1');
    expect(controller.value.settingsDraft?.templateId, 't1');
    expect(preferences.value?.templateId, 't1');
  });

  test('Settings template confirmation updates only the draft', () async {
    final controller = createController(
      templates: <CachedTemplate>[_template('t1'), _template('t2')],
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.continueFromPreparation();
    controller.selectTemplate('t1');
    await controller.preparePreview();

    controller.editSettings();
    controller.openTemplateSelection(
      origin: TemplateSelectionOrigin.reportSettings,
    );
    controller.selectTemplate('t2');
    controller.confirmTemplateSelection();

    expect(controller.value.stage, ReportFlowStage.editingSettings);
    expect(controller.value.settingsDraft?.templateId, 't2');
    expect(preferences.value?.templateId, 't1');
  });

  test(
    'Settings Resource Preparation mode updates the draft and can save',
    () async {
      final controller = createController();
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.continueFromPreparation();
      await controller.preparePreview();

      controller.editSettings();
      controller.openResourcePreparation(
        ResourcePreparationOrigin.reportSettings,
      );
      controller.selectMode(PresenterModePreference.offline);
      controller.returnFromResourcePreparation();

      expect(controller.value.stage, ReportFlowStage.editingSettings);
      expect(
        controller.value.settingsDraft?.mode,
        PresenterModePreference.offline,
      );

      await controller.commitSettings();

      expect(preferences.value?.mode, PresenterModePreference.offline);
      expect(controller.value.stage, ReportFlowStage.previewing);
    },
  );

  test(
    'Settings Cancel restores mode changed in Resource Preparation',
    () async {
      final controller = createController();
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.continueFromPreparation();
      await controller.preparePreview();

      controller.editSettings();
      controller.openResourcePreparation(
        ResourcePreparationOrigin.reportSettings,
      );
      controller.selectMode(PresenterModePreference.offline);
      controller.returnFromResourcePreparation();
      controller.cancelSettings();

      expect(controller.value.stage, ReportFlowStage.previewing);
      expect(controller.value.selectedMode, PresenterModePreference.online);
      expect(preferences.value?.mode, PresenterModePreference.online);
    },
  );

  test('Settings origins return to Settings deterministically', () async {
    final controller = createController();
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.continueFromPreparation();
    await controller.preparePreview();
    controller.editSettings();

    controller.openTemplateSelection(
      origin: TemplateSelectionOrigin.reportSettings,
    );
    controller.backToPreparation();
    expect(controller.value.stage, ReportFlowStage.editingSettings);

    controller.openResourcePreparation(
      ResourcePreparationOrigin.reportSettings,
    );
    controller.returnFromResourcePreparation();
    expect(controller.value.stage, ReportFlowStage.editingSettings);
  });

  test(
    'duplicate Preview preparation shares one operation and blocks close',
    () async {
      final controller = createController();
      addTearDown(controller.dispose);
      bridge.prepareBarrier = Completer<void>();

      await controller.initialize();
      await controller.continueFromPreparation();
      final first = controller.preparePreview();
      final second = controller.preparePreview();

      // The derived controller may wrap the shared in-flight Future while
      // still delegating to one underlying Preview preparation operation.
      expect(bridge.prepareCalls, 1);
      await expectLater(
        controller.close(),
        throwsA(
          isA<ReportFlowFailure>().having(
            (failure) => failure.code,
            'code',
            ReportFlowFailureCode.operationInProgress,
          ),
        ),
      );

      bridge.prepareBarrier!.complete();
      await Future.wait<void>(<Future<void>>[first, second]);

      expect(controller.value.presenterLaunch, isNotNull);
      expect(bridge.prepareCalls, 1);
    },
  );

  test(
    'dispose waits for in-flight Preview preparation and prevents persistence',
    () async {
      final controller = createController();
      bridge.prepareBarrier = Completer<void>();

      await controller.initialize();
      await controller.continueFromPreparation();
      final preview = controller.preparePreview();
      final disposal = controller.dispose();
      bridge.prepareBarrier!.complete();

      await Future.wait<void>(<Future<void>>[preview, disposal]);

      expect(preferences.value, isNull);
      expect(controller.value.presenterLaunch, isNull);
      expect(bridge.stopCalls, greaterThanOrEqualTo(1));
    },
  );

  test('close is idempotent and stops the session once', () async {
    final controller = createController();
    addTearDown(controller.dispose);
    await controller.initialize();

    final first = controller.close();
    final second = controller.close();

    expect(identical(first, second), isTrue);
    final results = await Future.wait<ReportResult>(<Future<ReportResult>>[
      first,
      second,
    ]);
    expect(results, everyElement(isA<ReportCancelled>()));
    expect(bridge.stopCalls, 1);
  });

  test(
    'WebView progress does not enable export before Presenter ready',
    () async {
      final controller = createController();
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.continueFromPreparation();
      await controller.preparePreview();

      expect(controller.value.presenterLaunch, isNotNull);
      expect(controller.value.renderStatus, PresenterRenderStatus.loading);
      expect(controller.value.exportReady, isFalse);

      controller.presenterLoadProgress(1);
      expect(controller.value.webViewLoadProgress, 1);
      expect(controller.value.presenterDownloadProgress, 1);
      expect(controller.value.exportReady, isFalse);

      controller.presenterProtocolDetected(BridgeContract.payloadVersion);
      controller.completePresenterRender(
        sessionId: controller.value.presenterLaunch!.sessionId,
      );
      expect(controller.value.renderStatus, PresenterRenderStatus.ready);
      expect(controller.value.exportReady, isTrue);
    },
  );

  test(
    'legacy fallback becomes usable immediately when the visible page loads',
    () async {
      final controller = createController(
        features: const BridgeUiFeatures(allowLegacyPresenterFallback: true),
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.continueFromPreparation();
      await controller.preparePreview();
      controller.presenterLoadStarted();
      controller.presenterLoadProgress(1);

      expect(controller.value.stage, ReportFlowStage.previewing);
      expect(controller.value.previewLoad, ReportOperationStatus.succeeded);
      expect(controller.value.renderStatus, PresenterRenderStatus.ready);
      expect(controller.value.webViewLoadProgress, 1);
      expect(controller.value.presenterProtocolReady, isFalse);
      expect(controller.value.failure, isNull);
      expect(controller.value.exportReady, isFalse);
    },
  );

  test(
    'late Preview callbacks cannot relaunch Preview over resource settings',
    () async {
      final controller = createController(
        renderTimeout: const Duration(milliseconds: 20),
        features: const BridgeUiFeatures(allowLegacyPresenterFallback: true),
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.continueFromPreparation();
      await controller.preparePreview();
      final sessionId = controller.value.presenterLaunch!.sessionId;
      controller.presenterLoadStarted();

      controller.editSettings();
      controller.openResourcePreparation(
        ResourcePreparationOrigin.reportSettings,
      );

      controller.presenterLoadStarted();
      controller.presenterLoadProgress(1);
      controller.presenterProtocolDetected(BridgeContract.payloadVersion);
      controller.completePresenterRender(sessionId: sessionId);
      controller.failPresenterRender(
        'late callback from disposed Preview',
        sessionId: sessionId,
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(controller.value.stage, ReportFlowStage.preparingResources);
      expect(
        controller.value.resourceOrigin,
        ResourcePreparationOrigin.reportSettings,
      );
      expect(controller.value.webViewLoadProgress, 0);
      expect(controller.value.failure, isNull);
    },
  );

  test('structured Presenter failure survives into flow state', () async {
    final controller = createController();
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.continueFromPreparation();
    await controller.preparePreview();
    final sessionId = controller.value.presenterLaunch!.sessionId;
    controller.presenterLoadStarted();
    controller.presenterProtocolDetected(BridgeContract.payloadVersion);

    controller.failPresenterRenderFailure(
      const ReportFlowFailure(
        code: ReportFlowFailureCode.renderFailed,
        diagnostic: 'Text content is invalid.',
        technicalCode: 'invalidElement',
        technicalCategory: 'document',
        technicalPath: r'elements[2].content',
        details: <String, Object?>{'source': 'runtimeFile'},
      ),
      sessionId: sessionId,
    );

    expect(controller.value.stage, ReportFlowStage.failed);
    expect(controller.value.failure?.code, ReportFlowFailureCode.renderFailed);
    expect(controller.value.failure?.diagnostic, 'Text content is invalid.');
    expect(controller.value.failure?.technicalCode, 'invalidElement');
    expect(controller.value.failure?.technicalCategory, 'document');
    expect(controller.value.failure?.technicalPath, r'elements[2].content');
    expect(controller.value.failure?.details['source'], 'runtimeFile');
  });

  test(
    'render timeout reports incompatible Presenter without protocol',
    () async {
      final controller = createController(
        renderTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.continueFromPreparation();
      await controller.preparePreview();
      controller.presenterLoadStarted();

      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(controller.value.stage, ReportFlowStage.failed);
      expect(
        controller.value.failure?.code,
        ReportFlowFailureCode.presenterIncompatible,
      );
      expect(controller.value.exportReady, isFalse);
    },
  );

  test('render timeout is distinct after protocol acknowledgement', () async {
    final controller = createController(
      renderTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.continueFromPreparation();
    await controller.preparePreview();
    controller.presenterLoadStarted();
    controller.presenterProtocolDetected(BridgeContract.payloadVersion);

    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(controller.value.stage, ReportFlowStage.failed);
    expect(
      controller.value.failure?.code,
      ReportFlowFailureCode.renderTimedOut,
    );
    expect(controller.value.exportReady, isFalse);
  });

  test('failed session replacement preserves the active launch', () async {
    final controller = createController(
      templates: <CachedTemplate>[_template('t1'), _template('t2')],
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.continueFromPreparation();
    controller.selectTemplate('t1');
    await controller.preparePreview();
    expect(controller.value.presenterLaunch?.sessionId, 'session-1');

    controller.editSettings();
    controller.selectTemplate('t2');
    bridge.failPrepare = true;
    await controller.commitSettings();

    expect(controller.value.stage, ReportFlowStage.editingSettings);
    expect(controller.value.presenterLaunch?.sessionId, 'session-1');
    expect(
      controller.value.failure?.code,
      ReportFlowFailureCode.previewPreparationFailed,
    );
  });

  test('Settings Cancel preserves Preview and stored preferences', () async {
    final controller = createController(
      templates: <CachedTemplate>[_template('t1'), _template('t2')],
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.continueFromPreparation();
    controller.selectTemplate('t1');
    await controller.preparePreview();
    final launch = controller.value.presenterLaunch;
    final stored = preferences.value;

    controller.editSettings();
    controller.selectMode(PresenterModePreference.offline);
    controller.cancelSettings();

    expect(controller.value.stage, ReportFlowStage.previewing);
    expect(controller.value.presenterLaunch, same(launch));
    expect(preferences.value?.templateId, stored?.templateId);
    expect(preferences.value?.mode, stored?.mode);
  });

  test('Settings template Cancel returns to the active Preview', () async {
    final controller = createController(
      templates: <CachedTemplate>[_template('t1'), _template('t2')],
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.continueFromPreparation();
    controller.selectTemplate('t1');
    await controller.preparePreview();
    final launch = controller.value.presenterLaunch;

    controller.editSettings();
    controller.selectMode(PresenterModePreference.offline);
    controller.openTemplateSelection(
      origin: TemplateSelectionOrigin.reportSettings,
    );
    controller.selectTemplate('t2');
    controller.cancelSettings();

    expect(controller.value.stage, ReportFlowStage.previewing);
    expect(controller.value.selectedTemplateId, 't1');
    expect(controller.value.selectedMode, PresenterModePreference.online);
    expect(controller.value.settingsDraft, isNull);
    expect(controller.value.presenterLaunch, same(launch));
  });

  test('Settings Save persists only after replacement preparation', () async {
    final controller = createController(
      templates: <CachedTemplate>[_template('t1'), _template('t2')],
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.continueFromPreparation();
    controller.selectTemplate('t1');
    await controller.preparePreview();

    controller.editSettings();
    controller.openTemplateSelection(
      origin: TemplateSelectionOrigin.reportSettings,
    );
    controller.selectTemplate('t2');
    controller.confirmTemplateSelection();
    bridge.prepareBarrier = Completer<void>();
    final replacement = controller.commitSettings();

    expect(preferences.value?.templateId, 't1');
    expect(controller.value.presenterLaunch?.sessionId, 'session-1');
    bridge.prepareBarrier!.complete();
    await replacement;

    expect(preferences.value?.templateId, 't2');
    expect(controller.value.presenterLaunch?.sessionId, 'session-2');
    expect(bridge.replacementCommitCalls, 1);
    expect(bridge.replacementDiscardCalls, 0);
  });

  test('replacement commit failure rolls preferences back', () async {
    final controller = createController(
      templates: <CachedTemplate>[_template('t1'), _template('t2')],
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.continueFromPreparation();
    controller.selectTemplate('t1');
    await controller.preparePreview();

    controller.editSettings();
    controller.openTemplateSelection(
      origin: TemplateSelectionOrigin.reportSettings,
    );
    controller.selectTemplate('t2');
    controller.confirmTemplateSelection();
    bridge.failReplacementCommit = true;

    await controller.commitSettings();

    expect(controller.value.stage, ReportFlowStage.editingSettings);
    expect(controller.value.presenterLaunch?.sessionId, 'session-1');
    expect(preferences.value?.templateId, 't1');
    expect(preferences.value?.mode, PresenterModePreference.online);
    expect(bridge.replacementCommitCalls, 1);
    expect(bridge.replacementDiscardCalls, 1);
    expect(
      controller.value.failure?.code,
      ReportFlowFailureCode.previewPreparationFailed,
    );
  });

  test('replacement persistence failure discards candidate session', () async {
    final controller = createController(
      templates: <CachedTemplate>[_template('t1'), _template('t2')],
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.continueFromPreparation();
    controller.selectTemplate('t1');
    await controller.preparePreview();

    controller.editSettings();
    controller.openTemplateSelection(
      origin: TemplateSelectionOrigin.reportSettings,
    );
    controller.selectTemplate('t2');
    controller.confirmTemplateSelection();
    preferences.failSave = true;
    await controller.commitSettings();

    expect(controller.value.stage, ReportFlowStage.editingSettings);
    expect(controller.value.presenterLaunch?.sessionId, 'session-1');
    expect(preferences.value?.templateId, 't1');
    expect(bridge.replacementCommitCalls, 0);
    expect(bridge.replacementDiscardCalls, 1);
    expect(bridge.stopCalls, 0);
    expect(
      controller.value.failure?.code,
      ReportFlowFailureCode.persistenceFailed,
    );
  });

  test(
    'persistence failure stops the prepared session and clears launch',
    () async {
      final controller = createController();
      addTearDown(controller.dispose);
      preferences.failSave = true;

      await controller.initialize();
      await controller.continueFromPreparation();
      await controller.preparePreview();

      expect(bridge.stopCalls, 1);
      expect(controller.value.presenterLaunch, isNull);
      expect(
        controller.value.failure?.code,
        ReportFlowFailureCode.persistenceFailed,
      );
    },
  );

  test(
    'close distinguishes cancellation from a completed Preview session',
    () async {
      final cancelledController = createController();
      await cancelledController.initialize();
      final cancelled = await cancelledController.close();
      await cancelledController.dispose();
      expect(cancelled, isA<ReportCancelled>());

      final closedController = createController();
      await closedController.initialize();
      await closedController.continueFromPreparation();
      await closedController.preparePreview();
      final closed = await closedController.close();
      await closedController.dispose();
      expect(closed, isA<ReportClosed>());
    },
  );

  test('cancelled Save does not emit export completion', () async {
    final surface = PresenterSurfaceBinding(
      exportTransport: PresenterWebExportTransport(
        correlationIdFactory: () => 'save-cancel',
      ),
    );
    final filePlatform = _FakeFilePlatform(saveAccepted: false);
    final controller = createController(
      filePlatform: filePlatform,
      surfaceBinding: surface,
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.continueFromPreparation();
    await controller.preparePreview();
    final launch = controller.value.presenterLaunch!;
    surface.attach(
      sessionId: launch.sessionId,
      templateName: controller.value.selectedTemplate!.templateName,
      evaluateJavaScript: (_) async {
        surface.acceptMessage(<String, dynamic>{
          'channel': bridgeWebMessageChannel,
          'method': BridgeWebMethods.exportPdf,
          'correlationId': 'save-cancel',
          'type': 'result',
          'ok': true,
          'base64': base64Encode(<int>[1, 2, 3]),
          'filename': 'bridge.pdf',
          'byteLength': 3,
        });
        return null;
      },
      reload: () async {},
      onLifecycle: (_) {},
    );
    controller.presenterProtocolDetected(BridgeContract.payloadVersion);
    controller.completePresenterRender(sessionId: launch.sessionId);
    final events = <ReportFlowEvent>[];
    final subscription = controller.events.listen(events.add);
    addTearDown(subscription.cancel);

    await controller.savePdf();

    expect(filePlatform.saveCalls, 1);
    expect(
      events.where(
        (event) => event.type == ReportFlowEventType.exportCancelled,
      ),
      hasLength(1),
    );
    expect(
      events.where(
        (event) => event.type == ReportFlowEventType.exportCompleted,
      ),
      isEmpty,
    );
    expect(controller.value.exportAction, isNull);
    expect(controller.value.failure, isNull);
  });

  test(
    'development support shares a ZIP through the injected platform',
    () async {
      final sharePlatform = _FakeSupportSharePlatform();
      final controller = createController(supportSharePlatform: sharePlatform);
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.shareDevelopmentSupportPackage();

      expect(sharePlatform.calls, 1);
      expect(sharePlatform.lastBytes, isNotEmpty);
      expect(sharePlatform.lastFilename, startsWith('urb_report_issue_'));
      expect(sharePlatform.lastFilename, endsWith('.zip'));
      expect(controller.value.supportShare, ReportOperationStatus.succeeded);
    },
  );

  test(
    'Host policy can disable development support even though default is true',
    () async {
      final sharePlatform = _FakeSupportSharePlatform();
      final controller = createController(
        supportSharePlatform: sharePlatform,
        features: const BridgeUiFeatures(showDevelopmentSupport: false),
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      await expectLater(
        controller.shareDevelopmentSupportPackage(),
        throwsA(
          isA<ReportFlowFailure>().having(
            (failure) => failure.code,
            'code',
            ReportFlowFailureCode.developmentSupportFailed,
          ),
        ),
      );
      expect(sharePlatform.calls, 0);
    },
  );

  test(
    'cache maintenance clears only caches and preserves saved preferences',
    () async {
      final controller = createController();
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.continueFromPreparation();
      await controller.preparePreview();
      controller.editSettings();
      expect(controller.value.stage, ReportFlowStage.editingSettings);

      preferences.valuesBySystem['legacy_system_1'] =
          const ReportFlowPreferences(
            templateId: 't1',
            mode: PresenterModePreference.online,
          );

      await controller.clearCachedResources();

      expect(bridge.clearTemplateCacheCalls, 1);
      expect(bridge.clearPresenterCacheCalls, 1);
      expect(preferences.valuesBySystem['legacy_system_1']?.templateId, 't1');
      expect(
        preferences.valuesBySystem['legacy_system_1']?.mode,
        PresenterModePreference.online,
      );
      expect(controller.value.stage, ReportFlowStage.preparingResources);
      expect(
        controller.value.resourceOrigin,
        ResourcePreparationOrigin.reportSettings,
      );
      expect(controller.value.templates, isEmpty);
      expect(controller.value.presenterCached, isFalse);
      expect(controller.value.presenterLaunch, isNull);
      expect(
        controller.value.cacheMaintenance,
        ReportOperationStatus.succeeded,
      );
    },
  );

  test('failed Preview can select a replacement template directly', () async {
    final controller = createController(
      templates: <CachedTemplate>[_template('t1'), _template('t2')],
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.continueFromPreparation();
    await controller.preparePreview();
    expect(controller.value.committedTemplateId, 't1');

    controller.failPresenterRender('Unable to render text element.');
    expect(controller.value.stage, ReportFlowStage.failed);

    controller.openTemplateSelection(
      origin: TemplateSelectionOrigin.previewRecovery,
    );
    expect(controller.value.failure, isNotNull);
    controller.selectTemplate('t2');
    await controller.preparePreview();

    expect(controller.value.stage, ReportFlowStage.previewing);
    expect(controller.value.committedTemplateId, 't2');
    expect(controller.value.failure, isNull);
  });

  test(
    'cancelling Preview recovery template selection restores failed report',
    () async {
      final controller = createController(
        templates: <CachedTemplate>[_template('t1'), _template('t2')],
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.continueFromPreparation();
      await controller.preparePreview();
      controller.failPresenterRender('render failed');
      final failure = controller.value.failure;

      controller.openTemplateSelection(
        origin: TemplateSelectionOrigin.previewRecovery,
      );
      controller.selectTemplate('t2');
      controller.backToPreparation();

      expect(controller.value.stage, ReportFlowStage.failed);
      expect(controller.value.selectedTemplateId, 't1');
      expect(controller.value.failure, same(failure));
    },
  );

  test('cleanup failure is returned as a non-blocking warning', () async {
    final controller = createController();
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.continueFromPreparation();
    await controller.preparePreview();
    bridge.failStop = true;

    final result = await controller.close();

    expect(result, isA<ReportClosed>());
    expect(
      (result as ReportClosed).cleanupWarning?.code,
      ReportFlowFailureCode.cleanupFailed,
    );
    expect(controller.value.stage, ReportFlowStage.closed);
  });
}

CachedTemplate _template(String id) => CachedTemplate(
  id: id,
  type: 'sales_invoice',
  systemId: 1,
  name: 'Template $id',
  version: '1.0.0',
  document: const <String, dynamic>{
    'schemaVersion': '1.0.0',
    'meta': <String, dynamic>{'name': 'Invoice', 'family': 'sales_invoice'},
    'page': <String, dynamic>{
      'layout': 'Pages',
      'size': 'A4',
      'unit': 'mm',
      'orientation': 'portrait',
      'language': 'ar',
      'direction': 'rtl',
      'width': 210,
      'height': 297,
    },
    'styleTokens': <String, dynamic>{},
    'assets': <dynamic>[],
    'layers': <dynamic>[],
    'elements': <dynamic>[],
  },
);

CachedTemplate _familyTemplate(String id, String family) => CachedTemplate(
  id: id,
  type: family,
  systemId: 1,
  name: 'Template $id',
  version: '1.0.0',
  document: <String, dynamic>{
    'schemaVersion': '1.0.0',
    'meta': <String, dynamic>{'name': 'Template', 'family': family},
    'page': const <String, dynamic>{
      'layout': 'Pages',
      'size': 'A4',
      'unit': 'mm',
      'orientation': 'portrait',
      'language': 'ar',
      'direction': 'rtl',
      'width': 210,
      'height': 297,
    },
    'styleTokens': const <String, dynamic>{},
    'assets': const <dynamic>[],
    'layers': const <dynamic>[],
    'elements': const <dynamic>[],
  },
);

CachedTemplate _sizedTemplate(String id, String size) {
  final thermal = size == '80mm' || size == '58mm';
  final width = switch (size) {
    '80mm' => 80.0,
    '58mm' => 58.0,
    'A5' => 148.0,
    'Letter' => 215.9,
    _ => 210.0,
  };
  final height = switch (size) {
    '80mm' => 220.0,
    '58mm' => 180.0,
    'A5' => 210.0,
    'Letter' => 279.4,
    _ => 297.0,
  };
  return CachedTemplate(
    id: id,
    type: 'sales_invoice',
    systemId: 1,
    name: 'Template $id',
    version: '1.0.0',
    document: <String, dynamic>{
      'schemaVersion': '1.0.0',
      'meta': const <String, dynamic>{
        'name': 'Invoice',
        'family': 'sales_invoice',
      },
      'page': <String, dynamic>{
        'layout': thermal ? 'Thermal' : 'Pages',
        'size': size,
        'unit': 'mm',
        'orientation': 'portrait',
        'language': 'ar',
        'direction': 'rtl',
        'width': width,
        'height': height,
      },
      'styleTokens': const <String, dynamic>{},
      'assets': const <dynamic>[],
      'layers': const <dynamic>[],
      'elements': const <dynamic>[],
    },
  );
}

class _FakeBridgeClient extends ReportingBridgeClient {
  _FakeBridgeClient(Directory root)
    : super(
        apiBaseUrl: Uri.parse('https://example.test/UltimateReport/backend/'),
        presenterEntryUrl: Uri.parse(
          'https://example.test/UltimateReport/apps/presenter/index.html',
        ),
        bridgeRoot: root,
      );

  List<CachedTemplate> templates = <CachedTemplate>[];
  List<CachedTemplate>? templatesAfterSync;
  bool failPrepare = false;
  bool failStop = false;
  bool failTemplateSync = false;
  bool failPresenterSync = false;
  List<String> templateSyncErrors = const <String>[];
  bool failReplacementCommit = false;
  bool presenterCached = true;
  Completer<void>? prepareBarrier;
  int prepareCalls = 0;
  int replacementCommitCalls = 0;
  int replacementDiscardCalls = 0;
  int stopCalls = 0;
  int templateSyncCalls = 0;
  int presenterSyncCalls = 0;
  int clearTemplateCacheCalls = 0;
  int clearPresenterCacheCalls = 0;

  @override
  Future<List<CachedTemplate>> listTemplates({
    String? systemCode,
    int? systemId,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async => templates
      .where((value) => systemId == null || value.systemId == systemId)
      .toList();

  @override
  Future<TemplateSyncSummary> syncTemplates({
    String? systemCode,
    int? systemId,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    templateSyncCalls += 1;
    if (failTemplateSync) throw StateError('template sync failed');
    final synchronized = templatesAfterSync;
    if (synchronized != null) templates = synchronized;
    return TemplateSyncSummary(
      syncedCount: templates.length,
      listCount: templates.length,
      errors: templateSyncErrors,
    );
  }

  @override
  Future<PresenterCacheManifest> syncPresenter({
    void Function(double progress)? onProgress,
  }) async {
    presenterSyncCalls += 1;
    if (failPresenterSync) throw StateError('presenter sync failed');
    onProgress?.call(0.5);
    onProgress?.call(1);
    presenterCached = true;
    return PresenterCacheManifest(
      bundleVersion: '1.0.0',
      devVersion: 1,
      rootPath: bridgeRoot.path,
      presenterVersion: '1.0.0',
    );
  }

  @override
  Future<void> clearTemplateCache() async {
    clearTemplateCacheCalls += 1;
  }

  @override
  Future<void> clearPresenterCache() async {
    clearPresenterCacheCalls += 1;
    presenterCached = false;
  }

  @override
  Future<PresenterSessionLaunch> prepareSession(
    PresenterSessionRequest request,
  ) => _prepareFakeSession();

  @override
  Future<PresenterSessionLaunch> prepareReplacementSession(
    PresenterSessionRequest request,
  ) => _prepareFakeSession();

  Future<PresenterSessionLaunch> _prepareFakeSession() async {
    prepareCalls += 1;
    await prepareBarrier?.future;
    if (failPrepare) throw StateError('replacement failed');
    return PresenterSessionLaunch(
      presenterUrl: 'https://presenter.test/session-$prepareCalls',
      sessionId: 'session-$prepareCalls',
      presenterVersion: '1.0.0',
      presenterDevVersion: 1,
    );
  }

  @override
  Future<void> commitReplacementSession() async {
    replacementCommitCalls += 1;
    if (failReplacementCommit) {
      throw StateError('replacement commit failed');
    }
  }

  @override
  Future<void> discardReplacementSession() async {
    replacementDiscardCalls += 1;
  }

  @override
  Future<ReportingBridgeStatus> getStatus() async => ReportingBridgeStatus(
    apiBaseUrl: apiBaseUrl.toString(),
    presenterCached: presenterCached,
    templateCount: templates.length,
  );

  @override
  Future<void> stopSession() async {
    stopCalls += 1;
    if (failStop) throw StateError('cleanup failed');
  }

  @override
  Future<void> dispose() async {}
}

class _FakePreferenceStore implements ReportFlowPreferenceStore {
  final Map<String, ReportFlowPreferences> valuesBySystem =
      <String, ReportFlowPreferences>{};
  bool failSave = false;

  ReportFlowPreferences? get value => valuesBySystem['legacy_system_1'];
  set value(ReportFlowPreferences? next) {
    if (next == null) {
      valuesBySystem.remove('legacy_system_1');
    } else {
      valuesBySystem['legacy_system_1'] = next;
    }
  }

  @override
  Future<ReportFlowPreferences?> load(ReportPreferenceScope scope) async =>
      valuesBySystem[scope.effectiveSystem];

  @override
  Future<void> remove(ReportPreferenceScope scope) async {
    valuesBySystem.remove(scope.effectiveSystem);
  }

  @override
  Future<void> removeSelectedTemplate(ReportPreferenceScope scope) async {
    final existing = valuesBySystem[scope.effectiveSystem];
    if (existing == null) return;
    valuesBySystem[scope.effectiveSystem] = ReportFlowPreferences(
      templateId: null,
      mode: existing.mode,
    );
  }

  @override
  Future<void> save(
    ReportPreferenceScope scope,
    ReportFlowPreferences preferences,
  ) async {
    if (failSave) throw StateError('save failed');
    valuesBySystem[scope.effectiveSystem] = preferences;
  }
}

class _FakeFilePlatform implements ReportFilePlatform {
  _FakeFilePlatform({this.saveAccepted = true});

  final bool saveAccepted;
  int saveCalls = 0;

  @override
  Future<bool> savePdf(Uint8List bytes, String filename) async {
    saveCalls += 1;
    return saveAccepted;
  }

  @override
  Future<void> sharePdf(Uint8List bytes, String filename) async {}
}

class _FakeSupportSharePlatform implements ReportSupportSharePlatform {
  int calls = 0;
  Uint8List lastBytes = Uint8List(0);
  String? lastFilename;
  Rect? lastOrigin;

  @override
  Future<void> shareArchive(
    Uint8List bytes,
    String filename, {
    Rect? sharePositionOrigin,
  }) async {
    calls += 1;
    lastBytes = Uint8List.fromList(bytes);
    lastFilename = filename;
    lastOrigin = sharePositionOrigin;
  }
}
