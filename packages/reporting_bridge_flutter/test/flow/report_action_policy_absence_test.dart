import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public and runtime contracts no longer contain action policy', () {
    final barrel = File('lib/reporting_bridge_flutter.dart').readAsStringSync();
    final request = File(
      'lib/src/contracts/report_open_request.dart',
    ).readAsStringSync();
    final features = File(
      'lib/src/ui/bridge_ui_features.dart',
    ).readAsStringSync();
    final failures = File(
      'lib/src/flow/report_flow_failure.dart',
    ).readAsStringSync();

    expect(barrel, isNot(contains('report_action_policy.dart')));
    expect(request, isNot(contains('actionPolicy')));
    expect(features, isNot(contains('restrictTo(')));
    expect(failures, isNot(contains('actionDenied')));
  });
}
