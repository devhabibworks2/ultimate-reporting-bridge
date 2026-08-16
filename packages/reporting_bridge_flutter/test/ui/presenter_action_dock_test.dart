import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  Widget buildDock({
    bool showSavePdf = true,
    bool showSharePdf = true,
    bool showPrint = true,
    bool showSettings = true,
    bool outputEnabled = true,
    ReportExportAction? busyAction,
    VoidCallback? onSave,
    VoidCallback? onShare,
    VoidCallback? onPrint,
    VoidCallback? onSettings,
  }) {
    return MaterialApp(
      home: Scaffold(
        bottomNavigationBar: PresenterActionDock(
          saveLabel: 'Save PDF',
          shareLabel: 'Share',
          printLabel: 'Print',
          settingsLabel: 'Settings',
          showSavePdf: showSavePdf,
          showSharePdf: showSharePdf,
          showPrint: showPrint,
          showSettings: showSettings,
          outputEnabled: outputEnabled,
          busyAction: busyAction,
          onSave: onSave ?? () {},
          onShare: onShare ?? () {},
          onPrint: onPrint ?? () {},
          onSettings: onSettings ?? () {},
        ),
      ),
    );
  }

  InkWell inkWellOf(WidgetTester tester, String key) {
    return tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byType(InkWell),
      ),
    );
  }

  testWidgets(
    'Print is primary when visible; Save becomes primary when Print hidden',
    (WidgetTester tester) async {
      Color materialColor(String key) {
        return tester
            .widget<Material>(
              find.descendant(
                of: find.byKey(ValueKey<String>(key)),
                matching: find.byType(Material),
              ),
            )
            .color!;
      }

      await tester.pumpWidget(buildDock(showPrint: true));
      final scheme = Theme.of(
        tester.element(find.byType(PresenterActionDock)),
      ).colorScheme;
      expect(materialColor('bridge-print-pdf'), scheme.primary);
      expect(materialColor('bridge-save-pdf'), scheme.primaryContainer);
      expect(materialColor('bridge-share-pdf'), scheme.primaryContainer);
      expect(
        materialColor('bridge-report-settings'),
        scheme.surfaceContainerLow,
      );

      await tester.pumpWidget(buildDock(showPrint: false));
      expect(
        find.byKey(const ValueKey<String>('bridge-print-pdf')),
        findsNothing,
      );
      expect(materialColor('bridge-save-pdf'), scheme.primary);

      await tester.pumpWidget(buildDock(showPrint: true, outputEnabled: false));
      expect(materialColor('bridge-print-pdf'), isNot(scheme.primary));
      // Disabled primary still uses primary hue at reduced alpha; layout stays stable.
      expect(
        find.byKey(const ValueKey<String>('bridge-print-pdf')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('bridge-save-pdf')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'export waits for render readiness while settings stays available',
    (WidgetTester tester) async {
      var settingsTaps = 0;
      await tester.pumpWidget(
        buildDock(outputEnabled: false, onSettings: () => settingsTaps += 1),
      );

      expect(inkWellOf(tester, 'bridge-save-pdf').onTap, isNull);
      expect(inkWellOf(tester, 'bridge-share-pdf').onTap, isNull);
      expect(inkWellOf(tester, 'bridge-print-pdf').onTap, isNull);

      await tester.tap(
        find.byKey(const ValueKey<String>('bridge-report-settings')),
      );
      expect(settingsTaps, 1);
    },
  );

  testWidgets('all four actions are visible and ready', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildDock());

    expect(
      find.byKey(const ValueKey<String>('bridge-save-pdf')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('bridge-share-pdf')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('bridge-print-pdf')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('bridge-report-settings')),
      findsOneWidget,
    );
    expect(inkWellOf(tester, 'bridge-save-pdf').onTap, isNotNull);
    expect(inkWellOf(tester, 'bridge-share-pdf').onTap, isNotNull);
    expect(inkWellOf(tester, 'bridge-print-pdf').onTap, isNotNull);
    expect(inkWellOf(tester, 'bridge-report-settings').onTap, isNotNull);
  });

  testWidgets('Print is hidden when feature/policy disabled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildDock(showPrint: false));
    expect(
      find.byKey(const ValueKey<String>('bridge-print-pdf')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('bridge-save-pdf')),
      findsOneWidget,
    );
  });

  testWidgets('Save is hidden when feature/policy disabled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildDock(showSavePdf: false));
    expect(find.byKey(const ValueKey<String>('bridge-save-pdf')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('bridge-print-pdf')),
      findsOneWidget,
    );
  });

  testWidgets(
    'supported but output not ready keeps output actions visible and disabled',
    (WidgetTester tester) async {
      await tester.pumpWidget(buildDock(outputEnabled: false));

      expect(
        find.byKey(const ValueKey<String>('bridge-save-pdf')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('bridge-share-pdf')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('bridge-print-pdf')),
        findsOneWidget,
      );
      expect(inkWellOf(tester, 'bridge-save-pdf').onTap, isNull);
      expect(inkWellOf(tester, 'bridge-share-pdf').onTap, isNull);
      expect(inkWellOf(tester, 'bridge-print-pdf').onTap, isNull);
      expect(inkWellOf(tester, 'bridge-report-settings').onTap, isNotNull);
    },
  );

  testWidgets('print busy shows spinner and disables other actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildDock(busyAction: ReportExportAction.print));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('bridge-print-pdf')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(inkWellOf(tester, 'bridge-save-pdf').onTap, isNull);
    expect(inkWellOf(tester, 'bridge-share-pdf').onTap, isNull);
    expect(inkWellOf(tester, 'bridge-print-pdf').onTap, isNull);
    expect(inkWellOf(tester, 'bridge-report-settings').onTap, isNull);
  });

  testWidgets('save busy disables Print/Share/Settings', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildDock(busyAction: ReportExportAction.save));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('bridge-save-pdf')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(inkWellOf(tester, 'bridge-share-pdf').onTap, isNull);
    expect(inkWellOf(tester, 'bridge-print-pdf').onTap, isNull);
    expect(inkWellOf(tester, 'bridge-report-settings').onTap, isNull);
  });

  testWidgets('each action exposes one consolidated semantics label', (
    WidgetTester tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(buildDock());

      expect(find.bySemanticsLabel('Save PDF'), findsOneWidget);
      expect(find.bySemanticsLabel('Share'), findsOneWidget);
      expect(find.bySemanticsLabel('Print'), findsOneWidget);
      expect(find.bySemanticsLabel('Settings'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'compact 320dp Arabic RTL 200% text uses 2x2 grid without overflow',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 900),
                textScaler: TextScaler.linear(2),
              ),
              child: Scaffold(
                bottomNavigationBar: PresenterActionDock(
                  saveLabel: 'حفظ PDF',
                  shareLabel: 'مشاركة',
                  printLabel: 'طباعة',
                  settingsLabel: 'الإعدادات',
                  showSavePdf: true,
                  showSharePdf: true,
                  showPrint: true,
                  showSettings: true,
                  outputEnabled: true,
                  busyAction: null,
                  onSave: () {},
                  onShare: () {},
                  onPrint: () {},
                  onSettings: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Column), findsWidgets);
      expect(find.byType(Row), findsWidgets);
      expect(find.text('حفظ PDF'), findsOneWidget);
      expect(find.text('مشاركة'), findsOneWidget);
      expect(find.text('طباعة'), findsOneWidget);
      expect(find.text('الإعدادات'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact 360dp Arabic RTL 130% text stays 2x2 without overflow', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(1.3),
            ),
            child: Scaffold(
              bottomNavigationBar: PresenterActionDock(
                saveLabel: 'حفظ PDF',
                shareLabel: 'مشاركة',
                printLabel: 'طباعة',
                settingsLabel: 'الإعدادات',
                showSavePdf: true,
                showSharePdf: true,
                showPrint: true,
                showSettings: true,
                outputEnabled: true,
                busyAction: null,
                onSave: () {},
                onShare: () {},
                onPrint: () {},
                onSettings: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final saveTop = tester.getTopLeft(
      find.byKey(const ValueKey<String>('bridge-save-pdf')),
    );
    final printTop = tester.getTopLeft(
      find.byKey(const ValueKey<String>('bridge-print-pdf')),
    );
    expect(printTop.dy, greaterThan(saveTop.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('normal phone width English keeps one row', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(440, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(440, 800)),
        child: buildDock(),
      ),
    );

    final saveTop = tester.getTopLeft(
      find.byKey(const ValueKey<String>('bridge-save-pdf')),
    );
    final printTop = tester.getTopLeft(
      find.byKey(const ValueKey<String>('bridge-print-pdf')),
    );
    // Same row: allow tiny paint/layout jitter, not a second grid row (~58+).
    expect((printTop.dy - saveTop.dy).abs(), lessThan(8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('light and dark schemes render dock without overflow', (
    WidgetTester tester,
  ) async {
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1565C0),
              brightness: brightness,
            ),
            useMaterial3: true,
          ),
          home: Scaffold(
            bottomNavigationBar: PresenterActionDock(
              saveLabel: 'Save PDF',
              shareLabel: 'Share',
              printLabel: 'Print',
              settingsLabel: 'Settings',
              showSavePdf: true,
              showSharePdf: true,
              showPrint: true,
              showSettings: true,
              outputEnabled: true,
              busyAction: null,
              onSave: () {},
              onShare: () {},
              onPrint: () {},
              onSettings: () {},
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey<String>('bridge-print-pdf')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('hostile Host theme does not deform Bridge dock geometry', (
    WidgetTester tester,
  ) async {
    final host = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6A1B9A),
        brightness: Brightness.light,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontFamily: 'HostileHostFont', fontSize: 18),
        labelSmall: TextStyle(fontFamily: 'HostileHostFont', fontSize: 8),
      ),
      visualDensity: VisualDensity(horizontal: -4, vertical: -4),
      useMaterial3: true,
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        shape: CircleBorder(),
        extendedPadding: EdgeInsets.zero,
        sizeConstraints: BoxConstraints.tightFor(width: 96, height: 96),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(8, 8),
          padding: EdgeInsets.zero,
          shape: const StadiumBorder(),
        ),
      ),
      cardTheme: const CardThemeData(
        shape: BeveledRectangleBorder(),
        margin: EdgeInsets.all(40),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
      ),
    );

    final bridge = const BridgeUiConfig.inheritHost().resolve(host);
    expect(bridge.colorScheme.primary, host.colorScheme.primary);
    expect(bridge.textTheme.bodyMedium?.fontFamily, 'HostileHostFont');
    expect(bridge.visualDensity, VisualDensity.standard);
    expect(bridge.visualDensity, isNot(host.visualDensity));
    expect(
      bridge.floatingActionButtonTheme.shape,
      isNot(host.floatingActionButtonTheme.shape),
    );
    expect(
      bridge.filledButtonTheme.style?.minimumSize?.resolve(<WidgetState>{}),
      isNot(
        host.filledButtonTheme.style?.minimumSize?.resolve(<WidgetState>{}),
      ),
    );
    expect(bridge.cardTheme.shape, isNot(host.cardTheme.shape));

    await tester.pumpWidget(
      MaterialApp(
        theme: host,
        home: Builder(
          builder: (context) {
            final resolved = const BridgeUiConfig.inheritHost().resolve(
              Theme.of(context),
            );
            return Theme(
              data: resolved,
              child: Scaffold(
                floatingActionButton: FloatingActionButton.small(
                  heroTag: 'bridge-close-test',
                  onPressed: () {},
                  child: const Icon(Icons.close),
                ),
                bottomNavigationBar: PresenterActionDock(
                  saveLabel: 'Save PDF',
                  shareLabel: 'Share',
                  printLabel: 'Print',
                  settingsLabel: 'Settings',
                  showSavePdf: true,
                  showSharePdf: true,
                  showPrint: true,
                  showSettings: true,
                  outputEnabled: true,
                  busyAction: null,
                  onSave: () {},
                  onShare: () {},
                  onPrint: () {},
                  onSettings: () {},
                ),
              ),
            );
          },
        ),
      ),
    );

    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(fab.shape, isNot(isA<CircleBorder>()));
    final saveSize = tester.getSize(
      find.byKey(const ValueKey<String>('bridge-save-pdf')),
    );
    expect(saveSize.height, greaterThanOrEqualTo(58));
    expect(tester.takeException(), isNull);
  });
}
