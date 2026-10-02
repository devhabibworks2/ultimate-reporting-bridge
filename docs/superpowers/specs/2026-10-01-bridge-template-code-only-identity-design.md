# Bridge TemplateCode-Only Identity Design

**Date:** 2026-10-01
**Repository:** `ultimate-reporting-bridge`
**Scope:** `packages/reporting_bridge` and `packages/reporting_bridge_flutter` only

## Intent

The Bridge must use **TemplateCode as the only template identity** everywhere it makes a decision or exposes template selection state. Backend template `id` remains a wire-format field that the Bridge may encounter while parsing backend responses, but it is opaque and must not be retained, matched, persisted, logged, displayed, used as a cache key, or exposed as template identity.

The backend is unchanged. This is a Bridge-only breaking identity cleanup.

Success means:

- Host/Bridge public contracts accept and expose TemplateCode, not template id.
- selection, saved defaults, smart entry, `alwaysPrepare`, `alwaysSelectTemplate`, settings drafts, and preview state all use TemplateCode;
- cache storage and template lookup use TemplateCode;
- stale-selection handling preserves TemplateCode without synthetic id sentinels;
- external print metadata carries `templateCode`, not `templateId`;
- lower-level Bridge selected-template state is code-based only;
- no Bridge behavior falls back to backend id when TemplateCode is absent;
- templates without a usable TemplateCode fail closed and cannot become selectable;
- backend code is not modified.

## Terminology

### TemplateCode

`TemplateCode` is the trimmed, non-empty business identity of a template. The Bridge resolves it in this order: top-level backend/template `code`, then `document.meta.code`. Whitespace is trimmed, original case is preserved, and comparisons are exact/case-sensitive to preserve current code semantics. Within the active system/query scope it is the only identity used by Bridge logic.

### Backend template id

The backend may continue to return an `id` field. The Bridge parser may accept that field for wire compatibility, but it is **parse-only and opaque**:

- no public Bridge API exposes it as template identity;
- no runtime state stores it as selected/committed identity;
- no persistence writes or reads it;
- no matching, sorting, deduplication, cache naming, search, diagnostics, print metadata, or selection logic uses it;
- no legacy id-only selection is migrated;
- no fallback uses it when TemplateCode is absent.

An implementation may read `raw['id']` only at the wire parsing boundary if needed to tolerate the backend shape. It must not flow beyond that boundary.

## Architecture

### 1. Canonical template model

`CachedTemplate` becomes code-addressed.

- A selectable/cacheable template must have a trimmed, non-empty TemplateCode.
- The canonical public identity property is the non-null `templateCode`.
- `CachedTemplate.id` and its public constructor parameter are removed. `CachedTemplate.fromMap` may read backend `raw['id']` only to tolerate the wire shape, then discards it; `CachedTemplate.toMap` does not emit it.
- `templateName` fallback must never return backend id. Use explicit name, document metadata name, TemplateCode, then a non-id generic fallback.
- searchable metadata excludes backend id.
- `SelectedTemplate` contains `type`, `code`, and `systemCode`; it has no id field or id fallback.
- `SelectedTemplate.durableIdentity` is `systemCode:code` when system scope is present, otherwise code; it never falls back to id.

If TemplateCode is missing from a freshly synchronized backend catalog item, that catalog response is invalid and synchronization fails through the existing template-catalog-invalid error path. For pre-existing local cache files, entries without TemplateCode are ignored/discarded during cache enumeration. The Bridge never synthesizes identity from backend id, array position, name, or document `meta.id`.

### 2. Catalog validation and cache

Catalog synchronization validates TemplateCode rather than backend id.

- duplicate detection is by trimmed, exact/case-sensitive TemplateCode in the active system scope;
- validation/error messages identify a template by code or catalog index, never backend id;
- cache file naming is derived from TemplateCode;
- cache maps/deduplication are keyed by TemplateCode;
- deterministic cache ordering is by TemplateCode;
- cache lookup API is `getTemplateByCode(String templateCode)`; id lookup is removed;
- old id-specific cache filename helpers and id-keyed cache migration logic are removed;
- namespace/cache migration uses TemplateCode when carrying valid cached templates forward.

