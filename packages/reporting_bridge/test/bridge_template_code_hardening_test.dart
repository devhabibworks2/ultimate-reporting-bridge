import 'dart:convert';
import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('Code-based presenter catalog validation', () {
    test('rejects a query item missing top-level Template Code', () async {
      final item = _queryTemplate(code: null, metaCode: 'INV-A5-AR');
      await _expectCatalogRejected(item);
    });

    test('rejects a query item missing document.meta.code', () async {
      final item = _queryTemplate(code: 'INV-A5-AR', metaCode: null);
      await _expectCatalogRejected(item);
    });

    test(
      'rejects a query item whose Code disagrees with document.meta.code',
      () async {
        final item = _queryTemplate(code: 'INV-A5-AR', metaCode: 'INV-A4-EN');
        await _expectCatalogRejected(item);
      },
    );
  });

  test(
    'legacy numeric id is never persisted as durable Template Code',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'bridge_no_id_as_code_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final cache = TemplateCacheService(cacheRoot: temp);
      await temp.create(recursive: true);
      await File('${temp.path}/.selection.json').writeAsString(
        jsonEncode(<String, dynamic>{
          'selectedTemplates': <String, dynamic>{
            'id': '595',
            'type': 'sales_invoice',
          },
        }),
      );

      final migrated = await cache.migrateSelectedTemplate(
        catalog: const <CachedTemplate>[
          CachedTemplate(
            id: '595',
            type: 'sales_invoice',
            systemId: 7,
            systemCode: 'system-a',
            document: <String, dynamic>{'meta': <String, dynamic>{}},
          ),
        ],
        systemCode: 'system-a',
      );

      expect(migrated, isNull);
      expect(await File('${temp.path}/.selection.json').exists(), isFalse);
    },
  );

  group('stale stored selection handling', () {
    test(
      'wrong-system stored selection never auto-selects another template',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'bridge_stale_system_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final cache = TemplateCacheService(cacheRoot: temp);
        await _putSingleTemplate(
          cache,
          systemId: 2,
          systemCode: 'system-b',
          code: 'INV-A5-AR',
        );
        final resolver = TemplateSelectionResolver(cache: cache);

        final result = await resolver.resolveSelectedTemplate(
          reportType: 'sales_invoice',
          systemCode: 'system-b',
          storedSelection: const SelectedTemplate(
            id: '10',
            type: 'sales_invoice',
            code: 'INV-A5-AR',
            systemCode: 'system-a',
          ),
        );

        expect(result.status, 'selection-required');
        expect(result.template, isNull);
        expect(result.errorCode, 'STALE_TEMPLATE_SELECTION');
      },
    );

    test(
      'missing stored Code never auto-selects a different compatible template',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'bridge_stale_code_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final cache = TemplateCacheService(cacheRoot: temp);
        await _putSingleTemplate(
          cache,
          systemId: 1,
          systemCode: 'system-a',
          code: 'INV-NEW',
        );
        final resolver = TemplateSelectionResolver(cache: cache);

        final result = await resolver.resolveSelectedTemplate(
          reportType: 'sales_invoice',
          systemCode: 'system-a',
          storedSelection: const SelectedTemplate(
            id: '10',
            type: 'sales_invoice',
            code: 'INV-OLD',
            systemCode: 'system-a',
          ),
        );

        expect(result.status, 'selection-required');
        expect(result.template, isNull);
        expect(result.errorCode, 'STALE_TEMPLATE_SELECTION');
      },
    );

    test(
      'fresh user with no stored selection may still auto-select a sole template',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'bridge_fresh_auto_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final cache = TemplateCacheService(cacheRoot: temp);
        await _putSingleTemplate(
          cache,
          systemId: 1,
          systemCode: 'system-a',
          code: 'INV-A5-AR',
        );
        final resolver = TemplateSelectionResolver(cache: cache);

        final result = await resolver.resolveSelectedTemplate(
          reportType: 'sales_invoice',
          systemCode: 'system-a',
        );

        expect(result.status, 'auto-selected');
        expect(result.template?.templateCode, 'INV-A5-AR');
      },
    );
  });
}

Future<void> _expectCatalogRejected(Map<String, dynamic> item) async {
  final root = await Directory.systemTemp.createTemp('bridge_catalog_code_');
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() async {
    await server.close(force: true);
    if (await root.exists()) await root.delete(recursive: true);
  });

  server.listen((request) async {
    await utf8.decoder.bind(request).join();
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(_queryEnvelope(item)));
    await request.response.close();
  });

  final gateway = PresenterServerGateway(
    apiBaseUrl: Uri.parse(
      'http://${server.address.address}:${server.port}/api/',
    ),
    bridgeRoot: root,
  );

  await expectLater(
    gateway.syncTemplates(query: TemplateQueryRequest(systemCode: 'system-a')),
    throwsA(
      isA<BridgeRuntimeException>().having(
        (error) => error.code,
        'code',
        BridgeTemplateSyncErrorCodes.templateCatalogInvalid,
      ),
    ),
  );
}

Future<void> _putSingleTemplate(
  TemplateCacheService cache, {
  required int systemId,
  required String systemCode,
  required String code,
}) async {
  await cache.putTemplate(
    CachedTemplate(
      id: '$systemId-$code',
      type: 'sales_invoice',
      systemId: systemId,
      systemCode: systemCode,
      code: code,
      document: <String, dynamic>{
        'meta': <String, dynamic>{'code': code, 'version': '1'},
      },
      minPresenterDevVersion: 1,
    ),
  );
  await cache.writeCatalogMetadata(
    TemplateCatalogMetadata(
      catalogRevision: '$systemCode-revision',
      systemCode: systemCode,
      systemId: systemId,
      filterFingerprint: 'filter',
      extraFingerprint: 'extra',
    ),
  );
}

Map<String, dynamic> _queryEnvelope(Map<String, dynamic> item) {
  return <String, dynamic>{
    'success': true,
    'message': 'OK',
    'data': <String, dynamic>{
      'catalogRevision': 'revision-1',
      'system': <String, dynamic>{
        'id': 7,
        'code': 'system-a',
        'name': 'System A',
      },
      'appliedFilter': <String, dynamic>{
        'reportTypes': <String>['all'],
        'layouts': <String>['all'],
        'sizes': <String>['all'],
        'languages': <String>['all'],
        'units': <String>['all'],
        'orientations': <String>['all'],
      },
      'count': 1,
      'items': <Map<String, dynamic>>[item],
    },
  };
}

Map<String, dynamic> _queryTemplate({
  required String? code,
  required String? metaCode,
}) {
  return <String, dynamic>{
    'id': '595',
    'systemId': 7,
    if (code != null) 'code': code,
    'name': 'Sales Invoice A5',
    'description': 'Template',
    'reportType': 'sales_invoice',
    'publishedVersionNo': 1,
    'metadata': <String, dynamic>{
      'layout': 'Pages',
      'size': 'A5',
      'languages': <String>['ar'],
      'unit': 'mm',
      'orientation': 'portrait',
    },
    'compatibility': <String, dynamic>{},
    'document': <String, dynamic>{
      'schemaVersion': '1.0.0',
      'meta': <String, dynamic>{
        'name': 'Sales Invoice A5',
        if (metaCode != null) 'code': metaCode,
      },
      'page': <String, dynamic>{},
      'styleTokens': <String, dynamic>{},
      'assets': <Object?>[],
      'layers': <Object?>[],
      'elements': <Object?>[],
    },
  };
}
