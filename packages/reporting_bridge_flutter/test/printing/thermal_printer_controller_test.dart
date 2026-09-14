import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:reporting_bridge_flutter/src/persistence/thermal_printer_settings_store.dart';
import 'package:reporting_bridge_flutter/src/printing/thermal_printer_native_client.dart';
import 'package:reporting_bridge_flutter/src/printing/thermal_report_print_platform.dart';

void main() {
  const profile = ThermalPrinterProfile(
    displayName: 'PR3-680AE24E223A',
    connectionType: ThermalPrinterConnectionType.bluetooth,
    bluetoothAddress: '68:0A:E2:4E:22:3A',
    printableWidthPx: ThermalPrinterProfile.width80mm,
  );
  const device = ThermalPrinterDevice(
    id: '68:0A:E2:4E:22:3A',
    connectionType: ThermalPrinterConnectionType.bluetooth,
    displayName: 'PR3-680AE24E223A',
    address: '68:0A:E2:4E:22:3A',
  );

  test(
    'retains a saved Bluetooth profile when it is no longer paired',
    () async {
      final store = MemoryThermalPrinterSettingsStore()..profile = profile;
      final native = _NativeClient(devices: <ThermalPrinterDevice>[device]);
      final sink = _AvailabilitySink();
      final testPlatform = _TestPlatform();
      final controller = ThermalPrinterSettingsController(
        settingsStore: store,
        nativeClient: native,
        availabilitySink: sink,
        testPlatform: testPlatform,
      );

      await controller.load();
      expect(
        controller.value.savedBluetoothAvailability,
        ThermalPrinterAvailability.available,
      );

      native.devices = const <ThermalPrinterDevice>[];
      await controller.refreshBluetoothDevices();

      expect(controller.value.profile, profile);
      expect(
        controller.value.savedBluetoothAvailability,
        ThermalPrinterAvailability.unavailable,
      );
      expect(sink.profile, profile);
      expect(sink.availability, ThermalPrinterAvailability.unavailable);
      controller.dispose();
    },
  );

  test(
    'loads a TCP profile without replacing it with Bluetooth state',
    () async {
      const tcpProfile = ThermalPrinterProfile(
        displayName: 'Epson TCP',
        connectionType: ThermalPrinterConnectionType.tcp,
        printableWidthPx: ThermalPrinterProfile.width80mm,
        tcpHost: '192.168.1.80',
        tcpPort: 9100,
        feedDots: 20,
      );
      final store = MemoryThermalPrinterSettingsStore()..profile = tcpProfile;
      final native = _NativeClient(devices: const <ThermalPrinterDevice>[]);
      final controller = ThermalPrinterSettingsController(
        settingsStore: store,
        nativeClient: native,
        availabilitySink: _AvailabilitySink(),
        testPlatform: _TestPlatform(),
      );

      await controller.ensureLoaded();

      expect(controller.value.initialized, isTrue);
      expect(controller.value.profile, tcpProfile);
      expect(native.bluetoothStateCalls, 0);
      controller.dispose();
    },
  );
}

final class _TestPlatform implements ThermalPrinterTestPlatform {
  @override
  Future<ReportPrintResult> testPrint(ThermalPrinterProfile profile) async =>
      const ReportPrintResult.submitted();
}

final class _AvailabilitySink implements ThermalBluetoothAvailabilitySink {
  ThermalPrinterProfile? profile;
  ThermalPrinterAvailability availability = ThermalPrinterAvailability.unknown;

  @override
  void setKnownBluetoothAvailability(
    ThermalPrinterProfile? value,
    ThermalPrinterAvailability next,
  ) {
    profile = value;
    availability = next;
  }
}

final class _NativeClient implements ThermalPrinterNativeClient {
  _NativeClient({required this.devices});

  List<ThermalPrinterDevice> devices;
  int bluetoothStateCalls = 0;

  @override
  Future<ThermalPrinterPermissionState> bluetoothPermissionState() async {
    bluetoothStateCalls++;
    return ThermalPrinterPermissionState.granted;
  }

  @override
  void dispose() {}

  @override
  Future<List<ThermalPrinterDevice>> listConnectedUsbPrinters() async =>
      const <ThermalPrinterDevice>[];

  @override
  Future<List<ThermalPrinterDevice>> listPairedBluetoothDevices() async =>
      devices;

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
