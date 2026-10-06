# Shared Presenter Surface Warm-up — Bridge Final Design

## Status

Final written design for user review before implementation planning.

This document is Bridge-only. It does not define Demo Host screens or Application Examples layout.

## Source of truth

Bridge candidate:

```text
repo:   /Users/abdualhabib/Desktop/ultimate-reporting-bridge/.worktrees/feat-presenter-loading-ui-20261003
branch: feat/presenter-loading-ui-20261003
HEAD:   8f09c66068fe413aa5647cda3f385c07b99ba241
```

Current implementation facts verified from source:

- `warmUpPresenter(..., warmHeadlessSurface: true)` warms the client-managed `InAppHeadlessPresenterSurface`.
- `openReport()` does not call `_ensureSurfaceWarm()`.
- `ReportFlowScreen` does not receive the client-managed surface factory.
- `BridgePresenterView` creates its own `InAppHeadlessPresenterSurface`.
- the interactive view shuts its internally owned warmable surface down on dispose.
- headless print/PDF use the client-managed surface factory and only detach the current session after the run.
- one report flow may be active per client.

## Goal

Make Presenter surface warm-up a generic client capability that can accelerate:

- `openReport()`;
- interactive printing reached through `openReport()`;
- `printReportHeadless()`;
- `generateReportPdfHeadless()`.

The optimization must remain optional. A report operation must remain correct without explicit warm-up.

## Public API

Preferred API:

```dart
Future<PresenterWarmupResult> warmUpPresenter(
  ReportOpenRequest request, {
  bool refreshResources = false,
  bool warmPresenterSurface = false,
  @Deprecated('Use warmPresenterSurface.')
  bool warmHeadlessSurface = false,
});
```

Effective surface warm-up is:

```dart
final shouldWarmPresenterSurface =
    warmPresenterSurface || warmHeadlessSurface;
```

The deprecated flag is source-compatibility only. New docs and generated examples use `warmPresenterSurface`.

No new `warmInteractiveSurface` flag is added. The public concept is one reusable Presenter surface.

## Ownership architecture

The client owns one reusable warmable Presenter surface for its whole lifetime.

```text
ReportingBridgeFlutterClient
        │
        └── managed Presenter surface
              ├── openReport()
              ├── interactive Print
              ├── printReportHeadless()
              └── generateReportPdfHeadless()
```

Operation lifecycle:

```text
client creates managed surface
        ↓
optional warmUpPresenter(...)
        ↓
operation borrows same surface
        ↓
surface.start(...)
        ↓
operation ends
        ↓
surface.dispose()       // detach session only
        ↓
surface remains alive
        ↓
next operation can reuse it
        ↓
client.dispose()
        ↓
surface.shutdown()      // destroy WebView exactly once
```

## Managed-surface provider and ownership contract

The implementation must make ownership explicit; it must not infer ownership merely from the fact that a factory was passed.

Normal public composition through `ReportingBridgeFlutter.createClient()` owns one stable `WarmableHeadlessPresenterSurface` instance for the client lifetime.

Low-level constructor compatibility rules:

- an explicitly supplied `headlessPresenterSurface` is treated as the stable client-managed reusable instance;
- an explicitly supplied `headlessPresenterSurfaceFactory` keeps its existing factory semantics and is not silently converted into a reusable warmable instance;
- when only a factory override exists, `warmPresenterSurface` reports the surface as unavailable rather than pretending a future factory-created surface was warmed;
- interactive routes created from a factory override may use an operation-owned surface and shut it down at route end;
- the default/public Demo Host path must use the stable client-managed surface and therefore supports shared warm-up.

The route/view boundary must carry explicit ownership metadata. Conceptually:

```text
PresenterSurfaceLease
  surfaceFactory
  ownership = borrowedFromClient | ownedByView
```

The exact internal type name may differ, but the behavior may not.

For a borrowed client-managed surface, `BridgePresenterView` detaches with `surface.dispose()` and never calls `surface.shutdown()`. For a view-owned surface, it shuts the surface down on widget disposal.

## Interactive flow integration

`openReport()` must pass the client-managed surface factory into the interactive route.

Expected data flow:

```text
openReport()
  → ReportFlowScreen(presenterSurfaceFactory: ...)
  → BridgePresenterView(headlessSurfaceFactory: ...)
  → factory returns client-managed surface
```

`BridgePresenterView` ownership rule:

- if it creates its own surface, it owns it and may `shutdown()` on widget disposal;
- if a surface is supplied by a factory/owner, it must only `dispose()`/detach the current session and must not destroy the underlying WebView.

This preserves standalone `BridgePresenterView` behavior while enabling client-owned reuse.

## Headless integration

`printReportHeadless()` and `generateReportPdfHeadless()` continue to use the same client-managed factory.

They may continue to ensure a usable surface before execution. Explicit host warm-up remains an optimization that moves that cost earlier.

No second headless surface pool is introduced.

## Warm-up behavior

`refreshResources` and `warmPresenterSurface` remain independent.

`refreshResources: true`:

- resolves the effective Presenter mode;
- runs report resource/template preparation for the request;
- can be useful before every report operation.

`warmPresenterSurface: true`:

