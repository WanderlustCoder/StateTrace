# Plan H Bundle Workflow

Use this checklist to produce a Plan H-ready telemetry bundle (UserAction coverage + freshness evidence) with readiness outputs.

## Steps
1) **Generate telemetry**
   - Run UI/headless flow to emit `UserAction` events (ScanLogs, LoadFromDb, HelpQuickstart, InterfacesView, CompareView, SpanSnapshot).
   - Ensure cache-provider/status signals are present (freshness tooltip) so `FreshnessTelemetrySummary` captures source/provider per site.

2) **Summaries**
   ```pwsh
   pwsh -NoLogo -File Tools\Analyze-UserActionTelemetry.ps1 -Path Logs\IngestionMetrics\<date>.json -OutputPath Logs\Reports\UserActionSummary-<date>.json
   pwsh -NoLogo -File Tools\Analyze-FreshnessTelemetry.ps1 -Path Logs\IngestionMetrics\<date>.json -OutputPath Logs\Reports/FreshnessTelemetrySummary-<date>.json
   ```

3) **Publish bundle (enforces Plan H readiness)**
   ```pwsh
   pwsh -NoLogo -File Tools\Publish-TelemetryBundle.ps1 `
     -BundleName UI-<date>-<tag> `
     -AreaName UI `
     -ColdTelemetryPath Logs\IngestionMetrics\<date>.json `
     -UserActionSummaryPath Logs\Reports\UserActionSummary-<date>.json `
     -FreshnessSummaryPath Logs\Reports\FreshnessTelemetrySummary-<date>.json `
     -AdditionalPath @('Logs\Reports\InterfacesViewChecklist-<date>.json','Logs\Reports\InterfacesViewQuickstart-<date>.json') `
     -PlanReferences docs/plans/PlanH_UserExperience.md `
     -TaskBoardIds ST-H-001,ST-H-003 `
     -Notes 'Plan H UI evidence' `
     -Force -VerifyPlanHReadiness
   ```
   - `PlanHReadiness.json` is written inside the bundle; publish fails if coverage is missing.

4) **Record outputs**
   - Cite bundle path + `PlanHReadiness.json` in Plan H timeline, backlog, task board, and session log.
   - Attach freshness/UserAction summary paths to the session log.

5) **Screenshots (if available)**
   - Capture freshness tooltip/help/Interfaces views; store under `docs/performance/screenshots/` and reference in Plan H.
