# Plan E – Telemetry & Launch Metrics

## Objective
Capture, roll up, and verify the telemetry needed for operations (Phase 1 dictionary) plus engineering automation. Plan E owns the ingestion metrics schema, rollup scripts, verification harness thresholds, and telemetry documentation.

## Current status (2025-11)
- Phase 1 telemetry dictionary (`docs/telemetry/Phase1_metrics.md`) is live and tracks ParseDuration, DatabaseWriteLatency, RowsWritten, DiffUsageRate, and Drift metrics, but several plan metrics (e.g., Span view usage, PortBatchReady summaries, WarmRunComparison) still lack schema notes or rollup coverage—ST-E-004 remains blocked until every plan updates its schema rows.
- `Tools/Rollup-IngestionMetrics.ps1` plus the wrapper (`Tools/Invoke-DailyMetricRollup.ps1`) are documented in `docs/CODEX_RUNBOOK.md` and the 2025-11-12 agent session log (`docs/agents/sessions/2025-11-12_session-0002.md`), yet teams have not scheduled them—Plan E must push adoption beyond ad-hoc runs and store artifacts under `Logs/IngestionMetrics/IngestionMetricsSummary-*.csv` with cadence documented in `docs/StateTrace_TaskBoard.md`.
- `docs/CODEX_PLAN_AUTOMATION_MATRIX.md` now routes plan-specific automation back to this plan, so every telemetry script/run needs a matching entry here, on the task board, and inside the doc-sync checklist (`docs/CODEX_DOC_SYNC_PLAYBOOK.md`).
- Warm-run verification ties directly to Plan B; Plan E keeps `docs/telemetry/Automation_Gates.md` current, mirrors cache-related metrics, and must ingest the shared-cache analyzer output plus Plan B's telemetry bundles when publishing rollups so governance reviews have a single reference.
- Plan G relies on Plan E to populate `Logs/TelemetryBundles/<version>/` with rollup CSVs, analyzer output, and warm-run summaries before sign-off; run `Tools\Publish-TelemetryBundle.ps1` (auto-discovers the latest files and calls `Tools\New-TelemetryBundle.ps1`) after each rollup so ST-E-007 (and Plan G ST-G-007) stay unblocked.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-E-003 | Schedule the daily rollup harness | Telemetry | Backlog | Stand up a scheduled run (Task Scheduler or CI) for `Tools/Invoke-DailyMetricRollup.ps1 -Days 1 -IncludePerSite -IncludeSiteCache`, publish the generated `Logs/IngestionMetrics/IngestionMetricsSummary-<timestamp>.csv`, and document the cadence in `docs/StateTrace_TaskBoard.md`. |
| ST-E-004 | Phase 1 dictionary coverage refresh | Telemetry + Plan owners | Backlog | Compare each metric in `docs/telemetry/Phase1_metrics.md` with the per-plan telemetry gates; add missing schema fields (e.g., `InterfaceSiteCacheMetrics`, `PortBatchReady`, `WarmRunComparison`) and link the updates back to the relevant plan sections. |
| ST-E-005 | Telemetry gate enforcement harness | Automation | Backlog | Extend `Modules/Tests/RollupIngestionMetrics.Tests.ps1` (or add a sibling suite) so `Tools/Rollup-IngestionMetrics.ps1` and `Tools/Invoke-DailyMetricRollup.ps1` validate gate thresholds (`ParseDuration`, `RowsWritten`, `DatabaseWriteLatency`) before publishing CSVs; integrate the checks with `Tools/Invoke-StateTraceVerification.ps1` once complete. |
| ST-E-006 | UI telemetry ingestion (Plan D handoff) | Telemetry + UI | Backlog | Add schema entries for `SpanViewUsage`, `UIRunbookStep`, or equivalent once Plan D emits events; ensure rollups ingest the files and expose the metrics alongside ingestion stats. |
| ST-E-007 | Release-readiness telemetry bundle | PMO + Telemetry | Backlog | Use `Tools\New-TelemetryBundle.ps1` to populate `Logs/TelemetryBundles/<date>/` with the latest rollup CSV, shared-cache analyzer output, warm-run telemetry summary, and automation-gates diff so Plan G can reference a single artifact per release (README must list commands, plan/task IDs, and verification status). |
| ST-E-008 | Task board alignment | Telemetry | Backlog | Ensure every telemetry task (ST-E-003 upwards) has a matching entry in `docs/StateTrace_TaskBoard.md` / `docs/taskboard/TaskBoard.csv`; capture the rollup path and telemetry artifacts in the task notes for future agents. |
| ST-E-009 | Plan A telemetry bundle handoff | Telemetry + Routing | Backlog | Use `Tools\Publish-TelemetryBundle.ps1 -AreaName Routing` to pull Plan A logs + dispatcher evidence into each `Logs/TelemetryBundles/<date>/` package so release reviews see the full cross-plan dataset. |

