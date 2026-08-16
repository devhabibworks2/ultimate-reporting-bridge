package com.ultimate.reportbuilder.reporting_bridge_flutter;

import android.os.CancellationSignal;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelFileDescriptor;
import android.print.PageRange;
import android.print.PrintAttributes;
import android.print.PrintDocumentAdapter;
import android.print.PrintDocumentInfo;
import android.print.PrintJob;
import android.print.PrintJobInfo;

import java.io.FileOutputStream;
import java.io.IOException;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

final class PdfPrintDocumentAdapter extends PrintDocumentAdapter {
  interface CompletionCallback {
    void complete(Map<String, Object> result);
  }

  private final String documentTitle;
  private final byte[] pdfBytes;
  private final CompletionCallback completionCallback;
  private final AtomicBoolean completed = new AtomicBoolean(false);
  private final Handler mainHandler = new Handler(Looper.getMainLooper());

  private volatile boolean writeCompleted;
  private volatile PrintJob printJob;

  PdfPrintDocumentAdapter(
      String documentTitle,
      byte[] pdfBytes,
      CompletionCallback completionCallback) {
    this.documentTitle = documentTitle;
    this.pdfBytes = pdfBytes;
    this.completionCallback = completionCallback;
  }

  void attachPrintJob(PrintJob printJob) {
    this.printJob = printJob;
  }

  @Override
  public void onLayout(
      PrintAttributes oldAttributes,
      PrintAttributes newAttributes,
      CancellationSignal cancellationSignal,
      LayoutResultCallback callback,
      android.os.Bundle extras) {
    if (cancellationSignal.isCanceled()) {
      callback.onLayoutCancelled();
      return;
    }
    final PrintDocumentInfo info = new PrintDocumentInfo.Builder(documentTitle)
        .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
        .setPageCount(PrintDocumentInfo.PAGE_COUNT_UNKNOWN)
        .build();
    callback.onLayoutFinished(info, !newAttributes.equals(oldAttributes));
  }

  @Override
  public void onWrite(
      PageRange[] pages,
      ParcelFileDescriptor destination,
      CancellationSignal cancellationSignal,
      WriteResultCallback callback) {
    if (cancellationSignal.isCanceled()) {
      callback.onWriteCancelled();
      return;
    }
    new Thread(() -> {
      try (FileOutputStream output = new FileOutputStream(destination.getFileDescriptor())) {
        output.write(pdfBytes);
        output.flush();
        writeCompleted = true;
        mainHandler.post(() -> callback.onWriteFinished(
            new PageRange[] {PageRange.ALL_PAGES}));
      } catch (IOException error) {
        mainHandler.post(() -> callback.onWriteFailed(error.getMessage()));
        complete(PrintResultPayload.failed("printWriteFailed", error.toString()));
      }
    }, "reporting-bridge-print-write").start();
  }

  @Override
  public void onFinish() {
    super.onFinish();
    final PrintJob currentJob = printJob;
    final int state = currentJob == null
        ? PrintJobInfo.STATE_CREATED
        : currentJob.getInfo().getState();
    complete(PrintResultMapper.fromSystemPrintState(state, writeCompleted));
  }

  private void complete(Map<String, Object> result) {
    if (!completed.compareAndSet(false, true)) {
      return;
    }
    mainHandler.post(() -> completionCallback.complete(result));
  }
}
