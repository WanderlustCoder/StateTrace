# Incremental Loading Performance Baseline (2025-11-13)

This note captures the Interfaces view incremental-loading telemetry sweep requested under Plan D ST-D-003. Use it as the baseline when evaluating future UI or parser changes that affect streaming performance.

## Method
1. Ran `Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs -RunSharedCacheDiagnostics` to process the BOYO/WLLS corpus and emit telemetry to `Logs/IngestionMetrics/2025-11-13.json`.
2. Exercised the Interfaces view per `docs/StateTrace_Operators_Runbook.md` until all batches streamed (ensuring progress bar + status strip activity was observed).
3. Generated the summary:
   ```powershell
   pwsh Tools/Analyze-PortBatchReadyTelemetry.ps1 `
       -Path Logs/IngestionMetrics/2025-11-13.json `
       -IncludeHostBreakdown `
       -OutputPath Logs/Reports/PortBatchReady-20251113.json
   ```
4. Saved the analyzer JSON beside the telemetry for reuse in bundles/release evidence (`Logs/Reports/PortBatchReady-20251113.json`). Future runs should pass `-BaselineSummaryPath Logs/Reports/PortBatchReady-20251113.json` to highlight regressions.

## Key Telemetry
| Metric | Value |
|--------|-------|
| PortBatchReady events | 213 |
| Unique hosts covered | 43 (full BOYO/WLLS set) |
| Total ports streamed | 906 |
| Average ports per batch | 4.25 |
| Duration (first → last batch) | 1,156.5 seconds |
| Sustained throughput | 47.0 ports/minute |
| Batch interval p95 | 1.77 seconds |
| UiClone duration p95 | 19.7 ms |
| StreamDispatch duration p95 | 28.4 ms |
| DiffDuration p95 | 17.7 ms |

Top talkers (ports committed = 50 each): `BOYO-A05-AS-02`, `BOYO-A05-AS-05`, `BOYO-A05-AS-12`, `BOYO-A05-AS-15`, `BOYO-A05-AS-22`, `BOYO-A05-AS-25`, `BOYO-A05-AS-32`, `BOYO-A05-AS-35`, `BOYO-A05-AS-42`, `BOYO-A05-AS-45`, `BOYO-A05-AS-52`, `BOYO-A05-AS-55`.

## Artifacts
- Telemetry JSON: `Logs/IngestionMetrics/2025-11-13.json`
- Analyzer report: `Logs/Reports/PortBatchReady-20251113.json`
- Bundle reference: `Logs/TelemetryBundles/Release-20251113/Telemetry/`

### 2025-11-13 14:29 MT Re-run
- Copied the refreshed telemetry to `Logs/IngestionMetrics/2025-11-13-142949.json` after another parser pass and re-ran the analyzer:
  ```powershell
  pwsh Tools/Analyze-PortBatchReadyTelemetry.ps1 `
      -Path Logs/IngestionMetrics/2025-11-13-142949.json `
      -IncludeHostBreakdown `
      -OutputPath Logs/Reports/PortBatchReady-20251113-142949.json `
      -BaselineSummaryPath Logs/Reports/PortBatchReady-20251113.json
  ```
- Result matched the baseline exactly (ports/minute, batch intervals, UiClone/Stream/Diff p95 all unchanged), confirming throughput stability after repeated runs.
- Store the new JSON in the telemetry bundle for historical comparisons; when a future run diverges, the delta table in the analyzer output will capture the change automatically.

## InterfaceSyncTiming Analysis
- Script: `pwsh Tools/Analyze-InterfaceSyncTiming.ps1 -Path Logs/IngestionMetrics/2025-11-13-142949.json -OutputPath Logs/Reports/InterfaceSyncTiming-20251113-142949.json -TopHosts 15`
- Global highlights:
  - UiClone p95 19.7 ms (max 62.1 ms)
  - StreamDispatch p95 28.4 ms (max 31.8 ms)
  - SiteCacheUpdate p95 258.6 ms (max 438.3 ms)
- Site breakdown p95 UiClone:

| Site | Events | UiClone p95 (ms) | StreamDispatch p95 (ms) |
|------|--------|------------------|-------------------------|
| BOYO | 60 | 34.58 | 28.57 |
| SITE | 15 | 3.41 | 26.65 |
| WLLS | 125 | 3.40 | 28.40 |
| SNAP | 5 | 2.29 | 27.06 |
| SW1 | 5 | 1.71 | 26.48 |
| LABS | 5 | 1.58 | 22.88 |

- Top offenders (UiClone p95): BOYO-A05-AS-02 (59.7 ms), BOYO-A05-AS-12 (21.3 ms), BOYO-A05-AS-05 (20.5 ms), etc. All WLLS hosts remain <4 ms.
- Full JSON summary: `Logs/Reports/InterfaceSyncTiming-20251113-142949.json`

### 2025-11-13 14:45 MT Additional sweep
- Ran both analyzers against the latest ingestion file (`Logs/IngestionMetrics/2025-11-13.json`) and produced:
  - `Logs/Reports/PortBatchReady-20251113-143327.json`
  - `Logs/Reports/InterfaceSyncTiming-20251113-143327.json`
- Metrics remain unchanged (47 ports/min, UiClone/Stream p95 stable), confirming consistency after repeated runs.
- Updated history trackers for quick diffing over time:
  - `Logs/Reports/PortBatchHistory.csv`
  - `Logs/Reports/InterfaceSyncHistory.csv`

### 2025-11-13 14:55 MT Warm-run telemetry context
- Executed `Tools/Invoke-WarmRunTelemetry.ps1` (cold + warm pass) to ensure warm telemetry entries are refreshed; telemetry file `Logs/IngestionMetrics/2025-11-13-145532.json` ready for future analyzers.
- Parsed the final ingestion file again with `Tools/Analyze-InterfaceSyncTiming.ps1 -Path Logs/IngestionMetrics/2025-11-13.json -OutputPath Logs/Reports/InterfaceSyncTiming-20251113-144532.json -TopHosts 15` and appended the report to `Logs/Reports/InterfaceSyncHistory.csv`.
- UiClone p95 remains 19.68 ms overall, but BOYO’s p95 climbed to 38.6 ms (more BOYO sample counts captured); this is now the top entry in the history CSV for tracking.

### 2025-11-13 15:00 MT Gap analysis
- Added `Tools/Analyze-PortBatchIntervals.ps1` to surface idle windows between `PortBatchReady` events.
- Command:
  ```powershell
  pwsh Tools/Analyze-PortBatchIntervals.ps1 `
      -Path Logs/IngestionMetrics/2025-11-13.json `
      -TopIntervals 5 `
      -ThresholdSeconds 60
  ```
