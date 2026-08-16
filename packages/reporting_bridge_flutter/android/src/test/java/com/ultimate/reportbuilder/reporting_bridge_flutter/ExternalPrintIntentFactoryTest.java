package com.ultimate.reportbuilder.reporting_bridge_flutter;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.content.Intent;
import android.net.Uri;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;

import java.util.HashMap;
import java.util.Map;

@RunWith(RobolectricTestRunner.class)
public class ExternalPrintIntentFactoryTest {
  @Test
  public void createsExplicitReadOnlyV1Intent() throws Exception {
    final Uri uri = Uri.parse("content://host.reporting_bridge_flutter.fileprovider/report.pdf");
    final Map<String, Object> arguments = arguments();
    final Intent intent = new ExternalPrintIntentFactory().createPrintIntent(uri, arguments);

    assertEquals(PrintContract.EXTERNAL_ACTION, intent.getAction());
    assertEquals(PrintContract.EXTERNAL_PACKAGE, intent.getPackage());
    assertEquals(PrintContract.MIME_TYPE, intent.getType());
    assertEquals(uri, intent.getData());
    assertTrue((intent.getFlags() & Intent.FLAG_GRANT_READ_URI_PERMISSION) != 0);
    assertNotNull(intent.getClipData());
    assertEquals(uri, intent.getClipData().getItemAt(0).getUri());
    assertEquals("1", intent.getStringExtra("contractVersion"));
    assertEquals("job-42", intent.getStringExtra("jobId"));
    assertEquals("Invoice 42", intent.getStringExtra("documentTitle"));
    assertEquals("mm", intent.getStringExtra("unit"));
    assertEquals("pages", intent.getStringExtra("layout"));
    assertEquals("a4", intent.getStringExtra("size"));
    assertEquals(210.0, intent.getDoubleExtra("width", 0), 0);
    assertEquals(297.0, intent.getDoubleExtra("height", 0), 0);
    assertEquals("portrait", intent.getStringExtra("orientation"));
    assertEquals("ar", intent.getStringExtra("language_code"));
    assertEquals(1, intent.getIntExtra("language", 0));

    @SuppressWarnings("unchecked")
    final Map<String, Object> extra =
        (Map<String, Object>) intent.getSerializableExtra("extra");
    assertNotNull(extra);
    assertEquals(2, extra.get("copyCount"));
  }

  static Map<String, Object> arguments() {
    final Map<String, Object> extra = new HashMap<>();
    extra.put("copyCount", 2);

    final Map<String, Object> arguments = new HashMap<>();
    arguments.put("packageName", PrintContract.EXTERNAL_PACKAGE);
    arguments.put("action", PrintContract.EXTERNAL_ACTION);
    arguments.put("mimeType", PrintContract.MIME_TYPE);
    arguments.put("contractVersion", PrintContract.CONTRACT_VERSION);
    arguments.put("jobId", "job-42");
    arguments.put("documentTitle", "Invoice 42");
    arguments.put("unit", "mm");
    arguments.put("layout", "pages");
    arguments.put("size", "a4");
    arguments.put("width", 210.0);
    arguments.put("height", 297.0);
    arguments.put("orientation", "portrait");
    arguments.put("language_code", "ar");
    arguments.put("language", 1);
    arguments.put("extra", extra);
    return arguments;
  }
}
