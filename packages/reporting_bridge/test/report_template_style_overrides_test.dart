import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('ReportTemplateStyleOverrides', () {
    test('defaults to immutable empty color and font groups', () {
      final overrides = ReportTemplateStyleOverrides();

      expect(overrides.color, isEmpty);
      expect(overrides.font, isEmpty);
      expect(overrides.isEmpty, isTrue);
      expect(
        () => overrides.color['primary'] = '#000000',
        throwsUnsupportedError,
      );
      expect(() => overrides.font['family'] = 'Cairo', throwsUnsupportedError);
    });

    test('isEmpty is false when either group contains an override', () {
      expect(
        ReportTemplateStyleOverrides(
          color: <String, Object?>{'primary': 1},
        ).isEmpty,
        isFalse,
      );
      expect(
        ReportTemplateStyleOverrides(
          font: <String, Object?>{'family': 'X'},
        ).isEmpty,
        isFalse,
      );
    });

    test('passes through semantically unknown JSON values unchanged', () {
      final overrides = ReportTemplateStyleOverrides(
        color: <String, Object?>{
          'primary': 'NOT_A_HEX',
          'future_color_leaf': 12,
        },
        font: <String, Object?>{
          'family': 'UnknownFont',
          'size_md': -3,
          'fractional_a': 7.5,
          'fractional_b': 9.5,
        },
      );

      expect(overrides.color, <String, Object?>{
        'primary': 'NOT_A_HEX',
        'future_color_leaf': 12,
      });
      expect(overrides.font, <String, Object?>{
        'family': 'UnknownFont',
        'size_md': -3,
        'fractional_a': 7.5,
        'fractional_b': 9.5,
      });
    });

    test('snapshots caller maps and nested JSON values immutably', () {
      final nested = <String, Object?>{
        'values': <Object?>[1, 'two'],
      };
      final color = <String, Object?>{'custom': nested};
      final overrides = ReportTemplateStyleOverrides(color: color);

      nested['values'] = <Object?>['mutated'];
      color['later'] = true;

      expect(overrides.color, <String, Object?>{
        'custom': <String, Object?>{
          'values': <Object?>[1, 'two'],
        },
      });
      expect(
        () => (overrides.color['custom'] as Map<String, Object?>)['x'] = 1,
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((overrides.color['custom'] as Map<String, Object?>)['values']
                    as List<Object?>)[0] =
                4,
        throwsUnsupportedError,
      );
    });
  });
}
