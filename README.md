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

## Host compatibility

| Item | Supported |
| --- | --- |
| Minimum Flutter | `3.35.0` |
| Minimum Dart | `3.9.0` |
| Current verified Flutter | `3.44.6` |
| Latest stable | CI `channel: stable` (authoritative tip-of-tree) |
| `file_picker` | `>=11.0.1 <14.0.0` |
| `share_plus` | `>=11.1.0 <14.0.0`; Bridge default support sharing + Host-compatible resolution |

The Host and Bridge resolve one compatible package version. Older Hosts can stay on the lower compatible release inside each range; newer Hosts can take newer releases that still satisfy the Bridge constraints.

**`file_picker` 10.x is not supported.** The public Save PDF API changed in `file_picker` 11. Hosts locked to 10.x need either a Host-provided `ReportFilePlatform` or a separate compatibility task.

**Android Gradle Plugin:** compatibility fixtures and `example/minimal_host` verify on **AGP 8.11.1**. **AGP 9 is not supported** on the stable `flutter_inappwebview` path Hosts resolve from `flutter_inappwebview: ">=6.1.5 <7.0.0"` (stable `6.1.5` pulls `flutter_inappwebview_android 1.1.3`, which still calls the removed `getDefaultProguardFile('proguard-android.txt')` API). Do not treat an AGP 8.x green build as AGP 9 proof.

Local Host compatibility checks:

```bash
bash tool/verify_host_compatibility.sh legacy   # file_picker 11 / share_plus 11
bash tool/verify_host_compatibility.sh modern   # file_picker 13 / share_plus 13
```

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
