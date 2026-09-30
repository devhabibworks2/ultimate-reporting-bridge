import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

const _pureDartFiles = <String>[
  'index.html',
  'presenter.js',
  'presenter-manifest.json',
  'resource-manifest.json',
  'fonts/Cairo-Regular.ttf',
  'fonts/Cairo-Medium.ttf',
  'fonts/Cairo-Bold.ttf',
  'fonts/NotoSansArabic-Regular.ttf',
  'fonts/NotoSansArabic-Medium.ttf',
  'fonts/NotoSansArabic-Bold.ttf',
  'fonts/NotoSansMono-Regular.ttf',
  'fonts/NotoSansMono-Medium.ttf',
  'fonts/NotoSansMono-Bold.ttf',
  'icons/MaterialIcons-Regular.ttf',
];

const _fontFiles = <String>[
  'fonts/Cairo-Regular.ttf',
  'fonts/Cairo-Medium.ttf',
  'fonts/Cairo-Bold.ttf',
  'fonts/NotoSansArabic-Regular.ttf',
  'fonts/NotoSansArabic-Medium.ttf',
  'fonts/NotoSansArabic-Bold.ttf',
  'fonts/NotoSansMono-Regular.ttf',
  'fonts/NotoSansMono-Medium.ttf',
  'fonts/NotoSansMono-Bold.ttf',
];

const _lifecycleMarkers = <String>[
  'base64Chunk',
  'urbReportingBridge',
  'presenterLifecycle',
  'onPresenterReady',
  'onRenderStarted',
  'onRenderCompleted',
  'onRenderFailed',
  'exportPdf',
];

void main() {
  late Directory root;
  late Directory presenterRoot;
  late PresenterCacheService cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('presenter-cache-ready-');
    presenterRoot = Directory('${root.path}/presenter');
    cache = PresenterCacheService(presenterRoot: presenterRoot);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'accepts a complete Pure Dart Presenter bundle and lifecycle contract',
    () async {
      await _writeReadyPresenter(presenterRoot, cache.manifestFile);

      expect(await cache.isReady(), isTrue);
      expect(await cache.supportsCurrentLifecycleContract(), isTrue);
    },
  );

  test(
    'requires presenter.js and scans it for lifecycle and export markers',
    () async {
      await _writeReadyPresenter(
        presenterRoot,
        cache.manifestFile,
        includeLegacyFlutterAssets: true,
        presenterJavaScript: _lifecycleMarkers
            .where((marker) => marker != 'onRenderCompleted')
            .join(' '),
        legacyMainJavaScript: _lifecycleMarkers.join(' '),
      );

      expect(await cache.isReady(), isTrue);
      expect(await cache.supportsCurrentLifecycleContract(), isFalse);
    },
  );

  test(
    'does not treat main.dart.js as a substitute for presenter.js',
    () async {
      await _writeReadyPresenter(
        presenterRoot,
        cache.manifestFile,
        includePresenterJavaScript: false,
        includeLegacyFlutterAssets: true,
        legacyMainJavaScript: _lifecycleMarkers.join(' '),
      );

      expect(await cache.isReady(), isFalse);
    },
  );

  test('requires resource-manifest.json before a bundle is ready', () async {
    await _writeReadyPresenter(
      presenterRoot,
      cache.manifestFile,
      includeLegacyFlutterAssets: true,
      includeResourceManifest: false,
    );

    expect(await cache.isReady(), isFalse);
  });

  test(
    'rejects a listed font or icon with a missing or mismatched SHA-256',
    () async {
      for (final mode in <_ResourceManifestMode>[
        _ResourceManifestMode.missingEntry,
        _ResourceManifestMode.tamperedHash,
      ]) {
        if (await presenterRoot.exists()) {
          await presenterRoot.delete(recursive: true);
        }
        await _writeReadyPresenter(
          presenterRoot,
          cache.manifestFile,
          includeLegacyFlutterAssets: true,
          resourceManifestMode: mode,
        );

        expect(
          await cache.isReady(),
          isFalse,
          reason: 'Resource manifest mode $mode must fail closed.',
        );
      }
    },
  );

  test('invalid downloaded bundle preserves the previous ready site', () async {
    await _writeReadyPresenter(presenterRoot, cache.manifestFile);
    await File('${presenterRoot.path}/index.html').writeAsString('old-site');
    final previousManifest = await cache.manifestFile.readAsString();
    final invalidZip = _presenterZipBytes(includePresenterJavaScript: false);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.uri.path == '/manifest') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, dynamic>{
            'presenterVersion': '1.1.0',
            'bundleVersion': 'invalid-bundle',
            'devVersion': 2,
            'downloadUrl': '/bundle.zip',
          }),
        );
      } else if (request.uri.path == '/bundle.zip') {
        request.response.headers.contentType = ContentType.binary;
        request.response.add(invalidZip);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    await expectLater(
      cache.syncPresenterSite(
        bundleManifestUrl: 'http://127.0.0.1:${server.port}/manifest',
        apiBaseUrl: null,
      ),
      throwsA(
        isA<BridgeRuntimeException>().having(
          (error) => error.code,
          'code',
          BridgeRuntimeErrorCodes.offlineAssetsNotReady,
        ),
      ),
    );

    expect(
      await File('${presenterRoot.path}/index.html').readAsString(),
      'old-site',
    );
    expect(await cache.manifestFile.readAsString(), previousManifest);
    expect(await cache.isReady(), isTrue);
  });
}

