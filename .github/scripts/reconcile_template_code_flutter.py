from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace(path: str, old: str, new: str, *, count: int = 1) -> None:
    file = ROOT / path
    text = file.read_text()
    actual = text.count(old)
    if actual < count:
        raise SystemExit(f"{path}: expected at least {count} occurrences, found {actual}: {old[:120]!r}")
    text = text.replace(old, new, count)
    file.write_text(text)
    print(f"patched {path}: {count} replacement(s)")


# Runtime-only/in-memory preference stores may retain the cache ID alongside Code.
# SharedPreferences remains the durable boundary and writes only systemCode+templateCode.
replace(
    "packages/reporting_bridge_flutter/lib/src/persistence/report_flow_preference_store.dart",
    """class MemoryReportFlowPreferenceStore implements ReportFlowPreferenceStore {\n  final Map<String, String> _selectedCodes = <String, String>{};\n  final Map<String, PresenterModePreference> _modes =\n      <String, PresenterModePreference>{};\n\n  @override\n  Future<ReportFlowPreferences?> load(ReportPreferenceScope scope) async {\n    final templateCode = _selectedCodes[scope.selectedTemplateCanonical];\n    final mode = _modes[scope.presenterModeCanonical];\n    if (templateCode != null) {\n      return ReportFlowPreferences(\n        templateCode: templateCode,\n        mode: mode ?? PresenterModePreference.online,\n      );\n    }\n    if (mode != null) {\n      return ReportFlowPreferences(mode: mode);\n    }\n    return null;\n  }\n\n  @override\n  Future<void> remove(ReportPreferenceScope scope) async {\n    _selectedCodes.remove(scope.selectedTemplateCanonical);\n    _modes.remove(scope.presenterModeCanonical);\n  }\n\n  @override\n  Future<void> removeSelectedTemplate(ReportPreferenceScope scope) async {\n    _selectedCodes.remove(scope.selectedTemplateCanonical);\n  }\n\n  @override\n  Future<void> save(\n    ReportPreferenceScope scope,\n    ReportFlowPreferences preferences,\n  ) async {\n    final templateCode = preferences.templateCode?.trim();\n    if (templateCode != null && templateCode.isNotEmpty) {\n      _selectedCodes[scope.selectedTemplateCanonical] = templateCode;\n    } else if (preferences.templateId == null) {\n      _selectedCodes.remove(scope.selectedTemplateCanonical);\n    }\n    _modes[scope.presenterModeCanonical] = preferences.mode;\n  }\n}\n""",
    """class MemoryReportFlowPreferenceStore implements ReportFlowPreferenceStore {\n  final Map<String, ReportFlowPreferences> _selected =\n      <String, ReportFlowPreferences>{};\n  final Map<String, PresenterModePreference> _modes =\n      <String, PresenterModePreference>{};\n\n  @override\n  Future<ReportFlowPreferences?> load(ReportPreferenceScope scope) async {\n    final selected = _selected[scope.selectedTemplateCanonical];\n    final mode = _modes[scope.presenterModeCanonical];\n    if (selected != null) {\n      return selected.copyWith(mode: mode ?? selected.mode);\n    }\n    if (mode != null) {\n      return ReportFlowPreferences(mode: mode);\n    }\n    return null;\n  }\n\n  @override\n  Future<void> remove(ReportPreferenceScope scope) async {\n    _selected.remove(scope.selectedTemplateCanonical);\n    _modes.remove(scope.presenterModeCanonical);\n  }\n\n  @override\n  Future<void> removeSelectedTemplate(ReportPreferenceScope scope) async {\n    _selected.remove(scope.selectedTemplateCanonical);\n  }\n\n  @override\n  Future<void> save(\n    ReportPreferenceScope scope,\n    ReportFlowPreferences preferences,\n  ) async {\n    final templateId = preferences.templateId?.trim();\n    final templateCode = preferences.templateCode?.trim();\n    if ((templateId != null && templateId.isNotEmpty) ||\n        (templateCode != null && templateCode.isNotEmpty)) {\n      _selected[scope.selectedTemplateCanonical] = preferences;\n    } else {\n      _selected.remove(scope.selectedTemplateCanonical);\n    }\n    _modes[scope.presenterModeCanonical] = preferences.mode;\n  }\n}\n""",
)

