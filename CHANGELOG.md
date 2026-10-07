# Changelog

## Unreleased

## 1.0.3

- Add shared Presenter warmup/resource-preparation orchestration and the
  headless render pipeline used by direct print and PDF generation.
- Add the report-preview loading overlay and keep Presenter surface lifecycle
  handling coordinated across interactive and headless flows.
- Make development-support archive sharing work by default through
  `share_plus >=11.1.0 <14.0.0`, while preserving the Host-injected
  `ReportSupportSharePlatform` override.
- Remove the obsolete public action-policy contract and keep report actions
  governed by the effective Bridge/Host feature configuration.
- Raise public Host floors to Flutter `>=3.35.0` and Dart `>=3.9.0` (protected
  `pdfx 2.11.0` requires `vector_math` APIs shipped from Flutter 3.35+).
- Migrate default Save PDF to the common `file_picker` 11+ API and widen the
  Bridge range to `>=11.0.1 <14.0.0`.
- Keep legacy/modern Host compatibility fixtures and CI coverage; verified
  `share_plus 11.1.0` and `13.3.1` endpoints.
- Document the AGP boundary: fixtures verify on AGP 8.11.1; AGP 9 remains
  unsupported with stable `flutter_inappwebview` `6.1.5` /
  `flutter_inappwebview_android` `1.1.3` due to the removed ProGuard default
  file API.

## 1.0.2

- Add configurable PDF preview scale defaults and propagation through the
  Bridge Flutter UI.
- Auto-select the first compatible template for `smart` entry and after
  `alwaysPrepare` preparation when no saved `TemplateCode` is available.
- Preserve saved `TemplateCode` priority, stale-selection protection, and
  explicit `alwaysSelectTemplate` behavior.
- Keep template selection/recovery changes inside the Bridge; no backend
  changes are required.

## 1.0.0

- Extract `reporting_bridge` and `reporting_bridge_flutter` from Ultimate
  Report Builder into this dedicated repository.
- Keep package versions at `1.0.0` and `publish_to: none`.
- Add a minimal Flutter host example and standalone CI for both packages.
