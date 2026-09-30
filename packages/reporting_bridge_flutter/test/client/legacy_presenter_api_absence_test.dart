import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter Bridge public client exposes no systems discovery API', () {
    final source = File(
      'lib/src/client/reporting_bridge_flutter_client.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('fetchSystems')));
    expect(source, isNot(contains('PresenterSystem')));
  });

  test('workflow Bridge client exposes no numeric template selector', () {
    final source = File(
      'lib/src/flow/report_flow_controller_impl.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('int? systemId')));
  });
}