controller = "packages/reporting_bridge_flutter/lib/src/flow/report_flow_controller_impl.dart"
replace(
    controller,
    """          ReportFlowPreferences(\n            templateCode: durableCode,\n            mode: stored.mode,\n          ),\n""",
    """          ReportFlowPreferences(\n            templateId: template.id,\n            templateCode: durableCode,\n            mode: stored.mode,\n          ),\n""",
)
replace(
    controller,
    """      final durable = ReportFlowPreferences(\n        templateCode: explicitCode,\n        mode: preferences.mode,\n      );\n""",
    """      final durable = ReportFlowPreferences(\n        templateId: preferences.templateId,\n        templateCode: explicitCode,\n        mode: preferences.mode,\n      );\n""",
)
replace(
    controller,
    """      ReportFlowPreferences(\n        templateCode: templateCode,\n        mode: preferences.mode,\n      ),\n""",
    """      ReportFlowPreferences(\n        templateId: template.id,\n        templateCode: templateCode,\n        mode: preferences.mode,\n      ),\n""",
)

# Shared controller fixtures: every selectable template has a genuine business Code.
path = "packages/reporting_bridge_flutter/test/flow/report_flow_controller_test.dart"
replace(path, """  systemId: 1,\n  name: 'Template $id',\n  version: '1.0.0',\n  document: const <String, dynamic>{\n    'schemaVersion': '1.0.0',\n    'meta': <String, dynamic>{'name': 'Invoice', 'family': 'sales_invoice'},\n""", """  systemId: 1,\n  code: 'CODE-$id',\n  name: 'Template $id',\n  version: '1.0.0',\n  document: <String, dynamic>{\n    'schemaVersion': '1.0.0',\n    'meta': <String, dynamic>{\n      'name': 'Invoice',\n      'family': 'sales_invoice',\n      'code': 'CODE-$id',\n    },\n""")
replace(path, """  systemId: 1,\n  name: 'Template $id',\n  version: '1.0.0',\n  document: <String, dynamic>{\n    'schemaVersion': '1.0.0',\n    'meta': <String, dynamic>{'name': 'Template', 'family': family},\n""", """  systemId: 1,\n  code: 'CODE-$id',\n  name: 'Template $id',\n  version: '1.0.0',\n  document: <String, dynamic>{\n    'schemaVersion': '1.0.0',\n    'meta': <String, dynamic>{\n      'name': 'Template',\n      'family': family,\n      'code': 'CODE-$id',\n    },\n""")
replace(path, """    systemId: 1,\n    name: 'Template $id',\n    version: '1.0.0',\n    document: <String, dynamic>{\n      'schemaVersion': '1.0.0',\n      'meta': const <String, dynamic>{\n        'name': 'Invoice',\n        'family': 'sales_invoice',\n      },\n""", """    systemId: 1,\n    code: 'CODE-$id',\n    name: 'Template $id',\n    version: '1.0.0',\n    document: <String, dynamic>{\n      'schemaVersion': '1.0.0',\n      'meta': <String, dynamic>{\n        'name': 'Invoice',\n        'family': 'sales_invoice',\n        'code': 'CODE-$id',\n      },\n""")

# Client/print fixtures use canonical System + Code.
for path in [
    "packages/reporting_bridge_flutter/test/client/reporting_bridge_flutter_client_print_integration_test.dart",
    "packages/reporting_bridge_flutter/test/client/public_print_composition_test.dart",
]:
    replace(path, """  systemId: 7,\n  name: 'Thermal invoice',\n  document: const <String, dynamic>{\n""", """  systemId: 7,\n  systemCode: 'motakamel_transactions',\n  code: 'THERMAL-EN',\n  name: 'Thermal invoice',\n  document: const <String, dynamic>{\n""")
    replace(path, """      'family': 'sales_invoice',\n      'systemCode': 'motakamel_transactions',\n""", """      'family': 'sales_invoice',\n      'systemCode': 'motakamel_transactions',\n      'code': 'THERMAL-EN',\n""")

path = "packages/reporting_bridge_flutter/test/client/reporting_bridge_flutter_client_print_integration_test.dart"
replace(path, """  systemId: 7,\n  name: 'Pages invoice AR',\n  document: const <String, dynamic>{\n""", """  systemId: 7,\n  systemCode: 'motakamel_transactions',\n  code: 'PAGES-AR',\n  name: 'Pages invoice AR',\n  document: const <String, dynamic>{\n""")
replace(path, """      'name': 'Pages invoice AR',\n      'family': 'sales_invoice',\n      'systemCode': 'motakamel_transactions',\n""", """      'name': 'Pages invoice AR',\n      'family': 'sales_invoice',\n      'systemCode': 'motakamel_transactions',\n      'code': 'PAGES-AR',\n""")

