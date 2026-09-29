package com.ultimate.reportbuilder.reporting_bridge_flutter;

import androidx.annotation.NonNull;

import java.io.IOException;
import java.io.OutputStream;
import java.net.SocketTimeoutException;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.FutureTask;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

/** Runs one physical transport write with a hard deadline. */
final class ThermalWriteDeadline {
  private ThermalWriteDeadline() {}

  static int writeDeadlineMillis(int timeoutSeconds) {
    return ThermalTransportPolicy.connectionTimeoutMillis(timeoutSeconds);
  }

  static void write(
      @NonNull OutputStream stream,
      @NonNull byte[] buffer,
      int offset,
      int length,
      long timeoutMillis) throws IOException {
    final FutureTask<Void> writeTask =
        new FutureTask<>(
            () -> {
              stream.write(buffer, offset, length);
              stream.flush();
              return null;
            });
    final Thread worker = new Thread(writeTask, "urb-thermal-write");
    worker.setDaemon(true);
    worker.start();
    try {
      writeTask.get(Math.max(1L, timeoutMillis), TimeUnit.MILLISECONDS);
    } catch (TimeoutException error) {
      writeTask.cancel(true);
      final SocketTimeoutException timeout = new SocketTimeoutException("thermalWriteTimeout");
      timeout.initCause(error);
      throw timeout;
    } catch (InterruptedException error) {
      writeTask.cancel(true);
      Thread.currentThread().interrupt();
      throw new IOException("thermalWriteInterrupted", error);
    } catch (ExecutionException error) {
      final Throwable cause = error.getCause();
      if (cause instanceof IOException) throw (IOException) cause;
      throw new IOException("thermalWriteFailed", cause);
    }
  }
}
