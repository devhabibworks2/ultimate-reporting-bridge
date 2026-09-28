# ESC/POS and Headless Printing Migration Design

**Date:** 2026-09-28
**Status:** Approved design, pending implementation plan
**Primary repository:** ultimate-reporting-bridge
**Source:** origin/esc_pos_printer at 7624f4cea1bc40aa56e38746985c7befbafa526b
**Target:** uat/ios-presenter-cross-platform-20260928 at 9548ec4f91bf570e97af2f91669427af316c8354
**Shared base:** 96b54a7a89d4d842e73e0a307830c57cb159a6f1

## 1. Goal

Migrate Android ESC/POS thermal printing and headless/direct printing from origin/esc_pos_printer into the current Bridge UAT line while preserving the current iOS Presenter proxy and WebView fixes.

The result must expose one authoritative print-mode selection per platform, preserve interactive and headless printing through the same ReportPrintPlatform abstraction, and provide no automatic fallback between Android print modes.

## 2. Source and target authority

The target UAT branch is authoritative for Presenter/session behavior introduced after the shared base:

- a9198fc — proxy online Presenter through localhost.
- d9fc632 — keep online Presenter runtime same-origin.
- 9548ec4 — avoid unsupported WebView navigation override.

The source branch contributes five commits:

- 72a29c5 — native Android ESC/POS thermal printing.
- 20b1085 — localized thermal-printer settings.
- 4d5b32e — headless print public API.
- dbdb77b — headless report printing.
- 7624f4c — printing performance, progress, connection, and session optimizations.

Migration strategy: selective forward-port. Do not merge or cherry-pick the source branch wholesale where doing so would overwrite current Presenter/session behavior.

## 3. Android print-mode contract

Extend the existing AndroidPrintMode:

~~~dart
enum AndroidPrintMode {
  escPos,
  systemPrintManager,
  externalApp,
}
~~~

Semantics are authoritative and mutually exclusive:

- escPos selects ThermalReportPrintPlatform.
- systemPrintManager selects AndroidReportPrintPlatform configured for Android System Print Manager.
- externalApp preserves the existing external printer-application contract.

There is no automatic fallback between Android modes. Failure from the selected mode is returned directly.

## 4. iOS print-mode contract

Add an iOS mode for API consistency:

~~~dart
enum IosPrintMode {
  airPrint,
}
~~~

IosPrintMode.airPrint selects IosAirPrintReportPrintPlatform.

## 5. Defaults and override precedence

Default configuration:

- iOS -> AirPrint.
- Android -> ESC/POS.
- Other platforms -> UnsupportedReportPrintPlatform.

An explicit host-supplied ReportPrintPlatform override remains authoritative over managed defaults.

No second Android print-selection enum is introduced.

## 6. Managed platform composition

ReportingBridgeFlutter owns managed print-platform composition when the host does not provide an explicit ReportPrintPlatform.

Resolution order:

~~~text
Explicit host ReportPrintPlatform
  -> use exactly that platform

Otherwise iOS
  -> IosPrintMode.airPrint
  -> IosAirPrintReportPrintPlatform

Otherwise Android
  -> AndroidPrintMode.escPos
       -> ThermalReportPrintPlatform
  -> AndroidPrintMode.systemPrintManager
       -> AndroidReportPrintPlatform(systemPrintManager)
  -> AndroidPrintMode.externalApp
       -> AndroidReportPrintPlatform(externalApp)

Otherwise
  -> UnsupportedReportPrintPlatform
~~~

Managed thermal resources must have deterministic ownership and disposal. Host-supplied print platforms are never silently replaced.

## 7. ESC/POS implementation

ThermalReportPrintPlatform is the ESC/POS implementation, not a mode.

Required flow:

~~~text
PDF bytes
  -> ThermalReportPrintPlatform
  -> load configured ThermalPrinterProfile
  -> stage PDF artifact
  -> rasterize PDF
  -> convert/transmit ESC/POS data
  -> Bluetooth / USB / TCP printer
