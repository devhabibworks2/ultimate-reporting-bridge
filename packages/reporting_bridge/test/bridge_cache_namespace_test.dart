import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('cache namespace preserves the existing FNV-1a 64-bit values', () {
    expect(
      bridgeTemplateCacheNamespace(Uri.parse('https://one.example/api/')),
      'c3fd156e7c443b53',
    );
    expect(
      bridgeTemplateCacheNamespace(Uri.parse('https://two.example/api/')),
      '228b50f58cf85ec1',
    );
    expect(
      bridgeTemplateCacheNamespace(Uri.parse('http://127.0.0.1:8000/')),
      '5c9d706692dacb04',
    );
  });

  test('equivalent normalized API URLs keep the same namespace', () {
    expect(
      bridgeTemplateCacheNamespace(Uri.parse('HTTPS://Example.COM/api')),
      '4d0e0d4c5e11f3ce',
    );
    expect(
      bridgeTemplateCacheNamespace(Uri.parse('https://example.com/api/')),
      '4d0e0d4c5e11f3ce',
    );
  });

  test('catalog scope isolates every identity dimension', () {
    BridgeTemplateCacheScope scope({
      String? tenantId = 'tenant-a',
      String? branchId = 'branch-a',
      String? userId = 'user-a',
      String? systemUnit = 'sales',
      String systemCode = 'motakamel_transactions',
    }) {
      return BridgeTemplateCacheScope(
        apiBaseUrl: Uri.parse('HTTPS://Reports.Example/api'),
        tenantId: tenantId,
        identity: BridgeIdentityContext(
          branchId: branchId,
          userId: userId,
          systemUnit: systemUnit,
        ),
        systemCode: systemCode,
        filter: TemplateSyncFilter(
          reportTypes: const <String>['sales_invoice'],
        ),
        extra: const <String, Object?>{'mode': 'normal'},
      );
    }

    final base = scope();
    expect(scope(tenantId: 'tenant-b').namespace, isNot(base.namespace));
    expect(scope(branchId: 'branch-b').namespace, isNot(base.namespace));
    expect(scope(userId: 'user-b').namespace, isNot(base.namespace));
    expect(scope(systemUnit: 'inventory').namespace, isNot(base.namespace));
    expect(
      scope(systemCode: 'another_system').namespace,
      isNot(base.namespace),
    );
  });

  test('scope fingerprints are stable and unsafe values never enter paths', () {
    final first = BridgeTemplateCacheScope(
      apiBaseUrl: Uri.parse('https://reports.example/api'),
      tenantId: '../tenant/one',
      identity: BridgeIdentityContext(
        branchId: 'branch/../../one',
        userId: 'user\\one',
        systemUnit: 'sales:unit',
      ),
      systemCode: 'motakamel_transactions',
      filter: TemplateSyncFilter(
        reportTypes: const <String>['sales_invoice', 'payment_voucher'],
      ),
      extra: const <String, Object?>{
        'b': <String, Object?>{'y': 2, 'x': 1},
        'a': true,
      },
    );
    final second = BridgeTemplateCacheScope(
      apiBaseUrl: Uri.parse('HTTPS://REPORTS.EXAMPLE/api/'),
      tenantId: '../tenant/one',
      identity: BridgeIdentityContext(
        branchId: 'branch/../../one',
        userId: 'user\\one',
        systemUnit: 'sales:unit',
      ),
      systemCode: 'motakamel_transactions',
      filter: TemplateSyncFilter(
        reportTypes: const <String>['payment_voucher', 'sales_invoice'],
      ),
      extra: const <String, Object?>{
        'a': true,
        'b': <String, Object?>{'x': 1, 'y': 2},
      },
    );

    expect(first, second);
    final path = bridgeTemplateCacheDirectoryForScope(
      bridgeRoot: Directory('/safe/root'),
      scope: first,
    ).path;
    expect(path, isNot(contains('../tenant')));
    expect(path, isNot(contains('branch/')));
    expect(path, isNot(contains('user\\one')));
    expect(path, contains(RegExp(r'catalog_[0-9a-f]{16}$')));
  });

  test('old base-URL cache migrates only to anonymous legacy scope', () async {
    final root = await Directory.systemTemp.createTemp('bridge-cache-migrate-');
    addTearDown(() => root.delete(recursive: true));
    final api = Uri.parse('https://reports.example/api/');
    final oldCache = TemplateCacheService(
      cacheRoot: bridgeTemplateCacheDirectoryForApi(
        bridgeRoot: root,
        apiBaseUrl: api,
      ),
    );
    await oldCache.putTemplate(_template('legacy', 7));

    await migrateLegacyBridgeTemplateCacheForApi(
      bridgeRoot: root,
      apiBaseUrl: api,
    );

    final anonymous = TemplateCacheService(
      cacheRoot: bridgeAnonymousLegacyTemplateCacheDirectoryForApi(
        bridgeRoot: root,
        apiBaseUrl: api,
      ),
    );
    expect((await anonymous.listTemplates()).single.id, 'legacy');
    expect(await anonymous.hasCatalog, isTrue);

    final authenticatedScope = BridgeTemplateCacheScope(
      apiBaseUrl: api,
      tenantId: 'tenant-a',
      identity: BridgeIdentityContext(userId: 'new-user'),
      systemCode: 'motakamel_transactions',
      filter: TemplateSyncFilter(),
      extra: const <String, Object?>{},
    );
    final authenticated = TemplateCacheService(
      cacheRoot: bridgeTemplateCacheDirectoryForScope(
        bridgeRoot: root,
        scope: authenticatedScope,
      ),
    );
    expect(await authenticated.hasCatalog, isFalse);
    expect(await authenticated.listTemplates(), isEmpty);
  });
}

CachedTemplate _template(String id, int systemId) => CachedTemplate(
  id: id,
  type: 'sales_invoice',
  systemId: systemId,
  document: const <String, dynamic>{
    'schemaVersion': '1.0.0',
    'meta': <String, dynamic>{},
    'page': <String, dynamic>{},
    'styleTokens': <String, dynamic>{},
    'assets': <Object?>[],
    'layers': <Object?>[],
    'elements': <Object?>[],
  },
);
