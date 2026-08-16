import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

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
    'accepts the AssetManifest.bin emitted by current Flutter Web',
    () async {
      await _writeReadyPresenter(presenterRoot, cache.manifestFile);

      expect(await cache.isReady(), isTrue);
      expect(await cache.supportsCurrentLifecycleContract(), isTrue);
    },
  );

  test('rejects a bundle without any supported AssetManifest', () async {
    await _writeReadyPresenter(presenterRoot, cache.manifestFile);
    await File('${presenterRoot.path}/assets/AssetManifest.bin').delete();

    expect(await cache.isReady(), isFalse);
  });

  test(
    'accepts a structurally ready legacy Presenter and reports old lifecycle',
    () async {
      await _writeReadyPresenter(
        presenterRoot,
        cache.manifestFile,
        mainJavaScript: 'base64Chunk urbReportingBridge',
      );

      expect(await cache.isReady(), isTrue);
      expect(await cache.supportsCurrentLifecycleContract(), isFalse);
    },
  );

  test('rejects Presenter JavaScript missing one required marker', () async {
    final markers = PresenterBundleContract.requiredJavaScriptMarkers
        .where((marker) => marker != 'onRenderCompleted')
        .join(' ');
    await _writeReadyPresenter(
      presenterRoot,
      cache.manifestFile,
      mainJavaScript: markers,
    );

    expect(await cache.isReady(), isTrue);
    expect(await cache.supportsCurrentLifecycleContract(), isFalse);
  });

  test('invalid downloaded bundle preserves the previous ready site', () async {
    await _writeReadyPresenter(presenterRoot, cache.manifestFile);
    await File('${presenterRoot.path}/index.html').writeAsString('old-site');
    final previousManifest = await cache.manifestFile.readAsString();
    final invalidZip = _presenterZipBytes(
      mainJavaScript: 'base64Chunk urbReportingBridge',
      includeMainJavaScript: false,
    );
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

Future<void> _writeReadyPresenter(
  Directory presenterRoot,
  File manifestFile, {
  String? mainJavaScript,
}) async {
  await presenterRoot.create(recursive: true);
  await manifestFile.parent.create(recursive: true);
  await manifestFile.writeAsString('{"bundleVersion":"test"}');
  await File('${presenterRoot.path}/index.html').writeAsString('<html></html>');

  for (final path in PresenterBundleContract.requiredFiles) {
    final file = File('${presenterRoot.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      path == 'main.dart.js'
          ? (mainJavaScript ??
                PresenterBundleContract.requiredJavaScriptMarkers.join(' '))
          : path,
    );
  }

  final assetManifest = File('${presenterRoot.path}/assets/AssetManifest.bin');
  await assetManifest.parent.create(recursive: true);
  await assetManifest.writeAsBytes(const <int>[1]);
}

List<int> _presenterZipBytes({
  required String mainJavaScript,
  bool includeMainJavaScript = true,
}) {
  final archive = Archive();
  final files = <String, String>{
    'index.html': '<!doctype html><html><head><base href="/"></head></html>',
    'main.dart.js': mainJavaScript,
    'flutter_bootstrap.js': 'bootstrap',
    'assets/AssetManifest.bin': 'manifest',
    'assets/FontManifest.json': '[]',
    'assets/fonts/MaterialIcons-Regular.otf': 'icons',
    'assets/assets/fonts/Cairo-Regular.ttf': 'cairo',
    'assets/assets/fonts/Cairo-Medium.ttf': 'cairo-medium',
    'assets/assets/fonts/Cairo-Bold.ttf': 'cairo-bold',
    'assets/assets/fonts/NotoSansArabic-Regular.ttf': 'arabic',
    'assets/assets/fonts/NotoSansArabic-Medium.ttf': 'arabic-medium',
    'assets/assets/fonts/NotoSansArabic-Bold.ttf': 'arabic-bold',
    'assets/assets/fonts/NotoSansMono-Regular.ttf': 'mono',
    'assets/assets/fonts/NotoSansMono-Medium.ttf': 'mono-medium',
    'assets/assets/fonts/NotoSansMono-Bold.ttf': 'mono-bold',
  };
  if (!includeMainJavaScript) files.remove('main.dart.js');
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.string(entry.key, entry.value));
  }
  return ZipEncoder().encode(archive);
}
