# Codex Plan Automation Matrix

This matrix condenses the per-plan expectations into a single page so Codex (or any agent) can jump from the Task Board directly into the right commands, telemetry gates, and documentation touchpoints. Open the relevant plan file for full context, but keep this sheet nearby as the "which script + which metric" cheat sheet.

## Quick reference table
| Plan | Focus | Primary entry points | Required telemetry | Docs to update |
|------|-------|----------------------|--------------------|----------------|
| **A** | Routing reliability & dispatcher health | `Tools\Invoke-StateTracePipeline.ps1 -ResetExtractedLogs`, dispatcher harness (`Invoke-StateTraceDispatcherReplay.ps1`) | `InterfaceSyncTiming`, `InterfacePortQueueMetrics`, queue latency notes | `docs/plans/PlanA_RoutingReliability.md`, task board row, session log |
| **B** | Performance & ingestion scale | Pipeline + warm regression, `Tools\Invoke-WarmRunRegression.ps1`, `Tools\Analyze-WarmRunDiffHotspots.ps1`, autoscale profile cmdlets | `ParseDuration`, `DatabaseWriteLatency`, `SiteCacheFetchDurationMs`, warm-run improvement, cache hit counts | `docs/plans/PlanB_Performance.md`, `docs/telemetry/Automation_Gates.md#plan-b`, task board |
| **C** | Change tracking & diff model | Diff prototype validation scripts, UI diff explorer smoke steps, `Get-SpanViewSnapshot` for compare baselines | `DiffUsageRate`, diff snapshot sample size, cache alignment evidence | `docs/plans/PlanC_ChangeTracking.md`, diff prototype notes, task board |
| **D** | Feature expansion & UI workflows | `Tools\Invoke-StateTracePipeline.ps1` (to hydrate), `Main\MainWindow.ps1`, `Tools\Invoke-SpanViewSmokeTest.ps1`, UI smoke checklist | UI smoke checklist outcomes, `PortBatchReady`, SPAN snapshot rows, UX regressions | `docs/plans/PlanD_FeatureExpansion.md`, `docs/UI_Smoke_Checklist.md`, task board |
| **E** | Telemetry, launch metrics, rollups | `Tools\Invoke-DailyMetricRollup.ps1`, `Tools\Rollup-IngestionMetrics.ps1`, telemetry gate docs | New/updated CSV paths, metric deltas, Automation Gates changes | `docs/plans/PlanE_Telemetry.md`, `docs/telemetry/Automation_Gates.md`, task board |
| **F** | Security, identity, online mode | `Tools\NetworkGuard.psm1::Invoke-AllowedDownload`, `Tools\Bootstrap-DevSeat.ps1`, sanitiser scripts | NetOps logs (`Logs/NetOps/*.json`), scrubber run evidence, ADR references | `docs/plans/PlanF_SecurityIdentity.md`, `docs/Security.md`, task board, session log |
| **G** | Release & governance | `Tools\Invoke-StateTracePipeline.ps1 -RunWarmRunRegression -ShowSharedCacheSummary`, `Tools\Invoke-StateTraceVerification.ps1`, shared cache warmup helpers | Warm vs cold regression deltas, shared cache summaries, release checklist updates | `docs/plans/PlanG_ReleaseGovernance.md`, `docs/Release.md`, task board |

## Plan-specific automation notes

### Plan A – Routing reliability & dispatcher health
- **Typical scripts:** cold pipeline with history reset, dispatcher replay harness, `Get-AutoScaleConcurrencyProfile` when verifying overrides for routing jobs.
- **Telemetry to capture:** `InterfaceSyncTiming` count (expect 37 events), `InterfacePortQueueMetrics`, queue latency (target <120 ms) plus any dispatcher error codes.
- **Documentation touchpoints:** update Plan A tables (active work/timeline), TaskBoard CSV row ST-A-001 (or newer), and mention captured metrics in `docs/StateTrace_TaskBoard.md`.

