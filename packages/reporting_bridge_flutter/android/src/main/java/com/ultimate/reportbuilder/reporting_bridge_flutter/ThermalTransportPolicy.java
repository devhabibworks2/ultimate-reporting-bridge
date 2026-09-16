package com.ultimate.reportbuilder.reporting_bridge_flutter;

import androidx.annotation.NonNull;

/** Central transport tuning used by rasterization and physical writes. */
final class ThermalTransportPolicy {
  static final int TCP_CHUNK_BYTES = 4096;
  static final int TCP_BYTES_PER_SECOND = 128 * 1024;
  static final int BLUETOOTH_CHUNK_BYTES = 2048;
  static final int BLUETOOTH_BYTES_PER_SECOND = 32 * 1024;
  static final int FAST_STRIPE_HEIGHT_PX = 384;
  static final int BLUETOOTH_STRIPE_HEIGHT_PX = 128;

  private ThermalTransportPolicy() {}

  static int stripeHeight(@NonNull ThermalPrinterApi.ThermalPigeonConnectionType type) {
    return type == ThermalPrinterApi.ThermalPigeonConnectionType.BLUETOOTH
        ? BLUETOOTH_STRIPE_HEIGHT_PX
        : FAST_STRIPE_HEIGHT_PX;
  }

  static long pacingDelayMillis(int length, int bytesPerSecond) {
    return Math.max(1L, ((long) length * 1000L + bytesPerSecond - 1L) / bytesPerSecond);
  }
}
