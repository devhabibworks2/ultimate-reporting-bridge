package com.ultimate.reportbuilder.reporting_bridge_flutter;

import android.annotation.SuppressLint;
import android.bluetooth.BluetoothDevice;
import android.content.Context;
import android.hardware.usb.UsbDevice;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import com.dantsu.escposprinter.connection.DeviceConnection;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

import io.flutter.plugin.common.BinaryMessenger;

/** Pigeon implementation and the single native thermal print job gate. */
final class ThermalPrinterApiHandler implements
    ThermalPrinterApi.ThermalPrinterPermissionHostApi,
    ThermalPrinterApi.ThermalPrinterHostApi {
  private static final long MAXIMUM_PDF_BYTES = 50L * 1024L * 1024L;

  private final Context applicationContext;
  private final PrinterPermissionCoordinator permissions;
  private final DantSuConnectionFactory connections;
  private final ExecutorService executor = Executors.newSingleThreadExecutor();
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private final AtomicBoolean printing = new AtomicBoolean(false);
  private final ThermalPrinterApi.ThermalPrinterFlutterApi flutterApi;
  private BinaryMessenger messenger;

  ThermalPrinterApiHandler(@NonNull Context context, @NonNull BinaryMessenger messenger,
      @NonNull PrinterPermissionCoordinator permissions) {
    applicationContext = context.getApplicationContext();
    this.permissions = permissions;
    connections = new DantSuConnectionFactory(applicationContext);
    flutterApi = new ThermalPrinterApi.ThermalPrinterFlutterApi(messenger);
    this.messenger = messenger;
  }

  void setUp() {
    ThermalPrinterApi.ThermalPrinterPermissionHostApi.setUp(messenger, this);
    ThermalPrinterApi.ThermalPrinterHostApi.setUp(messenger, this);
  }

  void tearDown() {
    ThermalPrinterApi.ThermalPrinterPermissionHostApi.setUp(messenger, null);
    ThermalPrinterApi.ThermalPrinterHostApi.setUp(messenger, null);
    executor.shutdownNow();
    messenger = null;
  }

  @Override public void getBluetoothPermissionState(
      @NonNull ThermalPrinterApi.Result<ThermalPrinterApi.ThermalPigeonPermissionState> result) {
    result.success(permission(permissions.bluetoothState()));
  }

  @Override public void requestBluetoothPermissions(
      @NonNull ThermalPrinterApi.Result<ThermalPrinterApi.ThermalPigeonPermissionState> result) {
    permissions.requestBluetooth(state -> result.success(permission(state)));
  }

  @Override public void hasUsbPermission(@NonNull ThermalPrinterApi.ThermalPigeonDevice device,
      @NonNull ThermalPrinterApi.Result<ThermalPrinterApi.ThermalPigeonPermissionState> result) {
    final UsbDevice usbDevice = connections.findUsbDevice(device);
    result.success(usbDevice == null
        ? ThermalPrinterApi.ThermalPigeonPermissionState.DENIED
        : permission(permissions.usbState(usbDevice)));
  }

  @Override public void requestUsbPermission(@NonNull ThermalPrinterApi.ThermalPigeonDevice device,
      @NonNull ThermalPrinterApi.Result<ThermalPrinterApi.ThermalPigeonPermissionState> result) {
    final UsbDevice usbDevice = connections.findUsbDevice(device);
    if (usbDevice == null) {
      result.success(ThermalPrinterApi.ThermalPigeonPermissionState.DENIED);
      return;
    }
    permissions.requestUsb(usbDevice, state -> result.success(permission(state)));
  }

  @Override public void listPairedBluetoothDevices(
      @NonNull ThermalPrinterApi.Result<List<ThermalPrinterApi.ThermalPigeonDevice>> result) {
    executor.execute(() -> {
      try {
        final List<ThermalPrinterApi.ThermalPigeonDevice> devices = new ArrayList<>();
        for (BluetoothDevice device : connections.pairedBluetoothDevices()) {
          devices.add(bluetoothDevice(device));
        }
        result.success(devices);
      } catch (Throwable error) {
        result.error(error);
      }
    });
  }

  @Override public void listConnectedUsbPrinters(
      @NonNull ThermalPrinterApi.Result<List<ThermalPrinterApi.ThermalPigeonDevice>> result) {
    executor.execute(() -> {
      try {
        final List<ThermalPrinterApi.ThermalPigeonDevice> devices = new ArrayList<>();
        for (UsbDevice device : connections.connectedUsbDevices()) {
          devices.add(usbDevice(device));
        }
        result.success(devices);
      } catch (Throwable error) {
        result.error(error);
      }
    });
  }

  @Override public void printPdf(@NonNull ThermalPrinterApi.ThermalPigeonPrintRequest request,
      @NonNull ThermalPrinterApi.Result<ThermalPrinterApi.ThermalPigeonResult> result) {
    if (!printing.compareAndSet(false, true)) {
      result.success(printResult(ThermalPrinterApi.ThermalPigeonResultStatus.BUSY, "thermalBusy", null));
      return;
    }
    executor.execute(() -> {
      DeviceConnection connection = null;
      try {
        if (request.getProfile().getConnectionType()
            == ThermalPrinterApi.ThermalPigeonConnectionType.BLUETOOTH
            && permissions.bluetoothState() != PrinterPermissionCoordinator.State.GRANTED) {
          result.success(printResult(
              ThermalPrinterApi.ThermalPigeonResultStatus.PERMISSION_DENIED,
              "bluetoothPermissionDenied",
              "Bluetooth CONNECT and SCAN permission is required."));
          return;
        }
        final File pdf = validatedPdf(request.getPdfPath());
        emit(request.getJobId(), ThermalPrinterApi.ThermalPigeonProgressPhase.PREPARING, null, null, null, null);
        validateProfile(request.getProfile());
        emit(request.getJobId(), ThermalPrinterApi.ThermalPigeonProgressPhase.CONNECTING, null, null, null, null);
        connection = connections.create(request.getProfile());
        connection.connect();
        final ThermalPrinterApi.ThermalPigeonProfile profile = request.getProfile();
        PdfStripeRasterizer.print(
            pdf,
            connection,
            profile.getPrintableWidthPx().intValue(),
            profile.getCopies().intValue(),
            profile.getGradient(),
            profile.getFeedDots().intValue(),
            profile.getCutAfterPrint(),
            profile.getUseEscAsteriskCommand(),
            (copy, copies, page, pages) -> emit(
                request.getJobId(), ThermalPrinterApi.ThermalPigeonProgressPhase.PRINTING,
                (long) copy, (long) copies, (long) page, (long) pages));
        result.success(printResult(ThermalPrinterApi.ThermalPigeonResultStatus.SUBMITTED, null, null));
      } catch (Throwable error) {
        result.success(mapError(error, request.getProfile().getConnectionType()));
      } finally {
        if (connection != null) {
          try { connection.disconnect(); } catch (Throwable ignored) {}
        }
        printing.set(false);
      }
    });
  }

  private File validatedPdf(@NonNull String path) throws IOException {
    final File root = new File(applicationContext.getCacheDir(),
        "reporting_bridge_flutter/thermal_print_jobs").getCanonicalFile();
    final File pdf = new File(path).getCanonicalFile();
    final String rootPath = root.getPath() + File.separator;
    if (!pdf.getPath().startsWith(rootPath) || !pdf.isFile() || !pdf.canRead()) {
      throw new IOException("invalidPdfPath");
    }
    if (pdf.length() <= 0 || pdf.length() > MAXIMUM_PDF_BYTES) throw new IOException("invalidPdfSize");
    return pdf;
  }

  private void validateProfile(@NonNull ThermalPrinterApi.ThermalPigeonProfile profile)
      throws IOException {
    if (profile.getPrintableWidthPx() <= 0 || profile.getCopies() < 1 || profile.getCopies() > 9
        || profile.getFeedDots() < 0 || profile.getFeedDots() > 255) {
      throw new IOException("invalidPrinterConfiguration");
    }
  }

  private void emit(@NonNull String jobId,
      @NonNull ThermalPrinterApi.ThermalPigeonProgressPhase phase,
      Long copy, Long copies, Long page, Long pages) {
    final ThermalPrinterApi.ThermalPigeonProgress progress =
        new ThermalPrinterApi.ThermalPigeonProgress.Builder()
            .setJobId(jobId).setPhase(phase).setCopyIndex(copy).setCopyCount(copies)
            .setPageIndex(page).setPageCount(pages).build();
    mainHandler.post(() -> flutterApi.onPrintProgress(progress, new ThermalPrinterApi.VoidResult() {
      @Override public void success() {}
      @Override public void error(@NonNull Throwable error) {}
    }));
  }

  @SuppressLint("MissingPermission")
  private ThermalPrinterApi.ThermalPigeonDevice bluetoothDevice(@NonNull BluetoothDevice device) {
    final String name = connections.safeName(device);
    return new ThermalPrinterApi.ThermalPigeonDevice.Builder()
        .setId(device.getAddress()).setConnectionType(ThermalPrinterApi.ThermalPigeonConnectionType.BLUETOOTH)
        .setDisplayName(name).setAddress(device.getAddress()).setPreferred(connections.isLikelyPrinter(device))
        .build();
  }

  private ThermalPrinterApi.ThermalPigeonDevice usbDevice(@NonNull UsbDevice device) {
    String serial = null;
    try { serial = device.getSerialNumber(); } catch (SecurityException ignored) {}
    final String label = device.getProductName() == null ? device.getDeviceName() : device.getProductName();
    return new ThermalPrinterApi.ThermalPigeonDevice.Builder()
        .setId(device.getDeviceName()).setConnectionType(ThermalPrinterApi.ThermalPigeonConnectionType.USB)
        .setDisplayName(label).setVendorId((long) device.getVendorId()).setProductId((long) device.getProductId())
        .setSerialNumber(serial).setDeviceName(device.getDeviceName()).setPreferred(true).build();
  }

  private ThermalPrinterApi.ThermalPigeonResult mapError(
      @NonNull Throwable error,
      @NonNull ThermalPrinterApi.ThermalPigeonConnectionType connectionType) {
    final String message = error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage();
    final String lower = message.toLowerCase();
    if (lower.startsWith("tcpconnectiontimeout")) {
      return printResult(
          ThermalPrinterApi.ThermalPigeonResultStatus.CONNECTION_FAILED,
          "tcpConnectionTimeout",
          message);
    }
    if (lower.startsWith("tcphostnotfound")) {
      return printResult(
          ThermalPrinterApi.ThermalPigeonResultStatus.CONNECTION_FAILED,
          "tcpHostNotFound",
          message);
    }
    if (lower.startsWith("tcpconnectionrefused")) {
      return printResult(
          ThermalPrinterApi.ThermalPigeonResultStatus.CONNECTION_FAILED,
          "tcpConnectionRefused",
          message);
    }
    if (lower.startsWith("tcpsendfailed")) {
      return printResult(
          ThermalPrinterApi.ThermalPigeonResultStatus.CONNECTION_FAILED,
          "tcpSendFailed",
          message);
    }
    if (lower.startsWith("tcpconnectionfailed")) {
      return printResult(
          ThermalPrinterApi.ThermalPigeonResultStatus.CONNECTION_FAILED,
          "tcpConnectionFailed",
          message);
    }
    if (lower.startsWith("savedbluetoothprinterunavailable")) {
      return printResult(
          ThermalPrinterApi.ThermalPigeonResultStatus.DEVICE_UNAVAILABLE,
          "savedBluetoothPrinterUnavailable",
          message);
    }
    if (lower.contains("bluetoothunavailable") || lower.contains("bluetoothdisabled")) {
      return printResult(
          ThermalPrinterApi.ThermalPigeonResultStatus.DEVICE_UNAVAILABLE,
          "bluetoothUnavailable",
          message);
    }
    if (lower.contains("permission")) {
      return printResult(
          ThermalPrinterApi.ThermalPigeonResultStatus.PERMISSION_DENIED,
          connectionType == ThermalPrinterApi.ThermalPigeonConnectionType.USB
              ? "usbPermissionDenied"
              : "bluetoothPermissionDenied",
          message);
    }
    if (lower.contains("notfound") || lower.contains("ambiguous") || lower.contains("unavailable")) {
      final String code = connectionType == ThermalPrinterApi.ThermalPigeonConnectionType.BLUETOOTH
          ? "bluetoothPrinterUnavailable"
          : message;
      return printResult(ThermalPrinterApi.ThermalPigeonResultStatus.DEVICE_UNAVAILABLE, code, message);
    }
    if (lower.contains("pdf")) {
      return printResult(ThermalPrinterApi.ThermalPigeonResultStatus.INVALID_PDF, message, message);
    }
    if (lower.contains("raster") || lower.contains("bitmap")) {
      return printResult(ThermalPrinterApi.ThermalPigeonResultStatus.RASTERIZATION_FAILED, message, message);
    }
    if (lower.contains("invalid")) {
      return printResult(ThermalPrinterApi.ThermalPigeonResultStatus.INVALID_REQUEST, message, message);
    }
    final String code = connectionType == ThermalPrinterApi.ThermalPigeonConnectionType.TCP
        ? "tcpConnectionFailed"
        : connectionType == ThermalPrinterApi.ThermalPigeonConnectionType.BLUETOOTH
            ? "bluetoothConnectionFailed"
            : "printerConnectionFailed";
    return printResult(
        ThermalPrinterApi.ThermalPigeonResultStatus.CONNECTION_FAILED,
        code,
        message);
  }

  private ThermalPrinterApi.ThermalPigeonResult printResult(
      @NonNull ThermalPrinterApi.ThermalPigeonResultStatus status,
      String errorCode, String diagnostic) {
    return new ThermalPrinterApi.ThermalPigeonResult.Builder()
        .setStatus(status).setErrorCode(errorCode).setDiagnostic(diagnostic).build();
  }

  private ThermalPrinterApi.ThermalPigeonPermissionState permission(
      @NonNull PrinterPermissionCoordinator.State state) {
    return ThermalPrinterApi.ThermalPigeonPermissionState.valueOf(state.name());
  }
}
