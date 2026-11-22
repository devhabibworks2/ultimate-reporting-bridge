import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfx/pdfx.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  group('mobile pinch preview', () {
    testWidgets('PDF preview opens slightly smaller than fit-width', (
      tester,
    ) async {
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

      await tester.pumpWidget(
        MaterialApp(
          home: BridgePdfView(
            bytes: bytes,
            documentFactory: (_) => Completer<PdfDocument>().future,
          ),
        ),
      );

      final view = tester.widget<PdfViewPinch>(
        find.byKey(const Key('bridge-pdf-view')),
      );
      expect(view.controller.value.row0[0], closeTo(0.97, 0.001));
      expect(view.controller.value.row1[1], closeTo(0.97, 0.001));
    });

    testWidgets('PDF preview centers the first page when it fits', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final document = _FakePdfDocument(width: 400, height: 500);

      await tester.pumpWidget(
        MaterialApp(
          home: BridgePdfView(
            bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
            documentFactory: (_) async => document,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      final view = tester.widget<PdfViewPinch>(
        find.byKey(const Key('bridge-pdf-view')),
      );

      expect(view.controller.zoomRatio, closeTo(0.97, 0.001));
      expect(view.controller.value.row0[3], greaterThan(0));
      expect(view.controller.value.row1[3], greaterThan(100));
    });

    testWidgets('PDF preview keeps a tall first page top-aligned', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Tall enough that after pdfx page insets and default initialScale 0.97
      // the first page still exceeds the viewport and stays top-aligned.
      final document = _FakePdfDocument(width: 400, height: 1200);

      await tester.pumpWidget(
        MaterialApp(
          home: BridgePdfView(
            bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
            documentFactory: (_) async => document,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      final view = tester.widget<PdfViewPinch>(
        find.byKey(const Key('bridge-pdf-view')),
      );

      expect(view.controller.zoomRatio, closeTo(0.97, 0.001));
      expect(view.controller.value.row1[3], closeTo(0, 0.001));
    });

    testWidgets('first-frame callback fires after document load post-frame', (
      tester,
    ) async {
      var firstFrames = 0;
      final document = _FakePdfDocument(width: 400, height: 500);

      await tester.pumpWidget(
        MaterialApp(
          home: BridgePdfView(
            bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
            documentFactory: (_) async => document,
            onFirstFrameAfterDocument: () => firstFrames += 1,
          ),
        ),
      );

      expect(firstFrames, 0);
      await tester.pump();
      expect(firstFrames, 0);
      await tester.pump();
      await tester.pump();
      expect(firstFrames, 1);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('PDF preview allows zooming out below fit-width', (
      tester,
    ) async {
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

      var openStarted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: BridgePdfView(
            bytes: bytes,
            documentFactory: (_) => Completer<PdfDocument>().future,
            onDocumentOpenStarted: () => openStarted = true,
            onDocumentLoaded: () {},
            onFirstFrameAfterDocument: () {},
          ),
        ),
      );

      expect(openStarted, isTrue);
      final view = tester.widget<PdfViewPinch>(
        find.byKey(const Key('bridge-pdf-view')),
      );
      expect(view.minScale, 0.6);
      expect(view.maxScale, 8.0);
      expect(view.onDocumentLoaded, isNotNull);
    });

    testWidgets('PDF preview applies custom BridgePdfPreviewConfig', (
      tester,
    ) async {
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

      await tester.pumpWidget(
        MaterialApp(
          home: BridgePdfView(
            bytes: bytes,
            previewConfig: const BridgePdfPreviewConfig(
              minScale: 0.5,
              maxScale: 4.0,
              initialScale: 0.75,
            ),
            documentFactory: (_) => Completer<PdfDocument>().future,
          ),
        ),
      );

      final view = tester.widget<PdfViewPinch>(
        find.byKey(const Key('bridge-pdf-view')),
      );
      expect(view.minScale, 0.5);
      expect(view.maxScale, 4.0);
      expect(view.controller.value.row0[0], closeTo(0.75, 0.001));
      expect(view.controller.value.row1[1], closeTo(0.75, 0.001));
    });

    testWidgets(
      'viewer receives exact bytes and contains viewer failure locally',
      (tester) async {
        final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
        Uint8List? openedBytes;
        Object? reportedError;
        final failure = Exception('bad pdf');

        await tester.pumpWidget(
          MaterialApp(
            home: BridgePdfView(
              bytes: bytes,
              documentFactory: (value) {
                openedBytes = value;
                return Future<PdfDocument>.error(failure);
              },
              onViewerError: (error) => reportedError = error,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(identical(openedBytes, bytes), isTrue);
        expect(reportedError, same(failure));
        expect(
          find.byKey(const ValueKey<String>('bridge-pdf-error')),
          findsOneWidget,
        );
      },
    );
  }, skip: Platform.isWindows);

  testWidgets('Windows builds non-pinch PdfView', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      MaterialApp(
        home: BridgePdfView(
          bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
          documentFactory: (_) => Completer<PdfDocument>().future,
        ),
      ),
    );
    expect(find.byType(PdfView), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('bridge-pdf-loading')),
      findsOneWidget,
    );
    expect(find.byType(PdfViewPinch), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows preserves exact PDF bytes and lifecycle callbacks', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    Uint8List? observed;
    var started = 0;
    var loaded = 0;
    var firstFrame = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BridgePdfView(
          bytes: bytes,
          documentFactory: (value) async {
            observed = value;
            return _FakePdfDocument(width: 400, height: 500);
          },
          onDocumentOpenStarted: () => started++,
          onDocumentLoaded: () => loaded++,
          onFirstFrameAfterDocument: () => firstFrame++,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(observed, same(bytes));
    expect(started, 1);
    expect(loaded, 1);
    expect(firstFrame, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows disposal safely ignores a pending PDF failure', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final pending = Completer<PdfDocument>();
    var errorCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BridgePdfView(
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
          documentFactory: (_) => pending.future,
          onViewerError: (_) => errorCalls++,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.completeError(StateError('late document failure'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(tester.takeException(), isNull);
    expect(errorCalls, 0);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows reports PDF open failures without attaching pdfx', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final error = StateError('invalid PDF');
    Object? reported;
    await tester.pumpWidget(
      MaterialApp(
        home: BridgePdfView(
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
          documentFactory: (_) => Future<PdfDocument>.error(error),
          onViewerError: (value) => reported = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(reported, same(error));
    expect(find.byType(PdfView), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('bridge-pdf-error')),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });
}

class _FakePdfDocument extends PdfDocument {
  _FakePdfDocument({required this.width, required this.height})
    : super(sourceName: 'test', id: 'test-doc', pagesCount: 1);

  final double width;
  final double height;

  @override
  Future<void> close() async {}

  @override
  Future<PdfPage> getPage(
    int pageNumber, {
    bool autoCloseAndroid = false,
  }) async => _FakePdfPage(
    document: this,
    width: width,
    height: height,
    autoCloseAndroid: autoCloseAndroid,
  );
}

class _FakePdfPage extends PdfPage {
  _FakePdfPage({
    required super.document,
    required super.width,
    required super.height,
    required super.autoCloseAndroid,
  }) : super(id: 'test-page', pageNumber: 1);

  @override
  Future<void> close() async {}

  @override
  Future<PdfPageTexture> createTexture() async => _FakePdfPageTexture();

  @override
  Future<PdfPageImage?> render({
    required double width,
    required double height,
    PdfPageImageFormat format = PdfPageImageFormat.jpeg,
    String? backgroundColor,
    Rect? cropRect,
    int quality = 100,
    bool forPrint = false,
    bool removeTempFile = true,
  }) async => _FakePdfPageImage();
}

class _FakePdfPageImage extends PdfPageImage {
  _FakePdfPageImage()
    : super(
        id: 'fake-png',
        pageNumber: 1,
        width: 1,
        height: 1,
        bytes: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
        ),
        format: PdfPageImageFormat.png,
        quality: 100,
      );
}

class _FakePdfPageTexture extends PdfPageTexture {
  _FakePdfPageTexture() : super(id: 1, pageId: 'test-page', pageNumber: 1);

  int? _textureWidth;
  int? _textureHeight;

  @override
  int? get textureWidth => _textureWidth;

  @override
  int? get textureHeight => _textureHeight;

  @override
  bool get hasUpdatedTexture => true;

  @override
  Future<void> dispose() async {}

  @override
  Future<bool> updateRect({
    required String documentId,
    int destinationX = 0,
    int destinationY = 0,
    int? width,
    int? height,
    int sourceX = 0,
    int sourceY = 0,
    int? textureWidth,
    int? textureHeight,
    double? fullWidth,
    double? fullHeight,
    String? backgroundColor,
    bool allowAntiAliasing = true,
  }) async {
    _textureWidth = textureWidth ?? width;
    _textureHeight = textureHeight ?? height;
    return true;
  }
}
