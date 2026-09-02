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
      );

      expect(selected.toMap(), <String, dynamic>{
        'id': '595',
        'type': 'sales_invoice',
        'code': 'INV-A5-AR',
      });
      expect(selected.toStorageMap(), <String, dynamic>{
        'selectedTemplates': <String, dynamic>{
          'id': '595',
          'type': 'sales_invoice',
          'code': 'INV-A5-AR',
        },
      });
      expect(
        SelectedTemplate.fromMap(selected.toStorageMap())?.code,
        'INV-A5-AR',
      );
      expect(selected.durableIdentity, 'INV-A5-AR');
    });

    test('legacy id-only storage still parses without code', () {
      final selected = SelectedTemplate.fromMap(<dynamic, dynamic>{
        'selectedTemplates': <dynamic, dynamic>{
          'id': '34',
          'type': 'invoice',
        },
      });
      expect(selected?.id, '34');
      expect(selected?.code, isNull);
      expect(selected?.durableIdentity, '34');
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
          'meta': <String, dynamic>{'code': 'INV-A5-AR', 'name': 'Sales Invoice A5'},
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
            ),
          )
          .toList(growable: false);
    }

    test('exact legacy id match persists that item code', () {
      const legacy = SelectedTemplate(id: '595', type: 'sales_invoice');
      final migrated = SelectedTemplate.migrateLegacyId(
        legacy: legacy,
        catalog: entriesFor(catalog),
      );
      expect(migrated, isNotNull);
      expect(migrated!.code, 'INV-A5-AR');
      expect(migrated.id, '595');
      expect(migrated.type, 'sales_invoice');
    });

    test('missing legacy id clears selection', () {
      const legacy = SelectedTemplate(id: '999', type: 'sales_invoice');
      final migrated = SelectedTemplate.migrateLegacyId(
        legacy: legacy,
        catalog: entriesFor(catalog),
      );
      expect(migrated, isNull);
    });

    test('never falls back by name report type or position', () {
      const legacy = SelectedTemplate(id: '999', type: 'sales_invoice');
      final migrated = SelectedTemplate.migrateLegacyId(
        legacy: legacy,
        catalog: entriesFor(catalog),
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
      );
      expect(again?.code, 'INV-A5-AR');
      expect(again?.id, '595');
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
          id: '595',
          type: 'sales_invoice',
          code: 'INV-A5-AR',
          document: <String, dynamic>{
            'meta': <String, dynamic>{'version': '1'},
          },
          minPresenterDevVersion: 1,
        ),
      );
      await cache.putTemplate(
        const CachedTemplate(
          id: '596',
          type: 'sales_invoice',
          code: 'INV-A4-EN',
          document: <String, dynamic>{
            'meta': <String, dynamic>{'version': '1'},
          },
          minPresenterDevVersion: 1,
        ),
      );

      final byCode = await resolver.resolveSelectedTemplate(
        reportType: 'sales_invoice',
        presenterDevVersion: 1,
        storedSelection: const SelectedTemplate(
          id: '0',
          type: 'sales_invoice',
          code: 'INV-A5-AR',
        ),
      );
      expect(byCode.status, 'stored-selected');
      expect(byCode.template?.id, '595');
      expect(byCode.template?.code, 'INV-A5-AR');
    });
  });
}