enum _ResourceManifestMode { valid, missingEntry, tamperedHash }

Future<void> _writeReadyPresenter(
  Directory presenterRoot,
  File manifestFile, {
  String? presenterJavaScript,
  String? legacyMainJavaScript,
  bool includePresenterJavaScript = true,
  bool includeLegacyFlutterAssets = false,
  bool includeResourceManifest = true,
  _ResourceManifestMode resourceManifestMode = _ResourceManifestMode.valid,
}) async {
  await presenterRoot.create(recursive: true);
  await manifestFile.parent.create(recursive: true);
  await manifestFile.writeAsString('{"bundleVersion":"test"}');

  for (final path in _pureDartFiles) {
    if (path == 'presenter.js' && !includePresenterJavaScript) continue;
    if (path == 'resource-manifest.json' && !includeResourceManifest) continue;
    if (path == 'presenter-manifest.json') {
      await _writeTextFile(
        presenterRoot,
        path,
        '{"formatVersion":1,"presenterVersion":"1.0.0",'
        '"devVersion":1,"protocolVersion":1,"entry":"presenter.js",'
        '"resourceManifest":"resource-manifest.json"}',
      );
    } else if (path == 'presenter.js') {
      await _writeTextFile(
        presenterRoot,
        path,
        presenterJavaScript ?? _lifecycleMarkers.join(' '),
      );
    } else if (_fontFiles.contains(path)) {
      await _writeTextFile(presenterRoot, path, 'font-bytes');
    } else if (path == 'icons/MaterialIcons-Regular.ttf') {
      await _writeTextFile(presenterRoot, path, 'icon-bytes');
    } else if (path != 'resource-manifest.json') {
      await _writeTextFile(presenterRoot, path, 'bundle-file');
    }
  }

  if (includeResourceManifest) {
    final resources = <String, String>{};
    for (final path in <String>[
      ..._fontFiles,
      'icons/MaterialIcons-Regular.ttf',
    ]) {
      if (resourceManifestMode == _ResourceManifestMode.missingEntry &&
          path == _fontFiles.first) {
        continue;
      }
      resources[path] =
          resourceManifestMode == _ResourceManifestMode.tamperedHash &&
              path == _fontFiles.first
          ? List<String>.filled(64, '0').join()
          : path == 'icons/MaterialIcons-Regular.ttf'
          ? '6cbd50037e50937c7aa9ad4a2de7770c8f5db9455c1be9e021bc236060dafa21'
          : 'a446817d40e4dc37c526fb5e30859fe0dd7bb0a7d5b3c0c56f7a0626d0019307';
    }
    await _writeTextFile(
      presenterRoot,
      'resource-manifest.json',
      jsonEncode(<String, Object>{
        'version': '1.0.0',
        'bundleSha256': List<String>.filled(64, 'a').join(),
        'resources': resources,
      }),
    );
  }

  if (includeLegacyFlutterAssets) {
    await _writeTextFile(
      presenterRoot,
      'main.dart.js',
      legacyMainJavaScript ?? _lifecycleMarkers.join(' '),
    );
  }
  if (includeLegacyFlutterAssets) {
    await _writeTextFile(presenterRoot, 'flutter_bootstrap.js', 'bootstrap');
    await _writeTextFile(presenterRoot, 'assets/FontManifest.json', '[]');
    await _writeTextFile(
      presenterRoot,
      'assets/fonts/MaterialIcons-Regular.otf',
      'legacy-icon-bytes',
    );
    await _writeTextFile(
      presenterRoot,
      'assets/AssetManifest.bin',
      'legacy-asset-manifest',
    );
  }
}

Future<void> _writeTextFile(
  Directory root,
  String path,
  String contents,
) async {
  final file = File('${root.path}/$path');
  await file.parent.create(recursive: true);
  await file.writeAsString(contents);
}

List<int> _presenterZipBytes({bool includePresenterJavaScript = true}) {
  final archive = Archive();
  final files = <String, String>{
    'index.html': '<!doctype html><html><head><base href="/"></head></html>',
    'presenter-manifest.json':
        '{"formatVersion":1,"presenterVersion":"1.0.0",'
        '"devVersion":1,"protocolVersion":1,"entry":"presenter.js",'
        '"resourceManifest":"resource-manifest.json"}',
    'resource-manifest.json': jsonEncode(<String, Object>{
      'version': '1.0.0',
      'bundleSha256': List<String>.filled(64, 'a').join(),
      'resources': <String, String>{
        for (final path in _fontFiles)
          path:
              'a446817d40e4dc37c526fb5e30859fe0dd7bb0a7d5b3c0c56f7a0626d0019307',
        'icons/MaterialIcons-Regular.ttf':
            '6cbd50037e50937c7aa9ad4a2de7770c8f5db9455c1be9e021bc236060dafa21',
      },
    }),
    for (final path in _fontFiles) path: 'font-bytes',
    'icons/MaterialIcons-Regular.ttf': 'icon-bytes',
  };
  if (includePresenterJavaScript) {
    files['presenter.js'] = _lifecycleMarkers.join(' ');
  }
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.string(entry.key, entry.value));
  }
  return ZipEncoder().encode(archive);
}