## Recently delivered
| ID | Date | Summary | Evidence |
|----|------|---------|----------|
| ST-E-001 | 2025-11-06 | Published `docs/telemetry/Automation_Gates.md` and linked every plan/task to the shared telemetry thresholds. | `docs/telemetry/Automation_Gates.md`, plan updates, task board entries. |
| ST-E-002 | 2025-11-12 | Added `Tools/Invoke-DailyMetricRollup.ps1`, updated README + Codex Runbook so daily ingestion summaries can be generated (and scheduled) with one command. | `Tools/Invoke-DailyMetricRollup.ps1`, `docs/README.md`, `docs/CODEX_RUNBOOK.md`. |

## Automation hooks
- `Tools\Invoke-DailyMetricRollup.ps1 -Days 1 -IncludePerSite -IncludeSiteCache [-OutputPath Logs\IngestionMetrics\IngestionMetricsSummary-<timestamp>.csv]` to generate timestamped daily summaries (useful for automation or Task Scheduler).
- `Tools\Rollup-IngestionMetrics.ps1 -MetricsDirectory Logs\IngestionMetrics -OutputPath Logs\IngestionMetrics\IngestionMetricsSummary.csv [-IncludePerSite -IncludeSiteCache -Start <date> -End <date>]` for ad-hoc or multi-day investigations.
- `Tools\Schedule-DailyRollupTask.ps1 -TaskName StateTraceDailyRollup -StartTime 02:00 [-MetricsDirectory <path> -OutputDirectory <path>]` to register (or preview via `-DryRun`) a Windows scheduled task that runs the daily rollup harness (see `docs/runbooks/Schedule_Daily_Rollup.md`).
- `pwsh -NoLogo -Command "Invoke-Pester Modules/Tests/RollupIngestionMetrics.Tests.ps1"` after modifying telemetry schemas or rollup scripts to ensure coverage stays green.
- `pwsh Tools\Analyze-SharedCacheStoreState.ps1 -Path Logs\IngestionMetrics\<file>.json -IncludeSiteBreakdown` (optional) so cache-related telemetry captured for Plan B is also recorded here when Plan E publishes summaries.
- `pwsh Tools\Analyze-WarmRunDiffHotspots.ps1 -TelemetryPath Logs\IngestionMetrics\WarmRunTelemetry-<run>.json -Top 20` when consuming preserved warm-run data for dashboards, ensuring the diff metrics referenced in Phase 1 dictionary are populated.
- Bundle handoff: after each rollup, run `Tools\Publish-TelemetryBundle.ps1` (see `docs/CODEX_RUNBOOK.md`) to auto-discover the latest CSV + analyzer output + warm-run summaries and copy them into `Logs/TelemetryBundles/<date>/` (include a README listing commands and task IDs) so Plan G can reference a single artifact per release (see `docs/CODEX_DOC_SYNC_PLAYBOOK.md`).