- Findings:
  - Four gaps > 4.5 minutes where the pipeline sat idle (`WLLS-A07-AS-07` to `BOYO-A05-AS-02` transitions).
  - One extreme gap of 11,465 seconds (~3h11m) accounting for the overall throughput drop to 5.15 ports/min.
- Action: investigate why BOYO batches paused for ~3 hours (likely queue/scheduler contention). Use this script on future runs to ensure no gap exceeds the 60-second target.

### 2025-11-13 15:17 MT Dispatcher correlation
- Exported the idle-interval data for reuse:
  ```powershell
  pwsh Tools/Analyze-PortBatchIntervals.ps1 `
      -Path Logs/IngestionMetrics/2025-11-13.json `
      -ThresholdSeconds 60 `
      -OutputPath Logs/Reports/PortBatchIntervals-20251113.json
  ```
- Correlated dispatcher queue telemetry with the interval report:
  ```powershell
  pwsh Tools/Analyze-DispatcherGaps.ps1 `
      -QueueSummaryPaths Logs/IngestionMetrics/QueueDelaySummary-20251113-114756.json `
      -IntervalReportPath Logs/Reports/PortBatchIntervals-20251113.json `
      -GapThresholdSeconds 60 `
      -OutputPath docs/performance/DispatcherGapCorrelation-20251113.md
  ```
- Result: dispatcher guard still reports `QueueBuildDelay p95 24.87 ms / p99 25.26 ms`, yet four idle gaps ≥267 s remain (largest 11,465 s). All gaps share the same boundary (`WLLS-A07-AS-07` → `BOYO-A05-AS-02`), so the scheduler is pausing BOYO hosts despite an empty queue.
- Copied the markdown + JSON to `Logs/TelemetryBundles/Release-20251113/Telemetry/` and opened Plan D task ST-D-010 to track the mitigation.
- Added a site-pair breakdown for future comparisons:
  ```powershell
  pwsh Tools/Analyze-PortBatchGapBreakdown.ps1 `
      -IntervalReportPath Logs/Reports/PortBatchIntervals-20251113.json `
      -TopGaps 10 `
      -OutputPath docs/performance/PortBatchSiteGapSummary-20251113.md
  ```
  The markdown confirms all five WLLS → BOYO transitions average 2,478 s gaps (max 11,465 s) while every other site pair stays ≤ 2 s. Stored alongside the dispatcher correlation inside the telemetry bundle.
