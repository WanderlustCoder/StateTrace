# Plan I - Harness & Gating Stability

## Objective
Ensure cold/warm harnesses (pipeline, verification, warm-run telemetry) consistently produce bundle-ready artifacts—queue summaries, port batch/site diversity, shared-cache diagnostics, diff hotspots—without guard skips or streak failures, using the approved PowerShell 5.1 toolchain.

## Current status (2025-12)
- Queue delay summary now emits when dispatcher sweep precedes runs, but diversity guard still blocks warm runs (WLLS streak=14 > 8) with the current synthetic dataset.
- History updaters (`Update-PortBatchHistory.ps1`, `Update-InterfaceSyncHistory.ps1`) succeed when called via 5.1; pipeline now shells them explicitly to avoid `-Depth` errors.
- Warm-run telemetry runs clean when port diversity guard is skipped; guarded path remains blocked by streaks. Shared cache snapshots load, but provider reasons for BOYO still skew toward `SharedCacheUnavailable/Unknown`.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-I-001 | Pass diversity guard with balanced input | Ingestion | In Progress | Reduce WLLS streaks by using `Data/RoutingHosts_Balanced.txt` (and pruning duplicates), then rerun `Invoke-WarmRunTelemetry.ps1 -GenerateDiffHotspotReport` with guard enabled. Capture streak report and ensure QueueDelaySummary + PortBatchSiteDiversity succeed. |
| ST-I-002 | Produce bundle-ready guarded run | Ingestion/PMO | Ready | After ST-I-001, run guarded cold+warm with shared-cache diagnostics and diff hotspots, then `Tools\Publish-TelemetryBundle.ps1 -PlanReferences PlanB,PlanI -TaskBoardIds ST-B-001,ST-I-002` so Plans B/E/G have fresh evidence. |
| ST-I-003 | Seed warm-run backups & cache snapshots | Ingestion | Ready | Export shared cache snapshot post-cold, preserve warm-run history (per guard module), and store latest snapshot paths in plan/task updates to cut `No warm-run backup found` warnings. |
| ST-I-004 | Add harness smoke to task board | Automation | Backlog | Add a scheduled 5.1 smoke (synthetic dataset) that checks: queue summary present, port diversity guard passes, history updaters run, and shared-cache diagnostics generated. Surface results on the task board and Plan I timeline. |

## Recently delivered
- History updaters now invoked via PowerShell 5.1 in the pipeline to avoid `-Depth` parameter errors.
- Balanced dispatcher sweep (`RoutingQueueSweep-20251203-153101.json`) with interleaved BOYO/WLLS hosts captured queue delays for harness reuse.

## Automation hooks
- Dispatcher sweep: `Tools\Invoke-RoutingQueueSweep.ps1 -HostListPath Data\RoutingHosts_Balanced.txt -UseBalancedHostOrder` (5.1).
- Guarded warm run: `Tools\Invoke-WarmRunTelemetry.ps1 -GenerateDiffHotspotReport -DisablePreservedRunspacePool` (add `-SkipPortDiversityGuard:$false` once streaks fixed; use 5.1).
- Pipeline cold pass with diagnostics: `Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs -DisableSkipSiteCacheUpdate -RunSharedCacheDiagnostics`.
- Bundle: `Tools\Publish-TelemetryBundle.ps1 -BundleName Release-<date> -PlanReferences PlanB,PlanI -TaskBoardIds ST-B-001,ST-I-002`.

## Telemetry gates
- Queue delay summary present with p95 ≤ 120 ms, p99 ≤ 200 ms (fail guard otherwise).
- Port batch diversity: max streak ≤ 8; failure blocks warm pass unless explicitly waived in plan/task updates.
- Warm run: `WarmCacheHitRatioPercentRaw > 0`, provider reasons not `Unknown/SharedCacheUnavailable` for BOYO/WLLS; diff hotspot CSV emitted.
- Shared cache: `SnapshotImported > 0`, `GetHit` improves vs `GetMiss` for BOYO/WLLS.

## References
- `docs/plans/PlanB_Performance.md` (warm-run and shared-cache workstreams).
- `docs/CODEX_RUNBOOK.md` (queue/diff/shared-cache automation matrix).
- `docs/CODEX_SHARED_CACHE_DIAGNOSTICS.md` and `docs/notes/2025-11-07_warm-run-optimization-plan.md` for cache investigations.
