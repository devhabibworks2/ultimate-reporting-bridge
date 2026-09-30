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
    root = await Directory.systemTemp.createTemp('presenter-update-');
    presenterRoot = Directory('${root.path}/presenter');
    cache = PresenterCacheService(presenterRoot: presenterRoot);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('activates a newer valid bundle before returning', () async {
    await _writeReadySite(presenterRoot, 'previous-site');
    final server = await _serveUpdate(
      presenterVersion: '2.0.0',
      bundleVersion: 'bundle-2',
      devVersion: 2,
      bundleBytes: _bundleBytes(indexHtml: 'new-site'),
    );
    addTearDown(() => server.close(force: true));
    final manifestUrl = 'http://127.0.0.1:${server.port}/manifest';
    await _writeCachedManifest(
      cache.manifestFile,
      manifestUrl: manifestUrl,
      presenterVersion: '1.0.0',
      bundleVersion: 'bundle-1',
      devVersion: 1,
    );

    final coordinator = PresenterSessionCoordinator(
      presenterCache: cache,
      runtimeStorage: RuntimeSessionStorage(
        runtimeRoot: Directory('${root.path}/runtime'),
      ),
      apiBaseUrl: Uri.parse('http://127.0.0.1:${server.port}/'),
      bundleManifestUrl: manifestUrl,
    );
    addTearDown(coordinator.dispose);
    final launch = await coordinator.prepare(
      PresenterSessionRequest(
        sessionId: 'updated-session',
        reportType: 'invoice',
        reportName: 'Invoice',
        mode: PresenterSessionMode.online,
        seedData: const <String, Object>{'value': 1},
        template: _template(),
      ),
    );

    expect(launch.presenterVersion, '2.0.0');
    expect(launch.presenterManifest?.bundleVersion, 'bundle-2');
    expect(Uri.parse(launch.presenterUrl).host, '127.0.0.1');
    expect(
      await File('${presenterRoot.path}/index.html').readAsString(),
      'new-site',
    );
    expect(await cache.isReady(), isTrue);
  });

  test('invalid newer bundle preserves previous cache byte-for-byte', () async {
    await _writeReadySite(presenterRoot, 'previous-site');
    final server = await _serveUpdate(
      presenterVersion: '2.0.0',
      bundleVersion: 'bundle-invalid',
      devVersion: 2,
      bundleBytes: _bundleBytes(indexHtml: 'partial-site', includeEntry: false),
    );
    addTearDown(() => server.close(force: true));
    final manifestUrl = 'http://127.0.0.1:${server.port}/manifest';
    await _writeCachedManifest(
      cache.manifestFile,
      manifestUrl: manifestUrl,
      presenterVersion: '1.0.0',
      bundleVersion: 'bundle-1',
      devVersion: 1,
    );
    final before = await _snapshot(root);

    await expectLater(
      cache.ensureCurrentPresenterSite(
        bundleManifestUrl: manifestUrl,
        apiBaseUrl: null,
      ),
      throwsA(isA<BridgeRuntimeException>()),
    );

    expect(await _snapshot(root), before);
    expect(await cache.isReady(), isTrue);
  });
}

Future<HttpServer> _serveUpdate({
  required String presenterVersion,
  required String bundleVersion,
  required int devVersion,
  required List<int> bundleBytes,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.uri.path == '/manifest') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object>{
          'presenterVersion': presenterVersion,
          'bundleVersion': bundleVersion,
          'devVersion': devVersion,
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
  return server;
}

Future<void> _writeReadySite(Directory site, String indexHtml) async {
  await site.create(recursive: true);
  for (final entry in _validBundleEntries(indexHtml: indexHtml).entries) {
    final file = File('${site.path}/${entry.key}');
    await file.parent.create(recursive: true);
    await file.writeAsString(entry.value);
  }
}

Future<void> _writeCachedManifest(
  File file, {
  required String manifestUrl,
  required String presenterVersion,
  required String bundleVersion,
  required int devVersion,
}) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(
    jsonEncode(<String, Object>{
      'manifestUrl': manifestUrl,
      'presenterVersion': presenterVersion,
      'bundleVersion': bundleVersion,
      'devVersion': devVersion,
    }),
  );
}

Future<Map<String, String>> _snapshot(Directory directory) async {
  final snapshot = <String, String>{};
  await for (final entity in directory.list(recursive: true)) {
    if (entity is File) {
      snapshot[entity.path.substring(directory.path.length + 1)] = base64Encode(
        await entity.readAsBytes(),
      );
    }
  }
  return snapshot;
}

CachedTemplate _template() => CachedTemplate(
  id: 'invoice-template',
  type: 'invoice',
  document: const <String, Object>{'meta': <String, Object>{}},
);

List<int> _bundleBytes({required String indexHtml, bool includeEntry = true}) {
  final archive = Archive();
  final entries = _validBundleEntries(indexHtml: indexHtml);
  if (!includeEntry) entries.remove('presenter.js');
  for (final entry in entries.entries) {
    archive.addFile(ArchiveFile.string(entry.key, entry.value));
  }
  return ZipEncoder().encode(archive);
}

Map<String, String> _validBundleEntries({required String indexHtml}) {
  const fontHash =
      'a446817d40e4dc37c526fb5e30859fe0dd7bb0a7d5b3c0c56f7a0626d0019307';
  const iconHash =
      '6cbd50037e50937c7aa9ad4a2de7770c8f5db9455c1be9e021bc236060dafa21';
  final resources = <String, String>{
    for (final path in PresenterBundleContract.requiredResourceFiles)
      path: path == 'icons/MaterialIcons-Regular.ttf' ? iconHash : fontHash,
  };
  return <String, String>{
    'index.html': indexHtml,
    'presenter.js': PresenterBundleContract.requiredJavaScriptMarkers.join(' '),
    'presenter-manifest.json': jsonEncode(<String, Object>{
      'formatVersion': 1,
      'presenterVersion': '1.0.0',
      'devVersion': 1,
      'protocolVersion': 1,
      'entry': 'presenter.js',
      'resourceManifest': 'resource-manifest.json',
    }),
    'resource-manifest.json': jsonEncode(<String, Object>{
      'version': 'fixture-v1',
      'bundleSha256': List<String>.filled(64, 'a').join(),
      'resources': resources,
    }),
    for (final path in PresenterBundleContract.requiredFontFiles)
      path: 'font-bytes',
    'icons/MaterialIcons-Regular.ttf': 'icon-bytes',
  };
}
