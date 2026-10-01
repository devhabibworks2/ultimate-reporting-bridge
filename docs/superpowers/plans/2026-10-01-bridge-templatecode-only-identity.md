# Bridge TemplateCode-Only Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `TemplateCode` the only Bridge template identity while keeping backend `id` parse-only/opaque for wire compatibility.

**Architecture:** Convert Bridge core models/cache/payloads first, then Flutter public contracts/state/controller/persistence/UI. Backend response parsing may tolerate `id`, but no Bridge selection, state, persistence, cache key, diagnostics, print metadata, or public API may expose or depend on it.

**Tech Stack:** Dart, Flutter, SharedPreferences, existing Bridge core + Flutter test suites.

**Spec:** `docs/superpowers/specs/2026-10-01-bridge-template-code-only-identity-design.md`

## Global Constraints

- Backend code/schema/API are untouched.
- Backend `id` may be parsed only at the backend wire boundary and discarded.
- `TemplateCode` is trimmed, non-empty, exact and case-sensitive.
- Missing TemplateCode fails closed; no fallback to backend id, document `meta.id`, name, or position.
- Old id-only preferences/selections are ignored; no id-to-code migration.
- `alwaysPrepare`, `alwaysSelectTemplate`, smart first-compatible, and stale-selection semantics stay the same except identity naming.
- Cache identity/file naming must be safe on case-insensitive filesystems; use a deterministic hash of exact TemplateCode rather than a case-folded filename.
- Current `main` already contains release/tag `1.0.2`; do not move/recreate that tag. This work is post-1.0.2 and the next release must be a new version (normally 1.0.3).
- No push/tag/publish in this execution. Local merge into `main` is authorized after all gates are green.

## Review Focus

- `ABC` and `abc` TemplateCodes must coexist in cache and resolve independently.
- transient catalog sync failure must preserve saved TemplateCode and recover it on a later authoritative sync.
- authoritative refresh proving saved code absent must require explicit reselection, never first-template substitution.
- code-less backend/cache templates must never become selectable or cacheable.
- external/serialized Bridge output must contain no template backend id identity fields.

---

### Task 1: Core Template Model, SelectedTemplate, and Cache Become Code-Only

**Files:**
- Modify: `packages/reporting_bridge/lib/src/bridge_template_cache.dart`
- Modify: `packages/reporting_bridge/lib/src/bridge_selected_template.dart`
- Test: corresponding core cache/selection tests under `packages/reporting_bridge/test/`

**Interfaces:**
- Produces: `CachedTemplate.templateCode` as non-null canonical identity; `SelectedTemplate(code,type,systemCode)`; `TemplateCacheService.getTemplateByCode(String)`.

- [ ] Add RED tests proving: missing code is rejected/ignored; `ABC` and `abc` coexist; cache lookup/dedup/sort is code-based; SelectedTemplate serialization contains no id; id-only selection parsing/migration is rejected.
- [ ] Remove `CachedTemplate.id` public state/constructor/toMap/search fallback. `fromMap` may read backend `id` only at parsing boundary and discard it.
- [ ] Make `templateName` fallback use explicit name -> document name -> TemplateCode -> generic non-id label.
- [ ] Make cache filename a deterministic hash of exact TemplateCode; remove id/legacy filename helpers and id migration.
- [ ] Remove `SelectedTemplate.id`, `migrateLegacyId`, and `SelectedTemplateCatalogEntry.id`; durable identity is code/system only.
- [ ] Run core focused tests and then full `packages/reporting_bridge` tests/analyzer.

### Task 2: Core Boot/Inline Payloads, Print Metadata, and Diagnostics Remove Template IDs

**Files:**
- Modify: `packages/reporting_bridge/lib/src/bridge_boot_payload.dart`
- Modify: `packages/reporting_bridge/lib/src/bridge_inline_session_payload.dart`
- Modify: relevant core status/session/serialization files found by source scan
- Modify: `packages/reporting_bridge_flutter/lib/src/contracts/external_printer_contract.dart`
- Test: matching core/flutter contract tests

**Interfaces:**
- Produces: `templateCodeHint` where a hint is needed; external print reserved key `templateCode`.

