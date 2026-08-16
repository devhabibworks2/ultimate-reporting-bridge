import 'dart:convert';
import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('RuntimeSessionStorage lifecycle', () {
    test(
      'rejects parent aliases and removes partial or completed sessions',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'bridge_session_life_',
        );
        addTearDown(() async {
          if (await temp.exists()) await temp.delete(recursive: true);
        });
        final storage = RuntimeSessionStorage(runtimeRoot: temp);

        expect(
          () => storage.prepareRuntimeSession(
            const RuntimeSessionInput(
              sessionId: '..',
              reportType: 'invoice',
              seedData: <String, dynamic>{},
              templateDocument: <String, dynamic>{
                'meta': <String, dynamic>{'name': 'Invoice'},
              },
            ),
          ),
          throwsA(
            isA<BridgeRuntimeException>().having(
              (error) => error.code,
              'code',
              BridgeRuntimeErrorCodes.runtimeSessionInvalid,
            ),
          ),
        );

        expect(
          () => storage.prepareRuntimeSession(
            const RuntimeSessionInput(
              sessionId: 'partial',
              reportType: 'invoice',
              seedData: <String, dynamic>{'value': 1},
              templateDocument: <String, dynamic>{},
            ),
          ),
          throwsA(isA<BridgeRuntimeException>()),
        );
        expect(await Directory('${temp.path}/partial').exists(), isFalse);

        final session = await storage.prepareRuntimeSession(
          const RuntimeSessionInput(
            sessionId: 'complete',
            reportType: 'invoice',
            seedData: <String, dynamic>{'value': 1},
            templateDocument: <String, dynamic>{
              'meta': <String, dynamic>{'name': 'Invoice'},
            },
          ),
        );
        expect(
          await Directory('${temp.path}/${session.sessionId}').exists(),
          isTrue,
        );

        await storage.deleteRuntimeSession(session.sessionId);

        expect(
          await Directory('${temp.path}/${session.sessionId}').exists(),
          isFalse,
        );
      },
    );
  });

  group('LocalPresenterServer isolation', () {
    test(
      'serves only the active session and respects runtime-only mode',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'bridge_server_scope_',
        );
        addTearDown(() async {
          if (await temp.exists()) await temp.delete(recursive: true);
        });
        final presenterRoot = Directory('${temp.path}/presenter');
        final runtimeRoot = Directory('${temp.path}/runtime');
        await presenterRoot.create(recursive: true);
        await File(
          '${presenterRoot.path}/index.html',
        ).writeAsString('<html>ok</html>');
        await File(
          '${presenterRoot.path}/app.js',
        ).writeAsString('window.ok=true;');
        for (final sessionId in <String>['s1', 's2']) {
          final dir = Directory('${runtimeRoot.path}/$sessionId');
          await dir.create(recursive: true);
          await File('${dir.path}/session.json').writeAsString(
            jsonEncode(<String, dynamic>{'sessionId': sessionId}),
          );
        }

        final server = LocalPresenterServer(
          presenterRoot: presenterRoot,
          runtimeRoot: runtimeRoot,
        );
        addTearDown(server.stop);
        final client = HttpClient();
        addTearDown(() => client.close(force: true));

        final runtimeOnly = await server.startRuntimeOnly(sessionId: 's1');
        expect(
          (await _request(
            client,
            'GET',
            '${runtimeOnly.baseUrl}/runtime/s1/session.json',
          )).statusCode,
          HttpStatus.ok,
        );
        expect(
          (await _request(
            client,
            'GET',
            '${runtimeOnly.baseUrl}/runtime/s2/session.json',
          )).statusCode,
          HttpStatus.notFound,
        );
        expect(
          (await _request(
            client,
            'GET',
            '${runtimeOnly.baseUrl}/app.js',
          )).statusCode,
          HttpStatus.notFound,
        );
        expect(
          (await _request(
            client,
            'POST',
            '${runtimeOnly.baseUrl}/runtime/s1/session.json',
          )).statusCode,
          HttpStatus.methodNotAllowed,
        );

        await runtimeOnly.stop();
        final full = await server.start(sessionId: 's1');
        expect(
          (await _request(client, 'GET', '${full.baseUrl}/app.js')).statusCode,
          HttpStatus.ok,
        );
        expect(
          (await _request(
            client,
            'GET',
            '${full.baseUrl}/runtime/s2/session.json',
          )).statusCode,
          HttpStatus.notFound,
        );
      },
    );
  });

  test('BridgeRuntimeController deletes its active runtime session', () async {
    final temp = await Directory.systemTemp.createTemp(
      'bridge_controller_life_',
    );
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final presenterRoot = Directory('${temp.path}/presenter');
    final runtimeRoot = Directory('${temp.path}/runtime');
    await presenterRoot.create(recursive: true);
    await File(
      '${presenterRoot.path}/index.html',
    ).writeAsString('<html>ok</html>');

    final storage = RuntimeSessionStorage(runtimeRoot: runtimeRoot);
    final controller = BridgeRuntimeController(
      runtimeStorage: storage,
      localServer: LocalPresenterServer(
        presenterRoot: presenterRoot,
        runtimeRoot: runtimeRoot,
      ),
    );
    final session = await controller.prepareRuntimeSession(
      const RuntimeSessionInput(
        sessionId: 'controller-session',
        reportType: 'invoice',
        seedData: <String, dynamic>{'value': 1},
        templateDocument: <String, dynamic>{
          'meta': <String, dynamic>{'name': 'Invoice'},
        },
      ),
    );
    await controller.startLocalPresenterServer(sessionId: session.sessionId);
    final sessionDirectory = Directory(
      '${runtimeRoot.path}/${session.sessionId}',
    );
    expect(await sessionDirectory.exists(), isTrue);

    await controller.disposeBridge();

    expect(await sessionDirectory.exists(), isFalse);
  });
}

Future<_HttpBody> _request(HttpClient client, String method, String url) async {
  final request = await client.openUrl(method, Uri.parse(url));
  final response = await request.close();
  return _HttpBody(
    statusCode: response.statusCode,
    body: await response.transform(utf8.decoder).join(),
  );
}

class _HttpBody {
  const _HttpBody({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}
