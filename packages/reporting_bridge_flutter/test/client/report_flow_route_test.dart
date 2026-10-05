import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/src/client/reporting_bridge_flutter_client.dart';

void main() {
  test('report flow route is opaque and has no host-revealing transition', () {
    final route = buildReportFlowRouteForTesting<void>(
      builder: (_) => const SizedBox.shrink(),
    );

    expect(route.opaque, isTrue);
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
  });
}
