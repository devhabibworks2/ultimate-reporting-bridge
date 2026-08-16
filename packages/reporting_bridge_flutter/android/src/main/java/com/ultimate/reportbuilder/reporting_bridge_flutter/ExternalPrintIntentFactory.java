package com.ultimate.reportbuilder.reporting_bridge_flutter;

import android.content.ClipData;
import android.content.Intent;
import android.net.Uri;

import java.io.Serializable;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

final class ExternalPrintIntentFactory {
  Intent createResolutionIntent(String packageName, String action, String mimeType) {
    return new Intent(action)
        .setPackage(packageName)
        .setType(mimeType);
  }

  Intent createPrintIntent(Uri contentUri, Map<String, Object> arguments) {
    final String packageName = requiredString(arguments, "packageName");
    final String action = requiredString(arguments, "action");
    final String mimeType = requiredString(arguments, "mimeType");

    final Intent intent = new Intent(action)
        .setPackage(packageName)
        .setDataAndType(contentUri, mimeType)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
    intent.setClipData(ClipData.newRawUri("reportPdf", contentUri));

    intent.putExtra("contractVersion", requiredString(arguments, "contractVersion"));
    intent.putExtra("jobId", requiredString(arguments, "jobId"));
    intent.putExtra("documentTitle", requiredString(arguments, "documentTitle"));
    intent.putExtra("unit", requiredString(arguments, "unit"));
    intent.putExtra("layout", requiredString(arguments, "layout"));
    intent.putExtra("size", requiredString(arguments, "size"));
    intent.putExtra("width", requiredDouble(arguments, "width"));
    intent.putExtra("height", requiredDouble(arguments, "height"));
    intent.putExtra("orientation", requiredString(arguments, "orientation"));
    intent.putExtra("language_code", requiredString(arguments, "language_code"));
    intent.putExtra("language", requiredInt(arguments, "language"));

    @SuppressWarnings("unchecked")
    final Map<String, Object> extra = arguments.get("extra") instanceof Map
        ? (Map<String, Object>) arguments.get("extra")
        : Collections.emptyMap();
    intent.putExtra("extra", (Serializable) new HashMap<>(extra));
    return intent;
  }

  private static String requiredString(Map<String, Object> arguments, String key) {
    final Object value = arguments.get(key);
    if (!(value instanceof String) || ((String) value).trim().isEmpty()) {
      throw new IllegalArgumentException("Missing or invalid " + key);
    }
    return (String) value;
  }

  private static double requiredDouble(Map<String, Object> arguments, String key) {
    final Object value = arguments.get(key);
    if (!(value instanceof Number)) {
      throw new IllegalArgumentException("Missing or invalid " + key);
    }
    return ((Number) value).doubleValue();
  }

  private static int requiredInt(Map<String, Object> arguments, String key) {
    final Object value = arguments.get(key);
    if (!(value instanceof Number)) {
      throw new IllegalArgumentException("Missing or invalid " + key);
    }
    return ((Number) value).intValue();
  }
}
