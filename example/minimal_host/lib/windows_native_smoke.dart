// Native Windows acceptance runner, intentionally separate from the normal host.
// Build explicitly with -t lib/windows_native_smoke.dart --dart-define=URB_SMOKE_PDF_PATH=...
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  runApp(const MaterialApp(home: WindowsNativeSmokeScreen()));
}

class WindowsNativeSmokeScreen extends StatefulWidget {
  const WindowsNativeSmokeScreen({super.key});

  @override
  State<WindowsNativeSmokeScreen> createState() =>
      _WindowsNativeSmokeScreenState();
}

class _WindowsNativeSmokeScreenState extends State<WindowsNativeSmokeScreen> {
  Uint8List? _bytes;
  String _message = 'Loading local PDF';
  bool _busy = false;
  bool _previewReady = false;
  final File _events = File(
    '${Directory.systemTemp.path}/urb-bridge-windows-native-uat-events.log',
  );

  @override
  void initState() {
    super.initState();
    _readFixture();
  }

  Future<void> _record(String event) async {
    await _events.writeAsString(
      '${DateTime.now().toUtc().toIso8601String()} $event\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<void> _readFixture() async {
    const path = String.fromEnvironment('URB_SMOKE_PDF_PATH');
    try {
      if (path.isEmpty) throw StateError('URB_SMOKE_PDF_PATH must be set');
      final bytes = await File(path).readAsBytes();
      if (bytes.length < 8 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
        throw FormatException('Input must be a real PDF');
      }
      await _record('fixture_ready bytes=${bytes.length}');
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _message = 'PDF fixture loaded (${bytes.length} bytes)';
      });
    } catch (error) {
      await _record('fixture_error $error');
      if (mounted) setState(() => _message = 'Load failed: $error');
    }
  }

  Future<void> _save() async {
    final data = _bytes;
    if (data == null || _busy) return;
    setState(() => _busy = true);
    await _record('save_started');
    try {
      final saved = await const DefaultReportFilePlatform().savePdf(
        data,
        'urb-windows-uat.pdf',
      );
      await _record(saved ? 'save_completed' : 'save_cancelled');
      if (mounted) {
        setState(
          () => _message = saved ? 'Save: completed' : 'Save: cancelled',
        );
      }
    } catch (error) {
      await _record('save_error $error');
      if (mounted) setState(() => _message = 'Save: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    final data = _bytes;
    if (data == null || _busy) return;
    setState(() => _busy = true);
    await _record('print_started');
    try {
      final result = await const WindowsSystemReportPrintPlatform().printPdf(
        ReportPrintRequest(
          pdfBytes: data,
          filename: 'urb-windows-uat.pdf',
          jobId: 'urb-windows-smoke',
          documentTitle: 'URB Windows Native UAT',
          document: const ReportPrintDocumentMetadata(
            unit: 'mm',
            layout: 'Pages',
            size: 'A4',
            width: 210,
            height: 297,
            orientation: 'portrait',
            languageCode: 'en',
          ),
        ),
      );
      await _record(
        'print_result status=${result.status.name} error=${result.errorCode}',
      );
      if (mounted) {
        setState(
          () => _message =
              'Print: ${result.status.name} ${result.errorCode ?? ''}',
        );
      }
    } catch (error) {
      await _record('print_error $error');
      if (mounted) setState(() => _message = 'Print: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Scaffold(
      appBar: AppBar(title: const Text('URB Windows Native UAT')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton(
                  onPressed: bytes != null && !_busy ? _save : null,
                  child: const Text('Save PDF'),
                ),
                FilledButton(
                  onPressed: bytes != null && !_busy ? _print : null,
                  child: const Text('Print PDF'),
                ),
                Text(_message),
                Text('Preview: ${_previewReady ? 'ready' : 'pending'}'),
              ],
            ),
          ),
          Expanded(
            child: bytes == null
                ? const Center(child: Text('No PDF loaded'))
                : BridgePdfView(
                    bytes: bytes,
                    onDocumentLoaded: () {
                      if (_previewReady) return;
                      _record('preview_loaded');
                    },
                    onFirstFrameAfterDocument: () {
                      if (_previewReady) return;
                      _record('preview_first_frame');
                      if (mounted) setState(() => _previewReady = true);
                    },
                    onViewerError: (error) {
                      _record('preview_error $error');
                      if (mounted) setState(() => _message = 'Preview: $error');
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
