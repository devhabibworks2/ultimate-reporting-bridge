package com.ultimate.reportbuilder.reporting_bridge_flutter;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ResolveInfo;
import android.net.Uri;
import android.print.PrintJob;
import android.print.PrintManager;

import androidx.annotation.NonNull;
import androidx.core.content.FileProvider;

import java.io.File;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

public final class ReportingBridgeFlutterPlugin implements
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener,
    PluginRegistry.RequestPermissionsResultListener {

  private MethodChannel channel;
  private Context applicationContext;
  private Activity activity;
  private TempPdfStore tempPdfStore;
  private ActivityPluginBinding activityBinding;
  private PrinterPermissionCoordinator printerPermissionCoordinator;
  private ThermalPrinterApiHandler thermalPrinterApiHandler;
  private final ExternalPrintIntentFactory externalIntentFactory =
      new ExternalPrintIntentFactory();

  private MethodChannel.Result pendingExternalResult;
  private File pendingExternalFile;
  private Uri pendingExternalUri;
  private String pendingExternalPackage;
  private boolean systemPrintActive;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    applicationContext = binding.getApplicationContext();
    tempPdfStore = new TempPdfStore(applicationContext);
    tempPdfStore.cleanup(
        PrintContract.DEFAULT_STALE_FILE_TTL_MILLIS,
        System.currentTimeMillis());
    channel = new MethodChannel(binding.getBinaryMessenger(), PrintContract.CHANNEL);
    channel.setMethodCallHandler(this);
    printerPermissionCoordinator = new PrinterPermissionCoordinator(applicationContext);
    thermalPrinterApiHandler = new ThermalPrinterApiHandler(
        applicationContext, binding.getBinaryMessenger(), printerPermissionCoordinator);
    thermalPrinterApiHandler.setUp();
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    detachActivityBinding();
    if (channel != null) {
      channel.setMethodCallHandler(null);
      channel = null;
    }
    failPendingExternal("pluginDetached", null);
    if (thermalPrinterApiHandler != null) {
      thermalPrinterApiHandler.tearDown();
      thermalPrinterApiHandler = null;
    }
    if (printerPermissionCoordinator != null) {
      printerPermissionCoordinator.detach();
      printerPermissionCoordinator = null;
    }
    applicationContext = null;
    tempPdfStore = null;
  }

  @Override
  public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
    activity = binding.getActivity();
    attachActivityBinding(binding);
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    detachActivityBinding();
  }

  @Override
  public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
    activity = binding.getActivity();
    attachActivityBinding(binding);
  }

  @Override
  public void onDetachedFromActivity() {
    detachActivityBinding();
  }

  private void attachActivityBinding(@NonNull ActivityPluginBinding binding) {
    activityBinding = binding;
    binding.addActivityResultListener(this);
    binding.addRequestPermissionsResultListener(this);
    if (printerPermissionCoordinator != null) {
      printerPermissionCoordinator.attach(binding.getActivity());
    }
  }

  private void detachActivityBinding() {
    final ActivityPluginBinding binding = activityBinding;
    if (binding != null) {
      binding.removeActivityResultListener(this);
      binding.removeRequestPermissionsResultListener(this);
    }
    activityBinding = null;
    activity = null;
    if (printerPermissionCoordinator != null) printerPermissionCoordinator.detach();
  }

  @Override
  public boolean onRequestPermissionsResult(
      int requestCode,
      @NonNull String[] permissions,
      @NonNull int[] grantResults) {
    return printerPermissionCoordinator != null &&
        printerPermissionCoordinator.onRequestPermissionsResult(
            requestCode, permissions, grantResults);
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
    final Map<String, Object> arguments = arguments(call, result);
    if (arguments == null) {
      return;
    }
    try {
      switch (call.method) {
        case "printSystem":
          printSystem(arguments, result);
          break;
        case "isExternalAppInstalled":
          result.success(isExternalAppInstalled(arguments));
          break;
        case "printExternal":
          printExternal(arguments, result);
          break;
        case "openInstallUri":
          result.success(openInstallUri(arguments));
          break;
        case "cleanupStaleFiles":
          cleanupStaleFiles(arguments);
          result.success(null);
          break;
        default:
          result.notImplemented();
      }
    } catch (IllegalArgumentException error) {
      result.success(PrintResultPayload.unsupportedContract(
          "invalidPrintArguments",
          error.getMessage()));
    } catch (Exception error) {
      result.success(PrintResultPayload.failed(
          "nativePrintFailure",
          error.toString()));
    }
  }

  private void printSystem(
      Map<String, Object> arguments,
      MethodChannel.Result result) {
    if (systemPrintActive) {
      result.success(PrintResultPayload.failed("printInProgress", null));
      return;
    }
    final Activity currentActivity = activity;
    if (currentActivity == null) {
      result.success(PrintResultPayload.failed("activityUnavailable", null));
      return;
    }
    final byte[] bytes = requiredBytes(arguments, "pdfBytes");
    final int maximumBytes = positiveInt(
        arguments,
        "maximumPdfBytes",
        PrintContract.DEFAULT_MAXIMUM_PDF_BYTES);
    if (bytes.length > maximumBytes) {
      result.success(PrintResultPayload.failed("pdfTooLarge", null));
      return;
    }

    final String documentTitle = requiredString(arguments, "documentTitle");
    final PrintManager printManager =
        (PrintManager) currentActivity.getSystemService(Context.PRINT_SERVICE);
    if (printManager == null) {
      result.success(PrintResultPayload.failed("printManagerUnavailable", null));
      return;
    }

    systemPrintActive = true;
    final PdfPrintDocumentAdapter adapter = new PdfPrintDocumentAdapter(
        documentTitle,
        bytes,
        payload -> {
          systemPrintActive = false;
          result.success(payload);
        });
    try {
      final PrintJob printJob = printManager.print(documentTitle, adapter, null);
      adapter.attachPrintJob(printJob);
    } catch (Exception error) {
      systemPrintActive = false;
      result.success(PrintResultPayload.failed(
          "printManagerInvocationFailed",
          error.toString()));
    }
  }

  private boolean isExternalAppInstalled(Map<String, Object> arguments) {
    validateV1Identity(arguments);
    final Intent intent = externalIntentFactory.createResolutionIntent(
        requiredString(arguments, "packageName"),
        requiredString(arguments, "action"),
        requiredString(arguments, "mimeType"));
    final ResolveInfo resolved = applicationContext
        .getPackageManager()
        .resolveActivity(intent, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY);
    return resolved != null
        && resolved.activityInfo != null
        && PrintContract.EXTERNAL_PACKAGE.equals(resolved.activityInfo.packageName);
  }

  private void printExternal(
      Map<String, Object> arguments,
      MethodChannel.Result result) throws Exception {
    if (pendingExternalResult != null) {
      result.success(PrintResultPayload.failed("printInProgress", null));
      return;
    }
    final Activity currentActivity = activity;
    if (currentActivity == null) {
      result.success(PrintResultPayload.failed("activityUnavailable", null));
      return;
    }

    validateV1Identity(arguments);
    validateExternalContract(arguments);
    final byte[] bytes = requiredBytes(arguments, "pdfBytes");
    final int maximumBytes = positiveInt(
        arguments,
        "maximumPdfBytes",
        PrintContract.DEFAULT_MAXIMUM_PDF_BYTES);
    if (bytes.length > maximumBytes) {
      result.success(PrintResultPayload.failed("pdfTooLarge", null));
      return;
    }

    final long ttlMillis = positiveLong(
        arguments,
        "staleFileTtlMillis",
        PrintContract.DEFAULT_STALE_FILE_TTL_MILLIS);
    tempPdfStore.cleanup(ttlMillis, System.currentTimeMillis());

    if (!isExternalAppInstalled(arguments)) {
      result.success(PrintResultPayload.appNotInstalled());
      return;
    }

    final File file = tempPdfStore.create(
        bytes,
        requiredString(arguments, "filename"),
        System.currentTimeMillis());
    final String authority = applicationContext.getPackageName()
        + ".reporting_bridge_flutter.fileprovider";
    final Uri contentUri = FileProvider.getUriForFile(
        applicationContext,
        authority,
        file);
    final Intent intent = externalIntentFactory.createPrintIntent(contentUri, arguments);
    final String packageName = requiredString(arguments, "packageName");

    applicationContext.grantUriPermission(
        packageName,
        contentUri,
        Intent.FLAG_GRANT_READ_URI_PERMISSION);
    pendingExternalResult = result;
    pendingExternalFile = file;
    pendingExternalUri = contentUri;
    pendingExternalPackage = packageName;
    try {
      currentActivity.startActivityForResult(
          intent,
          PrintContract.EXTERNAL_PRINT_REQUEST_CODE);
    } catch (Exception error) {
      clearPendingExternal();
      result.success(PrintResultPayload.failed(
          "externalPrinterInvocationFailed",
          error.toString()));
    }
  }

  private boolean openInstallUri(Map<String, Object> arguments) {
    final Uri installUri = Uri.parse(requiredString(arguments, "installUri"));
    final Intent intent = new Intent(Intent.ACTION_VIEW, installUri);
    final Activity currentActivity = activity;
    if (currentActivity != null) {
      if (intent.resolveActivity(currentActivity.getPackageManager()) == null) {
        return false;
      }
      currentActivity.startActivity(intent);
      return true;
    }
    if (intent.resolveActivity(applicationContext.getPackageManager()) == null) {
      return false;
    }
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    applicationContext.startActivity(intent);
    return true;
  }

  private void cleanupStaleFiles(Map<String, Object> arguments) {
    final long ttlMillis = positiveLong(
        arguments,
        "staleFileTtlMillis",
        PrintContract.DEFAULT_STALE_FILE_TTL_MILLIS);
    tempPdfStore.cleanup(ttlMillis, System.currentTimeMillis());
  }

  @Override
  public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
    if (requestCode != PrintContract.EXTERNAL_PRINT_REQUEST_CODE
        || pendingExternalResult == null) {
      return false;
    }
    final MethodChannel.Result result = pendingExternalResult;
    final Map<String, Object> payload =
        PrintResultMapper.fromExternalActivityResult(resultCode);
    clearPendingExternal();
    result.success(payload);
    return true;
  }

  private void validateV1Identity(Map<String, Object> arguments) {
    if (!PrintContract.EXTERNAL_PACKAGE.equals(requiredString(arguments, "packageName"))) {
      throw new IllegalArgumentException("V1 packageName mismatch");
    }
    if (!PrintContract.EXTERNAL_ACTION.equals(requiredString(arguments, "action"))) {
      throw new IllegalArgumentException("V1 action mismatch");
    }
    if (!PrintContract.MIME_TYPE.equals(requiredString(arguments, "mimeType"))) {
      throw new IllegalArgumentException("V1 mimeType mismatch");
    }
  }

  private void validateExternalContract(Map<String, Object> arguments) {
    if (!PrintContract.CONTRACT_VERSION.equals(
        requiredString(arguments, "contractVersion"))) {
      throw new IllegalArgumentException("Unsupported contractVersion");
    }
    requiredString(arguments, "jobId");
    requiredString(arguments, "documentTitle");
    requiredString(arguments, "unit");
    requiredString(arguments, "layout");
    requiredString(arguments, "size");
    requiredNumber(arguments, "width");
    requiredNumber(arguments, "height");
    requiredString(arguments, "orientation");
    final String languageCode = requiredString(arguments, "language_code");
    final int language = requiredNumber(arguments, "language").intValue();
    if (!("ar".equals(languageCode) && language == 1)
        && !("en".equals(languageCode) && language == 2)) {
      throw new IllegalArgumentException("Unsupported language mapping");
    }

    final Object extraValue = arguments.get("extra");
    if (!(extraValue instanceof Map)) {
      throw new IllegalArgumentException("extra must be a map");
    }
    @SuppressWarnings("unchecked")
    final Map<Object, Object> extra = (Map<Object, Object>) extraValue;
    for (Object key : extra.keySet()) {
      if (!(key instanceof String)) {
        throw new IllegalArgumentException("extra keys must be strings");
      }
      if (PrintContract.RESERVED_EXTRA_FIELDS.contains(key)) {
        throw new IllegalArgumentException("Reserved extra field: " + key);
      }
    }
  }

  private void failPendingExternal(String errorCode, String diagnostic) {
    if (pendingExternalResult == null) {
      return;
    }
    final MethodChannel.Result result = pendingExternalResult;
    clearPendingExternal();
    result.success(PrintResultPayload.failed(errorCode, diagnostic));
  }

  private void clearPendingExternal() {
    if (pendingExternalUri != null && pendingExternalPackage != null
        && applicationContext != null) {
      try {
        applicationContext.revokeUriPermission(
            pendingExternalUri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION);
      } catch (Exception ignored) {
        // Best effort. The URI is backed by a non-exported provider.
      }
    }
    if (tempPdfStore != null) {
      tempPdfStore.delete(pendingExternalFile);
    }
    pendingExternalResult = null;
    pendingExternalFile = null;
    pendingExternalUri = null;
    pendingExternalPackage = null;
  }

  @SuppressWarnings("unchecked")
  private static Map<String, Object> arguments(
      MethodCall call,
      MethodChannel.Result result) {
    if (!(call.arguments instanceof Map)) {
      result.success(PrintResultPayload.unsupportedContract(
          "invalidPrintArguments",
          "Arguments must be a map"));
      return null;
    }
    return (Map<String, Object>) call.arguments;
  }

  private static byte[] requiredBytes(Map<String, Object> arguments, String key) {
    final Object value = arguments.get(key);
    if (!(value instanceof byte[]) || ((byte[]) value).length == 0) {
      throw new IllegalArgumentException("Missing or invalid " + key);
    }
    return (byte[]) value;
  }

  private static String requiredString(Map<String, Object> arguments, String key) {
    final Object value = arguments.get(key);
    if (!(value instanceof String) || ((String) value).trim().isEmpty()) {
      throw new IllegalArgumentException("Missing or invalid " + key);
    }
    return (String) value;
  }

  private static Number requiredNumber(Map<String, Object> arguments, String key) {
    final Object value = arguments.get(key);
    if (!(value instanceof Number)) {
      throw new IllegalArgumentException("Missing or invalid " + key);
    }
    return (Number) value;
  }

  private static int positiveInt(
      Map<String, Object> arguments,
      String key,
      int fallback) {
    final Object value = arguments.get(key);
    final int number = value instanceof Number ? ((Number) value).intValue() : fallback;
    if (number <= 0) {
      throw new IllegalArgumentException(key + " must be greater than zero");
    }
    return number;
  }

  private static long positiveLong(
      Map<String, Object> arguments,
      String key,
      long fallback) {
    final Object value = arguments.get(key);
    final long number = value instanceof Number ? ((Number) value).longValue() : fallback;
    if (number <= 0) {
      throw new IllegalArgumentException(key + " must be greater than zero");
    }
    return number;
  }
}
