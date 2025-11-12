# Plan B – Performance & Ingestion Scale

## Objective
Reduce cold- and warm-run latency for parser + persistence + shared cache flows while keeping telemetry exhaustive enough for autonomous troubleshooting. Plan B owns autoscale heuristics, site cache hydration, warm-run verification, and concurrency overrides.

## Current status (2025-11)
- Instrumentation now captures `InterfaceSiteCacheMetrics`, `InterfaceSiteCacheHostPersisted`, and `SiteCacheRecordsetDurationMs` (landed 2025-10-24; see historical log).
- Shared cache normalization (`Normalize-InterfaceSiteCacheEntry`) keeps preserved sessions typed, eliminating cache fallback on warm runs (2025-10-27 entries).
- Warm regression harness (`Tools/Invoke-WarmRunRegression.ps1`) enforces cache-hit ratio ≥99% and improvement ≥60% via `Tools/Invoke-StateTraceVerification.ps1`.
- Outstanding issue: WLLS-A01-AS-01 cold hydrations regressed from ~0.65 s to 2.7 s after autoscale experiments; investigation continues in “Active work”.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-B-001 | Investigate WLLS snapshot/materialize regression | Ingestion | In Progress | Focused cold pass shows snapshot 859 ms, materialize 593 ms, host-map candidate misses 1224. Need cache adoption/sort key fixes. |
| ST-B-002 | Trial reduced auto-scale ceilings post-batching | Ingestion | Ready for Review | Cold pass with ceilings=1 logged `DatabaseWriteLatency` avg 387 ms; decision pending on multi-worker requirement. |
| ST-B-003 | Codify concurrency overrides | Automation | Ready | Document override-to-metric mapping in `docs/CODEX_RUNBOOK.md` and task board; ensure overrides reset to 0 post-tests. |
| ST-B-004 | Restore preserved warm-run cache hits | Ingestion | In Progress | Use new `SiteCacheProviderReason` telemetry to explain `SiteCacheProvider=Unknown/Refresh`, push warm regression back to ≥99% cache hits, and capture metrics in `Logs/IngestionMetrics/WarmRunTelemetry-*.json`. |

## Recently delivered
- Restored InterfaceSync telemetry and dispatcher queue instrumentation (2025-10-15).
- Added warm-run verification thresholds to `VerificationModule` and `Tools/Invoke-StateTraceVerification.ps1` (2025-11-06).

