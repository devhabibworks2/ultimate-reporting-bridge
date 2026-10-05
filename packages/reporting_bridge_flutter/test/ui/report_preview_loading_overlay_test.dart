import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/src/localization/report_flow_strings.dart';
import 'package:reporting_bridge_flutter/src/ui/bridge_pdf_preview_config.dart';
import 'package:reporting_bridge_flutter/src/ui/report_preview_loading_overlay.dart';

void main() {
  testWidgets(
    'loading UI shows only stage and skeleton in portrait and compact layouts',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final size in <Size>[const Size(430, 900), const Size(800, 360)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: ReportPreviewLoadingOverlay(
                  stage: ReportPreviewLoadingStage.preparingReport,
                  strings: ReportFlowStrings(Locale('ar')),
                ),
              ),
            ),
          ),
        );

        expect(find.text('إعداد التقرير'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('bridge-report-skeleton')),
          findsOneWidget,
        );
        expect(
          find.text(
            const ReportFlowStrings(Locale('ar')).preparingReportLoading,
          ),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('bridge-report-close')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('bridge-loading-pdf-badge')),
          findsNothing,
        );
      }

      tester.view.resetPhysicalSize();
    },
  );

  testWidgets('loading overlay shows agreed copy without progress UI', (
    tester,
  ) async {
    for (final entry in <(ReportPreviewLoadingStage, String)>[
      (ReportPreviewLoadingStage.preparingData, 'Preparing data'),
      (ReportPreviewLoadingStage.preparingReport, 'Preparing report'),
      (ReportPreviewLoadingStage.openingPreview, 'Opening preview'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportPreviewLoadingOverlay(
              stage: entry.$1,
              strings: const ReportFlowStrings(Locale('en')),
            ),
          ),
        ),
      );

      expect(find.text('Preparing report…'), findsNothing);
      expect(find.text(entry.$2), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('bridge-report-close')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('bridge-report-skeleton')),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('bridge-loading-bar')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('bridge-loading-percent')),
        findsNothing,
      );
      expect(find.textContaining('%'), findsNothing);
    }
  });

  testWidgets('stage stays centered 12dp above the skeleton with no header', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ReportPreviewLoadingOverlay(
              stage: ReportPreviewLoadingStage.preparingReport,
              strings: ReportFlowStrings(Locale('ar')),
            ),
          ),
        ),
      ),
    );

    final stage = tester.getRect(find.text('إعداد التقرير'));
    final skeleton = tester.getRect(
      find.byKey(const ValueKey<String>('bridge-report-skeleton')),
    );

    expect(stage.center.dx, closeTo(skeleton.center.dx, 0.5));
    expect(skeleton.top - stage.bottom, closeTo(12, 0.5));
    expect(
      find.text(const ReportFlowStrings(Locale('ar')).preparingReportLoading),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('bridge-report-close')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('bridge-loading-pdf-badge')),
      findsNothing,
    );
  });

  testWidgets('Arabic loading UI contains only stage and skeleton', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ReportPreviewLoadingOverlay(
              stage: ReportPreviewLoadingStage.preparingReport,
              strings: ReportFlowStrings(Locale('ar')),
            ),
          ),
        ),
      ),
    );

    expect(find.text('إعداد التقرير'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('bridge-report-skeleton')),
      findsOneWidget,
    );
    expect(
      find.text(const ReportFlowStrings(Locale('ar')).preparingReportLoading),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('bridge-report-close')),
      findsNothing,
    );
    expect(find.byIcon(Icons.picture_as_pdf_rounded), findsNothing);
  });

  testWidgets('top status has no floating card or segmented/circular meter', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReportPreviewLoadingOverlay(
            stage: ReportPreviewLoadingStage.preparingReport,
            strings: ReportFlowStrings(Locale('en')),
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'bridge-loading-segment-',
            ),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('bridge-loading-bar')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('bridge-loading-percent')),
      findsNothing,
    );
  });

  testWidgets('shimmer never masks the A4 page surface', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReportPreviewLoadingOverlay(
            stage: ReportPreviewLoadingStage.preparingData,
            strings: ReportFlowStrings(Locale('en')),
          ),
        ),
      ),
    );

    final page = find.byKey(const ValueKey<String>('bridge-report-skeleton'));
    expect(page, findsOneWidget);
    expect(
      find.ancestor(of: page, matching: find.byType(ShaderMask)),
      findsNothing,
    );
  });

  testWidgets('loading shimmer settles after one subtle sweep', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReportPreviewLoadingOverlay(
            stage: ReportPreviewLoadingStage.preparingReport,
            strings: ReportFlowStrings(Locale('en')),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(
      find.byKey(const ValueKey<String>('bridge-report-skeleton')),
      findsOneWidget,
    );
  });

  testWidgets('reduced motion renders a static skeleton', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: ReportPreviewLoadingOverlay(
              stage: ReportPreviewLoadingStage.preparingReport,
              strings: ReportFlowStrings(Locale('en')),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('bridge-report-skeleton')),
      findsOneWidget,
    );
    expect(find.byType(ShaderMask), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'loading skeleton remains overflow-free in a short landscape viewport',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 360);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReportPreviewLoadingOverlay(
              stage: ReportPreviewLoadingStage.openingPreview,
              strings: ReportFlowStrings(Locale('en')),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1700));

      expect(
        find.byKey(const ValueKey<String>('bridge-report-skeleton')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loading overlay is responsive and one semantic live region at 320dp 200% text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(320, 800),
              textScaler: TextScaler.linear(2),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: ReportPreviewLoadingOverlay(
                  stage: ReportPreviewLoadingStage.preparingData,
                  strings: ReportFlowStrings(Locale('ar')),
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('bridge-loading-status')),
        findsOneWidget,
      );
      expect(
        find.text(const ReportFlowStrings(Locale('ar')).preparingReportLoading),
        findsNothing,
      );
      expect(find.text('تجهيز البيانات'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'portrait skeleton matches the real PDF initial viewport geometry',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReportPreviewLoadingOverlay(
              stage: ReportPreviewLoadingStage.preparingReport,
              strings: ReportFlowStrings(Locale('en')),
            ),
          ),
        ),
      );

      final skeleton = tester.getRect(
        find.byKey(const ValueKey<String>('bridge-report-skeleton')),
      );
      const expectedWidth = (430.0 - 20.0) * 0.97;
      final expectedHeight = expectedWidth * 297 / 210;
      final expectedLeft = (430.0 - expectedWidth) / 2;
      final expectedTop = (900.0 - expectedHeight) / 2;

      expect(skeleton.width, closeTo(expectedWidth, 0.5));
      expect(skeleton.height, closeTo(expectedHeight, 0.5));
      expect(skeleton.left, closeTo(expectedLeft, 0.5));
      expect(skeleton.top, closeTo(expectedTop, 0.5));
    },
  );

  testWidgets('skeleton honors custom PDF initial scale', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReportPreviewLoadingOverlay(
            stage: ReportPreviewLoadingStage.preparingReport,
            strings: ReportFlowStrings(Locale('en')),
            previewConfig: BridgePdfPreviewConfig(
              minScale: 0.5,
              maxScale: 4,
              initialScale: 0.75,
            ),
          ),
        ),
      ),
    );

    final skeleton = tester.getRect(
      find.byKey(const ValueKey<String>('bridge-report-skeleton')),
    );
    expect(skeleton.width, closeTo((430.0 - 20.0) * 0.75, 0.5));
  });

  testWidgets('loading visual hierarchy keeps stage secondary and PDF hidden', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReportPreviewLoadingOverlay(
            stage: ReportPreviewLoadingStage.preparingReport,
            strings: ReportFlowStrings(Locale('en')),
          ),
        ),
      ),
    );

    final stage = tester.widget<Text>(find.text('Preparing report'));
    expect(stage.style?.fontWeight, FontWeight.w400);
    expect(stage.style?.color?.a, lessThanOrEqualTo(0.68));
    expect(
      find.byKey(const ValueKey<String>('bridge-loading-pdf-badge')),
      findsNothing,
    );
    expect(find.byIcon(Icons.picture_as_pdf_rounded), findsNothing);

    final skeleton = tester.widget<Container>(
      find.byKey(const ValueKey<String>('bridge-report-skeleton')),
    );
    final skeletonDecoration = skeleton.decoration! as BoxDecoration;
    final border = skeletonDecoration.border! as Border;
    expect(border.top.color.a, lessThanOrEqualTo(0.65));
  });

  testWidgets(
    'skeleton stays centered at the same rect across all loading stages',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      Rect? firstRect;
      for (final stage in ReportPreviewLoadingStage.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReportPreviewLoadingOverlay(
                stage: stage,
                strings: const ReportFlowStrings(Locale('en')),
              ),
            ),
          ),
        );

        final rect = tester.getRect(
          find.byKey(const ValueKey<String>('bridge-report-skeleton')),
        );
        expect(rect.center.dx, closeTo(215, 0.5));
        expect(rect.center.dy, closeTo(450, 0.5));
        if (firstRect != null) {
          expect(rect.left, closeTo(firstRect.left, 0.5));
          expect(rect.top, closeTo(firstRect.top, 0.5));
          expect(rect.width, closeTo(firstRect.width, 0.5));
          expect(rect.height, closeTo(firstRect.height, 0.5));
        }
        firstRect = rect;
      }
    },
  );

  testWidgets('English loading UI keeps only stage above skeleton', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReportPreviewLoadingOverlay(
            stage: ReportPreviewLoadingStage.openingPreview,
            strings: ReportFlowStrings(Locale('en')),
          ),
        ),
      ),
    );

    final stage = tester.getRect(find.text('Opening preview'));
    final skeleton = tester.getRect(
      find.byKey(const ValueKey<String>('bridge-report-skeleton')),
    );

    expect(stage.center.dx, closeTo(skeleton.center.dx, 0.5));
    expect(skeleton.top - stage.bottom, closeTo(12, 0.5));
    expect(find.text('Preparing report…'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('bridge-report-close')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('bridge-loading-pdf-badge')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic opening stage uses عرض التقرير above skeleton', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ReportPreviewLoadingOverlay(
              stage: ReportPreviewLoadingStage.openingPreview,
              strings: ReportFlowStrings(Locale('ar')),
            ),
          ),
        ),
      ),
    );

    final stage = tester.getRect(find.text('عرض التقرير'));
    final skeleton = tester.getRect(
      find.byKey(const ValueKey<String>('bridge-report-skeleton')),
    );

    expect(stage.center.dx, closeTo(skeleton.center.dx, 0.5));
    expect(skeleton.top - stage.bottom, closeTo(12, 0.5));
    expect(find.text('فتح المعاينة'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('bridge-report-close')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('bridge-loading-pdf-badge')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