- [ ] Add RED tests proving boot/inline payloads do not parse/emit template id identity; code hints round-trip.
- [ ] Replace/remove `templateIdHint`, `templateId`, `selectedTemplateId` identity hints.
- [ ] Replace Bridge-owned print/trace metadata `templateId` with `templateCode`.
- [ ] Run affected core/flutter contract tests.

### Task 3: Flutter Public Contracts, Flow State, Controller, and UI Become Code-Only

**Files:**
- Modify: `packages/reporting_bridge_flutter/lib/src/contracts/report_open_request.dart`
- Modify: `packages/reporting_bridge_flutter/lib/src/flow/report_flow_state.dart`
- Modify: `packages/reporting_bridge_flutter/lib/src/flow/report_flow_controller.dart`
- Modify: `packages/reporting_bridge_flutter/lib/src/flow/report_flow_controller_base.dart`
- Modify: `packages/reporting_bridge_flutter/lib/src/flow/report_flow_controller_impl.dart`
- Modify: `packages/reporting_bridge_flutter/lib/src/ui/report_flow_screen.dart`
- Test: `packages/reporting_bridge_flutter/test/flow/**`, UI tests, integration tests

**Interfaces:**
- Produces: `initialTemplateCode`, `selectedTemplateCode`, `committedTemplateCode`, `ReportSettingsDraft.templateCode`, `selectTemplate(String templateCode)`.

- [ ] Rename/add RED compile/behavior tests for the code-based public contract; remove all public id aliases.
- [ ] Convert lookup helpers to compare exact `template.templateCode`.
- [ ] Preserve priority: explicit code -> saved code -> first compatible code for smart/alwaysPrepare; alwaysSelectTemplate remains manual.
- [ ] Preserve preparation/recovery/settings behavior using TemplateCode state only.
- [ ] Change UI equality/widget keys to TemplateCode.
- [ ] Run controller + UI focused suites.

### Task 4: Persistence and Request-Scoped Stale Resolution Become TemplateCode-Only

**Files:**
- Modify: `packages/reporting_bridge_flutter/lib/src/persistence/report_flow_preference_store.dart`
- Modify: `packages/reporting_bridge_flutter/lib/src/flow/report_flow_controller_impl.dart`
- Test: persistence migration/isolation/mode/stale-selection tests

**Interfaces:**
- `ReportFlowPreferences` contains `templateCode` + mode/settings only.
- Request-scoped resolver carries saved code plus authoritative-unavailable state; no synthetic id sentinel.

- [ ] Add RED tests: id-only stored records ignored; saved code wins; transient lookup sync failure preserves/re-recovers code; authoritative absence requires explicit reselection; mode-only restore never revives id selection.
- [ ] Remove `templateId` field, legacy standalone id reads, V5/id selected-template migration, and synthetic `__urb_template_code_reselection_required__`.
- [ ] Keep durable TemplateCode unresolved on transient refresh failure; only mark explicit reselection after a successful authoritative catalog proves code absent/incompatible.
- [ ] Run all persistence + controller tests.

### Task 5: Source Scan, Documentation/Version Ruling, Full Verification, Review, and Local Merge

**Files:**
- Modify: spec release wording if still targeting 1.0.2.
- No backend files.

**Interfaces:**
- Final branch must have no forbidden template-id identity concepts in production Bridge code except narrowly documented backend parse-only `raw['id']` access.

- [ ] Update spec release section from already-published 1.0.2 to post-1.0.2 / next release 1.0.3.
- [ ] Run formatter on both packages.
- [ ] Run analyzers for `reporting_bridge` and `reporting_bridge_flutter`.
- [ ] Run full tests for both packages.
- [ ] Run source scan for forbidden identity names/uses and manually classify any literal `id` occurrence.
- [ ] Run `git diff --check`.
- [ ] Perform whole-branch code review; fix all Critical/Important findings with RED->GREEN coverage.
- [ ] Commit TemplateCode-only implementation.
- [ ] Merge locally into `main`.
- [ ] Re-run both package analyzers/tests/source scan/diff check on merged `main`.
- [ ] Do not push/tag/publish. Report local main HEAD and remaining release step (new version/tag, normally 1.0.3).
