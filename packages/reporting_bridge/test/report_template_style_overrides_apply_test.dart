import 'dart:convert';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('applyReportTemplateStyleOverrides', () {
    test('copies a canonical document and changes only requested leaves', () {
      final source = _canonicalDocument();
      final sourceBefore = jsonEncode(source);

      final prepared = applyReportTemplateStyleOverrides(
        document: source,
        overrides: ReportTemplateStyleOverrides(
          color: <String, Object?>{'primary': '#0E5A9C'},
        ),
      );

      expect(jsonEncode(source), sourceBefore);
      expect(prepared, isNot(same(source)));
      expect(
        prepared['styleTokens'],
        containsPair('color', containsPair('primary', '#0E5A9C')),
      );
      expect(
        prepared['styleTokens'],
        containsPair('color', containsPair('table_header_bg', '#E8EEF5')),
      );
      expect(
        prepared['styleTokens'],
        containsPair('font', containsPair('weight_bold', '700')),
      );
      expect(
        prepared['styleTokens'],
        containsPair('spacing', containsPair('md', 8)),
      );
      expect(
        prepared['styleTokens'],
        containsPair('border', containsPair('width', 1)),
      );
      expect(
        prepared['styleTokens'],
        containsPair('radius', containsPair('md', 4)),
      );
      expect(
        prepared['styleTokens'],
        containsPair('system', containsPair('brand', 'canonical')),
      );
      expect(jsonEncode(prepared['elements']), jsonEncode(source['elements']));
      expect(
        ((prepared['elements'] as List).single as Map)['style'],
        containsPair('text', containsPair('color', '#112233')),
      );
    });

    test(
      'empty overrides preserve the document without changing the source',
      () {
        final source = _canonicalDocument();
        final sourceBefore = jsonEncode(source);

        final prepared = applyReportTemplateStyleOverrides(
          document: source,
          overrides: ReportTemplateStyleOverrides(),
        );

        expect(jsonEncode(prepared), jsonEncode(source));
        expect(jsonEncode(source), sourceBefore);
      },
    );

    test('adds only supplied paths when styleTokens is absent', () {
      final source = <String, dynamic>{
        'schemaVersion': '1.0.0',
        'elements': <dynamic>[
          <String, dynamic>{'id': 'literal', 'color': 'green'},
        ],
      };
      final sourceBefore = jsonEncode(source);

      final prepared = applyReportTemplateStyleOverrides(
        document: source,
        overrides: ReportTemplateStyleOverrides(
          color: <String, Object?>{'future_color_leaf': 12},
        ),
      );

      expect(jsonEncode(source), sourceBefore);
      expect(prepared['styleTokens'], <String, dynamic>{
        'color': <String, dynamic>{'future_color_leaf': 12},
      });
      expect(
        prepared.keys,
        unorderedEquals(<String>['schemaVersion', 'elements', 'styleTokens']),
      );
    });

    test(
      'fails clearly for scalar merge ancestors without mutating source',
      () {
        final documents = <Map<String, dynamic>>[
          <String, dynamic>{'styleTokens': 'scalar'},
          <String, dynamic>{
            'styleTokens': <String, dynamic>{'color': 'scalar'},
          },
        ];

        for (final source in documents) {
          final sourceBefore = jsonEncode(source);
          expect(
            () => applyReportTemplateStyleOverrides(
              document: source,
              overrides: ReportTemplateStyleOverrides(
                color: <String, Object?>{'primary': '#0E5A9C'},
              ),
            ),
            throwsA(isA<ArgumentError>()),
          );
          expect(jsonEncode(source), sourceBefore);
        }
      },
    );

    test(
      'isolates sequential A and B overrides and passes invalid JSON values',
      () {
        final source = _canonicalDocument();
        final sourceBefore = jsonEncode(source);
        final a = applyReportTemplateStyleOverrides(
          document: source,
          overrides: ReportTemplateStyleOverrides(
            color: <String, Object?>{'primary': 'NOT_A_HEX'},
            font: <String, Object?>{'family': 'UnknownFont', 'size_md': -3},
          ),
        );
        final b = applyReportTemplateStyleOverrides(
          document: source,
          overrides: ReportTemplateStyleOverrides(
            color: <String, Object?>{'primary': '#B'},
            font: <String, Object?>{'size_md': 7.5},
          ),
        );

        expect(
          a['styleTokens'],
          containsPair('color', containsPair('primary', 'NOT_A_HEX')),
        );
        expect(
          a['styleTokens'],
          containsPair('font', containsPair('family', 'UnknownFont')),
        );
        expect(
          a['styleTokens'],
          containsPair('font', containsPair('size_md', -3)),
        );
        expect(
          b['styleTokens'],
          containsPair('color', containsPair('primary', '#B')),
        );
        expect(
          b['styleTokens'],
          containsPair('font', containsPair('size_md', 7.5)),
        );
        expect(
          b['styleTokens'],
          containsPair('font', containsPair('family', 'Cairo')),
        );
        expect(jsonEncode(source), sourceBefore);
      },
    );
  });
}

Map<String, dynamic> _canonicalDocument() => <String, dynamic>{
  'schemaVersion': '1.0.0',
  'meta': <String, dynamic>{'name': 'Canonical', 'version': 1},
  'page': <String, dynamic>{'size': 'A4', 'width': 210, 'height': 297},
  'styleTokens': <String, dynamic>{
    'color': <String, dynamic>{
      'primary': '#145A9E',
      'table_header_bg': '#E8EEF5',
    },
    'font': <String, dynamic>{
      'family': 'Cairo',
      'weight_regular': '400',
      'weight_bold': '700',
    },
    'spacing': <String, dynamic>{'md': 8},
    'border': <String, dynamic>{'width': 1},
    'radius': <String, dynamic>{'md': 4},
    'system': <String, dynamic>{'brand': 'canonical'},
  },
  'assets': <dynamic>[],
  'layers': <dynamic>[
    <String, dynamic>{
      'id': 'main',
      'elementIds': <String>['text-1'],
    },
  ],
  'elements': <dynamic>[
    <String, dynamic>{
      'id': 'text-1',
      'type': 'text',
      'style': <String, dynamic>{
        'text': <String, dynamic>{'color': '#112233'},
      },
    },
  ],
};
