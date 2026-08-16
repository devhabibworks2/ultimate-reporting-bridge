import 'dart:convert';
import 'dart:io';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test(
    'preserves the Task 13 canonical document through transport and cache',
    () async {
      final fixture = _fixture();
      final source = await fixture.readAsString();
      final document =
          (jsonDecode(source) as Map<String, dynamic>)['document']
              as Map<String, dynamic>;
      final root = await Directory.systemTemp.createTemp('task13-bridge-');
      addTearDown(() => root.delete(recursive: true));

      final cache = TemplateCacheService(
        cacheRoot: Directory('${root.path}/templates'),
      );
      final outbound = CachedTemplate(
        id: 'task13-canonical-document-fixture',
        type: 'invoice',
        document: document,
        minPresenterVersion: '1.0.0',
        minBridgeVersion: '1.0.0',
      );
      final transported = CachedTemplate.fromMap(
        jsonDecode(jsonEncode(outbound.toMap())) as Map<String, dynamic>,
      );
      expect(jsonEncode(transported.document), jsonEncode(document));

      await cache.putTemplate(transported);

      final restored = await cache.getTemplate(
        'task13-canonical-document-fixture',
      );
      expect(restored, isNotNull);
      expect(restored!.document, document);
    },
  );
}

File _fixture() {
  return File('test/fixtures/task13-cross-stack-canonical-document.v1.json');
}