~~~

Preserve these source-branch capabilities:

- Bluetooth, USB, and TCP printers.
- Bluetooth and USB permission handling.
- Paired Bluetooth discovery and connected USB discovery.
- Persistent default thermal-printer profile.
- 58 mm / 384 px and 80 mm / 576 px widths.
- Copies, gradient/raster settings, feed dots, and cut-after-print.
- Test-print PDF.
- Known unavailable Bluetooth-printer detection.
- Native progress events.
- Reliable Bluetooth and TCP transport.
- PDF stripe rasterization and transport timeouts.

Migrate the DantSu ESC/POS dependency and required Android permissions/features.

## 8. Existing Android print paths

### System Print Manager

AndroidPrintMode.systemPrintManager uses Android System Print Manager only. No thermal or external-app attempt occurs before or after it.

### External application

AndroidPrintMode.externalApp preserves the existing external printer application flow, including its package/action contract and setup behavior.

No ESC/POS or System Print Manager fallback occurs if external-app printing fails.

## 9. Common interactive/headless terminal path

Interactive and headless printing must converge on the same call:

~~~dart
controller.printPdf()
~~~

Interactive flow:

~~~text
Visible Presenter
  -> render report
  -> generate PDF
  -> controller.printPdf()
  -> configured ReportPrintPlatform
~~~

Headless/direct flow:

~~~text
Hidden Presenter
  -> render report
  -> generate PDF
  -> controller.printPdf()
  -> same configured ReportPrintPlatform
~~~

The headless runner must not contain independent print-mode selection logic.

## 10. Meaning of headless

Headless means the Presenter UI is hidden. It does not mean native print UI must be silent.

AirPrint headless:

~~~text
Hidden Presenter
  -> PDF
  -> IosAirPrintReportPrintPlatform
  -> native iOS print dialog
~~~

Android System Print Manager headless:

~~~text
Hidden Presenter
  -> PDF
  -> AndroidReportPrintPlatform
  -> native Android print dialog
~~~

ESC/POS headless:

~~~text
Hidden Presenter
  -> PDF
  -> ThermalReportPrintPlatform
  -> configured Bluetooth / USB / TCP printer directly
~~~

Once a valid thermal profile exists, ESC/POS headless printing needs no system print dialog.

AirPrint and Android System Print Manager need no new native print implementation for headless support; they need integration with the shared headless runner and verification.

## 11. Headless public API

Preserve the source branch APIs:

~~~dart
Future<ReportPrintResult> printReportHeadless(
  ReportOpenRequest request, {
  HeadlessReportPrintProgressCallback? onProgress,
  HeadlessReportPrintTimingCallback? onTiming,
});
~~~

~~~dart
Future<HeadlessPrintWarmupResult> warmUpHeadlessPrinting(
  ReportOpenRequest request, {
  bool refreshResources = false,
});
~~~

Preserve reusable hidden Presenter surface, WebView warm-up, render lifecycle, PDF generation, thermal progress mapping, timing callbacks, optional background resource refresh, and deterministic disposal.

The headless runner always finishes through controller.printPdf().

## 12. Presenter surface coordination

The PresenterWebSurfaceCoordinator concept may be migrated so visible and hidden Presenter surfaces share lifecycle wiring.

Current iOS behavior is authoritative:

- Do not restore useShouldOverrideUrlLoading: true.
- Do not add a navigation override without an explicit allow policy.
- Preserve the regression protection introduced by 9548ec4.

Visible and hidden Presenter surfaces must share corrected lifecycle/message semantics.

## 13. Local Presenter server and session reconciliation

The source branch supports multiple overlapping runtime sessions on one localhost server. The target branch adds same-origin online Presenter proxying.

These capabilities must be reconciled.

Target model:

