# iOS platform-print integration

Use `IosAirPrintReportPrintPlatform` as `ReportFlowRuntime.printPlatform`.

```dart
const printPlatform = IosAirPrintReportPrintPlatform();
```

The adapter uses the existing `printing` package to invoke native AirPrint. It passes the authoritative PDF bytes directly to the print callback and has no external-application dependency.
