import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  test(
    'canonical Admin fixture remains byte-for-value identical in cache model',
    () async {
      final source = File(
        'test/fixtures/canonical-template/mixed-document.json',
      );
      final decoded = jsonDecode(await source.readAsString());
      expect(decoded, isA<Map<String, dynamic>>());
      final document = Map<String, dynamic>.from(decoded as Map);

      final template = CachedTemplate(
        id: 'mixed',
        type: 'invoice',
        systemId: 1,
        document: document,
      );

      expect(template.document, equals(document));
      expect(template.toMap()['document'], equals(document));
    },
  );
}
