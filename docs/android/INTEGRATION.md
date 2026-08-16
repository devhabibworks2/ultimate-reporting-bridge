# Android platform-print integration

Use `AndroidReportPrintPlatform` as `ReportFlowRuntime.printPlatform`.

Initial Motakamel configuration:

```dart
final printPlatform = AndroidReportPrintPlatform(
  configuration: const AndroidPrintConfiguration.systemPrintManager(),
);
```

The package manifest contributes its private `FileProvider` and the V1 package-visibility query. Motakamel native files do not need changes.

For the future external-app mode, provide the approved install URI and a Bridge-owned prompt callback. The adapter returns `setupRequired` after opening that URI, re-checks the explicit package/action when the app resumes, and invokes `onDeferredResult` after the deferred print attempt.

Call `dispose()` when the owning Bridge runtime is disposed.
