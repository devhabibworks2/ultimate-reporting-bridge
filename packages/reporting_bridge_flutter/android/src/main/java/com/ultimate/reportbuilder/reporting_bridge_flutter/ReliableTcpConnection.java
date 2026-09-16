package com.ultimate.reportbuilder.reporting_bridge_flutter;

import androidx.annotation.NonNull;

import com.dantsu.escposprinter.connection.DeviceConnection;
import com.dantsu.escposprinter.exceptions.EscPosConnectionException;

import java.io.IOException;
import java.net.ConnectException;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.net.UnknownHostException;

/**
 * A TCP transport for DantSu commands that uses the profile timeout in seconds
 * and keeps network raster output smooth instead of pausing after an entire
 * bitmap stripe.
 */
final class ReliableTcpConnection extends DeviceConnection {
  static final int CHUNK_BYTES = ThermalTransportPolicy.TCP_CHUNK_BYTES;
  static final int BYTES_PER_SECOND = ThermalTransportPolicy.TCP_BYTES_PER_SECOND;
  private static final int CONNECT_RETRY_DELAY_MS = 300;
  private static final int CONNECT_ATTEMPTS = 2;

  private final String host;
  private final int port;
  private final int timeoutMillis;
  private Socket socket;

  ReliableTcpConnection(@NonNull String host, int port, int timeoutSeconds) {
    this.host = host;
    this.port = port;
    this.timeoutMillis = Math.multiplyExact(timeoutSeconds, 1000);
  }

  @Override
  public boolean isConnected() {
    return socket != null && socket.isConnected() && !socket.isClosed() && super.isConnected();
  }

  @Override
  @NonNull public ReliableTcpConnection connect() throws EscPosConnectionException {
    if (isConnected()) return this;
    IOException lastError = null;
    for (int attempt = 1; attempt <= CONNECT_ATTEMPTS; attempt++) {
      try {
        final Socket candidate = new Socket();
        socket = candidate;
        candidate.setTcpNoDelay(true);
        candidate.setKeepAlive(true);
        candidate.connect(
            new InetSocketAddress(InetAddress.getByName(host), port), timeoutMillis);
        outputStream = candidate.getOutputStream();
        data = new byte[0];
        return this;
      } catch (UnknownHostException error) {
        disconnect();
        throw connectionError("tcpHostNotFound", error);
      } catch (IOException error) {
        lastError = error;
        disconnect();
        if (attempt < CONNECT_ATTEMPTS) waitBeforeRetry();
      }
    }
    throw connectionError(errorCode(lastError), lastError);
  }

  @Override
  @NonNull public ReliableTcpConnection disconnect() {
    data = new byte[0];
    if (outputStream != null) {
      try {
        outputStream.close();
      } catch (IOException ignored) {
        // Closing is best effort during failure cleanup.
      }
      outputStream = null;
    }
    if (socket != null) {
      try {
        socket.close();
      } catch (IOException ignored) {
        // Closing is best effort during failure cleanup.
      }
      socket = null;
    }
    return this;
  }

  @Override
  public void send(int addWaitingTime) throws EscPosConnectionException {
    if (!isConnected()) {
      throw new EscPosConnectionException("tcpSendFailed;notConnected");
    }
    final byte[] pending = data;
    try {
      for (int offset = 0; offset < pending.length; offset += CHUNK_BYTES) {
        final int length = Math.min(CHUNK_BYTES, pending.length - offset);
        outputStream.write(pending, offset, length);
        outputStream.flush();
        if (offset + length < pending.length) {
          Thread.sleep(pacingDelayMillis(length));
        }
      }
      data = new byte[0];
      if (addWaitingTime > 0) Thread.sleep(addWaitingTime);
    } catch (IOException error) {
      throw new EscPosConnectionException("tcpSendFailed;" + safeMessage(error));
    } catch (InterruptedException error) {
      Thread.currentThread().interrupt();
      throw new EscPosConnectionException("tcpSendFailed;interrupted");
    }
  }

  static long pacingDelayMillis(int length) {
    return ThermalTransportPolicy.pacingDelayMillis(length, BYTES_PER_SECOND);
  }

  private void waitBeforeRetry() throws EscPosConnectionException {
    try {
      Thread.sleep(CONNECT_RETRY_DELAY_MS);
    } catch (InterruptedException error) {
      Thread.currentThread().interrupt();
      throw new EscPosConnectionException("tcpConnectionFailed;interrupted");
    }
  }

  @NonNull private EscPosConnectionException connectionError(String code, IOException error) {
    return new EscPosConnectionException(code + ";" + safeMessage(error));
  }

  @NonNull private static String errorCode(IOException error) {
    if (error instanceof SocketTimeoutException) return "tcpConnectionTimeout";
    if (error instanceof ConnectException) return "tcpConnectionRefused";
    return "tcpConnectionFailed";
  }

  @NonNull private static String safeMessage(IOException error) {
    final String message = error.getMessage();
    return message == null || message.trim().isEmpty()
        ? error.getClass().getSimpleName()
        : message;
  }
}
