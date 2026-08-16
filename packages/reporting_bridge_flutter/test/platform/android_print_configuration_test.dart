import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/src/contracts/external_printer_contract.dart';
import 'package:reporting_bridge_flutter/src/platform/android_print_configuration.dart';

void main() {
  test('external mode defaults to contract package/action/MIME', () {
    final configuration = AndroidExternalPrinterConfiguration(
      installUri: Uri.parse('https://example.test/printer'),
    );

    expect(configuration.packageName, ultimatePrinterPackageName);
    expect(configuration.action, ultimatePrinterAction);
    expect(configuration.mimeType, ultimatePrinterMimeType);
    expect(configuration.contractVersion, ultimatePrinterContractVersion);
  });

  test('rejects non-V1 package or action overrides', () {
    expect(
      () => AndroidExternalPrinterConfiguration(
        installUri: Uri.parse('https://example.test/printer'),
        packageName: 'com.other.Printer',
      ),
      throwsArgumentError,
    );
    expect(
      () => AndroidExternalPrinterConfiguration(
        installUri: Uri.parse('https://example.test/printer'),
        action: 'com.Ultimate.Printer.PRINT_OTHER',
      ),
      throwsArgumentError,
    );
  });

  test('system print manager mode remains available', () {
    const configuration = AndroidPrintConfiguration.systemPrintManager();
    expect(configuration.mode, AndroidPrintMode.systemPrintManager);
    expect(configuration.externalApp, isNull);
  });
}
