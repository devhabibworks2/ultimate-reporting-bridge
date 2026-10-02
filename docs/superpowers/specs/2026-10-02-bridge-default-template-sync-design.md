# Bridge Default Template Sync Design

## Goal

Extend the existing `POST /presenter/templates/query` synchronization contract so one request returns both the published template catalog available to the current Bridge query and the effective configured default template for each returned report type.

Backend defaults are a convenience only. They must never become a hard requirement for opening or using reports offline.

## Existing Behavior

- `POST /presenter/templates/query` returns published templates for one system and supports optional filtering by report type, layout, size, language, unit, and orientation.
- The request already carries optional `userId`, `branchId`, and `systemUnit`.
- Backend default configuration supports USER, BRANCH, SYSTEM_UNIT, and SYSTEM scopes.
- Bridge caches the synchronized catalog and user template selection.
- Bridge can continue from cached templates when the backend is unavailable.

## Response Contract

Add `defaultTemplates` to the successful query response:

```json
{
  "catalogRevision": "...",
  "system": { "...": "..." },
  "appliedFilter": { "...": "..." },
  "count": 4,
  "items": [ "...published templates..." ],
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

1. Return at most one entry per report type represented in the filtered `items` list.
2. Resolve configured defaults using the existing precedence:
   `USER -> BRANCH -> SYSTEM_UNIT -> SYSTEM`.
3. Include a default only when its template is present in the filtered `items` result.
4. If no configured usable default exists for a report type, omit that report type from `defaultTemplates`.
5. Do not emit `GLOBAL_FALLBACK` as a backend default entry. First-compatible fallback remains Bridge behavior.
6. `selectionReason` is diagnostic metadata only; Bridge selection behavior is driven by `templateCode`.
7. Preserve all existing query fields and semantics for backward compatibility.

## Backend Design

Use the already-loaded published/filtered catalog from `presenter/templates/query`. Do not issue a separate resolve HTTP request and do not reload the catalog once per report type.

Add a small resolver that, for each report type present in the filtered catalog:

- evaluates USER, BRANCH, SYSTEM_UNIT, then SYSTEM defaults using the optional query identity;
- accepts only a configured default whose template is already in the filtered result;
- returns `reportType`, `templateCode`, and diagnostic `selectionReason`.

Reuse the existing template-default scope rules instead of duplicating precedence semantics. Keep the current `templates.query` authorization/customer isolation and existing identity/header conflict validation; this feature must not widen access.

## Bridge Cache Design

Cache `defaultTemplates` as part of the same catalog metadata snapshot as the synchronized templates.

The catalog replacement remains atomic:

```text
templates + catalog metadata + defaultTemplates
                 ↓
          one successful cache swap
```

A failed online synchronization must leave the previous cached templates and previous cached defaults intact.

Cached defaults are scoped by the same cache namespace and query fingerprints already used for system, identity, filter, and extra data.

## Bridge Selection Behavior

For the report type being opened, selection precedence is:

```text
1. Current valid selection / explicit Host initialTemplateCode
2. Valid saved user selection
3. Cached backend default for this report type
4. First compatible template
```

Additional rules:

- A user may always choose a different template.
- A user override is persisted and remains authoritative while that selected template is still valid.
- A later backend default change must not replace a valid saved user selection.
- Existing stale/invalid saved-selection handling remains authoritative; this feature must not silently reinterpret an invalid user choice.
- `alwaysSelectTemplate` still opens template selection; the backend default may be preselected but must not bypass that policy.
- Backend defaults are not written into user-preference storage as though the user selected them manually.

## Offline Behavior

Offline operation must not require backend default resolution.

When the backend is unavailable:

1. Use the cached template catalog.
2. Use a valid saved user selection if present.
3. Otherwise use the cached backend default for that report type if it is still present in the cached compatible templates.
4. Otherwise use the first compatible cached template, subject to existing entry-policy behavior.

If the backend changes defaults while the device is offline, nothing changes locally until a later successful synchronization. Existing offline templates and user selections remain usable.

## Error Handling

- Missing `defaultTemplates` in an older backend response is valid and treated as no backend defaults.
- Malformed default entries must not corrupt the template cache; reject the new sync snapshot and preserve the last known good cache.
- A default pointing to a template not present in `items` is ignored/rejected by backend construction and must never become an active Bridge default.
- No configured default is not an error.

## Testing

Backend tests must cover:

- one effective default per returned report type;
- USER > BRANCH > SYSTEM_UNIT > SYSTEM precedence;
- filtered-out defaults are omitted;
- report types without configured defaults are omitted;
- response backward compatibility and customer isolation.

Bridge tests must cover:

- parsing/caching/restoring `defaultTemplates`;
- atomic cache preservation after failed sync;
- saved user selection overrides backend default;
- backend default overrides first-compatible fallback;
- first compatible is used when no cached default exists;
- cached default works offline;
- backend default updates do not override a valid saved user choice;
- missing `defaultTemplates` remains compatible with older backends;
- `alwaysSelectTemplate` still requires the selection UI.

## Non-Goals

- No new standalone default-resolution API call from Bridge.
- No numeric template ID authority in Bridge; `TemplateCode` remains the durable Bridge identity.
- No requirement for the backend to be reachable to open cached reports.
- No change to Admin default-configuration semantics.
