# Repository Map

This document describes the intended repository layout and how the major pieces connect.
It is designed for:
- new developers,
- Codex-style agents,
- and reviewers validating that changes land in the correct layer.

Update this file whenever directories move or responsibilities change.

## LANDMARK: High-level architecture
StateTrace is organized around a repeatable ingestion + telemetry loop:
1. Inputs (fixtures, device logs, snapshots)
2. Parsing (normalize raw logs/snapshots)
3. Persistence (Access-backed local store)
4. Cache strategy (shared cache snapshots + normalization)
5. Diff/change tracking (Plan C; snapshot health, diff model)
6. UI surfaces (Plan D/H/O)
7. Telemetry (Plan E; phase dictionaries, rollups, bundles)
8. Governance (Plan G/R; releases, incidents, evidence)

## LANDMARK: Directory ownership map

The following is the authoritative "who owns what" map.

| Path | Purpose | Primary owners | Notes |
|------|---------|----------------|-------|
| `Tools\` | PowerShell entrypoints for pipeline, verification, warm runs, rollups, bundling | Automation / Platform | Keep these stable; agents use them as front doors. |
| `Modules\` | PowerShell modules (core logic), helpers, guards | Ingestion / UI / Telemetry | Prefer composable modules; minimize script-level logic. |
| `Modules\Tests\` | Pester tests (unit + small integration) | QA / Automation | Avoid gitignored fixtures. |
| `Main\` | WPF shell (MainWindow XAML + code-behind) | UI | Primary UI entrypoint. |
| `Views\` | XAML view definitions (Summary, Interfaces, Alerts, Search, etc.) | UI | Keep bindings in sync with view modules. |
| `Templates\` | Vendor templates and show-command definitions | Parser / UI | See TemplatesModule. |
| `Themes\` | WPF theme resources | UI | Shared brushes/styles. |
| `Resources\` | Shared assets/resources | UI | Images and common resources. |
| `Tests\` | Ad-hoc harness scripts | QA / UI | Example: `Tests/Invoke-MainWindowSmokeTest.ps1`. |
| `Tests\Fixtures\` | Sanitized fixture seeds/templates | QA / Automation | Create when needed; keep small and documented. |
| `Data\` | Access DBs, ingestion history, settings | Ingestion / Platform | Per-site `Data/<site>/<site>.accdb`, plus `Data/IngestionHistory` and `Data/StateTraceSettings.json`. |
| `Logs\` | Generated artifacts (telemetry, reports, bundles, UI logs) | Everyone | Never commit. |
| `docs\` | Plans, runbooks, telemetry dictionaries, governance | PMO / Telemetry / Automation | Plans A-S + doc-sync workflows. |
| `docs\plans\` | Individual plan pages (A-S) | Plan owners | Link-stable. |
| `docs\taskboard\` | Machine-readable board snapshot (`TaskBoard.csv`) | PMO | Keep in sync with `StateTrace_TaskBoard.md`. |
| `Troubleshooting\` | Operator/developer troubleshooting scripts | Support | Keep aligned with docs/troubleshooting. |

## LANDMARK: Primary entrypoints (commands)

These scripts are referenced throughout Plans I/J/K/E/G. They should remain stable and well-documented:

- Cold pipeline: `Tools\Invoke-StateTracePipeline.ps1`
- Verification harness: `Tools\Invoke-StateTraceVerification.ps1`
- Warm-run telemetry: `Tools\Invoke-WarmRunTelemetry.ps1`
- Warm-run regression: `Tools\Invoke-WarmRunRegression.ps1`
- Headless UI smokes: `Tools\Invoke-SearchAlertsSmokeTest.ps1`, `Tools\Invoke-SpanViewSmokeTest.ps1`, `Tools\Invoke-InterfacesViewChecklist.ps1`
- Bundle publisher: `Tools\Publish-TelemetryBundle.ps1`
- Telemetry rollups: `Tools\Rollup-IngestionMetrics.ps1`, `Tools\Invoke-DailyMetricRollup.ps1`
- Fixture expansion: `Tools\Expand-MockLogCorpus.ps1`
- Aggregated checks: `Tools\Invoke-AllChecks.ps1`

Each entrypoint should:
- return a non-zero exit code on failure
- emit outputs under `Logs\` (IngestionMetrics, Reports, SharedCacheDiagnostics, TelemetryBundles)
- log any overrides and restore settings where applicable
- update the runbook and plan docs when flags/outputs change

## LANDMARK: Key artifacts and where they should live

| Artifact | Why it exists | Expected path |
|----------|---------------|---------------|
| Ingestion metrics JSON | Plan E rollups + perf tracking | `Logs/IngestionMetrics/<date>.json` (or `Logs/IngestionMetrics/Run-<timestamp>/...` when `STATETRACE_TELEMETRY_DIR` is set) |
| Queue delay summary | gating (Plan A/K) | `Logs/IngestionMetrics/QueueDelaySummary-<timestamp>.json` |
| Port batch diversity report | gating (Plan D/K) | `Logs/Reports/PortBatchSiteDiversity-<timestamp>.json` |
| Scheduler fairness report | gating (Plan A/D) | `Logs/Reports/ParserSchedulerLaunch-<date>.json` |
| Shared cache diagnostics | gating (Plan B/Q) | `Logs/SharedCacheDiagnostics/SharedCacheStoreState-<timestamp>.json`, `Logs/SharedCacheDiagnostics/SiteCacheProviderReasons-<timestamp>.json` |
| Shared cache snapshots | warm reuse + auditing | `Logs/SharedCacheSnapshot/SharedCacheSnapshot-<timestamp>.clixml` (+ summary JSON, latest pointers) |
| Warm-run telemetry | performance baselines | `Logs/IngestionMetrics/WarmRunTelemetry-<timestamp>.json` |
| Warm-run diff hotspots | perf triage | `Logs/IngestionMetrics/DiffHotspots-<timestamp>.csv` |
| Telemetry bundle | governance / release evidence | `Logs/TelemetryBundles/<bundle>/<Area>/TelemetryBundle.json` (+ README + artifacts) |
| UI smoke evidence | UI validation | `Logs/Reports/InterfacesViewChecklist-*.json`, `docs/performance/screenshots/*.png`, `Logs/UI/ParserJob-*.log` |

## LANDMARK: Where to document changes

- If you add or change a harness flag: update
  - this file (`Repo_Map.md`)
  - `docs/CODEX_PLAN_AUTOMATION_MATRIX.md`
  - the relevant plan page (A-S)
- If you change an artifact path or schema:
  - update `docs/schemas/**`
  - update rollup/bundling scripts to match
  - add migration notes to the plan(s) and Task Board entry
