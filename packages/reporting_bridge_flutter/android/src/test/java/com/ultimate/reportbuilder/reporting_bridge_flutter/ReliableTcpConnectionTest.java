package com.ultimate.reportbuilder.reporting_bridge_flutter;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import com.dantsu.escposprinter.exceptions.EscPosConnectionException;
import java.io.IOException;
import java.io.OutputStream;
import java.net.SocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
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
  public void tcpSendTimeoutUsesProfileTimeoutAndDisconnects() throws Exception {
    CountDownLatch writeEntered = new CountDownLatch(1);
    BlockingOutputStream stream = new BlockingOutputStream(writeEntered);
    TestSocket socket = new TestSocket(null, stream);
    // Profile timeout = 1s; send must fail closed within a small multiple of that.
    ReliableTcpConnection connection =
        new ReliableTcpConnection("127.0.0.1", 9100, 1, () -> socket);
    connection.connect();
    connection.write(new byte[] {1, 2, 3});

    ExecutorService executor = Executors.newSingleThreadExecutor();
    Future<?> sendFuture =
        executor.submit(
            () -> {
              connection.send(0);
              return null;
            });

    assertTrue(
        "send should reach OutputStream.write before timing out",
        writeEntered.await(1, TimeUnit.SECONDS));

    try {
      sendFuture.get(3, TimeUnit.SECONDS);
      fail("send should throw EscPosConnectionException on write deadline");
    } catch (TimeoutException hung) {
      sendFuture.cancel(true);
      fail(
          "send did not return within bounded deadline; OutputStream.write still blocks"
              + " without a write deadline");
    } catch (ExecutionException execution) {
      Throwable cause = execution.getCause();
      assertTrue(
          "expected EscPosConnectionException, got " + cause,
          cause instanceof EscPosConnectionException);
      assertTrue(
          ((EscPosConnectionException) cause).getMessage().startsWith("tcpSendTimeout;"));
    } finally {
      executor.shutdownNow();
    }

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

    @Override public synchronized void close() throws IOException {
      closed = true;
      connected = false;
      stream.close();
    }
  }

  /** Blocks in write/flush until {@link #close()} to simulate a stalled printer socket. */
  private static final class BlockingOutputStream extends OutputStream {
    private final CountDownLatch writeEntered;
    private final Object lock = new Object();
    private boolean closed;

    BlockingOutputStream(CountDownLatch writeEntered) {
      this.writeEntered = writeEntered;
    }

    @Override
    public void write(int value) throws IOException {
      write(new byte[] {(byte) value}, 0, 1);
    }

    @Override
    public void write(byte[] buffer, int offset, int length) throws IOException {
      writeEntered.countDown();
      synchronized (lock) {
        while (!closed) {
          try {
            lock.wait();
          } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            throw new IOException("interrupted");
          }
        }
        throw new IOException("stream closed");
      }
    }

    @Override
    public void flush() throws IOException {
      // No-op until close unblocks a parked write.
    }

    @Override
    public void close() {
      synchronized (lock) {
        closed = true;
        lock.notifyAll();
      }
    }
  }
}
