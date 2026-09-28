# iOS platform-print integration

`ReportingBridgeFlutter` manages iOS print composition when `printPlatform` is omitted.

- Default: `iosPrintMode: IosPrintMode.airPrint`.
- An explicit `printPlatform` override always wins and bypasses managed composition.
- Web and other unsupported targets fail closed to `UnsupportedReportPrintPlatform`.

## Managed default (AirPrint)

```dart
final bridge = ReportingBridgeFlutter(
  connection: connection,
  // iosPrintMode defaults to IosPrintMode.airPrint
);
```

## Explicit host override

```dart
final bridge = ReportingBridgeFlutter(
  connection: connection,
  printPlatform: const IosAirPrintReportPrintPlatform(),
);
```

The AirPrint adapter uses the existing `printing` package to invoke native AirPrint. It passes the authoritative PDF bytes directly to the print callback and has no external-application dependency.