Existing cache files may be read only insofar as they contain a genuine TemplateCode. Their backend id is ignored. A cache entry without TemplateCode is discarded rather than migrated by id.

### 3. Selected-template persistence

Persistent selection is TemplateCode-only.

`ReportFlowPreferences` keeps `templateCode` and mode/settings fields; `templateId` is removed.

The SharedPreferences store:

- writes only the code-based selected-template record;
- reads only code-based selected-template records plus independent mode/settings data;
- does not read, resolve, or migrate V5/id-only selected-template records;
- does not use standalone legacy template-id keys;
- treats old id-only selection data as nonexistent selection.

Old id-only keys may remain physically present in user storage; they are ignored. The next successful code-based selection writes the current code-based record. No backend change or id-to-code lookup is performed to migrate them.

### 4. Runtime preference resolution and stale selection

The current synthetic runtime id (`__urb_template_code_reselection_required__`) is removed because runtime identity is no longer represented by an id field.

The request-scoped preference layer must preserve the durable TemplateCode it loaded. Resolution has two independent pieces of state:

1. the stored TemplateCode;
2. whether an authoritative catalog refresh proved that code unavailable for the active request.

Behavior:

- code resolves in current/just-refreshed compatible catalog -> select that template;
- lookup cannot refresh because of a transient sync failure -> retain the code as unresolved; do not replace it with another template and do not erase it;
- a later authoritative sync returns that code -> recover it automatically;
- authoritative sync succeeds but code is absent/incompatible -> require explicit reselection for that request; do not silently choose the first template;
- no stored/default code -> smart/alwaysPrepare may choose the first compatible TemplateCode according to the approved entry policy.

This removes the current failure mode where a transient lookup replaces the durable identity with an id-shaped sentinel.

### 5. Flutter public flow contracts

Public and internal flow names become code-based:

- `ReportOpenRequest.initialTemplateId` -> `initialTemplateCode`;
- `ReportFlowState.selectedTemplateId` -> `selectedTemplateCode`;
- `ReportFlowState.committedTemplateId` -> `committedTemplateCode`;
- `ReportSettingsDraft.templateId` -> `templateCode`;
- `ReportFlowController.selectTemplate(String templateId)` -> `selectTemplate(String templateCode)`;
- all helpers such as `_validTemplateId`, `_templateById`, and `_resolveTemplateAfterSync` become TemplateCode-based;
- UI selection equality and widget keys use TemplateCode;
- diagnostic state and test fixtures expose code, not backend id.

`CachedTemplate` lookup from these fields compares only TemplateCode.

### 6. Entry policies after conversion

The already-approved entry-policy behavior remains, but all identity checks use TemplateCode.

Priority for `smart`:

1. valid explicit `initialTemplateCode`;
2. valid saved TemplateCode;
3. first compatible template's TemplateCode when no saved/default code exists;
4. no selection when no compatible coded template exists.

`alwaysPrepare`:

- Preparation remains mandatory;
- the same priority resolves/preselects a TemplateCode;
- Continue goes directly to Preview when a valid template is selected;
- stale saved code still requires explicit reselection.

`alwaysSelectTemplate`:

- manual selection remains mandatory;
- no first-compatible bypass;
- any optional preselection is code-based only.

### 7. Bridge core selected-template and payload contracts

`SelectedTemplate` is code-only. Remove legacy-id migration APIs and catalog-entry id matching.

`BridgeBootPayload`:

- remove `templateIdHint` and any parsing of `templateId` / `selectedTemplateId` as identity hints;
- if a hint is needed, expose `templateCodeHint` and read only code-shaped fields;
- id-only selected-template payloads do not create a selected template.

`BridgeInlineSessionPayload`:

- remove `templateIdHint` and emitted `templateId`;
- use `templateCode`/`templateCodeHint` only if the session needs an identity hint.

Boot/runtime/status serialization of `SelectedTemplate` emits code/type/system scope only. There is no id field.

### 8. Printing and diagnostics

Bridge-owned diagnostics and external print extras use TemplateCode.

- trace details: `templateCode`;
- `ReportPrintRequest.extra`: `templateCode`;
- `reservedHostExternalPrintExtraKeys`: reserve `templateCode`, not `templateId`;
- no template backend id is logged or sent to an external printer.

