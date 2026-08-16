import 'dart:convert';
import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:reporting_bridge/src/bridge_http_fetch.dart';
import 'package:test/test.dart';

void main() {
  group('BridgeHttpFetch', () {
    test('getBytes returns body on 200', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.write('hello');
        await request.response.close();
      });

      final port = server.port;
      final uri = Uri.parse('http://127.0.0.1:$port/path');
      final fetch = BridgeHttpFetch();
      final bytes = await fetch.getBytes(
        uri,
        headers: const <String, String>{},
      );
      expect(utf8.decode(bytes), 'hello');
    });

    test('uses injected httpClientFactory for each request', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.write('x');
        await request.response.close();
      });

      var factoryCalls = 0;
      final uri = Uri.parse('http://127.0.0.1:${server.port}/');
      final fetch = BridgeHttpFetch(
        httpClientFactory: () {
          factoryCalls++;
          return HttpClient();
        },
      );
      await fetch.getBytes(uri, headers: const <String, String>{});
      expect(factoryCalls, 1);
    });

    test('getBytes throws BridgeRuntimeException on non-2xx', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final uri = Uri.parse('http://127.0.0.1:${server.port}/missing');
      final fetch = BridgeHttpFetch();
      expect(
        () => fetch.getBytes(uri, headers: const <String, String>{}),
        throwsA(
          isA<BridgeRuntimeException>().having(
            (e) => e.code,
            'code',
            BridgeRuntimeErrorCodes.runtimeSessionInvalid,
          ),
        ),
      );
    });

    test('getJsonObject decodes JSON object', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, dynamic>{'ok': true, 'data': 1}),
        );
        await request.response.close();
      });

      final uri = Uri.parse('http://127.0.0.1:${server.port}/api');
      final fetch = BridgeHttpFetch();
      final map = await fetch.getJsonObject(
        uri,
        headers: const <String, String>{},
        notValidJsonMessage: 'bad',
      );
      expect(map['ok'], true);
      expect(map['data'], 1);
    });

    test(
      'getJsonObject uses custom message when body is not JSON object',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          request.response.statusCode = HttpStatus.ok;
          request.response.write('not json');
          await request.response.close();
        });

        final uri = Uri.parse('http://127.0.0.1:${server.port}/');
        final fetch = BridgeHttpFetch();
        expect(
          () => fetch.getJsonObject(
            uri,
            headers: const <String, String>{},
            notValidJsonMessage: 'Custom not JSON at $uri',
          ),
          throwsA(
            isA<BridgeRuntimeException>()
                .having(
                  (e) => e.code,
                  'code',
                  BridgeRuntimeErrorCodes.runtimeSessionInvalid,
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('Custom not JSON'),
                ),
          ),
        );
      },
    );
  });

  group('unwrapBridgeEnvelopeData', () {
    test('returns inner data map when present', () {
      final inner = <String, dynamic>{
        'items': <int>[1],
      };
      final envelope = <String, dynamic>{'success': true, 'data': inner};
      expect(unwrapBridgeEnvelopeData(envelope), inner);
    });

    test('returns envelope when data is absent', () {
      final envelope = <String, dynamic>{'success': true};
      expect(unwrapBridgeEnvelopeData(envelope), envelope);
    });
  });
}
