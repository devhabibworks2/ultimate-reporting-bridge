import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';

Future<void> main() async {
  final workRoot = await Directory.systemTemp.createTemp(
    'bridge_runtime_demo_',
  );
  final presenterRoot = Directory('${workRoot.path}/presenter');
  final runtimeRoot = Directory('${workRoot.path}/runtime');
  await presenterRoot.create(recursive: true);
  await runtimeRoot.create(recursive: true);

  final index = File('${presenterRoot.path}/index.html');
  await index.writeAsString(_demoPresenterHtml, flush: true);

  final storage = RuntimeSessionStorage(runtimeRoot: runtimeRoot);
  final session = await storage.prepareRuntimeSession(
    const RuntimeSessionInput(
      sessionId: 'phase8-bridge-session',
      reportType: 'invoice',
      reportName: 'Bridge Runtime Verification',
      mode: 'offline',
      locale: 'en',
      direction: 'ltr',
      seedData: <String, dynamic>{
        'ReportId': 'DocReport_Seed',
        'ReportTitel': 'Bridge Demo Runtime',
      },
      templateDocument: <String, dynamic>{
        'meta': <String, dynamic>{'template': 'demo'},
      },
    ),
  );

  final server = LocalPresenterServer(
    presenterRoot: presenterRoot,
    runtimeRoot: runtimeRoot,
  );
  final handle = await server.start(sessionId: session.sessionId);

  final metadataFile = File('${workRoot.path}/bridge_runtime_metadata.json');
  await metadataFile.writeAsString(
    jsonEncode(<String, dynamic>{
      'workRoot': workRoot.path,
      'baseUrl': handle.baseUrl,
      'presenterUrl': handle.presenterUrl,
      'seedPath': session.seedReportData?.path,
      'templatePath': session.template?.path,
      'sessionPath': session.session?.path,
    }),
    flush: true,
  );

  stdout.writeln('BRIDGE_RUNTIME_WORK_ROOT=${workRoot.path}');
  stdout.writeln('BRIDGE_RUNTIME_BASE_URL=${handle.baseUrl}');
  stdout.writeln('BRIDGE_RUNTIME_URL=${handle.presenterUrl}');
  stdout.writeln('BRIDGE_RUNTIME_METADATA=${metadataFile.path}');
  stdout.writeln('BRIDGE_RUNTIME_SESSION=${session.sessionId}');
  stdout.writeln('BRIDGE_RUNTIME_SERVER_READY=1');
  stdout.writeln('Press Ctrl+C to stop.');

  final stopSignal = Completer<void>();
  ProcessSignal.sigint.watch().first.then((_) async {
    if (!stopSignal.isCompleted) {
      stopSignal.complete();
    }
  });
  ProcessSignal.sigterm.watch().first.then((_) async {
    if (!stopSignal.isCompleted) {
      stopSignal.complete();
    }
  });

  await stopSignal.future;
  await handle.stop();
  await workRoot.delete(recursive: true);
}

const String _demoPresenterHtml = '''
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Bridge Runtime Demo Presenter</title>
  </head>
  <body>
    <h1>Bridge Runtime Demo Presenter</h1>
    <p id="session"></p>
    <script>
      const params = new URLSearchParams(window.location.search);
      document.getElementById('session').textContent = 'sessionId=' + (params.get('sessionId') || '');
    </script>
  </body>
</html>
''';
