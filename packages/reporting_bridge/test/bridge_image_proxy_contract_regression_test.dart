import 'dart:io';
import 'dart:typed_data';
import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test(
    'ACTIVE session has an image-proxy endpoint instead of static 404',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'urb_url_image_contract_',
      );
      final server = LocalPresenterServer(
        presenterRoot: Directory('${root.path}/presenter'),
        runtimeRoot: Directory('${root.path}/runtime'),
      );
      final handle = await server.startRuntimeOnly(sessionId: 'image-active');
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.stop();
        await root.delete(recursive: true);
      });
      final uri = Uri.parse(
        '${handle.baseUrl}/runtime/image-active/image-proxy',
      ).replace(queryParameters: {'url': 'https://example.org/logo.png'});
      final response = await (await client.getUrl(uri)).close();
      final status = response.statusCode;
      await response.drain<void>();
      expect(
        status,
        isNot(HttpStatus.notFound),
        reason:
            'The Presenter advertises this endpoint; currently Bridge '
            'falls through to static-file 404 even for an active session.',
      );
    },
  );

  test(
    'session-scoped image-proxy returns PNG from approved fetcher',
    () async {
      final root = await Directory.systemTemp.createTemp('bridge_proxy_ok_');
      var calls = 0;
      final server = LocalPresenterServer(
        presenterRoot: Directory('${root.path}/presenter'),
        runtimeRoot: Directory('${root.path}/runtime'),
        imageProxyFetch: (uri) async {
          calls++;
          expect(uri.host, 'example.org');
          return Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
        },
      );
      final handle = await server.startRuntimeOnly(
        sessionId: 'only-this-session',
      );
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.stop();
        await root.delete(recursive: true);
      });
      final live = Uri.parse(
        '${handle.baseUrl}/runtime/only-this-session/image-proxy',
      ).replace(queryParameters: {'url': 'https://example.org/logo.png'});
      final response = await (await client.getUrl(live)).close();
      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentType?.mimeType, 'image/png');
      expect(await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b)), [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ]);
      expect(calls, 1);

      final unauthorized = live.replace(path: '/runtime/unknown/image-proxy');
      final bad = await (await client.getUrl(unauthorized)).close();
      expect(bad.statusCode, HttpStatus.notFound);
      await bad.drain<void>();
      expect(calls, 1);

      await handle.stop();
      final ended = await (await client.getUrl(live)).close();
      expect(ended.statusCode, HttpStatus.notFound);
      await ended.drain<void>();
    },
  );

  test(
    'image-proxy rejects private targets and cross-origin browser calls',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bridge_proxy_secure_',
      );
      var calls = 0;
      final server = LocalPresenterServer(
        presenterRoot: Directory('${root.path}/presenter'),
        runtimeRoot: Directory('${root.path}/runtime'),
        imageProxyFetch: (uri) async {
          calls++;
          return Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
        },
      );
      final handle = await server.startRuntimeOnly(sessionId: 'secure-session');
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.stop();
        await root.delete(recursive: true);
      });
      final base = Uri.parse(
        '${handle.baseUrl}/runtime/secure-session/image-proxy',
      );
      for (final target in [
        'http://127.0.0.1/internal',
        'http://localhost/private',
        'http://192.168.1.2/asset',
        'http://[::1]/secret',
        'http://169.254.169.254/latest/meta-data',
        'file:///etc/passwd',
        'https://user:password@example.org/img',
        'https://example.org:8443/admin',
      ]) {
        final uri = base.replace(queryParameters: {'url': target});
        final response = await (await client.getUrl(uri)).close();
        expect(response.statusCode, HttpStatus.forbidden, reason: target);
        await response.drain<void>();
      }
      expect(calls, 0);
      final crossOrigin = await client.getUrl(
        base.replace(queryParameters: {'url': 'https://example.org/logo.png'}),
      );
      crossOrigin.headers.set('Origin', 'https://evil.example');
      final response = await crossOrigin.close();
      expect(response.statusCode, HttpStatus.forbidden);
      await response.drain<void>();
      expect(calls, 0);
    },
  );

  test('image-proxy rejects oversized and invalid image bytes', () async {
    final root = await Directory.systemTemp.createTemp('bridge_proxy_limit_');
    Uint8List result = Uint8List(5 * 1024 * 1024 + 1);
    final server = LocalPresenterServer(
      presenterRoot: Directory('${root.path}/presenter'),
      runtimeRoot: Directory('${root.path}/runtime'),
      imageProxyFetch: (_) async => result,
    );
    final handle = await server.startRuntimeOnly(sessionId: 'image-limit');
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.stop();
      await root.delete(recursive: true);
    });
    final uri = Uri.parse(
      '${handle.baseUrl}/runtime/image-limit/image-proxy',
    ).replace(queryParameters: {'url': 'https://example.org/large.png'});
    var resp = await (await client.getUrl(uri)).close();
    expect(resp.statusCode, HttpStatus.requestEntityTooLarge);
    await resp.drain<void>();
    result = Uint8List.fromList([1, 2, 3, 4]);
    resp = await (await client.getUrl(uri)).close();
    expect(resp.statusCode, HttpStatus.badGateway);
    await resp.drain<void>();
  });
}
