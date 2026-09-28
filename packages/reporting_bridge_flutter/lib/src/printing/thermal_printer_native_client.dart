import '../platform/generated/thermal_printer_api.g.dart';
import 'thermal_printer_models.dart';

abstract interface class ThermalPrinterNativeClient {
  Future<ThermalPrinterPermissionState> bluetoothPermissionState();
  Future<ThermalPrinterPermissionState> requestBluetoothPermissions();
  Future<ThermalPrinterPermissionState> usbPermission(
    ThermalPrinterDevice device,
  );
  Future<ThermalPrinterPermissionState> requestUsbPermission(
    ThermalPrinterDevice device,
  );
  Future<List<ThermalPrinterDevice>> listPairedBluetoothDevices();
  Future<List<ThermalPrinterDevice>> listConnectedUsbPrinters();
  Future<ThermalPrintOperationResult> printPdf({
    required String jobId,
    required String pdfPath,
    required ThermalPrinterProfile profile,
  });
  void setProgressListener(void Function(ThermalPrintProgress progress)? value);
  void dispose();
}

final class PigeonThermalPrinterNativeClient
    implements ThermalPrinterNativeClient, ThermalPrinterFlutterApi {
  PigeonThermalPrinterNativeClient() {
    ThermalPrinterFlutterApi.setUp(this);
  }

  final _permissions = ThermalPrinterPermissionHostApi();
  final _printer = ThermalPrinterHostApi();
  void Function(ThermalPrintProgress progress)? _onProgress;

  @override
  Future<ThermalPrinterPermissionState> bluetoothPermissionState() async =>
      _permission(await _permissions.getBluetoothPermissionState());

  @override
  Future<ThermalPrinterPermissionState> requestBluetoothPermissions() async =>
      _permission(await _permissions.requestBluetoothPermissions());

  @override
  Future<ThermalPrinterPermissionState> requestUsbPermission(
    ThermalPrinterDevice device,
  ) async =>
      _permission(await _permissions.requestUsbPermission(_device(device)));

  @override
  Future<ThermalPrinterPermissionState> usbPermission(
    ThermalPrinterDevice device,
  ) async => _permission(await _permissions.hasUsbPermission(_device(device)));

  @override
  Future<List<ThermalPrinterDevice>> listConnectedUsbPrinters() async =>
      (await _printer.listConnectedUsbPrinters()).map(_fromDevice).toList();

  @override
  Future<List<ThermalPrinterDevice>> listPairedBluetoothDevices() async =>
      (await _printer.listPairedBluetoothDevices()).map(_fromDevice).toList();

  @override
  Future<ThermalPrintOperationResult> printPdf({
    required String jobId,
    required String pdfPath,
    required ThermalPrinterProfile profile,
  }) async {
    final result = await _printer.printPdf(
      ThermalPigeonPrintRequest(
        jobId: jobId,
        pdfPath: pdfPath,
        profile: _profile(profile),
      ),
    );
    return ThermalPrintOperationResult(
      status: ThermalPrintResultStatus.values.byName(result.status.name),
      errorCode: result.errorCode,
      diagnostic: result.diagnostic,
    );
  }

  @override
  void onPrintProgress(ThermalPigeonProgress progress) {
    _onProgress?.call(
      ThermalPrintProgress(
        jobId: progress.jobId,
        phase: ThermalPrintPhase.values.byName(progress.phase.name),
        copyIndex: progress.copyIndex,
        copyCount: progress.copyCount,
        pageIndex: progress.pageIndex,
        pageCount: progress.pageCount,
        bytesSent: progress.bytesSent,
        totalBytes: progress.totalBytes,
      ),
    );
  }

  @override
  void setProgressListener(
    void Function(ThermalPrintProgress progress)? value,
  ) {
    _onProgress = value;
  }

  @override
  void dispose() {
    _onProgress = null;
    ThermalPrinterFlutterApi.setUp(null);
  }
}

ThermalPrinterPermissionState _permission(ThermalPigeonPermissionState value) =>
    ThermalPrinterPermissionState.values.byName(value.name);

ThermalPigeonDevice _device(ThermalPrinterDevice value) => ThermalPigeonDevice(
  id: value.id,
  connectionType: ThermalPigeonConnectionType.values.byName(
    value.connectionType.name,
  ),
  displayName: value.displayName,
  address: value.address,
  vendorId: value.vendorId,
  productId: value.productId,
  serialNumber: value.serialNumber,
  deviceName: value.deviceName,
  preferred: value.preferred,
);

ThermalPrinterDevice _fromDevice(ThermalPigeonDevice value) =>
    ThermalPrinterDevice(
      id: value.id,
      connectionType: ThermalPrinterConnectionType.values.byName(
        value.connectionType.name,
      ),
      displayName: value.displayName,
      address: value.address,
      vendorId: value.vendorId,
      productId: value.productId,
      serialNumber: value.serialNumber,
      deviceName: value.deviceName,
      preferred: value.preferred,
    );

ThermalPigeonProfile _profile(ThermalPrinterProfile value) =>
    ThermalPigeonProfile(
      displayName: value.displayName,
      connectionType: ThermalPigeonConnectionType.values.byName(
        value.connectionType.name,
      ),
      printableWidthPx: value.printableWidthPx,
      bluetoothAddress: value.bluetoothAddress,
      usbVendorId: value.usbVendorId,
      usbProductId: value.usbProductId,
      usbSerialNumber: value.usbSerialNumber,
      usbDeviceName: value.usbDeviceName,
      tcpHost: value.tcpHost,
      tcpPort: value.tcpPort,
      tcpTimeoutSeconds: value.tcpTimeoutSeconds,
      copies: value.copies,
      gradient: value.gradient,
      feedDots: value.feedDots,
      cutAfterPrint: value.cutAfterPrint,
      useEscAsteriskCommand: value.useEscAsteriskCommand,
    );
