import 'dart:convert';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('builds correlated request and accepts a direct result', () async {
    final transport = PresenterWebExportTransport(
      correlationIdFactory: () => 'direct-1',
    );
    addTearDown(transport.dispose);

    late String javaScript;
    final future = transport.exportPdf(
      evaluateJavaScript: (source) async => javaScript = source,
    );
    await Future<void>.delayed(Duration.zero);

    expect(_request(javaScript), <String, dynamic>{
      'channel': bridgeWebMessageChannel,
      'method': BridgeWebMethods.exportPdf,
      'correlationId': 'direct-1',
    });
    expect(transport.hasPendingExport, isTrue);
    expect(
      transport.acceptMessage(
        jsonEncode(<String, dynamic>{
          'channel': bridgeWebMessageChannel,
          'type': 'result',
          'method': BridgeWebMethods.exportPdf,
          'correlationId': 'direct-1',
          'ok': true,
          'filename': '../sales invoice',
          'base64': base64Encode(<int>[1, 2, 3]),
          'byteLength': 3,
        }),
      ),
      isTrue,
    );

    final result = await future;
    expect(result.correlationId, 'direct-1');
    expect(result.filename, '.._sales_invoice.pdf');
    expect(result.bytes, orderedEquals(<int>[1, 2, 3]));
    expect(transport.hasPendingExport, isFalse);
  });

  test(
    'assembles out-of-order chunks and accepts identical duplicates',
    () async {
      final transport = PresenterWebExportTransport(
        correlationIdFactory: () => 'chunks-1',
      );
      addTearDown(transport.dispose);
      final future = transport.exportPdf(evaluateJavaScript: (_) async {});
      await Future<void>.delayed(Duration.zero);

      final encoded = base64Encode(List<int>.generate(20, (index) => index));
      final chunks = <String>[
        encoded.substring(0, 8),
        encoded.substring(8, 16),
        encoded.substring(16),
      ];

      expect(transport.acceptMessage(_chunk('chunks-1', 2, chunks)), isTrue);
      expect(transport.acceptMessage(_chunk('chunks-1', 0, chunks)), isTrue);
      expect(transport.acceptMessage(_chunk('chunks-1', 0, chunks)), isTrue);
      expect(transport.acceptMessage(_chunk('chunks-1', 1, chunks)), isTrue);

      final result = await future;
      expect(result.filename, 'report_preview.pdf');
      expect(
        result.bytes,
        orderedEquals(List<int>.generate(20, (index) => index)),
      );
    },
  );

  test('rejects changed chunk metadata', () async {
    final transport = PresenterWebExportTransport(
      correlationIdFactory: () => 'chunks-bad',
    );
    addTearDown(transport.dispose);
    final future = transport.exportPdf(evaluateJavaScript: (_) async {});
    final expectation = expectLater(
      future,
      throwsA(
        isA<BridgeRuntimeException>().having(
          (error) => error.message,
          'message',
          contains('metadata changed'),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    transport.acceptMessage(<String, dynamic>{
      'channel': bridgeWebMessageChannel,
      'type': 'chunk',
      'method': BridgeWebMethods.exportPdf,
      'correlationId': 'chunks-bad',
      'ok': true,
      'filename': 'one.pdf',
      'chunkIndex': 0,
      'chunkCount': 2,
      'base64Chunk': 'AA',
      'byteLength': 2,
    });
    transport.acceptMessage(<String, dynamic>{
      'channel': bridgeWebMessageChannel,
      'type': 'chunk',
      'method': BridgeWebMethods.exportPdf,
      'correlationId': 'chunks-bad',
      'ok': true,
      'filename': 'two.pdf',
      'chunkIndex': 1,
      'chunkCount': 2,
      'base64Chunk': 'AA==',
      'byteLength': 2,
    });

    await expectation;
    expect(transport.hasPendingExport, isFalse);
  });

  test('enforces decoded size and declared byte length', () async {
    final transport = PresenterWebExportTransport(
      maxByteLength: 3,
      correlationIdFactory: () => 'too-large',
    );
    addTearDown(transport.dispose);
    final future = transport.exportPdf(evaluateJavaScript: (_) async {});
    final expectation = expectLater(
      future,
      throwsA(
        isA<BridgeRuntimeException>().having(
          (error) => error.message,
          'message',
          contains('allowed size'),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    transport.acceptMessage(<String, dynamic>{
      'channel': bridgeWebMessageChannel,
      'type': 'result',
      'method': BridgeWebMethods.exportPdf,
      'correlationId': 'too-large',
      'ok': true,
      'base64': base64Encode(<int>[1, 2, 3, 4]),
      'byteLength': 4,
    });
    await expectation;
  });

  test('ignores messages outside the active channel and correlation', () async {
    final transport = PresenterWebExportTransport(
      correlationIdFactory: () => 'active',
    );
    addTearDown(transport.dispose);
    final future = transport.exportPdf(evaluateJavaScript: (_) async {});
    await Future<void>.delayed(Duration.zero);

    expect(
      transport.acceptMessage(<String, dynamic>{
        'channel': 'other',
        'type': 'result',
        'method': BridgeWebMethods.exportPdf,
        'correlationId': 'active',
      }),
      isFalse,
    );
    expect(
      transport.acceptMessage(<String, dynamic>{
        'channel': bridgeWebMessageChannel,
        'type': 'result',
        'method': BridgeWebMethods.exportPdf,
        'correlationId': 'unknown',
      }),
      isFalse,
    );

    transport.acceptMessage(<String, dynamic>{
      'channel': bridgeWebMessageChannel,
      'type': 'result',
      'method': BridgeWebMethods.exportPdf,
      'correlationId': 'active',
      'ok': true,
      'base64': base64Encode(<int>[7]),
      'byteLength': 1,
    });
    expect((await future).bytes, orderedEquals(<int>[7]));
  });

  test('cleans pending state when JavaScript evaluation fails', () async {
    final transport = PresenterWebExportTransport(
      correlationIdFactory: () => 'send-failed',
    );
    addTearDown(transport.dispose);

    await expectLater(
      transport.exportPdf(
        evaluateJavaScript: (_) async => throw StateError('webview closed'),
      ),
      throwsA(
        isA<BridgeRuntimeException>().having(
          (error) => error.message,
          'message',
          contains('Failed to send'),
        ),
      ),
    );
    expect(transport.hasPendingExport, isFalse);
  });

  test('times out an unanswered export and clears pending state', () async {
    final transport = PresenterWebExportTransport(
      timeout: const Duration(milliseconds: 20),
      correlationIdFactory: () => 'timeout-1',
    );
    addTearDown(transport.dispose);

    final future = transport.exportPdf(evaluateJavaScript: (_) async {});
    await expectLater(
      future,
      throwsA(
        isA<BridgeRuntimeException>().having(
          (error) => error.message,
          'message',
          contains('Timed out'),
        ),
      ),
    );
    expect(transport.hasPendingExport, isFalse);
  });

  test('dispose fails pending calls and blocks new exports', () async {
    final transport = PresenterWebExportTransport(
      correlationIdFactory: () => 'dispose-1',
    );
    final future = transport.exportPdf(evaluateJavaScript: (_) async {});
    final expectation = expectLater(
      future,
      throwsA(isA<BridgeRuntimeException>()),
    );
    await Future<void>.delayed(Duration.zero);

    transport.dispose();
    await expectation;
    expect(transport.hasPendingExport, isFalse);
    await expectLater(
      transport.exportPdf(evaluateJavaScript: (_) async {}),
      throwsA(isA<BridgeRuntimeException>()),
    );
  });
}

Map<String, dynamic> _request(String source) {
  const prefix = 'window.postMessage(';
  const suffix = ', window.location.origin);';
  expect(source, startsWith(prefix));
  expect(source, endsWith(suffix));
  final encoded = source.substring(
    prefix.length,
    source.length - suffix.length,
  );
  return Map<String, dynamic>.from(jsonDecode(encoded) as Map);
}

Map<String, dynamic> _chunk(
  String correlationId,
  int index,
  List<String> chunks,
) {
  return <String, dynamic>{
    'channel': bridgeWebMessageChannel,
    'type': 'chunk',
    'method': BridgeWebMethods.exportPdf,
    'correlationId': correlationId,
    'ok': true,
    'filename': 'report_preview.pdf',
    'chunkIndex': index,
    'chunkCount': chunks.length,
    'base64Chunk': chunks[index],
    'byteLength': 20,
  };
}
