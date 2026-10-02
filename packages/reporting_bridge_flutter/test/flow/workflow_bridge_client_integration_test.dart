// T11 intentionally exercises deprecated numeric compatibility in this file.
// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:reporting_bridge_flutter/src/flow/report_flow_controller_impl.dart';

void main() {
  test(
    'Motakamel string synchronization uses one POST query and no legacy GETs',
    () async {
      final root = await Directory.systemTemp.createTemp('urb-workflow-query-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
        if (await root.exists()) await root.delete(recursive: true);
      });

      final requests = <String>[];
      Map<String, dynamic>? queryBody;
      server.listen((request) async {
        requests.add('${request.method} ${request.uri.path}');
        if (request.method == 'POST' &&
            request.uri.path == '/api/presenter/templates/query') {
          queryBody = Map<String, dynamic>.from(
            jsonDecode(await utf8.decoder.bind(request).join()) as Map,
          );
          await _writeJson(request, _queryEnvelope());
          return;
        }
        await utf8.decoder.bind(request).join();
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final delegate = ReportingBridgeClient(
        apiBaseUrl: _api(server),
        presenterEntryUrl: Uri.parse('https://presenter.test/'),
        bridgeRoot: root,
      );
      addTearDown(delegate.dispose);
      final filter = TemplateSyncFilter(
        reportTypes: const <String>['invoice'],
        sizes: const <String>['80mm'],
      );
      const extra = <String, Object?>{'transactionType': 'sales'};
      final client = createWorkflowBridgeClientForTesting(
        delegate: delegate,
        system: 'motakamel_transactions',
        templateSyncRequest: TemplateSyncRequest(
          systemCode: UrbSystem.motakamelTransactions,
          filter: filter,
          extra: extra,
        ),
      );
      addTearDown(client.dispose);

      final summary = await client.syncTemplates(
        systemCode: 'ignored_by_workflow_scope',
        filter: filter,
        extra: extra,
      );
      final templates = await client.listTemplates(
        systemCode: 'ignored_by_workflow_scope',
        filter: filter,
        extra: extra,
      );

      expect(summary.syncedCount, 1);
      expect(requests, <String>['POST /api/presenter/templates/query']);
      expect(queryBody?['systemCode'], 'motakamel_transactions');
      expect(queryBody?['filter'], filter.toJson());
      expect(queryBody?['extra'], extra);
      expect(templates.single.templateCode, 'invoice-80');
      expect(templates.single.description, 'Thermal invoice');
      expect(templates.single.metadata['layout'], 'Thermal');
      expect(templates.single.compatibility['minPresenterVersion'], '1.0.0');
    },
  );

  test(
    'TemplateSyncRequest scope wins over call-site system/filter args',
    () async {
      final root = await Directory.systemTemp.createTemp('urb-workflow-scope-');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final delegate = _RecordingBridgeClient(
        root,
        defaultTemplates: const <TemplateDefaultHint>[
          TemplateDefaultHint(
            reportType: 'sales_invoice',
            templateCode: 'invoice-a4-code',
            selectionReason: 'SYSTEM_DEFAULT',
          ),
        ],
      );
      addTearDown(delegate.dispose);
      final filter = TemplateSyncFilter(reportTypes: const <String>['invoice']);
      const extra = <String, Object?>{'source': 'compatibility'};
      final client = createWorkflowBridgeClientForTesting(
        delegate: delegate,
        system: 'motakamel_transactions',
        templateSyncRequest: TemplateSyncRequest(
          systemCode: UrbSystem.motakamelTransactions,
          filter: filter,
          extra: extra,
        ),
      );
      addTearDown(client.dispose);

      await client.syncTemplates(
        systemCode: 'must_not_be_forwarded',
        filter: TemplateSyncFilter(reportTypes: const <String>['other']),
        extra: const <String, Object?>{'ignored': true},
      );
      await client.listTemplates(
        systemCode: 'must_not_be_forwarded',
        filter: TemplateSyncFilter(reportTypes: const <String>['other']),
        extra: const <String, Object?>{'ignored': true},
      );
      final defaults = await client.listTemplateDefaults(
        systemCode: 'must_not_be_forwarded',
        filter: TemplateSyncFilter(reportTypes: const <String>['other']),
        extra: const <String, Object?>{'ignored': true},
      );

      expect(delegate.syncSystemCode, 'motakamel_transactions');
      expect(delegate.listSystemCode, 'motakamel_transactions');
      expect(delegate.defaultsSystemCode, 'motakamel_transactions');
      expect(delegate.syncFilter, same(filter));
      expect(delegate.listFilter, same(filter));
      expect(delegate.defaultsFilter, same(filter));
      expect(delegate.syncExtra, extra);
      expect(delegate.listExtra, extra);
      expect(delegate.defaultsExtra, extra);
      expect(defaults, delegate.defaultTemplates);
      expect(delegate.identityBoundBeforeDefaults, isTrue);
    },
  );

  test(
    'workflow listTemplateDefaults turns cold-cache miss into empty list',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'urb-workflow-defaults-miss-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final delegate = _RecordingBridgeClient(root, throwDefaultsOffline: true);
      addTearDown(delegate.dispose);
      final client = createWorkflowBridgeClientForTesting(
        delegate: delegate,
        system: 'motakamel_transactions',
        templateSyncRequest: TemplateSyncRequest(
          systemCode: UrbSystem.motakamelTransactions,
        ),
      );
      addTearDown(client.dispose);

      final defaults = await client.listTemplateDefaults(
        systemCode: 'motakamel_transactions',
      );
      expect(defaults, isEmpty);
    },
  );

  test(
    'string listing filters only explicit mismatches without rebuilding templates',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'urb-workflow-filter-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final matching = _cachedTemplate(
        'matching',
        systemCode: 'motakamel_transactions',
      );
      final unspecified = _cachedTemplate('unspecified');
      final mismatch = _cachedTemplate('mismatch', systemCode: 'other_system');
      final delegate = _RecordingBridgeClient(
        root,
        templates: <CachedTemplate>[matching, unspecified, mismatch],
      );
      addTearDown(delegate.dispose);
      final client = createWorkflowBridgeClientForTesting(
        delegate: delegate,
        system: 'motakamel_transactions',
        templateSyncRequest: TemplateSyncRequest(
          systemCode: UrbSystem.motakamelTransactions,
        ),
      );
      addTearDown(client.dispose);

      final templates = await client.listTemplates(
        systemCode: 'motakamel_transactions',
      );

      expect(delegate.listSystemCode, 'motakamel_transactions');
      expect(templates, <CachedTemplate>[matching, unspecified]);
      expect(identical(templates.first, matching), isTrue);
      expect(templates.first.description, 'Description matching');
      expect(templates.first.publishedVersionNo, 3);
      expect(templates.first.metadata['layout'], 'Pages');
      expect(templates.first.compatibility['minBridgeVersion'], '1.0.0');
    },
  );
}

