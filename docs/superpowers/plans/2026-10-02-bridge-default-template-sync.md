# Bridge Default Template Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or an equivalent strict task-by-task workflow. This plan is intentionally explicit so a lower-reasoning executor such as Cursor Auto can follow it without redesigning the feature.

**Goal:** Extend `POST /presenter/templates/query` so one sync returns published/filtered templates plus one effective configured default per returned report type, then cache and use those defaults in Bridge without making them a runtime dependency or overriding a user's valid saved choice.

**Architecture:** Backend resolves configured defaults from the same already-filtered catalog using USER → BRANCH → SYSTEM_UNIT → SYSTEM and returns `defaultTemplates[]`. Bridge validates and stores those hints in the same atomic catalog snapshot, exposes them through a local cache read API, and uses them only after explicit/current and saved-user selections but before first-compatible fallback.

**Tech Stack:** Python/FastAPI/Pydantic/SQLAlchemy/Pytest; Dart; Flutter; `reporting_bridge`; `reporting_bridge_flutter`.

**Spec:** `docs/superpowers/specs/2026-10-02-bridge-default-template-sync-design.md`

## Source Authority

### URB / backend — use this worktree only

- Repo/worktree: `/Users/abdualhabib/Desktop/Ultimate Report Builder/.worktrees/pure-dart-presenter-cutover-20260930`
- Branch: `feat/pure-dart-presenter-cutover-20260930`
- Verified starting HEAD before this plan: `46adfa5a9bad3e579f2074ca15d9881f40875498`
- Backend directory: `/Users/abdualhabib/Desktop/Ultimate Report Builder/.worktrees/pure-dart-presenter-cutover-20260930/backend`

**Do not implement in:**
`/Users/abdualhabib/Desktop/Ultimate Report Builder`

That root checkout is stale for this work and remains on `uat/ios-presenter-cross-platform-20260928`.

### Bridge — use this worktree only

- Repo/worktree: `/Users/abdualhabib/urb-worktrees/ultimate-reporting-bridge-auto-first-compatible-template-20261001`
- Branch: `feat/bridge-auto-first-compatible-template-20261001`
- Approved design spec: `docs/superpowers/specs/2026-10-02-bridge-default-template-sync-design.md`

## Dirty-tree protection

Both worktrees already contain unrelated work. The executor must preserve it.

### URB worktree known unrelated dirty areas

Examples include:
- `demo/demo_host_flutter/...`
- `deploy/product-version.txt`
- `presenter_web/pubspec.yaml`

These are not part of this feature.

### Bridge worktree known unrelated dirty areas

The Bridge worktree already contains substantial TemplateCode/Presenter changes predating this feature.

### Forbidden commands

Do not use:
- `git reset --hard`
- `git clean`
- `git stash`
- broad `git checkout -- .`
- broad `git restore .`
- branch switching
- destructive rebases

Before every commit:
1. run `git status --short`;
2. inspect `git diff -- <files owned by current task>`;
3. stage only current-task files;
4. run `git diff --cached --name-only`;
5. run `git diff --cached --check`;
6. commit only if staged scope is exact.

If a target file already contains unrelated uncommitted edits, use hunk-level staging. Never discard those edits.

## Contract to implement exactly

A successful presenter query keeps all existing fields and adds:

```json
{
  "catalogRevision": "...",
  "system": {
    "id": 1,
    "code": "erp",
    "name": "ERP"
  },
  "appliedFilter": {
    "reportTypes": ["all"],
    "layouts": ["all"],
    "sizes": ["all"],
    "languages": ["all"],
    "units": ["all"],
    "orientations": ["all"]
  },
  "count": 4,
  "items": [
    "...existing published/filtered template objects..."
  ],
  "defaultTemplates": [
    {
      "reportType": "sales_invoice",
      "templateCode": "INV-A5-AR",
      "selectionReason": "SYSTEM_DEFAULT"
    },
    {
      "reportType": "sales_return",
      "templateCode": "RET-A5-AR",
      "selectionReason": "BRANCH_DEFAULT"
    }
  ]
}
```

Rules:
- at most one `defaultTemplates` entry per report type;
- only report types represented in the final filtered `items` may appear;
- only a default whose `templateCode` is itself present in final `items` may appear;
- precedence is USER → BRANCH → SYSTEM_UNIT → SYSTEM;
- `GLOBAL_FALLBACK` is never returned inside `defaultTemplates`;
- no configured/usable default means that report type is omitted;
- no defaults at all means `defaultTemplates: []`;
- `selectionReason` is diagnostic metadata only;
- TemplateCode is the durable Bridge identity.

## Bridge selection contract

For the report type being opened:

```text
1. current valid selection / explicit Host initialTemplateCode
2. valid saved user selection
3. cached backend default for this report type
4. first compatible template
```

Additional rules:
- stale saved user selection keeps existing reselection behavior; do not silently replace it with a backend default;
- `alwaysSelectTemplate` still opens Template Selection;
- a backend default may be preselected in that screen;
- automatically adopting a backend default must not write it as the user's saved selected template;
- if the user manually selects that same TemplateCode, it becomes a user selection and may be persisted;
- first-compatible behavior keeps its current persistence behavior;
- backend unavailability never prevents use of valid cached templates/default hints;
- backend default changes while offline do not alter the local cache until a later successful sync.

