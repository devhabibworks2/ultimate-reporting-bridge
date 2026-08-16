import 'dart:convert';
import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('keeps previous cache when a template sync is partial', () async {
    final root = await Directory.systemTemp.createTemp('bridge_sync_review_');
    addTearDown(() => root.delete(recursive: true));
    final cache = TemplateCacheService(cacheRoot: root);
    await cache.putTemplate(
      const CachedTemplate(
        id: 'existing',
        type: 'invoice',
        document: <String, dynamic>{'meta': <String, dynamic>{}},
      ),
    );

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.uri.path == '/api/presenter/templates') {
        await _writeJson(request, <String, dynamic>{
          'success': true,
          'data': <String, dynamic>{
            'items': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'new-good'},
              <String, dynamic>{'id': 'new-bad'},
            ],
          },
        });
        return;
      }
      if (request.uri.path == '/api/presenter/templates/new-good/latest') {
        await _writeJson(request, <String, dynamic>{
          'success': true,
          'data': <String, dynamic>{
            'id': 'new-good',
            'type': 'invoice',
            'document': <String, dynamic>{'meta': <String, dynamic>{}},
          },
        });
        return;
      }
      if (request.uri.path == '/api/presenter/templates/new-bad/latest') {
        await _writeJson(request, <String, dynamic>{
          'success': false,
          'data': <String, dynamic>{},
        });
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final result = await PresenterTemplateSyncService().syncTemplatesToCache(
      apiBase: Uri.parse('http://127.0.0.1:${server.port}/'),
      headers: const <String, String>{},
      cache: cache,
    );

    expect(result.syncedCount, 0);
    expect(result.errors, isNotEmpty);
    expect((await cache.listTemplates()).map((item) => item.id), <String>[
      'existing',
    ]);
  });

  test('skips corrupt cache files and keeps colliding ids distinct', () async {
    final root = await Directory.systemTemp.createTemp('bridge_cache_review_');
    addTearDown(() => root.delete(recursive: true));
    final cache = TemplateCacheService(cacheRoot: root);

    for (final id in <String>['a/b', 'a?b']) {
      await cache.putTemplate(
        CachedTemplate(
          id: id,
          type: 'invoice',
          document: const <String, dynamic>{'meta': <String, dynamic>{}},
        ),
      );
    }
    await File('${root.path}/broken.json').writeAsString('{broken');

    final templates = await cache.listTemplates();
    expect(templates.map((item) => item.id).toSet(), <String>{'a/b', 'a?b'});
    expect((await cache.getTemplate('a/b'))?.id, 'a/b');
    expect((await cache.getTemplate('a?b'))?.id, 'a?b');
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
}

Future<void> _writeJson(HttpRequest request, Map<String, dynamic> body) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}
