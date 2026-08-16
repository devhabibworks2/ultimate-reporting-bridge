import 'dart:convert';

import 'bridge_config.dart';
import 'bridge_contract.dart';
import 'bridge_selected_template.dart';

/// Boot context from Host (`bridge_contract.md`: config, seedData, headers, hints).
class BridgeBootPayload {
  const BridgeBootPayload({
    required this.contractVersion,
    this.seedData,
    this.bearerToken,
    this.reportType,
    this.reportName,
    this.mode,
    this.locale,
    this.direction,
    this.presenterUrl,
    this.branding,
    this.apiHeaders,
    this.selectedTemplate,
    this.templateHints,
  });

  final int contractVersion;
  final Map<String, dynamic>? seedData;

  /// Backward-compatible token slot for the existing thin-slice Android host.
  /// New integrations should prefer `apiHeaders.Authorization`.
  final String? bearerToken;
  final String? reportType;
  final String? reportName;
  final String? mode;
  final String? locale;
  final String? direction;
  final String? presenterUrl;
  final BrandConfig? branding;
  final ApiHeaderConfig? apiHeaders;
  final SelectedTemplate? selectedTemplate;
  final Map<String, dynamic>? templateHints;

  int? get templateIdHint {
    final h = templateHints;
    if (h != null) {
      final v = h['templateId'] ?? h['selectedTemplateId'];
      if (v is int) {
        return v;
      }
      if (v is String) {
        return int.tryParse(v);
      }
    }
    final selectedId = selectedTemplate?.id;
    if (selectedId != null) {
      return int.tryParse(selectedId);
    }
    return null;
  }

  /// Parses host map; defaults [contractVersion] to [BridgeContract.payloadVersion] if absent.
  static BridgeBootPayload fromMap(Map<dynamic, dynamic> raw) {
    final version = raw['contractVersion'];
    final selectedTemplateRaw =
        raw['selectedTemplate'] ?? raw['selectedTemplates'];
    return BridgeBootPayload(
      contractVersion: version is int ? version : BridgeContract.payloadVersion,
      seedData: _deepMap(raw['seedData']),
      bearerToken: raw['bearerToken'] as String?,
      reportType: (raw['type'] ?? raw['reportType']) as String?,
      reportName: raw['reportName'] as String?,
      mode: raw['mode'] as String?,
      locale: raw['locale'] as String?,
      direction: raw['direction'] as String?,
      presenterUrl: raw['presenterUrl'] as String?,
      branding: BrandConfig.fromMap(_map(raw['branding'])),
      apiHeaders: ApiHeaderConfig.fromMap(_map(raw['apiHeaders'])),
      selectedTemplate: SelectedTemplate.fromMap(_map(selectedTemplateRaw)),
      templateHints: _deepMap(raw['templateHints']),
    );
  }

  static Map<String, dynamic>? _deepMap(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
    }
    return null;
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'contractVersion': contractVersion,
      if (seedData != null) 'seedData': seedData,
      if (bearerToken != null) 'bearerToken': bearerToken,
      if (reportType != null) 'type': reportType,
      if (reportName != null) 'reportName': reportName,
      if (mode != null) 'mode': mode,
      if (locale != null) 'locale': locale,
      if (direction != null) 'direction': direction,
      if (presenterUrl != null) 'presenterUrl': presenterUrl,
      if (branding != null) 'branding': branding!.toMap(),
      if (apiHeaders != null) 'apiHeaders': apiHeaders!.toMap(),
      if (selectedTemplate != null)
        'selectedTemplate': selectedTemplate!.toMap(),
      if (templateHints != null) 'templateHints': templateHints,
    };
  }
}

Map<dynamic, dynamic>? _map(Object? value) {
  if (value is Map) {
    return value;
  }
  return null;
}
