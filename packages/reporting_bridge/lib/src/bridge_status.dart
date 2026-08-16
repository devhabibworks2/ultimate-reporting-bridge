import 'bridge_config.dart';
import 'bridge_contract.dart';
import 'bridge_selected_template.dart';

class BridgeWarning {
  const BridgeWarning({required this.code, required this.message});

  final String code;
  final String message;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{'code': code, 'message': message};
  }
}

class BridgeStatus {
  const BridgeStatus({
    this.contractVersion = BridgeContract.payloadVersion,
    this.mode,
    this.isPresenterCached = false,
    this.areTemplatesCached = false,
    this.selectedTemplate,
    this.apiHeaders,
    this.warnings = const <BridgeWarning>[],
  });

  final int contractVersion;
  final String? mode;
  final bool isPresenterCached;
  final bool areTemplatesCached;
  final SelectedTemplate? selectedTemplate;
  final ApiHeaderConfig? apiHeaders;
  final List<BridgeWarning> warnings;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'contractVersion': contractVersion,
      if (mode != null) 'mode': mode,
      'isPresenterCached': isPresenterCached,
      'areTemplatesCached': areTemplatesCached,
      if (selectedTemplate != null)
        'selectedTemplates': selectedTemplate!.toMap(),
      if (apiHeaders != null) 'apiHeaders': apiHeaders!.toRedactedMap(),
      if (warnings.isNotEmpty)
        'warnings': warnings.map((warning) => warning.toMap()).toList(),
    };
  }
}