~~~text
Managed localhost server
  -> online Presenter proxy routes
  -> offline Presenter routes
  -> /runtime/<sessionId>/...
       -> visible session
       -> hidden/headless session(s)
~~~

Requirements:

- Multiple active session IDs may coexist where required.
- Releasing one session removes only that session.
- Starting a new report does not unnecessarily restart the server.
- Same-origin online proxying remains intact.
- Offline Presenter serving remains intact.
- Runtime paths remain session-scoped and path-safe.
- Server/proxy/shared-client resources are disposed at the owning Bridge/client lifecycle boundary.
- Concurrent/session lifecycle gets dedicated regression tests.

## 14. Performance and progress

Port source-branch performance improvements only after adapting them to current proxy/session semantics.

Retain:

- reusable/warm hidden WebView surface.
- background-only resource synchronization for headless printing.
- shared HTTP client where ownership is safe.
- preparing, connecting, rasterizing, transmitting, and printing progress.
- byte-count progress where available.
- headless timing diagnostics.
- reliable Bluetooth and TCP transfers.

Performance changes must not weaken correctness, isolation, cleanup, or current iOS behavior.

## 15. Thermal settings UI

Migrate the thermal-printer settings experience:

- Arabic/English localization and locale override.
- Bluetooth and USB refresh.
- Permission states and prompts.
- TCP host/port configuration.
- Width, copies, gradient, feed, and cut settings.
- Save/remove profile.
- Test print.
- Unavailable saved-Bluetooth-printer indication.

The settings UI configures ThermalPrinterProfile. It does not select the global Android print mode.

## 16. Demo Host integration

The URB Demo Host is the UAT consumer.

Defaults:

- iOS -> AirPrint.
- Android -> ESC/POS.

The Demo Host must also allow deliberate testing of all three AndroidPrintMode values. Changing mode is explicit configuration; there is no runtime fallback.

The testing-only hardcoded API credential currently used by the Demo Host remains in place for this UAT line by explicit project decision. Its value must not be copied into this spec, migration logs, commit messages, or new test fixtures.

## 17. Repository hygiene

In the URB repository:

- .cursorignore becomes developer-local.
- .cursorindexingignore becomes developer-local.
- both names are added to .gitignore.
- both files are removed from Git tracking with git rm --cached.
- both files remain on the developer workstation.

This is repository hygiene only and is not part of the print runtime.

## 18. Error handling

Each selected print mode is authoritative.

ESC/POS preserves typed outcomes such as setup required, permission denied, device unavailable, connection failure, invalid PDF/request, rasterization failure, busy, and native failure.

A thermal failure must not open System Print Manager or the external app.

System Print Manager returns its own result/failure directly.

External-app mode preserves existing setup, app-not-installed, contract, and error behavior.

AirPrint preserves availability, cancellation, submission, and typed failure behavior.

## 19. Migration boundaries

Implementation order:

1. Public print-mode contracts and tests.
2. ESC/POS models and persistence.
3. Android native/Pigeon thermal transport.
4. ThermalReportPrintPlatform.
5. Thermal settings UI/localization.
6. Managed platform composition and lifecycle.
7. Headless public contracts.
8. Hidden Presenter implementation.
9. Presenter coordinator integration.
10. Local proxy + multi-session reconciliation.
11. Performance/progress refinements.
12. Demo Host mode configuration and repository hygiene.
13. Cross-platform build/test/UAT verification.

Each behavior-changing task uses TDD and ends with focused verification and a commit.

## 20. High-risk overlap files

Treat these files as high-risk:

- packages/reporting_bridge/lib/src/bridge_local_server.dart
- packages/reporting_bridge/lib/src/bridge_presenter_session.dart
- packages/reporting_bridge_flutter/lib/src/ui/bridge_presenter_view.dart
- packages/reporting_bridge_flutter/lib/src/client/reporting_bridge_flutter.dart
- packages/reporting_bridge_flutter/lib/src/client/reporting_bridge_flutter_client.dart
- packages/reporting_bridge_flutter/lib/src/flow/report_flow_controller_impl.dart
- packages/reporting_bridge_flutter/lib/src/ui/report_flow_screen.dart