### Plan B – Performance & ingestion scale
- **Typical scripts:** cold pipeline, warm regression, verification harness, shared cache warmup, diff hotspot analyzer; include concurrency overrides when experimenting and reset them afterwards.
- **Telemetry to capture:** `ParseDuration`, `DatabaseWriteLatency` (p95), `InterfaceSiteCacheMetrics` fields (`SiteCacheFetchDurationMs`, `HydrationSnapshotRecordsetDurationMs`), warm-run improvement %, cache hit counts, plus `SiteCacheProviderReason` summaries.
- **Evidence bundle:** run `Tools\Publish-TelemetryBundle.ps1` (auto-discovers latest files, then calls `Tools\New-TelemetryBundle.ps1`) after each cold+warm run to copy the telemetry JSON, shared-cache analyzers, diff hotspot CSV, and doc-sync artifacts into `Logs/TelemetryBundles/<bundle>/`.
- **Documentation touchpoints:** Plan B active work + timeline, TaskBoard row(s), backlog entries, and evidence links inside `docs/StateTrace_TaskBoard.md` / session logs.

### Plan C – Change tracking & diff model
- **Typical scripts:** diff prototype validation (per `docs/StateTrace_DiffModel_Prototype.md`), UI diff explorer exercise (follow UI smoke checklist + compare tab section), `Get-InterfaceViewSnapshot` for dataset confirmation.
- **Telemetry to capture:** `DiffUsageRate` (weekly ratio), diff snapshot counts, hash alignment evidence, anomalies found during cache comparisons.
- **Documentation touchpoints:** Plan C tables + timeline, diff prototype doc (if schema changes), backlog/task board rows keyed to ST-C-00x IDs.

### Plan D – Feature expansion & guided troubleshooting
- **Typical scripts:** pipeline hydration prior to UI runs, full UI smoke checklist, SPAN headless smoke (`Tools\Invoke-SpanViewSmokeTest.ps1`), template helper tests if needed.
- **Telemetry to capture:** UI smoke results, `PortBatchReady` counts, SPAN snapshot statistics, any UX latency observations (e.g., incremental loading progress).
- **Documentation touchpoints:** Plan D page, README/UI sections, Codex runbook/checklist updates when workflows change, plus corresponding TaskBoard entry.

### Plan E – Telemetry & launch metrics
- **Typical scripts:** `Tools\Invoke-DailyMetricRollup.ps1`, manual rollup invocations with filters, telemetry gate updates.
- **Telemetry to capture:** Path to new CSV/JSON artifacts, metric deltas vs. prior snapshot, Automation Gate changes (with justification).
- **Bundles:** execute `Tools\Publish-TelemetryBundle.ps1` (or `Tools\New-TelemetryBundle.ps1` with explicit paths) to assemble rollup CSVs, analyzer output, and warm-run summaries for release governance (Plan G ST-G-007).
- **Documentation touchpoints:** Plan E tables, telemetry gate doc, README/runbook references, TaskBoard row.

### Plan F – Security, identity, online mode
- **Typical scripts:** online mode enablement scripts (`Tools\NetworkGuard.psm1::Invoke-AllowedDownload`, `Tools\Bootstrap-DevSeat.ps1`), sanitiser tools, RBAC/identity helpers described in plan F.
- **Telemetry/logs to capture:** `Logs/NetOps/<date>.json`, sanitized fixture listings, ADR references for any policy change.
- **Documentation touchpoints:** Plan F timeline, Security doc, online-mode ADR, TaskBoard/backlog updates, and explicit mention in session logs of every download/install.

### Plan G – Release & governance
- **Typical scripts:** pipeline + warm regression with shared cache summary, shared cache warmup/inspection, verification harness, release checklist updates (`docs/Release.md`).
- **Telemetry to capture:** Warm vs. cold regression comparisons, shared cache summary JSON paths, verification harness results, governance checklist confirmations.
- **Bundles:** require a pointer to `Logs/TelemetryBundles/<version>/` (produced via `Tools\Publish-TelemetryBundle.ps1`) inside every release record and doc-sync checklist.
- **Documentation touchpoints:** Plan G tables/timeline, Release doc, TaskBoard row, and any governance log noted in `docs/StateTrace_TaskBoard.md`.

## Usage checklist
1. Pick a task from `docs/taskboard/TaskBoard.csv` (or create one) and identify the matching plan row in this matrix.
2. Run the scripts listed for that plan, capturing the telemetry named here.
3. Update the plan file, TaskBoard/CSV, backlog, and session log with the evidence before moving on.

Tie this matrix together with `docs/CODEX_INSTRUCTION_STACK.md` (workflow steps) and `docs/CODEX_RUNBOOK.md` (command details) for fully autonomous execution.
