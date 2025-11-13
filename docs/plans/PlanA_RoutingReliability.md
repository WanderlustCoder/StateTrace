# Plan A – Routing Reliability

## Objective
Guarantee that parser output, dispatcher queueing, and interface hydration stay in lockstep so operators always see the latest routing information in the UI. Plan A owns InterfaceSync timing, dispatcher health, queue depth, and regression coverage for port delivery.

## Current status (2025-11)
- Interface queue instrumentation (`InterfacePortQueueMetrics`, `InterfaceSyncTiming`) was restored in the 2025-10-15 fixes (see `docs/StateTrace_Consolidated_Plans.md` around 15:12-16:30 MT), and the Codex automation matrix now maps Plan A tasks to the dispatcher harness + pipeline reset commands (`docs/CODEX_PLAN_AUTOMATION_MATRIX.md`).
- Dispatcher latency is traced separately from parser persistence; queue build times remain under 30 ms, so remaining latency lives upstream (historical log 2025-10-15 16:45 MT). We still need a recurring validation to prove the harness results land in `Logs/IngestionMetrics/*.json`.
- Plan B progression on shared cache hydration affects first-host cold starts; Plan A owns verifying that routing telemetry (`InterfaceSyncTiming`, dispatcher metrics) reaches the UI immediately after parsing, even when cold hydrations are slow. Coordinate with Plan B when cache regressions (WLLS/BOYO) could mask routing telemetry.
- No automated alert currently watches `InterfacePortQueueMetrics.QueueDelayMs`; Plan A must wire the planned alert into `Tools/Invoke-StateTraceVerification.ps1` or the dispatcher harness so releases block when queue delay exceeds thresholds.
- Plan D’s incremental loading UX relies on Plan A telemetry; keep the plan in sync with `docs/StateTrace_Operators_Runbook.md` and ensure UI smoke steps reference the routing metrics captured here.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-A-001 | Verify InterfaceSync timing completeness after recent parser refactors | Ingestion | Ready | Run `Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs` followed by `Tools\Invoke-InterfaceDispatchHarness.ps1 -Sites BOYO,WLLS`; confirm 37 `InterfaceSyncTiming` events and attach `Logs/IngestionMetrics/<date>.json` snippet to the plan/task board. |
| ST-A-002 | Add alert when InterfacePortQueueMetrics queue delay >120 ms | Ingestion + Telemetry | Backlog | Extend `Tools\Invoke-StateTraceVerification.ps1` (or dispatcher harness) to assert `QueueDelayMs` thresholds, fail the run, and update `docs/telemetry/Automation_Gates.md`. |
| ST-A-003 | Automate dispatcher harness evidence capture | Automation | Backlog | Document how to call `Tools\Invoke-InterfaceDispatchHarness.ps1` (parameters, expected output) in `docs/CODEX_RUNBOOK.md` and ensure every Plan A task records harness metrics + path to the generated `Logs/DispatchHarness/*.json`. |
| ST-A-004 | UI routing smoke alignment | UI / Ingestion | Backlog | Update `docs/UI_Smoke_Checklist.md` and `docs/StateTrace_Operators_Runbook.md` so routing verification steps (Interfaces tab refresh + metric sampling) reference this plan and capture `InterfaceSyncTiming` samples whenever incremental loading or parser changes land. |
| ST-A-005 | Dispatcher alert integration | Telemetry | Backlog | Add `InterfacePortQueueMetrics.QueueDelayMs` assertions to `Tools\Invoke-StateTraceVerification.ps1` (and optionally the dispatcher harness) so releases fail when queue delay exceeds 120 ms.
| ST-A-006 | Evidence bundle linkage | Ingestion + PMO | Backlog | After each dispatcher/pipeline run, deposit `Logs/IngestionMetrics/<date>.json` and dispatcher harness logs into `Logs/TelemetryBundles/<date>/Routing/` so Plan E/G can audit routing telemetry before release sign-off.

