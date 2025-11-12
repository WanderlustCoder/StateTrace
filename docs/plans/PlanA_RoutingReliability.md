# Plan A – Routing Reliability

## Objective
Guarantee that parser output, dispatcher queueing, and interface hydration stay in lockstep so operators always see the latest routing information in the UI. Plan A owns InterfaceSync timing, dispatcher health, queue depth, and regression coverage for port delivery.

## Current status (2025-11)
- Interface queue instrumentation (`InterfacePortQueueMetrics`, `InterfaceSyncTiming`) is restored and logging after the 2025-10-15 fixes (`docs/StateTrace_Consolidated_Plans.md` entries around 2025-10-15 15:12–16:30 MT).
- Dispatcher latency is now traced separately from parser persistence; queue build times remain <30 ms, so remaining latency lives upstream (see 2025-10-15 16:45 MT note in the historical log).
- Site cache hydration dominates first-host cold starts; Plan B owns performance tuning, but Plan A tracks whether routing updates continue to appear in the UI immediately after parsing.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-A-001 | Verify InterfaceSync timing completeness after recent parser refactors | Ingestion | Ready | Re-run dispatcher harness + pipeline; confirm 37 InterfaceSyncTiming events across BOYO/WLLS. |
| ST-A-002 | Add alert when InterfacePortQueueMetrics queue delay >120 ms | Ingestion + Telemetry | Backlog | Requires extending `Tools/Invoke-StateTraceVerification.ps1` to assert queue delay thresholds. |

## Recent timeline (migrated from consolidated log)
| Date (MT) | Summary | Metrics / Artifacts | Source |
|-----------|---------|---------------------|--------|
| 2025-10-15 15:12 | Identified missing `InterfaceSyncTiming` events and planned dispatcher/pipeline capture once emission path understood. | Telemetry gaps noted prior to patching `Update-InterfacesInDb`. | docs/StateTrace_Consolidated_Plans.md:4-5 |
| 2025-10-15 15:46 | Confirmed strict-mode `VariableIsUndefined` error in `Update-InterfacesInDb` prevented telemetry, queued fix + regression tests. | Root cause tied to uninitialised metrics in stream threads. | docs/StateTrace_Consolidated_Plans.md:7 |
| 2025-10-15 16:30 | Pipeline replay produced 37 `InterfaceSyncTiming` events with healthy stream metrics (Clone avg 22.2 ms/p95 53.7 ms, Dispatch avg 34.2 ms/p95 64.1 ms). | Command: `Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs`. | docs/StateTrace_Consolidated_Plans.md:8 |
| 2025-10-15 16:45 | Dispatcher harness showed queue build 18.9-26.5 ms, delay ≤103 ms, highlighting upstream InterfaceCall latency (1.5–10.5 s). | Data from `InterfacePortQueueMetrics` vs `DatabaseWriteBreakdown`. | docs/StateTrace_Consolidated_Plans.md:9 |
| 2025-10-15 17:05 | Added `SiteCacheFetchDurationMs`/`SiteCacheRefreshDurationMs` instrumentation mirrored into `DatabaseWriteBreakdown`; tests updated. | `Invoke-Pester Modules/Tests/ParserPersistenceModule.Tests.ps1` cover the new metrics. | docs/StateTrace_Consolidated_Plans.md:10 |

## Automation hooks
- `Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs` from a cold history, followed by `Tools\Invoke-WarmRunRegression.ps1 -VerboseParsing` to ensure routing telemetry persists across warm runs.
- `Tools\Invoke-StateTraceVerification.ps1 -SharedCacheMinimumSiteCount 2 -SharedCacheRequiredSites BOYO,WLLS` to fail fast when cache hydration blocks routing visibility.
- Capture `Logs/IngestionMetrics/<date>.json` snippets for the metrics noted below and link them in the task board update.

## Telemetry gates
- `InterfacePortQueueMetrics.QueueBuildDurationMs` average <30 ms, p95 <120 ms.
- `InterfaceSyncTiming.StreamCloneDurationMs` p95 <75 ms; alert if events drop below the expected host count (37 for BOYO/WLLS corpus).
- Documented in `docs/telemetry/Automation_Gates.md#plan-a`.

## References & history
- Historical narrative lives in `docs/StateTrace_Consolidated_Plans.md` (search for “InterfaceSyncTiming” and “Dispatcher harness” entries on 2025-10-15).
- Any UI impact should also be mentioned in `docs/plans/PlanD_FeatureExpansion.md` when it changes operator-facing behaviour.
