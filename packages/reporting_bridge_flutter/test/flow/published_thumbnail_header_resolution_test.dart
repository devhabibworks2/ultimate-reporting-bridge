import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:reporting_bridge_flutter/src/flow/report_flow_controller_base.dart';

void main() {
  final context = BridgeHeaderContext(
    operation: BridgeHeaderOperation.publishedThumbnail,
    apiBaseUrl: Uri.parse('https://example.test/api'),
  );

  test('cancellation releases a pending authenticated header lookup', () async {
    final never = Completer<Map<String, String>>();
    final cancel = Completer<void>();
    final headers = resolveCancellableThumbnailHeaders(
      context: context,
      provider: (_) => never.future,
      fallback: const <String, String>{},
      cancellation: cancel.future,
    );
    cancel.complete();
    await expectLater(
      headers.timeout(const Duration(seconds: 1)),
      throwsA(isA<StateError>()),
    );
  });

  test('header lookup has a bounded total deadline', () async {
    final never = Completer<Map<String, String>>();
    final cancel = Completer<void>();
    await expectLater(
      resolveCancellableThumbnailHeaders(
        context: context,
        provider: (_) => never.future,
        fallback: const <String, String>{},
        cancellation: cancel.future,
        deadline: const Duration(milliseconds: 60),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });
}
