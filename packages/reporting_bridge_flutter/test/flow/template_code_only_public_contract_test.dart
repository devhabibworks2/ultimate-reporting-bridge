import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

import '../test_open_request.dart';

void main() {
  test('public report flow identity is TemplateCode-only', () {
    final request = buildTestOpenRequest(initialTemplateCode: ' INV-A ');
    expect(request.initialTemplateCode, 'INV-A');

    const template = CachedTemplate(
      type: 'sales_invoice',
      code: 'INV-A',
      document: <String, dynamic>{
        'meta': <String, dynamic>{'code': 'INV-A'},
      },
    );
    final state = ReportFlowState(
      stage: ReportFlowStage.previewing,
      selectedMode: PresenterModePreference.online,
      templates: const <CachedTemplate>[template],
      selectedTemplateCode: 'INV-A',
      committedTemplateCode: 'INV-A',
    );
    expect(state.selectedTemplate, same(template));
    expect(state.committedTemplate, same(template));

    const draft = ReportSettingsDraft(
      templateCode: 'INV-A',
      mode: PresenterModePreference.online,
    );
    expect(draft.templateCode, 'INV-A');

    const preferences = ReportFlowPreferences(
      templateCode: 'INV-A',
      mode: PresenterModePreference.online,
    );
    expect(preferences.toJson(), <String, dynamic>{
      'templateCode': 'INV-A',
      'mode': 'online',
    });
  });
}
