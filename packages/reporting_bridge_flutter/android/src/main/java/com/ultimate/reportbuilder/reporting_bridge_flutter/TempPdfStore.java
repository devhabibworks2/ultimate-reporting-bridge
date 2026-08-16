package com.ultimate.reportbuilder.reporting_bridge_flutter;

import android.content.Context;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.UUID;

final class TempPdfStore {
  private static final String DIRECTORY_NAME = "reporting_bridge_print";

  private final File directory;

  TempPdfStore(Context context) {
    directory = new File(context.getCacheDir(), DIRECTORY_NAME);
  }

  File create(byte[] bytes, String filename, long nowMillis) throws IOException {
    if (!directory.exists() && !directory.mkdirs() && !directory.isDirectory()) {
      throw new IOException("Unable to create print cache directory");
    }
    final String safeName = sanitize(filename);
    final File file = new File(
        directory,
        nowMillis + "_" + UUID.randomUUID() + "_" + safeName);
    try (FileOutputStream output = new FileOutputStream(file)) {
      output.write(bytes);
      output.flush();
    }
    return file;
  }

  void cleanup(long ttlMillis, long nowMillis) {
    if (ttlMillis <= 0 || !directory.isDirectory()) {
      return;
    }
    final File[] files = directory.listFiles();
    if (files == null) {
      return;
    }
    final long cutoff = nowMillis - ttlMillis;
    for (File file : files) {
      if (file.isFile() && file.lastModified() <= cutoff) {
        delete(file);
      }
    }
  }

  void delete(File file) {
    if (file != null && file.exists()) {
      // Best effort. The 24-hour sweep handles any transient failure.
      file.delete();
    }
  }

  File directory() {
    return directory;
  }

  private static String sanitize(String filename) {
    final String candidate = filename == null ? "report.pdf" : filename.trim();
    final String safe = candidate.replaceAll("[^A-Za-z0-9._-]", "_");
    return safe.isEmpty() ? "report.pdf" : safe;
  }
}
