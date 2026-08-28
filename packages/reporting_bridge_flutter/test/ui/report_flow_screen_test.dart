import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import '../test_open_request.dart';

void main() {
  testWidgets('close button cleans up, pops once, and returns the result', (
    WidgetTester tester,
  ) async {
    final controller = _FakeController(_preparationState());
    ReportResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<ReportResult>(
                MaterialPageRoute<ReportResult>(
                  builder: (_) => ReportFlowScreen(
                    controller: controller,
                    ui: const BridgeUiConfig.inheritHost(),
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(controller.closeCalls, 1);
    expect(result, isA<ReportCancelled>());
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('system Back uses the same cleanup path', (
    WidgetTester tester,
  ) async {
    final controller = _FakeController(_preparationState());
    await _pumpFlow(tester, controller);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(controller.closeCalls, 1);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('system Back is blocked while an export is active', (
    WidgetTester tester,
  ) async {
    final controller = _FakeController(
      _selectionState().copyWith(exportAction: ReportExportAction.save),
    );
    await _pumpFlow(tester, controller);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(controller.closeCalls, 0);
    expect(find.text('Report setup'), findsOneWidget);
  });

  testWidgets('Preparation exposes both resources and continues to selection', (
    WidgetTester tester,
  ) async {
    final controller = _FakeController(_preparationState());
    await _pumpFlow(tester, controller);

    expect(find.text('Step 1 of 2'), findsOneWidget);
    expect(find.text('templates'), findsOneWidget);
    final templateCard = find
        .ancestor(of: find.text('templates'), matching: find.byType(Card))
        .first;
    expect(
      find.descendant(of: templateCard, matching: find.text('Update')),
      findsOneWidget,
    );
    final resourcesScrollable = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Presenter', skipOffstage: false),
      80,
      scrollable: resourcesScrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Presenter'), findsOneWidget);
    final presenterCard = find
        .ancestor(of: find.text('Presenter'), matching: find.byType(Card))
        .first;
    expect(
      find.descendant(of: presenterCard, matching: find.text('Update')),
      findsOneWidget,
    );
    expect(find.text('Synchronize templates'), findsNothing);
    expect(find.text('Download Presenter'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();

    expect(controller.continueCalls, 1);
    expect(find.text('Step 2 of 2'), findsOneWidget);
  });

  testWidgets('system Back from selection returns to Preparation', (
    WidgetTester tester,
  ) async {
    final controller = _FakeController(_selectionState());
    await _pumpFlow(tester, controller);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(controller.backCalls, 1);
    expect(controller.closeCalls, 0);
    expect(find.text('Step 1 of 2'), findsOneWidget);
  });

  testWidgets('Preparation uses an offline switch with localized help', (
    WidgetTester tester,
  ) async {
    final controller = _FakeController(_preparationState());
    await _pumpFlow(tester, controller);

    expect(find.text('Use Presenter offline'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SwitchListTile),
        matching: find.textContaining('Online mode uses Presenter'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();

    expect(controller.value.selectedMode, PresenterModePreference.offline);
    expect(
      find.descendant(
        of: find.byType(SwitchListTile),
        matching: find.textContaining(
          'Offline mode requires a complete local Presenter',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Preparation disables offline mode until Presenter is cached', (
    WidgetTester tester,
  ) async {
    final controller = _FakeController(
      _preparationState().copyWith(
        presenterCached: false,
        presenterSync: ReportOperationStatus.idle,
        presenterDownloadProgress: 0,
      ),
    );
    await _pumpFlow(tester, controller);

    final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(tile.onChanged, isNull);
    expect(
      find.text('Update Presenter before enabling offline mode.'),
      findsOneWidget,
    );
  });

  testWidgets('offline Preparation blocks Continue until Presenter is ready', (
    WidgetTester tester,
  ) async {
    final controller = _FakeController(
      _preparationState().copyWith(
        selectedMode: PresenterModePreference.offline,
        presenterCached: false,
        presenterSync: ReportOperationStatus.idle,
      ),
    );
    await _pumpFlow(tester, controller);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Update required'), findsOneWidget);
  });

  testWidgets('busy Preparation disables Continue without button progress', (
    WidgetTester tester,
  ) async {
    final controller = _FakeController(
      _preparationState().copyWith(templateSync: ReportOperationStatus.running),
    );
    await _pumpFlow(tester, controller);

    final buttonFinder = find.widgetWithText(FilledButton, 'Continue');
    final button = tester.widget<FilledButton>(buttonFinder);
    expect(button.onPressed, isNull);
    expect(
      find.descendant(
        of: buttonFinder,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
  });

  testWidgets('Preparation remains responsive at 320 dp and 200% text', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final controller = _FakeController(_preparationState());
    await _pumpFlow(tester, controller, textScale: 2);

    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.text('Use Presenter offline'), findsOneWidget);
    expect(find.text('Step 1 of 2'), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Preparation localizes copy and direction for Arabic', (
    WidgetTester tester,
  ) async {
    final controller = _FakeController(
      _preparationState(),
      localeOverride: 'ar',
    );
    await _pumpFlow(tester, controller);

    expect(find.text('الخطوة ١ من ٢'), findsOneWidget);
    expect(find.text('القوالب'), findsOneWidget);
    expect(find.text('استخدام التقارير دون اتصال'), findsOneWidget);
    final directionality = tester.widget<Directionality>(
      find
          .ancestor(
            of: find.text('الخطوة ١ من ٢'),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(directionality.textDirection, TextDirection.rtl);
  });

  testWidgets('Preparation describes system-wide template updates by default', (
    WidgetTester tester,
  ) async {
    final controller = _FakeController(
      _preparationState().copyWith(templateCatalogCount: 12),
      filterOverride: TemplateSyncFilter(),
    );
    await _pumpFlow(tester, controller);

    expect(
      find.text('Updates all report templates and stores them locally.'),
      findsOneWidget,
    );
    expect(
      find.text('Cached for system: 12 · Compatible with current report: 1'),
      findsOneWidget,
    );
  });

  testWidgets('Preparation describes an explicit Host report-family subset', (
    WidgetTester tester,
  ) async {
    final controller = _FakeController(
      _preparationState(),
      filterOverride: TemplateSyncFilter(
        reportTypes: const <String>['sales_invoice', 'sales_return'],
      ),
    );
    await _pumpFlow(tester, controller);

    expect(find.text('Updates templates.'), findsOneWidget);
  });

  testWidgets(
    'Preparation marks any explicit query dimension as a limited update scope',
    (WidgetTester tester) async {
      final controller = _FakeController(
        _preparationState().copyWith(templateCatalogCount: 7),
        filterOverride: TemplateSyncFilter(sizes: const <String>['A4']),
      );
      await _pumpFlow(tester, controller);

      expect(find.text('Updates templates.'), findsOneWidget);
      expect(
        find.text('Cached for this app: 7 · Compatible with current report: 1'),
        findsOneWidget,
      );
    },
  );

  testWidgets('system catalog can be ready while current report has no match', (
    WidgetTester tester,
  ) async {
    final controller = _FakeController(
      _preparationState().copyWith(
        templates: const <CachedTemplate>[],
        templateCatalogCount: 12,
        templateSync: ReportOperationStatus.succeeded,
      ),
      filterOverride: TemplateSyncFilter(),
    );
    await _pumpFlow(tester, controller);

    expect(
      find.text('Cached for system: 12 · Compatible with current report: 0'),
      findsOneWidget,
    );
    final templateCard = find
        .ancestor(of: find.text('templates'), matching: find.byType(Card))
        .first;
    expect(
      find.descendant(of: templateCard, matching: find.text('Ready')),
      findsOneWidget,
    );

    final resourcesScrollable = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Presenter', skipOffstage: false),
      80,
      scrollable: resourcesScrollable,
    );
    await tester.pumpAndSettle();
    final presenterCard = find
        .ancestor(of: find.text('Presenter'), matching: find.byType(Card))
        .first;
    expect(
      find.descendant(of: presenterCard, matching: find.text('Ready')),
      findsOneWidget,
    );
    final continueButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(continueButton.onPressed, isNull);
  });

  testWidgets('template resource error expands and collapses inline', (
    WidgetTester tester,
  ) async {
    final controller = _FakeController(
      _preparationState().copyWith(
        templateSync: ReportOperationStatus.failed,
        templateSyncFailure: const ReportFlowFailure(
          code: ReportFlowFailureCode.templateSyncFailed,
          diagnostic: 'Template endpoint returned 503.',
          technicalCode: 'HTTP_503',
        ),
      ),
    );
    await _pumpFlow(tester, controller);

    expect(find.text('Step 1 of 2'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Template update failed.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('templates-resource-error-more')),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('HTTP_503'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('templates-resource-error-more')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Code :'), findsOneWidget);
    expect(find.text('Message :'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == 'HTTP_503',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.data?.contains('Template endpoint returned 503.') == true,
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('templates-resource-error-less')),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
    final technicalCode = tester.widget<SelectableText>(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == 'HTTP_503',
      ),
    );
    expect(technicalCode.textDirection, TextDirection.ltr);

    await tester.tap(
      find.byKey(const ValueKey<String>('templates-resource-error-less')),
    );
    await tester.pumpAndSettle();
    expect(find.text('HTTP_503'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('templates-resource-error-more')),
      findsOneWidget,
    );
  });

  testWidgets(
    'resource error expansion resets when a new failure replaces it',
    (WidgetTester tester) async {
      final controller = _FakeController(
        _preparationState().copyWith(
          templateSync: ReportOperationStatus.failed,
          templateSyncFailure: const ReportFlowFailure(
            code: ReportFlowFailureCode.templateSyncFailed,
            diagnostic: 'First failure.',
            technicalCode: 'FIRST',
          ),
        ),
      );
      await _pumpFlow(tester, controller);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('templates-resource-error-more')),
      );
      await tester.pumpAndSettle();
      expect(find.text('FIRST'), findsOneWidget);

      controller.setState(
        controller.value.copyWith(
          templateSyncFailure: const ReportFlowFailure(
            code: ReportFlowFailureCode.templateSyncFailed,
            diagnostic: 'Second failure.',
            technicalCode: 'SECOND',
            technicalPath: r'elements[4].style.text',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FIRST'), findsNothing);
      expect(find.text('SECOND'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('templates-resource-error-more')),
        findsOneWidget,
      );
    },
  );

  testWidgets('resource failures are not duplicated as snackbars', (
    WidgetTester tester,
  ) async {
    const failure = ReportFlowFailure(
      code: ReportFlowFailureCode.templateSyncFailed,
    );
    final controller = _FakeController(
      _preparationState().copyWith(
        templateSync: ReportOperationStatus.failed,
        templateSyncFailure: failure,
      ),
    );
    await _pumpFlow(tester, controller);

    controller.emit(
      const ReportFlowEvent(
        type: ReportFlowEventType.failure,
        failure: failure,
      ),
    );
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Presenter update failure owns an independent inline expander', (
    WidgetTester tester,
  ) async {
    final controller = _FakeController(
      _preparationState().copyWith(
        presenterSync: ReportOperationStatus.failed,
        presenterSyncFailure: const ReportFlowFailure(
          code: ReportFlowFailureCode.presenterSyncFailed,
          diagnostic: 'Bundle download failed.',
          technicalCode: 'BUNDLE_DOWNLOAD_FAILED',
        ),
      ),
    );
    await _pumpFlow(tester, controller);

    final resourcesScrollable = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Presenter update failed.', skipOffstage: false),
      80,
      scrollable: resourcesScrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Presenter update failed.'), findsOneWidget);
    expect(find.text('Template update failed.'), findsNothing);
    final presenterCard = find
        .ancestor(of: find.text('Presenter'), matching: find.byType(Card))
        .first;
    expect(
      find.descendant(of: presenterCard, matching: find.text('Update')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('presenter-resource-error-more')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('presenter-resource-error-more')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText && widget.data == 'BUNDLE_DOWNLOAD_FAILED',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.data?.contains('Bundle download failed.') == true,
      ),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('template search stays visible and quick filters remain local', (
    WidgetTester tester,
  ) async {
    final controller = _FakeController(_mixedTemplateSelectionState());
    await _pumpFlow(tester, controller);

    expect(
      find.byKey(const ValueKey<String>('template-search-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('template-filter-all')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('template-filter-pages')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('template-filter-thermal')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('template-filter-a4')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('template-filter-thermal80')),
      findsOneWidget,
    );

    expect(find.text('Invoice A4'), findsOneWidget);
    expect(find.text('Receipt 80 mm'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('template-filter-pages')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Invoice A4'), findsOneWidget);
    expect(find.text('Receipt 80 mm'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('template-filter-a4')));
    await tester.pumpAndSettle();
    expect(find.text('Invoice A4'), findsOneWidget);
    expect(find.text('Receipt 80 mm'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('template-filter-thermal')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Receipt 80 mm'), findsOneWidget);
    expect(find.text('Invoice A4'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('template-filter-thermal80')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Receipt 80 mm'), findsOneWidget);
    expect(find.text('Receipt 58 mm'), findsNothing);
    expect(controller.syncTemplatesCalls, 0);

    await tester.enterText(
      find.byKey(const ValueKey<String>('template-search-field')),
      'missing',
    );
    await tester.pump();
    expect(find.text('No matching templates.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('template-clear-filters')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('template-clear-filters')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invoice A4'), findsOneWidget);
    expect(find.text('Receipt 80 mm'), findsOneWidget);
    expect(controller.syncTemplatesCalls, 0);
  });

  testWidgets(
    'template search and quick filters reset when selection origin changes',
    (WidgetTester tester) async {
      final controller = _FakeController(
        _mixedTemplateSelectionState(
          origin: TemplateSelectionOrigin.initialSetup,
        ),
      );
      await _pumpFlow(tester, controller);

      await tester.enterText(
        find.byKey(const ValueKey<String>('template-search-field')),
        'receipt',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('template-filter-thermal')),
      );
      await tester.pumpAndSettle();

      controller.setState(
        _mixedTemplateSelectionState(
          origin: TemplateSelectionOrigin.reportSettings,
        ),
      );
      await tester.pumpAndSettle();

      final search = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('template-search-field')),
      );
      expect(search.controller?.text, '');
      final allChip = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey<String>('template-filter-all')),
      );
      expect(allChip.selected, isTrue);
      expect(find.text('Invoice A4'), findsOneWidget);
    },
  );

  testWidgets(
    'template cards sanitize development case labels and preserve selection',
    (WidgetTester tester) async {
      final controller = _FakeController(_mixedTemplateSelectionState());
      await _pumpFlow(tester, controller);

      expect(find.text('إشعار استلام دفعة عميل — A4'), findsOneWidget);
      expect(find.textContaining('(case 3)'), findsNothing);
      final selectedIndicator = find.byKey(
        const ValueKey<String>('template-selection-t1'),
      );
      expect(selectedIndicator, findsOneWidget);
      expect(
        find.descendant(
          of: selectedIndicator,
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('template-filter-thermal')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Invoice A4'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('template-filter-all')),
      );
      await tester.pumpAndSettle();
      final restoredIndicator = find.byKey(
        const ValueKey<String>('template-selection-t1'),
      );
      expect(restoredIndicator, findsOneWidget);
      expect(
        find.descendant(
          of: restoredIndicator,
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      expect(controller.value.selectedTemplateId, 't1');
    },
  );

  testWidgets('Selection remains responsive at 320 dp and 200% text', (
    WidgetTester tester,
  ) async {
    _useCompactViewport(tester);
    final controller = _FakeController(_selectionState());

    await _pumpFlow(tester, controller, textScale: 2);

    expect(find.text('Select template'), findsOneWidget);
    expect(find.text('Adopt and open report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings remains responsive at 320 dp and 200% text', (
    WidgetTester tester,
  ) async {
    _useCompactViewport(tester);
    final controller = _FakeController(_settingsState());

    await _pumpFlow(tester, controller, textScale: 2);

    expect(find.text('Report settings'), findsOneWidget);
    expect(find.text('Presenter mode', skipOffstage: false), findsOneWidget);

    final settingsList = find.byType(ListView);
    expect(settingsList, findsOneWidget);
    final settingsScrollable = find.descendant(
      of: settingsList,
      matching: find.byType(Scrollable),
    );
    expect(settingsScrollable, findsOneWidget);

    final offlineMode = find.text('Use Presenter offline', skipOffstage: false);
    await tester.scrollUntilVisible(
      offlineMode,
      64,
      scrollable: settingsScrollable,
    );
    await tester.ensureVisible(offlineMode);
    await tester.pumpAndSettle();

    expect(find.text('Use Presenter offline'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.text('Save and refresh report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'operational Settings keeps template/mode/resources without filter UI',
    (WidgetTester tester) async {
      final controller = _FakeController(_settingsState());
      await _pumpFlow(tester, controller);

      expect(find.text('Report settings'), findsOneWidget);
      expect(find.text('Change template'), findsOneWidget);
      expect(find.text('Use Presenter offline'), findsOneWidget);
      expect(find.text('Prepare and update'), findsOneWidget);
      expect(find.text('Prepare and synchronize'), findsNothing);
      expect(find.text('Language'), findsNothing);
      expect(find.text('Layout'), findsNothing);
      expect(find.text('Size'), findsNothing);
      expect(find.text('Custom type'), findsNothing);
      expect(find.byType(DropdownButton<String?>), findsNothing);
      expect(find.text('Document settings'), findsNothing);
    },
  );

  testWidgets(
    'Report Settings uses compact mockup hierarchy and settings rows',
    (WidgetTester tester) async {
      final controller = _SupportFakeController(_settingsState());
      await _pumpFlow(tester, controller);

      final currentCard = find.byKey(
        const ValueKey<String>('settings-current-template'),
      );
      expect(currentCard, findsOneWidget);
      expect(
        find.descendant(
          of: currentCard,
          matching: find.byKey(
            const ValueKey<String>('settings-change-template-action'),
          ),
        ),
        findsOneWidget,
      );
      final currentSurface = tester.widget<Material>(
        find.byKey(const ValueKey<String>('settings-current-template-surface')),
      );
      final currentShape = currentSurface.shape! as RoundedRectangleBorder;
      expect(
        currentSurface.color,
        isNot(
          Theme.of(tester.element(currentCard)).colorScheme.primaryContainer,
        ),
      );
      expect(currentShape.side.width, greaterThan(0));
      expect(currentShape.side.width, lessThanOrEqualTo(1.5));
      expect(
        find.byKey(const ValueKey<String>('settings-offline-mode-row')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('settings-resource-row')),
        findsOneWidget,
      );
      expect(
        find.text('Manage available preparation and updates'),
        findsOneWidget,
      );

      final list = find.byType(ListView);
      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('settings-clear-cache-row')),
        80,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Help the development team improve this report'),
        findsOneWidget,
      );
      expect(
        find.text('Delete locally cached temporary files'),
        findsOneWidget,
      );
      final cacheTitleFinder = find.descendant(
        of: find.byKey(const ValueKey<String>('settings-clear-cache-row')),
        matching: find.text('Delete cache files'),
      );
      final cacheTitle = tester.widget<Text>(cacheTitleFinder);
      expect(
        cacheTitle.style?.color,
        Theme.of(tester.element(cacheTitleFinder)).colorScheme.error,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'showCurrentTemplate feature flag controls Current template card',
    (WidgetTester tester) async {
      Future<void> pumpSettings(_FakeController controller) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ReportFlowScreen(
              controller: controller,
              ui: const BridgeUiConfig.inheritHost(),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpSettings(
        _FakeController(
          _settingsState(),
          featuresOverride: const BridgeUiFeatures(showCurrentTemplate: true),
        ),
      );
      expect(find.text('Current template'), findsOneWidget);

      await pumpSettings(
        _FakeController(
          _settingsState(),
          featuresOverride: const BridgeUiFeatures(showCurrentTemplate: false),
        ),
      );
      expect(find.text('Current template'), findsNothing);
    },
  );

  testWidgets(
    'Preview disables native WebView zoom so Presenter is the only zoom authority',
    (WidgetTester tester) async {
      final platform = _TestInAppWebViewPlatform();
      InAppWebViewPlatform.instance = platform;
      final controller = _FakeController(_previewState());
      await _pumpFlow(tester, controller);

      final webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      expect(webView.platform.params.initialSettings?.supportZoom, isFalse);
    },
  );

  testWidgets(
    'Settings keeps the existing Presenter WebView mounted until Preview resumes',
    (WidgetTester tester) async {
      final platform = _TestInAppWebViewPlatform();
      InAppWebViewPlatform.instance = platform;
      final controller = _FakeController(_previewState());
      await _pumpFlow(tester, controller);

      expect(find.byType(BridgePresenterView), findsOneWidget);
      final presenterElement = find
          .byType(BridgePresenterView)
          .evaluate()
          .single;
      final webViewElement = find.byType(InAppWebView).evaluate().single;

      controller.editSettings();
      await tester.pumpAndSettle();
      final settingsTitle = find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Report settings'),
      );
      // The Preview action dock intentionally stays mounted underneath the
      // opaque Settings overlay, so an unscoped text finder also sees its
      // hidden "Report settings" label. Scope the assertion to the active
      // Settings AppBar instead.
      expect(settingsTitle, findsOneWidget);
      expect(find.byType(BridgePresenterView), findsOneWidget);
      expect(
        identical(
          find.byType(BridgePresenterView).evaluate().single,
          presenterElement,
        ),
        isTrue,
      );
      expect(
        identical(find.byType(InAppWebView).evaluate().single, webViewElement),
        isTrue,
      );

      controller.cancelSettings();
      await tester.pumpAndSettle();
      expect(find.byType(BridgePresenterView), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Report settings'),
        ),
        findsNothing,
      );
      expect(
        identical(
          find.byType(BridgePresenterView).evaluate().single,
          presenterElement,
        ),
        isTrue,
      );
      expect(
        identical(find.byType(InAppWebView).evaluate().single, webViewElement),
        isTrue,
      );
    },
  );

  testWidgets(
    'failed Preview uses Code and Message with two recovery actions',
    (WidgetTester tester) async {
      InAppWebViewPlatform.instance = _TestInAppWebViewPlatform();
      final controller = _SupportFakeController(
        _selectionState().copyWith(
          stage: ReportFlowStage.failed,
          selectedTemplateId: 't1',
          committedTemplateId: 't1',
          presenterLaunch: const PresenterSessionLaunch(
            presenterUrl: 'https://presenter.test/session',
            sessionId: 'session-failed',
            presenterVersion: '1.0.0',
            presenterDevVersion: 1,
          ),
          failure: const ReportFlowFailure(
            code: ReportFlowFailureCode.renderFailed,
            diagnostic: 'Unable to render text element.',
            technicalCode: 'TEXT_RENDER_FAILED',
          ),
          renderStatus: PresenterRenderStatus.failed,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReportFlowScreen(
            controller: controller,
            ui: const BridgeUiConfig.inheritHost(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Unable to display report'), findsOneWidget);
      expect(find.text('Code :'), findsOneWidget);
      expect(find.text('Message :'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText && widget.data == 'TEXT_RENDER_FAILED',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Unable to render text element.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('render-failure-update-templates')),
        findsOneWidget,
      );
      expect(find.text('Change template'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Show details'), findsNothing);
      expect(find.text('Send report data to development'), findsNothing);
      expect(find.text('Report settings'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BridgePresenterView), findsOneWidget);
      expect(find.byType(PresenterActionDock), findsNothing);
      expect(find.byIcon(Icons.warning_rounded), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('render-failure-update-templates')),
      );
      await tester.pumpAndSettle();
      expect(controller.value.stage, ReportFlowStage.preparingResources);
      expect(
        controller.value.resourceOrigin,
        ResourcePreparationOrigin.previewRecovery,
      );
      expect(controller.syncTemplatesCalls, 1);
    },
  );

  testWidgets(
    'Presenter error message deduplicates repeated technical values',
    (WidgetTester tester) async {
      InAppWebViewPlatform.instance = _TestInAppWebViewPlatform();
      final controller = _FakeController(
        _selectionState().copyWith(
          stage: ReportFlowStage.failed,
          committedTemplateId: 't1',
          presenterLaunch: const PresenterSessionLaunch(
            presenterUrl: 'https://presenter.test/session',
            sessionId: 'session-dedupe',
            presenterVersion: '1.0.0',
            presenterDevVersion: 1,
          ),
          failure: const ReportFlowFailure(
            code: ReportFlowFailureCode.renderFailed,
            technicalCode: 'INVALID_DOCUMENT',
            diagnostic: 'Invalid footer height.',
            technicalCategory: 'schema',
            technicalPath: r'elements[4].footer.height',
            details: <String, Object?>{
              'message': 'Invalid footer height.',
              'path': r'elements[4].footer.height',
            },
          ),
          renderStatus: PresenterRenderStatus.failed,
        ),
      );
      await _pumpDirectFlow(tester, controller);

      final message = tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('render-failure-message')),
          )
          .data!;
      expect('Invalid footer height.'.allMatches(message), hasLength(1));
      expect(r'elements[4].footer.height'.allMatches(message), hasLength(1));
      expect(message, contains('\u2068schema\u2069'));
    },
  );

  testWidgets('long Presenter error message supports More and Less', (
    WidgetTester tester,
  ) async {
    InAppWebViewPlatform.instance = _TestInAppWebViewPlatform();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = _FakeController(
      _selectionState().copyWith(
        stage: ReportFlowStage.failed,
        committedTemplateId: 't1',
        presenterLaunch: const PresenterSessionLaunch(
          presenterUrl: 'https://presenter.test/session',
          sessionId: 'session-long-error',
          presenterVersion: '1.0.0',
          presenterDevVersion: 1,
        ),
        failure: const ReportFlowFailure(
          code: ReportFlowFailureCode.renderFailed,
          technicalCode: 'INVALID_DOCUMENT',
          diagnostic:
              'The published document contains an invalid footer height and a long technical message that must remain available to the user without opening another dialog. Additional diagnostic context continues here so the collapsed state requires expansion.',
        ),
        renderStatus: PresenterRenderStatus.failed,
      ),
    );
    await _pumpDirectFlow(tester, controller);

    expect(find.text('More'), findsOneWidget);
    final collapsed = tester.widget<Text>(
      find.byKey(const ValueKey<String>('render-failure-message')),
    );
    expect(collapsed.maxLines, 2);
    expect(collapsed.overflow, TextOverflow.ellipsis);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    final expanded = tester.widget<Text>(
      find.byKey(const ValueKey<String>('render-failure-message')),
    );
    expect(expanded.maxLines, isNull);
    expect(find.text('Less'), findsOneWidget);

    await tester.ensureVisible(find.text('Less'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Less'));
    await tester.pumpAndSettle();
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets(
    'Presenter failure overlay remains scroll-safe at 320 dp and 200% text',
    (WidgetTester tester) async {
      InAppWebViewPlatform.instance = _TestInAppWebViewPlatform();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final controller = _FakeController(
        _selectionState().copyWith(
          stage: ReportFlowStage.failed,
          committedTemplateId: 't1',
          presenterLaunch: const PresenterSessionLaunch(
            presenterUrl: 'https://presenter.test/session',
            sessionId: 'session-accessible-error',
            presenterVersion: '1.0.0',
            presenterDevVersion: 1,
          ),
          failure: const ReportFlowFailure(
            code: ReportFlowFailureCode.renderFailed,
            technicalCode: 'PUBLISHED_TEMPLATE_DOCUMENT_INVALID',
            diagnostic:
                'The published template document contains a long validation message that must remain readable and scrollable at large accessibility text sizes.',
          ),
          renderStatus: PresenterRenderStatus.failed,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: ReportFlowScreen(
              controller: controller,
              ui: const BridgeUiConfig.inheritHost(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('render-failure-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('bridge-report-close')),
        findsOneWidget,
      );
      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(
        find.byKey(const ValueKey<String>('render-failure-update-templates')),
        findsOneWidget,
      );
      expect(find.text('Change template'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recovery overlay keeps one physical close control and warning icon in LTR and RTL',
    (WidgetTester tester) async {
      InAppWebViewPlatform.instance = _TestInAppWebViewPlatform();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      Future<void> pumpLocale(String locale) async {
        final controller = _FakeController(
          _selectionState().copyWith(
            stage: ReportFlowStage.failed,
            selectedTemplateId: 't1',
            committedTemplateId: 't1',
            presenterLaunch: const PresenterSessionLaunch(
              presenterUrl: 'https://presenter.test/session',
              sessionId: 'session-visual',
              presenterVersion: '1.0.0',
              presenterDevVersion: 1,
            ),
            failure: const ReportFlowFailure(
              code: ReportFlowFailureCode.renderFailed,
              diagnostic: 'Unable to render text element.',
            ),
            renderStatus: PresenterRenderStatus.failed,
          ),
          localeOverride: locale,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ReportFlowScreen(
              controller: controller,
              ui: const BridgeUiConfig.inheritHost(),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      void expectPhysicalPositions(String locale) {
        final outerClose = find.byKey(
          const ValueKey<String>('bridge-report-close'),
        );
        final failureCard = find.byKey(
          const ValueKey<String>('render-failure-card'),
        );
        expect(outerClose, findsOneWidget);
        expect(failureCard, findsOneWidget);
        expect(tester.getCenter(outerClose).dx, greaterThan(180));
        expect(
          tester.getCenter(failureCard).dy,
          closeTo(tester.view.physicalSize.height / 2, 90),
        );
        expect(
          find.byTooltip('Close'),
          locale == 'en' ? findsOneWidget : findsNothing,
        );
        expect(
          find.byTooltip('إغلاق'),
          locale == 'ar' ? findsOneWidget : findsNothing,
        );
        expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
        expect(find.byIcon(Icons.error), findsNothing);
      }

      await pumpLocale('en');
      expectPhysicalPositions('en');
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey<String>('render-failure-code')),
            )
            .textAlign,
        TextAlign.left,
      );

      await pumpLocale('ar');
      expectPhysicalPositions('ar');
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey<String>('render-failure-code')),
            )
            .textAlign,
        TextAlign.right,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('render-failure-message')),
            )
            .textAlign,
        TextAlign.right,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'development support opens native share flow directly without confirmation',
    (WidgetTester tester) async {
      final controller = _SupportFakeController(_settingsState());
      await _pumpFlow(tester, controller);

      final settingsList = find.byType(ListView);
      final scrollable = find.descendant(
        of: settingsList,
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Send report data to development', skipOffstage: false),
        80,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Send report data to development'));
      await tester.pumpAndSettle();

      expect(controller.supportShareCalls, 1);
      expect(find.text('Send report data to development?'), findsNothing);
      expect(find.text('Continue and share'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Report data sharing opened.'), findsNothing);
    },
  );

  testWidgets(
    'development support action shows preparation progress while sharing',
    (WidgetTester tester) async {
      final controller = _SupportFakeController(
        _settingsState().copyWith(supportShare: ReportOperationStatus.running),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReportFlowScreen(
            controller: controller,
            ui: const BridgeUiConfig.inheritHost(),
          ),
        ),
      );
      await tester.pump();

      final scrollable = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Preparing share…', skipOffstage: false),
        80,
        scrollable: scrollable,
      );
      await tester.pump();

      final support = find.byKey(
        const ValueKey<String>('settings-support-share-row'),
      );
      expect(support, findsOneWidget);
      expect(
        find.descendant(of: support, matching: find.text('Preparing share…')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: support,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      final supportTile = tester.widget<ListTile>(
        find.descendant(of: support, matching: find.byType(ListTile)),
      );
      expect(supportTile.enabled, isFalse);
    },
  );

  testWidgets('Settings groups maintenance actions into compact rows', (
    WidgetTester tester,
  ) async {
    final controller = _SupportFakeController(_settingsState());
    await _pumpFlow(tester, controller);

    final settingsList = find.byType(ListView);
    final scrollable = find.descendant(
      of: settingsList,
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('settings-clear-cache-row')),
      80,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    final support = find.byKey(
      const ValueKey<String>('settings-support-share-row'),
    );
    final cache = find.byKey(
      const ValueKey<String>('settings-clear-cache-row'),
    );
    expect(support, findsOneWidget);
    expect(cache, findsOneWidget);
    expect(
      find.descendant(
        of: support,
        matching: find.text('Help the development team improve this report'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: cache,
        matching: find.text('Delete locally cached temporary files'),
      ),
      findsOneWidget,
    );
    expect(tester.getRect(cache).top, greaterThan(tester.getRect(support).top));
    expect(tester.getSize(cache).width, tester.getSize(support).width);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Host can hide development support while keeping cache maintenance',
    (WidgetTester tester) async {
      final controller = _SupportFakeController(
        _settingsState(),
        featuresOverride: const BridgeUiFeatures(showDevelopmentSupport: false),
      );
      await _pumpFlow(tester, controller);

      expect(
        find.text('Send report data to development', skipOffstage: false),
        findsNothing,
      );
      expect(
        find.text('Delete cache files', skipOffstage: false),
        findsOneWidget,
      );
    },
  );

  testWidgets('Arabic template selection uses direction-aware BackButtonIcon', (
    WidgetTester tester,
  ) async {
    final controller = _FakeController(_selectionState(), localeOverride: 'ar');
    await _pumpFlow(tester, controller);

    expect(find.byType(BackButtonIcon), findsOneWidget);
  });

  testWidgets(
    'stacked primary labels stay fully visible at large text scales',
    (WidgetTester tester) async {
      Future<void> assertLabel({
        required Size viewport,
        required double textScale,
        required String locale,
        required String label,
      }) async {
        tester.view.physicalSize = Size(
          viewport.width * 3,
          viewport.height * 3,
        );
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final controller = _FakeController(
          _selectionState(),
          localeOverride: locale,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: viewport,
                textScaler: TextScaler.linear(textScale),
              ),
              child: ReportFlowScreen(
                controller: controller,
                ui: const BridgeUiConfig.inheritHost(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(label), findsOneWidget);
        final text = tester.widget<Text>(find.text(label));
        expect(text.maxLines, isNull);
        expect(text.overflow, TextOverflow.visible);
        expect(tester.takeException(), isNull);
      }

      await assertLabel(
        viewport: const Size(320, 640),
        textScale: 2,
        locale: 'en',
        label: 'Adopt and open report',
      );
      await assertLabel(
        viewport: const Size(320, 640),
        textScale: 2,
        locale: 'ar',
        label: 'اعتماد القالب وفتح التقرير',
      );
      await assertLabel(
        viewport: const Size(360, 640),
        textScale: 1.3,
        locale: 'ar',
        label: 'اعتماد القالب وفتح التقرير',
      );
    },
  );

  testWidgets('Selection localizes metadata and direction for Arabic', (
    WidgetTester tester,
  ) async {
    _useCompactViewport(tester);
    final controller = _FakeController(
      _selectionState(receiptPage: true),
      localeOverride: 'ar',
    );

    await _pumpFlow(tester, controller, textScale: 2);
    expect(find.text('اختر القالب'), findsOneWidget);
    final directionality = tester.widget<Directionality>(
      find
          .ancestor(
            of: find.text('اختر القالب'),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(directionality.textDirection, TextDirection.rtl);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.textContaining('فاتورة مبيعات'), findsOneWidget);
    expect(find.textContaining('الإنجليزية'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('template-filter-thermal')),
        matching: find.text('حراري'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('template-card-t1')),
        matching: find.text('حراري'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('template-filter-thermal80')),
        matching: find.text('٨٠ مم'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('template-card-t1')),
        matching: find.text('٨٠ مم'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('template-size-80mm')),
        matching: find.text('٨٠مم'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('عمودي'), findsNothing);
    expect(find.textContaining('الإصدار'), findsNothing);
    expect(find.text('portrait'), findsNothing);
    expect(find.text('80MM'), findsNothing);
    expect(find.text('v1.0.0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic Settings actions stay compact on mobile', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final controller = _FakeController(_settingsState(), localeOverride: 'ar');
    await _pumpFlow(tester, controller);

    final cancel = find.widgetWithText(OutlinedButton, 'إلغاء');
    final save = find.widgetWithText(FilledButton, 'حفظ وتحديث التقرير');

    expect(cancel, findsOneWidget);
    expect(save, findsOneWidget);
    expect(tester.getSize(cancel).height, lessThanOrEqualTo(56));
    expect(tester.getSize(save).height, lessThanOrEqualTo(56));
    expect(
      tester.getSize(save).width,
      greaterThan(tester.getSize(cancel).width),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('print export events surface the same Snackbar pattern', (
    WidgetTester tester,
  ) async {
    final controller = _FakeController(_preparationState());
    await _pumpFlow(tester, controller);

    controller.emit(
      const ReportFlowEvent(
        type: ReportFlowEventType.exportCompleted,
        detail: 'print',
      ),
    );
    await tester.pump();
    expect(find.text('Report submitted for printing.'), findsOneWidget);

    controller.emit(
      const ReportFlowEvent(
        type: ReportFlowEventType.exportCancelled,
        detail: 'print',
      ),
    );
    await tester.pump();
    expect(find.text('Printing was cancelled.'), findsOneWidget);
  });

  testWidgets(
    'Arabic Selection keeps Latin copy LTR and primary label single-line',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final controller = _FakeController(
        _selectionState(),
        localeOverride: 'ar',
      );
      await _pumpFlow(tester, controller);

      final title = tester.widget<Text>(find.text('Template 1'));
      final description = tester.widget<Text>(find.text('قالب تقرير جاهز'));
      final primaryLabel = tester.widget<Text>(
        find.text('اعتماد القالب وفتح التقرير'),
      );
      final primaryButton = find.widgetWithText(
        FilledButton,
        'اعتماد القالب وفتح التقرير',
      );
      final secondaryButton = find.widgetWithText(OutlinedButton, 'رجوع');

      expect(title.textDirection, TextDirection.ltr);
      expect(description.textDirection, TextDirection.rtl);
      expect(description.maxLines, 1);
      expect(primaryLabel.maxLines, 1);
      expect(primaryLabel.overflow, TextOverflow.ellipsis);
      expect(
        tester.getSize(primaryButton).width,
        greaterThan(tester.getSize(secondaryButton).width),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpDirectFlow(
  WidgetTester tester,
  _FakeController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ReportFlowScreen(
        controller: controller,
        ui: const BridgeUiConfig.inheritHost(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _useCompactViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _pumpFlow(
  WidgetTester tester,
  _FakeController controller, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push<ReportResult>(
            MaterialPageRoute<ReportResult>(
              builder: (routeContext) => MediaQuery(
                data: MediaQuery.of(
                  routeContext,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: ReportFlowScreen(
                  controller: controller,
                  ui: const BridgeUiConfig.inheritHost(),
                ),
              ),
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  if (controller.value.resourcesBusy) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  } else {
    await tester.pumpAndSettle();
  }
}

ReportFlowState _preparationState() => ReportFlowState(
  stage: ReportFlowStage.preparingResources,
  selectedMode: PresenterModePreference.online,
  templates: <CachedTemplate>[
    CachedTemplate(
      id: 't1',
      type: 'sales_invoice',
      systemId: 1,
      name: 'Template 1',
      version: '1.0.0',
      document: const <String, dynamic>{
        'schemaVersion': '1.0.0',
        'meta': <String, dynamic>{
          'family': 'sales_invoice',
          'name': 'Template 1',
        },
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
      },
    ),
  ],
  selectedTemplateId: 't1',
  templateSync: ReportOperationStatus.succeeded,
  presenterSync: ReportOperationStatus.succeeded,
  presenterCached: true,
  presenterDownloadProgress: 1,
);

ReportFlowState _selectionState({
  int count = 1,
  TemplateSelectionOrigin origin = TemplateSelectionOrigin.initialSetup,
  bool receiptPage = false,
}) => ReportFlowState(
  stage: ReportFlowStage.selectingTemplate,
  selectionOrigin: origin,
  selectedMode: PresenterModePreference.online,
  templates: List<CachedTemplate>.generate(
    count,
    (index) => CachedTemplate(
      id: 't${index + 1}',
      type: 'sales_invoice',
      systemId: 1,
      name: 'Template ${index + 1}',
      version: '1.0.0',
      document: <String, dynamic>{
        'schemaVersion': '1.0.0',
        'meta': const <String, dynamic>{
          'family': 'sales_invoice',
          'name': 'Template',
        },
        'page': <String, dynamic>{
          'layout': receiptPage ? 'Thermal' : 'Pages',
          'size': receiptPage ? '80mm' : 'A4',
          'unit': 'mm',
          'orientation': 'portrait',
          'language': receiptPage ? 'en' : 'ar',
          'direction': 'rtl',
          'width': receiptPage ? 80 : 210,
          'height': receiptPage ? 220 : 297,
        },
      },
    ),
  ),
  selectedTemplateId: 't1',
);

ReportFlowState _mixedTemplateSelectionState({
  TemplateSelectionOrigin origin = TemplateSelectionOrigin.reportSettings,
}) => ReportFlowState(
  stage: ReportFlowStage.selectingTemplate,
  selectionOrigin: origin,
  selectedMode: PresenterModePreference.online,
  templates: <CachedTemplate>[
    CachedTemplate(
      id: 't1',
      type: 'receipt_voucher',
      systemId: 1,
      name: 'إشعار استلام دفعة عميل — A4 (case 3)',
      version: '1.0.0',
      document: const <String, dynamic>{
        'schemaVersion': '1.0.0',
        'meta': <String, dynamic>{
          'family': 'receipt_voucher',
          'name': 'Receipt A4',
        },
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
      },
    ),
    CachedTemplate(
      id: 't2',
      type: 'sales_invoice',
      systemId: 1,
      name: 'Invoice A4',
      version: '1.0.0',
      document: const <String, dynamic>{
        'schemaVersion': '1.0.0',
        'meta': <String, dynamic>{
          'family': 'sales_invoice',
          'name': 'Invoice A4',
        },
        'page': <String, dynamic>{
          'layout': 'Pages',
          'size': 'A4',
          'unit': 'mm',
          'orientation': 'portrait',
          'language': 'en',
          'direction': 'ltr',
          'width': 210,
          'height': 297,
        },
      },
    ),
    CachedTemplate(
      id: 't3',
      type: 'receipt_voucher',
      systemId: 1,
      name: 'Receipt 80 mm',
      version: '1.0.0',
      document: const <String, dynamic>{
        'schemaVersion': '1.0.0',
        'meta': <String, dynamic>{
          'family': 'receipt_voucher',
          'name': 'Receipt 80 mm',
        },
        'page': <String, dynamic>{
          'layout': 'Thermal',
          'size': '80mm',
          'unit': 'mm',
          'orientation': 'portrait',
          'language': 'ar',
          'direction': 'rtl',
          'width': 80,
          'height': 220,
        },
      },
    ),
    CachedTemplate(
      id: 't4',
      type: 'receipt_voucher',
      systemId: 1,
      name: 'Receipt 58 mm',
      version: '1.0.0',
      document: const <String, dynamic>{
        'schemaVersion': '1.0.0',
        'meta': <String, dynamic>{
          'family': 'receipt_voucher',
          'name': 'Receipt 58 mm',
        },
        'page': <String, dynamic>{
          'layout': 'Thermal',
          'size': '58mm',
          'unit': 'mm',
          'orientation': 'portrait',
          'language': 'ar',
          'direction': 'rtl',
          'width': 58,
          'height': 220,
        },
      },
    ),
  ],
  selectedTemplateId: 't1',
);

ReportFlowState _previewState() => _selectionState().copyWith(
  stage: ReportFlowStage.previewing,
  selectedTemplateId: 't1',
  committedTemplateId: 't1',
  committedMode: PresenterModePreference.online,
  presenterLaunch: PresenterSessionLaunch(
    presenterUrl: 'https://presenter.test/session',
    sessionId: 'session-preview',
    presenterVersion: '1.0.0',
    presenterDevVersion: 1,
  ),
  previewLoad: ReportOperationStatus.succeeded,
  renderStatus: PresenterRenderStatus.ready,
  webViewLoadProgress: 1,
  presenterProtocolReady: true,
);

ReportFlowState _settingsState() => _selectionState().copyWith(
  stage: ReportFlowStage.editingSettings,
  committedTemplateId: 't1',
  committedMode: PresenterModePreference.online,
  settingsDraft: const ReportSettingsDraft(
    templateId: 't1',
    mode: PresenterModePreference.online,
  ),
);

class _FakeController extends ChangeNotifier implements ReportFlowController {
  _FakeController(
    this._value, {
    this.localeOverride = 'en',
    this.featuresOverride,
    this.filterOverride,
  });

  ReportFlowState _value;
  final String localeOverride;
  final BridgeUiFeatures? featuresOverride;
  final TemplateSyncFilter? filterOverride;
  int closeCalls = 0;
  int continueCalls = 0;
  int backCalls = 0;
  int syncTemplatesCalls = 0;
  final PresenterSurfaceBinding _surface = PresenterSurfaceBinding();
  final StreamController<ReportFlowEvent> _events =
      StreamController<ReportFlowEvent>.broadcast(sync: true);

  void setState(ReportFlowState value) {
    _value = value;
    notifyListeners();
  }

  @override
  ReportFlowState get value => _value;

  @override
  Stream<ReportFlowEvent> get events => _events.stream;

  void emit(ReportFlowEvent event) => _events.add(event);

  @override
  PresenterSurfaceBinding get presenterSurface => _surface;

  @override
  ReportOpenRequest get request => buildTestOpenRequest(
    system: 'legacy_system_1',
    reportType: 'sales_invoice',
    localeOverride: localeOverride,
    featuresOverride: featuresOverride,
    filter: filterOverride,
  );

  @override
  Future<ReportResult> close() async {
    closeCalls += 1;
    setState(_value.copyWith(stage: ReportFlowStage.closed));
    return const ReportCancelled();
  }

  @override
  void cancelSettings() {
    setState(
      _value.copyWith(
        stage: _value.presenterLaunch == null
            ? ReportFlowStage.selectingTemplate
            : ReportFlowStage.previewing,
      ),
    );
  }

  @override
  Future<void> continueFromPreparation() async {
    continueCalls += 1;
    setState(_value.copyWith(stage: ReportFlowStage.selectingTemplate));
  }

  @override
  void backToPreparation() {
    backCalls += 1;
    setState(
      _value.copyWith(
        stage: _value.selectionOrigin == TemplateSelectionOrigin.reportSettings
            ? ReportFlowStage.editingSettings
            : _value.selectionOrigin == TemplateSelectionOrigin.previewRecovery
            ? ReportFlowStage.failed
            : ReportFlowStage.preparingResources,
      ),
    );
  }

  @override
  void openTemplateSelection({
    TemplateSelectionOrigin origin = TemplateSelectionOrigin.initialSetup,
  }) {
    setState(
      _value.copyWith(
        stage: ReportFlowStage.selectingTemplate,
        selectionOrigin: origin,
      ),
    );
  }

  @override
  void openResourcePreparation(ResourcePreparationOrigin origin) {
    setState(
      _value.copyWith(
        stage: ReportFlowStage.preparingResources,
        resourceOrigin: origin,
      ),
    );
  }

  @override
  void returnFromResourcePreparation() {
    setState(_value.copyWith(stage: ReportFlowStage.editingSettings));
  }

  @override
  void confirmTemplateSelection() {
    setState(_value.copyWith(stage: ReportFlowStage.editingSettings));
  }

  @override
  Future<void> commitSettings() async {}

  @override
  void completePresenterRender({String? sessionId}) {}

  @override
  Future<void> dispose() async {
    _surface.dispose();
    await _events.close();
    super.dispose();
  }

  @override
  void editSettings() {
    setState(_value.copyWith(stage: ReportFlowStage.editingSettings));
  }

  @override
  void failPresenterRender(String diagnostic, {String? sessionId}) {}

  @override
  Future<void> initialize() async {}

  @override
  void presenterLoadProgress(double progress) {}

  @override
  void presenterLoadStarted() {}

  @override
  void presenterProtocolDetected(int contractVersion) {}

  @override
  Future<void> preparePreview() async {}

  @override
  Future<void> retry() async {}

  @override
  Future<void> savePdf() async {}

  @override
  void selectMode(PresenterModePreference mode) {
    setState(_value.copyWith(selectedMode: mode));
  }

  @override
  void selectTemplate(String templateId) {
    setState(_value.copyWith(selectedTemplateId: templateId));
  }

  @override
  Future<void> sharePdf() async {}

  @override
  Future<void> syncPresenter() async {}

  @override
  Future<void> syncTemplates() async {
    syncTemplatesCalls += 1;
  }
}

class _SupportFakeController extends _FakeController
    implements ReportFlowSupportController {
  _SupportFakeController(super.value, {super.featuresOverride});

  int supportShareCalls = 0;
  int clearCacheCalls = 0;
  Rect? lastShareOrigin;

  @override
  Future<void> shareDevelopmentSupportPackage({
    Rect? sharePositionOrigin,
  }) async {
    supportShareCalls += 1;
    lastShareOrigin = sharePositionOrigin;
  }

  @override
  Future<void> clearCachedResources() async {
    clearCacheCalls += 1;
    setState(
      value.copyWith(
        stage: ReportFlowStage.preparingResources,
        resourceOrigin: ResourcePreparationOrigin.reportSettings,
      ),
    );
  }
}

class _TestInAppWebViewPlatform extends InAppWebViewPlatform {
  int createCount = 0;

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    createCount += 1;
    return _TestPlatformInAppWebViewWidget(params);
  }
}

class _TestPlatformInAppWebViewWidget extends PlatformInAppWebViewWidget {
  _TestPlatformInAppWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) {
    throw UnimplementedError(
      'The failed-preview widget test does not request a WebView controller.',
    );
  }

  @override
  void dispose() {}
}
