import 'dart:convert';
import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('uses one complete POST request and zero detail requests', () async {
    final root = await Directory.systemTemp.createTemp('bridge-query-post-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      if (await root.exists()) await root.delete(recursive: true);
    });

    var queryCalls = 0;
    var detailCalls = 0;
    String? method;
    String? tenant;
    String? branch;
    String? user;
    Map<String, dynamic>? body;

    server.listen((request) async {
      if (request.uri.path == '/api/presenter/templates/query') {
        queryCalls += 1;
        method = request.method;
        tenant = request.headers.value('X-Tenant-Id');
        branch = request.headers.value('X-Branch-Id');
        user = request.headers.value('X-User-Context');
        body = Map<String, dynamic>.from(
          jsonDecode(await utf8.decoder.bind(request).join()) as Map,
        );
        await _writeJson(
          request,
          _queryEnvelope(<Map<String, dynamic>>[
            _queryTemplate('invoice-a4', 7, 'sales_invoice'),
            _queryTemplate('voucher-80', 7, 'payment_voucher'),
          ]),
        );
        return;
      }
      if (request.uri.path.contains('/templates/')) detailCalls += 1;
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final gateway = PresenterServerGateway(
      apiBaseUrl: _api(server),
      bridgeRoot: root,
      headers: const <String, String>{
        'X-Tenant-Id': 'tenant-a',
        'X-Branch-Id': 'branch-a',
        'X-User-Context': 'user-a',
      },
    );
    final query = TemplateQueryRequest(
      systemCode: 'motakamel_transactions',
      identity: BridgeIdentityContext(
        branchId: 'branch-a',
        userId: 'user-a',
        systemUnit: 'sales',
      ),
      filter: TemplateSyncFilter(
        reportTypes: const <String>['sales_invoice', 'payment_voucher'],
        sizes: const <String>['A4', '80mm'],
      ),
      extra: const <String, Object?>{'transactionType': 'sales'},
    );

    final summary = await gateway.syncTemplates(query: query);
    final cached = await gateway.listTemplates(query: query);

    expect(queryCalls, 1);
    expect(detailCalls, 0);
    expect(method, 'POST');
    expect(tenant, 'tenant-a');
    expect(branch, 'branch-a');
    expect(user, 'user-a');
    expect(body, query.toJson());
    expect(summary.syncedCount, 2);
    expect(summary.fromCache, isFalse);
    expect(summary.catalogRevision, 'revision-1');
    expect(summary.systemId, 7);
    expect(summary.systemName, 'Motakamel Transactions');
    expect(summary.systemDescription, 'Published report catalog');
    expect(summary.appliedFilter?['sizes'], <String>['all']);
    expect(cached.map((template) => template.templateCode), <String>[
      'invoice-a4-code',
      'voucher-80-code',
    ]);
    expect(cached.first.type, 'sales_invoice');
    expect(cached.first.systemCode, 'motakamel_transactions');
    expect(cached.first.selectedTemplate.systemCode, 'motakamel_transactions');
    expect(cached.first.publishedVersionNo, 7);
    expect(cached.first.description, 'Description for invoice-a4');
    expect(cached.first.metadata['layout'], 'Pages');
    expect(cached.first.compatibility['minPresenterVersion'], '1.0.0');
    expect(cached.first.document['schemaVersion'], '1.0.0');
  });

  test('catalog sync ignores legacy id-only selection', () async {
    final root = await Directory.systemTemp.createTemp(
      'bridge-query-selection-',
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      if (await root.exists()) await root.delete(recursive: true);
    });
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      await _writeJson(
        request,
        _queryEnvelope(<Map<String, dynamic>>[
          _queryTemplate('10', 7, 'sales_invoice'),
        ]),
      );
    });

    final query = TemplateQueryRequest(systemCode: 'motakamel_transactions');
    final cacheRoot = bridgeTemplateCacheDirectoryForScope(
      bridgeRoot: root,
      scope: BridgeTemplateCacheScope(
        apiBaseUrl: _api(server),
        systemCode: query.systemCode,
        identity: query.identity,
        filter: query.filter,
        extra: query.extra,
      ),
    );
    await cacheRoot.create(recursive: true);
    await File('${cacheRoot.path}/.selection.json').writeAsString(
      jsonEncode(<String, dynamic>{
        'selectedTemplates': <String, dynamic>{
          'id': '10',
          'type': 'sales_invoice',
        },
      }),
    );
    final gateway = PresenterServerGateway(
      apiBaseUrl: _api(server),
      bridgeRoot: root,
    );

    await gateway.syncTemplates(query: query);

    expect(await File('${cacheRoot.path}/.selection.json').exists(), isFalse);
  });

  test(
    'maps backend errors and preserves the previous valid catalog',
    () async {
      final root = await Directory.systemTemp.createTemp('bridge-query-error-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
        if (await root.exists()) await root.delete(recursive: true);
      });

      var fail = false;
      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        if (fail) {
          request.response.statusCode = HttpStatus.notFound;
          await _writeJson(request, <String, dynamic>{
            'success': false,
            'error': <String, dynamic>{
              'code': 'SYSTEM_NOT_FOUND',
              'message': 'Unknown system.',
            },
          });
          return;
        }
        await _writeJson(
          request,
          _queryEnvelope(<Map<String, dynamic>>[
            _queryTemplate('existing', 7, 'sales_invoice'),
          ]),
        );
      });

      final gateway = PresenterServerGateway(
        apiBaseUrl: _api(server),
        bridgeRoot: root,
        headers: const <String, String>{'X-Tenant-Id': 'tenant-a'},
      );
      final query = TemplateQueryRequest(
        systemCode: 'motakamel_transactions',
        identity: BridgeIdentityContext(userId: 'user-a'),
      );
      await gateway.syncTemplates(query: query);
      fail = true;

      await expectLater(
        gateway.syncTemplates(query: query),
        throwsA(
          isA<BridgeRuntimeException>()
              .having(
                (error) => error.code,
                'code',
                BridgeTemplateSyncErrorCodes.systemNotFound,
              )
              .having((error) => error.message, 'message', 'Unknown system.'),
        ),
      );
      expect(
        (await gateway.listTemplates(query: query)).single.templateCode,
        'existing-code',
      );
    },
  );

  test(
    'invalid complete response cannot partially replace the catalog',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bridge-query-atomic-',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
        if (await root.exists()) await root.delete(recursive: true);
      });

      var invalid = false;
      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        if (!invalid) {
          await _writeJson(
            request,
            _queryEnvelope(<Map<String, dynamic>>[
              _queryTemplate('existing', 7, 'sales_invoice'),
            ]),
          );
          return;
        }
        final malformed = _queryEnvelope(<Map<String, dynamic>>[
          _queryTemplate('replacement', 7, 'sales_invoice'),
        ]);
        (malformed['data'] as Map<String, dynamic>)['count'] = 2;
        await _writeJson(request, malformed);
      });

      final gateway = PresenterServerGateway(
        apiBaseUrl: _api(server),
        bridgeRoot: root,
      );
      final query = TemplateQueryRequest(systemCode: 'motakamel_transactions');
      await gateway.syncTemplates(query: query);
      invalid = true;

      await expectLater(
        gateway.syncTemplates(query: query),
        throwsA(
          isA<BridgeRuntimeException>().having(
            (error) => error.code,
            'code',
            BridgeTemplateSyncErrorCodes.templateCatalogInvalid,
          ),
        ),
      );
      expect(
        (await gateway.listTemplates(query: query)).single.templateCode,
        'existing-code',
      );
    },
  );

  test('tenant, branch, user, and system-unit catalogs are isolated', () async {
    final root = await Directory.systemTemp.createTemp('bridge-query-scope-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      if (await root.exists()) await root.delete(recursive: true);
    });

    server.listen((request) async {
      final tenant = request.headers.value('X-Tenant-Id') ?? 'none';
      final decoded = Map<String, dynamic>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      final id = <Object?>[
        tenant,
        decoded['branchId'] ?? 'none',
        decoded['userId'] ?? 'none',
        decoded['systemUnit'] ?? 'none',
      ].join('|');
      await _writeJson(
        request,
        _queryEnvelope(<Map<String, dynamic>>[
          _queryTemplate(id, 7, 'sales_invoice'),
        ]),
      );
    });

    final gateway = PresenterServerGateway(
      apiBaseUrl: _api(server),
      bridgeRoot: root,
    );
    final queryA = TemplateQueryRequest(
      systemCode: 'motakamel_transactions',
      identity: BridgeIdentityContext(
        branchId: 'branch-a',
        userId: 'user-a',
        systemUnit: 'sales',
      ),
    );
    final queryB = TemplateQueryRequest(
      systemCode: 'motakamel_transactions',
      identity: BridgeIdentityContext(
        branchId: 'branch-b',
        userId: 'user-b',
        systemUnit: 'inventory',
      ),
    );
    const headersA = <String, String>{'X-Tenant-Id': 'tenant-a'};
    const headersB = <String, String>{'X-Tenant-Id': 'tenant-b'};

    await gateway.syncTemplates(query: queryA, headers: headersA);
    await gateway.syncTemplates(query: queryA, headers: headersB);
    await gateway.syncTemplates(query: queryB, headers: headersA);

    expect(
      (await gateway.listTemplates(
        query: queryA,
        headers: headersA,
      )).single.templateCode,
      'tenant-a|branch-a|user-a|sales-code',
    );
    expect(
      (await gateway.listTemplates(
        query: queryA,
        headers: headersB,
      )).single.templateCode,
      'tenant-b|branch-a|user-a|sales-code',
    );
    expect(
      (await gateway.listTemplates(
        query: queryB,
        headers: headersA,
      )).single.templateCode,
      'tenant-a|branch-b|user-b|inventory-code',
    );
  });

  test(
    'returning user works offline and first-time user gets typed miss',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bridge-query-offline-',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var closed = false;
      addTearDown(() async {
        if (!closed) await server.close(force: true);
        if (await root.exists()) await root.delete(recursive: true);
      });

      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        await _writeJson(
          request,
          _queryEnvelope(<Map<String, dynamic>>[
            _queryTemplate('user-a-template', 7, 'sales_invoice'),
          ]),
        );
      });

      final gateway = PresenterServerGateway(
        apiBaseUrl: _api(server),
        bridgeRoot: root,
        timeout: const Duration(milliseconds: 300),
        headers: const <String, String>{'X-Tenant-Id': 'tenant-a'},
      );
      final returning = TemplateQueryRequest(
        systemCode: 'motakamel_transactions',
        identity: BridgeIdentityContext(userId: 'user-a'),
      );
      final firstTime = TemplateQueryRequest(
        systemCode: 'motakamel_transactions',
        identity: BridgeIdentityContext(userId: 'user-b'),
      );

      await gateway.syncTemplates(query: returning);
      await server.close(force: true);
      closed = true;

      final offline = await gateway.syncTemplates(query: returning);
      expect(offline.fromCache, isTrue);
      expect(offline.syncedCount, 1);
      expect(
        (await gateway.listTemplates(query: returning)).single.templateCode,
        'user-a-template-code',
      );

      await expectLater(
        gateway.syncTemplates(query: firstTime),
        throwsA(
          isA<BridgeRuntimeException>().having(
            (error) => error.code,
            'code',
            BridgeTemplateSyncErrorCodes.offlineCacheUnavailable,
          ),
        ),
      );
      await expectLater(
        gateway.listTemplates(query: firstTime),
        throwsA(
          isA<BridgeRuntimeException>().having(
            (error) => error.code,
            'code',
            BridgeTemplateSyncErrorCodes.offlineCacheUnavailable,
          ),
        ),
      );
    },
  );

  test('rejects conflicting body and approved identity headers', () async {
    final root = await Directory.systemTemp.createTemp(
      'bridge-query-conflict-',
    );
    addTearDown(() => root.delete(recursive: true));
    final gateway = PresenterServerGateway(
      apiBaseUrl: Uri.parse('https://reports.example/'),
      bridgeRoot: root,
    );
    final query = TemplateQueryRequest(
      systemCode: 'motakamel_transactions',
      identity: BridgeIdentityContext(branchId: 'branch-body'),
    );

    await expectLater(
      gateway.syncTemplates(
        query: query,
        headers: const <String, String>{'X-Branch-Id': 'branch-header'},
      ),
      throwsA(
        isA<BridgeRuntimeException>().having(
          (error) => error.code,
          'code',
          BridgeTemplateSyncErrorCodes.identityContextConflict,
        ),
      ),
    );
  });

  test('parses and caches valid defaultTemplates', () async {
    final root = await Directory.systemTemp.createTemp('bridge-query-defaults-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      if (await root.exists()) await root.delete(recursive: true);
    });

    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      await _writeJson(
        request,
        _queryEnvelope(
          <Map<String, dynamic>>[
            _queryTemplate('invoice-a4', 7, 'sales_invoice'),
            _queryTemplate('voucher-80', 7, 'payment_voucher'),
          ],
          defaultTemplates: <Map<String, dynamic>>[
            <String, dynamic>{
              'reportType': 'payment_voucher',
              'templateCode': 'voucher-80-code',
              'selectionReason': 'SYSTEM_DEFAULT',
            },
            <String, dynamic>{
              'reportType': 'sales_invoice',
              'templateCode': 'invoice-a4-code',
              'selectionReason': 'BRANCH_DEFAULT',
            },
          ],
        ),
      );
    });

    final gateway = PresenterServerGateway(
      apiBaseUrl: _api(server),
      bridgeRoot: root,
    );
    final query = TemplateQueryRequest(systemCode: 'motakamel_transactions');
    final summary = await gateway.syncTemplates(query: query);
    expect(summary.defaultTemplates.length, 2);
    expect(summary.defaultTemplates[0].reportType, 'payment_voucher');
    expect(summary.defaultTemplates[0].templateCode, 'voucher-80-code');
    expect(summary.defaultTemplates[0].selectionReason, 'SYSTEM_DEFAULT');
    expect(summary.defaultTemplates[1].reportType, 'sales_invoice');
    expect(summary.defaultTemplates[1].templateCode, 'invoice-a4-code');
    expect(summary.defaultTemplates[1].selectionReason, 'BRANCH_DEFAULT');

    final metadata = await TemplateCacheService(
      cacheRoot: bridgeTemplateCacheDirectoryForScope(
        bridgeRoot: root,
        scope: BridgeTemplateCacheScope(
          apiBaseUrl: _api(server),
          systemCode: query.systemCode,
          identity: query.identity,
          filter: query.filter,
          extra: query.extra,
        ),
      ),
    ).readCatalogMetadata();
    expect(metadata?.defaultTemplates.length, 2);
    expect(metadata?.defaultTemplates[0].templateCode, 'voucher-80-code');
    expect(metadata?.defaultTemplates[1].templateCode, 'invoice-a4-code');
  });

  test('missing defaultTemplates remains compatible with old backends', () async {
    final root = await Directory.systemTemp.createTemp('bridge-query-old-defaults-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      if (await root.exists()) await root.delete(recursive: true);
    });

    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      final envelope = _queryEnvelope(<Map<String, dynamic>>[
        _queryTemplate('invoice-a4', 7, 'sales_invoice'),
      ]);
      (envelope['data'] as Map<String, dynamic>).remove('defaultTemplates');
      await _writeJson(request, envelope);
    });

    final gateway = PresenterServerGateway(
      apiBaseUrl: _api(server),
      bridgeRoot: root,
    );
    final summary = await gateway.syncTemplates(
      query: TemplateQueryRequest(systemCode: 'motakamel_transactions'),
    );
    expect(summary.defaultTemplates, isEmpty);
  });

  test('duplicate default reportType is rejected', () async {
    await _expectInvalidDefaults(
      defaultTemplates: <Map<String, dynamic>>[
        <String, dynamic>{
          'reportType': 'sales_invoice',
          'templateCode': 'invoice-a4-code',
          'selectionReason': 'SYSTEM_DEFAULT',
        },
        <String, dynamic>{
          'reportType': 'sales_invoice',
          'templateCode': 'invoice-a4-code',
          'selectionReason': 'BRANCH_DEFAULT',
        },
      ],
    );
  });

  test('defaultTemplates missing templateCode is rejected', () async {
    await _expectInvalidDefaults(
      defaultTemplates: <Map<String, dynamic>>[
        <String, dynamic>{
          'reportType': 'sales_invoice',
          'templateCode': 'missing-code',
          'selectionReason': 'SYSTEM_DEFAULT',
        },
      ],
    );
  });

  test('defaultTemplates reportType mismatch is rejected', () async {
    await _expectInvalidDefaults(
      defaultTemplates: <Map<String, dynamic>>[
        <String, dynamic>{
          'reportType': 'payment_voucher',
          'templateCode': 'invoice-a4-code',
          'selectionReason': 'SYSTEM_DEFAULT',
        },
      ],
    );
  });

  test(
    'invalid defaultTemplates snapshot preserves prior templates and defaults',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bridge-query-defaults-atomic-',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
        if (await root.exists()) await root.delete(recursive: true);
      });

      var invalid = false;
      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        if (!invalid) {
          await _writeJson(
            request,
            _queryEnvelope(
              <Map<String, dynamic>>[
                _queryTemplate('existing', 7, 'sales_invoice'),
              ],
              defaultTemplates: <Map<String, dynamic>>[
                <String, dynamic>{
                  'reportType': 'sales_invoice',
                  'templateCode': 'existing-code',
                  'selectionReason': 'SYSTEM_DEFAULT',
                },
              ],
            ),
          );
          return;
        }
        await _writeJson(
          request,
          _queryEnvelope(
            <Map<String, dynamic>>[
              _queryTemplate('replacement', 7, 'sales_invoice'),
            ],
            defaultTemplates: <Map<String, dynamic>>[
              <String, dynamic>{
                'reportType': 'sales_invoice',
                'templateCode': 'missing-code',
                'selectionReason': 'SYSTEM_DEFAULT',
              },
            ],
          ),
        );
      });

      final gateway = PresenterServerGateway(
        apiBaseUrl: _api(server),
        bridgeRoot: root,
      );
      final query = TemplateQueryRequest(systemCode: 'motakamel_transactions');
      await gateway.syncTemplates(query: query);
      invalid = true;

      await expectLater(
        gateway.syncTemplates(query: query),
        throwsA(
          isA<BridgeRuntimeException>().having(
            (error) => error.code,
            'code',
            BridgeTemplateSyncErrorCodes.templateCatalogInvalid,
          ),
        ),
      );
      expect(
        (await gateway.listTemplates(query: query)).single.templateCode,
        'existing-code',
      );
      final metadata = await TemplateCacheService(
        cacheRoot: bridgeTemplateCacheDirectoryForScope(
          bridgeRoot: root,
          scope: BridgeTemplateCacheScope(
            apiBaseUrl: _api(server),
            systemCode: query.systemCode,
            identity: query.identity,
            filter: query.filter,
            extra: query.extra,
          ),
        ),
      ).readCatalogMetadata();
      expect(metadata?.defaultTemplates.single.templateCode, 'existing-code');
    },
  );

  test('offline fallback returns cached defaultTemplates', () async {
    final root = await Directory.systemTemp.createTemp(
      'bridge-query-defaults-offline-',
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      if (await root.exists()) await root.delete(recursive: true);
    });

    var accept = true;
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      if (!accept) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
        return;
      }
      await _writeJson(
        request,
        _queryEnvelope(
          <Map<String, dynamic>>[
            _queryTemplate('invoice-a4', 7, 'sales_invoice'),
          ],
          defaultTemplates: <Map<String, dynamic>>[
            <String, dynamic>{
              'reportType': 'sales_invoice',
              'templateCode': 'invoice-a4-code',
              'selectionReason': 'SYSTEM_DEFAULT',
            },
          ],
        ),
      );
    });

    final gateway = PresenterServerGateway(
      apiBaseUrl: _api(server),
      bridgeRoot: root,
    );
    final query = TemplateQueryRequest(systemCode: 'motakamel_transactions');
    await gateway.syncTemplates(query: query);
    accept = false;
    await server.close(force: true);

    final summary = await gateway.syncTemplates(query: query);
    expect(summary.fromCache, isTrue);
    expect(summary.defaultTemplates.single.templateCode, 'invoice-a4-code');

    final defaults = await gateway.listTemplateDefaults(query: query);
    expect(defaults.single.templateCode, 'invoice-a4-code');
  });

  test('listTemplateDefaults throws when cache scope is missing', () async {
    final root = await Directory.systemTemp.createTemp(
      'bridge-query-defaults-miss-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final gateway = PresenterServerGateway(
      apiBaseUrl: Uri.parse('https://reports.example/'),
      bridgeRoot: root,
    );
    await expectLater(
      gateway.listTemplateDefaults(
        query: TemplateQueryRequest(systemCode: 'motakamel_transactions'),
      ),
      throwsA(
        isA<BridgeRuntimeException>().having(
          (error) => error.code,
          'code',
          BridgeTemplateSyncErrorCodes.offlineCacheUnavailable,
        ),
      ),
    );
  });
}