## Review Focus

The executor must explicitly test these failure classes:
1. `userId == null` while BRANCH/SYSTEM_UNIT/SYSTEM defaults exist;
2. report type remains in `items` but its configured default template is removed by another filter;
3. malformed/duplicate `defaultTemplates` response must not partially replace previous cache;
4. stale saved user choice must not be silently replaced by backend default;
5. backend default update must not replace a valid saved user selection.

---

# Phase 0 — Preflight: prove you are in the correct sources

Do not edit code until every check below matches.

## 0.1 URB source check

Run:

```bash
cd "/Users/abdualhabib/Desktop/Ultimate Report Builder/.worktrees/pure-dart-presenter-cutover-20260930"
git branch --show-current
git rev-parse HEAD
git status --short
```

Expected branch:
`feat/pure-dart-presenter-cutover-20260930`

Do not require the HEAD to remain exactly the historical value above if another approved commit was added after this plan. Instead confirm this worktree is still the newest pure-dart Presenter line and not the stale UAT root.

Save the starting `git status --short` output for the completion report.

## 0.2 Bridge source check

Run:

```bash
cd "/Users/abdualhabib/urb-worktrees/ultimate-reporting-bridge-auto-first-compatible-template-20261001"
git branch --show-current
git rev-parse HEAD
git status --short
```

Expected branch:
`feat/bridge-auto-first-compatible-template-20261001`

Confirm these files exist:
- `docs/superpowers/specs/2026-10-02-bridge-default-template-sync-design.md`
- `docs/superpowers/plans/2026-10-02-bridge-default-template-sync.md`

## 0.3 Read authority files

Read fully before implementing:
1. the spec;
2. this plan;
3. `backend/app/services/report_template_resolution.py`;
4. `backend/app/services/presenter_template_query_service.py`;
5. `backend/app/presentation/routes/presenter.py`;
6. `packages/reporting_bridge/lib/src/bridge_template_sync.dart`;
7. `packages/reporting_bridge/lib/src/bridge_template_cache.dart`;
8. `packages/reporting_bridge_flutter/lib/src/flow/report_flow_controller_base.dart`.

Do not redesign after reading. If actual current code materially contradicts this plan, stop and report the contradiction instead of guessing.

---

# Task 1 — Extract one reusable backend configured-default candidate resolver

## Purpose

The existing `TemplateResolutionService._default_candidates` already contains the precedence logic, but Presenter query also needs it. Extract that logic into one dedicated service so the precedence exists in one place.

## Files

Create:
- `backend/app/services/report_template_default_resolution.py`

Modify:
- `backend/app/services/report_template_resolution.py`
- `backend/tests/test_report_template_resolution.py`

## Exact interface to create

Create in `report_template_default_resolution.py`:

```python
class TemplateDefaultAmbiguityError(LookupError):
    def __init__(self, scope_type: str) -> None:
        self.scope_type = scope_type
        super().__init__(f"More than one default exists for {scope_type}")


def configured_default_candidates(
    db: Session,
    *,
    system_id: int,
    report_type: str,
    user_id: int | str | None,
    branch_id: str | None,
    system_unit: str | None,
) -> list[tuple[str, TemplateDefault]]:
    ...
```

Use these exact reason/scope pairs, in this exact order:

```text
USER_DEFAULT        / USER
BRANCH_DEFAULT      / BRANCH
SYSTEM_UNIT_DEFAULT / SYSTEM_UNIT
SYSTEM_DEFAULT      / SYSTEM
```

### Exact candidate-building behavior

- If `user_id is not None`, add USER using `normalize_scope_key("USER", user_id)`.
- If `user_id is None`, do not call `normalize_scope_key` for USER and do not add USER.
- If `branch_id is not None`, add BRANCH.
- If `system_unit is not None`, add SYSTEM_UNIT.
- Always add SYSTEM using the internal key `"__system__"`.
- For each scope, query `TemplateDefault` by:
  - `system_id`
  - `report_type`
  - `scope_type`
  - `scope_key`
- 0 rows: continue.
- 1 row: append `(reason, row)`.
- >1 rows: raise `TemplateDefaultAmbiguityError(scope_type)`.

Do not perform template compatibility checks in this helper. It only returns configured candidates in precedence order.

## RED tests

In `backend/tests/test_report_template_resolution.py`:

Import:
```python
from app.services.report_template_default_resolution import configured_default_candidates
```

Add test:

```python
def test_configured_candidates_skip_absent_user_and_reach_system_default():
    with _db() as db:
        system = _system(db)
        template = _template(db, system, code="SYS")
        _default(db, system, template, "SYSTEM", "__system__")

        candidates = configured_default_candidates(
            db,
            system_id=system.id,
            report_type="report",
            user_id=None,
            branch_id=None,
            system_unit=None,
        )

        assert [(reason, row.template_id) for reason, row in candidates] == [
            ("SYSTEM_DEFAULT", template.id)
        ]
```

Add test with four distinct templates/defaults proving exact order:

```python
def test_configured_candidates_return_scope_precedence_order():
    ...
    assert [reason for reason, _ in candidates] == [
        "USER_DEFAULT",
        "BRANCH_DEFAULT",
        "SYSTEM_UNIT_DEFAULT",
        "SYSTEM_DEFAULT",
    ]
```

