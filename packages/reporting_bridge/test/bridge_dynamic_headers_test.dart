import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test(
    'resolves a fresh approved header snapshot for each operation',
    () async {
      var calls = 0;
      Map<String, String> provider(BridgeHeaderContext context) {
        calls += 1;
        return <String, String>{
          'Authorization': 'Bearer ${context.operation.name}-$calls',
          'X-Tenant-Id': '${context.systemId ?? 0}',
          'Not-Approved': 'discarded',
        };
      }

      final context = BridgeHeaderContext(
        operation: BridgeHeaderOperation.syncTemplates,
        apiBaseUrl: Uri.parse('https://example.test/api/'),
        systemId: 7,
      );

      final first = await resolveBridgeHeaders(
        context: context,
        provider: provider,
      );
      final second = await resolveBridgeHeaders(
        context: context,
        provider: provider,
      );

      expect(calls, 2);
      expect(first['Authorization'], 'Bearer syncTemplates-1');
      expect(second['Authorization'], 'Bearer syncTemplates-2');
      expect(first['X-Tenant-Id'], '7');
      expect(first.containsKey('Not-Approved'), isFalse);
      expect(() => first['Authorization'] = 'mutated', throwsUnsupportedError);
    },
  );

  test('rejects header line-break injection before filtering', () async {
    final context = BridgeHeaderContext(
      operation: BridgeHeaderOperation.probeApi,
      apiBaseUrl: Uri.parse('https://example.test/api/'),
    );

    await expectLater(
      resolveBridgeHeaders(
        context: context,
        provider: (_) => const <String, String>{
          'Authorization': 'Bearer safe\r\nInjected: value',
        },
      ),
      throwsA(isA<BridgeRuntimeException>()),
    );
  });
}
