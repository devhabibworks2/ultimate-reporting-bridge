import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:reporting_bridge_flutter/src/support/report_support_package.dart';

void main() {
  test(
    'support package emits interoperable URB diagnostics contract and redacts secrets',
    () {
      const canonicalDocument = <String, dynamic>{
        'schemaVersion': '1.0.0',
        'meta': <String, dynamic>{
          'id': 'invoice-a4',
          'code': 'INVOICE_A4',
          'name': 'Invoice A4',
          'family': 'sales_invoice',
          'status': 'draft',
          'version': 1,
          'description': '',
          'tags': <dynamic>[],
        },
        'page': <String, dynamic>{
          'layout': 'Pages',
          'unit': 'mm',
          'size': 'A4',
          'width': 210,
          'height': 297,
          'orientation': 'portrait',
          'language': 'en',
          'direction': 'ltr',
        },
        'styleTokens': <String, dynamic>{},
        'assets': <dynamic>[],
        'layers': <dynamic>[
          <String, dynamic>{
            'id': 'main',
            'name': 'Main',
            'visible': true,
            'locked': false,
            'elementIds': <dynamic>[],
          },
        ],
        'elements': <dynamic>[],
      };

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
          code: 'invoice-a4',
          name: 'Invoice A4',
          description: 'Invoice template',
          publishedVersionNo: 3,
          version: '3',
          minPresenterVersion: '1.0.0',
          minBridgeVersion: '1.0.0',
          metadata: <String, dynamic>{'family': 'sales_invoice'},
          compatibility: <String, dynamic>{'language': 'en'},
          document: canonicalDocument,
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

      expect(package.filename, 'urb_report_issue_20260814T010203Z.urb');

      final archive = ZipDecoder().decodeBytes(package.bytes, verify: true);
      expect(archive.map((entry) => entry.name).toSet(), <String>{
        'manifest.json',
        'template.json',
        'seed_data.json',
        'diagnostics/error.json',
        'diagnostics/system.json',
        'diagnostics/presenter.json',
        'diagnostics/bridge.json',
      });

      List<int> rawFile(String name) {
        final bytes = archive.findFile(name)?.readBytes();
        expect(bytes, isNotNull, reason: '$name should be present');
        return bytes!;
      }

      Map<String, dynamic> jsonFile(String name) {
        return jsonDecode(utf8.decode(rawFile(name))) as Map<String, dynamic>;
      }

      final seed = jsonFile('seed_data.json');
      expect(seed['CustomerName'], 'Acme Trading');
      expect(seed['Total'], 42.5);
      expect(seed['token'], '<redacted>');
      expect(seed['authToken'], '<redacted>');
      expect((seed['nested'] as Map)['password'], '<redacted>');
      expect((seed['nested'] as Map)['clientSecret'], '<redacted>');
      expect((seed['nested'] as Map)['styleTokens'], 'business-value');

      final error = jsonFile('diagnostics/error.json');
      expect(error['technicalCode'], 'TEXT_RENDER_FAILED');
      expect(error['message'], contains('<redacted>'));
      expect((error['details'] as Map)['token'], '<redacted>');
      expect((error['details'] as Map)['styleTokens'], 'must-stay-visible');

      final template = jsonFile('template.json');
      expect(template, canonicalDocument);
      expect(template.containsKey('document'), isFalse);
      expect(template.containsKey('id'), isFalse);

      final presenter = jsonFile('diagnostics/presenter.json');
      expect(presenter['presenterVersion'], '1.2.3');
      expect(presenter.containsKey('rootPath'), isFalse);

      final bridge = jsonFile('diagnostics/bridge.json');
      expect(bridge['bridgeVersion'], BridgeContract.implementationVersion);
      expect(bridge['bridgePayloadVersion'], BridgeContract.payloadVersion);
      final bridgeTemplate = bridge['template'] as Map<String, dynamic>;
      expect(bridgeTemplate['id'], 't1');
      expect(bridgeTemplate['publishedVersionNo'], 3);
      expect(bridgeTemplate.containsKey('document'), isFalse);

      final manifest = jsonFile('manifest.json');
      expect(manifest['format'], 'urb-template-package');
      expect(manifest['packageVersion'], 1);
      expect(manifest['generatedAt'], '2026-08-14T01:02:03.000Z');
      expect(manifest['producer'], 'bridge');
      expect(manifest['packageKind'], 'diagnostics');
      expect(manifest['sourceSystemCode'], 'motakamel_transactions');
      expect(manifest['seedData'], <String, dynamic>{'mode': 'redacted'});

      final integrity = manifest['integrity'] as Map<String, dynamic>;
      expect(integrity['algorithm'], 'sha256');
      final hashes = integrity['files'] as Map<String, dynamic>;
      final physicalPayloads = archive
          .map((entry) => entry.name)
          .where((name) => name != 'manifest.json')
          .toSet();
      expect(hashes.keys.toSet(), physicalPayloads);
      expect(hashes.containsKey('manifest.json'), isFalse);
      for (final path in physicalPayloads) {
        expect(hashes[path], sha256.convert(rawFile(path)).toString());
      }
    },
  );
}
