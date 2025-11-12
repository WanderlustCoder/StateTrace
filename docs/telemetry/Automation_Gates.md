# Automation Telemetry Gates

This reference consolidates the success criteria that each plan/task must meet before code can land. Capture the listed metrics in `Logs/IngestionMetrics/<date>.json` (or the referenced CSV/JSON) and link them from your task board update and session log.

## Plan A – Routing Reliability
- `InterfacePortQueueMetrics.QueueBuildDurationMs` avg <30 ms, p95 <120 ms.
- `InterfaceSyncTiming` event count matches processed host count (37 for BOYO/WLLS corpus); zero `VariableIsUndefined` errors.

## Plan B – Performance & Ingestion Scale
- `DatabaseWriteLatency` p95 <950 ms (cold) and <500 ms (warm); alert if warm p95 >600 ms.
- `InterfaceSiteCacheMetrics.SiteCacheFetchDurationMs` p95 <5 s. Document host-level values when >10 s.
- `WarmRunComparison.ImprovementPercent` ≥60% with `WarmProviderCounts.Cache` covering all hosts.

## Plan C – Change Tracking
- `DiffUsageRate` rolling weekly ratio ≥70% once the feature is live.
- `DriftDetectionTime` p95 decreases release-over-release (target -40% vs. baseline).

## Plan D – Feature Expansion
- `PortBatchReady` emits per-device records with `PortsCommitted` totals aligning with Access rows.
- Any new UI telemetry must include a schema snippet in `docs/telemetry/Phase1_metrics.md` before shipping.

## Plan E – Telemetry & Launch Metrics
- `ParseDuration` p95 ≤3 s, max ≤10 s.
- `RowsWritten` sums per site align with Access counts (tolerate ±1%).
- Rollup CSV (`Logs/IngestionMetrics/IngestionMetricsSummary.csv`) updated within 24 hours of material changes.

## Plan F – Security & Identity
- Zero `.accdb` or raw logs committed; verify via PR review checklist.
- Online dev sessions log entries to `Logs/NetOps/<date>.json` plus `docs/agents/sessions/`.

## Plan G – Release & Governance
- `Tools/Invoke-StateTraceVerification.ps1` passes with warm improvement ≥60% and shared cache coverage meeting `-SharedCacheMinimum*` thresholds.
- `Logs/SharedCacheSnapshot/SharedCacheSnapshot-latest-summary.json` shows minimum site count 2, host count 37, row count 1,200+ prior to release sign-off.

Update this file whenever a plan adds or changes a gate so automation agents can enforce the criteria programmatically.
