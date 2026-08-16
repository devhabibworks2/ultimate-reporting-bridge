import 'dart:convert';
import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('canonical Presenter document integrity', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('agent22f-bridge-');
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test(
      'runtime storage preserves canonical strings and caller maps',
      () async {
        final document = _canonicalDocument();
        final runtimeData = <String, dynamic>{
          'invoice': <String, dynamic>{'number': 'INV-22F'},
        };
        final documentBefore = jsonEncode(document);
        final runtimeBefore = jsonEncode(runtimeData);
        final storage = RuntimeSessionStorage(
          runtimeRoot: Directory('${root.path}/runtime'),
        );

        final session = await storage.prepareRuntimeSession(
          RuntimeSessionInput(
            sessionId: 'agent22f',
            reportType: 'invoice',
            seedData: runtimeData,
            templateDocument: document,
          ),
        );

        expect(
          await File(session.template!.path).readAsString(),
          documentBefore,
        );
        expect(
          await File(session.seedReportData!.path).readAsString(),
          runtimeBefore,
        );
        expect(jsonEncode(document), documentBefore);
        expect(jsonEncode(runtimeData), runtimeBefore);
      },
    );

    test(
      'template cache round trip preserves the canonical document',
      () async {
        final document = _canonicalDocument();
        final before = jsonEncode(document);
        final cache = TemplateCacheService(
          cacheRoot: Directory('${root.path}/templates'),
        );

        await cache.putTemplate(
          CachedTemplate(
            id: 'agent22f-template',
            type: 'invoice',
            document: document,
            minPresenterVersion: '1.0.0',
            minBridgeVersion: '1.0.0',
          ),
        );

        final restored = await cache.getTemplate('agent22f-template');
        expect(restored, isNotNull);
        expect(jsonEncode(restored!.document), before);
        expect(
          restored.document['styleTokens'],
          containsPair('font', containsPair('weight_bold', '700')),
        );
        expect(
          ((restored.document['elements'] as List)[1] as Map)['encoding'],
          containsPair('version', '7'),
        );
        expect(jsonEncode(document), before);
      },
    );
  });
}

Map<String, dynamic> _canonicalDocument() {
  return <String, dynamic>{
    'schemaVersion': '1.0.0',
    'meta': <String, dynamic>{
      'name': 'Agent 22F',
      'family': 'invoice',
      'status': 'draft',
      'version': 1,
    },
    'page': <String, dynamic>{
      'unit': 'mm',
      'size': 'A4',
      'orientation': 'portrait',
      'width': 210,
      'height': 297,
      'direction': 'ltr',
      'language': 'en',
    },
    'styleTokens': <String, dynamic>{
      'color': <String, dynamic>{},
      'font': <String, dynamic>{
        'family': 'Cairo',
        'weight_regular': '400',
        'weight_medium': '500',
        'weight_bold': '700',
      },
      'spacing': <String, dynamic>{},
      'border': <String, dynamic>{},
      'radius': <String, dynamic>{},
    },
    'assets': <Map<String, dynamic>>[],
    'layers': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'main',
        'name': 'Main',
        'visible': true,
        'locked': false,
        'elementIds': <String>['text-1', 'qr-1'],
      },
    ],
    'elements': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'text-1',
        'type': 'text',
        'layerId': 'main',
        'box': <String, dynamic>{'x': 10, 'y': 10, 'width': 80, 'height': 10},
        'content': <String, dynamic>{
          'source': 'static',
          'value': 'Canonical string weight',
        },
        'style': <String, dynamic>{
          'text': <String, dynamic>{'fontWeight': '700'},
        },
      },
      <String, dynamic>{
        'id': 'qr-1',
        'type': 'qr',
        'layerId': 'main',
        'box': <String, dynamic>{'x': 10, 'y': 30, 'width': 30, 'height': 30},
        'content': <String, dynamic>{
          'source': 'static',
          'static': <String, dynamic>{'value': 'agent22f'},
          'binding': <String, dynamic>{'path': ''},
          'emptyBehavior': 'hide',
        },
        'encoding': <String, dynamic>{'version': '7'},
      },
    ],
  };
}
