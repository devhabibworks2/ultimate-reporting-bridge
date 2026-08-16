package com.ultimate.reportbuilder.reporting_bridge_flutter;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;

final class PrintContract {
  static final String CHANNEL = "reporting_bridge_flutter/print";
  static final String EXTERNAL_PACKAGE = "com.Ultimate.Printer";
  static final String EXTERNAL_ACTION = "com.Ultimate.Printer.PRINT_PDF_V1";
  static final String MIME_TYPE = "application/pdf";
  static final String CONTRACT_VERSION = "1";
  static final int DEFAULT_MAXIMUM_PDF_BYTES = 50 * 1024 * 1024;
  static final long DEFAULT_STALE_FILE_TTL_MILLIS = 24L * 60L * 60L * 1000L;
  static final int EXTERNAL_PRINT_REQUEST_CODE = 45731;

  static final Set<String> RESERVED_EXTRA_FIELDS = Collections.unmodifiableSet(
      new HashSet<>(Arrays.asList(
          "contractVersion",
          "jobId",
          "documentTitle",
          "unit",
          "layout",
          "size",
          "width",
          "height",
          "orientation",
          "language_code",
          "language",
          "extra")));

  private PrintContract() {}
}
