# Host integration

A Host application supplies business inputs and opens one report through
`reporting_bridge_flutter`. The Host must not own WebView, Presenter
synchronization, template cache, Settings, or PDF export.

## Host supplies

- Report Server URL and profile (`deployed` or `localDevelopment`)
- System code and report type
- Immutable runtime or seed JSON
- Locale
- Optional UI configuration and an approved dynamic-header provider

## Host calls

```dart
await client.openReport(context, request);
```

Headless or custom UI uses the same controller:

```dart
final controller = client.createController(request);
```

## Do not implement in the Host

- Presenter WebView
- Template or Presenter cache
- Duplicate Settings or PDF Save/Share workflows
- Direct Presenter HTTP calls

See `docs/architecture/bridge-contract.md` and
`docs/architecture/adr-0001-flow-ownership.md`.