Use existing `_system`, `_template`, and `_default` helpers.

## Run RED

```bash
cd "/Users/abdualhabib/Desktop/Ultimate Report Builder/.worktrees/pure-dart-presenter-cutover-20260930/backend"
.venv/bin/python -m pytest -q   tests/test_report_template_resolution.py::test_configured_candidates_skip_absent_user_and_reach_system_default   tests/test_report_template_resolution.py::test_configured_candidates_return_scope_precedence_order
```

Expected before implementation: import/function failure.

## Implement

1. Create the new helper file.
2. In `report_template_resolution.py`:
   - remove imports of `TemplateDefault` and `normalize_scope_key` if no longer needed;
   - import:
     `TemplateDefaultAmbiguityError, configured_default_candidates`.
3. Replace the body that calls `self._default_candidates(...)` with:

```python
try:
    default_candidates = configured_default_candidates(
        db,
        system_id=system.id,
        report_type=report_type,
        user_id=context.user_id,
        branch_id=context.branch_id,
        system_unit=context.system_unit,
    )
except TemplateDefaultAmbiguityError as exc:
    raise TemplateResolutionError(
        "TEMPLATE_DEFAULT_AMBIGUITY",
        str(exc),
    ) from exc
```

4. Remove the old private static method `_default_candidates`.
5. Do not change explicit selection, eligible filtering, `GLOBAL_FALLBACK`, or snapshot generation.

## GREEN verification

Run:

```bash
.venv/bin/python -m pytest -q tests/test_report_template_resolution.py
```

Expected: all tests in the file pass.

## Commit

Stage only:
- `backend/app/services/report_template_default_resolution.py`
- `backend/app/services/report_template_resolution.py`
- `backend/tests/test_report_template_resolution.py`

Commit:
```bash
git commit -m "refactor: share configured template default resolution"
```

---

# Task 2 — Add effective defaults to `POST /presenter/templates/query`

## Purpose

Return one configured/usable default per report type represented by the already-filtered query result. Do not call the separate report resolver endpoint.

## Files

Modify:
- `backend/app/services/presenter_template_query_service.py`
- `backend/app/presentation/routes/presenter.py`
- `backend/tests/test_presenter_template_query.py`
- `backend/tests/helpers/customer_architecture_fixture.py`
- `backend/tests/test_customer_architecture_e2e.py`

## Exact service type

Add to `presenter_template_query_service.py`:

```python
@dataclass(frozen=True)
class PresenterDefaultTemplate:
    report_type: str
    template_code: str
    selection_reason: str
```

Import Task 1:
```python
from app.services.report_template_default_resolution import (
    TemplateDefaultAmbiguityError,
    configured_default_candidates,
)
```

## Exact service function

Add:

```python
def resolve_configured_defaults_for_catalog(
    session: Session,
    *,
    system_id: int,
    entries: list[PresenterCatalogEntry],
    user_id: str | None,
    branch_id: str | None,
    system_unit: str | None,
) -> list[PresenterDefaultTemplate]:
    ...
```

### Exact algorithm

1. Build `entries_by_report_type: dict[str, list[PresenterCatalogEntry]]`.
2. Iterate report types in `sorted(entries_by_report_type)` order.
3. For each report type:
   - call `configured_default_candidates(...)`;
   - build `eligible_by_id = {entry.template.id: entry for entry in report_entries}`;
   - walk candidates in returned precedence order;
   - first candidate whose `default.template_id` exists in `eligible_by_id` wins;
   - append one `PresenterDefaultTemplate`;
   - break candidate loop.
4. If no candidate is eligible, append nothing.
5. Never create a fallback entry from `report_entries[0]`.
6. Never emit `GLOBAL_FALLBACK`.

## Exact route serialization

In `query_presenter_templates` after `matching = filter_catalog(...)`, compute:

```python
effective_branch_id = body.branch_id or header_branch_id
default_templates = template_query.resolve_configured_defaults_for_catalog(
    db,
    system_id=system.id,
    entries=matching,
    user_id=body.user_id,
    branch_id=effective_branch_id,
    system_unit=body.system_unit,
)
```

Catch `TemplateDefaultAmbiguityError` around that call and return:

- HTTP 500
- code `TEMPLATE_DEFAULT_AMBIGUITY`
- message from the exception.

Serialize:

```python
"defaultTemplates": [
    {
        "reportType": item.report_type,
        "templateCode": item.template_code,
        "selectionReason": item.selection_reason,
    }
    for item in default_templates
],
```

Place it beside `"items": items`.

Do not alter:
- `catalogRevision`;
- existing item shape;
- count;
- filter behavior;
- selector behavior;
- customer DB dependency.

## Backend test helper

In `tests/test_presenter_template_query.py`, import:
- `engine` from `app.core.database`;
- `TemplateDefault` from `app.data.models` if not already available.

Add:

```python
def _insert_default(
    *,
    system_id: int,
    report_type: str,
    scope_type: str,
    scope_key: str,
    template_id: int,
) -> None:
    session = sessionmaker(bind=engine)()
    try:
        session.add(
            TemplateDefault(
                system_id=system_id,
                report_type=report_type,
                scope_type=scope_type,
                scope_key=scope_key,
                template_id=template_id,
            )
        )
        session.commit()
    finally:
        session.close()
```

