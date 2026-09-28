package com.ultimate.reportbuilder.reporting_bridge_flutter;

import android.Manifest;
import android.app.Activity;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.os.Build;

import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import io.flutter.plugin.common.PluginRegistry;

/** Owns runtime Bluetooth and per-device USB permission requests. */
final class PrinterPermissionCoordinator
    implements PluginRegistry.RequestPermissionsResultListener {
  static final int BLUETOOTH_PERMISSION_REQUEST = 9187;

  enum State { GRANTED, DENIED, PERMANENTLY_DENIED, ACTIVITY_UNAVAILABLE, UNSUPPORTED }

  interface Callback { void complete(@NonNull State state); }

  private final Context applicationContext;
  private final UsbManager usbManager;
  private final String usbPermissionAction;
  private Activity activity;
  private Callback pendingBluetoothCallback;
  private Callback pendingUsbCallback;
  private boolean usbReceiverRegistered;

  private final BroadcastReceiver usbReceiver = new BroadcastReceiver() {
    @Override public void onReceive(Context context, Intent intent) {
      if (!usbPermissionAction.equals(intent.getAction())) return;
      final Callback callback = pendingUsbCallback;
      pendingUsbCallback = null;
      unregisterUsbReceiver();
      if (callback == null) return;
      callback.complete(intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
          ? State.GRANTED : State.DENIED);
    }
  };

  PrinterPermissionCoordinator(@NonNull Context context) {
    applicationContext = context.getApplicationContext();
    usbManager = (UsbManager) applicationContext.getSystemService(Context.USB_SERVICE);
    usbPermissionAction = applicationContext.getPackageName()
        + ".reporting_bridge_flutter.USB_PERMISSION";
  }

  void attach(@NonNull Activity activity) { this.activity = activity; }

  void detach() {
    activity = null;
    if (pendingBluetoothCallback != null) {
      pendingBluetoothCallback.complete(State.ACTIVITY_UNAVAILABLE);
      pendingBluetoothCallback = null;
    }
    if (pendingUsbCallback != null) {
      pendingUsbCallback.complete(State.ACTIVITY_UNAVAILABLE);
      pendingUsbCallback = null;
    }
    unregisterUsbReceiver();
  }

  @NonNull State bluetoothState() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return State.GRANTED;
    final boolean connect = ContextCompat.checkSelfPermission(
        applicationContext, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED;
    final boolean scan = ContextCompat.checkSelfPermission(
        applicationContext, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED;
    if (connect && scan) return State.GRANTED;
    final Activity current = activity;
    if (current == null) return State.ACTIVITY_UNAVAILABLE;
    final boolean rationale = ActivityCompat.shouldShowRequestPermissionRationale(
        current, Manifest.permission.BLUETOOTH_CONNECT)
        || ActivityCompat.shouldShowRequestPermissionRationale(
            current, Manifest.permission.BLUETOOTH_SCAN);
    return rationale ? State.DENIED : State.PERMANENTLY_DENIED;
  }

  void requestBluetooth(@NonNull Callback callback) {
    final State state = bluetoothState();
    if (state == State.GRANTED || state == State.ACTIVITY_UNAVAILABLE) {
      callback.complete(state);
      return;
    }
    final Activity current = activity;
    if (current == null || pendingBluetoothCallback != null) {
      callback.complete(current == null ? State.ACTIVITY_UNAVAILABLE : State.DENIED);
      return;
    }
    pendingBluetoothCallback = callback;
    ActivityCompat.requestPermissions(
        current,
        new String[] {Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_SCAN},
        BLUETOOTH_PERMISSION_REQUEST);
  }

  @NonNull State usbState(@NonNull UsbDevice device) {
    if (usbManager == null) return State.UNSUPPORTED;
    return usbManager.hasPermission(device) ? State.GRANTED : State.DENIED;
  }

  void requestUsb(@NonNull UsbDevice device, @NonNull Callback callback) {
    final State state = usbState(device);
    if (state == State.GRANTED || state == State.UNSUPPORTED) {
      callback.complete(state);
      return;
    }
    if (pendingUsbCallback != null) {
      callback.complete(State.DENIED);
      return;
    }
    pendingUsbCallback = callback;
    final Intent intent = new Intent(usbPermissionAction).setPackage(applicationContext.getPackageName());
    final int flags = PendingIntent.FLAG_UPDATE_CURRENT
        | (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ? PendingIntent.FLAG_MUTABLE : 0);
    final PendingIntent pendingIntent = PendingIntent.getBroadcast(applicationContext, 0, intent, flags);
    final IntentFilter filter = new IntentFilter(usbPermissionAction);
    ContextCompat.registerReceiver(
        applicationContext, usbReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED);
    usbReceiverRegistered = true;
    usbManager.requestPermission(device, pendingIntent);
  }

  @Override public boolean onRequestPermissionsResult(
      int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
    if (requestCode != BLUETOOTH_PERMISSION_REQUEST) return false;
    final Callback callback = pendingBluetoothCallback;
    pendingBluetoothCallback = null;
    if (callback != null) callback.complete(bluetoothState());
    return true;
  }

  private void unregisterUsbReceiver() {
    if (!usbReceiverRegistered) return;
    try { applicationContext.unregisterReceiver(usbReceiver); } catch (IllegalArgumentException ignored) {}
    usbReceiverRegistered = false;
  }
}
