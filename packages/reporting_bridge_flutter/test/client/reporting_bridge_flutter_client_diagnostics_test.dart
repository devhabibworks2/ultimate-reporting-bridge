import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  test('client API operations emit structured diagnostics', () async {
    final root = Directory.systemTemp.createTempSync('urb-client-log-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final records = <BridgeLogRecord>[];
    final connection = ReportServerConnection(
      endpoints: ReportServerEndpoints.deployed(
        Uri.parse('https://example.test'),
      ),
      cacheRoot: root,
      diagnostics: BridgeDiagnostics(sink: records.add),
    );
    final bridge = _DiagnosticBridgeClient(root);
    final client = DefaultReportingBridgeFlutterClient(
      connection: connection,
      bridgeClient: bridge,
      preferences: MemoryReportFlowPreferenceStore(),
      filePlatform: const _NoopFiles(),
      ui: const BridgeUiConfig.inheritHost(),
    );
    addTearDown(client.dispose);

    await client.probeEndpoints();

    expect(bridge.probeCalls, 1);
    expect(records.map((record) => record.event), <String>[
      'probeEndpoints.start',
      'probeEndpoints.success',
    ]);
    expect(
      records.where((record) => record.category == BridgeLogCategory.api),
      hasLength(2),
    );
    final rendered = records.map((record) => record.toConsoleLine()).join('\n');
    expect(rendered, contains('/UltimateReport/backend/api/health'));
  });
}

final class _DiagnosticBridgeClient extends ReportingBridgeClient {
  _DiagnosticBridgeClient(Directory root)
    : super(
        apiBaseUrl: Uri.parse(
          'https://example.test/UltimateReport/backend/api/',
        ),
        presenterEntryUrl: Uri.parse(
          'https://example.test/UltimateReport/apps/presenter/',
        ),
        bridgeRoot: root,
      );

  int probeCalls = 0;

  @override
  Future<void> probeEndpoints() async {
    probeCalls += 1;
  }
}

class _NoopFiles implements ReportFilePlatform {
  const _NoopFiles();

  @override
  Future<bool> savePdf(Uint8List bytes, String filename) async => true;

  @override
  Future<void> sharePdf(Uint8List bytes, String filename) async {}
}
