import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test(
    'localhost serves only the deployment-aligned Presenter route',
    () async {
      final temp = await Directory.systemTemp.createTemp('bridge_route_test_');
      addTearDown(() => temp.delete(recursive: true));
      final presenterRoot = Directory('${temp.path}/presenter');
      final runtimeRoot = Directory('${temp.path}/runtime');
      await presenterRoot.create(recursive: true);
      await runtimeRoot.create(recursive: true);
      await File(
        '${presenterRoot.path}/index.html',
      ).writeAsString('<html>ok</html>');

      final server = LocalPresenterServer(
        presenterRoot: presenterRoot,
        runtimeRoot: runtimeRoot,
      );
      final handle = await server.start(sessionId: 's1');
      addTearDown(handle.stop);
      final client = HttpClient();
      addTearDown(client.close);

      final aligned = await client.getUrl(
        Uri.parse('${handle.baseUrl}/UltimateReport/apps/presenter/index.html'),
      );
      final alignedResponse = await aligned.close();
      await alignedResponse.drain<void>();
      expect(alignedResponse.statusCode, HttpStatus.ok);

      final legacy = await client.getUrl(
        Uri.parse('${handle.baseUrl}/Report/presenter'),
      );
      final legacyResponse = await legacy.close();
      await legacyResponse.drain<void>();
      expect(legacyResponse.statusCode, HttpStatus.notFound);
    },
  );
}
