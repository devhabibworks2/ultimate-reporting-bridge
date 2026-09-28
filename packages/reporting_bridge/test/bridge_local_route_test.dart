import 'dart:convert';
import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test(
    'localhost serves only the deployment-aligned Presenter route',
    () async {
      final temp = await Directory.systemTemp.createTemp('bridge_route_test_');
      addTearDown(() => temp.delete(recursive: true));
      final presenterRoot = Directory('${temp.path}/presenter');
      final runtimeRoot = Directory('${temp.path}/runtime');
      await presenterRoot.create(recursive: true);
      await runtimeRoot.create(recursive: true);
      await File(
        '${presenterRoot.path}/index.html',
      ).writeAsString('<html>ok</html>');

      final server = LocalPresenterServer(
        presenterRoot: presenterRoot,
        runtimeRoot: runtimeRoot,
      );
      final handle = await server.start(sessionId: 's1');
      addTearDown(handle.stop);
      final client = HttpClient();
      addTearDown(client.close);

      final aligned = await client.getUrl(
        Uri.parse('${handle.baseUrl}/UltimateReport/apps/presenter/index.html'),
      );
      final alignedResponse = await aligned.close();
      await alignedResponse.drain<void>();
      expect(alignedResponse.statusCode, HttpStatus.ok);

      final legacy = await client.getUrl(
        Uri.parse('${handle.baseUrl}/Report/presenter'),
      );
      final legacyResponse = await legacy.close();
      await legacyResponse.drain<void>();
      expect(legacyResponse.statusCode, HttpStatus.notFound);
    },
  );

  test('proxy keeps Presenter and runtime on one localhost origin', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstreamRequests = <HttpRequest>[];
    upstream.listen((request) async {
      upstreamRequests.add(request);
      if (request.uri.path == '/UltimateReport/apps/presenter/index.html') {
        request.response.headers.contentType = ContentType.html;
        request.response.write('<html>online presenter</html>');
      } else if (request.uri.path ==
          '/UltimateReport/apps/presenter/main.dart.js') {
        request.response.headers.contentType = ContentType(
          'application',
          'javascript',
          charset: 'utf-8',
        );
        request.response.write('console.log("presenter");');
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    addTearDown(() => upstream.close(force: true));

    final temp = await Directory.systemTemp.createTemp('bridge_proxy_test_');
    addTearDown(() => temp.delete(recursive: true));
    final presenterRoot = Directory('${temp.path}/presenter');
    final runtimeRoot = Directory('${temp.path}/runtime');
    await presenterRoot.create(recursive: true);
    final sessionDir = Directory('${runtimeRoot.path}/s1');
    await sessionDir.create(recursive: true);
    await File(
      '${sessionDir.path}/seed_report_data.json',
    ).writeAsString('{"ok":true}');

    final server = LocalPresenterServer(
      presenterRoot: presenterRoot,
      runtimeRoot: runtimeRoot,
    );
    final handle = await server.startProxy(
      sessionId: 's1',
      presenterUrl: Uri.parse(
        'http://127.0.0.1:${upstream.port}'
        '/UltimateReport/apps/presenter/index.html?existing=1',
      ),
    );
    addTearDown(handle.stop);
    final client = HttpClient();
    addTearDown(client.close);

    final presenterUri = Uri.parse(handle.presenterUrl);
    expect(presenterUri.scheme, 'http');
    expect(presenterUri.host, '127.0.0.1');
    expect(presenterUri.path, '/UltimateReport/apps/presenter/index.html');
    expect(presenterUri.queryParameters['existing'], '1');

    final presenterRequest = await client.getUrl(
      presenterUri.replace(
        queryParameters: <String, String>{
          ...presenterUri.queryParameters,
          'sessionId': 's1',
          'locale': 'ar',
          'dir': 'rtl',
        },
      ),
    );
    final presenterResponse = await presenterRequest.close();
    final presenterBody = await presenterResponse
        .transform(const Utf8Decoder())
        .join();
    expect(presenterResponse.statusCode, HttpStatus.ok);
    expect(presenterBody, contains('online presenter'));
    expect(
      upstreamRequests.single.uri.queryParameters,
      containsPair('existing', '1'),
    );
    expect(
      upstreamRequests.single.uri.queryParameters,
      containsPair('sessionId', 's1'),
    );

    final assetRequest = await client.getUrl(
      Uri.parse('${handle.baseUrl}/UltimateReport/apps/presenter/main.dart.js'),
    );
    final assetResponse = await assetRequest.close();
    final assetBody = await assetResponse.transform(const Utf8Decoder()).join();
    expect(assetResponse.statusCode, HttpStatus.ok);
    expect(
      assetResponse.headers.contentType?.mimeType,
      'application/javascript',
    );
    expect(assetBody, contains('console.log'));

    final runtimeRequest = await client.getUrl(
      Uri.parse('${handle.baseUrl}/runtime/s1/seed_report_data.json'),
    );
    final runtimeResponse = await runtimeRequest.close();
    final runtimeBody = await runtimeResponse
        .transform(const Utf8Decoder())
        .join();
    expect(runtimeResponse.statusCode, HttpStatus.ok);
    expect(runtimeBody, '{"ok":true}');
    expect(upstreamRequests.length, 2);

    final unknownRequest = await client.getUrl(
      Uri.parse('${handle.baseUrl}/not-a-presenter-route'),
    );
    final unknownResponse = await unknownRequest.close();
    await unknownResponse.drain<void>();
    expect(unknownResponse.statusCode, HttpStatus.notFound);
    expect(upstreamRequests.length, 2);
  });

  test('proxy preserves HEAD and upstream HTTP status', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      request.response.headers.contentType = ContentType.text;
      request.response.statusCode = request.uri.path.endsWith('missing.js')
          ? HttpStatus.notFound
          : HttpStatus.ok;
      if (request.method != 'HEAD') {
        request.response.write('body');
      }
      await request.response.close();
    });
    addTearDown(() => upstream.close(force: true));

    final temp = await Directory.systemTemp.createTemp('bridge_proxy_head_');
    addTearDown(() => temp.delete(recursive: true));
    final server = LocalPresenterServer(
      presenterRoot: Directory('${temp.path}/presenter')..createSync(),
      runtimeRoot: Directory('${temp.path}/runtime')..createSync(),
    );
    final handle = await server.startProxy(
      sessionId: 's1',
      presenterUrl: Uri.parse(
        'http://127.0.0.1:${upstream.port}/UltimateReport/apps/presenter/index.html',
      ),
    );
    addTearDown(handle.stop);
    final client = HttpClient();
    addTearDown(client.close);

    final head = await client.openUrl(
      'HEAD',
      Uri.parse('${handle.baseUrl}/UltimateReport/apps/presenter/index.html'),
    );
    final headResponse = await head.close();
    await headResponse.drain<void>();
    expect(headResponse.statusCode, HttpStatus.ok);

    final missing = await client.getUrl(
      Uri.parse('${handle.baseUrl}/UltimateReport/apps/presenter/missing.js'),
    );
    final missingResponse = await missing.close();
    await missingResponse.drain<void>();
    expect(missingResponse.statusCode, HttpStatus.notFound);

    final post = await client.postUrl(
      Uri.parse('${handle.baseUrl}/UltimateReport/apps/presenter/index.html'),
    );
    final postResponse = await post.close();
    await postResponse.drain<void>();
    expect(postResponse.statusCode, HttpStatus.methodNotAllowed);
  });

  test('proxy maps upstream transport failure to 502', () async {
    final closedServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final closedPort = closedServer.port;
    await closedServer.close(force: true);

    final temp = await Directory.systemTemp.createTemp('bridge_proxy_502_');
    addTearDown(() => temp.delete(recursive: true));
    final server = LocalPresenterServer(
      presenterRoot: Directory('${temp.path}/presenter')..createSync(),
      runtimeRoot: Directory('${temp.path}/runtime')..createSync(),
    );
    final handle = await server.startProxy(
      sessionId: 's1',
      presenterUrl: Uri.parse(
        'http://127.0.0.1:$closedPort/UltimateReport/apps/presenter/index.html',
      ),
    );
    addTearDown(handle.stop);
    final client = HttpClient();
    addTearDown(client.close);

    final request = await client.getUrl(Uri.parse(handle.presenterUrl));
    final response = await request.close();
    await response.drain<void>();
    expect(response.statusCode, HttpStatus.badGateway);
  });

  test(
    'compatible offline sessions reuse one port and isolate runtime trees',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'bridge_offline_multi_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final presenterRoot = Directory('${temp.path}/presenter');
      final runtimeRoot = Directory('${temp.path}/runtime');
      await presenterRoot.create(recursive: true);
      await File(
        '${presenterRoot.path}/index.html',
      ).writeAsString('<html>offline</html>');
      for (final id in const <String>['first', 'second']) {
        final directory = Directory('${runtimeRoot.path}/$id');
        await directory.create(recursive: true);
        await File('${directory.path}/payload.json').writeAsString(id);
      }

      final server = LocalPresenterServer(
        presenterRoot: presenterRoot,
        runtimeRoot: runtimeRoot,
      );
      addTearDown(server.stop);

      final first = await server.start(sessionId: 'first');
      final second = await server.start(sessionId: 'second');

      expect(second.port, first.port);
      expect(second.baseUrl, first.baseUrl);
      expect(
        await _httpStatus('${first.baseUrl}/runtime/first/payload.json'),
        HttpStatus.ok,
      );
      expect(
        await _httpStatus('${second.baseUrl}/runtime/second/payload.json'),
        HttpStatus.ok,
      );
      expect(
        await _httpStatus(
          '${first.baseUrl}/UltimateReport/apps/presenter/index.html',
        ),
        HttpStatus.ok,
      );

      // Path traversal must stay rejected under multi-session registration.
      expect(
        await _httpStatus('${first.baseUrl}/runtime/first/../secret.json'),
        HttpStatus.notFound,
      );

      await first.stop();
      expect(
        await _httpStatus('${first.baseUrl}/runtime/first/payload.json'),
        HttpStatus.notFound,
      );
      expect(
        await _httpStatus('${second.baseUrl}/runtime/second/payload.json'),
        HttpStatus.ok,
      );
      expect(
        await _httpStatus(
          '${second.baseUrl}/UltimateReport/apps/presenter/index.html',
        ),
        HttpStatus.ok,
      );
    },
  );

  test(
    'compatible online-proxy sessions reuse one port with isolated runtimes',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        if (request.uri.path.startsWith('/UltimateReport/apps/presenter/')) {
          request.response.headers.contentType = ContentType.html;
          request.response.write('<html>online presenter</html>');
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
      addTearDown(() => upstream.close(force: true));

      final temp = await Directory.systemTemp.createTemp('bridge_proxy_multi_');
      addTearDown(() => temp.delete(recursive: true));
      final presenterRoot = Directory('${temp.path}/presenter')..createSync();
      final runtimeRoot = Directory('${temp.path}/runtime')..createSync();
      for (final id in const <String>['s1', 's2']) {
        final directory = Directory('${runtimeRoot.path}/$id');
        await directory.create(recursive: true);
        await File(
          '${directory.path}/seed_report_data.json',
        ).writeAsString('{"session":"$id"}');
      }

      final presenterUrl = Uri.parse(
        'http://127.0.0.1:${upstream.port}'
        '/UltimateReport/apps/presenter/index.html?existing=1',
      );
      final server = LocalPresenterServer(
        presenterRoot: presenterRoot,
        runtimeRoot: runtimeRoot,
      );
      addTearDown(server.stop);

      final first = await server.startProxy(
        sessionId: 's1',
        presenterUrl: presenterUrl,
      );
      final second = await server.startProxy(
        sessionId: 's2',
        presenterUrl: presenterUrl,
      );

      expect(second.port, first.port);
      expect(
        await _httpStatus('${first.baseUrl}/runtime/s1/seed_report_data.json'),
        HttpStatus.ok,
      );
      expect(
        await _httpStatus('${second.baseUrl}/runtime/s2/seed_report_data.json'),
        HttpStatus.ok,
      );
      expect(
        await _httpStatus(
          '${first.baseUrl}/UltimateReport/apps/presenter/index.html',
        ),
        HttpStatus.ok,
      );

      await first.stop();
      expect(
        await _httpStatus('${first.baseUrl}/runtime/s1/seed_report_data.json'),
        HttpStatus.notFound,
      );
      expect(
        await _httpStatus('${second.baseUrl}/runtime/s2/seed_report_data.json'),
        HttpStatus.ok,
      );
      expect(
        await _httpStatus(
          '${second.baseUrl}/UltimateReport/apps/presenter/index.html',
        ),
        HttpStatus.ok,
      );
    },
  );
}

Future<int> _httpStatus(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}
