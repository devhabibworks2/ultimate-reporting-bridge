# Bridge Final Changes Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: use superpowers:executing-plans or superpowers:subagent-driven-development task-by-task. This plan is deliberately written for a lower-reasoning local model. Do not redesign the architecture. Follow the locked decisions and exact task order.

**Goal:** Generalize Presenter warm-up so openReport, interactive print, headless print, and headless PDF can reuse one client-owned Presenter surface; remove duplicate ReportActionPolicy authorization; and lock template-sync versus compatibility semantics.

**Architecture:** One ReportingBridgeFlutterClient owns one reusable warmable Presenter surface. Explicit host warm-up is optional and generic through warmPresenterSurface. Interactive UI borrows the managed surface and detaches it when the route closes; only client.dispose shuts it down. A factory-only low-level override remains operation-owned and cannot truthfully report a shared surface as warmed.

**Tech Stack:** Dart, Flutter, flutter_inappwebview, reporting_bridge, reporting_bridge_flutter, flutter_test.

**Spec:** docs/superpowers/specs/2026-10-06-shared-presenter-surface-warmup-design.md

**Mandatory Clean-Code Contract:** `/Users/abdualhabib/Desktop/Ultimate Report Builder/docs/superpowers/plans/2026-10-06-clean-code-reviewability-contract.md`

**Hard-Task Safety TODOs:** `/Users/abdualhabib/Desktop/Ultimate Report Builder/docs/superpowers/plans/2026-10-06-hard-task-agent-safety-todos.md` — Bridge Task 2 must complete H1; Bridge Task 4 must complete H2.

## Executor Contract

- Work only in:
  /Users/abdualhabib/Desktop/ultimate-reporting-bridge/.worktrees/feat-presenter-loading-ui-20261003
