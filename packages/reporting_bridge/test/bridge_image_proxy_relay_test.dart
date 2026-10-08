import 'dart:io';

import 'package:reporting_bridge/src/bridge_image_proxy_relay.dart';
import 'package:test/test.dart';

void main() {
  test(
    'relays only to configured Backend with approved headers and image bytes',
    () async {
      final seenPaths = <String>[];
      final seenHeaders = <String, String?>{};
      final backend = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => backend.close(force: true));
      backend.listen((request) async {
        seenPaths.add(request.uri.path);
        seenHeaders['Authorization'] = request.headers.value('Authorization');
        seenHeaders['X-Tenant-Id'] = request.headers.value('X-Tenant-Id');
        seenHeaders['X-Branch-Id'] = request.headers.value('X-Branch-Id');
        seenHeaders['X-User-Context'] = request.headers.value('X-User-Context');
        seenHeaders['Unapproved'] = request.headers.value('Unapproved');
        expect(request.uri.queryParameters, <String, String>{
          'url': 'https://images.example.test/logo.png',
        });
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(<int>[137, 80, 78, 71, 13, 10, 26, 10]);
        await request.response.close();
      });

      final relay = BridgeImageProxyRelay(
        apiBaseUrl: Uri.parse(
          'http://127.0.0.1:' + backend.port.toString() + '/',
        ),
        headers: const <String, String>{
          'authorization': 'Bearer runtime-secret',
          'X-Tenant-Id': 'customer-A',
          'X-Branch-Id': 'branch-A',
          'X-User-Context': 'user-A',
          'Unapproved': 'MUST-NOT-LEAK',
        },
      );
      final result = await relay.fetch(
        Uri.parse('https://images.example.test/logo.png'),
      );
      expect(result.statusCode, HttpStatus.ok);
      expect(result.contentType, 'image/png');
      expect(result.bytes, <int>[137, 80, 78, 71, 13, 10, 26, 10]);
      expect(seenPaths, <String>['/api/image-proxy']);
      expect(seenHeaders['Authorization'], 'Bearer runtime-secret');
      expect(seenHeaders['X-Tenant-Id'], 'customer-A');
      expect(seenHeaders['X-Branch-Id'], 'branch-A');
      expect(seenHeaders['X-User-Context'], 'user-A');
      expect(seenHeaders['Unapproved'], isNull);
    },
  );

  test('rejects non-HTTP source URL before any network request', () async {
    final relay = BridgeImageProxyRelay(
      apiBaseUrl: Uri.parse('https://backend.example.test/api/'),
      headers: const <String, String>{},
    );
    await expectLater(
      relay.fetch(Uri.parse('file:///private/secret.png')),
      throwsArgumentError,
    );
  });

  test('fails safely for non-image Backend response', () async {
    final backend = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => backend.close(force: true));
    backend.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{}');
      await request.response.close();
    });
    final relay = BridgeImageProxyRelay(
      apiBaseUrl: Uri.parse(
        'http://127.0.0.1:' + backend.port.toString() + '/',
      ),
      headers: const <String, String>{},
    );
    await expectLater(
      relay.fetch(Uri.parse('https://images.example.test/logo.png')),
      throwsA(isA<Exception>()),
    );
  });
}
