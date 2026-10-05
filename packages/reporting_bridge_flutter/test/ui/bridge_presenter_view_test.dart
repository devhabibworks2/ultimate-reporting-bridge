import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  test('BridgePresenterView source contains no visible InAppWebView', () {
    final source = File(
      'lib/src/ui/bridge_presenter_view.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('return InAppWebView(')));
    expect(source, isNot(contains('initialUrlRequest: URLRequest')));
  });

  test(
    'BridgePresenterView forwards pdfPreview into default BridgePdfView',
    () {
      final source = File(
        'lib/src/ui/bridge_presenter_view.dart',
      ).readAsStringSync();
      expect(source, contains('previewConfig: widget.pdfPreview'));
    },
  );

  testWidgets('keeps internal loading spinner by default and can suppress it', (
    tester,
  ) async {
    Future<void> pump({required bool suppress}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BridgePresenterView(
            launch: _launch('loading'),
            templateName: 'Template',
            controller: _FakeController(),
            surfaceBinding: PresenterSurfaceBinding(),
            showInternalLoadingIndicator: !suppress,
            headlessSurfaceFactory: _FakeHeadlessSurface.new,
          ),
        ),
      );
      await tester.pump();
    }

    await pump(suppress: false);
    expect(find.byKey(const Key('bridge-pdf-loading')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await pump(suppress: true);
    expect(find.byKey(const Key('bridge-pdf-loading')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  test(
    'BridgePresenterView forwards viewer terminal callbacks in default PDF path',
    () {
      final source = File(
        'lib/src/ui/bridge_presenter_view.dart',
      ).readAsStringSync();
      expect(source, contains('widget.surfaceBinding.markViewerFirstFrame();'));
      expect(source, contains('widget.onViewerFirstFrame?.call();'));
      expect(source, contains('onViewerError: widget.onPreviewError'));
    },
  );

  testWidgets('starts headless runtime and renders exact cached PDF bytes', (
    tester,
  ) async {
    final bytes = Uint8List.fromList(<int>[9, 8, 7]);
    final cache = PresenterPdfExportCache();
    cache.bindSession('s1');
    await cache.resolve(
      () async => PresenterCachedPdf(bytes: bytes, filename: 'report.pdf'),
    );
    final timingRecords = <BridgeLogRecord>[];
    final binding = PresenterSurfaceBinding(
      cache: cache,
      diagnostics: BridgeDiagnostics(
        sink: timingRecords.add,
        minimumLevel: BridgeLogLevel.debug,
      ),
    );
    final surfaces = <_FakeHeadlessSurface>[];

    await tester.pumpWidget(
      MaterialApp(
        home: BridgePresenterView(
          launch: _launch('s1'),
          templateName: 'Template',
          controller: _FakeController(),
          surfaceBinding: binding,
          headlessSurfaceFactory: () {
            final surface = _FakeHeadlessSurface();
            surfaces.add(surface);
            return surface;
          },
          pdfViewBuilder: (_, value) => _BytesProbe(bytes: value),
        ),
      ),
    );
    await tester.pump();

    expect(surfaces, hasLength(1));
    expect(surfaces.single.startCalls, 1);
    expect(
      timingRecords.map((record) => record.event),
      contains('previewTiming.surfaceStart'),
    );
    final probe = tester.widget<_BytesProbe>(find.byType(_BytesProbe));
    expect(identical(probe.bytes, bytes), isTrue);
  });

  testWidgets('replacement reuses warm runtime and clears prior PDF', (
    tester,
  ) async {
    final cache = PresenterPdfExportCache();
    cache.bindSession('s1');
    await cache.resolve(
      () async => PresenterCachedPdf(
        bytes: Uint8List.fromList(<int>[1]),
        filename: 'old.pdf',
      ),
    );
    final binding = PresenterSurfaceBinding(cache: cache);
    final surfaces = <_FakeHeadlessSurface>[];

    Widget build(String sessionId) => MaterialApp(
      home: BridgePresenterView(
        launch: _launch(sessionId),
        templateName: 'Template',
        controller: _FakeController(),
        surfaceBinding: binding,
        headlessSurfaceFactory: () {
          final surface = _FakeHeadlessSurface();
          surfaces.add(surface);
          return surface;
        },
        pdfViewBuilder: (_, value) => _BytesProbe(bytes: value),
      ),
    );

    await tester.pumpWidget(build('s1'));
    await tester.pump();
    expect(binding.cachedPdf, isNotNull);

    await tester.pumpWidget(build('s2'));
    await tester.pump();
    await tester.pump();

    expect(surfaces, hasLength(1));
    expect(surfaces.single.startCalls, 2);
    expect(surfaces.single.shutdownCalls, 0);
    expect(binding.cachedPdf, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(surfaces.single.shutdownCalls, 1);
  });
}

PresenterSessionLaunch _launch(String sessionId) => PresenterSessionLaunch(
  presenterUrl: 'http://127.0.0.1/presenter?sessionId=$sessionId',
  sessionId: sessionId,
  presenterVersion: '1.0.0',
  presenterDevVersion: 1,
);

class _BytesProbe extends StatelessWidget {
  const _BytesProbe({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _FakeHeadlessSurface implements WarmableHeadlessPresenterSurface {
  int startCalls = 0;
  int shutdownCalls = 0;

  @override
  Future<void> start({
    required PresenterSessionLaunch launch,
    required String templateName,
    required ReportFlowController controller,
    required PresenterSurfaceBinding surfaceBinding,
  }) async {
    startCalls += 1;
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> warmUp() async {}

  @override
  Future<void> shutdown() async {
    shutdownCalls += 1;
  }
}

class _FakeController implements ReportFlowController {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
