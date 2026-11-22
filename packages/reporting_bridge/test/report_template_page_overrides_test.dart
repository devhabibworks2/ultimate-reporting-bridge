import 'dart:convert';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

Map<String, dynamic> document({
  String layout = 'Pages',
  String size = 'A4',
  double width = 210,
  double height = 297,
  String direction = 'ltr',
}) => <String, dynamic>{
  'schemaVersion': '1.0.2',
  'page': <String, dynamic>{
    'layout': layout,
    'size': size,
    'unit': 'mm',
    'width': width,
    'height': height,
    'orientation': 'portrait',
    'direction': direction,
    'language': 'en',
    'margins': <String, num>{'top': 10, 'right': 10, 'bottom': 10, 'left': 10},
  },
  'styleTokens': <String, dynamic>{
    'color': <String, dynamic>{'primary': '#000000'},
  },
  'elements': <Map<String, dynamic>>[],
};

void main() {
  test('empty overrides preserve canonical document untouched', () {
    final original = document();
    expect(
      applyReportTemplatePageOverrides(
        document: original,
        overrides: const ReportTemplatePageOverrides(),
      ),
      same(original),
    );
  });

  test('A4 landscape derives dimensions, preserves source and other keys', () {
    final original = document();
    final snapshot = jsonEncode(original);
    final output = applyReportTemplatePageOverrides(
      document: original,
      overrides: const ReportTemplatePageOverrides(
        layout: BridgePageLayout.pages,
        size: BridgePageSize.a4,
        orientation: BridgePageOrientation.landscape,
        direction: BridgePageDirection.rtl,
      ),
    );
    expect((output['page'] as Map)['width'], 297);
    expect((output['page'] as Map)['height'], 210);
    expect((output['page'] as Map)['direction'], 'rtl');
    expect((output['page'] as Map)['language'], 'en');
    expect((output['styleTokens'] as Map)['color'], {'primary': '#000000'});
    expect(jsonEncode(original), snapshot);
  });

  test('only direction changes direction, not UI locale or dimensions', () {
    final output = applyReportTemplatePageOverrides(
      document: document(),
      overrides: const ReportTemplatePageOverrides(
        direction: BridgePageDirection.rtl,
      ),
    );
    final page = output['page'] as Map;
    expect(page['width'], 210);
    expect(page['height'], 297);
    expect(page['direction'], 'rtl');
    expect(page['language'], 'en');
  });

  test(
    'direction-only does not normalize irregular legacy page dimensions',
    () {
      final original = document(width: 208, height: 295);
      final result = applyReportTemplatePageOverrides(
        document: original,
        overrides: const ReportTemplatePageOverrides(
          direction: BridgePageDirection.rtl,
        ),
      );
      expect((result['page'] as Map)['width'], 208);
      expect((result['page'] as Map)['height'], 295);
      expect((original['page'] as Map)['direction'], 'ltr');
    },
  );

  test('Pages custom dimensions accepted', () {
    final output = applyReportTemplatePageOverrides(
      document: document(),
      overrides: const ReportTemplatePageOverrides(
        size: BridgePageSize.custom,
        widthMm: 105,
        heightMm: 148,
      ),
    );
    final page = output['page'] as Map;
    expect(page['size'], 'custom');
    expect(page['width'], 105);
    expect(page['height'], 148);
  });

  test('explicit dimension mismatch with named size rejects', () {
    expect(
      () => applyReportTemplatePageOverrides(
        document: document(),
        overrides: const ReportTemplatePageOverrides(
          size: BridgePageSize.a4,
          widthMm: 105,
        ),
      ),
      throwsA(
        isA<BridgeRuntimeException>().having(
          (x) => x.message,
          'message',
          contains('page.width'),
        ),
      ),
    );
  });

  test('custom size may override width alone and preserve template height', () {
    final result = applyReportTemplatePageOverrides(
      document: document(),
      overrides: const ReportTemplatePageOverrides(
        size: BridgePageSize.custom,
        widthMm: 105,
      ),
    );
    final page = result['page'] as Map;
    expect(page['size'], 'custom');
    expect(page['width'], 105);
    expect(page['height'], 297);
  });

  test('width and height imply custom when no named preset requested', () {
    final result = applyReportTemplatePageOverrides(
      document: document(),
      overrides: const ReportTemplatePageOverrides(widthMm: 100, heightMm: 150),
    );
    expect((result['page'] as Map)['size'], 'custom');
  });

  test('thermal width is fixed and height remains compatibility metadata', () {
    final original = document(
      layout: 'Thermal',
      size: '80mm',
      width: 80,
      height: 1000,
    );
    final result = applyReportTemplatePageOverrides(
      document: original,
      overrides: const ReportTemplatePageOverrides(
        direction: BridgePageDirection.rtl,
      ),
    );
    expect((result['page'] as Map)['height'], 1000);
    expect((result['page'] as Map)['width'], 80);
  });

  test(
    'thermal rejects explicit physical height, landscape and custom widths',
    () {
      final original = document(
        layout: 'Thermal',
        size: '80mm',
        width: 80,
        height: 1000,
      );
      for (final value in [
        const ReportTemplatePageOverrides(heightMm: 150),
        const ReportTemplatePageOverrides(
          orientation: BridgePageOrientation.landscape,
        ),
        const ReportTemplatePageOverrides(
          layout: BridgePageLayout.thermal,
          size: BridgePageSize.custom,
          widthMm: 72,
          heightMm: 1000,
        ),
      ]) {
        expect(
          () => applyReportTemplatePageOverrides(
            document: original,
            overrides: value,
          ),
          throwsA(isA<BridgeRuntimeException>()),
        );
      }
    },
  );

  test(
    'Pages-only override derives A4 rather than inheriting Thermal height',
    () {
      final original = document(
        layout: 'Thermal',
        size: '80mm',
        width: 80,
        height: 1000,
      );
      final snapshot = jsonEncode(original);
      final result = applyReportTemplatePageOverrides(
        document: original,
        overrides: const ReportTemplatePageOverrides(
          layout: BridgePageLayout.pages,
        ),
      );
      final page = result['page'] as Map;
      expect(page['layout'], 'Pages');
      expect(page['size'], 'A4');
      expect(page['width'], 210);
      expect(page['height'], 297);
      expect(jsonEncode(original), snapshot);
    },
  );

  test('impossible margins reject without editing caller-owned document', () {
    final original = document();
    final snapshot = jsonEncode(original);
    expect(
      () => applyReportTemplatePageOverrides(
        document: original,
        overrides: const ReportTemplatePageOverrides(
          size: BridgePageSize.custom,
          widthMm: 15,
          heightMm: 15,
        ),
      ),
      throwsA(isA<BridgeRuntimeException>()),
    );
    expect(jsonEncode(original), snapshot);
  });
}
