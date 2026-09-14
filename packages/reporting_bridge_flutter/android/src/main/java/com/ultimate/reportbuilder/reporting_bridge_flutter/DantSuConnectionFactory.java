package com.ultimate.reportbuilder.reporting_bridge_flutter;

import android.annotation.SuppressLint;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothClass;
import android.bluetooth.BluetoothDevice;
import android.content.Context;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.dantsu.escposprinter.connection.DeviceConnection;
import com.dantsu.escposprinter.connection.bluetooth.BluetoothConnection;
import com.dantsu.escposprinter.connection.usb.UsbConnection;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Set;

final class DantSuConnectionFactory {
  private final Context context;
  private final UsbManager usbManager;

  DantSuConnectionFactory(@NonNull Context context) {
    this.context = context.getApplicationContext();
    this.usbManager = (UsbManager) this.context.getSystemService(Context.USB_SERVICE);
  }

  @SuppressLint("MissingPermission")
  @NonNull List<BluetoothDevice> pairedBluetoothDevices() throws IOException {
    final BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
    if (adapter == null) throw new IOException("bluetoothUnavailable");
    if (!adapter.isEnabled()) throw new IOException("bluetoothDisabled");
    final Set<BluetoothDevice> bonded = adapter.getBondedDevices();
    final List<BluetoothDevice> devices = new ArrayList<>(bonded);
    devices.sort(Comparator.comparing(this::isLikelyPrinter).reversed()
        .thenComparing(device -> safeName(device)));
    return devices;
  }

  @NonNull List<UsbDevice> connectedUsbDevices() {
    if (usbManager == null) return new ArrayList<>();
    final List<UsbDevice> printers = new ArrayList<>();
    for (UsbDevice device : usbManager.getDeviceList().values()) {
      if (isPrinter(device)) printers.add(device);
    }
    return printers;
  }

  @SuppressLint("MissingPermission")
  @NonNull DeviceConnection create(@NonNull ThermalPrinterApi.ThermalPigeonProfile profile)
      throws IOException {
    switch (profile.getConnectionType()) {
      case BLUETOOTH:
        final String address = profile.getBluetoothAddress();
        if (address == null) throw new IOException("invalidBluetoothProfile");
        final List<BluetoothDevice> paired = pairedBluetoothDevices();
        for (BluetoothDevice device : paired) {
          if (address.equalsIgnoreCase(device.getAddress())) return new BluetoothConnection(device);
        }
        throw new IOException(
            "savedBluetoothPrinterUnavailable;address=" + address
                + ";pairedCount=" + paired.size());
      case USB:
        final UsbDevice usb = resolveUsb(profile);
        if (usbManager == null) throw new IOException("usbUnsupported");
        if (!usbManager.hasPermission(usb)) throw new IOException("usbPermissionDenied");
        return new UsbConnection(usbManager, usb);
      case TCP:
        final String host = profile.getTcpHost();
        final Long port = profile.getTcpPort();
        final Long timeout = profile.getTcpTimeoutSeconds();
        if (host == null || host.trim().isEmpty() || port == null || port < 1 || port > 65535
            || timeout == null || timeout < 1 || timeout > 60) {
          throw new IOException("invalidTcpProfile");
        }
        return new ReliableTcpConnection(
            host.trim(),
            port.intValue(),
            timeout.intValue());
      default:
        throw new IOException("unsupportedConnection");
    }
  }

  @NonNull UsbDevice resolveUsb(@NonNull ThermalPrinterApi.ThermalPigeonProfile profile)
      throws IOException {
    final Long vendor = profile.getUsbVendorId();
    final Long product = profile.getUsbProductId();
    if (vendor == null || product == null) throw new IOException("invalidUsbProfile");
    final String wantedSerial = profile.getUsbSerialNumber();
    final List<UsbDevice> matches = new ArrayList<>();
    for (UsbDevice device : connectedUsbDevices()) {
      if (device.getVendorId() != vendor.intValue() || device.getProductId() != product.intValue()) continue;
      if (wantedSerial != null && !wantedSerial.isEmpty()) {
        try {
          if (!wantedSerial.equals(device.getSerialNumber())) continue;
        } catch (SecurityException ignored) {
          continue;
        }
      }
      matches.add(device);
    }
    if (matches.isEmpty()) throw new IOException("printerNotFound");
    if (matches.size() > 1) throw new IOException("ambiguousUsbPrinter");
    return matches.get(0);
  }

  @Nullable UsbDevice findUsbDevice(@NonNull ThermalPrinterApi.ThermalPigeonDevice device) {
    for (UsbDevice candidate : connectedUsbDevices()) {
      if (device.getId().equals(candidate.getDeviceName())) return candidate;
    }
    return null;
  }

  @SuppressLint("MissingPermission")
  @NonNull String safeName(@NonNull BluetoothDevice device) {
    final String name = device.getName();
    return name == null || name.trim().isEmpty() ? device.getAddress() : name;
  }

  @SuppressLint("MissingPermission")
  boolean isLikelyPrinter(@NonNull BluetoothDevice device) {
    final BluetoothClass klass = device.getBluetoothClass();
    return klass != null && klass.getMajorDeviceClass() == BluetoothClass.Device.Major.IMAGING;
  }

  private boolean isPrinter(@NonNull UsbDevice device) {
    if (device.getDeviceClass() == 7) return true;
    for (int index = 0; index < device.getInterfaceCount(); index++) {
      if (device.getInterface(index).getInterfaceClass() == 7) return true;
    }
    return false;
  }
}
