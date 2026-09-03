import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('RuntimeSessionStorage', () {
    test(
      'writes runtime JSON files and redacts custom headers in session.json',
      () async {
        final temp = await Directory.systemTemp.createTemp('bridge_runtime_');
        addTearDown(() => temp.delete(recursive: true));
        final storage = RuntimeSessionStorage(runtimeRoot: temp);

        final session = await storage.prepareRuntimeSession(
          const RuntimeSessionInput(
            sessionId: 'invoice-session',
            reportType: 'invoice',
            reportName: 'Sales Invoice',
            mode: 'offline',
            locale: 'ar',
            direction: 'rtl',
            presenterUrl: 'http://127.0.0.1:8080',
            seedData: <String, dynamic>{
              'ReportHeader': <String, dynamic>{'DocNo': 'INV-1'},
            },
            templateDocument: <String, dynamic>{
              'meta': <String, dynamic>{'version': '1'},
            },
            selectedTemplate: SelectedTemplate(id: '34', type: 'invoice'),
            branding: BrandConfig(primaryColor: '#2563EB'),
            apiHeaders: ApiHeaderConfig(<String, String>{
              'Authorization': 'Bearer secret-token',
              'X-Tenant-Id': 'tenant-secret',
            }),
          ),
        );

        expect(session.sessionId, 'invoice-session');
        expect(await File(session.seedReportData!.path).exists(), isTrue);
        expect(await File(session.template!.path).exists(), isTrue);
        expect(await File(session.session!.path).exists(), isTrue);
        expect(
          session.seedReportData!.url,
          '/runtime/invoice-session/seed_report_data.json',
        );
        expect(session.template!.url, '/runtime/invoice-session/template.json');

        final sessionJson =
            jsonDecode(await File(session.session!.path).readAsString()) as Map;
        expect(sessionJson['apiHeaders'], <String, dynamic>{
          'present': true,
          'redactedKeys': <String>['Authorization', 'X-Tenant-Id'],
        });
        expect(sessionJson.toString(), isNot(contains('secret-token')));
        expect(sessionJson.toString(), isNot(contains('tenant-secret')));
      },
    );

    test('rejects empty template document', () async {
      final temp = await Directory.systemTemp.createTemp('bridge_runtime_');
      addTearDown(() => temp.delete(recursive: true));
      final storage = RuntimeSessionStorage(runtimeRoot: temp);

      expect(
        () => storage.prepareRuntimeSession(
          const RuntimeSessionInput(
            sessionId: 'bad-template',
            reportType: 'invoice',
            seedData: <String, dynamic>{},
            templateDocument: <String, dynamic>{},
          ),
        ),
        throwsA(
          isA<BridgeRuntimeException>().having(
            (error) => error.code,
            'code',
            BridgeRuntimeErrorCodes.templateDocumentInvalid,
          ),
        ),
      );
    });
  });

  test(
    'writes canonical new-schema sample through runtime session storage',
    () async {
      final raw = _canonicalTemplateFixture();

      final temp = await Directory.systemTemp.createTemp('bridge_canonical_');
      addTearDown(() => temp.delete(recursive: true));
      final storage = RuntimeSessionStorage(runtimeRoot: temp);

      final session = await storage.prepareRuntimeSession(
        RuntimeSessionInput(
          sessionId: 'canonical-invoice',
          reportType: 'invoice',
          reportName: 'Full Coverage Invoice',
          mode: 'offline',
          locale: 'en',
          direction: 'ltr',
          presenterUrl: 'http://127.0.0.1:8080',
          seedData: <String, dynamic>{
            'ReportMst': <String, dynamic>{
              'InvoiceNo': <String, dynamic>{'value': 'INV-001'},
            },
          },
          templateDocument: raw,
          selectedTemplate: const SelectedTemplate(
            id: 'canonical',
            type: 'invoice',
          ),
        ),
      );

      expect(session.sessionId, 'canonical-invoice');

      // Template file was written and key new-schema fields survive
      final templateJson =
          jsonDecode(await File(session.template!.path).readAsString())
              as Map<String, dynamic>;
      expect(templateJson['schemaVersion'], '1.0.0');
      expect(templateJson['page']['size'], 'A4');
      expect(templateJson['meta']['family'], 'invoice');

      // Elements exist with new-schema structure
      final elements = templateJson['elements'] as List;
      expect(elements.length, greaterThan(5));

      // Table element preserves new-schema sub-structure
      final table =
          elements.firstWhere((e) => (e as Map)['type'] == 'table') as Map;
      expect(table['columns'], isNotEmpty);
      expect(table['header'], isNotNull);
      expect(table['body'], isNotNull);
      final col = (table['columns'] as List).first as Map;
      final columnContent = col['content'] as Map;
      expect(columnContent['header'], isNotNull);
      expect(columnContent['body'], isNotNull);
      expect(columnContent['footer'], isNotNull);

      // Text element has visibility object
      final textElem =
          elements.firstWhere((e) => (e as Map)['type'] == 'text') as Map;
      expect(textElem['visibility']['visible'], isTrue);
    },
  );

  group('TemplateCacheService and TemplateSelectionResolver', () {
    test(
      'stores templates and resolves stored/auto/selection-required states',
      () async {
        final temp = await Directory.systemTemp.createTemp('bridge_templates_');
        addTearDown(() => temp.delete(recursive: true));
        final cache = TemplateCacheService(cacheRoot: temp);
        final resolver = TemplateSelectionResolver(cache: cache);

        await cache.putTemplate(
          const CachedTemplate(
            id: '34',
            type: 'invoice',
            systemId: 10,
            document: <String, dynamic>{
              'meta': <String, dynamic>{'version': '1'},
            },
            minPresenterDevVersion: 1,
          ),
        );
        await cache.putTemplate(
          const CachedTemplate(
            id: '35',
            type: 'invoice',
            systemId: 20,
            document: <String, dynamic>{
              'meta': <String, dynamic>{'version': '2'},
            },
            minPresenterDevVersion: 1,
          ),
        );
        await cache.putTemplate(
          const CachedTemplate(
            id: '90',
            type: 'receipt',
            document: <String, dynamic>{
              'meta': <String, dynamic>{'version': '1'},
            },
            minPresenterDevVersion: 1,
          ),
        );
        await cache.writeCatalogMetadata(
          TemplateCatalogMetadata(
            catalogRevision: 'test-revision',
            systemCode: 'test-system',
            filterFingerprint: 'test-filter',
            extraFingerprint: 'test-extra',
          ),
        );

        final systemFiltered = await cache.listTemplates(
          type: 'invoice',
          systemId: 10,
        );
        expect(systemFiltered.map((template) => template.id), <String>['34']);

        final stored = await resolver.resolveSelectedTemplate(
          reportType: 'invoice',
          systemCode: 'test-system',
          presenterDevVersion: 1,
          storedSelection: const SelectedTemplate(
            id: '34',
            type: 'invoice',
            systemCode: 'test-system',
          ),
        );
        expect(stored.status, 'stored-selected');
        expect(stored.template?.id, '34');

        final wrongType = await resolver.resolveSelectedTemplate(
          reportType: 'receipt',
          systemCode: 'test-system',
          presenterDevVersion: 1,
          storedSelection: const SelectedTemplate(
            id: '34',
            type: 'invoice',
            systemCode: 'test-system',
          ),
        );
        expect(wrongType.status, 'selection-required');
        expect(wrongType.template, isNull);
        expect(
          wrongType.errorCode,
          BridgeRuntimeErrorCodes.staleTemplateSelection,
        );

        final many = await resolver.resolveSelectedTemplate(
          reportType: 'invoice',
          systemCode: 'test-system',
          presenterDevVersion: 1,
        );
        expect(many.status, 'selection-required');
        expect(many.template, isNull);
      },
    );

    test('reports no-template and incompatible states', () async {
      final temp = await Directory.systemTemp.createTemp('bridge_templates_');
      addTearDown(() => temp.delete(recursive: true));
      final cache = TemplateCacheService(cacheRoot: temp);
      final resolver = TemplateSelectionResolver(cache: cache);

      final none = await resolver.resolveSelectedTemplate(
        reportType: 'invoice',
        systemCode: 'test-system',
        presenterDevVersion: 1,
      );
      expect(none.status, 'no-template');
      expect(none.errorCode, BridgeRuntimeErrorCodes.noTemplateAvailable);

      await cache.putTemplate(
        const CachedTemplate(
          id: '99',
          type: 'invoice',
          document: <String, dynamic>{
            'meta': <String, dynamic>{'version': '1'},
          },
          minPresenterDevVersion: 4,
        ),
      );
      await cache.writeCatalogMetadata(
        TemplateCatalogMetadata(
          catalogRevision: 'test-revision',
          systemCode: 'test-system',
          filterFingerprint: 'test-filter',
          extraFingerprint: 'test-extra',
        ),
      );
      final incompatible = await resolver.resolveSelectedTemplate(
        reportType: 'invoice',
        systemCode: 'test-system',
        presenterDevVersion: 1,
      );
      expect(incompatible.status, 'incompatible');
      expect(
        incompatible.errorCode,
        BridgeRuntimeErrorCodes.presenterVersionTooOld,
      );
    });
  });

  group('PresenterCacheService', () {
    test(
      'returns OFFLINE_ASSETS_NOT_READY when index.html is missing',
      () async {
        final temp = await Directory.systemTemp.createTemp('bridge_presenter_');
        addTearDown(() => temp.delete(recursive: true));
        final cache = PresenterCacheService(presenterRoot: temp);

        expect(
          () => cache.requireReady(bundleVersion: 'dev-local', devVersion: 1),
          throwsA(
            isA<BridgeRuntimeException>().having(
              (error) => error.code,
              'code',
              BridgeRuntimeErrorCodes.offlineAssetsNotReady,
            ),
          ),
        );
      },
    );

    test(
      'downloads manifest+zip, safely activates presenter site, and persists metadata',
      () async {
        final temp = await Directory.systemTemp.createTemp('bridge_presenter_');
        addTearDown(() => temp.delete(recursive: true));
        final presenterRoot = Directory('${temp.path}/presenter');
        await presenterRoot.create(recursive: true);
        await File(
          '${presenterRoot.path}/index.html',
        ).writeAsString('<html>old</html>');
        await File('${presenterRoot.path}/old.txt').writeAsString('stale');

        final zipBytes = _zipFromEntries(<String, String>{
          'index.html':
              '<!doctype html><head><base href="/UltimateReport/apps/presenter/"></head><body>new</body>',
          'main.dart.js': PresenterBundleContract.requiredJavaScriptMarkers
              .join(' '),
          'flutter_bootstrap.js': 'bootstrap',
          'assets/AssetManifest.bin': 'manifest',
          'assets/FontManifest.json': '[]',
          'assets/app.js': 'window.presenter=true;',
          for (final path in PresenterBundleContract.requiredFiles)
            if (path != 'main.dart.js' &&
                path != 'flutter_bootstrap.js' &&
                path != 'assets/FontManifest.json')
              path: path,
        });

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);
        server.listen((request) async {
          if (request.uri.path == '/api/presenter/bundles/manifest') {
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(<String, dynamic>{
                'success': true,
                'data': <String, dynamic>{
                  'presenterVersion': '1.0.0',
                  'bundleVersion': 'dev-local',
                  'devVersion': 1,
                  'downloadUrl': '/api/presenter/bundles/dev-local',
                  'available': true,
                },
              }),
            );
          } else if (request.uri.path == '/api/presenter/bundles/dev-local') {
            request.response.headers.contentType = ContentType.binary;
            request.response.add(zipBytes);
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
          await request.response.close();
        });

        final service = PresenterCacheService(presenterRoot: presenterRoot);
        final manifest = await service.syncPresenterSite(
          bundleManifestUrl: null,
          apiBaseUrl: 'http://127.0.0.1:${server.port}',
        );

        expect(manifest.bundleVersion, 'dev-local');
        expect(manifest.devVersion, 1);
        expect(
          await File('${presenterRoot.path}/index.html').readAsString(),
          '<!doctype html><head><base href="/UltimateReport/apps/presenter/"></head><body>new</body>',
        );
        expect(await File('${presenterRoot.path}/old.txt').exists(), isFalse);
        expect(
          await File('${presenterRoot.path}/assets/app.js').exists(),
          isTrue,
        );
        expect(await service.manifestFile.exists(), isTrue);
        final persisted =
            jsonDecode(await service.manifestFile.readAsString())
                as Map<String, dynamic>;
        expect(persisted['bundleVersion'], 'dev-local');
      },
    );

    test(
      'rejects zip traversal entries and keeps previous active site',
      () async {
        final temp = await Directory.systemTemp.createTemp('bridge_presenter_');
        addTearDown(() => temp.delete(recursive: true));
        final presenterRoot = Directory('${temp.path}/presenter');
        await presenterRoot.create(recursive: true);
        await File(
          '${presenterRoot.path}/index.html',
        ).writeAsString('<html>stable</html>');

        final zipBytes = _zipFromEntries(<String, String>{
          'index.html': '<html>unsafe</html>',
          '../escape.txt': 'bad',
        });

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);
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
            request.response.add(zipBytes);
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
          await request.response.close();
        });

        final service = PresenterCacheService(presenterRoot: presenterRoot);
        expect(
          () => service.syncPresenterSite(
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
          '<html>stable</html>',
        );
        expect(await File('${temp.path}/escape.txt').exists(), isFalse);
      },
    );

    test('clearPresenterCache removes active site and metadata', () async {
      final temp = await Directory.systemTemp.createTemp('bridge_presenter_');
      addTearDown(() => temp.delete(recursive: true));
      final presenterRoot = Directory('${temp.path}/presenter');
      await presenterRoot.create(recursive: true);
      final service = PresenterCacheService(presenterRoot: presenterRoot);
      await File(
        '${presenterRoot.path}/index.html',
      ).writeAsString('<html>ok</html>');
      await service.manifestFile.writeAsString('{}');

      await service.clearPresenterCache();

      expect(await presenterRoot.exists(), isFalse);
      expect(await service.manifestFile.exists(), isFalse);
    });

    test('normalizes an existing cached IIS index for offline localhost', () async {
      final temp = await Directory.systemTemp.createTemp('bridge_presenter_');
      addTearDown(() => temp.delete(recursive: true));
      final presenterRoot = Directory('${temp.path}/presenter');
      await presenterRoot.create(recursive: true);
      final service = PresenterCacheService(presenterRoot: presenterRoot);
      await File('${presenterRoot.path}/index.html').writeAsString(
        '<!doctype html><head><base href="/UltimateReport/apps/presenter/"></head>',
      );

      await service.normalizeCachedPresenterForOffline();

      expect(
        await File('${presenterRoot.path}/index.html').readAsString(),
        '<!doctype html><head><base href="/UltimateReport/apps/presenter/"></head>',
      );
    });
  });

  group('LocalPresenterServer', () {
    test(
      'serves only approved files on 127.0.0.1 and disables directory listing',
      () async {
        final temp = await Directory.systemTemp.createTemp('bridge_server_');
        addTearDown(() => temp.delete(recursive: true));
        final presenterRoot = Directory('${temp.path}/presenter');
        final runtimeRoot = Directory('${temp.path}/runtime');
        await presenterRoot.create(recursive: true);
        await runtimeRoot.create(recursive: true);
        await File(
          '${presenterRoot.path}/index.html',
        ).writeAsString('<html>ok</html>');
        await File(
          '${presenterRoot.path}/app.js',
        ).writeAsString('window.ok = true;');
        await Directory('${runtimeRoot.path}/s1').create(recursive: true);
        await File(
          '${runtimeRoot.path}/s1/seed_report_data.json',
        ).writeAsString('{}');

        final server = LocalPresenterServer(
          presenterRoot: presenterRoot,
          runtimeRoot: runtimeRoot,
        );
        final handle = await server.start(sessionId: 's1');
        addTearDown(handle.stop);

        expect(handle.baseUrl, startsWith('http://127.0.0.1:'));
        expect(
          handle.presenterUrl,
          '${handle.baseUrl}/UltimateReport/apps/presenter/index.html?sessionId=s1',
        );

        final client = HttpClient();
        addTearDown(client.close);

        final index = await _get(
          client,
          '${handle.baseUrl}/UltimateReport/apps/presenter/index.html',
        );
        expect(index.statusCode, HttpStatus.ok);
        expect(index.body, '<html>ok</html>');

        final runtime = await _get(
          client,
          '${handle.baseUrl}/runtime/s1/seed_report_data.json',
        );
        expect(runtime.statusCode, HttpStatus.ok);
        expect(runtime.body, '{}');

        final directory = await _get(
          client,
          '${handle.baseUrl}/UltimateReport/apps/presenter/',
        );
        expect(directory.statusCode, HttpStatus.ok);
        expect(directory.body, '<html>ok</html>');

        final rootAsset = await _get(client, '${handle.baseUrl}/app.js');
        expect(rootAsset.statusCode, HttpStatus.ok);
        expect(rootAsset.body, 'window.ok = true;');

        final prefixedAsset = await _get(
          client,
          '${handle.baseUrl}/UltimateReport/apps/presenter/app.js',
        );
        expect(prefixedAsset.statusCode, HttpStatus.ok);
        expect(prefixedAsset.body, 'window.ok = true;');

        final iisPrefixedAsset = await _get(
          client,
          '${handle.baseUrl}/UltimateReport/apps/presenter/app.js',
        );
        expect(iisPrefixedAsset.statusCode, HttpStatus.ok);
        expect(iisPrefixedAsset.body, 'window.ok = true;');

        final traversal = await _get(
          client,
          '${handle.baseUrl}/runtime/s1/../secret.json',
        );
        expect(traversal.statusCode, HttpStatus.notFound);
      },
    );

    test(
      'throws OFFLINE_ASSETS_NOT_READY when presenter cache is missing',
      () async {
        final temp = await Directory.systemTemp.createTemp('bridge_server_');
        addTearDown(() => temp.delete(recursive: true));
        final server = LocalPresenterServer(
          presenterRoot: Directory('${temp.path}/missing_presenter'),
          runtimeRoot: Directory('${temp.path}/runtime'),
        );

        expect(
          () => server.start(sessionId: 's1'),
          throwsA(
            isA<BridgeRuntimeException>().having(
              (error) => error.code,
              'code',
              BridgeRuntimeErrorCodes.offlineAssetsNotReady,
            ),
          ),
        );
      },
    );

    test(
      'starts runtime-only server without cached presenter assets',
      () async {
        final temp = await Directory.systemTemp.createTemp('bridge_server_');
        addTearDown(() => temp.delete(recursive: true));
        final runtimeRoot = Directory('${temp.path}/runtime');
        await Directory('${runtimeRoot.path}/s1').create(recursive: true);
        await File('${runtimeRoot.path}/s1/session.json').writeAsString('{}');

        final server = LocalPresenterServer(
          presenterRoot: Directory('${temp.path}/missing_presenter'),
          runtimeRoot: runtimeRoot,
        );
        final handle = await server.startRuntimeOnly(sessionId: 's1');
        addTearDown(handle.stop);
        final client = HttpClient();
        addTearDown(client.close);

        final runtime = await _get(
          client,
          '${handle.baseUrl}/runtime/s1/session.json',
        );
        expect(runtime.statusCode, HttpStatus.ok);
        expect(runtime.body, '{}');
      },
    );
  });

  group('BridgeRuntimeController', () {
    test('disposeBridge stops the local presenter server', () async {
      final temp = await Directory.systemTemp.createTemp('bridge_controller_');
      addTearDown(() => temp.delete(recursive: true));
      final presenterRoot = Directory('${temp.path}/presenter');
      final runtimeRoot = Directory('${temp.path}/runtime');
      await presenterRoot.create(recursive: true);
      await runtimeRoot.create(recursive: true);
      await File(
        '${presenterRoot.path}/index.html',
      ).writeAsString('<html>ok</html>');

      final controller = BridgeRuntimeController(
        runtimeStorage: RuntimeSessionStorage(runtimeRoot: runtimeRoot),
        localServer: LocalPresenterServer(
          presenterRoot: presenterRoot,
          runtimeRoot: runtimeRoot,
        ),
      );
      final handle = await controller.startLocalPresenterServer(
        sessionId: 's1',
      );
      final client = HttpClient();
      addTearDown(client.close);

      final beforeDispose = await _get(
        client,
        '${handle.baseUrl}/UltimateReport/apps/presenter/index.html',
      );
      expect(beforeDispose.statusCode, HttpStatus.ok);

      await controller.disposeBridge();

      expect(
        () => _get(
          client,
          '${handle.baseUrl}/UltimateReport/apps/presenter/index.html',
        ),
        throwsA(isA<Object>()),
      );
      await controller.disposeBridge();
    });
  });
}

