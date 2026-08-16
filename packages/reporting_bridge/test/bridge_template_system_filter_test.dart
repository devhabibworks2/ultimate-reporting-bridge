import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('preserves systemId and filters cached templates by system', () async {
    final temp = await Directory.systemTemp.createTemp(
      'bridge_template_system_filter_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final cache = TemplateCacheService(cacheRoot: temp);
    await cache.putTemplate(
      const CachedTemplate(
        id: 'erp-invoice',
        type: 'invoice',
        systemId: 1,
        document: <String, dynamic>{
          'meta': <String, dynamic>{'name': 'ERP Invoice'},
        },
      ),
    );
    await cache.putTemplate(
      const CachedTemplate(
        id: 'pos-invoice',
        type: 'invoice',
        systemId: 2,
        document: <String, dynamic>{
          'meta': <String, dynamic>{'name': 'POS Invoice'},
        },
      ),
    );

    final erpTemplates = await cache.listTemplates(
      type: 'invoice',
      systemId: 1,
    );

    expect(erpTemplates, hasLength(1));
    expect(erpTemplates.single.id, 'erp-invoice');
    expect(erpTemplates.single.systemId, 1);
  });

  test('reads canonical presenter compatibility metadata without aliases', () {
    final template = CachedTemplate.fromMap(<String, dynamic>{
      'id': 34,
      'type': 'invoice',
      'systemId': 7,
      'code': 'invoice_standard',
      'name': 'Canonical Invoice',
      'document': <String, dynamic>{
        'meta': <String, dynamic>{'name': 'Canonical Invoice'},
      },
      'compatibility': <String, dynamic>{
        'version': '4',
        'minPresenterVersion': '2.1.0',
        'minBridgeVersion': '1.0.0',
      },
    });

    expect(template.id, '34');
    expect(template.type, 'invoice');
    expect(template.systemId, 7);
    expect(template.templateCode, 'invoice_standard');
    expect(template.templateName, 'Canonical Invoice');
    expect(template.version, '4');
    expect(template.minPresenterVersion, '2.1.0');
    expect(template.minBridgeVersion, '1.0.0');
    expect(
      template.isCompatibleWith(
        presenterVersion: '2.1.0',
        bridgeVersion: '1.0.0',
      ),
      isTrue,
    );
    expect(
      template.isCompatibleWith(
        presenterVersion: '2.0.9',
        bridgeVersion: '1.0.0',
      ),
      isFalse,
    );
  });

  test('compares semantic prerelease versions correctly', () {
    final release = BridgeSemanticVersion.tryParse('1.2.3');
    final candidate = BridgeSemanticVersion.tryParse('1.2.3-rc.1');
    final next = BridgeSemanticVersion.tryParse('1.3.0');

    expect(release, isNotNull);
    expect(candidate, isNotNull);
    expect(next, isNotNull);
    expect(release!.compareTo(candidate!), greaterThan(0));
    expect(next!.compareTo(release), greaterThan(0));
  });
}
