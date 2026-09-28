package com.ultimate.reportbuilder.reporting_bridge_flutter;

import android.bluetooth.BluetoothDevice;

import androidx.annotation.NonNull;

import com.dantsu.escposprinter.connection.bluetooth.BluetoothConnection;
import com.dantsu.escposprinter.exceptions.EscPosConnectionException;

import java.io.IOException;

/** Bluetooth RFCOMM transport without DantSu's fixed data.length / 16 pause. */
final class ReliableBluetoothConnection extends BluetoothConnection {
  ReliableBluetoothConnection(@NonNull BluetoothDevice device) {
    super(device);
  }

  @Override
  public void send(int addWaitingTime) throws EscPosConnectionException {
    if (!isConnected()) {
      throw new EscPosConnectionException("bluetoothSendFailed;notConnected");
    }
    final byte[] pending = data;
    try {
      for (int offset = 0; offset < pending.length;
          offset += ThermalTransportPolicy.BLUETOOTH_CHUNK_BYTES) {
        final int length = Math.min(
            ThermalTransportPolicy.BLUETOOTH_CHUNK_BYTES,
            pending.length - offset);
        outputStream.write(pending, offset, length);
        outputStream.flush();
        if (offset + length < pending.length) {
          Thread.sleep(ThermalTransportPolicy.pacingDelayMillis(
              length,
              ThermalTransportPolicy.BLUETOOTH_BYTES_PER_SECOND));
        }
      }
      data = new byte[0];
      if (addWaitingTime > 0) Thread.sleep(addWaitingTime);
    } catch (IOException error) {
      throw new EscPosConnectionException(
          "bluetoothSendFailed;" + safeMessage(error));
    } catch (InterruptedException error) {
      Thread.currentThread().interrupt();
      throw new EscPosConnectionException("bluetoothSendFailed;interrupted");
    }
  }

  @NonNull
  private static String safeMessage(@NonNull IOException error) {
    final String message = error.getMessage();
    return message == null || message.trim().isEmpty()
        ? error.getClass().getSimpleName()
        : message;
  }
}