Map<String, dynamic> _canonicalTemplateFixture() {
  return <String, dynamic>{
    'schemaVersion': '1.0.0',
    'meta': <String, dynamic>{
      'name': 'Bridge Canonical Invoice Fixture',
      'family': 'invoice',
    },
    'page': <String, dynamic>{'size': 'A4'},
    'styleTokens': <String, dynamic>{},
    'assets': <Object>[],
    'layers': <Map<String, dynamic>>[
      <String, dynamic>{'id': 'default', 'name': 'Default'},
    ],
    'elements': <Map<String, dynamic>>[
      for (var index = 0; index < 5; index++)
        <String, dynamic>{
          'id': 'text-$index',
          'type': 'text',
          'layerId': 'default',
          'box': <String, dynamic>{
            'x': 10,
            'y': 10 + (index * 10),
            'width': 100,
            'height': 8,
          },
          'visibility': <String, dynamic>{'visible': true, 'locked': false},
          'content': <String, dynamic>{
            'source': 'static',
            'value': 'Text $index',
          },
        },
      <String, dynamic>{
        'id': 'table-1',
        'type': 'table',
        'layerId': 'default',
        'box': <String, dynamic>{'x': 10, 'y': 70, 'width': 180, 'height': 80},
        'visibility': <String, dynamic>{'visible': true, 'locked': false},
        'content': <String, dynamic>{
          'source': 'binding',
          'mode': 'objectArray',
          'rowsPath': 'ReportDtl.RowData',
          'headerPath': null,
        },
        'columns': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'column-1',
            'width': '100%',
            'content': <String, dynamic>{
              'header': <String, dynamic>{'source': 'static', 'value': 'Item'},
              'body': <String, dynamic>{
                'source': 'binding',
                'path': 'ItemName',
              },
              'footer': <String, dynamic>{'source': 'static', 'value': 'Total'},
            },
          },
        ],
        'header': <String, dynamic>{'visible': true, 'height': 24},
        'body': <String, dynamic>{'rowHeight': 24},
      },
    ],
  };
}

Future<_HttpBody> _get(HttpClient client, String url) async {
  final request = await client.getUrl(Uri.parse(url));
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

List<int> _zipFromEntries(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive);
}
