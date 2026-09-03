from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, found {count}")
    p.write_text(text.replace(old, new, 1))


replace_once(
    "packages/reporting_bridge/lib/src/bridge_runtime_error.dart",
    "  static const String templateDocumentInvalid = 'TEMPLATE_DOCUMENT_INVALID';\n",
    "  static const String templateDocumentInvalid = 'TEMPLATE_DOCUMENT_INVALID';\n"
    "  static const String staleTemplateSelection = 'STALE_TEMPLATE_SELECTION';\n",
)

replace_once(
    "packages/reporting_bridge/lib/src/bridge_template_cache.dart",
    "  SelectedTemplate get selectedTemplate => SelectedTemplate(\n"
    "    id: id,\n"
    "    type: type,\n"
    "    code: templateCode,\n"
    "    systemCode: systemCode,\n"
    "  );\n",
    "  SelectedTemplate get selectedTemplate => SelectedTemplate(\n"
    "    id: id,\n"
    "    type: type,\n"
    "    code: durableTemplateCode,\n"
    "    systemCode: systemCode,\n"
    "  );\n",
)

replace_once(
    "packages/reporting_bridge/lib/src/bridge_template_cache.dart",
    "  String get templateCode {\n"
    "    final explicit = code?.trim();\n"
    "    if (explicit != null && explicit.isNotEmpty) return explicit;\n\n"
    "    final meta = document['meta'];\n"
    "    if (meta is Map) {\n"
    "      final value = (meta['code'] ?? meta['id'])?.toString().trim();\n"
    "      if (value != null && value.isNotEmpty) return value;\n"
    "    }\n"
    "    return id;\n"
    "  }\n",
    "  String? get durableTemplateCode {\n"
    "    final explicit = code?.trim();\n"
    "    if (explicit != null && explicit.isNotEmpty) return explicit;\n\n"
    "    final meta = document['meta'];\n"
    "    if (meta is Map) {\n"
    "      final value = meta['code']?.toString().trim();\n"
    "      if (value != null && value.isNotEmpty) return value;\n"
    "    }\n"
    "    return null;\n"
    "  }\n\n"
    "  String get templateCode {\n"
    "    final durable = durableTemplateCode;\n"
    "    if (durable != null) return durable;\n\n"
    "    final meta = document['meta'];\n"
    "    if (meta is Map) {\n"
    "      final legacy = meta['id']?.toString().trim();\n"
    "      if (legacy != null && legacy.isNotEmpty) return legacy;\n"
    "    }\n"
    "    return id;\n"
    "  }\n",
)

replace_once(
    "packages/reporting_bridge/lib/src/bridge_template_cache.dart",
    "      catalog: catalog.map(\n"
    "        (template) => SelectedTemplateCatalogEntry(\n"
    "          id: template.id,\n"
    "          type: template.type,\n"
    "          code: template.templateCode,\n"
    "          systemCode: systemCode,\n"
    "        ),\n"
    "      ),\n",
    "      catalog: catalog.expand((template) {\n"
    "        final code = template.durableTemplateCode;\n"
    "        if (code == null) return const <SelectedTemplateCatalogEntry>[];\n"
    "        return <SelectedTemplateCatalogEntry>[\n"
    "          SelectedTemplateCatalogEntry(\n"
    "            id: template.id,\n"
    "            type: template.type,\n"
    "            code: code,\n"
    "            systemCode: systemCode,\n"
    "          ),\n"
    "        ];\n"
    "      }),\n",
)

old_resolver = """    if (storedSelection != null &&
        storedSelection.matchesType(reportType) &&
        storedSelection.systemCode == systemCode) {
      final storedCode = storedSelection.code?.trim();
      if (storedCode != null && storedCode.isNotEmpty) {
        for (final template in compatible) {
          if (template.templateCode == storedCode) {
            return TemplateSelectionResult(
              status: 'stored-selected',
              template: template,
            );
          }
        }
      } else {
        for (final template in compatible) {
          if (template.id == storedSelection.id) {
            return TemplateSelectionResult(
              status: 'stored-selected',
              template: template,
            );
          }
        }
      }
    }
    if (compatible.length == 1) {
"""
new_resolver = """    if (storedSelection != null) {
      if (storedSelection.matchesType(reportType) &&
          storedSelection.systemCode == systemCode) {
        final storedCode = storedSelection.code?.trim();
        if (storedCode != null && storedCode.isNotEmpty) {
          for (final template in compatible) {
            if (template.templateCode == storedCode) {
              return TemplateSelectionResult(
                status: 'stored-selected',
                template: template,
              );
            }
          }
        } else {
          for (final template in compatible) {
            if (template.id == storedSelection.id) {
              return TemplateSelectionResult(
                status: 'stored-selected',
                template: template,
              );
            }
          }
        }
      }
      return const TemplateSelectionResult(
        status: 'selection-required',
        errorCode: BridgeRuntimeErrorCodes.staleTemplateSelection,
      );
    }
    if (compatible.length == 1) {
"""
replace_once(
    "packages/reporting_bridge/lib/src/bridge_template_cache.dart",
    old_resolver,
    new_resolver,
)

marker = """      late final CachedTemplate template;
      try {
        template = CachedTemplate.fromMap(raw, systemCode: responseSystemCode);
"""
replacement = """      final topLevelCode = _nonEmptyString(raw['code']);
      final rawDocument = raw['document'];
      final rawMeta = rawDocument is Map ? rawDocument['meta'] : null;
      final documentCode = rawMeta is Map ? _nonEmptyString(rawMeta['code']) : null;
      if (topLevelCode == null ||
          documentCode == null ||
          topLevelCode != documentCode) {
        throw BridgeRuntimeException(
          BridgeTemplateSyncErrorCodes.templateCatalogInvalid,
          'Template query item $index requires matching non-empty '
          'code and document.meta.code.',
        );
      }

      late final CachedTemplate template;
      try {
        template = CachedTemplate.fromMap(raw, systemCode: responseSystemCode);
"""
replace_once(
    "packages/reporting_bridge/lib/src/bridge_template_sync.dart",
    marker,
    replacement,
)

replace_once(
    "packages/reporting_bridge/test/bridge_selected_template_code_test.dart",
    "      expect(result.status, 'auto-selected');\n"
    "      expect(result.template?.id, '44');\n",
    "      expect(result.status, 'selection-required');\n"
    "      expect(result.template, isNull);\n"
    "      expect(\n"
    "        result.errorCode,\n"
    "        BridgeRuntimeErrorCodes.staleTemplateSelection,\n"
    "      );\n",
)

replace_once(
    "packages/reporting_bridge/test/bridge_template_query_transport_test.dart",
    "      'meta': <String, dynamic>{'name': 'Template $id'},\n",
    "      'meta': <String, dynamic>{\n"
    "        'name': 'Template $id',\n"
    "        'code': '$id-code',\n"
    "      },\n",
)
