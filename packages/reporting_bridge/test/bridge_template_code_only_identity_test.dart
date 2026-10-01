import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('TemplateCode-only identity', () {
    test('SelectedTemplate serializes code without backend id', () {
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
      expect(
        SelectedTemplate.fromMap(<String, dynamic>{
          'selectedTemplates': <String, dynamic>{
            'id': '595',
            'type': 'sales_invoice',
          },
        }),
        isNull,
      );
    });

    test('CachedTemplate ignores backend id and exposes TemplateCode only', () {
      final template = CachedTemplate.fromMap(<String, dynamic>{
        'id': '595',
        'type': 'sales_invoice',
        'code': 'INV-A5-AR',
        'document': <String, dynamic>{
          'meta': <String, dynamic>{'code': 'INV-A5-AR'},
        },
      });

      expect(template.templateCode, 'INV-A5-AR');
      expect(template.toMap().containsKey('id'), isFalse);
      expect(template.selectedTemplate.code, 'INV-A5-AR');
    });

    test(
      'case-distinct TemplateCodes coexist and resolve independently',
      () async {
        final root = await Directory.systemTemp.createTemp('bridge_code_case_');
        addTearDown(() => root.delete(recursive: true));
        final cache = TemplateCacheService(cacheRoot: root);

        for (final code in <String>['ABC', 'abc']) {
          await cache.putTemplate(
            CachedTemplate(
              type: 'invoice',
              code: code,
              document: <String, dynamic>{
                'meta': <String, dynamic>{'code': code},
              },
            ),
          );
        }

        expect((await cache.getTemplateByCode('ABC'))?.templateCode, 'ABC');
        expect((await cache.getTemplateByCode('abc'))?.templateCode, 'abc');
        expect(
          (await cache.listTemplates()).map((e) => e.templateCode).toList(),
          <String>['ABC', 'abc'],
        );
      },
    );

    test('code-less cache records are rejected', () {
      expect(
        () => CachedTemplate.fromMap(<String, dynamic>{
          'id': '595',
          'type': 'sales_invoice',
          'document': <String, dynamic>{'meta': <String, dynamic>{}},
        }),
        throwsA(isA<BridgeRuntimeException>()),
      );
    });
  });
}
