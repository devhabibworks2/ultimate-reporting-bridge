# ADR 0001: Reporting Bridge Flutter owns the report workflow

- **Status:** Accepted
- **Scope:** Host applications, `reporting_bridge`, `reporting_bridge_flutter`, Presenter

## Decision

`reporting_bridge` remains the Dart/IO transport, cache, runtime-session, and Presenter protocol core. It must not import Flutter UI libraries.

`reporting_bridge_flutter` owns the reusable mobile report workflow:

1. resource preparation;
2. template selection;
3. Presenter mode selection;
4. Preview lifecycle;
5. report Settings;
6. Save PDF and Share;
7. scoped default persistence;
8. route close, Back, cleanup, and recovery behavior.

A host application owns only business input selection: Report Server connection, system, report type, runtime/seed data, locale, and optional UI configuration. It opens a report with `ReportingBridgeFlutterClient.openReport(...)` or uses the same controller in headless mode.

Presenter owns report rendering and sends typed render lifecycle events. WebView page progress is visual feedback only and must not authorize PDF export.

## Consequences

- The Demo app must not implement duplicate setup, Preview, Settings, export, cache, WebView, or Presenter synchronization workflows.
- Only one report flow may be active per Flutter Bridge client.
- Dynamic privileged headers are resolved immediately before each core network operation and are never exposed to UI state or logs.
- Template and Presenter-mode defaults are scoped by normalized server/profile/ports, system, and report type.
- Settings uses draft values and commits only after the replacement Preview session and preference write succeed.
- Android and iOS are the v1 targets. macOS and Windows are experimental; web and Linux host workflows are unsupported in v1.
