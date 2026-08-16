# Bridge Contract

This is not an HTTP API. It is the typed integration contract between Host apps, Bridge, Presenter, and Admin/browser workflows.

## Contract Versioning

- Every payload must include `contractVersion`.
- Async calls should include `correlationId`.
- Calls must define timeout behavior.
- Sensitive custom API header values must be redacted in status/log payloads.

Current planned contract version:

```text
1
```

## Flutter Workflow Profile

Flutter hosts integrate through `reporting_bridge_flutter` rather than calling the low-level operation list as a UI workflow:

```text
openReport(request)       # default full UI
createController(request) # headless/custom UI using the same state machine
```

The Host supplies Report Server connection/profile, system, report type/name, immutable runtime or seed data, locale, optional UI configuration, and an approved dynamic-header provider.

`reporting_bridge_flutter` owns Preparation, synchronization status, Template Selection, Presenter mode, Preview, Settings, Save/Share, scoped defaults, Back/close, cleanup, and recovery. Headless mode changes presentation ownership only; it does not transfer transport, cache, persistence, runtime-session, export, or lifecycle ownership back to the Host.

The lower-level calls below describe the core capability surface and non-Flutter adapters. They must not be reassembled into a duplicate Flutter Host workflow.

## Host -> Bridge

Host apps call Bridge. Host apps must not call Presenter directly.

```text
initializeBridge
setBrandConfig
setServerConfig
setApiHeaders
setActionsUiState

syncPresenterSite
syncTemplates

openReportSetup

getAvailableTemplates
setSelectedTemplate
getSelectedTemplate
clearSelectedTemplate

setReportName
setReportType
setSeedData

prepareRuntimeSession
rebuildReport
openPreview

savePdf
sharePdf
printPdf
shareImage

clearRuntimeSession
clearTemplateCache
clearPresenterCache

getBridgeStatus
disposeBridge
```

Do not add:

```text
getSelectedTemplateForFamily
setSelectedTemplateForFamily
clearSelectedTemplateForFamily
openTemplateSelection
openTemplateSettings
```

Use `openReportSetup()` as the single setup/settings entry point.

## Host Boot Config

Example:

```json
{
  "contractVersion": 1,
  "type": "invoice",
  "reportName": "Sales Invoice",
  "locale": "en",
  "direction": "ltr",
  "branding": {
    "primaryColor": "#2563EB"
  },
  "presenterUrl": "https://client-server.com/presenter",
  "seedData": {},
  "apiHeaders": {
    "Authorization": "Bearer <redacted>",
    "X-Tenant-Id": "tenant_001",
    "X-Branch-Id": "branch_01"
  },
  "templateHints": {
    "templateId": "34"
  }
}
```

## Selected Template

Bridge stores selected template exactly:

```json
{
  "selectedTemplates": {
    "id": "34",
    "type": "invoice"
  }
}
```

Rules:

- `id` is the selected template ID.
- `type` is the report/template type.
- Bridge validates `id` and `type` against available templates before preview/export.
- Bridge auto-selects when exactly one compatible template exists for the current type.

## Bridge -> Host Callbacks

```text
onBridgeReady
onModeChanged

onReportSetupRequired
onReportSetupStarted
onReportSetupCompleted

onPresenterSyncStarted
onPresenterSyncProgress
onPresenterSyncCompleted

onTemplateSyncStarted
onTemplateSyncProgress
onTemplateSyncCompleted

onTemplateSelectionRequired
onTemplateSelectionSkipped
onSelectedTemplateChanged

onRuntimeSessionPrepared

onPreviewOpened
onReportRenderStarted
onReportRenderCompleted

onSaveCompleted
onSharePdfCompleted
onShareImageCompleted
onPrintCompleted

onWarnings
onError
```

## Bridge -> Presenter

```text
initializeRuntime
loadRuntimeSession
applyInlineSession

exportPdf
exportImage
printPdf

getRenderStatus
disposeSession
ping
```

### applyInlineSession (NEW)

Pushes an inline template document + runtime data via MethodChannel (0 HTTP calls). The same logical payload format is used by Admin (web postMessage) and Bridge (mobile MethodChannel).

```json
{
  "contractVersion": 1,
  "templateDocument": { "... full document ..." },
  "runtimeData": { "... full seed data ..." },
  "sessionData": { "... optional metadata ..." },
  "wantPdf": false,
  "mode": "preview",
  "templateName": "optional name",
  "templateId": 42
}
```

`templateDocument` must use the active saved-template schema root: `schemaVersion`, `meta`, `page`, `styleTokens`, `assets`, `layers`, and `elements`. Bridge and Presenter must reject old saved-template roots instead of converting them at runtime.

## Presenter -> Bridge/Admin

```text
onPresenterReady

onRuntimeSessionLoaded
onSeedDataLoaded
onTemplateLoaded

onRenderStarted
onRenderCompleted
onRenderFailed

onExportStarted
onExportCompleted
onExportFailed

onPrintStarted
onPrintCompleted

onHeightChanged

onWarnings
onError
onLog
```

## Admin -> Presenter

Admin may communicate directly with Presenter for browser workflows:

```text
openPresenterPreview
openPresenterPdf
sendAdminHandoff
validatePresenterReachability
handlePresenterCallback
```

Admin direct flow does not require Bridge localhost/offline logic.

## Runtime Files

Bridge prepares:

```text
seed_report_data.json
template.json
session.json
```

`template.json` contains the selected published template document in the active new schema. It is not a place for runtime conversion or old schema fallback.

Offline mobile Presenter URL:

```text
http://127.0.0.1:{port}/UltimateReport/apps/presenter/index.html?sessionId={sessionId}
```

## Error Codes

```text
OFFLINE_ASSETS_NOT_READY
NO_TEMPLATE_AVAILABLE
PRESENTER_VERSION_TOO_OLD
TEMPLATE_VERSION_TOO_OLD
CUSTOM_HEADERS_INVALID
LOCALHOST_SERVER_UNAVAILABLE
RUNTIME_SESSION_INVALID
PRESENTER_OPEN_FAILED
PDF_EXPORT_FAILED
IMAGE_EXPORT_FAILED
PRINT_FAILED
```

## Security Rules

- Treat custom API headers as privileged.
- Redact header values in logs/status/callbacks.
- Forward headers only to approved backend/template/Presenter requests.
- Validate postMessage origins where possible.
- Keep local server loopback-only.
- Disable directory listing.
- Do not expose broad host APIs to Presenter JavaScript.
