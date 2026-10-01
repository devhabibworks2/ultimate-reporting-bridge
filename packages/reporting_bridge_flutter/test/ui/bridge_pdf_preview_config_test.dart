import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  test('defaults and partial overrides resolve correctly', () {
    const defaults = BridgePdfPreviewConfig();
    expect(defaults.minScale, 0.6);
    expect(defaults.maxScale, 8.0);
    expect(defaults.initialScale, 0.8);

    const partial = BridgePdfPreviewConfig(maxScale: 4.0);
    expect(partial.minScale, 0.6);
    expect(partial.maxScale, 4.0);
    expect(partial.initialScale, 0.8);

    const ui = BridgeUiConfig.inheritHost(pdfPreview: partial);
    expect(ui.pdfPreview.minScale, 0.6);
    expect(ui.pdfPreview.maxScale, 4.0);
    expect(ui.pdfPreview.initialScale, 0.8);

    const brand = BridgeUiConfig.brand(
      seedColor: Color(0xFF29AD5F),
      pdfPreview: partial,
    );
    expect(brand.pdfPreview.maxScale, 4.0);

    final custom = BridgeUiConfig.custom(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF123456)),
      pdfPreview: partial,
    );
    expect(custom.pdfPreview.maxScale, 4.0);
  });

  test('rejects invalid numeric and range values', () {
    expect(() => BridgePdfPreviewConfig(minScale: 0), throwsAssertionError);
    expect(() => BridgePdfPreviewConfig(minScale: -0.1), throwsAssertionError);
    expect(
      () => BridgePdfPreviewConfig(minScale: double.nan),
      throwsAssertionError,
    );
    expect(
      () => BridgePdfPreviewConfig(maxScale: double.infinity),
      throwsAssertionError,
    );
    expect(
      () => BridgePdfPreviewConfig(minScale: 1.0, maxScale: 0.9),
      throwsAssertionError,
    );
    expect(
      () => BridgePdfPreviewConfig(initialScale: 0.5),
      throwsAssertionError,
    );
    expect(
      () => BridgePdfPreviewConfig(initialScale: 8.1),
      throwsAssertionError,
    );
  });
}
