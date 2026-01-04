# Automation Telemetry Gates

This reference consolidates the success criteria that each plan/task must meet before code can land. Capture the listed metrics in `Logs/IngestionMetrics/<date>.json` (or the referenced CSV/JSON) and link them from your task board update and session log.

## Plan A - Routing Reliability
- `InterfacePortQueueMetrics.QueueBuildDurationMs` avg <30 ms; `QueueBuildDelayMs` (queue delay) p95 ≤120 ms and p99 ≤200 ms. Queue delay summary must include at least 10 samples (default `QueueDelayMinimumSampleCount`); otherwise the gate reports `InsufficientData` and fails unless explicitly skipped. `Tools\Invoke-StateTraceVerification.ps1` and `Tools\Invoke-InterfaceDispatchHarness.ps1` enforce these thresholds and produce `Logs\IngestionMetrics\QueueDelaySummary-<timestamp>.json` as evidence. `Tools\Invoke-StateTracePipeline.ps1 -RunQueueDelayHarness` now runs the dispatcher sweep to emit queue metrics during standard pipeline passes.
- `InterfaceSyncTiming` event count matches processed host count (37 for BOYO/WLLS corpus); zero `VariableIsUndefined` errors.
- Parser scheduler fairness guard passes: `Tools\Test-ParserSchedulerFairness.ps1 -ReportPath Logs/Reports/ParserSchedulerLaunch-<date>.json -MaxAllowedStreak 8 -ThrowOnViolation` must report `MaxObservedStreak <= 8` (current baseline: 86 launch events, max streak 1). `Tools\Invoke-StateTracePipeline.ps1` runs this guard by default; document any run where it is disabled.

## Plan B – Performance & Ingestion Scale
- `DatabaseWriteLatency` p95 <950 ms (cold) and <500 ms (warm); alert if warm p95 >600 ms.
- `InterfaceSiteCacheMetrics.SiteCacheFetchDurationMs` p95 <5 s. Document host-level values when >10 s.
- `WarmRunComparison.ImprovementPercent` ≥60% with `WarmProviderCounts.Cache` covering all hosts.

## Plan C – Change Tracking
- `DiffUsageRate` rolling weekly ratio ≥70% once the feature is live.
- `DriftDetectionTime` p95 decreases release-over-release (target -40% vs. baseline).

## Plan D – Feature Expansion
- `PortBatchReady` emits per-device records with `PortsCommitted` totals aligning with Access rows.
- Incremental telemetry completeness + fairness: `Tools\Test-IncrementalTelemetryCompleteness.ps1 -RequirePortBatchReady -RequireInterfaceSync -RequireSchedulerLaunch -ThrowOnMissing [-AllowNoParse]` and the scheduler fairness guard must both pass before declaring ST-D-003/ST-D-010 ready. Use `-AllowNoParse` only when the telemetry file is duplicate-only (`SkippedDuplicate` entries and no parse activity); otherwise treat missing signals as failures. Link the resulting analyzer JSON (`PortBatchReady-*.json`, `InterfaceSyncTiming-*.json`, `ParserSchedulerLaunch-*.json`) and history CSV rows in the task/bundle notes.
- Scheduler vs. UI replay comparison: `Logs/Reports/SchedulerVsPortDiversity-*.json` (generated via `Tools\Compare-SchedulerAndPortDiversity.ps1`) accompanies `Logs/Reports/PortBatchSiteDiversity-*.json` for every incremental run so ST-D-010 can prove whether UI streaks still exceed the parser guard.
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

## Plan H - User Experience & Adoption

### Required UserAction Events
Core flows that must appear in every telemetry bundle (gate failure if missing):
- `ScanLogs` - User initiated log scan
- `LoadFromDb` - User loaded from database
- `HelpQuickstart` - User accessed help/quickstart
- `InterfacesView` - User viewed interfaces tab
- `CompareView` - User performed comparison
- `SpanSnapshot` - User captured SPAN snapshot

### Optional UserAction Events (tracked but not required)
- `RefreshFromDb` - User reloaded from database without parsing (ST-H-002)

### Adoption Thresholds
| Metric | Threshold | Gate Type |
|--------|-----------|-----------|
| Required action coverage | 100% (all 6 required actions present) | Release blocking |
| UserAction events per bundle | ≥ 10 total events | Warning (not blocking) |
| Site coverage | ≥ 2 distinct sites with UserAction events | Release blocking |
| Onboarding completion rate | ≥ 80% for guided runs | Soft gate (tracked) |
| Compare/Span invocation rate | Trending upward release-over-release | Soft gate (tracked) |

### Evidence Requirements
- `UserAction` telemetry present for core flows; cite the latest telemetry bundle in plan/task updates (current evidence: `Logs/Reports/UserActionSummary-20251126-run3.json` inside `Logs/TelemetryBundles/UI-20251126-useraction7/`, all required actions present).
- Adoption signals captured in rollups; treat missing required actions as a gate failure for release readiness. Rollup CSV includes `Metric=UserActionCoverage` (Count=covered actions, Total=required actions, Notes=Missing=...) per scope/site.
- Freshness evidence: telemetry bundles must include a `FreshnessTelemetrySummary*.json` showing cache provider/source per site; freshness tooltip must align with the summary when capturing UI screenshots.
- Freshness indicator coverage: 100% of supported sites show last ingest timestamp + source with color-coded status (Green <24h, Yellow 24-48h, Orange 2-7d, Red >7d).
Update this file whenever a plan adds or changes a gate so automation agents can enforce the criteria programmatically.
