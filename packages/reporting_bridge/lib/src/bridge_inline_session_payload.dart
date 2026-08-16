import 'bridge_contract.dart';

/// Payload for [BridgeMethods.applyInlineSession].
///
/// Both Admin (web postMessage) and Bridge (mobile MethodChannel) send the
/// same logical payload: template document, runtime data, optional session
/// metadata, and UI flags.
class BridgeInlineSessionPayload {
  const BridgeInlineSessionPayload({
    required this.contractVersion,
    required this.templateDocument,
    required this.runtimeData,
    this.sessionData,
    this.wantPdf = false,
    this.modeLabel = 'preview',
    this.templateName,
    this.templateIdHint,
  });

  final int contractVersion;
  final Map<String, dynamic> templateDocument;
  final Map<String, dynamic> runtimeData;
  final Map<String, dynamic>? sessionData;
  final bool wantPdf;
  final String modeLabel;
  final String? templateName;
  final int? templateIdHint;

  static BridgeInlineSessionPayload fromMap(Map<dynamic, dynamic> raw) {
    return BridgeInlineSessionPayload(
      contractVersion: raw['contractVersion'] is int
          ? raw['contractVersion'] as int
          : BridgeContract.payloadVersion,
      templateDocument: Map<String, dynamic>.from(
        raw['templateDocument'] as Map,
      ),
      runtimeData: Map<String, dynamic>.from(raw['runtimeData'] as Map),
      sessionData: raw['sessionData'] is Map
          ? Map<String, dynamic>.from(raw['sessionData'] as Map)
          : null,
      wantPdf: raw['wantPdf'] == true,
      modeLabel: raw['mode']?.toString() ?? 'preview',
      templateName: raw['templateName']?.toString(),
      templateIdHint: raw['templateId'] is int
          ? raw['templateId'] as int
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'contractVersion': contractVersion,
      'templateDocument': templateDocument,
      'runtimeData': runtimeData,
      if (sessionData != null) 'sessionData': sessionData,
      'wantPdf': wantPdf,
      if (modeLabel != 'preview') 'mode': modeLabel,
      if (templateName != null) 'templateName': templateName,
      if (templateIdHint != null) 'templateId': templateIdHint,
    };
  }
}