Use `"__system__"` for SYSTEM scope.

## RED test A — empty default list is explicit

Extend existing minimum request test:

```python
assert data["defaultTemplates"] == []
```

This proves the field always exists on the new backend.

## RED test B — one default per available report type

Create system and at least two published report types. Insert SYSTEM defaults for both. Query unfiltered.

Assert exact shape:

```python
assert data["defaultTemplates"] == [
    {
        "reportType": "payment_voucher",
        "templateCode": payment["code"],
        "selectionReason": "SYSTEM_DEFAULT",
    },
    {
        "reportType": "sales_invoice",
        "templateCode": invoice["code"],
        "selectionReason": "SYSTEM_DEFAULT",
    },
]
```

Order must be reportType lexical order.

## RED test C — precedence

For one `sales_invoice` report type, create four published templates:
- USER template
- BRANCH template
- UNIT template
- SYSTEM template

Insert all four scoped defaults.

Query with:
```json
{
  "systemCode": "...",
  "userId": "user_123",
  "branchId": "branch_01",
  "systemUnit": "sales"
}
```

Assert USER wins.

Then issue separate requests omitting higher scopes to prove:
- no user → BRANCH;
- no user/branch → SYSTEM_UNIT;
- no user/branch/systemUnit → SYSTEM.

Do not mutate defaults between these requests.

## RED test D — filtered default omitted while report type remains

Create two `sales_invoice` templates:
- default template A4;
- non-default template A5.

Configure SYSTEM default to A4.

Query filter:
```json
{"sizes": ["A5"]}
```

Assert:
- `items` contains the A5 invoice;
- `defaultTemplates == []`.

This proves a default is not returned merely because the report type is present.

## RED test E — customer isolation

Update `ArchitectureFixture` to expose customer sessions safely:

Add field:
```python
customer_dbs: dict[str, Session]
```

Yield it from fixture.

Seed:
- CUST-A SYSTEM default to INV-A;
- CUST-B either no default or its own INV-B default.

Call each customer's API credential separately and assert each response sees only its own configured default.

Do not use one customer's numeric template ID as authority across DBs.

## Run RED

```bash
cd "/Users/abdualhabib/Desktop/Ultimate Report Builder/.worktrees/pure-dart-presenter-cutover-20260930/backend"
.venv/bin/python -m pytest -q   tests/test_presenter_template_query.py   tests/test_customer_architecture_e2e.py
```

Expected: new `defaultTemplates` assertions fail.

## Implement service + route

Implement exactly the service type/function and route changes above.

## GREEN

Run:

```bash
.venv/bin/python -m pytest -q   tests/test_presenter_template_query.py   tests/test_report_template_resolution.py   tests/test_admin_report_template_defaults.py   tests/test_customer_architecture_e2e.py   tests/test_runtime_customer_authorization.py
```

Expected: PASS.

## Commit

Stage only Task 2 backend/test files.

Commit:
```bash
git commit -m "feat: return default templates with presenter query"
```

---

# Task 3 — Add a strict Bridge default-hint model and cache serialization

## Purpose

Bridge needs a small typed value for backend default hints and must persist it inside `.catalog.json`, not in user preference storage.

## Files

Create:
- `packages/reporting_bridge/lib/src/bridge_template_default.dart`

Modify:
- `packages/reporting_bridge/lib/reporting_bridge.dart`
- `packages/reporting_bridge/lib/src/bridge_template_cache.dart`
- `packages/reporting_bridge/test/bridge_template_cache_review_test.dart`

## Exact model

Create:

```dart
final class TemplateDefaultHint {
  const TemplateDefaultHint({
    required this.reportType,
    required this.templateCode,
    required this.selectionReason,
  });

  final String reportType;
  final String templateCode;
  final String selectionReason;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'reportType': reportType,
    'templateCode': templateCode,
    'selectionReason': selectionReason,
  };

  static TemplateDefaultHint? tryFromMap(Map<dynamic, dynamic> raw) {
    ...
  }
}
```

### Exact `tryFromMap` rules

Trim all 3 string values.

Return `null` if any is missing/empty.

Do not convert case.

Do not interpret `selectionReason`.

## Export

Add:
```dart
export 'src/bridge_template_default.dart';
```
to `packages/reporting_bridge/lib/reporting_bridge.dart`.

## Extend metadata

In `TemplateCatalogMetadata` add constructor arg:

```dart
this.defaultTemplates = const <TemplateDefaultHint>[],
```

Add field:

```dart
final List<TemplateDefaultHint> defaultTemplates;
```

In `toMap()`, always write:

```dart
'defaultTemplates': defaultTemplates.map((value) => value.toMap()).toList(growable: false),
```

### Backward-compatible `fromMap`

Rules:
- field absent → empty list;
- field present but not a List → return `null` metadata;
- each item must be a Map and `tryFromMap` must succeed;
- duplicate reportType → return `null`;
- otherwise construct unmodifiable list.

Do not validate template cross-reference here; this class does not have the template list.

## RED cache tests

Add to `bridge_template_cache_review_test.dart`:

### Test: metadata round-trip

Write metadata with two hints, read it, assert equality by fields.

### Test: old metadata without field

Manually write `.catalog.json` without `defaultTemplates`, call `readCatalogMetadata()`, assert:
`metadata!.defaultTemplates == []`.

