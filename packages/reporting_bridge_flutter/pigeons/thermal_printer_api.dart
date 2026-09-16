import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/platform/generated/thermal_printer_api.g.dart',
    dartOptions: DartOptions(),
    javaOut:
        'android/src/main/java/com/ultimate/reportbuilder/reporting_bridge_flutter/ThermalPrinterApi.java',
    javaOptions: JavaOptions(
      package: 'com.ultimate.reportbuilder.reporting_bridge_flutter',
    ),
    dartPackageName: 'reporting_bridge_flutter',
  ),
)
// ignore: unused_element
class _Config {
  late String sentinel;
}

enum ThermalPigeonConnectionType { bluetooth, usb, tcp }

enum ThermalPigeonPermissionState {
  granted,
  denied,
  permanentlyDenied,
  activityUnavailable,
  unsupported,
}

enum ThermalPigeonResultStatus {
  submitted,
  setupRequired,
  permissionDenied,
  deviceUnavailable,
  connectionFailed,
  invalidRequest,
  invalidPdf,
  rasterizationFailed,
  busy,
  nativeFailure,
}

enum ThermalPigeonProgressPhase {
  preparing,
  connecting,
  rasterizing,
  transmitting,
  printing,
}

class ThermalPigeonDevice {
  late String id;
  late ThermalPigeonConnectionType connectionType;
  late String displayName;
  String? address;
  int? vendorId;
  int? productId;
  String? serialNumber;
  String? deviceName;
  late bool preferred;
}

class ThermalPigeonProfile {
  late String displayName;
  late ThermalPigeonConnectionType connectionType;
  late int printableWidthPx;
  String? bluetoothAddress;
  int? usbVendorId;
  int? usbProductId;
  String? usbSerialNumber;
  String? usbDeviceName;
  String? tcpHost;
  int? tcpPort;
  late int tcpTimeoutSeconds;
  late int copies;
  late bool gradient;
  late int feedDots;
  late bool cutAfterPrint;
  late bool useEscAsteriskCommand;
}

class ThermalPigeonPrintRequest {
  late String jobId;
  late String pdfPath;
  late ThermalPigeonProfile profile;
}

class ThermalPigeonResult {
  late ThermalPigeonResultStatus status;
  String? errorCode;
  String? diagnostic;
}

class ThermalPigeonProgress {
  late String jobId;
  late ThermalPigeonProgressPhase phase;
  int? copyIndex;
  int? copyCount;
  int? pageIndex;
  int? pageCount;
  int? bytesSent;
  int? totalBytes;
}

@HostApi()
abstract class ThermalPrinterPermissionHostApi {
  @async
  ThermalPigeonPermissionState getBluetoothPermissionState();

  @async
  ThermalPigeonPermissionState requestBluetoothPermissions();

  @async
  ThermalPigeonPermissionState hasUsbPermission(ThermalPigeonDevice device);

  @async
  ThermalPigeonPermissionState requestUsbPermission(ThermalPigeonDevice device);
}

@HostApi()
abstract class ThermalPrinterHostApi {
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  @async
  List<ThermalPigeonDevice> listPairedBluetoothDevices();

  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  @async
  List<ThermalPigeonDevice> listConnectedUsbPrinters();

  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  @async
  ThermalPigeonResult printPdf(ThermalPigeonPrintRequest request);
}

@FlutterApi()
abstract class ThermalPrinterFlutterApi {
  void onPrintProgress(ThermalPigeonProgress progress);
}
