import 'dart:convert';
import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('deployed server URL derives API and Presenter entry paths', () {
    final endpoints = ReportServerEndpoints.deployed(
      Uri.parse('https://mdev.yemensoft.net:473'),
    );

    expect(endpoints.profile, ReportServerProfile.deployed);
    expect(endpoints.serverUrl.toString(), 'https://mdev.yemensoft.net:473');
    expect(
      endpoints.apiBaseUrl.toString(),
      'https://mdev.yemensoft.net:473/UltimateReport/backend/api/',
    );
    expect(
      endpoints.presenterEntryUrl.toString(),
      'https://mdev.yemensoft.net:473/UltimateReport/apps/presenter/index.html',
    );
    expect(
      endpoints.cacheIdentityBaseUrl.toString(),
      'https://mdev.yemensoft.net:473/UltimateReport/backend/',
    );
  });

  test('local profile derives backend and Presenter ports from one host', () {
    final endpoints = ReportServerEndpoints.localDevelopment(
      Uri.parse('http://127.0.0.1/ignored/path'),
    );

    expect(endpoints.profile, ReportServerProfile.localDevelopment);
    expect(endpoints.serverUrl.toString(), 'http://127.0.0.1');
    expect(
      endpoints.apiBaseUrl.toString(),
      'http://127.0.0.1:8000/UltimateReport/backend/api/',
    );
    expect(
      endpoints.presenterEntryUrl.toString(),
      'http://127.0.0.1:8080/UltimateReport/apps/presenter/index.html',
    );
    expect(endpoints.cacheIdentityBaseUrl.toString(), 'http://127.0.0.1:8000/');
  });

  test(
    'local and deployed profiles expose identical public route prefixes',
    () {
      final deployed = ReportServerEndpoints.deployed(
        Uri.parse('https://mdev.yemensoft.net:473'),
      );
      final local = ReportServerEndpoints.localDevelopment(
        Uri.parse('http://127.0.0.1'),
      );

      expect(deployed.apiBaseUrl.path, '/UltimateReport/backend/api/');
      expect(local.apiBaseUrl.path, '/UltimateReport/backend/api/');
      expect(
        deployed.presenterEntryUrl.path,
        '/UltimateReport/apps/presenter/index.html',
      );
      expect(
        local.presenterEntryUrl.path,
        '/UltimateReport/apps/presenter/index.html',
      );
    },
  );

  test('local profile supports development port overrides', () {
    final endpoints = ReportServerEndpoints.resolve(
      serverUrl: Uri.parse('http://192.168.1.20:9999/root'),
      profile: ReportServerProfile.localDevelopment,
      localBackendPort: 18000,
      localPresenterPort: 18080,
    );

    expect(endpoints.serverUrl.toString(), 'http://192.168.1.20');
    expect(endpoints.apiBaseUrl.port, 18000);
    expect(endpoints.presenterEntryUrl.port, 18080);
  });

  test('server normalization removes paths, query, and fragment', () {
    final endpoints = ReportServerEndpoints.deployed(
      Uri.parse('https://example.test:9443/old/path?token=ignored#section'),
    );

    expect(endpoints.serverUrl.toString(), 'https://example.test:9443');
    expect(
      endpoints.presenterEntryUrl.path,
      '/UltimateReport/apps/presenter/index.html',
    );
  });

  test('report server profiles parse exact canonical values only', () {
    expect(
      ReportServerProfileX.tryParse('localDevelopment'),
      ReportServerProfile.localDevelopment,
    );
    expect(
      ReportServerProfileX.tryParse('deployed'),
      ReportServerProfile.deployed,
    );
    expect(ReportServerProfileX.tryParse('local'), isNull);
  });

  test('rejects unsupported URLs, credentials, and invalid local ports', () {
    expect(
      () => ReportServerEndpoints.parseServerUrl('example.test'),
      throwsA(isA<BridgeRuntimeException>()),
    );
    expect(
      () => ReportServerEndpoints.deployed(Uri.parse('ftp://example.test')),
      throwsA(isA<BridgeRuntimeException>()),
    );
    expect(
      () => ReportServerEndpoints.deployed(
        Uri.parse('https://user:secret@example.test'),
      ),
      throwsA(isA<BridgeRuntimeException>()),
    );
    expect(
      () => ReportServerEndpoints.localDevelopment(
        Uri.parse('http://127.0.0.1'),
        backendPort: 0,
      ),
      throwsA(isA<BridgeRuntimeException>()),
    );
  });

  test('infers deployed origin from legacy API or Presenter URL', () {
    expect(
      ReportServerEndpoints.inferDeployedServerUrl(
        'https://example.test/UltimateReport/backend/api/',
      ).toString(),
      'https://example.test',
    );
    expect(
      ReportServerEndpoints.inferDeployedServerUrl(
        'https://example.test/UltimateReport/apps/presenter/',
      ).toString(),
      'https://example.test',
    );
  });

  test('historical and canonical API source forms remain equivalent', () {
    final deployedCanonical = Uri.parse(
      'https://example.test:473/UltimateReport/backend/api/',
    );
    final localCanonical = Uri.parse(
      'http://127.0.0.1:8000/UltimateReport/backend/api/',
    );
    expect(
      sameBridgeApiBaseUrl(
        'https://example.test:473/UltimateReport/backend/',
        deployedCanonical,
      ),
      isTrue,
    );
    expect(
      sameBridgeApiBaseUrl('http://127.0.0.1:8000/', localCanonical),
      isTrue,
    );
    expect(
      sameBridgeApiBaseUrl(
        'https://other.example.test:473/UltimateReport/backend/',
        deployedCanonical,
      ),
      isFalse,
    );
  });

  test('logical API routes support canonical and historical bases', () {
    expect(
      resolveBridgeApiRoute(
        Uri.parse('https://example.test/UltimateReport/backend/api/'),
        'presenter/systems',
      ).path,
      '/UltimateReport/backend/api/presenter/systems',
    );
    expect(
      resolveBridgeApiRoute(
        Uri.parse('https://example.test/UltimateReport/backend/'),
        'presenter/systems',
      ).path,
      '/UltimateReport/backend/api/presenter/systems',
    );
    expect(
      resolveBridgeApiRoute(Uri.parse('http://127.0.0.1:8000/'), 'health').path,
      '/api/health',
    );
  });

  test(
    'Bridge requests canonical health, systems, and manifest paths',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requestedPaths = <String>[];
      server.listen((request) async {
        requestedPaths.add(request.uri.path);
        switch (request.uri.path) {
          case '/UltimateReport/backend/api/health':
            request.response.statusCode = HttpStatus.ok;
            request.response.write('ok');
            break;
          case '/UltimateReport/apps/presenter/index.html':
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.contentType = ContentType.html;
            request.response.write('<!doctype html><html></html>');
            break;
          case '/UltimateReport/backend/api/presenter/systems':
            await _writeJson(request, <String, dynamic>{
              'success': true,
              'data': <String, dynamic>{
                'items': <Map<String, dynamic>>[
                  <String, dynamic>{'id': 1, 'code': 'demo', 'name': 'Demo'},
                ],
              },
            });
            return;
          case '/UltimateReport/backend/api/presenter/bundles/manifest':
            await _writeJson(request, <String, dynamic>{
              'success': true,
              'data': <String, dynamic>{
                'presenterVersion': '1.0.0',
                'bundleVersion': 'canonical-path-test',
                'devVersion': 1,
                'downloadUrl': '/api/presenter/bundles/canonical-path-test',
                'available': true,
                'enforceUpdate': false,
              },
            });
            return;
          default:
            request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final root = await Directory.systemTemp.createTemp(
        'bridge_canonical_api_',
      );
      addTearDown(() => root.delete(recursive: true));
      final origin = 'http://127.0.0.1:${server.port}';
      final apiBase = Uri.parse('$origin/UltimateReport/backend/api/');
      final client = ReportingBridgeClient(
        apiBaseUrl: apiBase,
        presenterEntryUrl: Uri.parse(
          '$origin/UltimateReport/apps/presenter/index.html',
        ),
        bridgeRoot: root,
      );
      addTearDown(client.dispose);

      await client.probeEndpoints();
      final systems = await client.fetchSystems();
      expect(systems.single.code, 'demo');

      final presenterCache = PresenterCacheService(
        presenterRoot: Directory('${root.path}/presenter-manifest-probe'),
      );
      final manifest = await presenterCache.fetchRemoteManifest(
        bundleManifestUrl: null,
        apiBaseUrl: apiBase.toString(),
      );
      expect(manifest.bundleVersion, 'canonical-path-test');

      expect(
        requestedPaths,
        containsAll(<String>[
          '/UltimateReport/backend/api/health',
          '/UltimateReport/apps/presenter/index.html',
          '/UltimateReport/backend/api/presenter/systems',
          '/UltimateReport/backend/api/presenter/bundles/manifest',
        ]),
      );
      expect(requestedPaths.where((p) => p.contains('/api/api/')), isEmpty);
    },
  );
}

Future<void> _writeJson(
  HttpRequest request,
  Map<String, dynamic> payload,
) async {
  request.response.statusCode = HttpStatus.ok;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(payload));
  await request.response.close();
}