## Recent timeline (migrated from consolidated log)
| Date (MT) | Summary | Metrics / Artifacts | Source |
|-----------|---------|---------------------|--------|
| 2025-11-06 12:24 | Delivered `Tools/Rollup-IngestionMetrics.ps1` to summarise ingestion metrics (totals, averages, p95) with optional per-site/site-cache slices for regression tracking. | Script coverage in `Modules/Tests/RollupIngestionMetrics.Tests.ps1`; README/telemetry dictionary updated to advertise the command. | docs/StateTrace_Consolidated_Plans.md:38 |
| 2025-11-12 | Added `Tools/Invoke-DailyMetricRollup.ps1` and refreshed README + Codex Runbook guidance so daily CSV exports are one command away; session log captured the workflow. | `Tools/Invoke-DailyMetricRollup.ps1`, `docs/README.md`, `docs/CODEX_RUNBOOK.md`, `docs/agents/sessions/2025-11-12_session-0002.md`. | docs/agents/sessions/2025-11-12_session-0002.md |
| 2025-11-12 19:35 | Shared-cache analyzer output (Plan B) identified `SnapshotImported=0` and high AccessRefresh counts; Plan E must capture these files with the rollups so telemetry bundles include cache status. | `Tools/Analyze-SharedCacheStoreState.ps1`, `Tools/Analyze-SiteCacheProviderReasons.ps1`, `Logs/IngestionMetrics/2025-11-12.json`. | docs/plans/PlanB_Performance.md, docs/CODEX_SHARED_CACHE_DIAGNOSTICS.md |
| 2025-11-13 | Plan G dependency noted: release candidates must cite `Logs/TelemetryBundles/<version>/` with rollup CSVs + analyzer outputs; Plan E owns running `Tools/New-TelemetryBundle.ps1` after each cold/warm run. | Telemetry bundle checklist referenced in Plan G ST-G-007 and TaskBoard ST-E-003/007 rows. | docs/plans/PlanG_ReleaseGovernance.md, docs/StateTrace_TaskBoard.md |

## Telemetry gates
- See `docs/telemetry/Automation_Gates.md` for per-plan tables; Plan E maintains that file.
- `ParseDuration` p95 target <= 3 s, max <= 10 s.
- `DatabaseWriteLatency` p95 <= 500 ms (Plan B) with alerts at 950 ms cold.
- `RowsWritten` sums per site stay within +/-1% of Access counts; record comparisons inside the generated CSV and session notes.
- `Logs/IngestionMetrics/IngestionMetricsSummary*.csv` (or the timestamped variant) must be refreshed within 24 hours of telemetry-impacting changes.
- `Logs/TelemetryBundles/<date>/` exists for every release candidate (includes rollup CSV, shared-cache analyzers, warm-run summary, doc-sync checklist artifact). 

## References & history
- Historical notes remain in `docs/StateTrace_Consolidated_Plans.md` under Plan E sections.
- Telemetry specs + gates: `docs/telemetry/Phase1_metrics.md`, `docs/telemetry/Automation_Gates.md`.
- Automation references: `docs/CODEX_RUNBOOK.md`, `docs/CODEX_PLAN_AUTOMATION_MATRIX.md`, `docs/agents/sessions/2025-11-12_session-0002.md`.
- Scripts/tests: `Tools/Rollup-IngestionMetrics.ps1`, `Tools/Invoke-DailyMetricRollup.ps1`, `Modules/Tests/RollupIngestionMetrics.Tests.ps1`.
- Runbook references: `docs/runbooks/Schedule_Daily_Rollup.md`.
- Warm-run telemetry exports: `Logs/IngestionMetrics/WarmRunTelemetry-*.json`.
- Shared-cache diagnostics & bundles: `docs/CODEX_SHARED_CACHE_DIAGNOSTICS.md`, `Logs/SharedCacheSnapshot/`, `Logs/ReleaseEvidence/` (once created).