This changes only Bridge/external-print metadata. It does not change backend APIs.

### 9. Presenter/session behavior

Presenter preparation continues to receive the full template document/model. Compatibility and report-type checks remain unchanged except their messages identify templates by TemplateCode (or generic template wording) rather than backend id.

Inline Presenter data must not require backend id. If any current session payload includes a template-id hint, replace it with code or remove the hint when unused.

## Public compatibility and migration policy

This is an intentional breaking Bridge API cleanup **after the already-published `1.0.2` release**. The next release should use a new immutable version/tag, normally `1.0.3`.

No compatibility aliases such as `initialTemplateId`, `selectedTemplateId`, `templateId`, deprecated id getters, or id-based selector overloads are retained in the Bridge public API. The user explicitly chose TemplateCode-only behavior rather than legacy-id support.

Callers must update to TemplateCode names. Existing durable code-based preferences remain valid. Existing id-only preferences are ignored.

The backend response format may continue carrying `id`; that does not constitute a Bridge identity contract.

## Backend boundary

Out of scope:

- backend schema/API changes;
- changing backend template primary keys;
- asking the backend to stop returning `id`;
- database migrations;
- Admin/server changes solely to remove backend id.

The Bridge query/sync parser continues to tolerate the current backend response. It extracts TemplateCode and ignores template id for all downstream behavior.

## Tests and verification

Implementation must be TDD-driven. Required regression categories include:

- explicit `initialTemplateCode` wins;
- saved TemplateCode wins;
- no saved/default -> first compatible TemplateCode;
- zero compatible coded templates -> no Preview;
- saved code absent after authoritative refresh -> manual reselection;
- transient first preference-resolution sync failure followed by successful authoritative sync recovers the saved TemplateCode;
- the same transient case works for code persistence without any id sentinel;
- `alwaysPrepare` and `alwaysSelectTemplate` semantics remain unchanged apart from identity naming;
- code-only mode persistence does not revive old id selection;
- old id-only preference records are ignored;
- duplicate TemplateCode catalog entries are rejected;
- missing TemplateCode cannot be selected or cached as a valid template;
- cache filenames/lookup/dedup/sort are TemplateCode-based;
- SelectedTemplate serialization contains no id;
- boot/inline payloads expose no template-id hint;
- external printer metadata contains `templateCode` and no `templateId`;
- source-scan gate proves no Bridge template-identity API/logic references remain except the narrowly documented backend wire parser occurrence.

Verification must cover both packages:

```text
packages/reporting_bridge
packages/reporting_bridge_flutter
```

Required final gates:

- Dart/Flutter formatting check;
- analyzers for both packages;
- full test suites for both packages;
- `git diff --check`;
- source scan for forbidden template-id identity names/uses;
- merged-result verification after combining with PDF preview commit `e0880f687f17a33d1ed1ddeb1f434315e79e09a3`;
- package/release version review for the next release (normally `1.0.3`) only after the merged `main` tree is green.

## Forbidden Bridge identity patterns

After implementation, production Bridge code must not contain these as template identity concepts:

```text
initialTemplateId
selectedTemplateId
committedTemplateId
templateIdHint
_validTemplateId
_templateById
templateId (preference/state/selection/print field)
id-based selected-template migration
id-based template cache lookup/dedup/sort/filename
fallback from TemplateCode to backend id or document meta.id
```

The literal backend JSON key `'id'` is allowed only at the backend parsing boundary (and unrelated non-template identities such as system/printer ids are unaffected).

## Release integration

The final release sequence after implementation approval is:

1. complete and verify TemplateCode-only identity work;
2. commit it on the isolated feature branch;
3. integrate reviewed PDF preview commit `e0880f687f17a33d1ed1ddeb1f434315e79e09a3`;
4. merge the combined reviewed work into `main` without disturbing unrelated untracked main-checkout files;
5. run fresh merged-result analyzers/tests/source-scan/diff checks;
6. when separately authorized for release, create a new immutable tag (normally `1.0.3`) at the verified `main` commit;
7. push `main` and that new tag only with explicit push/tag authority;
8. verify remote branch and tag identities.

No push, tag, or release occurs before the combined tree is green.
