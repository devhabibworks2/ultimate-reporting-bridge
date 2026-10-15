import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test(
    'online session launches verified cached Presenter instead of proxy',
    () async {
      var upstreamRequests = 0;
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        upstreamRequests++;
        request.response.write('remote presenter');
        await request.response.close();
      });
      addTearDown(() => upstream.close(force: true));
      var downloads = 0;
      final api = await _startSessionUpdateServer(
        presenterVersion: '1.2.3',
        bundleVersion: 'online-12',
        devVersion: 12,
        onDownload: () => downloads++,
      );
      addTearDown(() => api.close(force: true));
      final root = await Directory.systemTemp.createTemp(
        'bridge_session_local_',
      );
      addTearDown(() => root.delete(recursive: true));
      final presenterRoot = Directory('${root.path}/presenter');
      await _writeReadyPresenterSite(presenterRoot);
      await _writeCachedManifest(
        root,
        presenterVersion: '1.2.3',
        bundleVersion: 'online-12',
        devVersion: 12,
        manifestUrl:
            'http://127.0.0.1:${api.port}/api/presenter/bundles/manifest',
      );
      final coordinator = _coordinator(
        root: root,
        apiBaseUrl: Uri.parse('http://127.0.0.1:${api.port}/'),
      );
      addTearDown(coordinator.dispose);

      final launch = await coordinator.prepare(
        PresenterSessionRequest(
          sessionId: 'cached-online',
          reportType: 'invoice',
          reportName: 'Invoice',
          mode: PresenterSessionMode.online,
          seedData: const <String, dynamic>{'value': 1},
          template: _template('invoice-template'),
        ),
      );
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(launch.presenterUrl));
      final page = await request.close();
      final html = await utf8.decoder.bind(page).join();
      client.close(force: true);

      expect(Uri.parse(launch.presenterUrl).host, '127.0.0.1');
      expect(html, contains('base href'));
      expect(upstreamRequests, 0);
      expect(downloads, 0);
    },
  );

  test('enforced failed update prevents online session launch', () async {
    final api = await _startSessionUpdateServer(
      presenterVersion: '2.0.0',
      bundleVersion: 'broken-newer',
      devVersion: 20,
      enforceUpdate: true,
      bundleBytes: const <int>[1, 2, 3],
    );
    addTearDown(() => api.close(force: true));
    final root = await Directory.systemTemp.createTemp(
      'bridge_session_enforced_',
    );
    addTearDown(() => root.delete(recursive: true));
    final coordinator = _coordinator(
      root: root,
      apiBaseUrl: Uri.parse('http://127.0.0.1:${api.port}/'),
    );
    addTearDown(coordinator.dispose);

    await expectLater(
      coordinator.prepare(_onlineRequest('enforced-failure')),
      throwsA(isA<BridgeRuntimeException>()),
    );
    expect(
      await Directory('${root.path}/runtime/enforced-failure').exists(),
      isFalse,
    );
    expect(coordinator.activeSessionId, isNull);
  });

  test(
    'unenforced failed update launches previous compatible verified cache',
    () async {
      final api = await _startSessionUpdateServer(
        presenterVersion: '2.0.0',
        bundleVersion: 'broken-newer',
        devVersion: 20,
        bundleBytes: const <int>[1, 2, 3],
      );
      addTearDown(() => api.close(force: true));
      final root = await Directory.systemTemp.createTemp(
        'bridge_session_fallback_',
      );
      addTearDown(() => root.delete(recursive: true));
      final presenterRoot = Directory('${root.path}/presenter');
      await _writeReadyPresenterSite(presenterRoot);
      await _writeCachedManifest(
        root,
        presenterVersion: '1.0.0',
        devVersion: 10,
        manifestUrl:
            'http://127.0.0.1:${api.port}/api/presenter/bundles/manifest',
      );
      final coordinator = _coordinator(
        root: root,
        apiBaseUrl: Uri.parse('http://127.0.0.1:${api.port}/'),
      );
      addTearDown(coordinator.dispose);

      final launch = await coordinator.prepare(
        _onlineRequest('fallback-session'),
      );

      expect(launch.presenterVersion, '1.0.0');
      expect(launch.presenterManifest?.bundleVersion, 'offline-10');
      expect(Uri.parse(launch.presenterUrl).host, '127.0.0.1');
      expect(await File('${presenterRoot.path}/index.html').exists(), isTrue);
    },
  );

  test('offline session never requests manifest or bundle endpoints', () async {
    var endpointCalls = 0;
    final api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api.listen((request) async {
      endpointCalls++;
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    });
    addTearDown(() => api.close(force: true));
    final root = await Directory.systemTemp.createTemp(
      'bridge_session_offline_network_',
    );
    addTearDown(() => root.delete(recursive: true));
    await _writeReadyPresenterSite(Directory('${root.path}/presenter'));
    await _writeCachedManifest(
      root,
      presenterVersion: '2.0.0',
      devVersion: 20,
      manifestUrl:
          'http://127.0.0.1:${api.port}/api/presenter/bundles/manifest',
    );
    final coordinator = _coordinator(
      root: root,
      apiBaseUrl: Uri.parse('http://127.0.0.1:${api.port}/'),
    );
    addTearDown(coordinator.dispose);

    await coordinator.prepare(
      PresenterSessionRequest(
        sessionId: 'offline-no-network',
        reportType: 'invoice',
        reportName: 'Invoice',
        mode: PresenterSessionMode.offline,
        seedData: const <String, dynamic>{'value': 1},
        template: _template('invoice-template'),
      ),
    );

    expect(endpointCalls, 0);
  });

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

      final firstSessionJson =
          jsonDecode(
                await File(
                  '${root.path}/runtime/online-first/session.json',
                ).readAsString(),
              )
              as Map;
      expect(firstSessionJson['apiBaseUrl'], 'http://127.0.0.1:${api.port}/');

      final firstUri = Uri.parse(first.presenterUrl);
      expect(firstUri.scheme, 'http');
      expect(firstUri.host, '127.0.0.1');
      expect(firstUri.path, '/UltimateReport/apps/presenter/index.html');
      expect(firstUri.queryParameters['existing'], isNull);
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
    'coordinator writes per-session style overrides in online and offline modes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bridge_session_style_overrides_',
      );
      addTearDown(() => root.delete(recursive: true));
      final sourceDocument = _styleOverrideDocument();
      final sourceBefore = jsonEncode(sourceDocument);
      final cache = TemplateCacheService(
        cacheRoot: Directory('${root.path}/template-cache'),
      );
      await cache.putTemplate(
        _template(
          'style-template',
          document: sourceDocument,
          systemCode: 'motakamel_transactions',
        ),
      );
      final cachedTemplate = await cache.getTemplateByCode('style-template');
      expect(cachedTemplate, isNotNull);
      final selectedTemplate = cachedTemplate!;
      final cachedBefore = jsonEncode(selectedTemplate.document);
      expect(cachedBefore, sourceBefore);

      final api = await _startManifestServer();
      addTearDown(() => api.close(force: true));
      final seedData = <String, dynamic>{
        'ReportId': 'style-report',
        'rows': <dynamic>[
          <String, dynamic>{'id': 1, 'amount': 42.5},
        ],
      };
      final seedBefore = jsonEncode(seedData);
      final overrides = ReportTemplateStyleOverrides(
        color: <String, Object?>{'primary': '#0E5A9C', 'future_color_leaf': 12},
        font: <String, Object?>{
          'family': 'UnknownFont',
          'size_md': 9.5,
          'size_xs': -3,
        },
      );
      final effectiveDocuments = <String>[];

      for (final mode in <PresenterSessionMode>[
        PresenterSessionMode.online,
        PresenterSessionMode.offline,
      ]) {
        final modeRoot = Directory('${root.path}/${mode.name}')
          ..createSync(recursive: true);
        if (mode == PresenterSessionMode.offline) {
          await _writeReadyPresenterSite(
            Directory('${modeRoot.path}/presenter'),
          );
          await _writeCachedManifest(
            modeRoot,
            presenterVersion: '2.0.0',
            devVersion: 20,
          );
        }
        final coordinator = _coordinator(
          root: modeRoot,
          apiBaseUrl: mode == PresenterSessionMode.online
              ? Uri.parse('http://127.0.0.1:${api.port}/')
              : Uri.parse('https://reports.example/'),
        );
        addTearDown(coordinator.dispose);
        final sessionId = 'style-${mode.name}';
        final sessionRequest = PresenterSessionRequest(
          sessionId: sessionId,
          reportType: 'invoice',
          reportName: 'Style report',
          mode: mode,
          seedData: seedData,
          template: selectedTemplate,
          templateStyleOverrides: overrides,
        );
        expect(sessionRequest.templateStyleOverrides, same(overrides));
        expect(sessionRequest.template, same(selectedTemplate));

        await coordinator.prepare(sessionRequest);

        final runtimeTemplateFile = File(
          '${modeRoot.path}/runtime/$sessionId/template.json',
        );
        final runtimeDocument =
            jsonDecode(await runtimeTemplateFile.readAsString())
                as Map<String, dynamic>;
        final styleTokens = runtimeDocument['styleTokens'] as Map;
        expect(styleTokens, <String, dynamic>{
          'color': <String, dynamic>{
            'primary': '#0E5A9C',
            'table_header_bg': '#223344',
            'text_primary': '#334455',
            'future_color_leaf': 12,
          },
          'font': <String, dynamic>{
            'family': 'UnknownFont',
            'size_md': 9.5,
            'size_xs': -3,
            'weight_bold': '700',
          },
          'spacing': <String, dynamic>{'md': 8},
          'border': <String, dynamic>{'width': 1},
          'radius': <String, dynamic>{'md': 4},
          'system': <String, dynamic>{'brand': 'canonical'},
        });
        expect(runtimeDocument['meta'], sourceDocument['meta']);
        expect(runtimeDocument['page'], sourceDocument['page']);
        expect(runtimeDocument['elements'], sourceDocument['elements']);
        effectiveDocuments.add(jsonEncode(runtimeDocument));

        final runtimeSeedFile = File(
          '${modeRoot.path}/runtime/$sessionId/seed_report_data.json',
        );
        expect(await runtimeSeedFile.readAsString(), seedBefore);
        final runtimeSession =
            jsonDecode(
                  await File(
                    '${modeRoot.path}/runtime/$sessionId/session.json',
                  ).readAsString(),
                )
                as Map;
        expect(runtimeSession['selectedTemplate'], <String, dynamic>{
          'type': 'invoice',
          'code': 'style-template',
          'systemCode': 'motakamel_transactions',
        });

        expect(jsonEncode(sourceDocument), sourceBefore);
        expect(jsonEncode(selectedTemplate.document), cachedBefore);
        expect(
          jsonEncode(
            (await cache.getTemplateByCode('style-template'))!.document,
          ),
          cachedBefore,
        );

        final noOverrideSessionId = 'style-no-override-${mode.name}';
        await coordinator.prepare(
          PresenterSessionRequest(
            sessionId: noOverrideSessionId,
            reportType: 'invoice',
            reportName: 'Style report',
            mode: mode,
            seedData: seedData,
            template: selectedTemplate,
          ),
        );
        final noOverrideTemplate = await File(
          '${modeRoot.path}/runtime/$noOverrideSessionId/template.json',
        ).readAsString();
        expect(noOverrideTemplate, cachedBefore);
        final noOverrideSeedFile = File(
          '${modeRoot.path}/runtime/$noOverrideSessionId/seed_report_data.json',
        );
        expect(await noOverrideSeedFile.readAsString(), seedBefore);
      }

      expect(effectiveDocuments[0], effectiveDocuments[1]);
    },
  );

  test(
    'coordinator.stop terminal-stops the shared localhost Presenter server',
    () async {
      final api = await _startManifestServer();
      addTearDown(() => api.close(force: true));
      final root = await Directory.systemTemp.createTemp(
        'bridge_session_stop_terminal_',
      );
      addTearDown(() => root.delete(recursive: true));
      final coordinator = _coordinator(
        root: root,
        apiBaseUrl: Uri.parse('http://127.0.0.1:${api.port}/'),
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
      final sessionJson =
          jsonDecode(
                await File(
                  '${root.path}/runtime/offline-one/session.json',
                ).readAsString(),
              )
              as Map;
      expect(sessionJson.containsKey('apiBaseUrl'), isFalse);
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
      await _writeReadyPresenterSite(Directory('${root.path}/presenter'));

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
              code: 'voucher-template',
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
            code: 'wrong-type',
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
      final root = await Directory.systemTemp.createTemp(
        'bridge_session_staged_share_commit_',
      );
      addTearDown(() => root.delete(recursive: true));
      final coordinator = _coordinator(
        root: root,
        apiBaseUrl: Uri.parse('http://127.0.0.1:${api.port}/'),
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
      final root = await Directory.systemTemp.createTemp(
        'bridge_session_staged_share_discard_',
      );
      addTearDown(() => root.delete(recursive: true));
      final coordinator = _coordinator(
        root: root,
        apiBaseUrl: Uri.parse('http://127.0.0.1:${api.port}/'),
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

      final coordinator = _coordinator(root: root, apiBaseUrl: apiBaseUrl);
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
        reason: 'staged sessions retain distinct localhost server handles',
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
}) {
  return PresenterSessionCoordinator(
    presenterCache: PresenterCacheService(
      presenterRoot: Directory('${root.path}/presenter'),
    ),
    runtimeStorage: RuntimeSessionStorage(
      runtimeRoot: Directory('${root.path}/runtime'),
    ),
    apiBaseUrl: apiBaseUrl,
    headers: const <String, String>{
      'X-Tenant-Id': 'tenant_demo',
      'Not-Approved': 'must-not-leak',
    },
  );
}

PresenterSessionRequest _onlineRequest(String sessionId) =>
    PresenterSessionRequest(
      sessionId: sessionId,
      reportType: 'invoice',
      reportName: 'Invoice',
      mode: PresenterSessionMode.online,
      seedData: const <String, dynamic>{'value': 1},
      template: _template('invoice-template'),
    );

CachedTemplate _template(
  String id, {
  Map<String, dynamic>? document,
  String? systemCode,
}) => CachedTemplate(
  code: id,
  type: 'invoice',
  systemCode: systemCode,
  document:
      document ??
      const <String, dynamic>{
        'meta': <String, dynamic>{'name': 'Invoice'},
        'elements': <dynamic>[],
      },
);

Map<String, dynamic> _styleOverrideDocument() => <String, dynamic>{
  'schemaVersion': '1.0.0',
  'meta': <String, dynamic>{'name': 'Style report', 'family': 'invoice'},
  'page': <String, dynamic>{
    'layout': 'Pages',
    'size': 'A4',
    'language': 'ar',
    'direction': 'rtl',
  },
  'styleTokens': <String, dynamic>{
    'color': <String, dynamic>{
      'primary': '#112233',
      'table_header_bg': '#223344',
      'text_primary': '#334455',
    },
    'font': <String, dynamic>{
      'family': 'Cairo',
      'size_md': 11,
      'size_xs': 8,
      'weight_bold': '700',
    },
    'spacing': <String, dynamic>{'md': 8},
    'border': <String, dynamic>{'width': 1},
    'radius': <String, dynamic>{'md': 4},
    'system': <String, dynamic>{'brand': 'canonical'},
  },
  'elements': <dynamic>[
    <String, dynamic>{
      'id': 'literal-text',
      'type': 'text',
      'style': <String, dynamic>{
        'text': <String, dynamic>{'color': '#ABCDEF'},
      },
    },
  ],
};

Future<void> _writeReadyPresenterSite(Directory presenterRoot) async {
  await presenterRoot.create(recursive: true);
  for (final entry in _validPureDartBundleEntries().entries) {
    final path = entry.key;
    final file = File('${presenterRoot.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(entry.value);
  }
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

Future<void> _writeCachedManifest(
  Directory root, {
  required String presenterVersion,
  required int devVersion,
  String? bundleVersion,
  String manifestUrl = 'https://reports.example/api/presenter/bundles/manifest',
}) async {
  await File('${root.path}/presenter_manifest.json').writeAsString(
    jsonEncode(<String, dynamic>{
      'manifestUrl': manifestUrl,
      'presenterVersion': presenterVersion,
      'bundleVersion': bundleVersion ?? 'offline-$devVersion',
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
            'downloadUrl': '/api/presenter/bundles/online-12',
          },
        }),
      );
    } else if (request.uri.path == '/api/presenter/bundles/online-12') {
      request.response.headers.contentType = ContentType.binary;
      request.response.add(_validPresenterZipBytes());
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  });
  return server;
}

List<int> _validPresenterZipBytes() {
  final archive = Archive();
  for (final entry in _validPureDartBundleEntries().entries) {
    archive.addFile(ArchiveFile.string(entry.key, entry.value));
  }
  return ZipEncoder().encode(archive);
}

Future<HttpServer> _startSessionUpdateServer({
  required String presenterVersion,
  required String bundleVersion,
  required int devVersion,
  bool enforceUpdate = false,
  List<int> bundleBytes = const <int>[1, 2, 3],
  void Function()? onDownload,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.uri.path == '/api/presenter/bundles/manifest') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object>{
          'success': true,
          'data': <String, Object>{
            'available': true,
            'presenterVersion': presenterVersion,
            'bundleVersion': bundleVersion,
            'devVersion': devVersion,
            'downloadUrl': '/api/presenter/bundles/download',
            'enforceUpdate': enforceUpdate,
          },
        }),
      );
    } else if (request.uri.path == '/api/presenter/bundles/download') {
      onDownload?.call();
      request.response.headers.contentType = ContentType.binary;
      request.response.add(bundleBytes);
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
