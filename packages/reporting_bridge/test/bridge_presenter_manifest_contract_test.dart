import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('Presenter bundle manifest compatibility contract', () {
    test('accepts the Pure Dart presenter manifest contract', () async {
      final presenterManifest = _pureDartPresenterManifest();
      await _syncPureDartBundle(presenterManifest);
    });

    test(
      'rejects invalid or missing Pure Dart presenter manifest fields',
      () async {
        final invalidManifests = <String, Map<String, dynamic>>{
          'unsupported formatVersion': <String, dynamic>{
            ..._pureDartPresenterManifest(),
            'formatVersion': 2,
          },
          'non-semantic presenterVersion': <String, dynamic>{
            ..._pureDartPresenterManifest(),
            'presenterVersion': 'dev-local',
          },
          'missing devVersion': _withoutPresenterManifestField('devVersion'),
          'unsupported protocolVersion': <String, dynamic>{
            ..._pureDartPresenterManifest(),
            'protocolVersion': 2,
          },
          'non-Pure Dart entry': <String, dynamic>{
            ..._pureDartPresenterManifest(),
            'entry': 'main.dart.js',
          },
          'missing resourceManifest': _withoutPresenterManifestField(
            'resourceManifest',
          ),
        };

        for (final entry in invalidManifests.entries) {
          await expectLater(
            _syncPureDartBundle(entry.value),
            throwsA(isA<BridgeRuntimeException>()),
            reason: 'Presenter manifest with ${entry.key} must be rejected.',
          );
        }
      },
    );

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
        code: 'invoice-1',
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

Map<String, dynamic> _pureDartPresenterManifest() => <String, dynamic>{
  'formatVersion': 1,
  'presenterVersion': '1.0.0',
  'devVersion': 1,
  'protocolVersion': 1,
  'entry': 'presenter.js',
  'resourceManifest': 'resource-manifest.json',
};

Map<String, dynamic> _withoutPresenterManifestField(String field) =>
    _pureDartPresenterManifest()..remove(field);

Map<String, dynamic> _pureDartResourceManifest() => <String, dynamic>{
  'version': '1.0.0',
  'bundleSha256': List<String>.filled(64, 'a').join(),
  'resources': <String, String>{
    'fonts/Cairo-Regular.ttf':
        'a446817d40e4dc37c526fb5e30859fe0dd7bb0a7d5b3c0c56f7a0626d0019307',
    'fonts/Cairo-Medium.ttf':
        'a446817d40e4dc37c526fb5e30859fe0dd7bb0a7d5b3c0c56f7a0626d0019307',
    'fonts/Cairo-Bold.ttf':
        'a446817d40e4dc37c526fb5e30859fe0dd7bb0a7d5b3c0c56f7a0626d0019307',
    'fonts/NotoSansArabic-Regular.ttf':
        'a446817d40e4dc37c526fb5e30859fe0dd7bb0a7d5b3c0c56f7a0626d0019307',
    'fonts/NotoSansArabic-Medium.ttf':
        'a446817d40e4dc37c526fb5e30859fe0dd7bb0a7d5b3c0c56f7a0626d0019307',
    'fonts/NotoSansArabic-Bold.ttf':
        'a446817d40e4dc37c526fb5e30859fe0dd7bb0a7d5b3c0c56f7a0626d0019307',
    'fonts/NotoSansMono-Regular.ttf':
        'a446817d40e4dc37c526fb5e30859fe0dd7bb0a7d5b3c0c56f7a0626d0019307',
    'fonts/NotoSansMono-Medium.ttf':
        'a446817d40e4dc37c526fb5e30859fe0dd7bb0a7d5b3c0c56f7a0626d0019307',
    'fonts/NotoSansMono-Bold.ttf':
        'a446817d40e4dc37c526fb5e30859fe0dd7bb0a7d5b3c0c56f7a0626d0019307',
    'icons/MaterialIcons-Regular.ttf':
        '6cbd50037e50937c7aa9ad4a2de7770c8f5db9455c1be9e021bc236060dafa21',
  },
};

Future<void> _syncPureDartBundle(Map<String, dynamic> presenterManifest) async {
  final bundle = Archive();
  final files = <String, String>{
    'index.html': '<!doctype html><html><head></head><body></body></html>',
    'presenter.js':
        'urbReportingBridge presenterLifecycle onPresenterReady '
        'onRenderStarted onRenderCompleted onRenderFailed exportPdf',
    'presenter-manifest.json': jsonEncode(presenterManifest),
    'resource-manifest.json': jsonEncode(_pureDartResourceManifest()),
    'fonts/Cairo-Regular.ttf': 'font-bytes',
    'fonts/Cairo-Medium.ttf': 'font-bytes',
    'fonts/Cairo-Bold.ttf': 'font-bytes',
    'fonts/NotoSansArabic-Regular.ttf': 'font-bytes',
    'fonts/NotoSansArabic-Medium.ttf': 'font-bytes',
    'fonts/NotoSansArabic-Bold.ttf': 'font-bytes',
    'fonts/NotoSansMono-Regular.ttf': 'font-bytes',
    'fonts/NotoSansMono-Medium.ttf': 'font-bytes',
    'fonts/NotoSansMono-Bold.ttf': 'font-bytes',
    'icons/MaterialIcons-Regular.ttf': 'icon-bytes',
  };
  for (final entry in files.entries) {
    bundle.addFile(ArchiveFile.string(entry.key, entry.value));
  }
  final bundleBytes = ZipEncoder().encode(bundle);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.uri.path == '/manifest') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, dynamic>{
          'presenterVersion': '1.0.0',
          'bundleVersion': 'dev-local',
          'devVersion': 1,
          'downloadUrl': '/bundle.zip',
          'available': true,
        }),
      );
    } else if (request.uri.path == '/bundle.zip') {
      request.response.headers.contentType = ContentType.binary;
      request.response.add(bundleBytes);
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  });

  final root = await Directory.systemTemp.createTemp('bridge_pure_manifest_');
  final cache = PresenterCacheService(
    presenterRoot: Directory('${root.path}/presenter'),
  );
  try {
    await cache.syncPresenterSite(
      bundleManifestUrl: 'http://127.0.0.1:${server.port}/manifest',
      apiBaseUrl: null,
    );
  } finally {
    await server.close(force: true);
    await root.delete(recursive: true);
  }
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