- Expected branch: feat/presenter-loading-ui-20261003
- Baseline design/plan checkpoint: a63f898556c7a573545629342f89e5ceca216678.
- Do not demand literal HEAD equality because safety-plan hardening commits may follow this checkpoint. Before Task 1, verify `git merge-base --is-ancestor a63f898556c7a573545629342f89e5ceca216678 HEAD` and inspect paths changed since the checkpoint; only docs/plan hardening is allowed before product implementation begins.
- Do not reset, clean, checkout, restore, rebase, merge, tag, push, or delete unrelated files.
- Preserve pre-existing untracked files under example/*/pubspec.lock and packages/reporting_bridge_flutter/.vscode/.
- No dependency additions are needed.
- No commit is authorized. Every task ends with a checkpoint, not a commit.
- If a task discovers code already changed by an earlier task, use the post-task state and preserve the interface decisions below.
- If a focused test fails for a reason unrelated to the task, capture the exact test and failure, prove it is unrelated, and continue. Do not “fix” unrelated code.
- Never rename HeadlessPresenterSurface or WarmableHeadlessPresenterSurface as part of this feature.
- New public examples and docs use warmPresenterSurface. warmHeadlessSurface remains only as a deprecated compatibility input.
- ReportActionPolicy removal is intentional breaking cleanup on this unreleased candidate. Do not preserve it through a second compatibility layer.

## Global Constraints

- Read and enforce the mandatory Clean-Code Contract before every task.
- Existing large Bridge files are containment zones, not cleanup targets. In particular, `lib/src/ui/report_flow_screen.dart` (~3000 lines) and `lib/src/flow/report_flow_controller_base.dart` (~2000 lines) must receive only surgical task-owned edits.
- Do not add a new major responsibility to any existing >500-line file. Put new substantial behavior in a focused collaborator and leave only wiring in the legacy file.
- A passing test does not make a task PASS until its STRUCTURE_REVIEW also passes.
- warmUpPresenter remains optional; final report operations must remain correct without explicit warm-up.
- warmPresenterSurface and refreshResources are independent.
- openReport, printReportHeadless, and generateReportPdfHeadless must all be able to reuse the same managed Presenter surface when the default/stable surface path is used.
- one report flow per client remains the authority; flowAlreadyActive behavior remains fail-closed.
- warm-up requested while a flow is active must not navigate/load the shared surface.
- factory-only low-level override keeps factory semantics; shared warm-up reports unavailable for that path.
- borrowed surface route disposal detaches only; owned surface route disposal shuts down.
- client.dispose shuts the managed surface down exactly once.
- generic warm-up diagnostics must not emit stale headlessSurfaceUnavailable wording.
- TemplateSyncRequest.filter remains catalog acquisition/query scope.
- TemplateCompatibilityConstraints remains report eligibility scope.
- Do not remove sync.filter from listTemplates/listTemplateDefaults merely to enforce conceptual separation.

## Review Focus

1. Active interactive flow + warmPresenterSurface: surface must not be touched; result reports failed surface status with flowAlreadyActive diagnostic.
2. Borrowed surface lifecycle: closing interactive report must not shutdown the client-managed WebView.
3. Factory-only override: direct/headless operation still works; shared explicit warm-up reports presenterSurfaceUnavailable.
4. Failed warm-up retry: first failure must not permanently poison later retry.
5. Policy removal: hiding an action with BridgeUiFeatures must not become a hidden authorization check for programmatic controller methods.

---

### Task 0: Preflight and baseline capture

**Files:** none.

- [ ] Step 1: Confirm branch and HEAD.

    cd /Users/abdualhabib/Desktop/ultimate-reporting-bridge/.worktrees/feat-presenter-loading-ui-20261003
    git branch --show-current
    git rev-parse HEAD
    git status --short --branch

Expected branch: feat/presenter-loading-ui-20261003.
Do not require a clean worktree.

- [ ] Step 2: Save the current diff/status as evidence outside the repo.

    mkdir -p /Users/abdualhabib/Downloads/agent-state/URB_FINAL_IMPLEMENTATION/bridge
    git status --short --branch > /Users/abdualhabib/Downloads/agent-state/URB_FINAL_IMPLEMENTATION/bridge/preflight-status.txt
    git diff > /Users/abdualhabib/Downloads/agent-state/URB_FINAL_IMPLEMENTATION/bridge/preflight-diff.patch

- [ ] Step 3: Read the Bridge spec and this entire plan before editing.

- [ ] Step 4: Checkpoint.

    git diff --check
    git status --short --branch

Do not commit.

---

### Task 1: Generalize the Presenter warm-up API

**Files:**
- Modify: packages/reporting_bridge_flutter/lib/src/client/reporting_bridge_flutter_client.dart
- Modify: packages/reporting_bridge_flutter/lib/src/presenter/presenter_warmup_coordinator.dart
- Modify: packages/reporting_bridge_flutter/test/presenter/presenter_warmup_coordinator_test.dart
- Modify: packages/reporting_bridge_flutter/test/public_api_test.dart
- Modify: packages/reporting_bridge_flutter/test/client/reporting_bridge_flutter_client_print_integration_test.dart

**Interfaces produced:**

ReportingBridgeFlutterClient.warmUpPresenter must have this effective signature:

    Future<PresenterWarmupResult> warmUpPresenter(
      ReportOpenRequest request, {
      bool refreshResources = false,
      bool warmPresenterSurface = false,
      @Deprecated('Use warmPresenterSurface instead.')
      bool warmHeadlessSurface = false,
    });

PresenterWarmupCoordinator.warmUp must use only the generic internal option:

    Future<PresenterWarmupResult> warmUp(
      ReportOpenRequest request, {
      bool refreshResources = false,
      bool warmPresenterSurface = false,
    });

DefaultReportingBridgeFlutterClient maps:

    shouldWarmSurface = warmPresenterSurface || warmHeadlessSurface

warmUpHeadlessPrinting delegates using warmPresenterSurface: true.

- [ ] Step 1: Write/adjust failing coordinator tests.

Add tests that assert:
- warmPresenterSurface: true requests surface warm-up.
- false skips surface warm-up.
- false result from warmSurface produces PresenterWarmupSurfaceStatus.failed and diagnostic presenterSurfaceUnavailable.
- no test expects headlessSurfaceUnavailable.
- resource-only warm-up remains independent.
- failed surface warm-up can be retried and calls warmSurface again.

- [ ] Step 2: Run RED.

    cd packages/reporting_bridge_flutter
    flutter test --no-pub test/presenter/presenter_warmup_coordinator_test.dart

Expected: compile/test failure because warmPresenterSurface does not exist yet or old diagnostic differs.

- [ ] Step 3: Implement the coordinator rename/generalization.

In presenter_warmup_coordinator.dart:
- rename warmHeadlessSurface parameter to warmPresenterSurface.
- use warmPresenterSurface for disposed-result status selection and future creation.
- change false-ready diagnostic from headlessSurfaceUnavailable to presenterSurfaceUnavailable.
- preserve existing coalescing and retry behavior.
- do not change resource warm-up semantics.

- [ ] Step 4: Update the public client signature and compatibility mapping.

In reporting_bridge_flutter_client.dart:
- add warmPresenterSurface named parameter before deprecated warmHeadlessSurface.
- keep warmHeadlessSurface accepted and deprecated.
- compute one boolean using OR.
- pass only warmPresenterSurface to PresenterWarmupCoordinator.
- change warmUpHeadlessPrinting deprecation message to point to warmPresenterSurface.
- make warmUpHeadlessPrinting call warmUpPresenter(... warmPresenterSurface: true).

- [ ] Step 5: Update public API tests.

public_api_test.dart must compile against both:
- new warmPresenterSurface parameter.
- deprecated warmHeadlessSurface parameter.

Do not add a second overload.

- [ ] Step 6: Add compatibility tests to reporting_bridge_flutter_client_print_integration_test.dart.

Assert:
- new warmPresenterSurface warms once.
- legacy warmHeadlessSurface also warms once.
- setting both true still warms once.
- warmUpHeadlessPrinting warms through the generic path.

- [ ] Step 7: Run GREEN.

    flutter test --no-pub test/presenter/presenter_warmup_coordinator_test.dart
    flutter test --no-pub test/public_api_test.dart
    flutter test --no-pub test/client/reporting_bridge_flutter_client_print_integration_test.dart

Expected: PASS.

- [ ] Step 8: Format/checkpoint.

    dart format lib/src/client/reporting_bridge_flutter_client.dart lib/src/presenter/presenter_warmup_coordinator.dart test/presenter/presenter_warmup_coordinator_test.dart test/public_api_test.dart test/client/reporting_bridge_flutter_client_print_integration_test.dart
    git diff --check
    git status --short

Do not commit.

---

### Task 2: Make one managed Presenter surface reusable by openReport and headless flows

**Mandatory agent safety gate:** Complete H1 — Shared Presenter Surface Ownership in `2026-10-06-hard-task-agent-safety-todos.md`. This task cannot be marked PASS until `SURFACE_OWNERSHIP_REVIEW=PASS` is recorded in durable state.

**Files:**
- Modify: packages/reporting_bridge_flutter/lib/src/client/reporting_bridge_flutter_client.dart
- Modify: packages/reporting_bridge_flutter/lib/src/ui/report_flow_screen.dart
- Modify: packages/reporting_bridge_flutter/lib/src/ui/bridge_presenter_view.dart
- Modify: packages/reporting_bridge_flutter/test/ui/bridge_presenter_view_test.dart
- Modify: packages/reporting_bridge_flutter/test/client/reporting_bridge_flutter_client_print_integration_test.dart
- Modify if needed for route construction test: packages/reporting_bridge_flutter/test/client/report_flow_route_test.dart

**Clean-code constraint for this task:** `report_flow_screen.dart` is a legacy containment zone. Add only constructor fields and the minimal wiring needed to pass the shared surface into `BridgePresenterView`. Do not move/reformat unrelated UI code and do not add a new subsystem to that file.

**Locked ownership design:**

Use the existing stable direct-surface constructor path as the borrowed/shared path.

In DefaultReportingBridgeFlutterClient:
- rename internal _managedHeadlessSurface to _managedPresenterSurface.
- keep _headlessPresenterSurfaceFactory for headless runner compatibility.
- default construction creates one InAppHeadlessPresenterSurface and stores it as _managedPresenterSurface.
- explicitly injected headlessPresenterSurface is also the stable managed surface.
- explicitly injected headlessPresenterSurfaceFactory means _managedPresenterSurface is null and the factory remains operation-owned.

Add optional route/view inputs:
- ReportFlowScreen receives HeadlessPresenterSurface? presenterSurface.
- ReportFlowScreen receives HeadlessPresenterSurfaceFactory? presenterSurfaceFactory.
- BridgePresenterView receives HeadlessPresenterSurface? presenterSurface in addition to its existing testing factory.

BridgePresenterView acquisition rule:
- if presenterSurface is non-null, use exactly that instance and treat it as borrowed.
- else if headlessSurfaceFactory is non-null, call it and treat the returned instance as owned by the view.
- else create InAppHeadlessPresenterSurface and treat it as owned by the view.

BridgePresenterView disposal rule:
- borrowed direct presenterSurface -> await/trigger surface.dispose() only; never shutdown().
- owned warmable surface -> shutdown().
- owned non-warmable surface -> dispose().

Do not change InAppHeadlessPresenterSurface.start semantics; it already detaches the previous session while keeping the WebView.

- [ ] Step 1: Add failing BridgePresenterView ownership tests.

In bridge_presenter_view_test.dart add:
- borrowed surface starts exactly once.
- removing the widget calls dispose once and shutdown zero times on borrowed fake.
- owned factory surface still shuts down exactly once.
- session replacement within one widget keeps the same surface instance and does not shutdown.

Extend the fake to count disposeCalls separately from shutdownCalls.

- [ ] Step 2: Run RED.

    flutter test --no-pub test/ui/bridge_presenter_view_test.dart

Expected: FAIL because presenterSurface input/borrowed ownership does not exist.

- [ ] Step 3: Implement borrowed/owned view behavior exactly as locked above.

Do not infer ownership from type. Ownership is direct-instance versus factory/default.

- [ ] Step 4: Thread the inputs through ReportFlowScreen.

Add constructor fields:
- presenterSurface
- presenterSurfaceFactory

When creating BridgePresenterView:
- pass presenterSurface.
- pass presenterSurfaceFactory as headlessSurfaceFactory.

Do not change PDF preview behavior or loading overlay behavior.

- [ ] Step 5: Make openReport use the managed surface.

In DefaultReportingBridgeFlutterClient.openReport:
- when _managedPresenterSurface is non-null, pass it as presenterSurface and pass no factory.
- when _managedPresenterSurface is null because a factory override was supplied, pass that factory as presenterSurfaceFactory.

Headless print/PDF continue using _headlessPresenterSurfaceFactory.

- [ ] Step 6: Add client integration tests.

Using the existing fake fixture, add tests proving:
- warm surface -> open interactive flow uses the exact same fake surface instance.
- close interactive flow -> fake dispose increments, shutdown remains zero until client.dispose.
- after interactive close, headless print uses the same surface instance.
- headless run followed by interactive open uses the same surface instance.
- client.dispose finally calls shutdown exactly once.

Reuse existing fixture helpers rather than adding a parallel fake stack.

- [ ] Step 7: Run GREEN.

    flutter test --no-pub test/ui/bridge_presenter_view_test.dart
    flutter test --no-pub test/client/reporting_bridge_flutter_client_print_integration_test.dart
    flutter test --no-pub test/client/report_flow_route_test.dart

Expected: PASS.

- [ ] Step 8: Format/checkpoint.

    dart format lib/src/client/reporting_bridge_flutter_client.dart lib/src/ui/report_flow_screen.dart lib/src/ui/bridge_presenter_view.dart test/ui/bridge_presenter_view_test.dart test/client/reporting_bridge_flutter_client_print_integration_test.dart test/client/report_flow_route_test.dart
    git diff --check
    git status --short

Do not commit.

---

### Task 3: Enforce active-flow-safe generic warm-up and low-level factory semantics

**Files:**
- Modify: packages/reporting_bridge_flutter/lib/src/client/reporting_bridge_flutter_client.dart
- Modify: packages/reporting_bridge_flutter/test/client/reporting_bridge_flutter_client_print_integration_test.dart
- Modify if coordinator assertion needed: packages/reporting_bridge_flutter/test/presenter/presenter_warmup_coordinator_test.dart

**Interfaces:**

Create/retain two distinct internal operations:

1. Operation warm:
   _ensureManagedPresenterSurfaceWarm()
   - may be called by headless final operations after their normal flow-availability check.
   - returns false when there is no stable managed surface.

2. Explicit warm-up action:
   _warmManagedPresenterSurfaceForWarmup()
   - if active controller exists, throw ReportFlowFailure(flowAlreadyActive) before touching the surface.
   - otherwise delegate to _ensureManagedPresenterSurfaceWarm().

PresenterWarmupCoordinator catches that failure and returns surfaceStatus failed with a diagnostic containing flowAlreadyActive.

Do not change the result-oriented public warm-up into a throwing API for ordinary warm-up failure.

- [ ] Step 1: Add failing tests.

Add:
- create an active controller, then call warmUpPresenter(warmPresenterSurface: true); expect surfaceStatus failed, diagnostic contains flowAlreadyActive, fake warmUpCalls == 0.
- request refreshResources plus warmPresenterSurface during active flow; surface reports failed; resource branch is still allowed to report its own status.
- factory-only client + warmPresenterSurface -> failed surface status, diagnostic presenterSurfaceUnavailable.
- factory-only final headless print still creates/uses factory surface and remains functional.
- disposed client behavior remains result-oriented for warm-up and throwing for final report operations.

- [ ] Step 2: Run RED.

    flutter test --no-pub test/client/reporting_bridge_flutter_client_print_integration_test.dart

- [ ] Step 3: Implement the two internal warm paths.

Do not add another public flag.

- [ ] Step 4: Run GREEN.

    flutter test --no-pub test/client/reporting_bridge_flutter_client_print_integration_test.dart
    flutter test --no-pub test/presenter/presenter_warmup_coordinator_test.dart

- [ ] Step 5: Checkpoint.

    dart format lib/src/client/reporting_bridge_flutter_client.dart test/client/reporting_bridge_flutter_client_print_integration_test.dart
    git diff --check

Do not commit.

---

### Task 4: Remove duplicate ReportActionPolicy authorization

**Mandatory agent safety gate:** Complete H2 — Remove ReportActionPolicy Without Replacing It in `2026-10-06-hard-task-agent-safety-todos.md`. This task cannot be marked PASS until `POLICY_REMOVAL_REVIEW=PASS` is recorded in durable state.

**Files:**
- Delete: packages/reporting_bridge_flutter/lib/src/flow/report_action_policy.dart
- Modify: packages/reporting_bridge_flutter/lib/reporting_bridge_flutter.dart
- Modify: packages/reporting_bridge_flutter/lib/src/contracts/report_open_request.dart
- Modify: packages/reporting_bridge_flutter/lib/src/ui/bridge_ui_features.dart
- Modify: packages/reporting_bridge_flutter/lib/src/flow/report_flow_controller.dart
- Modify: packages/reporting_bridge_flutter/lib/src/flow/report_flow_controller_impl.dart
- Modify: packages/reporting_bridge_flutter/lib/src/flow/report_flow_failure.dart
- Modify: packages/reporting_bridge_flutter/lib/src/localization/report_flow_strings.dart
- Modify: packages/reporting_bridge_flutter/test/public_api_test.dart
- Modify: packages/reporting_bridge_flutter/test/contracts/report_open_request_test.dart
- Modify: packages/reporting_bridge_flutter/test/flow/report_flow_action_controller_test.dart
- Modify: packages/reporting_bridge_flutter/test/flow/report_flow_controller_test.dart
- Modify tests/helpers containing actionPolicy references.
- Delete or rewrite: packages/reporting_bridge_flutter/test/flow/report_request_policy_test.dart
- Delete or rewrite: packages/reporting_bridge_flutter/test/flow/report_print_policy_controller_test.dart
- Add: packages/reporting_bridge_flutter/test/flow/report_action_policy_absence_test.dart

**Clean-code constraint for this task:** policy removal is a mechanical migration across several files and is an allowed diff-size exception, but `report_flow_controller_impl.dart` must not absorb replacement authorization logic or unrelated cleanup. Delete policy behavior; do not replace it with a new hidden policy layer.

**Locked behavior after removal:**

ReportOpenRequest has no actionPolicy field or copyWith parameter.

BridgeUiFeatures has no restrictTo method and no import of report_action_policy.dart.

ReportFlowActionController has no actionPolicy getter.

ReportFlowControllerActions.effectiveFeatures fallback is:
- controller effectiveFeatures when available;
- otherwise request.featuresOverride;
- otherwise const BridgeUiFeatures().

ReportFlowControllerImpl uses the features passed to it directly. It must not intersect them with a policy.

Remove _ensureActionAllowed and all calls that exist only for ReportActionPolicy.

Programmatic save/share/print methods are not authorization-gated by BridgeUiFeatures. BridgeUiFeatures controls UI visibility only.

Remove ReportFlowFailureCode.actionDenied and its localization when no independent code path remains.

- [ ] Step 1: Add/convert tests first.

In report_flow_action_controller_test.dart add explicit tests:
- showPrint false does not make controller.printPdf throw actionDenied.
- showSavePdf false does not create a hidden policy gate for savePdf.
- showSharePdf false does not create a hidden policy gate for sharePdf.
Use existing ready-controller fixtures; if the action cannot complete for another real reason, assert it does not fail with actionDenied.

Add report_action_policy_absence_test.dart that source-checks:
- reporting_bridge_flutter.dart does not export report_action_policy.dart.
- ReportOpenRequest source does not contain actionPolicy.
- BridgeUiFeatures source does not contain restrictTo(.
- ReportFlowFailureCode source does not contain actionDenied.

- [ ] Step 2: Run RED.

    flutter test --no-pub test/flow/report_flow_action_controller_test.dart
    flutter test --no-pub test/flow/report_action_policy_absence_test.dart

Expected: FAIL while the policy still exists.

- [ ] Step 3: Remove public contract references.

- remove export from reporting_bridge_flutter.dart.
- remove actionPolicy constructor parameter/field/copyWith mapping from report_open_request.dart.
- remove restrictTo and import from bridge_ui_features.dart.
- remove controller interface/extension policy getters.

- [ ] Step 4: Remove implementation authorization checks.

In report_flow_controller_impl.dart:
- replace features.restrictTo(request.actionPolicy) with features.
- keep the current effective-request copy only if required by existing flow behavior; its featuresOverride must equal the effective features.
- remove actionPolicy getter.
- remove _ensureActionAllowed.
- remove every invocation of _ensureActionAllowed.
- do not replace these checks with BridgeUiFeatures checks.

- [ ] Step 5: Remove failure/localization artifacts.

- remove actionDenied enum value.
- remove the matching English/Arabic failure string branch.
- update tests that enumerate or assert this failure.

- [ ] Step 6: Remove the policy file and policy-only tests.

Delete report_action_policy.dart only after rg shows no production reference.

Run:

    rg -n "ReportActionPolicy|actionPolicy|actionDenied|restrictTo\(" lib test

Expected after cleanup: no intentional production references and no stale tests, except text in the new absence test if it is searching source strings.

- [ ] Step 7: Update request/test helpers.

Search and remove actionPolicy arguments/getters from:
- test/test_open_request.dart
- headless runner test fake controllers
- presenter web surface coordinator tests
- public print composition tests
- contract foundation tests
- any other rg result.

Do not remove unrelated request fields.

- [ ] Step 8: Run focused GREEN.

    flutter test --no-pub test/contracts/report_open_request_test.dart
    flutter test --no-pub test/flow/report_flow_action_controller_test.dart
    flutter test --no-pub test/flow/report_flow_controller_test.dart
    flutter test --no-pub test/flow/report_action_policy_absence_test.dart
    flutter test --no-pub test/ui/report_flow_strings_test.dart
    flutter test --no-pub test/public_api_test.dart

Expected: PASS.

- [ ] Step 9: Checkpoint.

    dart format lib test
    git diff --check
    git status --short

Do not commit.

---

### Task 5: Lock TemplateSyncFilter versus compatibility semantics with tests

**Files:**
- Modify: packages/reporting_bridge_flutter/test/flow/report_flow_query_scope_test.dart
- Modify: packages/reporting_bridge_flutter/test/flow/eligible_template_authority_test.dart
- Modify production flow code only if a new focused test fails and proves a real violation.

**Locked semantics:**

- sync.filter may restrict what templates are fetched/listed from server/cache.
- compatibility is evaluated independently on the resulting catalog.
- surviving the sync query does not imply eligibility.
- do not remove sync.filter from listTemplates or listTemplateDefaults merely for conceptual separation.

- [ ] Step 1: Add a query-scope test.

Assert the request TemplateSyncFilter is passed unchanged into:
- listTemplates
- listTemplateDefaults
- syncTemplates when refresh occurs

Use at least two dimensions, for example reportTypes and languages.

- [ ] Step 2: Add an eligibility test.

Construct a catalog template that survives the sync/query filter but violates one TemplateCompatibilityConstraints dimension. Assert it is not in eligibleTemplates.

- [ ] Step 3: Run the tests.

    flutter test --no-pub test/flow/report_flow_query_scope_test.dart
    flutter test --no-pub test/flow/eligible_template_authority_test.dart

If both pass immediately:
- record NO_RUNTIME_CHANGE_REQUIRED in the evidence log.
- do not edit production filtering code.

If a test fails:
- change only the code directly proven wrong by the test.
- do not broaden the refactor.

- [ ] Step 4: Checkpoint.

    git diff --check
    git status --short

Do not commit.

---

### Task 6: Documentation/public API cleanup and full Bridge verification

**Files:**
- Modify package README/examples only where they mention warmHeadlessSurface as the preferred API or ReportActionPolicy.
- Modify any public API test snapshots/source scans needed by earlier tasks.
- Do not change unrelated docs.

- [ ] Step 1: Search for stale public wording.

    rg -n "warmHeadlessSurface|warmUpHeadlessPrinting|ReportActionPolicy|actionDenied|headlessSurfaceUnavailable" packages/reporting_bridge_flutter README.md docs example

Rules:
- warmHeadlessSurface may remain only in deprecated compatibility API/tests/docs explaining migration.
- warmUpHeadlessPrinting may remain only as deprecated API/tests/docs.
- ReportActionPolicy/actionDenied must not remain as active public behavior.
- headlessSurfaceUnavailable must not remain as the generic warm-up diagnostic.

- [ ] Step 2: Update README/examples to show:

    await client.warmUpPresenter(
      request,
      refreshResources: true,
      warmPresenterSurface: true,
    );

and describe it as optional optimization usable before interactive or headless final operations.

- [ ] Step 3: Run package formatter/analyzer.

    cd packages/reporting_bridge_flutter
    dart format lib test
    flutter analyze

Expected: exit 0.

- [ ] Step 4: Run full package tests.

    flutter test

Expected: all package tests PASS.

- [ ] Step 5: Run final source scans.

    rg -n "ReportActionPolicy|actionPolicy|actionDenied|restrictTo\(" lib test
    rg -n "headlessSurfaceUnavailable" lib test

Expected:
- no active policy implementation references.
- no generic stale headless diagnostic.
- deprecated compatibility names may remain only where intentionally documented/tested.

- [ ] Step 6: Save verification evidence.

    mkdir -p /Users/abdualhabib/Downloads/agent-state/URB_FINAL_IMPLEMENTATION/bridge
    git diff --check > /Users/abdualhabib/Downloads/agent-state/URB_FINAL_IMPLEMENTATION/bridge/final-diff-check.txt
    git status --short --branch > /Users/abdualhabib/Downloads/agent-state/URB_FINAL_IMPLEMENTATION/bridge/final-status.txt
    git diff > /Users/abdualhabib/Downloads/agent-state/URB_FINAL_IMPLEMENTATION/bridge/final.patch

- [ ] Step 7: Final checkpoint.

Do not commit or push.

## Bridge Plan Completion Criteria

The Bridge track is ready for the Demo Host track only when all are true:
- warmPresenterSurface is the preferred public warm-up option.
- legacy warmHeadlessSurface still maps correctly.
- openReport borrows/reuses the managed surface.
- headless print/PDF still reuse the managed surface.
- closing interactive UI does not shutdown the borrowed surface.
- client.dispose shuts it down exactly once.
- active-flow warm-up does not touch the surface.
- factory-only explicit shared warm-up reports unavailable without breaking final headless operations.
- ReportActionPolicy/actionDenied duplicate authorization is removed.
- sync/query versus compatibility tests are explicit.
- flutter analyze passes.
- full reporting_bridge_flutter tests pass.
