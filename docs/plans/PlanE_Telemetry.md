# Plan E – Telemetry & Launch Metrics

## Objective
Capture, roll up, and verify the telemetry needed for operations (Phase 1 dictionary) plus engineering automation. Plan E owns the ingestion metrics schema, rollup scripts, verification harness thresholds, and telemetry documentation.

## Current status (2025-11)
- Phase 1 telemetry dictionary is published (`docs/telemetry/Phase1_metrics.md`), but encoding cleanup was required (addressed in this change set).
- Daily rollups are available via `Tools/Rollup-IngestionMetrics.ps1`, though adoption is ad-hoc.
- Warm-run verification now enforces cache improvement thresholds (shared with Plan B).

## Active work
_No active tasks at the moment._ Add new entries here when fresh telemetry or automation initiatives spin up.

## Recently delivered
| ID | Date | Summary | Evidence |
|----|------|---------|----------|
| ST-E-001 | 2025-11-06 | Published `docs/telemetry/Automation_Gates.md` and linked every plan/task to the shared telemetry thresholds. | `docs/telemetry/Automation_Gates.md`, plan updates, task board entries. |
| ST-E-002 | 2025-11-12 | Added `Tools/Invoke-DailyMetricRollup.ps1`, updated README + Codex Runbook so daily ingestion summaries can be generated (and scheduled) with one command. | `Tools/Invoke-DailyMetricRollup.ps1`, `docs/README.md`, `docs/CODEX_RUNBOOK.md`. |

## Automation hooks
- `Tools/Rollup-IngestionMetrics.ps1 -MetricsDirectory Logs/IngestionMetrics -OutputPath Logs/IngestionMetrics/IngestionMetricsSummary.csv [-IncludePerSite -IncludeSiteCache]`.
- `Tools/Analyze-WarmRunDiffHotspots.ps1 -TelemetryPath Logs\IngestionMetrics\<warm run>.json -Top 20` for hotspot reporting.

## Recent timeline (migrated from consolidated log)
| Date (MT) | Summary | Metrics / Artifacts | Source |
|-----------|---------|---------------------|--------|
| 2025-11-06 12:24 | Delivered `Tools/Rollup-IngestionMetrics.ps1` to summarise ingestion metrics (totals, averages, p95) with optional per-site/site-cache slices for regression tracking. | Script coverage in `Modules/Tests/RollupIngestionMetrics.Tests.ps1`; README/telemetry dictionary updated to advertise the command. | docs/StateTrace_Consolidated_Plans.md:38 |

## Telemetry gates
- See `docs/telemetry/Automation_Gates.md` for per-plan tables; Plan E maintains that file.
- `ParseDuration` p95 target ≤3 s, max ≤10 s.
- `DatabaseWriteLatency` p95 ≤500 ms (Plan B) with alerts at 950 ms cold.

## References & history
- Historical notes remain in `docs/StateTrace_Consolidated_Plans.md` under Plan E sections.
- Warm-run telemetry exports: `Logs/IngestionMetrics/WarmRunTelemetry-*.json`.
