# Android platform-print integration

`ReportingBridgeFlutter` manages Android print composition when `printPlatform` is omitted.

- Default: `androidPrintConfiguration: const AndroidPrintConfiguration.escPos()`.
- ESC/POS uses the managed thermal print platform and thermal printer settings/profile flow.
- Opt into System Print Manager or external-app mode with `androidPrintConfiguration`; there is no automatic fallback across Android modes.
- An explicit `printPlatform` override always wins and bypasses managed composition.
- Web and other unsupported targets fail closed to `UnsupportedReportPrintPlatform`.

## Managed defaults

```dart
final bridge = ReportingBridgeFlutter(
  connection: connection,
  // androidPrintConfiguration defaults to AndroidPrintConfiguration.escPos()
);
```

## Opt-in System Print Manager

```dart
final bridge = ReportingBridgeFlutter(
  connection: connection,
  androidPrintConfiguration: const AndroidPrintConfiguration.systemPrintManager(),
);
```

## Explicit host override

```dart
final bridge = ReportingBridgeFlutter(
  connection: connection,
  printPlatform: AndroidReportPrintPlatform(
    configuration: const AndroidPrintConfiguration.systemPrintManager(),
  ),
);
```

When you inject `printPlatform`, Bridge does not create or dispose managed thermal/Android resources for that override. Dispose any host-owned platform yourself.

## External-app mode (V1 contract)

For external-app mode, provide the approved install URI through `AndroidPrintConfiguration.externalApp(...)` (managed) or an explicit `AndroidReportPrintPlatform` override. The adapter returns `setupRequired` after opening that URI, re-checks the explicit package/action when the app resumes, and invokes `onDeferredResult` after the deferred print attempt. There is still no fallback into ESC/POS or System Print Manager.

The package manifest contributes its private `FileProvider` and the V1 package-visibility query. Motakamel native files do not need changes.

For managed platforms, Bridge disposes owned resources when the client is disposed. For an explicit override, call `dispose()` on the host-owned platform when the owning Bridge runtime is disposed.
