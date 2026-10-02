import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('inline session round-trips TemplateCode and ignores templateId', () {
    final payload = BridgeInlineSessionPayload.fromMap(<dynamic, dynamic>{
      'contractVersion': 1,
      'templateDocument': <dynamic, dynamic>{'meta': <dynamic, dynamic>{}},
      'runtimeData': <dynamic, dynamic>{'ReportId': '1'},
      'templateCode': ' INV-A ',
      'templateId': 595,
    });

    expect(payload.templateCodeHint, 'INV-A');
    final serialized = payload.toMap();
    expect(serialized['templateCode'], 'INV-A');
    expect(serialized.containsKey('templateId'), isFalse);
  });

  test('id-only inline session provides no template identity hint', () {
    final payload = BridgeInlineSessionPayload.fromMap(<dynamic, dynamic>{
      'contractVersion': 1,
      'templateDocument': <dynamic, dynamic>{'meta': <dynamic, dynamic>{}},
      'runtimeData': <dynamic, dynamic>{'ReportId': '1'},
      'templateId': 595,
    });

    expect(payload.templateCodeHint, isNull);
    expect(payload.toMap().containsKey('templateId'), isFalse);
  });
}
