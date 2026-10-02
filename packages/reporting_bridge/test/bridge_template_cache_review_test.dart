import 'dart:convert';
import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('skips corrupt cache files and keeps colliding ids distinct', () async {
    final root = await Directory.systemTemp.createTemp('bridge_cache_review_');
    addTearDown(() => root.delete(recursive: true));
    final cache = TemplateCacheService(cacheRoot: root);

    for (final id in <String>['a/b', 'a?b']) {
      await cache.putTemplate(
        CachedTemplate(
          code: id,
          type: 'invoice',
          document: const <String, dynamic>{'meta': <String, dynamic>{}},
        ),
      );
    }
    await File('${root.path}/broken.json').writeAsString('{broken');

    final templates = await cache.listTemplates();
    expect(templates.map((item) => item.templateCode).toSet(), <String>{
      'a/b',
      'a?b',
    });
    expect((await cache.getTemplateByCode('a/b'))?.templateCode, 'a/b');
    expect((await cache.getTemplateByCode('a?b'))?.templateCode, 'a?b');
  });

  test('filters approved headers without case sensitivity', () {
    expect(
      filterPresenterBridgeHeaders(const <String, String>{
        'authorization': '  Bearer token  ',
        'x-tenant-id': 'tenant',
        'X-Other': 'blocked',
      }),
      <String, String>{
        'Authorization': 'Bearer token',
        'X-Tenant-Id': 'tenant',
      },
    );
  });

  test('catalog metadata round-trips default template hints', () async {
    final root = await Directory.systemTemp.createTemp('bridge_cache_defaults_');
    addTearDown(() => root.delete(recursive: true));
    final cache = TemplateCacheService(cacheRoot: root);
    final hints = <TemplateDefaultHint>[
      const TemplateDefaultHint(
        reportType: 'sales_invoice',
        templateCode: 'INV-A5-AR',
        selectionReason: 'SYSTEM_DEFAULT',
      ),
      const TemplateDefaultHint(
        reportType: 'sales_return',
        templateCode: 'RET-A5-AR',
        selectionReason: 'BRANCH_DEFAULT',
      ),
    ];

    await cache.writeCatalogMetadata(
      TemplateCatalogMetadata(
        catalogRevision: 'rev-1',
        systemCode: 'erp',
        filterFingerprint: 'filter',
        extraFingerprint: 'extra',
        defaultTemplates: hints,
      ),
    );

    final metadata = await cache.readCatalogMetadata();
    expect(metadata, isNotNull);
    expect(metadata!.defaultTemplates.length, 2);
    expect(metadata.defaultTemplates[0].reportType, 'sales_invoice');
    expect(metadata.defaultTemplates[0].templateCode, 'INV-A5-AR');
    expect(metadata.defaultTemplates[0].selectionReason, 'SYSTEM_DEFAULT');
    expect(metadata.defaultTemplates[1].reportType, 'sales_return');
    expect(metadata.defaultTemplates[1].templateCode, 'RET-A5-AR');
    expect(metadata.defaultTemplates[1].selectionReason, 'BRANCH_DEFAULT');
  });

  test('old catalog metadata without defaultTemplates yields empty list', () async {
    final root = await Directory.systemTemp.createTemp('bridge_cache_legacy_');
    addTearDown(() => root.delete(recursive: true));
    final cache = TemplateCacheService(cacheRoot: root);
    await root.create(recursive: true);
    await File('${root.path}/.catalog.json').writeAsString(
      jsonEncode(<String, dynamic>{
        'catalogRevision': 'rev-legacy',
        'systemCode': 'erp',
        'filterFingerprint': 'filter',
        'extraFingerprint': 'extra',
        'cachedAt': DateTime.utc(2026, 10, 1).toIso8601String(),
      }),
    );

    final metadata = await cache.readCatalogMetadata();
    expect(metadata, isNotNull);
    expect(metadata!.defaultTemplates, isEmpty);
  });

  test('malformed defaultTemplates metadata is rejected', () async {
    final root = await Directory.systemTemp.createTemp('bridge_cache_bad_');
    addTearDown(() => root.delete(recursive: true));
    final cache = TemplateCacheService(cacheRoot: root);
    await root.create(recursive: true);

    Future<void> writeRaw(Object? defaults) async {
      await File('${root.path}/.catalog.json').writeAsString(
        jsonEncode(<String, dynamic>{
          'catalogRevision': 'rev-bad',
          'systemCode': 'erp',
          'filterFingerprint': 'filter',
          'extraFingerprint': 'extra',
          'defaultTemplates': defaults,
          'cachedAt': DateTime.utc(2026, 10, 1).toIso8601String(),
        }),
      );
    }

    await writeRaw(<Map<String, dynamic>>[
      <String, dynamic>{
        'reportType': 'sales_invoice',
        'templateCode': 'INV-A',
        'selectionReason': 'SYSTEM_DEFAULT',
      },
      <String, dynamic>{
        'reportType': 'sales_invoice',
        'templateCode': 'INV-B',
        'selectionReason': 'BRANCH_DEFAULT',
      },
    ]);
    expect(await cache.readCatalogMetadata(), isNull);

    await writeRaw(<Map<String, dynamic>>[
      <String, dynamic>{
        'reportType': 'sales_invoice',
        'templateCode': '',
        'selectionReason': 'SYSTEM_DEFAULT',
      },
    ]);
    expect(await cache.readCatalogMetadata(), isNull);
  });
}
