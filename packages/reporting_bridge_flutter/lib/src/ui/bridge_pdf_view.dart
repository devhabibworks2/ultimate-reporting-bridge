import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

typedef BridgePdfDocumentFactory =
    Future<PdfDocument> Function(Uint8List bytes);

class BridgePdfView extends StatefulWidget {
  const BridgePdfView({
    super.key,
    required this.bytes,
    this.onViewerError,
    this.onDocumentOpenStarted,
    this.onDocumentLoaded,
    this.onFirstFrameAfterDocument,
    @visibleForTesting this.documentFactory,
  });

  final Uint8List bytes;
  final ValueChanged<Object>? onViewerError;
  final VoidCallback? onDocumentOpenStarted;
  final VoidCallback? onDocumentLoaded;
  final VoidCallback? onFirstFrameAfterDocument;

  @visibleForTesting
  final BridgePdfDocumentFactory? documentFactory;

  @override
  State<BridgePdfView> createState() => _BridgePdfViewState();
}

class _BridgePdfViewState extends State<BridgePdfView> {
  late PdfControllerPinch _controller;
  Object? _viewerError;
  Object? _documentFactoryError;

  @override
  void initState() {
    super.initState();
    _controller = _createController();
  }

  @override
  void didUpdateWidget(covariant BridgePdfView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes) ||
        oldWidget.documentFactory != widget.documentFactory) {
      _controller.dispose();
      _viewerError = null;
      _documentFactoryError = null;
      _controller = _createController();
    }
  }

  PdfControllerPinch _createController() {
    widget.onDocumentOpenStarted?.call();
    final factory = widget.documentFactory ?? PdfDocument.openData;
    final document = Future<PdfDocument>.sync(() => factory(widget.bytes)).then(
      (value) => value,
      onError: (Object error, StackTrace stackTrace) {
        _documentFactoryError = error;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    return PdfControllerPinch(document: document);
  }

  void _handleViewerError(Object error) {
    final reportedError = _documentFactoryError ?? error;
    widget.onViewerError?.call(reportedError);
    if (!mounted) return;
    setState(() {
      _viewerError = reportedError;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_viewerError != null) {
      return const Center(
        key: ValueKey<String>('bridge-pdf-error'),
        child: Text('PDF preview unavailable'),
      );
    }

    return PdfViewPinch(
      key: const Key('bridge-pdf-view'),
      controller: _controller,
      minScale: 0.5,
      maxScale: 8,
      onDocumentLoaded: (_) {
        widget.onDocumentLoaded?.call();
        if (widget.onFirstFrameAfterDocument != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onFirstFrameAfterDocument?.call();
          });
        }
      },
      onDocumentError: _handleViewerError,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
