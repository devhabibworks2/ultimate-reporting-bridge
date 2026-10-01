import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfx/pdfx.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
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
    expect(view.controller.zoomRatio, closeTo(0.9, 0.001));
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

    expect(view.controller.zoomRatio, closeTo(0.9, 0.001));
    expect(view.controller.value.row0[3], greaterThan(0));
    expect(view.controller.value.row1[3], greaterThan(100));
  });

  testWidgets('PDF preview keeps a tall first page top-aligned', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final document = _FakePdfDocument(width: 400, height: 1000);

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

    expect(view.controller.zoomRatio, closeTo(0.9, 0.001));
    expect(view.controller.value.row1[3], closeTo(0, 0.001));
  });

  testWidgets('PDF preview allows zooming out below fit-width', (tester) async {
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
    expect(view.minScale, lessThan(1.0));
    expect(view.maxScale, greaterThanOrEqualTo(6.0));
    expect(view.onDocumentLoaded, isNotNull);
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
  }) async => null;
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
