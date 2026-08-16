import 'dart:convert';
import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('Presenter bundle manifest compatibility contract', () {
    test(
      'accepts semantic presenterVersion and non-semantic bundle label',
      () async {
        final server = await _manifestServer(<String, dynamic>{
          'presenterVersion': '1.0.0',
          'bundleVersion': 'dev-local',
          'devVersion': 1,
          'downloadUrl': '/api/presenter/bundles/dev-local',
          'available': true,
        });
        addTearDown(() => server.close(force: true));

        final root = await Directory.systemTemp.createTemp('bridge_manifest_');
        addTearDown(() => root.delete(recursive: true));
        final cache = PresenterCacheService(presenterRoot: root);

        final manifest = await cache.fetchRemoteManifest(
          bundleManifestUrl: 'http://127.0.0.1:${server.port}/manifest',
          apiBaseUrl: null,
        );

        expect(manifest.presenterVersion, '1.0.0');
        expect(manifest.bundleVersion, 'dev-local');
        expect(manifest.devVersion, 1);
      },
    );

    test('rejects a bundle label used as presenterVersion', () async {
      final server = await _manifestServer(<String, dynamic>{
        'presenterVersion': 'dev-local',
        'bundleVersion': 'dev-local',
        'devVersion': 1,
        'downloadUrl': '/api/presenter/bundles/dev-local',
        'available': true,
      });
      addTearDown(() => server.close(force: true));

      final root = await Directory.systemTemp.createTemp('bridge_manifest_');
      addTearDown(() => root.delete(recursive: true));
      final cache = PresenterCacheService(presenterRoot: root);

      expect(
        () => cache.fetchRemoteManifest(
          bundleManifestUrl: 'http://127.0.0.1:${server.port}/manifest',
          apiBaseUrl: null,
        ),
        throwsA(
          isA<BridgeRuntimeException>().having(
            (error) => error.code,
            'code',
            BridgeRuntimeErrorCodes.runtimeSessionInvalid,
          ),
        ),
      );
    });

    test('template compatibility uses Presenter and Bridge semver only', () {
      const template = CachedTemplate(
        id: 'invoice-1',
        type: 'invoice',
        document: <String, dynamic>{
          'meta': <String, dynamic>{'name': 'Invoice'},
        },
        minPresenterVersion: '1.0.0',
        minBridgeVersion: '1.0.0',
      );

      expect(
        template.isCompatibleWith(
          presenterVersion: '1.0.0',
          bridgeVersion: '1.0.0',
        ),
        isTrue,
      );
      expect(
        template.isCompatibleWith(
          presenterVersion: '0.9.9',
          bridgeVersion: '1.0.0',
        ),
        isFalse,
      );
      expect(
        template.isCompatibleWith(
          presenterVersion: '1.0.0',
          bridgeVersion: '0.9.9',
        ),
        isFalse,
      );
    });
  });
}

Future<HttpServer> _manifestServer(Map<String, dynamic> data) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(<String, dynamic>{'success': true, 'data': data}),
    );
    await request.response.close();
  });
  return server;
}
