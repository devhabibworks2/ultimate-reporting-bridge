import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('client updates and clears identity context lifecycle', () async {
    final root = await Directory.systemTemp.createTemp('bridge-identity-');
    addTearDown(() => root.delete(recursive: true));
    final apiBaseUrl = Uri.parse('https://reports.example/');
    final legacy = TemplateCacheService(
      cacheRoot: bridgeTemplateCacheDirectoryForApi(
        bridgeRoot: root,
        apiBaseUrl: apiBaseUrl,
      ),
    );
    await legacy.putTemplate(
      const CachedTemplate(
        id: 'anonymous-legacy',
        type: 'sales_invoice',
        systemId: 7,
        document: <String, dynamic>{'meta': <String, dynamic>{}},
      ),
    );

    final client = ReportingBridgeClient(
      apiBaseUrl: apiBaseUrl,
      presenterEntryUrl: Uri.parse('https://reports.example/presenter/'),
      bridgeRoot: root,
      identityContext: BridgeIdentityContext(
        branchId: 'branch-a',
        userId: 'user-a',
        systemUnit: 'sales',
      ),
    );
    addTearDown(client.dispose);

    expect(client.identityContext.userId, 'user-a');
    await expectLater(
      client.listTemplates(),
      throwsA(
        isA<BridgeRuntimeException>().having(
          (error) => error.code,
          'code',
          BridgeTemplateSyncErrorCodes.offlineCacheUnavailable,
        ),
      ),
    );
    await client.updateIdentityContext(
      BridgeIdentityContext(
        branchId: 'branch-b',
        userId: 'user-b',
        systemUnit: 'inventory',
      ),
    );
    expect(
      client.identityContext,
      BridgeIdentityContext(
        branchId: 'branch-b',
        userId: 'user-b',
        systemUnit: 'inventory',
      ),
    );

    await client.clearIdentityContext();
    expect(client.identityContext.isEmpty, isTrue);
    expect((await client.listTemplates()).single.id, 'anonymous-legacy');
  });

  test(
    'header provider receives the active identity and system code',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bridge-header-context-',
      );
      addTearDown(() => root.delete(recursive: true));
      BridgeHeaderContext? captured;
      final client = ReportingBridgeClient(
        apiBaseUrl: Uri.parse('http://127.0.0.1:1/'),
        presenterEntryUrl: Uri.parse('http://127.0.0.1:1/presenter/'),
        bridgeRoot: root,
        timeout: const Duration(milliseconds: 50),
        identityContext: BridgeIdentityContext(
          branchId: 'branch-a',
          userId: 'user-a',
          systemUnit: 'sales',
        ),
        headersProvider: (context) {
          captured = context;
          return const <String, String>{'X-Tenant-Id': 'tenant-a'};
        },
      );
      addTearDown(client.dispose);

      await expectLater(
        client.syncTemplates(systemCode: 'motakamel_transactions'),
        throwsA(
          isA<BridgeRuntimeException>().having(
            (error) => error.code,
            'code',
            BridgeTemplateSyncErrorCodes.offlineCacheUnavailable,
          ),
        ),
      );
      expect(captured?.operation, BridgeHeaderOperation.syncTemplates);
      expect(captured?.systemCode, 'motakamel_transactions');
      expect(captured?.branchId, 'branch-a');
      expect(captured?.userId, 'user-a');
      expect(captured?.systemUnit, 'sales');
    },
  );
}
