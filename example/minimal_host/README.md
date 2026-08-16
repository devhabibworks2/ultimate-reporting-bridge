# Minimal Host

Thin Flutter sample that depends on `reporting_bridge_flutter` and opens one
report. It is not the Motakamel or Demo ERP host.

```bash
flutter pub get
flutter run --dart-define=HOST_SERVER_URL=https://mdev.yemensoft.net:473
```

The Host supplies a Report Server URL, a tiny inline seed map, and calls
`ReportingBridgeFlutterClient.openReport`.