path = "packages/reporting_bridge_flutter/test/flow/report_print_policy_controller_test.dart"
replace(path, """      systemId: 1,\n      name: id,\n      document: <String, dynamic>{\n        'schemaVersion': '1.0.0',\n        'meta': const <String, dynamic>{\n          'name': 'Thermal invoice',\n          'family': 'sales_invoice',\n          'systemCode': 'motakamel_transactions',\n        },\n""", """      systemId: 1,\n      systemCode: 'motakamel_transactions',\n      code: 'CODE-$id',\n      name: id,\n      document: <String, dynamic>{\n        'schemaVersion': '1.0.0',\n        'meta': <String, dynamic>{\n          'name': 'Thermal invoice',\n          'family': 'sales_invoice',\n          'systemCode': 'motakamel_transactions',\n          'code': 'CODE-$id',\n        },\n""")
replace(path, """  systemId: 1,\n  name: id,\n  document: const <String, dynamic>{\n""", """  systemId: 1,\n  systemCode: 'motakamel_transactions',\n  code: 'CODE-$id',\n  name: id,\n  document: <String, dynamic>{\n""")
replace(path, """      'name': 'A4 invoice',\n      'family': 'sales_invoice',\n      'systemCode': 'motakamel_transactions',\n""", """      'name': 'A4 invoice',\n      'family': 'sales_invoice',\n      'systemCode': 'motakamel_transactions',\n      'code': 'CODE-$id',\n""")

path = "packages/reporting_bridge_flutter/test/ui/report_flow_screen_real_controller_test.dart"
replace(path, """  systemId: 1,\n  name: 'Template $id',\n  version: '1.0.0',\n  document: const <String, dynamic>{\n    'schemaVersion': '1.0.0',\n    'meta': <String, dynamic>{'name': 'Invoice', 'family': 'sales_invoice'},\n""", """  systemId: 1,\n  code: 'CODE-$id',\n  name: 'Template $id',\n  version: '1.0.0',\n  document: <String, dynamic>{\n    'schemaVersion': '1.0.0',\n    'meta': <String, dynamic>{\n      'name': 'Invoice',\n      'family': 'sales_invoice',\n      'code': 'CODE-$id',\n    },\n""")

path = "packages/reporting_bridge_flutter/test/persistence/preference_flow_migration_isolation_test.dart"
replace(path, """  systemId: 7,\n  code: 'legacy_system_7',\n  name: id,\n""", """  systemId: 7,\n  code: 'CODE-$id',\n  name: id,\n""")
replace(path, """      'name': 'Invoice',\n      'family': 'sales_invoice',\n""", """      'name': 'Invoice',\n      'family': 'sales_invoice',\n      'code': 'CODE-$id',\n""")
replace(path, "test('new writes remain V5 only', () async {", "test('new writes use V6 Code identity only', () async {")
replace(path, """        const ReportFlowPreferences(\n          templateId: 'fresh',\n          mode: PresenterModePreference.online,\n        ),\n      );\n      expect(\n        prefs.getKeys().where((key) => key.contains('selected_template.v5.')),\n        isNotEmpty,\n      );\n""", """        const ReportFlowPreferences(\n          templateCode: 'FRESH-CODE',\n          mode: PresenterModePreference.online,\n        ),\n      );\n      expect(\n        prefs.getKeys().where((key) => key.contains('selected_template.v6.')),\n        isNotEmpty,\n      );\n      expect(\n        prefs.getKeys().where((key) => key.contains('selected_template.v5.')),\n        isEmpty,\n      );\n""")
replace(path, """        const ReportFlowPreferences(\n          templateId: 'gone-template',\n          mode: PresenterModePreference.offline,\n        ),\n""", """        const ReportFlowPreferences(\n          templateCode: 'GONE-CODE',\n          mode: PresenterModePreference.offline,\n        ),\n""")
replace(path, """      expect(controller.value.selectedTemplateId, isNot('gone-template'));\n""", """      expect(controller.value.selectedTemplateId, isNull);\n""")
replace(path, """          'urb.reporting_bridge.selected_template.v5.${scope.selectedTemplateStorageToken}',\n        ),\n        contains('gone-template'),\n""", """          'urb.reporting_bridge.selected_template.v6.${scope.selectedTemplateStorageToken}',\n        ),\n        contains('GONE-CODE'),\n""")

