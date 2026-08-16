// T11 compatibility remains intentionally exercised by the numeric regression.
// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:reporting_bridge_flutter/src/flow/report_flow_controller_impl.dart';

void main() {
  group('_WorkflowBridgeClient.listTemplates cold-cache boundary', () {
    test(
      'systemCode OFFLINE_CACHE_UNAVAILABLE becomes an empty workflow list',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'urb-cold-cache-string-',
        );
        addTearDown(() async {
          if (await root.exists()) await root.delete(recursive: true);
        });
        const failure = BridgeRuntimeException(
          BridgeTemplateSyncErrorCodes.offlineCacheUnavailable,
          'No cached template catalog is available for the current scope.',
        );
        final delegate = _ListFailureBridgeClient(root, failure: failure);
        addTearDown(delegate.dispose);
        final client = createWorkflowBridgeClientForTesting(
          delegate: delegate,
          system: 'motakamel_transactions',
          templateSyncRequest: TemplateSyncRequest(
            systemCode: UrbSystem.motakamelTransactions,
          ),
        );
        addTearDown(client.dispose);

        final templates = await client.listTemplates();

        expect(templates, isEmpty);
        expect(delegate.listSystemCode, 'motakamel_transactions');
        expect(delegate.listSystemId, isNull);
      },
    );

    test(
      'systemCode unrelated BridgeRuntimeException still propagates',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'urb-cold-cache-error-',
        );
        addTearDown(() async {
          if (await root.exists()) await root.delete(recursive: true);
        });
        const failure = BridgeRuntimeException(
          BridgeTemplateSyncErrorCodes.systemNotFound,
          'Unknown system.',
        );
        final delegate = _ListFailureBridgeClient(root, failure: failure);
        addTearDown(delegate.dispose);
        final client = createWorkflowBridgeClientForTesting(
          delegate: delegate,
          system: 'motakamel_transactions',
          templateSyncRequest: TemplateSyncRequest(
            systemCode: UrbSystem.motakamelTransactions,
          ),
        );
        addTearDown(client.dispose);

        await expectLater(
          client.listTemplates(),
          throwsA(
            isA<BridgeRuntimeException>()
                .having(
                  (error) => error.code,
                  'code',
                  BridgeTemplateSyncErrorCodes.systemNotFound,
                )
                .having((error) => error.message, 'message', 'Unknown system.'),
          ),
        );
      },
    );
  });
}

final class _ListFailureBridgeClient extends ReportingBridgeClient {
  _ListFailureBridgeClient(Directory root, {required this.failure})
    : super(
        apiBaseUrl: Uri.parse('https://example.test/backend/'),
        presenterEntryUrl: Uri.parse('https://example.test/presenter/'),
        bridgeRoot: root,
      );

  final BridgeRuntimeException failure;
  String? listSystemCode;
  int? listSystemId;

  @override
  Future<List<CachedTemplate>> listTemplates({
    String? systemCode,
    int? systemId,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    listSystemCode = systemCode;
    listSystemId = systemId;
    throw failure;
  }
}