Uri _api(HttpServer server) =>
    Uri.parse('http://${server.address.host}:${server.port}/');

Map<String, dynamic> _queryEnvelope() => <String, dynamic>{
  'success': true,
  'message': 'OK',
  'data': <String, dynamic>{
    'catalogRevision': 'revision-t11',
    'system': <String, dynamic>{
      'id': 7,
      'code': 'motakamel_transactions',
      'name': 'Motakamel Transactions',
      'description': 'Published report catalog',
    },
    'appliedFilter': <String, dynamic>{
      'reportTypes': <String>['invoice'],
      'layouts': <String>['all'],
      'sizes': <String>['80mm'],
      'languages': <String>['all'],
      'units': <String>['all'],
      'orientations': <String>['all'],
    },
    'count': 1,
    'items': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'invoice-80',
        'systemId': 7,
        'code': 'invoice-80',
        'name': 'Invoice 80mm',
        'description': 'Thermal invoice',
        'reportType': 'invoice',
        'publishedVersionNo': 3,
        'metadata': <String, dynamic>{
          'layout': 'Thermal',
          'size': '80mm',
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
          'meta': <String, dynamic>{
            'name': 'Invoice 80mm',
            'systemCode': 'motakamel_transactions',
            'code': 'invoice-80',
          },
          'page': <String, dynamic>{},
          'styleTokens': <String, dynamic>{},
          'assets': <Object?>[],
          'layers': <Object?>[],
          'elements': <Object?>[],
        },
      },
    ],
  },
};

