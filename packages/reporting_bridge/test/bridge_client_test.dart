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
        if (path == '/api/presenter/templates/query') {
          expect(request.method, 'POST');
          final body = Map<String, dynamic>.from(
            jsonDecode(await utf8.decoder.bind(request).join()) as Map,
          );
          expect(body['systemCode'], 'erp');
          await _writeJson(
            request,
            _queryEnvelope(<Map<String, dynamic>>[
              _queryTemplate('invoice-7', 7, 'invoice', systemCode: 'erp'),
            ], systemCode: 'erp'),
          );
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
      final templateSync = await client.syncTemplates(systemCode: 'erp');
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

      final template = (await client.listTemplates(systemCode: 'erp')).single;
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
      () => client.listTemplates(systemCode: 'erp'),
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
        if (path == '/api/presenter/templates/query') {
          expect(request.headers.value('X-Tenant-Id'), 'tenant_demo');
          expect(request.headers.value('Not-Approved'), isNull);
          await utf8.decoder.bind(request).join();
          await _writeJson(
            request,
            _queryEnvelope(<Map<String, dynamic>>[
              _queryTemplate('shared-1', 7, 'invoice', systemCode: 'erp'),
            ], systemCode: 'erp'),
          );
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
      await client.syncTemplates(systemCode: 'erp');
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

Map<String, dynamic> _queryEnvelope(
  List<Map<String, dynamic>> items, {
  required String systemCode,
}) {
  return <String, dynamic>{
    'success': true,
    'message': 'OK',
    'data': <String, dynamic>{
      'catalogRevision': 'client-test-revision',
      'system': <String, dynamic>{
        'id': 7,
        'code': systemCode,
        'name': 'ERP',
        'description': 'Client test system',
      },
      'appliedFilter': <String, dynamic>{
        'reportTypes': <String>['all'],
        'layouts': <String>['all'],
        'sizes': <String>['all'],
        'languages': <String>['all'],
        'units': <String>['all'],
        'orientations': <String>['all'],
      },
      'count': items.length,
      'items': items,
    },
  };
}

Map<String, dynamic> _queryTemplate(
  String id,
  int systemId,
  String reportType, {
  required String systemCode,
}) {
  return <String, dynamic>{
    'id': id,
    'systemId': systemId,
    'systemCode': systemCode,
    'code': '$id-code',
    'name': 'Template $id',
    'description': 'Description for $id',
    'reportType': reportType,
    'publishedVersionNo': 1,
    'metadata': <String, dynamic>{},
    'compatibility': <String, dynamic>{
      'minPresenterVersion': '1.0.0',
      'minBridgeVersion': '1.0.0',
    },
    'document': <String, dynamic>{
      'schemaVersion': '1.0.0',
      'meta': <String, dynamic>{'name': 'Template $id', 'code': '$id-code'},
      'page': <String, dynamic>{},
      'styleTokens': <String, dynamic>{},
      'assets': <Object?>[],
      'layers': <Object?>[],
      'elements': <Object?>[],
    },
  };
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
