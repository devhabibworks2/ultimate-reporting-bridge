package com.ultimate.reportbuilder.reporting_bridge_flutter;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import java.io.IOException;
import java.io.OutputStream;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.net.SocketTimeoutException;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import org.junit.Test;

/**
 * Names the shared package-private write-deadline seam expected for both
 * {@link ReliableTcpConnection#send(int)} and {@link ReliableBluetoothConnection#send(int)}.
 * BluetoothConnection needs an Android BluetoothDevice, so Bluetooth is covered through this
 * helper rather than a device-backed {@code ReliableBluetoothConnectionTest}.
 */
public final class ThermalWriteDeadlineTest {
  private static final String HELPER_CLASS =
      "com.ultimate.reportbuilder.reporting_bridge_flutter.ThermalWriteDeadline";

  @Test
  public void writeDeadlineMillisMatchesProfileSeconds() throws Exception {
    Class<?> helper = Class.forName(HELPER_CLASS);
    Method deadlineMillis = helper.getDeclaredMethod("writeDeadlineMillis", int.class);
    deadlineMillis.setAccessible(true);
    assertEquals(1000, ((Number) deadlineMillis.invoke(null, 1)).intValue());
    assertEquals(1, ((Number) deadlineMillis.invoke(null, 0)).intValue());
  }

  @Test
  public void writeTimesOutOnBlockedStreamAndIsReusableForTcpAndBluetooth() throws Exception {
    Class<?> helper = Class.forName(HELPER_CLASS);
    Method write =
        helper.getDeclaredMethod(
            "write", OutputStream.class, byte[].class, int.class, int.class, long.class);
    write.setAccessible(true);

    CountDownLatch entered = new CountDownLatch(1);
    BlockingOutputStream stream = new BlockingOutputStream(entered);
    byte[] payload = new byte[] {9, 8, 7};

    long started = System.nanoTime();
    try {
      write.invoke(null, stream, payload, 0, payload.length, 200L);
      fail("ThermalWriteDeadline.write should time out on a blocked OutputStream");
    } catch (InvocationTargetException invocation) {
      Throwable cause = invocation.getCause();
      assertTrue(
          "expected SocketTimeoutException, got " + cause,
          cause instanceof SocketTimeoutException);
    }
    long elapsedMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started);

    assertTrue(entered.await(0, TimeUnit.MILLISECONDS));
    assertTrue("deadline should fire near 200ms, elapsed=" + elapsedMs, elapsedMs < 1500);
  }

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
    public void close() {
      synchronized (lock) {
        closed = true;
        lock.notifyAll();
      }
    }
  }
}