- creates/warms the reusable Presenter WebView if needed;
- does not render the report;
- does not choose a final template;
- does not make the final operation mandatory.

Example:

```dart
await client.warmUpPresenter(
  request,
  refreshResources: true,
  warmPresenterSurface: true,
);

await client.openReport(context, request);
```

## Active-flow warm-up semantics

`warmUpPresenter()` remains result-oriented rather than throwing for an ordinary warm-up failure.

If `warmPresenterSurface: true` is requested while a report flow is active:

- do not call `warmUp()` or navigate/load the shared surface;
- return `surfaceStatus: PresenterWarmupSurfaceStatus.failed`;
- include a stable diagnostic containing `flowAlreadyActive`;
- if `refreshResources: true` was also requested, its resource branch may complete independently and its status is still returned.

The old headless-specific diagnostic `headlessSurfaceUnavailable` must not be emitted for the new generic path. Use generic Presenter-surface wording such as `presenterSurfaceUnavailable`.

## Concurrency and lifecycle safety

Because the same surface is shared across interactive and headless flows:

- no surface mutation may start while another report flow is active;
- existing `flowAlreadyActive` protection remains authoritative;
- a surface warm-up requested while a report flow owns the surface must fail safely rather than navigate the shared WebView away from the active report;
- resource refresh may remain independently reportable through `PresenterWarmupResult`;
- repeated warm-up is idempotent while the surface is already warm;
- failed warm-up must not permanently poison future retries;
- `client.dispose()` shuts the managed surface down exactly once.

## Naming scope

Do not rename the existing `HeadlessPresenterSurface` / `WarmableHeadlessPresenterSurface` public types in this feature.

Although the implementation is already used by interactive preview, renaming the public types would add migration scope unrelated to the warm-up capability. Internal client fields/methods may use generic Presenter naming.

## Existing Bridge cleanup included in the final program

The final Bridge implementation program also carries these previously approved Bridge changes:

### UI authorization simplification

The Host application is the authorization authority.

This is an intentional breaking cleanup on the current unreleased candidate. Do not add a second compatibility/deprecation layer that keeps the duplicate authorization model alive.

Remove the duplicate Bridge action-policy authorization layer:

- remove `ReportOpenRequest.actionPolicy`;
- remove `ReportActionPolicy` and its public export when no remaining non-duplicate use exists;
- remove `BridgeUiFeatures.restrictTo(policy)`;
- remove Bridge-side `actionDenied` authorization checks that exist only for this duplicate policy;
- remove `ReportFlowFailureCode.actionDenied` and its localized failure strings/tests if no independent failure path remains;
- update public API tests, request/test helpers, README/examples, and controller tests that reference the removed policy;
- keep `BridgeUiFeatures` as UI visibility configuration.

This is independent from Presenter warm-up and must be implemented/tested as a separate Bridge task.

### Template sync versus compatibility semantics

Preserve the conceptual separation:

```text
TemplateSyncRequest.filter
→ catalog acquisition/query scope

TemplateCompatibilityConstraints
→ eligibility for the current report
```

It is valid for `TemplateSyncRequest.filter` to restrict which templates are synchronized or listed from the catalog/cache. That restricted catalog is then the input set for report resolution.

Eligibility must still be evaluated independently with `TemplateCompatibilityConstraints`. Do not derive compatibility from the sync filter, copy sync dimensions into compatibility, or skip compatibility checks merely because a template survived the catalog query.

Do **not** remove `sync.filter` from `listTemplates` / `listTemplateDefaults` solely to enforce this conceptual separation. Change runtime filtering only if a focused test proves the current behavior violates the rule above.

## Non-goals

This Bridge change does not:

- add Application Examples concepts to Bridge;
- expose Online/Offline controls in Demo Host;
- change `BridgePdfPreviewConfig`;
- remove `showCurrentTemplate` or `showTemplateMetadata` from the Bridge API;
- add multiple simultaneous report flows per client;
- add a surface pool;
- make warm-up required for correctness.

## Required verification

Tests must cover at least:

1. warm → `openReport()` reuses the managed surface;
2. warm → `printReportHeadless()` reuses it;
3. warm → `generateReportPdfHeadless()` reuses it;
4. open → close → open reuses it;
5. open → headless operation reuses it after detach;
6. headless → open reuses it;
7. interactive widget disposal does not shut down a borrowed surface;
8. standalone widget-owned surface still shuts down correctly;
9. client disposal shuts down the managed surface exactly once;
10. concurrent flow still fails closed;
11. warm-up during an active flow does not redirect the active surface;
12. legacy `warmHeadlessSurface` maps to the generic warm-up;
13. `warmUpHeadlessPrinting()` delegates through `warmPresenterSurface: true`;
14. resource-only warm-up still works without surface warm-up;
15. failed warm-up can be retried;
16. warm-up during an active flow does not touch the shared surface and reports `flowAlreadyActive`;
17. low-level factory override remains operation-owned and reports generic shared warm-up unavailable;
18. generic surface-unavailable diagnostics contain no stale `headlessSurfaceUnavailable` wording.

## Implementation boundary

This design authorizes a Bridge implementation plan after written review. It does not authorize code changes by itself.

Do not commit, push, merge, tag, or release without explicit user authorization.
