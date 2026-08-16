import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:reporting_bridge_flutter/src/support/report_support_package.dart';

void main() {
  test('support package contains expected diagnostics and redacts secrets', () {
    final package = const ReportSupportPackageBuilder().build(
      seedData: <String, dynamic>{
        'CustomerName': 'Acme Trading',
        'Total': 42.5,
        'token': 'seed-secret',
        'authToken': 'seed-auth-secret',
        'nested': <String, dynamic>{
          'password': 'seed-password',
          'clientSecret': 'nested-client-secret',
          'styleTokens': 'business-value',
        },
      },
      template: const CachedTemplate(
        id: 't1',
        type: 'sales_invoice',
        name: 'Invoice A4',
        version: '3',
        metadata: <String, dynamic>{'family': 'sales_invoice'},
        document: <String, dynamic>{
          'schemaVersion': '1.0.0',
          'styleTokens': <String, dynamic>{'primary': '#123456'},
          'page': <String, dynamic>{'layout': 'Pages', 'size': 'A4'},
        },
      ),
      failure: const ReportFlowFailure(
        code: ReportFlowFailureCode.renderFailed,
        diagnostic: 'Authorization: Bearer top-secret token=abc123',
        technicalCode: 'TEXT_RENDER_FAILED',
        technicalCategory: 'render',
        technicalPath: r'elements[2]',
        details: <String, Object?>{
          'token': 'diagnostic-secret',
          'styleTokens': 'must-stay-visible',
        },
      ),
      systemCode: 'motakamel_transactions',
      reportType: 'sales_invoice',
      presenterMode: PresenterModePreference.online,
      reportName: 'Sales invoice',
      requestId: 'request-7',
      userId: 'user-1',
      branchId: 'branch-2',
      systemUnit: 'unit-3',
      locale: 'ar',
      presenterLaunch: const PresenterSessionLaunch(
        presenterUrl: 'https://presenter.test/session',
        sessionId: 'session-1',
        presenterVersion: '1.2.3',
        presenterDevVersion: 1,
      ),
      presenterManifest: const PresenterCacheManifest(
        bundleVersion: 'bundle-1',
        devVersion: 1,
        rootPath: '/Users/private/cache/presenter',
        presenterVersion: '1.2.3',
      ),
      generatedAt: DateTime.utc(2026, 8, 14, 1, 2, 3),
    );

    expect(package.filename, 'urb_report_issue_20260814T010203Z.zip');

    final archive = ZipDecoder().decodeBytes(package.bytes, verify: true);
    expect(archive.map((entry) => entry.name).toSet(), <String>{
      'error.json',
      'template.json',
      'seed_data.json',
      'system.json',
      'presenter.json',
      'manifest.json',
    });

    Map<String, dynamic> jsonFile(String name) {
      final bytes = archive.findFile(name)?.readBytes();
      expect(bytes, isNotNull, reason: '$name should be present');
      return jsonDecode(utf8.decode(bytes!)) as Map<String, dynamic>;
    }

    final seed = jsonFile('seed_data.json');
    expect(seed['CustomerName'], 'Acme Trading');
    expect(seed['Total'], 42.5);
    expect(seed['token'], '<redacted>');
    expect(seed['authToken'], '<redacted>');
    expect((seed['nested'] as Map)['password'], '<redacted>');
    expect((seed['nested'] as Map)['clientSecret'], '<redacted>');
    expect((seed['nested'] as Map)['styleTokens'], 'business-value');

    final error = jsonFile('error.json');
    expect(error['technicalCode'], 'TEXT_RENDER_FAILED');
    expect(error['message'], contains('<redacted>'));
    expect((error['details'] as Map)['token'], '<redacted>');
    expect((error['details'] as Map)['styleTokens'], 'must-stay-visible');

    final template = jsonFile('template.json');
    expect(template['id'], 't1');
    expect(
      ((template['document'] as Map)['styleTokens'] as Map)['primary'],
      '#123456',
    );

    final presenter = jsonFile('presenter.json');
    expect(presenter['presenterVersion'], '1.2.3');
    expect(presenter.containsKey('rootPath'), isFalse);

    final manifest = jsonFile('manifest.json');
    expect(manifest['containsSeedData'], isTrue);
    expect(manifest['generatedAt'], '2026-08-14T01:02:03.000Z');
  });
}
