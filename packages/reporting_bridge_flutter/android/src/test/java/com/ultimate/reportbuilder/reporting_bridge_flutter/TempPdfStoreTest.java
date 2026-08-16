package com.ultimate.reportbuilder.reporting_bridge_flutter;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.core.app.ApplicationProvider;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;

import java.io.File;
import java.nio.file.Files;

@RunWith(RobolectricTestRunner.class)
public class TempPdfStoreTest {
  private TempPdfStore store;

  @Before
  public void setUp() {
    final Context context = ApplicationProvider.getApplicationContext();
    store = new TempPdfStore(context);
    deleteRecursively(store.directory());
  }

  @After
  public void tearDown() {
    deleteRecursively(store.directory());
  }

  @Test
  public void createsAndDeletesAuthoritativePdfArtifact() throws Exception {
    final byte[] bytes = new byte[] {37, 80, 68, 70};
    final File file = store.create(bytes, "invoice.pdf", 1000L);

    assertTrue(file.exists());
    assertArrayEquals(bytes, Files.readAllBytes(file.toPath()));

    store.delete(file);
    assertFalse(file.exists());
  }

  @Test
  public void removesOnlyFilesOlderThanTtl() throws Exception {
    final File stale = store.create(new byte[] {1}, "stale.pdf", 1000L);
    final File fresh = store.create(new byte[] {2}, "fresh.pdf", 2000L);
    stale.setLastModified(1000L);
    fresh.setLastModified(2000L);

    store.cleanup(500L, 2000L);

    assertFalse(stale.exists());
    assertTrue(fresh.exists());
  }

  private static void deleteRecursively(File file) {
    if (file == null || !file.exists()) {
      return;
    }
    if (file.isDirectory()) {
      final File[] children = file.listFiles();
      if (children != null) {
        for (File child : children) {
          deleteRecursively(child);
        }
      }
    }
    file.delete();
  }
}
