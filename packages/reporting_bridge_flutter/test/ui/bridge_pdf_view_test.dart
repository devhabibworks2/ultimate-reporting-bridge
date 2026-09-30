import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfx/pdfx.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
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