path = "packages/reporting_bridge_flutter/test/persistence/report_flow_preference_scope_test.dart"
replace(path, "test('selected-template token ignores language/layout/size/source', () {", "test('selected-template token is System-scoped and ignores presentation/source', () {")
replace(path, """    expect(base.selectedTemplateCanonical, isNot(contains('system=')));\n""", """    expect(\n      base.selectedTemplateCanonical,\n      contains('system=motakamel_transactions'),\n    );\n""")
replace(path, """    const first = ReportFlowPreferences(\n      templateId: 'template-a',\n      mode: PresenterModePreference.online,\n    );\n""", """    const first = ReportFlowPreferences(\n      templateCode: 'TEMPLATE-A',\n      mode: PresenterModePreference.online,\n    );\n""")
replace(path, """    expect((await store.load(base))?.templateId, 'template-a');\n""", """    expect((await store.load(base))?.templateCode, 'TEMPLATE-A');\n""")

path = "packages/reporting_bridge_flutter/test/persistence/report_flow_preference_store_test.dart"
replace(path, "group('V5 selected-template identity', () {", "group('V6 selected-template identity', () {")
replace(path, """        system: 'other_system',\n        reportType: 'sales_invoice',\n""", """        system: 'motakamel_transactions',\n        reportType: 'sales_invoice',\n""")
replace(path, """      const ReportFlowPreferences(\n        templateId: 'shared-template',\n        mode: PresenterModePreference.online,\n      ),\n""", """      const ReportFlowPreferences(\n        templateCode: 'SHARED-CODE',\n        mode: PresenterModePreference.online,\n      ),\n""")
replace(path, """      const ReportFlowPreferences(\n        templateId: 'shared-template',\n        mode: PresenterModePreference.offline,\n      ),\n""", """      const ReportFlowPreferences(\n        templateCode: 'SHARED-CODE',\n        mode: PresenterModePreference.offline,\n      ),\n""")
replace(path, """      first.selectedTemplateStorageToken,\n      second.selectedTemplateStorageToken,\n    );\n""", """      first.selectedTemplateStorageToken,\n      isNot(second.selectedTemplateStorageToken),\n    );\n""")
replace(path, """    'migrates V4 into V5 selected-template + mode without deleting V4',\n""", """    'loads V4 ID for controller migration and persists mode without inventing Code',\n""")
replace(path, """      expect(\n        preferences.getString(\n          'urb.reporting_bridge.selected_template.v5.${scope.selectedTemplateStorageToken}',\n        ),\n        jsonEncode(<String, dynamic>{'templateId': 'v4-template'}),\n      );\n""", """      expect(\n        preferences.getKeys().where(\n          (key) =>\n              key.contains('selected_template.v6.') ||\n              key.contains('selected_template.v5.'),\n        ),\n        isEmpty,\n      );\n""")
replace(path, """          templateId: 'invoice-template',\n          mode: PresenterModePreference.online,\n""", """          templateCode: 'INVOICE-CODE',\n          mode: PresenterModePreference.online,\n""")
replace(path, """          templateId: 'voucher-template',\n          mode: PresenterModePreference.offline,\n""", """          templateCode: 'VOUCHER-CODE',\n          mode: PresenterModePreference.offline,\n""")
replace(path, """    expect((await firstStore.load(firstScope))?.templateId, 'invoice-template');\n""", """    expect((await firstStore.load(firstScope))?.templateCode, 'INVOICE-CODE');\n""")
replace(path, """      (await secondStore.load(secondScope))?.templateId,\n      'voucher-template',\n""", """      (await secondStore.load(secondScope))?.templateCode,\n      'VOUCHER-CODE',\n""")
replace(path, """      const value = ReportFlowPreferences(\n        templateId: 'template',\n        mode: PresenterModePreference.online,\n      );\n""", """      const value = ReportFlowPreferences(\n        templateCode: 'TEMPLATE-CODE',\n        mode: PresenterModePreference.online,\n      );\n""")
replace(path, """      expect((await store.load(second))?.templateId, 'template');\n""", """      expect((await store.load(second))?.templateCode, 'TEMPLATE-CODE');\n""")

path = "packages/reporting_bridge_flutter/test/flow/workflow_bridge_client_integration_test.dart"
replace(path, """            'name': 'Invoice 80mm',\n            'systemCode': 'motakamel_transactions',\n""", """            'name': 'Invoice 80mm',\n            'systemCode': 'motakamel_transactions',\n            'code': 'invoice-80',\n""")

print('Template Code Flutter reconciliation patch complete')
