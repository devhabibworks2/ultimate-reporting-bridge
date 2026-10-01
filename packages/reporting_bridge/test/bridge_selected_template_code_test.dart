import 'dart:convert';
import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('SelectedTemplate TemplateCode persistence', () {
    test('persists only code/type/system scope', () {
      const selected = SelectedTemplate(
        type: 'sales_invoice',
        code: 'INV-A5-AR',
        systemCode: 'system-a',
      );

      expect(selected.toMap(), <String, dynamic>{
        'type': 'sales_invoice',
        'code': 'INV-A5-AR',
        'systemCode': 'system-a',
      });
      expect(selected.durableIdentity, 'system-a:INV-A5-AR');
      expect(
        SelectedTemplate.fromMap(selected.toStorageMap())?.code,
        'INV-A5-AR',
      );
    });

    test('id-only storage is ignored', () {
      expect(
        SelectedTemplate.fromMap(<dynamic, dynamic>{
          'selectedTemplates': <dynamic, dynamic>{
            'id': '34',
            'type': 'invoice',
          },
        }),
        isNull,
      );
    });

    test('refuses or clears empty TemplateCode writes', () async {
      const incomplete = SelectedTemplate(
        type: 'sales_invoice',
        code: '   ',
        systemCode: 'system-a',
      );
      expect(incomplete.toStorageMap, throwsStateError);

      final temp = await Directory.systemTemp.createTemp(
        'bridge_sel_incomplete_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final cache = TemplateCacheService(cacheRoot: temp);
      await cache.writeSelectedTemplate(
        const SelectedTemplate(
          type: 'sales_invoice',
          code: 'INV-A5-AR',
          systemCode: 'system-a',
        ),
      );
      await cache.writeSelectedTemplate(incomplete);
      expect(await File('${temp.path}/.selection.json').exists(), isFalse);
    });

    test('cached template selection carries code and system scope', () {
      const template = CachedTemplate(
        type: 'sales_invoice',
        code: 'INV-A5-AR',
        systemCode: 'system-a',
        document: <String, dynamic>{},
      );

      expect(template.selectedTemplate.toStorageMap(), <String, dynamic>{
        'selectedTemplates': <String, dynamic>{
          'type': 'sales_invoice',
          'code': 'INV-A5-AR',
          'systemCode': 'system-a',
        },
      });
    });
  });

  group('SelectedTemplate reconciliation', () {
    final catalog = <CachedTemplate>[
      const CachedTemplate(
        type: 'sales_invoice',
        code: 'INV-A5-AR',
        systemCode: 'system-a',
        document: <String, dynamic>{},
      ),
      const CachedTemplate(
        type: 'sales_invoice',
        code: 'INV-A4-EN',
        systemCode: 'system-a',
        document: <String, dynamic>{},
      ),
    ];

    test('existing code is reconciled and persisted', () async {
      final temp = await Directory.systemTemp.createTemp('bridge_sel_code_');
      addTearDown(() => temp.delete(recursive: true));
      final cache = TemplateCacheService(cacheRoot: temp);

      final reconciled = await cache.reconcileSelectedTemplate(
        catalog: catalog,
        systemCode: 'system-a',
        stored: const SelectedTemplate(
          type: 'stale_type',
          code: 'INV-A5-AR',
          systemCode: 'system-a',
        ),
      );

      expect(reconciled?.type, 'sales_invoice');
      expect(reconciled?.code, 'INV-A5-AR');
      final raw =
          jsonDecode(await File('${temp.path}/.selection.json').readAsString())
              as Map<String, dynamic>;
      expect((raw['selectedTemplates'] as Map)['code'], 'INV-A5-AR');
      expect(raw.toString(), isNot(contains("'id'")));
    });

    test('missing or wrong-system code clears selection', () async {
      final temp = await Directory.systemTemp.createTemp('bridge_sel_stale_');
      addTearDown(() => temp.delete(recursive: true));
      final cache = TemplateCacheService(cacheRoot: temp);

      for (final selection in <SelectedTemplate>[
        const SelectedTemplate(
          type: 'sales_invoice',
          code: 'MISSING',
          systemCode: 'system-a',
        ),
        const SelectedTemplate(
          type: 'sales_invoice',
          code: 'INV-A5-AR',
          systemCode: 'system-b',
        ),
      ]) {
        await cache.writeSelectedTemplate(selection);
        expect(
          await cache.reconcileSelectedTemplate(
            catalog: catalog,
            systemCode: 'system-a',
          ),
          isNull,
        );
        expect(await File('${temp.path}/.selection.json').exists(), isFalse);
      }
    });
  });

  group('TemplateSelectionResolver code matching', () {
    test(
      'resolves stored selection by exact code within system catalog',
      () async {
        final temp = await Directory.systemTemp.createTemp('bridge_code_sel_');
        addTearDown(() => temp.delete(recursive: true));
        final cache = TemplateCacheService(cacheRoot: temp);
        await _putTemplate(
          cache,
          systemId: 1,
          systemCode: 'system-a',
          code: 'INV-A5-AR',
        );
        final resolver = TemplateSelectionResolver(cache: cache);

        final result = await resolver.resolveSelectedTemplate(
          reportType: 'sales_invoice',
          systemCode: 'system-a',
          storedSelection: const SelectedTemplate(
            type: 'sales_invoice',
            code: 'INV-A5-AR',
            systemCode: 'system-a',
          ),
        );

        expect(result.status, 'stored-selected');
        expect(result.template?.templateCode, 'INV-A5-AR');
      },
    );

    test('stale stored code requires selection and never falls back', () async {
      final temp = await Directory.systemTemp.createTemp('bridge_code_stale_');
      addTearDown(() => temp.delete(recursive: true));
      final cache = TemplateCacheService(cacheRoot: temp);
      await _putTemplate(
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
          type: 'sales_invoice',
          code: 'INV-OLD',
          systemCode: 'system-a',
        ),
      );

      expect(result.status, 'selection-required');
      expect(result.template, isNull);
      expect(result.errorCode, BridgeRuntimeErrorCodes.staleTemplateSelection);
    });
  });
}

Future<void> _putTemplate(
  TemplateCacheService cache, {
  required int systemId,
  required String systemCode,
  required String code,
}) async {
  await cache.putTemplate(
    CachedTemplate(
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
