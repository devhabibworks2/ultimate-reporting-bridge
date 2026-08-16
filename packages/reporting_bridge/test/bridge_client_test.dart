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
}

List<int> _presenterZipBytes() {
  final archive = Archive();
  final files = <String, String>{
    'index.html': '<!doctype html><html><head><base href="/"></head></html>',
    'main.dart.js': PresenterBundleContract.requiredJavaScriptMarkers.join(' '),
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
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.string(entry.key, entry.value));
  }
  return ZipEncoder().encode(archive);
}

Future<void> _writeJson(HttpRequest request, Map<String, dynamic> body) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}
