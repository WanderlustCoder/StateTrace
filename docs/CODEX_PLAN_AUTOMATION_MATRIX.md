# Codex Plan Automation Matrix

This matrix condenses the per-plan expectations into a single page so Codex (or any agent) can jump from the Task Board directly into the right commands, telemetry gates, and documentation touchpoints. Open the relevant plan file for full context, but keep this sheet nearby as the "which script + which metric" cheat sheet.

## Quick reference table
| Plan | Focus | Primary entry points | Required telemetry | Docs to update |
|------|-------|----------------------|--------------------|----------------|
| **A** | Routing reliability & dispatcher health | `Tools\Invoke-StateTracePipeline.ps1 -ResetExtractedLogs`, dispatcher harness (`Invoke-StateTraceDispatcherReplay.ps1`) | `InterfaceSyncTiming`, `InterfacePortQueueMetrics` (`QueueBuildDelayMs` p95 ≤120 ms / p99 ≤200 ms guard output + `QueueDelaySummary-<timestamp>.json`) | `docs/plans/PlanA_RoutingReliability.md`, task board row, session log |
| **B** | Performance & ingestion scale | Pipeline + warm regression, `Tools\Invoke-WarmRunRegression.ps1`, `Tools\Invoke-StateTraceVerification.ps1 -GenerateDiffHotspotReport -GenerateSharedCacheDiagnostics`, autoscale profile cmdlets | `ParseDuration`, `DatabaseWriteLatency`, `SiteCacheFetchDurationMs`, warm-run improvement, cache hit counts, diff hotspot CSVs, shared-cache diagnostics | `docs/plans/PlanB_Performance.md`, `docs/telemetry/Automation_Gates.md#plan-b`, task board |
| **C** | Change tracking & diff model | Diff prototype validation scripts, UI diff explorer smoke steps, `Get-SpanViewSnapshot` for compare baselines | `DiffUsageRate`, diff snapshot sample size, cache alignment evidence | `docs/plans/PlanC_ChangeTracking.md`, diff prototype notes, task board |
| **D** | Feature expansion & UI workflows | `Tools\Invoke-StateTracePipeline.ps1` (to hydrate), `Main\MainWindow.ps1`, `Tools\Invoke-SpanViewSmokeTest.ps1`, UI smoke checklist | UI smoke checklist outcomes, `PortBatchReady`, SPAN snapshot rows, UX regressions | `docs/plans/PlanD_FeatureExpansion.md`, `docs/UI_Smoke_Checklist.md`, task board |
| **E** | Telemetry, launch metrics, rollups | `Tools\Invoke-DailyMetricRollup.ps1`, `Tools\Invoke-DailyRollupScheduled.ps1`, `Tools\Rollup-IngestionMetrics.ps1`, `Tools\Test-TelemetryBundleReadiness.ps1` | New/updated CSV paths, metric deltas, Automation Gates changes, verified bundles per `docs/runbooks/Telemetry_Bundle_Verification.md` | `docs/plans/PlanE_Telemetry.md`, `docs/telemetry/Automation_Gates.md`, `docs/runbooks/Telemetry_Bundle_Verification.md`, task board |
| **F** | Security, identity, online mode | `Tools\NetworkGuard.psm1::Invoke-AllowedDownload`, `Tools\Bootstrap-DevSeat.psm1`, sanitiser scripts, `Tools\Reset-OnlineModeFlags.ps1 -Reason "<task>"`, `Tools\Test-NetOpsEvidence.ps1 -RequireEvidence -RequireReason` | NetOps logs (`Logs/NetOps/*.json`), scrubber run evidence, ADR references, reset logs (with reason) | `docs/plans/PlanF_SecurityIdentity.md`, `docs/Security.md`, task board, session log |
| **G** | Release & governance | `Tools\Invoke-StateTracePipeline.ps1 -RunWarmRunRegression -ShowSharedCacheSummary`, `Tools\Invoke-StateTraceVerification.ps1`, `Tools\Test-TelemetryBundleReadiness.ps1` / `Tools\Invoke-AllChecks.ps1 -TelemetryBundlePath …`, shared cache warmup helpers | Warm vs cold regression deltas, shared cache summaries, release checklist updates | `docs/plans/PlanG_ReleaseGovernance.md`, `docs/Release.md`, task board |
| **H** | User experience & adoption | `Tools\Invoke-InterfacesViewChecklist.ps1`, onboarding quickstart flow, UI help entry | Onboarding completion rate, freshness indicator coverage, `UserAction` telemetry (Scan/Load/Compare/Span) | `docs/plans/PlanH_UserExperience.md`, task board, session log |
## Plan-specific automation notes

