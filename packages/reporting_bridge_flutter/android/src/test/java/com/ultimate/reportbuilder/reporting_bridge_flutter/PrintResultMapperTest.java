package com.ultimate.reportbuilder.reporting_bridge_flutter;

import static org.junit.Assert.assertEquals;

import android.app.Activity;
import android.print.PrintJobInfo;

import org.junit.Test;

import java.util.Map;

public class PrintResultMapperTest {
  @Test
  public void mapsSystemPrintStates() {
    assertStatus("submitted", PrintResultMapper.fromSystemPrintState(
        PrintJobInfo.STATE_QUEUED, true));
    assertStatus("submitted", PrintResultMapper.fromSystemPrintState(
        PrintJobInfo.STATE_COMPLETED, true));
    assertStatus("cancelled", PrintResultMapper.fromSystemPrintState(
        PrintJobInfo.STATE_CANCELED, false));
    assertStatus("failed", PrintResultMapper.fromSystemPrintState(
        PrintJobInfo.STATE_FAILED, true));
  }

  @Test
  public void mapsExternalActivityResultsWithoutGuessingCustomProtocol() {
    assertStatus("submitted", PrintResultMapper.fromExternalActivityResult(Activity.RESULT_OK));
    assertStatus("cancelled", PrintResultMapper.fromExternalActivityResult(Activity.RESULT_CANCELED));
    assertStatus("failed", PrintResultMapper.fromExternalActivityResult(Activity.RESULT_FIRST_USER));
  }

  private static void assertStatus(String expected, Map<String, Object> result) {
    assertEquals(expected, result.get("status"));
  }
}
