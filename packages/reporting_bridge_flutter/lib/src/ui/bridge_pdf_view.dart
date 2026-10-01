import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import 'bridge_pdf_preview_config.dart';

typedef BridgePdfDocumentFactory =
    Future<PdfDocument> Function(Uint8List bytes);

class BridgePdfView extends StatefulWidget {
  const BridgePdfView({
    super.key,
    required this.bytes,
    this.previewConfig = const BridgePdfPreviewConfig(),
    this.onViewerError,
    this.onDocumentOpenStarted,
    this.onDocumentLoaded,
    this.onFirstFrameAfterDocument,
    @visibleForTesting this.documentFactory,
  });

  final Uint8List bytes;
  final BridgePdfPreviewConfig previewConfig;
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
  Size? _viewportSize;
  bool _initialPositionApplied = false;

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
      _viewportSize = null;
      _initialPositionApplied = false;
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
    final controller = PdfControllerPinch(document: document);
    final scale = widget.previewConfig.initialScale;
    controller.value = Matrix4.diagonal3Values(scale, scale, 1);
    return controller;
  }

  void _applyInitialPreviewPosition() {
    if (_initialPositionApplied) return;

    final viewportSize = _viewportSize;
    if (viewportSize == null || viewportSize.isEmpty) return;

    final firstPageRect = _controller.getPageRect(1);
    if (firstPageRect == null) return;

    final scale = widget.previewConfig.initialScale;
    final scaledWidth = firstPageRect.width * scale;
    final scaledHeight = firstPageRect.height * scale;

    final dx = scaledWidth < viewportSize.width
        ? (viewportSize.width - scaledWidth) / 2 - firstPageRect.left * scale
        : 0.0;
    final dy = scaledHeight < viewportSize.height
        ? (viewportSize.height - scaledHeight) / 2 - firstPageRect.top * scale
        : 0.0;

    final transform = Matrix4.diagonal3Values(scale, scale, 1)
      ..setEntry(0, 3, dx)
      ..setEntry(1, 3, dy);
    _controller.value = transform;
    _initialPositionApplied = true;
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

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = constraints.biggest;
        return PdfViewPinch(
          key: const Key('bridge-pdf-view'),
          controller: _controller,
          minScale: widget.previewConfig.minScale,
          maxScale: widget.previewConfig.maxScale,
          onDocumentLoaded: (_) {
            widget.onDocumentLoaded?.call();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _applyInitialPreviewPosition();
              if (widget.onFirstFrameAfterDocument != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) widget.onFirstFrameAfterDocument?.call();
                });
              }
            });
          },
          onDocumentError: _handleViewerError,
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