Future<void> _writeJson(HttpRequest request, Map<String, dynamic> body) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}

CachedTemplate _cachedTemplate(String id, {String? systemCode}) =>
    CachedTemplate(
      type: 'invoice',
      systemId: 7,
      code: '$id-code',
      name: 'Template $id',
      description: 'Description $id',
      publishedVersionNo: 3,
      metadata: const <String, dynamic>{'layout': 'Pages'},
      compatibility: const <String, dynamic>{'minBridgeVersion': '1.0.0'},
      document: <String, dynamic>{
        'schemaVersion': '1.0.0',
        'meta': <String, dynamic>{
          'name': 'Template $id',
          if (systemCode != null) 'systemCode': systemCode,
        },
        'page': <String, dynamic>{},
        'styleTokens': <String, dynamic>{},
        'assets': <Object?>[],
        'layers': <Object?>[],
        'elements': <Object?>[],
      },
    );

final class _RecordingBridgeClient extends ReportingBridgeClient {
  _RecordingBridgeClient(
    Directory root, {
    this.templates = const <CachedTemplate>[],
    this.defaultTemplates = const <TemplateDefaultHint>[],
    this.throwDefaultsOffline = false,
  }) : super(
         apiBaseUrl: Uri.parse('https://example.test/backend/'),
         presenterEntryUrl: Uri.parse('https://example.test/presenter/'),
         bridgeRoot: root,
       );

  final List<CachedTemplate> templates;
  final List<TemplateDefaultHint> defaultTemplates;
  final bool throwDefaultsOffline;
  String? syncSystemCode;
  TemplateSyncFilter? syncFilter;
  Map<String, Object?>? syncExtra;
  String? listSystemCode;
  TemplateSyncFilter? listFilter;
  Map<String, Object?>? listExtra;
  String? defaultsSystemCode;
  TemplateSyncFilter? defaultsFilter;
  Map<String, Object?>? defaultsExtra;
  bool identityBoundBeforeDefaults = false;

  @override
  Future<void> updateIdentityContext(BridgeIdentityContext identity) async {
    await super.updateIdentityContext(identity);
    identityBoundBeforeDefaults = true;
  }

  @override
  Future<TemplateSyncSummary> syncTemplates({
    required String systemCode,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    syncSystemCode = systemCode;
    syncFilter = filter;
    syncExtra = extra;
    return TemplateSyncSummary(
      syncedCount: templates.length,
      listCount: templates.length,
      errors: const <String>[],
    );
  }

  @override
  Future<List<CachedTemplate>> listTemplates({
    required String systemCode,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    listSystemCode = systemCode;
    listFilter = filter;
    listExtra = extra;
    return templates;
  }

  @override
  Future<List<TemplateDefaultHint>> listTemplateDefaults({
    required String systemCode,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    defaultsSystemCode = systemCode;
    defaultsFilter = filter;
    defaultsExtra = extra;
    if (throwDefaultsOffline) {
      throw const BridgeRuntimeException(
        BridgeTemplateSyncErrorCodes.offlineCacheUnavailable,
        'No cached template catalog is available for the current scope.',
      );
    }
    return defaultTemplates;
  }
}
