import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

const _validHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _png = <int>[137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2, 3];

void main() {
  test(
    'GETs exact encoded TemplateCode and validates both integrity headers',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      HttpRequest? received;
      server.listen((request) async {
        received = request;
        request.response.headers
          ..set(HttpHeaders.contentTypeHeader, 'image/png')
          ..set('X-URB-Thumbnail-Content-Hash', _validHash)
          ..set(
            'X-URB-Thumbnail-Bytes-Sha256',
            sha256.convert(_png).toString(),
          );
        request.response.add(_png);
        await request.response.close();
      });

      final bytes = await fetchPublishedThumbnail(
        apiBase: _api(server),
        systemCode: 'system A',
        templateCode: 'فاتورة/A',
        descriptor: _descriptor(),
        headers: const <String, String>{
          'Authorization': 'Bearer safe',
          'X-Tenant-Id': 'tenant-a',
          'X-Evil': 'ignored',
        },
      );

      expect(bytes, _png);
      expect(received?.method, 'GET');
      expect(received?.uri.path, '/api/presenter/template-thumbnails');
      expect(received?.uri.queryParameters, <String, String>{
        'templateCode': 'فاتورة/A',
        'systemCode': 'system A',
        'versionNo': '3',
        'contentHash': _validHash,
      });
      expect(received?.headers.value('Authorization'), 'Bearer safe');
      expect(received?.headers.value('X-Evil'), isNull);
    },
  );

  test('injected shared HTTP client survives cancellation and subsequent GET', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final shared = HttpClient();
    addTearDown(() => shared.close(force: true));
    final firstStarted = Completer<void>();
    var requests = 0;
    var factoryCalls = 0;
    server.listen((request) async {
      requests++;
      if (requests == 1) {
        firstStarted.complete();
        return;
      }
      request.response.headers
        ..set(HttpHeaders.contentTypeHeader, 'image/png')
        ..set('X-URB-Thumbnail-Content-Hash', _validHash)
        ..set('X-URB-Thumbnail-Bytes-Sha256', sha256.convert(_png).toString());
      request.response.add(_png);
      await request.response.close();
    });

    HttpClient clientFactory() {
      factoryCalls++;
      return shared;
    }

    final cancellation = Completer<void>();
    final first = fetchPublishedThumbnail(
      apiBase: _api(server),
      systemCode: 's',
      templateCode: 't',
      descriptor: _descriptor(),
      headers: const {},
      cancellation: cancellation.future,
      httpClientFactory: clientFactory,
    );
    await firstStarted.future.timeout(const Duration(seconds: 2));
    cancellation.complete();
    await expectLater(
      first.timeout(const Duration(seconds: 2)),
      throwsA(isA<BridgeRuntimeException>()),
    );

    final second = await fetchPublishedThumbnail(
      apiBase: _api(server),
      systemCode: 's',
      templateCode: 't',
      descriptor: _descriptor(),
      headers: const {},
      httpClientFactory: clientFactory,
    );
    expect(second, _png);
    expect(factoryCalls, 2);
    expect(requests, 2);
  });

  test('unavailable descriptor makes no request', () async {
    var calls = 0;
    final server = await _serve((request) async => calls++);
    addTearDown(() => server.close(force: true));

    expect(
      await fetchPublishedThumbnail(
        apiBase: _api(server),
        systemCode: 's',
        templateCode: 't',
        descriptor: _descriptor(available: false),
        headers: const {},
      ),
      isNull,
    );
    expect(calls, 0);
  });

  test('cancellation closes an active GET promptly', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = Completer<void>();
    server.listen((request) {
      if (!received.isCompleted) received.complete();
    });
    final cancellation = Completer<void>();
    final fetch = fetchPublishedThumbnail(
      apiBase: _api(server),
      systemCode: 's',
      templateCode: 't',
      descriptor: _descriptor(),
      headers: const {},
      cancellation: cancellation.future,
    );
    await received.future.timeout(const Duration(seconds: 2));
    cancellation.complete();
    await expectLater(
      fetch.timeout(const Duration(seconds: 2)),
      throwsA(isA<BridgeRuntimeException>()),
    );
  });

  test(
    'verified missing image returns null and does not retry another route',
    () async {
      var calls = 0;
      final server = await _serve((request) async {
        calls++;
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      expect(
        await fetchPublishedThumbnail(
          apiBase: _api(server),
          systemCode: 's',
          templateCode: 't',
          descriptor: _descriptor(),
          headers: const {},
        ),
        isNull,
      );
      expect(calls, 1);
    },
  );

  for (final status in <int>[HttpStatus.unauthorized, HttpStatus.forbidden]) {
    test('$status fails closed', () async {
      final server = await _serve((request) async {
        request.response.statusCode = status;
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      await expectLater(
        fetchPublishedThumbnail(
          apiBase: _api(server),
          systemCode: 's',
          templateCode: 't',
          descriptor: _descriptor(),
          headers: const {},
        ),
        throwsA(isA<BridgeRuntimeException>()),
      );
    });
  }

  test(
    'rejects wrong identity hash, byte digest, MIME, and oversized image',
    () async {
      for (final response
          in <
            ({String identity, String bytesHash, String mime, List<int> body})
          >[
            (
              identity: 'b' * 64,
              bytesHash: sha256.convert(_png).toString(),
              mime: 'image/png',
              body: _png,
            ),
            (
              identity: _validHash,
              bytesHash: _validHash,
              mime: 'image/png',
              body: _png,
            ),
            (
              identity: _validHash,
              bytesHash: sha256.convert(_png).toString(),
              mime: 'image/jpeg',
              body: _png,
            ),
            (
              identity: _validHash,
              bytesHash: sha256
                  .convert(List<int>.filled(2 * 1024 * 1024 + 1, 0))
                  .toString(),
              mime: 'image/png',
              body: List<int>.filled(2 * 1024 * 1024 + 1, 0),
            ),
          ]) {
        final server = await _serve((request) async {
          request.response.headers
            ..set(HttpHeaders.contentTypeHeader, response.mime)
            ..set('X-URB-Thumbnail-Content-Hash', response.identity)
            ..set('X-URB-Thumbnail-Bytes-Sha256', response.bytesHash);
          request.response.add(response.body);
          await request.response.close();
        });
        await expectLater(
          fetchPublishedThumbnail(
            apiBase: _api(server),
            systemCode: 's',
            templateCode: 't',
            descriptor: _descriptor(),
            headers: const {},
          ),
          throwsA(isA<BridgeRuntimeException>()),
        );
        await server.close(force: true);
      }
    },
  );
}

BridgePublishedThumbnail _descriptor({bool available = true}) =>
    BridgePublishedThumbnail.fromMap(<String, Object?>{
      'versionNo': 3,
      'contentHash': _validHash,
      'mimeType': 'image/png',
      'available': available,
    })!;

Future<HttpServer> _serve(Future<void> Function(HttpRequest) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  return server;
}

Uri _api(HttpServer server) => Uri.parse('http://127.0.0.1:${server.port}/');