### Test: malformed metadata

Write duplicate reportType hints or an empty templateCode. Assert:
`readCatalogMetadata() == null`.

## Run RED

```bash
cd "/Users/abdualhabib/urb-worktrees/ultimate-reporting-bridge-auto-first-compatible-template-20261001/packages/reporting_bridge"
dart test test/bridge_template_cache_review_test.dart
```

## Implement and GREEN

Run same test until PASS.

Then:
```bash
dart analyze
```

No new analysis issues.

## Commit

Stage only Task 3 files.

Commit:
```bash
git commit -m "feat: model cached template defaults"
```

---

# Task 4 — Parse `defaultTemplates`, validate cross-references, and preserve atomic cache

## Purpose

The server response must be fully validated before replacing cache. A malformed default list must leave the previous complete catalog/default snapshot untouched.

## Files

Modify:
- `packages/reporting_bridge/lib/src/bridge_template_sync.dart`
- `packages/reporting_bridge/test/bridge_template_query_transport_test.dart`

## Extend internal parsed catalog

Add to `_ParsedTemplateCatalog`:

```dart
required this.defaultTemplates,
...
final List<TemplateDefaultHint> defaultTemplates;
```

## Extend sync summary

In `TemplateSyncSummary` add optional constructor arg:

```dart
this.defaultTemplates = const <TemplateDefaultHint>[],
```

Add field:
```dart
final List<TemplateDefaultHint> defaultTemplates;
```

Add to `toMap()`:
```dart
'defaultTemplates':
    defaultTemplates.map((value) => value.toMap()).toList(growable: false),
```

Keep default empty so existing test fakes do not need immediate changes.

## Parser behavior

Inside `_parseQueryResponse`:

1. Read:
```dart
final rawDefaults = data['defaultTemplates'];
```

2. Backward compatibility:
- if key absent / value `null`: treat as empty list;
- if non-null and not List: throw `TEMPLATE_CATALOG_INVALID`.

3. Parse all normal templates first.

4. Build:
```dart
final templatesByCode = <String, CachedTemplate>{
  for (final template in templates) template.templateCode: template,
};
```

5. Parse each default:
- item must be Map;
- `TemplateDefaultHint.tryFromMap` must succeed;
- reportType must be unique;
- referenced templateCode must exist in `templatesByCode`;
- referenced template's `type` must equal hint.reportType.

Any failure throws:
`BridgeRuntimeException(BridgeTemplateSyncErrorCodes.templateCatalogInvalid, ...)`.

6. Put validated list into `_ParsedTemplateCatalog`.

## Cache write

When building `TemplateCatalogMetadata` in `queryTemplatesToCache`, pass:

```dart
defaultTemplates: parsed.defaultTemplates,
```

No change is needed to the staging/backup algorithm because metadata and template files are already installed through one directory swap.

## Sync summary

Online success:
```dart
defaultTemplates: parsed.defaultTemplates,
```

Transport fallback using valid cache:
```dart
defaultTemplates: metadata?.defaultTemplates ?? const <TemplateDefaultHint>[],
```

## Test helper change

Change:

```dart
Map<String, dynamic> _queryEnvelope(List<Map<String, dynamic>> items)
```

to:

```dart
Map<String, dynamic> _queryEnvelope(
  List<Map<String, dynamic>> items, {
  List<Map<String, dynamic>> defaultTemplates = const <Map<String, dynamic>>[],
})
```

Add `'defaultTemplates': defaultTemplates` in data.

For the old-backend compatibility test, explicitly remove the field from the generated envelope before sending it.

## RED transport tests

Add:

### A. valid defaults parse/cache

Response has two items and two matching default hints.

Assert:
- `summary.defaultTemplates.length == 2`;
- fields exact;
- later cache metadata contains same hints.

### B. missing field supported

Remove `defaultTemplates` from response.

Assert sync succeeds and summary list is empty.

### C. duplicate report type rejected

Two hints with same `reportType`.

Assert `TEMPLATE_CATALOG_INVALID`.

### D. missing code rejected

Hint points to `missing-code`.

Assert invalid.

### E. report type mismatch rejected

Hint says `payment_voucher` but points to sales invoice item.

Assert invalid.

### F. invalid new snapshot preserves prior templates + defaults

First response:
- existing sales invoice template;
- existing matching default.

Second response:
- replacement template;
- malformed default.

Assert after failed second sync:
- old template still returned;
- old metadata/default still returned.

### G. offline fallback returns cached defaults

First successful sync caches default.
Stop server.
Second `syncTemplates` returns `fromCache == true`.
Assert summary contains cached hint.

## Run RED/GREEN

```bash
dart test test/bridge_template_query_transport_test.dart
```

Then full core package:

```bash
dart test
dart analyze
```

Expected: PASS.

## Commit

Stage only:
- `bridge_template_sync.dart`
- `bridge_template_query_transport_test.dart`

Commit:
```bash
git commit -m "feat: cache presenter default template hints"
```

---

# Task 5 — Expose cached defaults through the existing Bridge query scope

## Purpose

Flutter flow must read cached default hints without making a network call. The read must use the exact same cache namespace validation as `listTemplates`.

## Files

