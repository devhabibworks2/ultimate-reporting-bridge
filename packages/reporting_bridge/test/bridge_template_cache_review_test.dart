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
}
