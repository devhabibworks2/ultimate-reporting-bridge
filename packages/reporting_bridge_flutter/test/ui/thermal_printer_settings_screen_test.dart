import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:reporting_bridge_flutter/src/persistence/thermal_printer_settings_store.dart';
import 'package:reporting_bridge_flutter/src/printing/thermal_printer_native_client.dart';
import 'package:reporting_bridge_flutter/src/printing/thermal_report_print_platform.dart';
import 'package:reporting_bridge_flutter/src/ui/thermal_printer_settings_screen.dart';

void main() {
  testWidgets('restores a saved TCP profile into the settings form', (
    tester,
  ) async {
    const profile = ThermalPrinterProfile(
      displayName: 'Epson network printer',
      connectionType: ThermalPrinterConnectionType.tcp,
      printableWidthPx: ThermalPrinterProfile.width80mm,
      tcpHost: '192.168.1.80',
      tcpPort: 9100,
      tcpTimeoutSeconds: 30,
      feedDots: 37,
    );
    final controller = ThermalPrinterSettingsController(
      settingsStore: MemoryThermalPrinterSettingsStore()..profile = profile,
      nativeClient: _NativeClient(),
      availabilitySink: _AvailabilitySink(),
      testPlatform: _TestPlatform(),
    );
    await controller.ensureLoaded();

    await tester.pumpWidget(
      MaterialApp(home: ThermalPrinterSettingsScreen(controller: controller)),
    );
    await tester.pump();

    expect(find.text('TCP / Network'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextFormField &&
            widget.controller?.text == '192.168.1.80',
      ),
      findsOneWidget,
    );
    controller.dispose();
  });
}

final class _NativeClient implements ThermalPrinterNativeClient {
  @override
  Future<ThermalPrinterPermissionState> bluetoothPermissionState() async =>
      ThermalPrinterPermissionState.granted;

  @override
  void dispose() {}

  @override
  Future<List<ThermalPrinterDevice>> listConnectedUsbPrinters() async =>
      const <ThermalPrinterDevice>[];

  @override
  Future<List<ThermalPrinterDevice>> listPairedBluetoothDevices() async =>
      const <ThermalPrinterDevice>[];

  @override
  Future<ThermalPrintOperationResult> printPdf({
    required String jobId,
    required String pdfPath,
    required ThermalPrinterProfile profile,
  }) async => const ThermalPrintOperationResult(
    status: ThermalPrintResultStatus.submitted,
  );

  @override
  Future<ThermalPrinterPermissionState> requestBluetoothPermissions() async =>
      ThermalPrinterPermissionState.granted;

  @override
  Future<ThermalPrinterPermissionState> requestUsbPermission(
    ThermalPrinterDevice device,
  ) async => ThermalPrinterPermissionState.granted;

  @override
  void setProgressListener(
    void Function(ThermalPrintProgress progress)? value,
  ) {}

  @override
  Future<ThermalPrinterPermissionState> usbPermission(
    ThermalPrinterDevice device,
  ) async => ThermalPrinterPermissionState.granted;
}

final class _AvailabilitySink implements ThermalBluetoothAvailabilitySink {
  @override
  void setKnownBluetoothAvailability(
    ThermalPrinterProfile? profile,
    ThermalPrinterAvailability availability,
  ) {}
}

final class _TestPlatform implements ThermalPrinterTestPlatform {
  @override
  Future<ReportPrintResult> testPrint(ThermalPrinterProfile profile) async =>
      const ReportPrintResult.submitted();
}
