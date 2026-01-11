# Code review entrypoints (2026-01-09)

This list highlights the primary execution paths to review first and cross-link in the ledger.

## UI entrypoints
- `Main/MainWindow.ps1` (WPF shell startup, module loading, view composition)
- `Main/MainWindow.xaml` (root UI bindings and resources)

## Parser/ingestion entrypoints
- `Modules/ParserWorker.psm1` (ingestion orchestration, telemetry, Access writes)
- `Modules/ParserRunspaceModule.psm1` (scheduler, concurrency, runspace lifecycle)
- `Modules/ParserPersistenceModule.psm1` (Access write helpers, schema interactions)
- `Modules/DeviceLogParserModule.psm1` (log parsing + ingestion pipeline)

## Tooling entrypoints (readiness + telemetry)
- `Tools/Invoke-StateTracePipeline.ps1` (cold ingestion + shared cache handling)
- `Tools/Invoke-WarmRunRegression.ps1` (warm pass regression)
- `Tools/Invoke-WarmRunTelemetry.ps1` (warm telemetry capture + diagnostics)
- `Tools/Invoke-StateTraceVerification.ps1` (Plan G verification harness)
- `Tools/Invoke-StateTraceScheduledVerification.ps1` (scheduled verification)

## UI harness entrypoints (if UI in scope)
- `Tools/Invoke-InterfacesViewSmokeTest.ps1`
- `Tools/Invoke-SearchAlertsSmokeTest.ps1`
- `Tools/Invoke-SpanViewSmokeTest.ps1`
- `Tools/Invoke-PlanHBundle.ps1`

## Diagnostics/analysis entrypoints
- `Tools/Analyze-SharedCacheStoreState.ps1`
- `Tools/Analyze-SiteCacheProviderReasons.ps1`
- `Tools/Analyze-InterfaceSyncTiming.ps1`
- `Tools/Test-ParserSchedulerFairness.ps1`
