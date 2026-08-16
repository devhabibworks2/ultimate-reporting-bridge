import 'dart:convert';
import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test(
    'loads systems and syncs selected-system templates end to end',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bridge_server_gateway_',
      );
      addTearDown(() => root.delete(recursive: true));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var sawTenantHeader = false;
      var requestedSystemId = '';

      server.listen((request) async {
        sawTenantHeader = request.headers.value('X-Tenant-Id') == 'tenant_demo';
        if (request.uri.path == '/api/presenter/systems') {
          await _writeJson(request, <String, dynamic>{
            'success': true,
            'data': <String, dynamic>{
              'items': <Map<String, dynamic>>[
                <String, dynamic>{'id': 8, 'code': 'B', 'name': 'Beta'},
                <String, dynamic>{'id': 7, 'code': 'A', 'name': 'Alpha'},
              ],
            },
          });
          return;
        }
        if (request.uri.path == '/api/presenter/templates') {
          requestedSystemId = request.uri.queryParameters['systemId'] ?? '';
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
        if (request.uri.path == '/api/presenter/templates/invoice-7/latest') {
          await _writeJson(request, <String, dynamic>{
            'success': true,
            'data': <String, dynamic>{
              'id': 'invoice-7',
              'type': 'invoice',
              'systemId': 7,
              'document': <String, dynamic>{
                'meta': <String, dynamic>{'name': 'System 7 Invoice'},
              },
            },
          });
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final gateway = PresenterServerGateway(
        apiBaseUrl: Uri.parse('http://127.0.0.1:${server.port}/'),
        bridgeRoot: root,
        headers: const <String, String>{'X-Tenant-Id': 'tenant_demo'},
      );

      final systems = await gateway.fetchSystems();
      expect(systems.map((system) => system.name), <String>['Alpha', 'Beta']);

      final summary = await gateway.syncTemplates(systemId: 7);
      expect(summary.syncedCount, 1);
      expect(summary.errors, isEmpty);
      expect(requestedSystemId, '7');
      expect(sawTenantHeader, isTrue);

      final cached = await gateway.listTemplates(systemId: 7);
      expect(cached.single.id, 'invoice-7');
      expect(cached.single.systemId, 7);
    },
  );

  test('rejects duplicate system ids in the bridge transport', () async {
    final root = await Directory.systemTemp.createTemp('bridge_system_dupe_');
    addTearDown(() => root.delete(recursive: true));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    server.listen((request) async {
      await _writeJson(request, <String, dynamic>{
        'success': true,
        'data': <String, dynamic>{
          'items': <Map<String, dynamic>>[
            <String, dynamic>{'id': 7, 'code': 'A', 'name': 'Alpha'},
            <String, dynamic>{'id': 7, 'code': 'B', 'name': 'Beta'},
          ],
        },
      });
    });

    final gateway = PresenterServerGateway(
      apiBaseUrl: Uri.parse('http://127.0.0.1:${server.port}/'),
      bridgeRoot: root,
    );

    expect(
      gateway.fetchSystems,
      throwsA(
        isA<BridgeRuntimeException>().having(
          (error) => error.message,
          'message',
          contains('duplicate id 7'),
        ),
      ),
    );
  });
}

Future<void> _writeJson(HttpRequest request, Map<String, dynamic> body) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}
