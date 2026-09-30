import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test(
    'one client owns server, cache, download, and session lifecycle',
    () async {
      var bundleDownloads = 0;
      var apiHeaderSeen = false;
      var presenterHeaderSeen = false;
      final zipBytes = _presenterZipBytes();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((request) async {
        final path = request.uri.path;
        if (path.startsWith('/api/')) {
          apiHeaderSeen =
              request.headers.value('X-Tenant-Id') == 'tenant_demo' &&
              request.headers.value('Not-Approved') == null;
        }
        if (path == '/presenter/index.html') {
          presenterHeaderSeen = request.headers.value('X-Tenant-Id') != null;
          request.response.headers.contentType = ContentType.html;
          request.response.write('<!doctype html><html>Presenter</html>');
          await request.response.close();
          return;
        }
        if (path == '/api/health') {
          await _writeJson(request, <String, dynamic>{'status': 'ok'});
          return;
        }
        if (path == '/api/presenter/systems') {
          await _writeJson(request, <String, dynamic>{
            'success': true,
            'data': <String, dynamic>{
              'items': <Map<String, dynamic>>[
                <String, dynamic>{'id': 7, 'code': 'erp', 'name': 'ERP'},
              ],
            },
          });
          return;
        }
        if (path == '/api/presenter/templates') {
          expect(request.uri.queryParameters['systemId'], '7');
          await _writeJson(request, <String, dynamic>{
            'success': true,
            'data': <String, dynamic>{
              'items': <Map<String, dynamic>>[
                <String, dynamic>{'id': 'invoice-7', 'systemId': 7},
              ],
            },
          });
          return;
        }
        if (path == '/api/presenter/templates/invoice-7/latest') {
          await _writeJson(request, <String, dynamic>{
            'success': true,
            'data': <String, dynamic>{
              'id': 'invoice-7',
              'type': 'invoice',
              'systemId': 7,
              'document': <String, dynamic>{
                'meta': <String, dynamic>{'name': 'Invoice'},
                'page': <String, dynamic>{},
                'elements': <dynamic>[],
              },
            },
          });
          return;
        }
        if (path == '/api/presenter/bundles/manifest') {
          await _writeJson(request, <String, dynamic>{
            'success': true,
            'data': <String, dynamic>{
              'available': true,
              'presenterVersion': '2.1.0',
              'bundleVersion': 'bundle-210',
              'devVersion': 210,
              'downloadUrl': '/api/presenter/bundles/bundle-210',
            },
          });
          return;
        }
        if (path == '/api/presenter/bundles/bundle-210') {
          bundleDownloads += 1;
          request.response.headers.contentType = ContentType(
            'application',
            'zip',
          );
          request.response.contentLength = zipBytes.length;
          request.response.add(zipBytes);
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final root = await Directory.systemTemp.createTemp('bridge_client_test_');
      addTearDown(() => root.delete(recursive: true));
      final client = ReportingBridgeClient(
        apiBaseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
        presenterEntryUrl: Uri.parse(
          'http://127.0.0.1:${server.port}/presenter/index.html',
        ),
        bridgeRoot: root,
        headers: const <String, String>{
          'X-Tenant-Id': 'tenant_demo',
          'Not-Approved': 'blocked',
        },
      );
      addTearDown(client.dispose);

      await client.probeEndpoints();
      expect((await client.fetchSystems()).single.id, 7);
      final templateSync = await client.syncTemplates(systemId: 7);
      expect(templateSync.syncedCount, 1);

      final firstProgress = <double>[];
      final secondProgress = <double>[];
      final manifests = await Future.wait<PresenterCacheManifest>(
        <Future<PresenterCacheManifest>>[
          client.syncPresenter(onProgress: firstProgress.add),
          client.syncPresenter(onProgress: secondProgress.add),
        ],
      );
      expect(bundleDownloads, 1);
      expect(manifests.first.presenterVersion, '2.1.0');
      expect(firstProgress.first, 0);
      expect(firstProgress.last, 1);
      expect(secondProgress, isNotEmpty);
      expect(firstProgress, orderedEquals(<double>[...firstProgress]..sort()));
      expect(apiHeaderSeen, isTrue);
      expect(presenterHeaderSeen, isFalse);

      final status = await client.getStatus();
      expect(status.presenterCached, isTrue);
      expect(status.templateCount, 1);
      expect(status.presenterManifest?.bundleVersion, 'bundle-210');

      final template = (await client.listTemplates(systemId: 7)).single;
      final seed = <String, dynamic>{
        'dynamic': <String, dynamic>{
          'rows': <dynamic>[1, null, true],
        },
      };
      final launch = await client.prepareSession(
        PresenterSessionRequest(
          sessionId: 'facade-offline',
          reportType: 'invoice',
          reportName: 'Invoice',
          mode: PresenterSessionMode.offline,
          seedData: seed,
          template: template,
        ),
      );
      expect(launch.presenterVersion, '2.1.0');
      final runtimeFile = File(
        '${root.path}/runtime/facade-offline/seed_report_data.json',
      );
      expect(jsonDecode(await runtimeFile.readAsString()), seed);

      await client.stopSession();
      expect(await runtimeFile.parent.exists(), isFalse);
      await client.clearTemplateCache();
      await client.clearPresenterCache();
      final cleared = await client.getStatus();
      expect(cleared.templateCount, 0);
      expect(cleared.presenterCached, isFalse);
      expect(cleared.presenterManifest, isNull);
    },
  );

  test('disposed client rejects new operations', () async {
    final root = await Directory.systemTemp.createTemp(
      'bridge_client_dispose_',
    );
    addTearDown(() => root.delete(recursive: true));
    final client = ReportingBridgeClient(
      apiBaseUrl: Uri.parse('https://reports.example/'),
      presenterEntryUrl: Uri.parse(
        'https://reports.example/presenter/index.html',
      ),
      bridgeRoot: root,
    );
    await client.dispose();

    expect(
      () => client.listTemplates(),
      throwsA(isA<BridgeRuntimeException>()),
    );
  });

  test(
    'owns one shared HttpClient across HTTP collaborators until dispose',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final path = request.uri.path;
        if (path == '/api/health') {
          await _writeJson(request, <String, dynamic>{'status': 'ok'});
          return;
        }
        if (path == '/presenter/index.html') {
          request.response.headers.contentType = ContentType.html;
          request.response.write('<!doctype html><html>Presenter</html>');
          await request.response.close();
          return;
        }
        if (path == '/api/presenter/systems') {
          expect(request.headers.value('X-Tenant-Id'), 'tenant_demo');
          expect(request.headers.value('Not-Approved'), isNull);
          await _writeJson(request, <String, dynamic>{
            'success': true,
            'data': <String, dynamic>{
              'items': <Map<String, dynamic>>[
                <String, dynamic>{'id': 1, 'code': 'erp', 'name': 'ERP'},
              ],
            },
          });
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      var factoryCalls = 0;
      final sharedClient = HttpClient();
      addTearDown(() {
        try {
          sharedClient.close(force: true);
        } catch (_) {}
      });

      final root = await Directory.systemTemp.createTemp(
        'bridge_client_shared_http_',
      );
      addTearDown(() => root.delete(recursive: true));
      final client = ReportingBridgeClient(
        apiBaseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
        presenterEntryUrl: Uri.parse(
          'http://127.0.0.1:${server.port}/presenter/index.html',
        ),
        bridgeRoot: root,
        headers: const <String, String>{
          'X-Tenant-Id': 'tenant_demo',
          'Not-Approved': 'blocked',
        },
        httpClientFactory: () {
          factoryCalls++;
          return sharedClient;
        },
      );

      await client.probeEndpoints();
      final systems = await client.fetchSystems();
      expect(systems.single.id, 1);
      expect(
        factoryCalls,
        1,
        reason:
            'ReportingBridgeClient must construct one shared HttpClient once '
            'and inject it into HTTP collaborators',
      );

      await client.dispose();

      await expectLater(() async {
        final request = await sharedClient.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/api/health'),
        );
        final response = await request.close();
        await response.drain<void>();
      }(), throwsA(isA<Object>()));
    },
  );
}

List<int> _presenterZipBytes() {
  final archive = Archive();
  final files = _validPureDartBundleEntries();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.string(entry.key, entry.value));
  }
  return ZipEncoder().encode(archive);
}

Map<String, String> _validPureDartBundleEntries() {
  const fontHash =
      'a446817d40e4dc37c526fb5e30859fe0dd7bb0a7d5b3c0c56f7a0626d0019307';
  const iconHash =
      '6cbd50037e50937c7aa9ad4a2de7770c8f5db9455c1be9e021bc236060dafa21';
  final resources = <String, String>{
    for (final path in PresenterBundleContract.requiredResourceFiles)
      path: path == 'icons/MaterialIcons-Regular.ttf' ? iconHash : fontHash,
  };
  return <String, String>{
    'index.html': '<!doctype html><html><head><base href="/"></head></html>',
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

Future<void> _writeJson(HttpRequest request, Map<String, dynamic> body) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}
