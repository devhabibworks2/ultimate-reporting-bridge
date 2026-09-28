package com.ultimate.reportbuilder.reporting_bridge_flutter;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import com.dantsu.escposprinter.exceptions.EscPosConnectionException;
import java.io.IOException;
import java.io.OutputStream;
import java.net.SocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.util.ArrayList;
import java.util.List;
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

  @Test
  public void tcpTimeoutUsesProfileSecondsAndRejectsInvalidValues() {
    assertEquals(3000, ThermalTransportPolicy.connectionTimeoutMillis(3));
    assertEquals(1, ThermalTransportPolicy.connectionTimeoutMillis(0));
    assertEquals(1, ThermalTransportPolicy.connectionTimeoutMillis(-1));
  }

  @Test
  public void failedTcpConnectLeavesTransportDisconnected() throws Exception {
    try (ServerSocket server = new ServerSocket(0)) {
      ReliableTcpConnection connection =
          new ReliableTcpConnection("127.0.0.1", server.getLocalPort(), 1);
      server.close();

      try {
        connection.connect();
      } catch (EscPosConnectionException expected) {
        assertTrue(expected.getMessage().startsWith("tcpConnectionRefused;"));
      }

      assertFalse(connection.isConnected());
      connection.disconnect();
      assertFalse(connection.isConnected());
    }
  }

  @Test
  public void tcpConnectTimeoutUsesProfileTimeoutAndClosesEachAttempt() throws Exception {
    List<TestSocket> sockets = new ArrayList<>();
    ReliableTcpConnection connection = new ReliableTcpConnection("127.0.0.1", 9100, 3, () -> {
      TestSocket socket = new TestSocket(new SocketTimeoutException("timed out"));
      sockets.add(socket);
      return socket;
    });

    boolean timedOut = false;
    try {
      connection.connect();
    } catch (EscPosConnectionException expected) {
      assertTrue(expected.getMessage().startsWith("tcpConnectionTimeout;"));
      timedOut = true;
    }

    assertTrue(timedOut);
    assertEquals(2, sockets.size());
    for (TestSocket socket : sockets) {
      assertEquals(3000, socket.timeoutMillis);
      assertTrue(socket.closed);
    }
    assertFalse(connection.isConnected());
  }

  @Test
  public void tcpWriteFailureReturnsTypedErrorAndClosesConnection() throws Exception {
    TestSocket socket = new TestSocket(null, new OutputStream() {
      @Override public void write(int value) throws IOException {
        throw new IOException("write failed");
      }
    });
    ReliableTcpConnection connection = new ReliableTcpConnection("127.0.0.1", 9100, 3, () -> socket);
    connection.connect();
    connection.write(new byte[] {1, 2, 3});

    boolean writeFailed = false;
    try {
      connection.send(0);
    } catch (EscPosConnectionException expected) {
      assertTrue(expected.getMessage().startsWith("tcpSendFailed;write failed"));
      writeFailed = true;
    }

    assertTrue(writeFailed);
    assertTrue(socket.closed);
    assertFalse(connection.isConnected());
  }

  @Test
  public void explicitDisconnectClosesTcpPeer() throws Exception {
    try (ServerSocket server = new ServerSocket(0)) {
      Thread acceptor = new Thread(() -> {
        try (Socket ignored = server.accept()) {
          // Keep the accepted socket open until the client disconnects.
          Thread.sleep(1000);
        } catch (IOException | InterruptedException ignored) {
          Thread.currentThread().interrupt();
        }
      });
      acceptor.start();
      ReliableTcpConnection connection =
          new ReliableTcpConnection("127.0.0.1", server.getLocalPort(), 1);

      connection.connect();
      assertTrue(connection.isConnected());
      connection.disconnect();

      assertFalse(connection.isConnected());
      acceptor.join(1500);
    }
  }

  private static final class TestSocket extends Socket {
    private final IOException connectFailure;
    private final OutputStream stream;
    private boolean connected;
    private boolean closed;
    private int timeoutMillis;

    TestSocket(IOException connectFailure) {
      this(connectFailure, new OutputStream() {
        @Override public void write(int value) {}
      });
    }

    TestSocket(IOException connectFailure, OutputStream stream) {
      this.connectFailure = connectFailure;
      this.stream = stream;
    }

    @Override public void setTcpNoDelay(boolean enabled) {}
    @Override public void setKeepAlive(boolean enabled) {}

    @Override public void connect(SocketAddress endpoint, int timeout) throws IOException {
      timeoutMillis = timeout;
      if (connectFailure != null) throw connectFailure;
      connected = true;
    }

    @Override public OutputStream getOutputStream() {
      return stream;
    }

    @Override public boolean isConnected() {
      return connected;
    }

    @Override public boolean isClosed() {
      return closed;
    }

    @Override public synchronized void close() {
      closed = true;
      connected = false;
    }
  }
}