Modify:
- `packages/reporting_bridge/lib/src/bridge_presenter_server.dart`
- `packages/reporting_bridge/lib/src/bridge_client.dart`
- `packages/reporting_bridge/test/bridge_template_query_transport_test.dart`
- `packages/reporting_bridge_flutter/lib/src/flow/report_flow_controller_impl.dart`
- `packages/reporting_bridge_flutter/test/flow/workflow_bridge_client_integration_test.dart`

## Gateway method

Add to `PresenterServerGateway`:

```dart
Future<List<TemplateDefaultHint>> listTemplateDefaults({
  required TemplateQueryRequest query,
  Map<String, String>? headers,
}) async
```

Implementation must:
1. compute effective headers exactly like `listTemplates`;
2. call `_queryTemplateCache(query, effectiveHeaders)`;
3. read metadata;
4. perform exact same valid-catalog checks:
   - metadata non-null;
   - systemCode matches;
   - filterFingerprint matches;
   - extraFingerprint matches;
5. if invalid: throw `OFFLINE_CACHE_UNAVAILABLE`;
6. return `metadata.defaultTemplates`.

No network call.

## Client method

Add to `ReportingBridgeClient`:

```dart
Future<List<TemplateDefaultHint>> listTemplateDefaults({
  required String systemCode,
  TemplateSyncFilter? filter,
  Map<String, Object?> extra = const <String, Object?>{},
}) async
```

Mirror `listTemplates`:
- build same `TemplateQueryRequest`;
- resolve headers with `BridgeHeaderOperation.listTemplates`;
- call gateway;
- set `_lastTemplateQuery = query`;
- return defaults.

Do not add a new header operation enum.

## Workflow wrapper override

In `_WorkflowBridgeClient` add override matching the new client method.

It must:
1. call `_ensureRequestScope()`;
2. ignore caller-supplied system/filter/extra in favor of `templateSyncRequest`, exactly like existing `listTemplates`;
3. delegate;
4. catch `OFFLINE_CACHE_UNAVAILABLE` and return `const <TemplateDefaultHint>[]`.

This keeps cold-cache behavior parallel with `listTemplates`.

## Tests

### Core transport test

After sync:
```dart
final defaults = await gateway.listTemplateDefaults(query: query);
```

Assert returned hints.

Also verify first-time/offline scope with no cache throws `OFFLINE_CACHE_UNAVAILABLE`.

### Flutter integration test

In `workflow_bridge_client_integration_test.dart`, extend fake delegate to record `listTemplateDefaults`.

Assert:
- identity context is bound before call;
- canonical system/filter/extra from `TemplateSyncRequest` are used;
- returned hints pass through;
- cold-cache typed miss becomes empty list.

## Verification

Core:
```bash
cd "/Users/abdualhabib/urb-worktrees/ultimate-reporting-bridge-auto-first-compatible-template-20261001/packages/reporting_bridge"
dart test
dart analyze
```

Flutter focused:
```bash
cd "../reporting_bridge_flutter"
flutter test --no-pub test/flow/workflow_bridge_client_integration_test.dart
```

## Commit

Stage only Task 5 files.

Commit:
```bash
git commit -m "feat: expose cached template defaults"
```

---

# Task 6 — Use cached backend defaults in report flow without turning them into user preferences

## Purpose

This is the behavior task. Do not change UI structure. Only change selection authority and persistence bookkeeping.

## Files

Modify:
- `packages/reporting_bridge_flutter/lib/src/flow/report_flow_controller_base.dart`
- `packages/reporting_bridge_flutter/test/flow/report_flow_controller_test.dart`

Possibly modify only if compiler requires:
- `packages/reporting_bridge_flutter/lib/src/flow/report_flow_controller_impl.dart` from Task 5.

Do not add backend default fields to public `ReportFlowState` unless strictly necessary. Keep helper provenance private to controller.

## Private provenance field

Near `_persistedPreferences`, add:

```dart
String? _autoBackendDefaultTemplateCode;
```

Meaning:
- non-null only when the current selected TemplateCode was automatically chosen from a backend default hint;
- null for Host explicit, saved user, manual user, and first-compatible choices.

## Helper

Add:

```dart
String? _validBackendDefaultCode(
  List<CachedTemplate> templates,
  List<TemplateDefaultHint> defaults,
  String reportType,
)
```

Exact behavior:
1. find hint whose `reportType == reportType`;
2. if none return null;
3. call existing `_validTemplateCode(templates, hint.templateCode)`;
4. return valid code or null.

Do not use `selectionReason` for behavior.

## Initial cached load

In `initialize()`, after:

```dart
final catalog = await _runtime.bridgeClient.listTemplates(...)
```

also read:

```dart
final cachedDefaults = await _runtime.bridgeClient.listTemplateDefaults(
  systemCode: sync.systemCode.value,
  filter: sync.filter,
  extra: sync.extra,
);
```

Because workflow wrapper converts cold-cache miss to empty, do not add a new failure path.

Compute:

```dart
final backendDefault = _validBackendDefaultCode(
  templates,
  cachedDefaults,
  request.reportType.value,
);
```

### Preserve stale saved selection rule

Existing:
`storedTemplateUnavailableForRequest`

must remain authoritative.

If that bool is true:
- selected stays null;
- do not use backend default;
- smart flow opens selection as before.

### Fallback calculation

For `alwaysSelectTemplate`:

```text
backendDefault
else single template if exactly one
else null
```