### Plan A - Routing reliability & dispatcher health
- **Typical scripts:** cold pipeline with history reset, dispatcher replay harness, `Get-AutoScaleConcurrencyProfile` when verifying overrides for routing jobs, and `Tools\Invoke-StateTraceVerification.ps1` (queue delay gate enabled by default, override via `-QueueMetricsPath` / `-SkipQueueDelayEvaluation` only with documented justification).
- **Telemetry to capture:** `InterfaceSyncTiming` count (expect 37 events), `InterfacePortQueueMetrics` queue build delay stats (record `QueueBuildDelayMs` avg/p95/p99 + guard outcome) plus the generated `Logs\IngestionMetrics\QueueDelaySummary-<timestamp>.json`, dispatcher error codes, routing bundle artifacts.
- **Documentation touchpoints:** update Plan A tables (active work/timeline), TaskBoard CSV row ST-A-005/006, and mention captured metrics + guard status in `docs/StateTrace_TaskBoard.md`.

-### Plan B - Performance & ingestion scale
- **Typical scripts:** cold pipeline, warm regression (`Tools\Invoke-StateTraceVerification.ps1 -GenerateDiffHotspotReport -DiffHotspotTop 25 ...`), shared cache warmup, diff hotspot analyzer; include concurrency overrides when experimenting and reset them afterwards.
- **Telemetry to capture:** `ParseDuration`, `DatabaseWriteLatency` (p95), `InterfaceSiteCacheMetrics` fields (`SiteCacheFetchDurationMs`, `HydrationSnapshotRecordsetDurationMs`), warm-run improvement %, cache hit counts, diff hotspot CSV path, plus `SiteCacheProviderReason` summaries.
- **Evidence bundle:** run `Tools\Publish-TelemetryBundle.ps1` (auto-discovers latest files, then calls `Tools\New-TelemetryBundle.ps1`) after each cold+warm run to copy the telemetry JSON, shared-cache analyzers, diff hotspot CSV, and doc-sync artifacts into `Logs/TelemetryBundles/<bundle>/`.
- **Documentation touchpoints:** Plan B active work + timeline, TaskBoard row(s), backlog entries, and evidence links inside `docs/StateTrace_TaskBoard.md` / session logs.

### Plan C – Change tracking & diff model
- **Typical scripts:** diff prototype validation (per `docs/StateTrace_DiffModel_Prototype.md`), UI diff explorer exercise (follow UI smoke checklist + compare tab section), `Get-InterfaceViewSnapshot` for dataset confirmation.
- **Telemetry to capture:** `DiffUsageRate` (weekly ratio), diff snapshot counts, hash alignment evidence, anomalies found during cache comparisons.
- **Documentation touchpoints:** Plan C tables + timeline, diff prototype doc (if schema changes), backlog/task board rows keyed to ST-C-00x IDs.

### Plan D – Feature expansion & guided troubleshooting
- **Typical scripts:** pipeline hydration prior to UI runs, full UI smoke checklist, SPAN headless smoke (`Tools\Invoke-SpanViewSmokeTest.ps1`), template helper tests, incremental-loading analysis (`Tools\Analyze-PortBatchReadyTelemetry.ps1`), and InterfaceSyncTiming sweeps (`Tools\Analyze-InterfaceSyncTiming.ps1`) to keep performance baselines current.
- **Telemetry to capture:** UI smoke results, `PortBatchReady` counts/ports-per-minute, SPAN snapshot statistics, InterfaceSyncTiming host/site hot spots, and any UX latency observations (e.g., incremental loading progress).
- **Documentation touchpoints:** Plan D page, README/UI sections, Codex runbook/checklist updates when workflows change, plus corresponding TaskBoard entry.