## Recent timeline (migrated from consolidated log)
| Date (MT) | Summary | Metrics / Artifacts | Source |
|-----------|---------|---------------------|--------|
| 2025-10-15 17:20 | Cold-shell pipeline exposed WLLS-A07-AS-07 hydration costs dominating InterfaceCall duration (14.5 s fetch vs. 16.57 s total). | `Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs` run; `SiteCacheFetchDurationMs` logged alongside bulk/stream timings <100 ms. | docs/StateTrace_Consolidated_Plans.md:11 |
| 2025-10-15 17:35 | DeviceRepository instrumentation now emits `InterfaceSiteCacheMetrics`/`SiteCacheFetchStatus`, mirrored into ParserPersistence + DatabaseWriteBreakdown. | `Invoke-Pester Modules/Tests/DeviceRepositoryModule.Tests.ps1` and `Modules/Tests/ParserPersistenceModule.Tests.ps1` updated. | docs/StateTrace_Consolidated_Plans.md:12 |
| 2025-10-15 18:05 | Cleared `Data/IngestionHistory` and reran cold pipeline to capture full telemetry for BOYO/WLLS hydration tails. | `Logs/IngestionMetrics/2025-10-15.json` records BOYO Hydration 4.913 s / WLLS 14.781 s plus per-host `DatabaseWriteBreakdown.SiteCacheFetchDurationMs`. | docs/StateTrace_Consolidated_Plans.md:13 |
| 2025-10-15 18:45 | Stage-level metrics (query, execute, materialize, template, build) wired through `InterfaceSiteCacheMetrics`, revealing ADODB + host-map hotspots. | Example: BOYO Hydration 6.31 s (Query 1.99 s, Materialize 1.97 s); WLLS Hydration 14.42 s. | docs/StateTrace_Consolidated_Plans.md:15 |
| 2025-10-16 11:58 | Fresh cold pass (history cleared) confirmed hydrations now sub-second (max 0.637 s) after instrumentation. | `Logs/IngestionMetrics/2025-10-16.json` shows BOYO/WLLS hydration ≤0.637 s and `DatabaseWriteBreakdown.SiteCacheFetchDurationMs` ≤0.698 s. | docs/StateTrace_Consolidated_Plans.md:16 |
| 2025-10-24 09:33 | Focused cold pass (WLLS history cleared) still showed first host hydrating via Access while others hit cache. | `SiteCacheFetchDurationMs` 1,171.86 ms; `HostMapCandidateMissingCount=1224`. | docs/StateTrace_Consolidated_Plans.md:101 |
| 2025-10-24 11:07 | Landed `HydrationSnapshotRecordsetDurationMs` + `InterfaceSiteCacheHostPersisted` instrumentation with refreshed tests. | `Modules/Tests/DeviceRepositoryModule.Tests.ps1` / `ParserPersistenceModule.Tests.ps1` passing. | docs/StateTrace_Consolidated_Plans.md:105 |
| 2025-10-24 11:15 | Cold replay captured recordset vs. materialize timings (snapshot 992.7 ms vs. materialize 593.27 ms) showing Access still dominant. | See `Logs/IngestionMetrics/2025-10-24.json`. | docs/StateTrace_Consolidated_Plans.md:106 |
| 2025-10-24 13:25 | Port-sort cache audit revealed typed cache entries drop `PortSort`, forcing Gi1/0/1-27 misses; template hints also lack seeded data. | Action: persist sort key/template hints inside `ConvertTo-InterfaceCacheEntryObject`. | docs/StateTrace_Consolidated_Plans.md:117-118 |
| 2025-10-27 14:05 | Shared-cache snapshot normalization keeps typed host dictionaries so preserved sessions reuse caches. | `Normalize-InterfaceSiteCacheEntry` + snapshot helpers updated with tests. | docs/StateTrace_Consolidated_Plans.md:131 |
| 2025-10-27 15:10 | Script-scope caches adopt merged shared-store entries before reuse, preventing warm runs from falling back to refresh. | Regression coverage added (`DeviceRepositoryModule.Tests.ps1`). | docs/StateTrace_Consolidated_Plans.md:134 |
| 2025-10-27 16:05 | Warm verification still reported `SiteCacheProvider=Refresh`, so cache hits were invisible in DatabaseWriteBreakdown. | `Tools/Invoke-StateTraceVerification.ps1 -SkipTests -VerboseParsing` failure; evidence in `Logs/IngestionMetrics/2025-10-27.json`. | docs/StateTrace_Consolidated_Plans.md:135 |
| 2025-10-28 08:46 | ParserPersistence now reads renamed `InterfaceSiteCacheMetrics` fields, but warm verification continued to fail with Provider=Refresh. | `Modules/Tests/ParserPersistenceModule.Tests.ps1` updated; follow-up to reconcile `resolveCachedHost`. | docs/StateTrace_Consolidated_Plans.md:136 |
| 2025-11-06 09:15 | Verification harness enforces warm-run thresholds (improvement ≥25%, cache hit ≥99%) via `Test-WarmRunRegressionSummary`. | `Tools/Invoke-StateTraceVerification.ps1` + `Tools/Invoke-StateTraceScheduledVerification.ps1`; coverage in `Modules/Tests/VerificationModule.Tests.ps1`. | docs/StateTrace_Consolidated_Plans.md:36 |
| 2025-11-06 09:52 | Pipeline auto-imports/exports shared cache snapshots so cold runs hydrate from cache (WLLS fetch now 0 ms). | `Logs/SharedCacheSnapshot/SharedCacheSnapshot-latest.clixml` restored each run; cold pass shows `SiteCacheFetchDurationMs=0`. | docs/StateTrace_Consolidated_Plans.md:37 |
| 2025-11-07 16:20 | `Tools\Invoke-SharedCacheWarmup.ps1` produced snapshots (BOYO 12 hosts/120 rows, WLLS 25/1,200) but warm regression still failed with `WarmCacheProviderHitCount=215`. | Warm telemetry: `WarmCacheProviderMissCount=778`, improvement -1.73%; need to explain `SiteCacheProvider=Unknown/Refresh`. | docs/StateTrace_Consolidated_Plans.md:151 |
| 2025-11-07 17:05 | Added `SiteCacheProviderReason` telemetry to tag cache reuse vs. refresh vs. skipped hydrations, plus unit coverage. | `Modules/ParserPersistenceModule.psm1` + tests updated; next rerun to isolate provider reasons. | docs/StateTrace_Consolidated_Plans.md:152 |
| 2025-11-12 | Ensured cached interface rows retain their `PortSort` values by having `ConvertTo-InterfaceCacheEntryObject` compute the key whenever snapshots omit it; added regression coverage in `DeviceRepositoryModule.Tests.ps1`. | Modules/DeviceRepositoryModule.psm1, Modules/Tests/DeviceRepositoryModule.Tests.ps1, `Invoke-Pester Modules/Tests/DeviceRepositoryModule.Tests.ps1`. | – |

## Automation hooks
- `Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing [-ThreadCeilingOverride <n> ...]` with overrides logged in `docs/StateTrace_TaskBoard.md` and `docs/taskboard/TaskBoard.csv`.
- `Tools\Invoke-WarmRunRegression.ps1 -VerboseParsing` (or `Tools\Invoke-StateTracePipeline.ps1 -RunWarmRunRegression`) to prove cache hit ratios.
- `Tools\Invoke-StateTraceVerification.ps1` to enforce warm-run deltas and shared cache coverage.

## Telemetry gates
- `DatabaseWriteLatency` p95 <950 ms cold, <500 ms warm.
- `InterfaceSiteCacheMetrics.SiteCacheFetchDurationMs` p95 <5 s (alert when >10 s); WLLS regression investigation tracks this.
- `WarmRunComparison.ImprovementPercent` ≥60% with `WarmProviderCounts.Cache` covering every host.
- Document and check thresholds in `docs/telemetry/Automation_Gates.md#plan-b`.

## References & history
- Detailed notes in `docs/StateTrace_Consolidated_Plans.md` (see entries dated 2025-10-15 through 2025-10-27 and 2025-11-06).
- Task board cards ST-B-001 and ST-B-002 summarised at the top of `docs/StateTrace_TaskBoard.md`.