For normal smart/other initial fallback:

```text
backendDefault
else first compatible
```

### Set provenance

After final `selected` is chosen:

Set:
```dart
_autoBackendDefaultTemplateCode =
    candidate == null &&
    !storedTemplateUnavailableForRequest &&
    selected != null &&
    selected == backendDefault
        ? selected
        : null;
```

Important:
- if explicit Host code equals backend default, `candidate != null`, so provenance is null;
- if saved user code equals backend default, candidate is non-null, provenance is null.

## Sync result record

Change internal signature:

From:
```dart
Future<({int catalogCount, List<CachedTemplate> compatibleTemplates})>
_synchronizeTemplateCatalog()
```

To:
```dart
Future<({
  int catalogCount,
  List<CachedTemplate> compatibleTemplates,
  List<TemplateDefaultHint> defaultTemplates,
})> _synchronizeTemplateCatalog()
```

After `syncTemplates`, read both:
- `listTemplates`;
- `listTemplateDefaults`.

Return both.

## Update `_resolveTemplateAfterSync`

Change signature:

```dart
String? _resolveTemplateAfterSync(
  List<CachedTemplate> templates,
  List<TemplateDefaultHint> defaults,
)
```

Exact precedence inside:

1. current valid selection;
2. explicit `request.initialTemplateCode`;
3. valid persisted user selection when no explicit initial;
4. existing non-initial-resource behavior;
5. existing stale saved-choice guard;
6. backend default for current reportType;
7. existing `alwaysSelectTemplate` single-template fallback;
8. first compatible.

### Provenance updates inside helper

- current valid:
  - preserve `_autoBackendDefaultTemplateCode` only if it already equals current;
  - otherwise set it null.
- explicit valid: set provenance null.
- persisted valid: set provenance null.
- stale persisted: set provenance null and return null.
- backend default: set provenance to returned code.
- single/first-compatible fallback: set provenance null.

Update both call sites:
- `syncTemplates()`;
- `_synchronizeTemplatesForEntry()`.

Pass `synchronized.defaultTemplates`.

## Manual selection clears helper provenance

In `selectTemplate(String templateCode)`, after validation succeeds and before/with state mutation:

```dart
_autoBackendDefaultTemplateCode = null;
```

This must happen even when user selects the same TemplateCode as the backend hint.

## Persistence change

Current `_persistSelection()` always writes selected template.

Change only this method.

Use:

```dart
final isUntouchedBackendDefault =
    _autoBackendDefaultTemplateCode == template.templateCode;
```

Create preferences:

```dart
final preferences = ReportFlowPreferences(
  templateCode: isUntouchedBackendDefault ? null : template.templateCode,
  mode: _value.selectedMode,
);
```

Save as before.

This deliberately:
- saves presenter mode;
- removes/does not create user-selected TemplateCode when backend default was only auto-adopted;
- preserves existing behavior for first-compatible and explicit/manual selections.

Do not modify `ReportFlowPreferenceStore` API.

## Focused RED tests

Use existing `_FakeBridgeClient` and `_FakePreferenceStore`.

Extend fake bridge:

```dart
List<TemplateDefaultHint> defaultTemplates = <TemplateDefaultHint>[];
List<TemplateDefaultHint>? defaultTemplatesAfterSync;
```

Override:
```dart
Future<List<TemplateDefaultHint>> listTemplateDefaults(...)
    async => defaultTemplates;
```

In fake `syncTemplates`, if `defaultTemplatesAfterSync != null`, assign it.

### Test 1

Name:
`smart entry prefers backend default over first compatible`

Setup:
- templates t1, t2;
- default sales_invoice → t2;
- no saved preference.

Assert:
- selected/committed t2;
- stage previewing.

### Test 2

Name:
`saved user template overrides backend default`

Setup:
- saved t1;
- backend default t2.

Assert t1.

### Test 3

Name:
`explicit initial template overrides saved and backend default`

Setup:
- saved t1;
- backend default t2;
- initialTemplateCode t3.

Assert t3.

### Test 4

Name:
`auto backend default is not persisted as user template`

Setup:
- no preference;
- backend default t2;
- smart entry automatically reaches preview.

After initialize:
```dart
expect(preferences.valuesBySystem['legacy_system_1']?.templateCode, isNull);
expect(
  preferences.valuesBySystem['legacy_system_1']?.mode,
  controller.value.selectedMode,
);
```

### Test 5

Name:
`manual selection of backend default persists as user template`

Use `alwaysSelectTemplate` with default t2 so UI remains selecting.

Assert initial selected t2.

Call the existing initial-selection path exactly as the UI does:
```dart
controller.selectTemplate('t2');
await controller.preparePreview();
```

The current UI calls `preparePreview` directly from the initial Template Selection Continue action; do not invent a new continuation API.

After preview/persist:
`templateCode == 't2'`.

### Test 6

Name:
`alwaysSelectTemplate preselects backend default but keeps selection screen`

Assert:
- stage `selectingTemplate`;
- selected t2;
- `prepareCalls == 0`.

### Test 7

Name:
`stale saved template is not replaced by backend default`

Setup:
- persisted template `removed`;
- current templates t1/t2;
- backend default t2.

Assert:
- selection screen;
- selected null;
- stored preference still follows existing stale-selection behavior.

### Test 8

Name:
`backend default for another report type is ignored`

