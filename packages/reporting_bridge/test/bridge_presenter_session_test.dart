import 'dart:convert';
import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test(
    'online session preserves runtime JSON and replaces active session',
    () async {
      final api = await _startManifestServer();
      addTearDown(() => api.close(force: true));
      final root = await Directory.systemTemp.createTemp(
        'bridge_session_online_',
      );
      addTearDown(() => root.delete(recursive: true));

      final coordinator = _coordinator(
        root: root,
        apiBaseUrl: Uri.parse('http://127.0.0.1:${api.port}/'),
      );
      addTearDown(coordinator.dispose);
      final seed = <String, dynamic>{
        'ReportId': 'invoice',
        'rows': <dynamic>[
          <String, dynamic>{'id': 1, 'value': null},
          <String, dynamic>{
            'id': 2,
            'nested': <String, dynamic>{'ok': true},
          },
        ],
      };

      final first = await coordinator.prepare(
        PresenterSessionRequest(
          sessionId: 'online-first',
          reportType: 'invoice',
          reportName: 'Invoice',
          mode: PresenterSessionMode.online,
          seedData: seed,
          template: _template('invoice-template'),
          locale: 'ar',
          direction: 'rtl',
        ),
      );

      final firstUri = Uri.parse(first.presenterUrl);
      expect(firstUri.scheme, 'http');
      expect(firstUri.host, '127.0.0.1');
      expect(firstUri.path, '/UltimateReport/apps/presenter/index.html');
      expect(firstUri.queryParameters['existing'], '1');
      expect(firstUri.queryParameters['sessionId'], 'online-first');
      expect(firstUri.queryParameters['locale'], 'ar');
      expect(firstUri.queryParameters['dir'], 'rtl');
      expect(firstUri.queryParameters['runtimeBaseUrl'], isNull);
      expect(first.presenterVersion, '1.2.3');
      expect(first.presenterDevVersion, 12);

      final firstSeed = File(
        '${root.path}/runtime/online-first/seed_report_data.json',
      );
      expect(jsonDecode(await firstSeed.readAsString()), seed);

      final second = await coordinator.prepare(
        PresenterSessionRequest(
          sessionId: 'online-second',
          reportType: 'invoice',
          reportName: 'Invoice',
          mode: PresenterSessionMode.online,
          seedData: <String, dynamic>{
            'unchanged': <dynamic>[1, 2, 3],
          },
          template: _template('invoice-template'),
        ),
      );

      expect(second.sessionId, 'online-second');
      expect(await firstSeed.exists(), isFalse);
      final secondDir = Directory('${root.path}/runtime/online-second');
      expect(await secondDir.exists(), isTrue);

      await coordinator.stop();
      expect(await secondDir.exists(), isFalse);
      expect(coordinator.activeSessionId, isNull);
    },
  );

  test(
    'coordinator.stop terminal-stops the shared localhost proxy server',
    () async {
      final api = await _startManifestServer();
      addTearDown(() => api.close(force: true));
      final upstream = await _startOnlinePresenterUpstream();
      addTearDown(() => upstream.close(force: true));
      final root = await Directory.systemTemp.createTemp(
        'bridge_session_stop_terminal_',
      );
      addTearDown(() => root.delete(recursive: true));
      final coordinator = _coordinator(
        root: root,
        apiBaseUrl: Uri.parse('http://127.0.0.1:${api.port}/'),
        onlinePresenterUrl: Uri.parse(
          'http://127.0.0.1:${upstream.port}'
          '/UltimateReport/apps/presenter/index.html?existing=1',
        ),
      );
      addTearDown(coordinator.dispose);

      final launch = await coordinator.prepare(
        PresenterSessionRequest(
          sessionId: 'stop-online',
          reportType: 'invoice',
          reportName: 'Invoice',
          mode: PresenterSessionMode.online,
          seedData: const <String, dynamic>{'value': 1},
          template: _template('invoice-template'),
        ),
      );
      final launchUri = Uri.parse(launch.presenterUrl);
      expect(
        await _httpStatus(_runtimeSeedUrl(launchUri, 'stop-online')),
        HttpStatus.ok,
      );
      expect(await _httpStatus(launch.presenterUrl), HttpStatus.ok);

      await coordinator.stop();

      expect(
        await Directory('${root.path}/runtime/stop-online').exists(),
        isFalse,
      );
      expect(coordinator.activeSessionId, isNull);
      await _expectLocalhostUnreachable(launch.presenterUrl);
    },
  );

  test(
    'offline session uses cached presenter and cleans runtime files',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bridge_session_offline_',
      );
      addTearDown(() => root.delete(recursive: true));
      final presenterRoot = Directory('${root.path}/presenter');
      await presenterRoot.create(recursive: true);
      final index = File('${presenterRoot.path}/index.html');
      await index.writeAsString(
        '<!doctype html><html><head><base href="/"></head></html>',
      );
      await _writeCachedManifest(
        root,
        presenterVersion: '2.0.0',
        devVersion: 20,
      );
      await _writeReadyPresenterSite(presenterRoot);

      final coordinator = _coordinator(
        root: root,
        apiBaseUrl: Uri.parse('https://reports.example/'),
      );
      addTearDown(coordinator.dispose);

      final launch = await coordinator.prepare(
        PresenterSessionRequest(
          sessionId: 'offline-one',
          reportType: 'invoice',
          reportName: 'Invoice',
          mode: PresenterSessionMode.offline,
          seedData: <String, dynamic>{'value': 'kept'},
          template: _template('invoice-template'),
          locale: 'ar',
          direction: 'rtl',
        ),
      );

      final uri = Uri.parse(launch.presenterUrl);
      expect(uri.host, '127.0.0.1');
      expect(uri.path, '/UltimateReport/apps/presenter/index.html');
      expect(uri.queryParameters['sessionId'], 'offline-one');
      expect(uri.queryParameters['locale'], 'ar');
      expect(uri.queryParameters['dir'], 'rtl');
      expect(launch.presenterVersion, '2.0.0');
      expect(launch.presenterManifest?.bundleVersion, 'offline-20');
      expect(
        await index.readAsString(),
        contains('<base href="/UltimateReport/apps/presenter/">'),
      );

      await coordinator.stop();
      expect(
        await Directory('${root.path}/runtime/offline-one').exists(),
        isFalse,
      );
    },
  );

  test(
    'offline session accepts cached manifest from canonical api base',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bridge_session_offline_canonical_',
      );
      addTearDown(() => root.delete(recursive: true));
      final presenterRoot = Directory('${root.path}/presenter');
      await _writeReadyPresenterSite(presenterRoot);
      const canonicalManifestUrl =
          'https://reports.example/UltimateReport/backend/api/'
          'presenter/bundles/manifest';
      await _writeCachedManifest(
        root,
        presenterVersion: '2.0.0',
        devVersion: 20,
        manifestUrl: canonicalManifestUrl,
      );

      final coordinator = _coordinator(
        root: root,
        apiBaseUrl: Uri.parse(
          'https://reports.example/UltimateReport/backend/api/',
        ),
      );
      addTearDown(coordinator.dispose);

      final cached = await coordinator.loadCachedManifest();
      expect(cached, isNotNull);
      expect(canonicalManifestUrl, isNot(contains('/api/api/')));

      final launch = await coordinator.prepare(
        PresenterSessionRequest(
          sessionId: 'offline-canonical',
          reportType: 'invoice',
          reportName: 'Invoice',
          mode: PresenterSessionMode.offline,
          seedData: const <String, dynamic>{'value': 'kept'},
          template: _template('invoice-template'),
        ),
      );

      expect(launch.presenterVersion, '2.0.0');
      expect(launch.presenterManifest?.bundleVersion, 'offline-20');
      expect(
        Uri.parse(launch.presenterUrl).path,
        '/UltimateReport/apps/presenter/index.html',
      );
    },
  );

  test(
    'offline session rejects a cached manifest with an incompatible site',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bridge_session_offline_stale_',
      );
      addTearDown(() => root.delete(recursive: true));
      final presenterRoot = Directory('${root.path}/presenter');
      await presenterRoot.create(recursive: true);
      await File('${presenterRoot.path}/index.html').writeAsString(
        '<!doctype html><html><head><base href="/"></head></html>',
      );
      await _writeCachedManifest(
        root,
        presenterVersion: '2.0.0',
        devVersion: 20,
      );
      final coordinator = _coordinator(
        root: root,
        apiBaseUrl: Uri.parse('https://reports.example/'),
      );
      addTearDown(coordinator.dispose);

      await expectLater(
        coordinator.prepare(
          PresenterSessionRequest(
            sessionId: 'offline-stale',
            reportType: 'invoice',
            reportName: 'Invoice',
            mode: PresenterSessionMode.offline,
            seedData: const <String, dynamic>{'value': 'kept'},
            template: _template('invoice-template'),
          ),
        ),
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
    'reloads the persisted manifest instead of keeping a stale version',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bridge_session_manifest_',
      );
      addTearDown(() => root.delete(recursive: true));
      final coordinator = _coordinator(
        root: root,
        apiBaseUrl: Uri.parse('https://reports.example/'),
      );
      addTearDown(coordinator.dispose);

      await _writeCachedManifest(
        root,
        presenterVersion: '1.0.0',
        devVersion: 10,
      );
      expect(
        (await coordinator.loadCachedManifest())?.presenterVersion,
        '1.0.0',
      );

      await _writeCachedManifest(
        root,
        presenterVersion: '2.0.0',
        devVersion: 20,
      );
      expect(
        (await coordinator.loadCachedManifest())?.presenterVersion,
        '2.0.0',
      );
    },
  );

  test(
    'rejects a template from another report type before writing files',
    () async {
      final api = await _startManifestServer();
      addTearDown(() => api.close(force: true));
      final root = await Directory.systemTemp.createTemp(
        'bridge_session_invalid_',
      );
      addTearDown(() => root.delete(recursive: true));
      final coordinator = _coordinator(
        root: root,
        apiBaseUrl: Uri.parse('http://127.0.0.1:${api.port}/'),
      );
      addTearDown(coordinator.dispose);

      await expectLater(
        coordinator.prepare(
          PresenterSessionRequest(
            sessionId: 'must-not-exist',
            reportType: 'invoice',
            reportName: 'Invoice',
            mode: PresenterSessionMode.online,
            seedData: const <String, dynamic>{'value': 1},
            template: CachedTemplate(
              id: 'voucher-template',
              type: 'voucher',
              document: const <String, dynamic>{'meta': <String, dynamic>{}},
            ),
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
      expect(
        await Directory('${root.path}/runtime/must-not-exist').exists(),
        isFalse,
      );
    },
  );

  test('failed replacement preserves the active session', () async {
    final api = await _startManifestServer();
    addTearDown(() => api.close(force: true));
    final root = await Directory.systemTemp.createTemp(
      'bridge_session_replacement_',
    );
    addTearDown(() => root.delete(recursive: true));
    final coordinator = _coordinator(
      root: root,
      apiBaseUrl: Uri.parse('http://127.0.0.1:${api.port}/'),
    );
    addTearDown(coordinator.dispose);

    await coordinator.prepare(
      PresenterSessionRequest(
        sessionId: 'active',
        reportType: 'invoice',
        reportName: 'Invoice',
        mode: PresenterSessionMode.online,
        seedData: const <String, dynamic>{'value': 1},
        template: _template('invoice-template'),
      ),
    );

    await expectLater(
      coordinator.prepare(
        PresenterSessionRequest(
          sessionId: 'replacement',
          reportType: 'invoice',
          reportName: 'Invoice',
          mode: PresenterSessionMode.online,
          seedData: const <String, dynamic>{'value': 2},
          template: CachedTemplate(
            id: 'wrong-type',
            type: 'voucher',
            document: const <String, dynamic>{'meta': <String, dynamic>{}},
          ),
        ),
      ),
      throwsA(isA<BridgeRuntimeException>()),
    );

    expect(coordinator.activeSessionId, 'active');
    expect(await Directory('${root.path}/runtime/active').exists(), isTrue);
  });

  test('staged replacement commits only after explicit confirmation', () async {
    final api = await _startManifestServer();
    addTearDown(() => api.close(force: true));
    final root = await Directory.systemTemp.createTemp(
      'bridge_session_staged_commit_',
    );
    addTearDown(() => root.delete(recursive: true));
    final coordinator = _coordinator(
      root: root,
      apiBaseUrl: Uri.parse('http://127.0.0.1:${api.port}/'),
    );
    addTearDown(coordinator.dispose);

    await coordinator.prepare(
      PresenterSessionRequest(
        sessionId: 'active',
        reportType: 'invoice',
        reportName: 'Invoice',
        mode: PresenterSessionMode.online,
        seedData: const <String, dynamic>{'value': 1},
        template: _template('invoice-template'),
      ),
    );
    final staged = await coordinator.prepare(
      PresenterSessionRequest(
        sessionId: 'candidate',
        reportType: 'invoice',
        reportName: 'Invoice',
        mode: PresenterSessionMode.online,
        seedData: const <String, dynamic>{'value': 2},
        template: _template('invoice-template'),
      ),
      deferReplacementCommit: true,
    );

    expect(staged.sessionId, 'candidate');
    expect(coordinator.activeSessionId, 'active');
    expect(await Directory('${root.path}/runtime/active').exists(), isTrue);
    expect(await Directory('${root.path}/runtime/candidate').exists(), isTrue);

    await coordinator.commitStaged();

    expect(coordinator.activeSessionId, 'candidate');
    expect(await Directory('${root.path}/runtime/active').exists(), isFalse);
    expect(await Directory('${root.path}/runtime/candidate').exists(), isTrue);
  });

  test(
    'discarding a staged replacement preserves the active session',
    () async {
      final api = await _startManifestServer();
      addTearDown(() => api.close(force: true));
      final root = await Directory.systemTemp.createTemp(
        'bridge_session_staged_discard_',
      );
      addTearDown(() => root.delete(recursive: true));
      final coordinator = _coordinator(
        root: root,
        apiBaseUrl: Uri.parse('http://127.0.0.1:${api.port}/'),
      );
      addTearDown(coordinator.dispose);

      await coordinator.prepare(
        PresenterSessionRequest(
          sessionId: 'active',
          reportType: 'invoice',
          reportName: 'Invoice',
          mode: PresenterSessionMode.online,
          seedData: const <String, dynamic>{'value': 1},
          template: _template('invoice-template'),
        ),
      );
      await coordinator.prepare(
        PresenterSessionRequest(
          sessionId: 'candidate',
          reportType: 'invoice',
          reportName: 'Invoice',
          mode: PresenterSessionMode.online,
          seedData: const <String, dynamic>{'value': 2},
          template: _template('invoice-template'),
        ),
        deferReplacementCommit: true,
      );

      await coordinator.discardStaged();

      expect(coordinator.activeSessionId, 'active');
      expect(await Directory('${root.path}/runtime/active').exists(), isTrue);
      expect(
        await Directory('${root.path}/runtime/candidate').exists(),
        isFalse,
      );
    },
  );

  test(
    'same-mode online staged candidate shares localhost port before commit',
    () async {
      final api = await _startManifestServer();
      addTearDown(() => api.close(force: true));
      final upstream = await _startOnlinePresenterUpstream();
      addTearDown(() => upstream.close(force: true));
      final root = await Directory.systemTemp.createTemp(
        'bridge_session_staged_share_commit_',
      );
      addTearDown(() => root.delete(recursive: true));
      final coordinator = _coordinator(
        root: root,
        apiBaseUrl: Uri.parse('http://127.0.0.1:${api.port}/'),
        onlinePresenterUrl: Uri.parse(
          'http://127.0.0.1:${upstream.port}'
          '/UltimateReport/apps/presenter/index.html?existing=1',
        ),
      );
      addTearDown(coordinator.dispose);

      final active = await coordinator.prepare(
        PresenterSessionRequest(
          sessionId: 'active',
          reportType: 'invoice',
          reportName: 'Invoice',
          mode: PresenterSessionMode.online,
          seedData: const <String, dynamic>{'value': 1},
          template: _template('invoice-template'),
        ),
      );
      final candidate = await coordinator.prepare(
        PresenterSessionRequest(
          sessionId: 'candidate',
          reportType: 'invoice',
          reportName: 'Invoice',
          mode: PresenterSessionMode.online,
          seedData: const <String, dynamic>{'value': 2},
          template: _template('invoice-template'),
        ),
        deferReplacementCommit: true,
      );

      final activeUri = Uri.parse(active.presenterUrl);
      final candidateUri = Uri.parse(candidate.presenterUrl);
      expect(candidateUri.port, activeUri.port);
      expect(candidateUri.origin, activeUri.origin);
      expect(
        await _httpStatus(_runtimeSeedUrl(activeUri, 'active')),
        HttpStatus.ok,
      );
      expect(
        await _httpStatus(_runtimeSeedUrl(candidateUri, 'candidate')),
        HttpStatus.ok,
      );
      expect(await _httpStatus(active.presenterUrl), HttpStatus.ok);
      expect(await _httpStatus(candidate.presenterUrl), HttpStatus.ok);

      await coordinator.commitStaged();

      expect(coordinator.activeSessionId, 'candidate');
      expect(await Directory('${root.path}/runtime/active').exists(), isFalse);
      expect(
        await Directory('${root.path}/runtime/candidate').exists(),
        isTrue,
      );
      expect(
        await _httpStatus(_runtimeSeedUrl(activeUri, 'active')),
        HttpStatus.notFound,
      );
      expect(
        await _httpStatus(_runtimeSeedUrl(candidateUri, 'candidate')),
        HttpStatus.ok,
      );
      expect(await _httpStatus(candidate.presenterUrl), HttpStatus.ok);
    },
  );

  test(
    'same-mode online staged discard releases only the candidate session',
    () async {
      final api = await _startManifestServer();
      addTearDown(() => api.close(force: true));
      final upstream = await _startOnlinePresenterUpstream();
      addTearDown(() => upstream.close(force: true));
      final root = await Directory.systemTemp.createTemp(
        'bridge_session_staged_share_discard_',
      );
      addTearDown(() => root.delete(recursive: true));
      final coordinator = _coordinator(
        root: root,
        apiBaseUrl: Uri.parse('http://127.0.0.1:${api.port}/'),
        onlinePresenterUrl: Uri.parse(
          'http://127.0.0.1:${upstream.port}'
          '/UltimateReport/apps/presenter/index.html?existing=1',
        ),
      );
      addTearDown(coordinator.dispose);

      final active = await coordinator.prepare(
        PresenterSessionRequest(
          sessionId: 'active',
          reportType: 'invoice',
          reportName: 'Invoice',
          mode: PresenterSessionMode.online,
          seedData: const <String, dynamic>{'value': 1},
          template: _template('invoice-template'),
        ),
      );
      final candidate = await coordinator.prepare(
        PresenterSessionRequest(
          sessionId: 'candidate',
          reportType: 'invoice',
          reportName: 'Invoice',
          mode: PresenterSessionMode.online,
          seedData: const <String, dynamic>{'value': 2},
          template: _template('invoice-template'),
        ),
        deferReplacementCommit: true,
      );

      final activeUri = Uri.parse(active.presenterUrl);
      final candidateUri = Uri.parse(candidate.presenterUrl);
      expect(candidateUri.port, activeUri.port);

      await coordinator.discardStaged();

      expect(coordinator.activeSessionId, 'active');
      expect(await Directory('${root.path}/runtime/active').exists(), isTrue);
      expect(
        await Directory('${root.path}/runtime/candidate').exists(),
        isFalse,
      );
      expect(
        await _httpStatus(_runtimeSeedUrl(activeUri, 'active')),
        HttpStatus.ok,
      );
      expect(await _httpStatus(active.presenterUrl), HttpStatus.ok);
      expect(
        await _httpStatus(_runtimeSeedUrl(candidateUri, 'candidate')),
        HttpStatus.notFound,
      );
    },
  );

  test(
    'mixed online-to-offline staged candidate uses a distinct localhost port',
    () async {
      final api = await _startManifestServer();
      addTearDown(() => api.close(force: true));
      final upstream = await _startOnlinePresenterUpstream();
      addTearDown(() => upstream.close(force: true));
      final root = await Directory.systemTemp.createTemp(
        'bridge_session_staged_mixed_',
      );
      addTearDown(() => root.delete(recursive: true));
      final presenterRoot = Directory('${root.path}/presenter');
      await _writeReadyPresenterSite(presenterRoot);
      final apiBaseUrl = Uri.parse('http://127.0.0.1:${api.port}/');
      await _writeCachedManifest(
        root,
        presenterVersion: '2.0.0',
        devVersion: 20,
        manifestUrl:
            'http://127.0.0.1:${api.port}/api/presenter/bundles/manifest',
      );

      final coordinator = _coordinator(
        root: root,
        apiBaseUrl: apiBaseUrl,
        onlinePresenterUrl: Uri.parse(
          'http://127.0.0.1:${upstream.port}'
          '/UltimateReport/apps/presenter/index.html?existing=1',
        ),
      );
      addTearDown(coordinator.dispose);

      final active = await coordinator.prepare(
        PresenterSessionRequest(
          sessionId: 'active-online',
          reportType: 'invoice',
          reportName: 'Invoice',
          mode: PresenterSessionMode.online,
          seedData: const <String, dynamic>{'value': 1},
          template: _template('invoice-template'),
        ),
      );
      final candidate = await coordinator.prepare(
        PresenterSessionRequest(
          sessionId: 'candidate-offline',
          reportType: 'invoice',
          reportName: 'Invoice',
          mode: PresenterSessionMode.offline,
          seedData: const <String, dynamic>{'value': 2},
          template: _template('invoice-template'),
        ),
        deferReplacementCommit: true,
      );

      final activeUri = Uri.parse(active.presenterUrl);
      final candidateUri = Uri.parse(candidate.presenterUrl);
      expect(
        candidateUri.port,
        isNot(activeUri.port),
        reason:
            'proxy Presenter and static offline Presenter are incompatible on one server',
      );
      expect(
        await _httpStatus(_runtimeSeedUrl(activeUri, 'active-online')),
        HttpStatus.ok,
      );
      expect(await _httpStatus(active.presenterUrl), HttpStatus.ok);
      expect(
        await _httpStatus(_runtimeSeedUrl(candidateUri, 'candidate-offline')),
        HttpStatus.ok,
      );

      await coordinator.discardStaged();

      expect(coordinator.activeSessionId, 'active-online');
      expect(
        await Directory('${root.path}/runtime/active-online').exists(),
        isTrue,
      );
      expect(
        await Directory('${root.path}/runtime/candidate-offline').exists(),
        isFalse,
      );
      expect(
        await _httpStatus(_runtimeSeedUrl(activeUri, 'active-online')),
        HttpStatus.ok,
      );
      expect(await _httpStatus(active.presenterUrl), HttpStatus.ok);
    },
  );
}

PresenterSessionCoordinator _coordinator({
  required Directory root,
  required Uri apiBaseUrl,
  Uri? onlinePresenterUrl,
}) {
  return PresenterSessionCoordinator(
    presenterCache: PresenterCacheService(
      presenterRoot: Directory('${root.path}/presenter'),
    ),
    runtimeStorage: RuntimeSessionStorage(
      runtimeRoot: Directory('${root.path}/runtime'),
    ),
    onlinePresenterUrl:
        onlinePresenterUrl ??
        Uri.parse(
          'https://reports.example/UltimateReport/apps/presenter/index.html?existing=1',
        ),
    apiBaseUrl: apiBaseUrl,
    headers: const <String, String>{
      'X-Tenant-Id': 'tenant_demo',
      'Not-Approved': 'must-not-leak',
    },
  );
}

CachedTemplate _template(String id) => CachedTemplate(
  id: id,
  type: 'invoice',
  document: const <String, dynamic>{
    'meta': <String, dynamic>{'name': 'Invoice'},
    'elements': <dynamic>[],
  },
);

Future<void> _writeReadyPresenterSite(Directory presenterRoot) async {
  await presenterRoot.create(recursive: true);
  await File(
    '${presenterRoot.path}/index.html',
  ).writeAsString('<!doctype html><html><head><base href="/"></head></html>');
  for (final path in PresenterBundleContract.requiredFiles) {
    final file = File('${presenterRoot.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      path == 'main.dart.js'
          ? PresenterBundleContract.requiredJavaScriptMarkers.join(' ')
          : path,
    );
  }
  final assetManifest = File('${presenterRoot.path}/assets/AssetManifest.bin');
  await assetManifest.parent.create(recursive: true);
  await assetManifest.writeAsBytes(const <int>[1]);
}

Future<void> _writeCachedManifest(
  Directory root, {
  required String presenterVersion,
  required int devVersion,
  String manifestUrl = 'https://reports.example/api/presenter/bundles/manifest',
}) async {
  await File('${root.path}/presenter_manifest.json').writeAsString(
    jsonEncode(<String, dynamic>{
      'manifestUrl': manifestUrl,
      'presenterVersion': presenterVersion,
      'bundleVersion': 'offline-$devVersion',
      'devVersion': devVersion,
    }),
  );
}

Future<HttpServer> _startManifestServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.uri.path == '/api/presenter/bundles/manifest') {
      expect(request.headers.value('X-Tenant-Id'), 'tenant_demo');
      expect(request.headers.value('Not-Approved'), isNull);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, dynamic>{
          'success': true,
          'data': <String, dynamic>{
            'available': true,
            'presenterVersion': '1.2.3',
            'bundleVersion': 'online-12',
            'devVersion': 12,
          },
        }),
      );
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  });
  return server;
}

Future<HttpServer> _startOnlinePresenterUpstream() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.uri.path.startsWith('/UltimateReport/apps/presenter/')) {
      request.response.headers.contentType = ContentType.html;
      request.response.write('<html>online presenter</html>');
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  });
  return server;
}

String _runtimeSeedUrl(Uri presenterUri, String sessionId) {
  return '${presenterUri.scheme}://${presenterUri.host}:${presenterUri.port}'
      '/runtime/$sessionId/seed_report_data.json';
}

Future<int> _httpStatus(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

Future<void> _expectLocalhostUnreachable(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 2));
    final response = await request.close().timeout(const Duration(seconds: 2));
    await response.drain<void>();
    fail(
      'Expected localhost Presenter server to be terminally unavailable, '
      'but HTTP ${response.statusCode} succeeded for $url',
    );
  } on SocketException {
    // Terminal stop: connection refused / host unreachable.
  } on HttpException {
    // Terminal stop: connection closed during handshake/request.
  } finally {
    client.close(force: true);
  }
}
