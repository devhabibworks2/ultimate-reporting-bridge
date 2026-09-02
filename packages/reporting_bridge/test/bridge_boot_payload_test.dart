import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('BridgeBootPayload round-trips nested seedData', () {
    final payload = BridgeBootPayload.fromMap(<dynamic, dynamic>{
      'contractVersion': 1,
      'seedData': <dynamic, dynamic>{
        'ReportHeader': <dynamic, dynamic>{'k': 1},
      },
      'bearerToken': 'tok',
      'templateHints': <dynamic, dynamic>{'templateId': 42},
    });
    expect(payload.contractVersion, 1);
    expect(payload.seedData!['ReportHeader'], isA<Map<String, dynamic>>());
    expect(payload.bearerToken, 'tok');
    expect(payload.templateIdHint, 42);
    expect(payload.toMap()['seedData'], isNotNull);
  });

  test('BridgeBootPayload parses host config and custom headers', () {
    final payload = BridgeBootPayload.fromMap(<dynamic, dynamic>{
      'contractVersion': 1,
      'type': 'invoice',
      'reportName': 'Sales Invoice',
      'locale': 'ar',
      'direction': 'rtl',
      'presenterUrl': 'https://example.test/presenter',
      'branding': <dynamic, dynamic>{'primaryColor': '#2563EB'},
      'apiHeaders': <dynamic, dynamic>{
        'Authorization': 'Bearer secret',
        'X-Tenant-Id': 'tenant_001',
      },
      'selectedTemplate': <dynamic, dynamic>{'id': '34', 'type': 'invoice'},
    });

    expect(payload.reportType, 'invoice');
    expect(payload.reportName, 'Sales Invoice');
    expect(payload.direction, 'rtl');
    expect(payload.presenterUrl, 'https://example.test/presenter');
    expect(payload.branding?.primaryColor, '#2563EB');
    expect(payload.apiHeaders?.values['Authorization'], 'Bearer secret');
    expect(payload.apiHeaders?.toRedactedMap(), <String, dynamic>{
      'present': true,
      'redactedKeys': <String>['Authorization', 'X-Tenant-Id'],
    });
    expect(payload.selectedTemplate?.id, '34');
    expect(payload.templateIdHint, 34);
  });

  test('SelectedTemplate keeps required storage shape', () {
    const selected = SelectedTemplate(
      id: '34',
      type: 'invoice',
      code: 'INV-34',
    );

    expect(selected.toStorageMap(), <String, dynamic>{
      'selectedTemplates': <String, dynamic>{
        'id': '34',
        'type': 'invoice',
        'code': 'INV-34',
      },
    });
    expect(
      SelectedTemplate.fromMap(selected.toStorageMap())?.matchesType('invoice'),
      isTrue,
    );
    expect(SelectedTemplate.fromMap(selected.toStorageMap())?.code, 'INV-34');
  });

  test('BridgeConfig status redacts custom API headers', () {
    final config = BridgeConfig.fromMap(<dynamic, dynamic>{
      'contractVersion': 1,
      'type': 'invoice',
      'apiHeaders': <dynamic, dynamic>{
        'Authorization': 'Bearer secret',
        'X-Branch-Id': 'branch_01',
      },
    });

    expect(config.apiHeaders?.toMap()['Authorization'], 'Bearer secret');
    expect(config.toRedactedStatusMap()['apiHeaders'], <String, dynamic>{
      'present': true,
      'redactedKeys': <String>['Authorization', 'X-Branch-Id'],
    });
    expect(config.toRedactedStatusMap().toString(), isNot(contains('secret')));
  });

  test('BridgeStatus reports selected template and redacted headers', () {
    const status = BridgeStatus(
      mode: 'offline',
      isPresenterCached: true,
      selectedTemplate: SelectedTemplate(id: '34', type: 'invoice'),
      apiHeaders: ApiHeaderConfig(<String, String>{
        'Authorization': 'Bearer secret',
      }),
    );

    expect(status.toMap()['selectedTemplates'], <String, dynamic>{
      'id': '34',
      'type': 'invoice',
    });
    expect(status.toMap()['apiHeaders'], <String, dynamic>{
      'present': true,
      'redactedKeys': <String>['Authorization'],
    });
    expect(status.toMap().toString(), isNot(contains('secret')));
  });

  test('BridgeMethods includes Phase 2 host to bridge methods', () {
    expect(BridgeMethods.setApiHeaders, 'setApiHeaders');
    expect(BridgeMethods.initializeBridge, 'initializeBridge');
    expect(BridgeMethods.prepareRuntimeSession, 'prepareRuntimeSession');
    expect(BridgeMethods.disposeBridge, 'disposeBridge');
  });
}
