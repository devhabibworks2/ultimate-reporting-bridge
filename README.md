# Ultimate Reporting Bridge

Host–Presenter bridge for Ultimate Report Builder.

This repository owns:

- `packages/reporting_bridge` — Dart/IO transport, cache, runtime session, and Presenter protocol
- `packages/reporting_bridge_flutter` — Flutter workflow UI and Android print plugin
- `example/minimal_host` — thin Host sample that calls `openReport`

Presenter and the Motakamel ERP host stay in their own repositories. The Demo ERP host remains in Ultimate Report Builder.

## Packages

```text
packages/reporting_bridge
packages/reporting_bridge_flutter   # path: ../reporting_bridge
```

Both packages use `publish_to: none`. Consume them with a Git path dependency:

```yaml
reporting_bridge_flutter:
  git:
    url: https://github.com/devhabibworks2/ultimate-reporting-bridge.git
    ref: <FULL_40_CHAR_SHA>
    path: packages/reporting_bridge_flutter
```

Do not add a second direct `reporting_bridge` dependency unless the consumer imports the core package. Pub resolves the sibling core package from the same Git checkout.

Ultimate Report Builder consumes this repo as a git submodule at `ultimate-reporting-bridge/`.

## Local development

```bash
cd packages/reporting_bridge
dart pub get
dart analyze
dart test

cd ../reporting_bridge_flutter
flutter pub get
flutter analyze
flutter test

cd ../../example/minimal_host
flutter pub get
flutter run --dart-define=HOST_SERVER_URL=https://mdev.yemensoft.net:473
```

## Docs

- [Architecture / contract](docs/architecture/bridge-contract.md)
- [Flow ownership ADR](docs/architecture/adr-0001-flow-ownership.md)
- [Host integration](docs/integration/host-integration.md)
- [Android print](docs/android/INTEGRATION.md)
- [iOS print](docs/ios/INTEGRATION.md)
