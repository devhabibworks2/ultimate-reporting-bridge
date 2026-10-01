# Changelog

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
