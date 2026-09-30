import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test(
    'serves resource cache bytes only for the active runtime session',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bridge_resource_http_',
      );
      addTearDown(() => root.delete(recursive: true));
      final cache = PresenterResourceCacheStore(
        cacheRoot: Directory('${root.path}/presenter_resources'),
      );
      final server = LocalPresenterServer(
        presenterRoot: Directory('${root.path}/presenter'),
        runtimeRoot: Directory('${root.path}/runtime'),
        resourceCacheStore: cache,
      );
      addTearDown(server.stop);
      final handle = await server.startRuntimeOnly(
        sessionId: 'resource-active',
      );
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final key = List<String>.filled(64, 'c').join();
      final uri = Uri.parse(
        '${handle.baseUrl}/runtime/resource-active/resource-cache/$key',
      );

      final put = await client.putUrl(uri);
      put.add(<int>[7, 8, 9]);
      expect((await put.close()).statusCode, HttpStatus.noContent);

      final get = await client.getUrl(uri);
      final response = await get.close();
      expect(response.statusCode, HttpStatus.ok);
      expect(
        await response.fold<List<int>>(
          <int>[],
          (all, bytes) => all..addAll(bytes),
        ),
        <int>[7, 8, 9],
      );

      final invalid = await client.getUrl(uri.replace(path: '${uri.path}x'));
      expect((await invalid.close()).statusCode, HttpStatus.badRequest);

      await handle.stop();
      final inactive = await client.getUrl(uri);
      expect((await inactive.close()).statusCode, HttpStatus.notFound);
    },
  );

  test('rejects resource cache uploads over five MiB', () async {
    final root = await Directory.systemTemp.createTemp('bridge_resource_http_');
    addTearDown(() => root.delete(recursive: true));
    final server = LocalPresenterServer(
      presenterRoot: Directory('${root.path}/presenter'),
      runtimeRoot: Directory('${root.path}/runtime'),
      resourceCacheStore: PresenterResourceCacheStore(
        cacheRoot: Directory('${root.path}/presenter_resources'),
      ),
    );
    addTearDown(server.stop);
    final handle = await server.startRuntimeOnly(sessionId: 'resource-large');
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.putUrl(
      Uri.parse(
        '${handle.baseUrl}/runtime/resource-large/resource-cache/${'d' * 64}',
      ),
    );
    request.add(List<int>.filled(5 * 1024 * 1024 + 1, 1));

    expect(
      (await request.close()).statusCode,
      HttpStatus.requestEntityTooLarge,
    );
  });
}
