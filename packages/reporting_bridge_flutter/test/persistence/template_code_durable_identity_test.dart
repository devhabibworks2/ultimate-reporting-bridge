import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('selected-template storage token is scoped by System', () {
    const first = ReportPreferenceScope(
      connectionKey: 'deployed|https://one.example',
      system: 'system_a',
      reportType: 'sales_invoice',
      userId: '42',
    );
    const second = ReportPreferenceScope(
      connectionKey: 'deployed|https://two.example',
      system: 'system_b',
      reportType: 'sales_invoice',
      userId: '42',
    );

    expect(
      first.selectedTemplateStorageToken,
      isNot(second.selectedTemplateStorageToken),
    );
  });

  test('durable selected-template record stores systemCode plus templateCode', () async {
    const scope = ReportPreferenceScope(
      connectionKey: 'deployed|https://example.test',
      system: 'system_a',
      reportType: 'sales_invoice',
      userId: '42',
    );
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesReportFlowPreferenceStore(preferences);
    final durable = ReportFlowPreferences.fromJson(<String, dynamic>{
      'templateCode': 'INV-A5-AR',
      'mode': 'online',
    });

    expect(durable, isNotNull);
    await store.save(scope, durable!);

    final selectedKeys = preferences
        .getKeys()
        .where((key) => key.startsWith('urb.reporting_bridge.selected_template.'))
        .toList(growable: false);
    expect(selectedKeys, hasLength(1));
    expect(selectedKeys.single, startsWith('urb.reporting_bridge.selected_template.v6.'));

    final raw = jsonDecode(preferences.getString(selectedKeys.single)!) as Map;
    expect(raw['systemCode'], 'system_a');
    expect(raw['templateCode'], 'INV-A5-AR');
    expect(raw.containsKey('templateId'), isFalse);
  });

  test('legacy numeric templateId is never written as a durable V6 selection', () async {
    const scope = ReportPreferenceScope(
      connectionKey: 'deployed|https://example.test',
      system: 'system_a',
      reportType: 'sales_invoice',
    );
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesReportFlowPreferenceStore(preferences);

    await store.save(
      scope,
      const ReportFlowPreferences(
        templateId: '17',
        mode: PresenterModePreference.online,
      ),
    );

    expect(
      preferences.getKeys().where(
        (key) => key.startsWith('urb.reporting_bridge.selected_template.v6.'),
      ),
      isEmpty,
    );
  });
}
