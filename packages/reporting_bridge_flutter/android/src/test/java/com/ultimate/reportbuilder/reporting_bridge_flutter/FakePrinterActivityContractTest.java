package com.ultimate.reportbuilder.reporting_bridge_flutter;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import static org.robolectric.Shadows.shadowOf;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;

@RunWith(RobolectricTestRunner.class)
public class FakePrinterActivityContractTest {
  @Test
  public void fakeTargetAcceptsV1ContractAndReturnsStandardResult() {
    final Uri uri = Uri.parse("content://host.reporting_bridge_flutter.fileprovider/report.pdf");
    final Intent intent = new ExternalPrintIntentFactory().createPrintIntent(
        uri,
        ExternalPrintIntentFactoryTest.arguments());

    final FakePrinterActivity activity = Robolectric
        .buildActivity(FakePrinterActivity.class, intent)
        .create()
        .get();

    assertTrue(activity.accepted);
    assertEquals(Activity.RESULT_OK, shadowOf(activity).getResultCode());
  }

  public static final class FakePrinterActivity extends Activity {
    boolean accepted;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
      super.onCreate(savedInstanceState);
      final Intent intent = getIntent();
      accepted = PrintContract.EXTERNAL_ACTION.equals(intent.getAction())
          && PrintContract.EXTERNAL_PACKAGE.equals(intent.getPackage())
          && PrintContract.MIME_TYPE.equals(intent.getType())
          && intent.getData() != null
          && "content".equals(intent.getData().getScheme())
          && (intent.getFlags() & Intent.FLAG_GRANT_READ_URI_PERMISSION) != 0
          && PrintContract.CONTRACT_VERSION.equals(
              intent.getStringExtra("contractVersion"));
      setResult(accepted ? RESULT_OK : RESULT_CANCELED);
      finish();
    }
  }
}
