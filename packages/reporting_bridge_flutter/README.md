# reporting_bridge_flutter

Flutter integration layer for Ultimate Report Builder. It owns Preparation,
Template Selection, Presenter preparation, Preview, Settings, PDF Save/Share,
preferences, and route lifecycle. `reporting_bridge` remains the Dart/IO core.

Hosts can use `ReportingBridgeFlutterClient.openReport` for the default Material
flow or `createController` with `BridgePresenterView` for a headless/custom UI.
Only one report flow may be active per client.

## Default flow

1. Preparation checks compatible Templates and local Presenter readiness.
2. Online/offline mode is selected before Template Selection.
3. Template Selection preserves server order and supports localized search.
4. Preview waits for typed Presenter render completion before enabling export.
5. Settings reuses Template Selection with draft/committed values.

The Host supplies only connection, system, report type, seed JSON, locale, and
optional feature/theme configuration.

## Developer diagnostics

Bridge diagnostics are opt-in and disabled by default. During development, a
Host can enable structured console traces on the canonical connection:

```dart
final connection = ReportServerConnection(
  endpoints: endpoints,
  cacheRoot: cacheRoot,
  diagnostics: BridgeDiagnostics.console(),
);
```

The trace uses stable categories such as `API`, `FLOW`, and `PRINT`. API entries
include operation, HTTP method, safe URI, duration, and failures. Print entries
include the selected report/template metadata and returned print status. Flow
failures include the Bridge failure code and diagnostic.

Bridge-owned API logs never print request/response bodies, seed data, PDF bytes,
Authorization/header values, URI user-info, fragments, or query values. Query
parameter names are retained while their values are rendered as `<redacted>`.
For production telemetry, provide `BridgeDiagnostics(sink: ...)` and apply any
additional Host-specific redaction required by the application.
