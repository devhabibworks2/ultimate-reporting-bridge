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

  test('cached Presenter and runtime share one localhost origin', () async {
    final temp = await Directory.systemTemp.createTemp('bridge_local_test_');
    addTearDown(() => temp.delete(recursive: true));
    final presenterRoot = Directory('${temp.path}/presenter');
    final runtimeRoot = Directory('${temp.path}/runtime');
    await presenterRoot.create(recursive: true);
    await File(
      '${presenterRoot.path}/index.html',
    ).writeAsString('<html>cached presenter</html>');
    await File(
      '${presenterRoot.path}/presenter.js',
    ).writeAsString('console.log("presenter");');
    final sessionDir = Directory('${runtimeRoot.path}/s1');
    await sessionDir.create(recursive: true);
    await File(
      '${sessionDir.path}/seed_report_data.json',
    ).writeAsString('{"ok":true}');

    final server = LocalPresenterServer(
      presenterRoot: presenterRoot,
      runtimeRoot: runtimeRoot,
    );
    final handle = await server.start(sessionId: 's1');
    addTearDown(handle.stop);
    final client = HttpClient();
    addTearDown(client.close);

    final presenterUri = Uri.parse(handle.presenterUrl);
    expect(presenterUri.scheme, 'http');
    expect(presenterUri.host, '127.0.0.1');
    expect(presenterUri.path, '/UltimateReport/apps/presenter/index.html');
    expect(presenterUri.queryParameters['sessionId'], 's1');

    final presenterRequest = await client.getUrl(presenterUri);
    final presenterResponse = await presenterRequest.close();
    final presenterBody = await presenterResponse
        .transform(const Utf8Decoder())
        .join();
    expect(presenterResponse.statusCode, HttpStatus.ok);
    expect(presenterBody, contains('cached presenter'));

    final assetRequest = await client.getUrl(
      Uri.parse('${handle.baseUrl}/UltimateReport/apps/presenter/presenter.js'),
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

    final unknownRequest = await client.getUrl(
      Uri.parse('${handle.baseUrl}/not-a-presenter-route'),
    );
    final unknownResponse = await unknownRequest.close();
    await unknownResponse.drain<void>();
    expect(unknownResponse.statusCode, HttpStatus.notFound);
  });

  test('local Presenter preserves HEAD, 404 and method status', () async {
    final temp = await Directory.systemTemp.createTemp('bridge_local_head_');
    addTearDown(() => temp.delete(recursive: true));
    final presenterRoot = Directory('${temp.path}/presenter')..createSync();
    final runtimeRoot = Directory('${temp.path}/runtime')..createSync();
    await File(
      '${presenterRoot.path}/index.html',
    ).writeAsString('<html>body</html>');

    final server = LocalPresenterServer(
      presenterRoot: presenterRoot,
      runtimeRoot: runtimeRoot,
    );
    final handle = await server.start(sessionId: 's1');
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

  test('local Presenter start requires cached index.html', () async {
    final temp = await Directory.systemTemp.createTemp('bridge_local_missing_');
    addTearDown(() => temp.delete(recursive: true));
    final server = LocalPresenterServer(
      presenterRoot: Directory('${temp.path}/presenter')..createSync(),
      runtimeRoot: Directory('${temp.path}/runtime')..createSync(),
    );

    await expectLater(
      server.start(sessionId: 's1'),
      throwsA(
        isA<BridgeRuntimeException>().having(
          (error) => error.code,
          'code',
          BridgeRuntimeErrorCodes.offlineAssetsNotReady,
        ),
      ),
    );
  });

  test(
    'compatible cached sessions reuse one port and isolate runtime trees',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'bridge_cached_multi_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final presenterRoot = Directory('${temp.path}/presenter');
      final runtimeRoot = Directory('${temp.path}/runtime');
      await presenterRoot.create(recursive: true);
      await File(
        '${presenterRoot.path}/index.html',
      ).writeAsString('<html>cached</html>');
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
