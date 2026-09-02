import 'dart:convert';
import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('SelectedTemplate code persistence', () {
    test('persists code as durable identity alongside cached id', () {
      const selected = SelectedTemplate(
        id: '595',
        type: 'sales_invoice',
        code: 'INV-A5-AR',
        systemCode: 'system-a',
      );

      expect(selected.toMap(), <String, dynamic>{
        'id': '595',
        'type': 'sales_invoice',
        'code': 'INV-A5-AR',
        'systemCode': 'system-a',
      });
      expect(selected.toStorageMap(), <String, dynamic>{
        'selectedTemplates': <String, dynamic>{
          'type': 'sales_invoice',
          'code': 'INV-A5-AR',
          'systemCode': 'system-a',
        },
      });
      expect(
        SelectedTemplate.fromMap(selected.toStorageMap())?.code,
        'INV-A5-AR',
      );
      expect(selected.durableIdentity, 'system-a:INV-A5-AR');
      expect(
        SelectedTemplate.fromMap(selected.toStorageMap())?.systemCode,
        'system-a',
      );
    });

    test('legacy id-only storage still parses without code', () {
      final selected = SelectedTemplate.fromMap(<dynamic, dynamic>{
        'selectedTemplates': <dynamic, dynamic>{'id': '34', 'type': 'invoice'},
      });
      expect(selected?.id, '34');
      expect(selected?.code, isNull);
      expect(selected?.durableIdentity, '34');
    });

    test('refuses or clears incomplete durable writes', () async {
      const incomplete = SelectedTemplate(
        id: '595',
        type: 'sales_invoice',
        code: 'INV-A5-AR',
      );
      expect(incomplete.toStorageMap, throwsStateError);

      final temp = await Directory.systemTemp.createTemp(
        'bridge_sel_incomplete_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final cache = TemplateCacheService(cacheRoot: temp);
      await cache.writeSelectedTemplate(
        const SelectedTemplate(
          id: '595',
          type: 'sales_invoice',
          code: 'INV-A5-AR',
          systemCode: 'system-a',
        ),
      );

      await cache.writeSelectedTemplate(incomplete);

      expect(await File('${temp.path}/.selection.json').exists(), isFalse);
    });

    test('cached template selection carries its system code', () {
      const template = CachedTemplate(
        id: '595',
        type: 'sales_invoice',
        code: 'INV-A5-AR',
        systemCode: 'system-a',
        document: <String, dynamic>{},
      );

      expect(template.selectedTemplate.systemCode, 'system-a');
      expect(template.selectedTemplate.toStorageMap(), <String, dynamic>{
        'selectedTemplates': <String, dynamic>{
          'type': 'sales_invoice',
          'code': 'INV-A5-AR',
          'systemCode': 'system-a',
        },
      });
    });
  });

  group('SelectedTemplate legacy migration', () {
    final catalog = <CachedTemplate>[
      const CachedTemplate(
        id: '595',
        type: 'sales_invoice',
        code: 'INV-A5-AR',
        name: 'Sales Invoice A5',
        document: <String, dynamic>{
          'meta': <String, dynamic>{
            'code': 'INV-A5-AR',
            'name': 'Sales Invoice A5',
          },
          'page': <String, dynamic>{
            'size': 'A5',
            'language': 'ar',
            'orientation': 'portrait',
            'layout': 'Pages',
          },
        },
      ),
      const CachedTemplate(
        id: '596',
        type: 'sales_invoice',
        code: 'INV-A4-EN',
        name: 'Sales Invoice A4',
        document: <String, dynamic>{
          'meta': <String, dynamic>{'code': 'INV-A4-EN'},
        },
      ),
    ];

    List<SelectedTemplateCatalogEntry> entriesFor(
      List<CachedTemplate> templates,
    ) {
      return templates
          .map(
            (template) => SelectedTemplateCatalogEntry(
              id: template.id,
              type: template.type,
              code: template.templateCode,
              systemCode: 'system-a',
            ),
          )
          .toList(growable: false);
    }

    test('exact legacy id match persists that item code', () {
      const legacy = SelectedTemplate(id: '595', type: 'sales_invoice');
      final migrated = SelectedTemplate.migrateLegacyId(
        legacy: legacy,
        catalog: entriesFor(catalog),
        systemCode: 'system-a',
      );
      expect(migrated, isNotNull);
      expect(migrated!.code, 'INV-A5-AR');
      expect(migrated.id, '595');
      expect(migrated.type, 'sales_invoice');
      expect(migrated.systemCode, 'system-a');
    });

    test('exact legacy id adopts catalog type when legacy type is stale', () {
      const legacy = SelectedTemplate(id: '595', type: 'stale_invoice_type');
      final migrated = SelectedTemplate.migrateLegacyId(
        legacy: legacy,
        catalog: entriesFor(catalog),
        systemCode: 'system-a',
      );

      expect(migrated?.id, '595');
      expect(migrated?.type, 'sales_invoice');
      expect(migrated?.code, 'INV-A5-AR');
      expect(migrated?.systemCode, 'system-a');
    });

    test('coded selection adopts catalog type when stored type is stale', () {
      const coded = SelectedTemplate(
        id: 'stale-id',
        type: 'stale_invoice_type',
        code: 'INV-A5-AR',
        systemCode: 'system-a',
      );
      final migrated = SelectedTemplate.migrateLegacyId(
        legacy: coded,
        catalog: entriesFor(catalog),
        systemCode: 'system-a',
      );

      expect(migrated?.id, '595');
      expect(migrated?.type, 'sales_invoice');
      expect(migrated?.code, 'INV-A5-AR');
      expect(migrated?.systemCode, 'system-a');
    });

    test('missing legacy id clears selection', () {
      const legacy = SelectedTemplate(id: '999', type: 'sales_invoice');
      final migrated = SelectedTemplate.migrateLegacyId(
        legacy: legacy,
        catalog: entriesFor(catalog),
        systemCode: 'system-a',
      );
      expect(migrated, isNull);
    });

    test('never falls back by name report type or position', () {
      const legacy = SelectedTemplate(id: '999', type: 'sales_invoice');
      final migrated = SelectedTemplate.migrateLegacyId(
        legacy: legacy,
        catalog: entriesFor(catalog),
        systemCode: 'system-a',
      );
      expect(migrated, isNull);

      // Idempotent: already-coded selection keeps code without guessing.
      const coded = SelectedTemplate(
        id: '595',
        type: 'sales_invoice',
        code: 'INV-A5-AR',
      );
      final again = SelectedTemplate.migrateLegacyId(
        legacy: coded,
        catalog: entriesFor(catalog),
        systemCode: 'system-a',
      );
      expect(again?.code, 'INV-A5-AR');
      expect(again?.id, '595');
    });

    test('legacy id migration rewrites actual preference JSON', () async {
      final temp = await Directory.systemTemp.createTemp('bridge_sel_migrate_');
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
        catalog: catalog,
        systemCode: 'system-a',
      );

      expect(migrated?.code, 'INV-A5-AR');
      final persisted =
          jsonDecode(await File('${temp.path}/.selection.json').readAsString())
              as Map<String, dynamic>;
      expect(persisted, <String, dynamic>{
        'selectedTemplates': <String, dynamic>{
          'type': 'sales_invoice',
          'code': 'INV-A5-AR',
          'systemCode': 'system-a',
        },
      });
    });

    test('stale legacy id deletes actual preference JSON', () async {
      final temp = await Directory.systemTemp.createTemp('bridge_sel_stale_');
      addTearDown(() => temp.delete(recursive: true));
      final cache = TemplateCacheService(cacheRoot: temp);
      await temp.create(recursive: true);
      await File('${temp.path}/.selection.json').writeAsString(
        jsonEncode(<String, dynamic>{
          'selectedTemplates': <String, dynamic>{
            'id': '999',
            'type': 'sales_invoice',
          },
        }),
      );

      final migrated = await cache.migrateSelectedTemplate(
        catalog: catalog,
        systemCode: 'system-a',
      );

      expect(migrated, isNull);
      expect(await File('${temp.path}/.selection.json').exists(), isFalse);
    });
  });

  group('TemplateSelectionResolver code matching', () {
    test('resolves stored selection by code within system catalog', () async {
      final temp = await Directory.systemTemp.createTemp('bridge_code_sel_');
      addTearDown(() => temp.delete(recursive: true));
      final cache = TemplateCacheService(cacheRoot: temp);
      final resolver = TemplateSelectionResolver(cache: cache);

      await cache.putTemplate(
        const CachedTemplate(
          id: '10',
          type: 'sales_invoice',
          systemId: 1,
          code: 'INV-A5-AR',
          document: <String, dynamic>{
            'meta': <String, dynamic>{'version': '1'},
          },
          minPresenterDevVersion: 1,
        ),
      );
      await cache.putTemplate(
        const CachedTemplate(
          id: '44',
          type: 'sales_invoice',
          systemId: 2,
          code: 'INV-A5-AR',
          document: <String, dynamic>{
            'meta': <String, dynamic>{'version': '1'},
          },
          minPresenterDevVersion: 1,
        ),
      );
      await cache.writeCatalogMetadata(
        TemplateCatalogMetadata(
          catalogRevision: 'system-a-revision',
          systemCode: 'system-a',
          systemId: 1,
          filterFingerprint: 'filter',
          extraFingerprint: 'extra',
        ),
      );

      final byCode = await resolver.resolveSelectedTemplate(
        reportType: 'sales_invoice',
        systemCode: 'system-a',
        presenterDevVersion: 1,
        storedSelection: const SelectedTemplate(
          id: '0',
          type: 'sales_invoice',
          code: 'INV-A5-AR',
          systemCode: 'system-a',
        ),
      );
      expect(byCode.status, 'stored-selected');
      expect(byCode.template?.id, '10');
      expect(byCode.template?.code, 'INV-A5-AR');
    });

    test('does not resolve a selection from another system', () async {
      final temp = await Directory.systemTemp.createTemp('bridge_code_scope_');
      addTearDown(() => temp.delete(recursive: true));
      final cache = TemplateCacheService(cacheRoot: temp);
      final resolver = TemplateSelectionResolver(cache: cache);
      await cache.putTemplate(
        const CachedTemplate(
          id: '44',
          type: 'sales_invoice',
          systemId: 2,
          code: 'INV-A5-AR',
          document: <String, dynamic>{'meta': <String, dynamic>{}},
        ),
      );
      await cache.writeCatalogMetadata(
        TemplateCatalogMetadata(
          catalogRevision: 'system-b-revision',
          systemCode: 'system-b',
          systemId: 2,
          filterFingerprint: 'filter',
          extraFingerprint: 'extra',
        ),
      );

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

      expect(result.status, 'auto-selected');
      expect(result.template?.id, '44');
    });
  });
}
