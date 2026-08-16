import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:reporting_bridge_flutter/src/localization/report_flow_strings.dart';

void main() {
  test(
    'template presentation metadata never mutates the canonical document',
    () {
      final document = <String, dynamic>{
        'schemaVersion': '1.0.0',
        'meta': <String, dynamic>{
          'name': 'Invoice',
          'family': 'sales_invoice',
          'description': 'Canonical invoice',
        },
        'page': <String, dynamic>{
          'layout': 'Pages',
          'size': 'A4',
          'unit': 'mm',
          'orientation': 'portrait',
          'language': 'en',
          'direction': 'ltr',
          'width': 210,
          'height': 297,
        },
      };
      final before = jsonEncode(document);
      final template = CachedTemplate(
        id: 'invoice',
        type: 'sales_invoice',
        document: document,
        version: '1.0.0',
      );

      final metadata = TemplatePresentationMetadata.tryFromTemplate(
        template,
        strings: ReportFlowStrings(const Locale('en')),
      );

      expect(metadata, isNotNull);
      expect(metadata!.sizeLabel, 'A4');
      expect(metadata.reportTypeLabel, 'Sales Invoice');
      expect(jsonEncode(document), before);
    },
  );
}