Hint payment_voucher → some code while current report is sales_invoice.

Assert first-compatible sales invoice remains selection.

### Test 9

Name:
`cold cache sync adopts returned backend default`

Initial templates empty.
`templatesAfterSync = [t1,t2]`.
`defaultTemplatesAfterSync = sales_invoice -> t2`.

Assert after initialize selected t2.

### Test 10

Name:
`backend default update does not replace valid saved user selection`

Saved t1.
Sync produces default t2.
Assert t1 remains.

## Run RED/GREEN

```bash
cd "/Users/abdualhabib/urb-worktrees/ultimate-reporting-bridge-auto-first-compatible-template-20261001/packages/reporting_bridge_flutter"
flutter test --no-pub test/flow/report_flow_controller_test.dart
```

Then:

```bash
flutter test --no-pub test/flow/workflow_bridge_client_integration_test.dart
flutter test --no-pub
flutter analyze --no-pub
```

Expected: all pass.

## Commit

Stage only Task 6 files.

Commit:
```bash
git commit -m "feat: apply cached backend template defaults"
```

---

# Task 7 — Cross-repo contract verification

Do not add features in this task.

## 7.1 Backend full focused verification

```bash
cd "/Users/abdualhabib/Desktop/Ultimate Report Builder/.worktrees/pure-dart-presenter-cutover-20260930/backend"

.venv/bin/python -m pytest -q   tests/test_presenter_template_query.py   tests/test_report_template_resolution.py   tests/test_admin_report_template_defaults.py   tests/test_customer_architecture_e2e.py   tests/test_runtime_customer_authorization.py
```

Expected: PASS.

## 7.2 Bridge core verification

```bash
cd "/Users/abdualhabib/urb-worktrees/ultimate-reporting-bridge-auto-first-compatible-template-20261001/packages/reporting_bridge"
dart test
dart analyze
```

Expected: PASS / no issues.

## 7.3 Flutter Bridge verification

```bash
cd "/Users/abdualhabib/urb-worktrees/ultimate-reporting-bridge-auto-first-compatible-template-20261001/packages/reporting_bridge_flutter"
flutter test --no-pub
flutter analyze --no-pub
```

Expected: PASS / no issues.

## 7.4 Diff integrity

URB:

```bash
cd "/Users/abdualhabib/Desktop/Ultimate Report Builder/.worktrees/pure-dart-presenter-cutover-20260930"
git diff --check
git status --short
git log --oneline -8
```

Bridge:

```bash
cd "/Users/abdualhabib/urb-worktrees/ultimate-reporting-bridge-auto-first-compatible-template-20261001"
git diff --check
git status --short
git log --oneline -10
```

## 7.5 Required final behavioral checklist

Do not declare completion until all are proven:

- [ ] Query still returns all existing published/filtered `items`.
- [ ] `defaultTemplates[]` returns at most one configured default per returned report type.
- [ ] USER beats BRANCH.
- [ ] BRANCH beats SYSTEM_UNIT.
- [ ] SYSTEM_UNIT beats SYSTEM.
- [ ] No configured default produces no entry, not an error.
- [ ] Filtered-out default is omitted even if another template of same report type remains.
- [ ] TemplateCode, not numeric ID, is Bridge authority.
- [ ] Missing `defaultTemplates` works with old backend responses.
- [ ] Malformed default list cannot partially replace cache.
- [ ] Cached defaults survive backend/network unavailability.
- [ ] Saved user selection beats backend default.
- [ ] Explicit Host selection beats backend default.
- [ ] Stale user selection still requests reselection.
- [ ] Auto backend default is not saved as user-selected template.
- [ ] Manually choosing the same backend-default template is saved as user choice.
- [ ] `alwaysSelectTemplate` still shows Template Selection.
- [ ] A later backend default update does not replace a valid saved user choice.

---

# Task 8 — Final review and handoff

## No merge yet

Do not merge branches automatically unless the coordinator explicitly requests it after review.

## Final report format

Return exactly these sections:

### 1. URB backend
- worktree path
- branch
- starting HEAD
- ending HEAD
- commits created
- files changed

### 2. Bridge
- worktree path
- branch
- starting HEAD
- ending HEAD
- commits created
- files changed

### 3. Verification
For every command:
- exact command
- pass/fail
- test count if available
- analyzer result

### 4. Behavior proven
List each checkbox from Task 7.5 as PASS or FAIL.

### 5. Dirty-tree preservation
Compare final status with Phase 0 status.
Explicitly list all unrelated pre-existing dirty files still present.
Confirm none were reset/reverted/staged accidentally.

### 6. Remaining issues
If none, say:
`No known feature-scope blockers remain; merge still requires coordinator review.`

## Stop conditions

Stop instead of improvising if any of these occur:
- required source branch/path is not the one defined above;
- current source has incompatible interfaces that make an exact plan step impossible;
- a test fails for a pre-existing unrelated reason and the failure cannot be isolated;
- implementation would require changing Admin default semantics;
- implementation would require numeric template ID authority in Bridge;
- implementation would require making backend availability mandatory for report opening;
- safe staging cannot separate feature edits from pre-existing dirty changes.

When stopping, report:
1. exact command/file;
2. exact failure/contradiction;
3. why continuing would be unsafe;
4. minimal proposed adjustment.