Future<void> _expectInvalidDefaults({
  required List<Map<String, dynamic>> defaultTemplates,
}) async {
  final root = await Directory.systemTemp.createTemp('bridge-query-bad-defaults-');
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() async {
    await server.close(force: true);
    if (await root.exists()) await root.delete(recursive: true);
  });

  server.listen((request) async {
    await utf8.decoder.bind(request).join();
    await _writeJson(
      request,
      _queryEnvelope(
        <Map<String, dynamic>>[
          _queryTemplate('invoice-a4', 7, 'sales_invoice'),
        ],
        defaultTemplates: defaultTemplates,
      ),
    );
  });

  final gateway = PresenterServerGateway(
    apiBaseUrl: _api(server),
    bridgeRoot: root,
  );
  await expectLater(
    gateway.syncTemplates(
      query: TemplateQueryRequest(systemCode: 'motakamel_transactions'),
    ),
    throwsA(
      isA<BridgeRuntimeException>().having(
        (error) => error.code,
        'code',
        BridgeTemplateSyncErrorCodes.templateCatalogInvalid,
      ),
    ),
  );
}

Uri _api(HttpServer server) =>
    Uri.parse('http://${server.address.host}:${server.port}/');

Map<String, dynamic> _queryEnvelope(
  List<Map<String, dynamic>> items, {
  List<Map<String, dynamic>> defaultTemplates = const <Map<String, dynamic>>[],
}) {
  return <String, dynamic>{
    'success': true,
    'message': 'OK',
    'data': <String, dynamic>{
      'catalogRevision': 'revision-1',
      'system': <String, dynamic>{
        'id': 7,
        'code': 'motakamel_transactions',
        'name': 'Motakamel Transactions',
        'description': 'Published report catalog',
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
      'defaultTemplates': defaultTemplates,
    },
  };
}

Map<String, dynamic> _queryTemplate(
  String id,
  int systemId,
  String reportType,
) {
  return <String, dynamic>{
    'id': id,
    'systemId': systemId,
    'code': '$id-code',
    'name': 'Template $id',
    'description': 'Description for $id',
    'reportType': reportType,
    'publishedVersionNo': 7,
    'metadata': <String, dynamic>{
      'layout': 'Pages',
      'size': 'A4',
      'languages': <String>['ar'],
      'unit': 'mm',
      'orientation': 'portrait',
    },
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

Future<void> _writeJson(HttpRequest request, Map<String, dynamic> body) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}