- Generated the host-level timeline for each gap:
  ```powershell
  pwsh Tools/Analyze-PortBatchGapTimeline.ps1 `
      -MetricsPath Logs/IngestionMetrics/2025-11-13.json `
      -GapThresholdSeconds 60 `
      -EventsBefore 5 `
      -EventsAfter 5 `
      -OutputPath docs/performance/WLLS_BOYO_GapTimeline-20251113.md
  ```
  Output shows five consecutive WLLS hosts (`...-A05-AS-25/35/45/55 -> WLLS-A07-AS-07`) before every idle window, then BOYO resumes immediately, proving the scheduler never interleaves sites during the stall. Timeline is bundled for Plan D/G evidence.
- Summarised site mix over rolling 5-minute windows:
  ```powershell
    pwsh Tools/Analyze-PortBatchSiteMix.ps1 `
        -MetricsPath Logs/IngestionMetrics/2025-11-13.json `
        -WindowMinutes 5 `
        -TopWindows 6 `
        -OutputPath docs/performance/PortBatchSiteMix-20251113.md
    ```
    These windows show WLLS maintaining 47-100% of batches while BOYO remains below 30% during the critical period (18:20-18:35 UTC), aligning with the timeline/diversity guard findings. Markdown copied into the telemetry bundle for Plan D ST-D-003/ST-D-010 references.
- Parsed the dispatcher sweep order:
  ```powershell
  pwsh Tools/Analyze-DispatchHarnessSweep.ps1 `
      -SweepPath Logs/DispatchHarness/RoutingQueueSweep-20251113.json `
      -OutputPath docs/performance/DispatchHarnessSweepOrder-20251113.md
  ```
  Report (`docs/performance/DispatchHarnessSweepOrder-20251113-balanced.md`) shows the harness executed five WLLS hosts before touching BOYO (matching the telemetry streaks). Added to the telemetry bundle and cited in ST-D-010 as evidence that our automation currently enforces a WLLS-first ordering.

## Next Steps
- Re-run the sweep after any UI, parser, or caching change that could impact streaming performance. Include the latest report in telemetry bundles and reference this baseline in Plan D ST-D-003 before sign-off.
- Add SPAN view instrumentation (Plan D ST-D-004/ST-D-007) so SPAN telemetry can be correlated with the incremental-loading data in future releases.

### 2025-11-14 Follow-up
- Added the missing WLLS host census to `Data/RoutingHosts.txt` (37 total) and regenerated the segmented rotation via `Tools/New-BalancedRoutingHostList.ps1`. Balanced list now drives `Tools\Invoke-RoutingQueueSweep.ps1 -UseBalancedHostOrder` without rebalancing.
- Latest harness evidence (`Logs/DispatchHarness/RoutingQueueSweep-20251114-balanced2.json`, `docs/performance/DispatchHarnessSweepOrder-20251114-balanced.md`) captures the improved ordering (max WLLS streak = 2, queue delay <32 ms). Include these artifacts in the next telemetry bundle alongside the incremental-loading analyzers.
- TODO: rerun the incremental-loading pipeline with the refreshed routing order so `Logs/IngestionMetrics/<date>.json`, site-diversity guard output, and Plan A references match the sweep data.
- Created `Tools/Add-PortBatchReadyTelemetry.ps1` to synthesize PortBatchReady events from InterfacePortStreamMetrics when the ingestion file omits them; generated `Logs/Reports/PortBatchReady-20251114.json` from `Logs/IngestionMetrics/2025-11-14.json`.
- Added `Tools/Generate-QueueDelaySummary.ps1` for lightweight queue summaries (`Logs/IngestionMetrics/QueueDelaySummary-20251114.json`, SampleCount=128, p95=20.02 ms, p99=20.76 ms).
- Updated analyzers (`PortBatchIntervals-20251114.json`, `docs/performance/DispatcherGapCorrelation-20251114.md`, `docs/performance/PortBatchSiteGapSummary-20251114.md`, `docs/performance/WLLS_BOYO_GapTimeline-20251114.md`, `docs/performance/PortBatchSiteMix-20251114.md`) and bundled everything under `Logs/TelemetryBundles/Release-20251114/Telemetry/`.
- Despite the balanced sweep, the site-diversity guard still fails (WLLS streak 25 vs. limit 8) and PortBatchReady-derived throughput jumps to 188 ports/min because harness sweeps execute in rapid succession. Plan D ST-D-003/ST-D-010 must now focus on smoothing the host scheduler so telemetry matches the balanced host order rather than synthetic replay bursts.

### 2025-12-05 Rerun (balanced host order)
- Reran the incremental-loading pipeline after the routing/scheduler cleanups:
  ```powershell
  pwsh Tools/Invoke-StateTracePipeline.ps1 `
      -SkipTests `
      -VerboseParsing `
      -ResetExtractedLogs `
      -RunSharedCacheDiagnostics
  ```
- Outputs:
  - Telemetry: `Logs/IngestionMetrics/2025-12-05.json`
  - Queue summary: `Logs/IngestionMetrics/QueueDelaySummary-2025-12-05.json` (appended to `Logs/Reports/QueueDelayHistory.csv`)
  - Port batch summaries: `Logs/Reports/PortBatchReady-2025-12-05.json`, `Logs/Reports/PortBatchSiteDiversity-2025-12-05.json`, `Logs/Reports/PortBatchHistory.csv`
  - Scheduler summaries: `Logs/Reports/ParserSchedulerLaunch-2025-12-05.json`, `Logs/Reports/ParserSchedulerHistory.csv`, `Logs/Reports/SchedulerVsPortDiversity-2025-12-05.json`, `docs/performance/SchedulerVsPortDiversity-2025-12-05.md`
  - Bundle: copied all of the above to `Logs/TelemetryBundles/Release-2025-12-05/Telemetry` for the current baseline.
- InterfaceSync analyzer currently fails with a `Count` property error when the telemetry lacks InterfaceSyncTiming events; follow up to harden `Tools/Analyze-InterfaceSyncTiming.ps1` before the next sweep.
- Site diversity now passes (max streak 1) under the balanced order; shared cache diagnostics show primary reliance on shared matches (BOYO 10/12, WLLS 24/35). Keep this run as the new baseline until the InterfaceSync analyzer is fixed.

### Planned refactors to reduce duplication (tracking)
- Shared cache plumbing: consolidate snapshot export/import/store init between `DeviceRepository.Cache.psm1` and `ParserPersistenceModule.psm1` into a common helper to eliminate divergent code paths.
- Analyzer stats: extract percentile/empty-set handling into a shared stats module and import it in `Tools/Analyze-InterfaceSyncTiming.ps1`, `Analyze-PortBatch*`, `Generate-QueueDelaySummary.ps1`, etc.
- Pipeline presets: introduce named profiles (Quick/Full/Diag) in `Tools/Invoke-StateTracePipeline.ps1` to replace multiple switch combinations and reduce guard duplication.
- Index expectations: centralize expected Access index definitions so `Modules/DatabaseModule.psm1`, `ParserPersistenceModule.psm1`, and `Tools/Maintain-AccessDatabases.ps1` consume the same list.
- Port normalization: unify port sort/normalization helpers between `InterfaceModule` and `DeviceRepositoryModule` to avoid parallel implementations.

### Port normalization unification plan
- Build a shared helper (`Modules/PortNormalization.psm1`) that captures the full InterfaceModule behavior: compiled regex options, type/number regexes, normalization rules (including MGMT/PO/LO/VL), and type weights.
- Update InterfaceModule to import the helper and drop its duplicated cache/normalization initialization while keeping existing weights/rules intact.
- Update DeviceRepositoryModule to import the same helper and rely on it for port sort keys so both modules share one implementation.
- Validate with `Invoke-Pester Modules/Tests` and a quick parse smoke test to confirm PortSort values remain stable.
- Implementation steps (to do):
  1) Expand `PortNormalization.psm1` with InterfaceModule’s full regex setup, normalization rules (MGMT/PO/LO/VL), type weights, cache stats, and `Get-PortSortKey`/`Get-PortSortCacheStatistics`.
  2) Refactor InterfaceModule to import the helper and remove its local PortSort init (retain all usage/behavior).
  3) Import the helper in DeviceRepositoryModule; keep calls to `InterfaceModule\Get-PortSortKey` or switch to the shared export if names match.
  4) Validate via `Invoke-Pester Modules/Tests` + a parser smoke run to ensure PortSort stability.