### Plan E - Telemetry & launch metrics
- **Typical scripts:** `Tools\Invoke-DailyMetricRollup.ps1`, `Tools\Invoke-DailyRollupScheduled.ps1`, manual rollup invocations with filters, telemetry gate updates, and `Tools\Test-TelemetryBundleReadiness.ps1` (after following `docs/runbooks/Telemetry_Bundle_Verification.md`) to prove bundle completeness.
- **Telemetry to capture:** Path to new CSV/JSON artifacts, metric deltas vs. prior snapshot, Automation Gate changes (with justification), readiness output (README hashes/status table), and the verification steps captured in the runbook.
- **Bundles:** execute `Tools\Publish-TelemetryBundle.ps1` (or `Tools\New-TelemetryBundle.ps1` with explicit paths) to assemble rollup CSVs, analyzer output, and warm-run summaries for release governance (Plan G ST-G-007), then run the readiness script/runbook steps and stash the output alongside the plan/task board updates.
- **Evidence viewer:** use `Tools\Show-TelemetryBundleSummary.ps1 -BundlePath Logs\TelemetryBundles\<bundle>` to display the stored README hashes + requirement table from `VerificationSummary.json` when filling in plans/task board entries.
- **Documentation touchpoints:** Plan E tables, telemetry gate doc, README/runbook references, TaskBoard row (include bundle name + readiness result + README hash).

### Plan F – Security, identity, online mode
- **Typical scripts:** online mode enablement scripts (`Tools\NetworkGuard.psm1::Invoke-AllowedDownload`, `Tools\Bootstrap-DevSeat.psm1`), sanitiser tools, RBAC/identity helpers described in Plan F, plus `Tools\Reset-OnlineModeFlags.ps1 -Reason "<task>"` to clear `STATETRACE_AGENT_ALLOW_*`, record the reason, and log the reset.
- **Telemetry/logs to capture:** `Logs/NetOps/<date>.json`, sanitized fixture listings, ADR references for any policy change, and `Logs/NetOps/Resets/OnlineModeReset-<timestamp>.json`.
- **Documentation touchpoints:** Plan F timeline, Security doc, online-mode ADR, TaskBoard/backlog updates, and explicit mention in session logs of every download/install.
- **Automation hooks:** Run `Tools\Test-NetOpsEvidence.ps1 -RequireEvidence -RequireReason [-SessionLogPath <log>]` (or `Tools\Invoke-AllChecks.ps1 -RequireNetOpsEvidence`) to verify NetOps/reset logs, embedded reasons, and session references exist before closing online-mode sessions.

### Plan G - Release & governance
- **Typical scripts:** pipeline + warm regression with shared cache summary, shared cache warmup/inspection, verification harness (`Tools\Invoke-StateTraceVerification.ps1 -TelemetryBundlePath <bundle> -VerifyTelemetryBundleReadiness`), telemetry bundle readiness checks (`Tools\Test-TelemetryBundleReadiness.ps1` or `Tools\Invoke-AllChecks.ps1 -TelemetryBundlePath … -RequireTelemetryBundleReady`), release checklist updates (`docs/Release.md`).
- **Telemetry to capture:** Warm vs. cold regression comparisons, shared cache summary JSON paths, verification harness results, governance checklist confirmations, readiness script output.
- **Bundles:** require a pointer to `Logs/TelemetryBundles/<version>/` (produced via `Tools\Publish-TelemetryBundle.ps1`) plus a successful readiness run captured inside every release record and doc-sync checklist.
- **Documentation touchpoints:** Plan G tables/timeline, Release doc, TaskBoard row, and any governance log noted in `docs/StateTrace_TaskBoard.md` (record bundle hash + readiness evidence).

### Plan H - User experience & adoption
- **Typical scripts:** onboarding + UI smoke via `Tools\Invoke-InterfacesViewChecklist.ps1 -SiteFilter <sites>` (extend with onboarding steps), incremental-loading checklist to hydrate data before UI validation, and the UI help entry/quickstart once added.
- **Telemetry to capture:** onboarding completion timestamps, time-to-first-view, freshness indicator values per site (last ingest + source), and `UserAction` events for Scan Logs, Load from DB, Compare view, and Span snapshots. Add adoption thresholds to `docs/telemetry/Automation_Gates.md` when ST-H-003 lands.
- **Documentation touchpoints:** Plan H page, Operators Runbook quickstart section, UI smoke checklist, TaskBoard/CSV row ST-H-001, and session logs noting onboarding/freshness telemetry paths.

## Usage checklist
1. Pick a task from `docs/taskboard/TaskBoard.csv` (or create one) and identify the matching plan row in this matrix.
2. Run the scripts listed for that plan, capturing the telemetry named here.
3. Update the plan file, TaskBoard/CSV, backlog, and session log with the evidence before moving on.

Tie this matrix together with `docs/CODEX_INSTRUCTION_STACK.md` (workflow steps) and `docs/CODEX_RUNBOOK.md` (command details) for fully autonomous execution.








