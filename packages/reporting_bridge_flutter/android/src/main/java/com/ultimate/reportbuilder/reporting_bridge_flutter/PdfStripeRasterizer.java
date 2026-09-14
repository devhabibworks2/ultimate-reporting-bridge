package com.ultimate.reportbuilder.reporting_bridge_flutter;

import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.Rect;
import android.graphics.pdf.PdfRenderer;
import android.os.ParcelFileDescriptor;

import androidx.annotation.NonNull;

import com.dantsu.escposprinter.EscPosPrinterCommands;
import com.dantsu.escposprinter.connection.DeviceConnection;

import java.io.File;
import java.io.IOException;

/** Renders one bounded ARGB bitmap at a time and sends it as ESC/POS raster. */
final class PdfStripeRasterizer {
  private static final int MAX_BITMAP_BYTES = 1024 * 1024;

  interface Progress {
    void onPrinting(int copyIndex, int copyCount, int pageIndex, int pageCount);
  }

  private PdfStripeRasterizer() {}

  static void print(
      @NonNull File pdf,
      @NonNull DeviceConnection connection,
      int printableWidthPx,
      int copies,
      boolean gradient,
      int feedDots,
      boolean cutAfterPrint,
      boolean useEscAsteriskCommand,
      @NonNull Progress progress) throws Exception {
    if (printableWidthPx <= 0) throw new IOException("invalidRasterWidth");
    try (ParcelFileDescriptor descriptor = ParcelFileDescriptor.open(
            pdf, ParcelFileDescriptor.MODE_READ_ONLY);
        PdfRenderer renderer = new PdfRenderer(descriptor)) {
      final int pageCount = renderer.getPageCount();
      if (pageCount <= 0) throw new IOException("emptyPdf");
      final EscPosPrinterCommands commands = new EscPosPrinterCommands(connection);
      commands.useEscAsteriskCommand(useEscAsteriskCommand);
      for (int copy = 1; copy <= copies; copy++) {
        for (int pageIndex = 0; pageIndex < pageCount; pageIndex++) {
          progress.onPrinting(copy, copies, pageIndex + 1, pageCount);
          try (PdfRenderer.Page page = renderer.openPage(pageIndex)) {
            printPage(page, printableWidthPx, gradient, commands);
          }
        }
        if (feedDots > 0) commands.feedPaper(feedDots);
        if (cutAfterPrint) commands.cutPaper();
      }
    }
  }

  private static void printPage(
      @NonNull PdfRenderer.Page page,
      int printableWidthPx,
      boolean gradient,
      @NonNull EscPosPrinterCommands commands) throws Exception {
    final float scale = printableWidthPx / (float) page.getWidth();
    final int renderedHeight = Math.max(1, (int) Math.ceil(page.getHeight() * scale));
    final int stripeHeight = Math.max(
        1,
        Math.min(renderedHeight, MAX_BITMAP_BYTES / Math.max(4, printableWidthPx * 4)));
    for (int top = 0; top < renderedHeight; top += stripeHeight) {
      final int height = Math.min(stripeHeight, renderedHeight - top);
      final Bitmap bitmap = Bitmap.createBitmap(
          printableWidthPx, height, Bitmap.Config.ARGB_8888);
      try {
        bitmap.eraseColor(Color.WHITE);
        final Matrix matrix = new Matrix();
        matrix.setScale(scale, scale);
        matrix.postTranslate(0, -top);
        page.render(
            bitmap,
            new Rect(0, 0, printableWidthPx, height),
            matrix,
            PdfRenderer.Page.RENDER_MODE_FOR_PRINT);
        commands.printImage(EscPosPrinterCommands.bitmapToBytes(bitmap, gradient));
      } finally {
        bitmap.recycle();
      }
    }
  }
}
