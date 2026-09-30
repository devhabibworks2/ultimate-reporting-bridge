import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  test(
    'emits one correlated timing trace across render export and viewer',
    () async {
      final records = <BridgeLogRecord>[];
      final transport = PresenterWebExportTransport(
        correlationIdFactory: () => 'timing-export-1',
      );
      final binding = PresenterSurfaceBinding(
        exportTransport: transport,
        diagnostics: BridgeDiagnostics(
          sink: records.add,
          minimumLevel: BridgeLogLevel.debug,
        ),
      );
      addTearDown(binding.dispose);

      binding.beginPreviewTiming('session-a');
      binding.attach(
        sessionId: 'session-a',
        templateName: 'Credit note',
        evaluateJavaScript: (_) async => null,
        reload: () async {},
        onLifecycle: (_) {},
      );

      binding.acceptMessage(<String, Object?>{
        'channel': bridgeWebMessageChannel,
        'method': BridgeWebMethods.presenterLifecycle,
        'event': 'onRenderStarted',
        'contractVersion': BridgeContract.payloadVersion,
        'payload': <String, Object?>{'sessionId': 'session-a'},
      });
      binding.acceptMessage(<String, Object?>{
        'channel': bridgeWebMessageChannel,
        'method': BridgeWebMethods.presenterLifecycle,
        'event': 'onRenderCompleted',
        'contractVersion': BridgeContract.payloadVersion,
        'payload': <String, Object?>{'sessionId': 'session-a'},
      });

      final exported = binding.exportPdf();
      await Future<void>.delayed(Duration.zero);
      binding.acceptMessage(<String, Object?>{
        'channel': bridgeWebMessageChannel,
        'type': 'result',
        'method': BridgeWebMethods.exportPdf,
        'correlationId': 'timing-export-1',
        'ok': true,
        'filename': 'credit.pdf',
        'base64': base64Encode(<int>[1, 2, 3]),
        'byteLength': 3,
      });
      await exported;

      binding.markViewerOpenStarted();
      binding.markViewerDocumentLoaded();
      binding.markViewerFirstFrame();

      final timing = records
          .where((record) => record.event.startsWith('previewTiming.'))
          .toList(growable: false);
      expect(
        timing.map((record) => record.event),
        containsAllInOrder(<String>[
          'previewTiming.surfaceStart',
          'previewTiming.renderStarted',
          'previewTiming.renderCompleted',
          'previewTiming.exportStarted',
          'previewTiming.exportCompleted',
          'previewTiming.viewerOpenStarted',
          'previewTiming.viewerDocumentLoaded',
          'previewTiming.viewerFirstFrame',
        ]),
      );
      for (final record in timing) {
        expect(record.category, BridgeLogCategory.presenter);
        expect(record.details['sessionId'], 'session-a');
        expect(record.details['elapsedUs'], isA<int>());
        expect(record.details['stageUs'], isA<int>());
      }
    },
  );
}
