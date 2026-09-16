package com.ultimate.reportbuilder.reporting_bridge_flutter;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class ReliableTcpConnectionTest {
  @Test
  public void pacingMatchesConfiguredTcpThroughput() {
    assertEquals(32L, ReliableTcpConnection.pacingDelayMillis(4 * 1024));
    assertEquals(1000L, ReliableTcpConnection.pacingDelayMillis(128 * 1024));
  }

  @Test
  public void transportPolicyUsesSmallerBluetoothStripes() {
    assertEquals(
        128,
        ThermalTransportPolicy.stripeHeight(
            ThermalPrinterApi.ThermalPigeonConnectionType.BLUETOOTH));
    assertEquals(
        384,
        ThermalTransportPolicy.stripeHeight(
            ThermalPrinterApi.ThermalPigeonConnectionType.USB));
    assertEquals(
        384,
        ThermalTransportPolicy.stripeHeight(
            ThermalPrinterApi.ThermalPigeonConnectionType.TCP));
  }

  @Test
  public void bluetoothPacingIsFasterThanDantSuDefault() {
    assertEquals(
        63L,
        ThermalTransportPolicy.pacingDelayMillis(
            ThermalTransportPolicy.BLUETOOTH_CHUNK_BYTES,
            ThermalTransportPolicy.BLUETOOTH_BYTES_PER_SECOND));
  }
}
