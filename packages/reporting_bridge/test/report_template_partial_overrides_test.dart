import 'dart:convert';
import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

Map<String, dynamic> fixture({
  String layout = 'Pages',
  String size = 'A4',
  double width = 210,
  double height = 297,
}) => {
  'schemaVersion': '1.0.2',
  'page': {
    'layout': layout,
    'size': size,
    'unit': 'mm',
    'width': width,
    'height': height,
    'orientation': 'portrait',
    'direction': 'ltr',
    'language': 'en',
    'margins': {'top': 10, 'right': 10, 'bottom': 10, 'left': 10},
  },
  'elements': <Map<String, dynamic>>[],
};
Map<String, dynamic> page(
  Map<String, dynamic> doc,
  ReportTemplatePageOverrides changes,
) =>
    applyReportTemplatePageOverrides(document: doc, overrides: changes)['page']
        as Map<String, dynamic>;

void main() {
  test('one field: layout Pages converts Thermal source', () {
    final original = fixture(
      layout: 'Thermal',
      size: '80mm',
      width: 80,
      height: 1000,
    );
    final before = jsonEncode(original);
    final p = page(
      original,
      const ReportTemplatePageOverrides(layout: BridgePageLayout.pages),
    );
    expect(
      [p['layout'], p['size'], p['width'], p['height'], p['orientation']],
      ['Pages', 'A4', 210, 297, 'portrait'],
    );
    expect(jsonEncode(original), before);
  });
  test('one field: layout Thermal derives compatible defaults', () {
    final p = page(
      fixture(),
      const ReportTemplatePageOverrides(layout: BridgePageLayout.thermal),
    );
    expect(
      [p['layout'], p['size'], p['orientation'], p['width']],
      ['Thermal', '80mm', 'portrait', 80],
    );
  });
  test('one field: A5 size switches Thermal to Pages', () {
    final p = page(
      fixture(layout: 'Thermal', size: '80mm', width: 80, height: 1000),
      const ReportTemplatePageOverrides(size: BridgePageSize.a5),
    );
    expect([p['layout'], p['width'], p['height']], ['Pages', 148, 210]);
  });
  test('one field: thermal58 size derives Thermal layout', () {
    final p = page(
      fixture(),
      const ReportTemplatePageOverrides(size: BridgePageSize.thermal58),
    );
    expect([p['layout'], p['size'], p['width']], ['Thermal', '58mm', 58]);
  });
  test('one field: custom size inherits existing Pages dimensions', () {
    final p = page(
      fixture(),
      const ReportTemplatePageOverrides(size: BridgePageSize.custom),
    );
    expect([p['size'], p['width'], p['height']], ['custom', 210, 297]);
  });
  test('one field: width changes only width and yields custom size', () {
    final p = page(fixture(), const ReportTemplatePageOverrides(widthMm: 180));
    expect([p['size'], p['width'], p['height']], ['custom', 180, 297]);
  });
  test('one field: height changes only height and yields custom size', () {
    final p = page(fixture(), const ReportTemplatePageOverrides(heightMm: 320));
    expect([p['size'], p['width'], p['height']], ['custom', 210, 320]);
  });
  test('one field: custom Pages width preserves existing height', () {
    final p = page(
      fixture(size: 'custom', width: 100, height: 200),
      const ReportTemplatePageOverrides(widthMm: 110),
    );
    expect([p['width'], p['height']], [110, 200]);
  });
  test('two fields: orientation and direction work independently', () {
    final p = page(
      fixture(),
      const ReportTemplatePageOverrides(
        orientation: BridgePageOrientation.landscape,
        direction: BridgePageDirection.rtl,
      ),
    );
    expect(
      [p['layout'], p['size'], p['width'], p['height'], p['direction']],
      ['Pages', 'A4', 297, 210, 'rtl'],
    );
  });
  test('orientation-only rotates existing custom physical dimensions', () {
    final p = page(
      fixture(size: 'custom', width: 100, height: 200),
      const ReportTemplatePageOverrides(
        orientation: BridgePageOrientation.landscape,
      ),
    );
    expect(
      [p['width'], p['height'], p['orientation']],
      [200, 100, 'landscape'],
    );
  });
  test('width-only that changes aspect ratio derives landscape', () {
    final p = page(fixture(), const ReportTemplatePageOverrides(widthMm: 400));
    expect(
      [p['size'], p['width'], p['height'], p['orientation']],
      ['custom', 400, 297, 'landscape'],
    );
  });
  test('explicitly contradictory layout and size fail', () {
    expect(
      () => page(
        fixture(),
        const ReportTemplatePageOverrides(
          layout: BridgePageLayout.thermal,
          size: BridgePageSize.a4,
        ),
      ),
      throwsA(isA<BridgeRuntimeException>()),
    );
  });
  test('Thermal fixed height still unsupported', () {
    expect(
      () => page(
        fixture(layout: 'Thermal', size: '80mm', width: 80, height: 1000),
        const ReportTemplatePageOverrides(heightMm: 350),
      ),
      throwsA(isA<BridgeRuntimeException>()),
    );
  });
}