Changes to the first three must explicitly prove preservation of the current iOS Presenter fixes.

## 21. Verification strategy

Bridge core verification:

- formatting.
- static analysis.
- full tests.
- same-origin online Presenter proxy regression.
- proxy status/content-type/body forwarding.
- transport failure handling.
- path safety.
- concurrent runtime session isolation.
- deterministic server/client disposal.

Bridge Flutter verification:

- formatting.
- static analysis.
- full Flutter tests.
- Android mode selection.
- no cross-mode fallback.
- iOS mode selection.
- host override precedence.
- thermal persistence/settings.
- Bluetooth/USB/TCP behavior.
- thermal progress and busy protection.
- localization.
- visible and hidden Presenter lifecycle.
- common controller.printPdf() termination.
- headless progress/timing.
- WebView navigation-override regression.
- managed print-platform disposal.

Android verification:

- migrated native unit tests.
- Android build.
- physical Bluetooth ESC/POS UAT.
- physical USB ESC/POS UAT.
- TCP ESC/POS UAT.
- System Print Manager UAT.
- external-app UAT where available.
- interactive and headless printing.

iOS verification:

- iOS build.
- interactive AirPrint UAT.
- headless AirPrint UAT with native print dialog.
- online same-origin Presenter UAT.
- offline Presenter UAT.

## 22. Acceptance criteria

The migration is accepted only when:

1. AndroidPrintMode contains escPos, systemPrintManager, and externalApp.
2. There is no second Android print selector.
3. IosPrintMode.airPrint exists.
4. iOS defaults to AirPrint.
5. Android defaults to ESC/POS.
6. Other platforms default to UnsupportedReportPrintPlatform.
7. Explicit host ReportPrintPlatform overrides remain authoritative.
8. Android modes never automatically fall back.
9. escPos selects ThermalReportPrintPlatform with Bluetooth, USB, and TCP.
10. systemPrintManager selects Android System Print Manager only.
11. externalApp preserves existing external-app behavior.
12. airPrint selects IosAirPrintReportPrintPlatform.
13. Interactive printing terminates through controller.printPdf().
14. Headless printing terminates through the same controller.printPdf().
15. Headless Presenter UI is hidden.
16. Headless AirPrint shows the native iOS print dialog.
17. Headless System Print Manager shows the native Android print dialog.
18. Headless ESC/POS prints directly once configured.
19. Current same-origin iOS Presenter proxy remains intact.
20. Current offline Presenter behavior remains intact.
21. useShouldOverrideUrlLoading: true is not restored.
22. Multi-session optimization does not break proxy/session isolation.
23. Relevant Dart, Flutter, and native tests pass.
24. Android and iOS builds pass.
25. Physical/manual UAT covers each configured print mode.
26. .cursorignore and .cursorindexingignore are developer-local and ignored by Git in URB.
27. The testing-only Demo Host credential remains available for UAT without being duplicated into new docs/logs/fixtures.

## 23. Non-goals

This migration does not:

- add an automatic Android fallback chain.
- make AirPrint or Android System Print Manager silent.
- replace the existing external printer application contract.
- create another Android print-selection enum.
- redesign report rendering or PDF generation.
- replace the current same-origin Presenter proxy.
- change the approved offline Presenter bundle format.
- add iOS ESC/POS support.
- push, merge, tag, or release UAT branches.

## 24. Implementation constraint

No implementation task may treat origin/esc_pos_printer as authoritative for an overlapping file merely because that branch changed it later in its own history.

When a source-branch change overlaps current UAT Presenter/proxy behavior, preserve the current UAT semantics and port only the required capability.