## Recent timeline (migrated from consolidated log)
| Date (MT) | Summary | Metrics / Artifacts | Source |
|-----------|---------|---------------------|--------|
| 2025-10-15 15:12 | Identified missing `InterfaceSyncTiming` events and planned dispatcher/pipeline capture once emission path understood. | Telemetry gaps noted prior to patching `Update-InterfacesInDb`. | docs/StateTrace_Consolidated_Plans.md:4-5 |
| 2025-10-15 15:46 | Confirmed strict-mode `VariableIsUndefined` error in `Update-InterfacesInDb` prevented telemetry, queued fix + regression tests. | Root cause tied to uninitialised metrics in stream threads. | docs/StateTrace_Consolidated_Plans.md:7 |
| 2025-10-15 16:30 | Pipeline replay produced 37 `InterfaceSyncTiming` events with healthy stream metrics (Clone avg 22.2 ms/p95 53.7 ms, Dispatch avg 34.2 ms/p95 64.1 ms). | Command: `Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs`. | docs/StateTrace_Consolidated_Plans.md:8 |
| 2025-10-15 16:45 | Dispatcher harness showed queue build 18.9-26.5 ms, delay ≤103 ms, highlighting upstream InterfaceCall latency (1.5–10.5 s). | Data from `InterfacePortQueueMetrics` vs `DatabaseWriteBreakdown`. | docs/StateTrace_Consolidated_Plans.md:9 |
| 2025-10-15 17:05 | Added `SiteCacheFetchDurationMs`/`SiteCacheRefreshDurationMs` instrumentation mirrored into `DatabaseWriteBreakdown`; tests updated. | `Invoke-Pester Modules/Tests/ParserPersistenceModule.Tests.ps1` cover the new metrics. | docs/StateTrace_Consolidated_Plans.md:10 |
| 2025-11-13 | Routed telemetry bundles landed in Plans E/G by way of `Tools\New-TelemetryBundle.ps1`; Plan A now owns dispatcher alert integration + routing bundle drop-offs (ST-A-005/006). | Bundle README cites routing evidence + Plan A task IDs. | docs/plans/PlanE_Telemetry.md, docs/plans/PlanG_ReleaseGovernance.md |

## Automation hooks
- `Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs` (cold history) followed by `Tools\Invoke-WarmRunRegression.ps1 -VerboseParsing` to confirm routing telemetry persists across warm runs.
- `Tools\Invoke-InterfaceDispatchHarness.ps1 -Sites BOYO,WLLS -OutputDirectory Logs\DispatchHarness` to replay dispatcher load and capture queue/append timings alongside the pipeline results.
- `Tools\Invoke-StateTraceVerification.ps1 -SharedCacheMinimumSiteCount 2 -SharedCacheRequiredSites BOYO,WLLS -EmitWarmRunTelemetry` whenever Plan A changes ship, ensuring routing gates are checked with the rest of the verification suite.
- Capture `Logs/IngestionMetrics/<date>.json` (InterfaceSyncTiming + InterfacePortQueueMetrics) and the dispatcher harness output; reference both paths in TaskBoard updates per `docs/CODEX_PLAN_AUTOMATION_MATRIX.md`.
- When Plan B publishes telemetry bundles (`Logs/TelemetryBundles/<date>/`), drop the routing JSON + dispatcher logs into the same folder so Plan G can confirm release readiness.

## Telemetry gates
- `InterfacePortQueueMetrics.QueueBuildDurationMs` average < 30 ms, p95 < 120 ms; if the dispatcher harness reports a higher p95, fail the run and log the evidence.
- `InterfaceSyncTiming.StreamCloneDurationMs` p95 < 75 ms and event count equals processed hosts (37 for BOYO/WLLS corpus); deviations require a Plan A + TaskBoard update.
- `InterfaceSyncTiming.StreamDispatchDurationMs` and dispatcher harness `DispatcherDurationMs` remain within 2x historical baselines (see 2025-10-15 entries in `docs/StateTrace_Consolidated_Plans.md`); document any regressions.
- Gates are tracked in `docs/telemetry/Automation_Gates.md#plan-a`; update that file if thresholds change.
- Routing telemetry + dispatcher evidence copied into the release telemetry bundle (see Plan E ST-E-007 / Plan G ST-G-007) before any candidate build proceeds.

## References & history
- Historical narrative: `docs/StateTrace_Consolidated_Plans.md` (2025-10-15 InterfaceSyncTiming and dispatcher harness entries).
- Automation references: `docs/CODEX_PLAN_AUTOMATION_MATRIX.md`, `docs/CODEX_RUNBOOK.md`, `docs/CODEX_SHARED_CACHE_DIAGNOSTICS.md`.
- UI + operator guidance: `docs/StateTrace_Operators_Runbook.md`, `docs/UI_Smoke_Checklist.md`, `docs/plans/PlanD_FeatureExpansion.md`.
