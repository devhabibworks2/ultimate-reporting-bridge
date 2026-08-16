package com.ultimate.reportbuilder.reporting_bridge_flutter;

import android.app.Activity;
import android.print.PrintJobInfo;

import java.util.Map;

final class PrintResultMapper {
  private PrintResultMapper() {}

  static Map<String, Object> fromSystemPrintState(int state, boolean writeCompleted) {
    switch (state) {
      case PrintJobInfo.STATE_CANCELED:
        return PrintResultPayload.cancelled();
      case PrintJobInfo.STATE_FAILED:
        return PrintResultPayload.failed("printJobFailed", null);
      case PrintJobInfo.STATE_BLOCKED:
        return PrintResultPayload.failed("printJobBlocked", null);
      case PrintJobInfo.STATE_QUEUED:
      case PrintJobInfo.STATE_STARTED:
      case PrintJobInfo.STATE_COMPLETED:
        return PrintResultPayload.submitted();
      case PrintJobInfo.STATE_CREATED:
        return writeCompleted
            ? PrintResultPayload.submitted()
            : PrintResultPayload.cancelled();
      default:
        return PrintResultPayload.failed("printJobUnknownState", Integer.toString(state));
    }
  }

  static Map<String, Object> fromExternalActivityResult(int resultCode) {
    if (resultCode == Activity.RESULT_OK) {
      return PrintResultPayload.submitted();
    }
    if (resultCode == Activity.RESULT_CANCELED) {
      return PrintResultPayload.cancelled();
    }
    return PrintResultPayload.failed(
        "externalPrinterUnknownResult",
        Integer.toString(resultCode));
  }
}
