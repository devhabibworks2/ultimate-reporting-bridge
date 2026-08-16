package com.ultimate.reportbuilder.reporting_bridge_flutter;

import java.util.HashMap;
import java.util.Map;

final class PrintResultPayload {
  private PrintResultPayload() {}

  static Map<String, Object> submitted() {
    return of("submitted", null, null);
  }

  static Map<String, Object> cancelled() {
    return of("cancelled", null, null);
  }

  static Map<String, Object> appNotInstalled() {
    return of("appNotInstalled", "externalPrinterNotInstalled", null);
  }

  static Map<String, Object> failed(String errorCode, String diagnostic) {
    return of("failed", errorCode, diagnostic);
  }

  static Map<String, Object> unsupportedContract(String errorCode, String diagnostic) {
    return of("unsupportedContract", errorCode, diagnostic);
  }

  static Map<String, Object> of(String status, String errorCode, String diagnostic) {
    final Map<String, Object> result = new HashMap<>();
    result.put("status", status);
    if (errorCode != null) {
      result.put("errorCode", errorCode);
    }
    if (diagnostic != null) {
      result.put("diagnostic", diagnostic);
    }
    return result;
  }
}
