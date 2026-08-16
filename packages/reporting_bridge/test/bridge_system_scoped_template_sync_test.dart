import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:reporting_bridge/reporting_bridge.dart';

void main() {
  test(
    'system-scoped sync preserves other systems and removes stale items',
    () async {
      final root = await Directory.systemTemp.createTemp('bridge-system-sync-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
        if (await root.exists()) await root.delete(recursive: true);
      });

      final templates = <int, List<Map<String, dynamic>>>{
        1: <Map<String, dynamic>>[_template('a1', 1)],
        2: <Map<String, dynamic>>[_template('b1', 2)],
      };
      final requestedSystems = <String?>[];

      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/api/presenter/templates') {
          final rawSystem = request.uri.queryParameters['systemId'];
          requestedSystems.add(rawSystem);
          final systemId = int.tryParse(rawSystem ?? '');
          request.response.write(
            jsonEncode(<String, dynamic>{
              'success': true,
              'data': <String, dynamic>{
                'items': templates[systemId] ?? const <Map<String, dynamic>>[],
              },
            }),
          );
        } else if (request.uri.path.startsWith('/api/presenter/templates/')) {
          final segments = request.uri.pathSegments;
          final id = segments[3];
          final match = templates.values
              .expand((items) => items)
              .where((item) => item['id'] == id)
              .single;
          request.response.write(
            jsonEncode(<String, dynamic>{'success': true, 'data': match}),
          );
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final cache = TemplateCacheService(
        cacheRoot: Directory('${root.path}/templates'),
      );
      final sync = PresenterTemplateSyncService();
      final apiBase = Uri.parse(
        'http://${server.address.host}:${server.port}/',
      );

      await sync.syncTemplatesToCache(
        apiBase: apiBase,
        headers: const <String, String>{},
        cache: cache,
        systemId: 1,
      );
      await sync.syncTemplatesToCache(
        apiBase: apiBase,
        headers: const <String, String>{},
        cache: cache,
        systemId: 2,
      );

      expect(
        (await cache.listTemplates()).map((template) => template.id).toSet(),
        <String>{'a1', 'b1'},
      );

      templates[1] = <Map<String, dynamic>>[_template('a2', 1)];
      await sync.syncTemplatesToCache(
        apiBase: apiBase,
        headers: const <String, String>{},
        cache: cache,
        systemId: 1,
      );

      final all = await cache.listTemplates();
      expect(all.map((template) => template.id).toSet(), <String>{'a2', 'b1'});
      expect((await cache.listTemplates(systemId: 1)).single.id, 'a2');
      expect((await cache.listTemplates(systemId: 2)).single.id, 'b1');
      expect(requestedSystems, <String?>['1', '2', '1']);
    },
  );

  test(
    'mismatched system response leaves the previous cache unchanged',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bridge-system-guard-',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
        if (await root.exists()) await root.delete(recursive: true);
      });

      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, dynamic>{
            'success': true,
            'data': <String, dynamic>{
              'items': <Map<String, dynamic>>[_template('wrong', 2)],
            },
          }),
        );
        await request.response.close();
      });

      final cache = TemplateCacheService(
        cacheRoot: Directory('${root.path}/templates'),
      );
      await cache.putTemplate(CachedTemplate.fromMap(_template('existing', 1)));
      final sync = PresenterTemplateSyncService();
      final result = await sync.syncTemplatesToCache(
        apiBase: Uri.parse('http://${server.address.host}:${server.port}/'),
        headers: const <String, String>{},
        cache: cache,
        systemId: 1,
      );

      expect(result.errors, isNotEmpty);
      expect(
        (await cache.listTemplates()).map((template) => template.id).toList(),
        <String>['existing'],
      );
    },
  );

  test('empty scoped manifest preserves the existing system cache', () async {
    final root = await Directory.systemTemp.createTemp('bridge-empty-sync-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      if (await root.exists()) await root.delete(recursive: true);
    });

    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, dynamic>{
          'success': true,
          'data': <String, dynamic>{'items': <Object>[]},
        }),
      );
      await request.response.close();
    });

    final cache = TemplateCacheService(
      cacheRoot: Directory('${root.path}/templates'),
    );
    await cache.putTemplate(CachedTemplate.fromMap(_template('existing', 1)));

    final result = await PresenterTemplateSyncService().syncTemplatesToCache(
      apiBase: Uri.parse('http://${server.address.host}:${server.port}/'),
      headers: const <String, String>{},
      cache: cache,
      systemId: 1,
    );

    expect(result.errors, isNotEmpty);
    expect((await cache.listTemplates(systemId: 1)).single.id, 'existing');
  });
}

Map<String, dynamic> _template(String id, int systemId) => <String, dynamic>{
  'id': id,
  'type': 'invoice',
  'systemId': systemId,
  'name': 'Template $id',
  'document': <String, dynamic>{
    'meta': <String, dynamic>{'name': 'Template $id'},
  },
  'compatibility': <String, dynamic>{
    'version': '1',
    'minPresenterVersion': '1.0.0',
    'minBridgeVersion': '1.0.0',
  },
};
