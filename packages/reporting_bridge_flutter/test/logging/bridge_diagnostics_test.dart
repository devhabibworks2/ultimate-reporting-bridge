import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  test('safeBridgeLogUri redacts user info, query values, and fragments', () {
    final safe = safeBridgeLogUri(
      Uri.parse(
        'https://user:password@example.test/path?token=secret&branch=01#private',
      ),
    );

    expect(safe, startsWith('https://example.test/path?'));
    expect(safe, contains('branch=<redacted>'));
    expect(safe, contains('token=<redacted>'));
    expect(safe, isNot(contains('password')));
    expect(safe, isNot(contains('secret')));
    expect(safe, isNot(contains('private')));
    expect(safe, isNot(contains('01')));
  });

  test('traceApi records start and success without request secrets', () async {
    final records = <BridgeLogRecord>[];
    final diagnostics = BridgeDiagnostics(sink: records.add);

    final value = await diagnostics.traceApi<int>(
      operation: 'queryTemplates',
      method: 'POST',
      uri: Uri.parse(
        'https://example.test/UltimateReport/backend/api/'
        'presenter/templates/query?token=private',
      ),
      details: const <String, Object?>{'reportType': 'sales_invoice'},
      action: () async => 7,
    );

    expect(value, 7);
    expect(records.map((record) => record.event), <String>[
      'queryTemplates.start',
      'queryTemplates.success',
    ]);
    final rendered = records.map((record) => record.toConsoleLine()).join('\n');
    expect(rendered, contains('[URB][Bridge][API]'));
    expect(rendered, contains('token=<redacted>'));
    expect(rendered, isNot(contains('private')));
    expect(records.last.details['durationMs'], isA<int>());
  });

  test('traceApi preserves failures and records the original error', () async {
    final records = <BridgeLogRecord>[];
    final diagnostics = BridgeDiagnostics(sink: records.add);
    final failure = StateError(
      'transport failed token=very-secret at '
      'https://example.test/p?access_token=hidden',
    );

    await expectLater(
      diagnostics.traceApi<void>(
        operation: 'fetchSystems',
        method: 'GET',
        uri: Uri.parse('https://example.test/presenter/systems'),
        action: () => Future<void>.error(failure),
      ),
      throwsA(same(failure)),
    );

    expect(records.last.event, 'fetchSystems.error');
    expect(records.last.level, BridgeLogLevel.error);
    expect(records.last.error, same(failure));
    expect(records.last.stackTrace, isNotNull);
    final console = records.last.toConsoleLine();
    expect(console, contains('transport failed'));
    expect(console, contains('token=<redacted>'));
    expect(console, contains('access_token=<redacted>'));
    expect(console, isNot(contains('very-secret')));
    expect(console, isNot(contains('hidden')));
  });

  test('diagnostic sink failures never change Bridge behavior', () async {
    final diagnostics = BridgeDiagnostics(
      sink: (_) => throw StateError('logger failed'),
    );

    final result = await diagnostics.tracePrint<int>(
      operation: 'printPdf',
      action: () async => 11,
    );

    expect(result, 11);
  });

  test('flow failure records code and diagnostic', () {
    final records = <BridgeLogRecord>[];
    final diagnostics = BridgeDiagnostics(sink: records.add);

    diagnostics.flowFailure(
      operation: 'previewing',
      code: 'previewLoadFailed',
      diagnostic: 'WebView failed at https://example.test/p?token=secret',
    );

    expect(records, hasLength(1));
    expect(records.single.category, BridgeLogCategory.flow);
    expect(records.single.event, 'previewing.failure');
    expect(records.single.details['code'], 'previewLoadFailed');
    final console = records.single.toConsoleLine();
    expect(console, contains('token=<redacted>'));
    expect(console, isNot(contains('secret')));
  });
}
