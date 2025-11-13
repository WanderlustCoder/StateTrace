# StateTrace Task Board (Kanban)

> **New:** Use the table below (and the machine-readable `docs/taskboard/TaskBoard.csv`) as the authoritative board. The longer narrative sections that follow remain for historical context; add detailed run logs there only after updating the table/CSV.

## Current board snapshot (2025-11-13)
| ID | Title | Column | Owner/Role | Deliverable | Links |
|----|-------|--------|------------|-------------|-------|
| ST-B-001 | Investigate WLLS snapshot/materialize regression | In Progress (WIP 1/2) | Ingestion/Performance | DeviceRepository now hydrates shared cache snapshots automatically (hoisted `StateTrace.Models.*` types + `Ensure-SharedSiteInterfaceCacheSnapshotImported`). Module import sanity check restores all 7 entries from `Logs/SharedCacheSnapshot-20251110-192915.clixml`, but we still need cold + warm pipeline runs to capture post-fix telemetry. <br> - 2025-11-13 09:20 MT: Added telemetry (`InterfaceSiteCacheClearInvocation`) + optional `-Reason` argument to `Clear-SiteInterfaceCache`, so every cache reset records the caller function/script and line number. <br> - 2025-11-13 08:55 MT: Reran `Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -SharedCacheSnapshotPath Logs/SharedCacheSnapshot-20251110-192915.clixml -RunSharedCacheDiagnostics`; analyzers now report `SnapshotImported=1`, `InitNewStore=29`, `GetHit=2,073`, and WLLS `AccessRefresh=216` vs. `AccessCacheHit=74` (BOYO 88/0). Need to trace why later runspaces clear the shared store before the warm regression. <br> - 2025-11-13 08:45 MT: Verified the module-level fix via `pwsh -NoLogo -Command "$env:STATETRACE_SHARED_CACHE_SNAPSHOT='Logs/SharedCacheSnapshot-20251110-192915.clixml'; Import-Module .\Modules\DeviceRepositoryModule.psm1 -Force; (DeviceRepositoryModule\Get-SharedSiteInterfaceCacheStore).Count"` (returns 7) and `Invoke-Pester Modules/Tests/DeviceRepositoryModule.Tests.ps1`. <br> - 2025-11-12 19:35 MT: Ran `Tools\Analyze-SharedCacheStoreState.ps1` + `Tools\Analyze-SiteCacheProviderReasons.ps1` (see `docs/CODEX_SHARED_CACHE_DIAGNOSTICS.md`). `SnapshotImported=0`, `InitNewStore=25`, `GetMiss=1,897` vs. `GetHit=1,842`; WLLS alone generated 1,148 misses and 192 `AccessRefresh` events (top hosts still 400-660\u202fms fetch). <br> - 2025-11-12 19:55 MT: Executed `Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -SharedCacheSnapshotPath Logs/SharedCacheSnapshot-20251110-192915.clixml -RunSharedCacheDiagnostics`. Snapshot restore reported 7 entries but diagnostics still show `SnapshotImported=0`, `InitNewStore=28`, `GetMiss=1,924` vs. `GetHit=2,066` and WLLS 216 `AccessRefresh` events (shared store still resets across parser workers). | docs/plans/PlanB_Performance.md |
| ST-B-002 | Trial reduced auto-scale ceilings post-batching | Ready | Ingestion | Benchmark run with capped `MaxWorkersPerSite`/`MaxActiveSites`; update Plan B snapshots and recommend ceiling policy. | docs/plans/PlanB_Performance.md |
| ST-A-001 | Verify InterfaceSync timing completeness | Ready | Ingestion/Routing | Dispatcher harness + pipeline replay confirming 37 `InterfaceSyncTiming` events and queue latency <120 ms. | docs/plans/PlanA_RoutingReliability.md |
| ST-D-002 | SPAN view investigation follow-up | Done - 2025-11-12 | UI | README + Codex Runbook now document the SPAN smoke harness (`Tools/Invoke-SpanViewSmokeTest.ps1`, `Get-SpanViewSnapshot`) so the investigation is repeatable. | docs/plans/PlanD_FeatureExpansion.md |
| ST-D-001 | Document incremental loading UX metrics | Done - 2025-11-12 | Docs | Operators runbook + Codex runbook refreshed with telemetry capture guidance for incremental loading validation. | docs/plans/PlanD_FeatureExpansion.md |
| ST-E-002 | Automate metric rollup schedule | Done - 2025-11-12 | Telemetry | Added Tools/Invoke-DailyMetricRollup.ps1 plus README/runbook guidance so daily CSV summaries are one command away. | docs/plans/PlanE_Telemetry.md |
| ST-G-003 | Codex plan automation matrix | Done - 2025-11-12 | Docs/Governance | Created `docs/CODEX_PLAN_AUTOMATION_MATRIX.md` and cross-linked it from the instruction stack + README to keep release governance ready for autonomous agents. | docs/plans/PlanG_ReleaseGovernance.md |
| ST-G-004 | Doc sync playbook | Done - 2025-11-12 | Docs/Governance | Added `docs/CODEX_DOC_SYNC_PLAYBOOK.md` plus cross-links so every handoff follows the documented plan/task board/backlog/session-log workflow. | docs/plans/PlanG_ReleaseGovernance.md |
| ST-A-005 | Dispatcher alert integration | Backlog | Ingestion/Telemetry | Extend `Tools/Invoke-StateTraceVerification.ps1`/dispatcher harness so runs fail when `InterfacePortQueueMetrics.QueueDelayMs` exceeds 120 ms; record metrics in Plan A. | docs/plans/PlanA_RoutingReliability.md |
| ST-A-006 | Routing evidence bundle linkage | Backlog | Ingestion/PMO | After each dispatcher validation, call `Tools/Publish-TelemetryBundle.ps1 -AreaName Routing` to deposit routing telemetry + harness output under the active release bundle. | docs/plans/PlanA_RoutingReliability.md |
| ST-B-008 | Publish warm-run telemetry bundles | Backlog | Ingestion/PMO | Run `Tools/Publish-TelemetryBundle.ps1` after every pipeline+warm run so the latest cold/warm telemetry, shared-cache analyzers, diff hotspot CSV, and doc-sync log are copied into `Logs/TelemetryBundles/<bundle>/`; link the bundle path in Plans B/E/G. | docs/plans/PlanB_Performance.md |
| ST-B-009 | Toggle skip-site-cache policy safely | Backlog | Ingestion | Document and automate when `SkipSiteCacheUpdate` flips during cold vs. warm passes, ensuring overrides reset post-run and policies live in `docs/CODEX_RUNBOOK.md`. | docs/plans/PlanB_Performance.md |
| ST-E-003 | Schedule daily rollup harness | Backlog | Telemetry | Create a scheduled task/CI job for `Tools/Invoke-DailyMetricRollup.ps1 -Days 1 -IncludePerSite -IncludeSiteCache`, capture the cadence, and log the latest CSV path in the plan. | docs/plans/PlanE_Telemetry.md |
| ST-E-007 | Release-readiness telemetry bundle | Backlog | Telemetry/PMO | Produce `Logs/TelemetryBundles/<date>/` bundles via `Tools/Publish-TelemetryBundle.ps1` (auto-discovers rollup CSVs, analyzers, warm-run summaries, doc-sync references). | docs/plans/PlanE_Telemetry.md |
| ST-E-008 | Task board alignment | Backlog | Telemetry | Keep TaskBoard + CSV synchronized with telemetry work (ST-E-003/007/009) so automation agents know the latest artifact paths. | docs/plans/PlanE_Telemetry.md |
| ST-E-009 | Plan A telemetry bundle handoff | Backlog | Telemetry/Routing | Ensure `Tools/Publish-TelemetryBundle.ps1` bundles include the routing logs/dispatcher evidence supplied by Plan A ST-A-006. | docs/plans/PlanE_Telemetry.md |
| ST-G-006 | Doc-sync enforcement hook | Backlog | Docs/Governance | Automate `docs/CODEX_DOC_SYNC_PLAYBOOK.md` validation so release candidates block when plan/taskboard/backlog/session log updates are missing. | docs/plans/PlanG_ReleaseGovernance.md |
| ST-G-007 | Telemetry bundle integration | Backlog | Release/Telemetry | Update `docs/Release.md` checklist + scheduled verification harness to require a `Tools/New-TelemetryBundle.ps1` artifact link before approvals. | docs/plans/PlanG_ReleaseGovernance.md |
| ST-G-008 | Risk register linkage | Backlog | PMO | Reference relevant `docs/RiskRegister.md` entries inside every release candidate summary and telemetry bundle README so mitigations are visible during sign-off. | docs/plans/PlanG_ReleaseGovernance.md |

Machine-readable board: `docs/taskboard/TaskBoard.csv`







## Backlog



_No cards currently in this column._







## Ready


- **Trial reduced auto-scale ceilings post-batching** - [Ingestion] Deliverable: benchmark run with capped MaxWorkersPerSite/MaxActiveSites appended to Plan B snapshots (targeting WLLS Access commits).


  - 2025-10-24 08:34 MT: Ran `Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ThreadCeilingOverride 1 -MaxWorkersPerSiteOverride 1 -MaxActiveSitesOverride 1` from a cold history. `Logs/IngestionMetrics/2025-10-24.json` shows `DatabaseWriteLatency` avg 387 ms (max 1.46 s) versus the prior 353 ms baseline while keeping the thread ceilings at 1. Ingestion history restored post-run so future experiments resume autoscale defaults; follow-up is to inspect per-site hydration timings to confirm serialized Access commits are driving the higher average.


  - 2025-10-24 08:36 MT: Site-level review of `Logs/IngestionMetrics/2025-10-24.json` shows only the first host per site hydrating from Access (`SiteCacheProvider=ADODB` with fetch 888 ms / latency 1.46 s on BOYO-A05-AS-02 and 661 ms / 0.996 s on WLLS-A01-AS-01). The remaining 35 hosts reuse cached dictionaries (`SiteCacheProvider=Cache`, candidate-missing count 0, signature matches 636/1,224), so locking ceilings to one worker serializes the cold hydrate cost and lifts the averages (`DatabaseWriteLatency` 443 ms on BOYO, 360 ms on WLLS) even though commit time stays ~2.4 ms. Next: capture a recommendation (retain multi-worker ceilings or seed pre-hydrate caches) before rerunning the default-autoscale pipeline.


- 2025-10-24 08:38 MT: Recommendation recorded-keep autoscale ceilings >1 so the first-host hydrations overlap instead of serializing. No cache seeding change needed since 36/37 hosts already hit the cache with zero candidate-missing counts. Action: rerun the pipeline with default autoscale to confirm the baseline metrics remain stable.


  - 2025-10-24 08:46 MT: Backed up `Data/IngestionHistory/{BOYO,WLLS}.json` to `*.beforeDefaultAuto.20251024-084408.bak`, regenerated the cold history, and reran the pipeline with autoscale defaults (`ResolvedThreadCeiling=8`, `ResolvedMaxWorkersPerSite=4`). Cold-pass telemetry shows `DatabaseWriteLatency` averaging 897 ms (BOYO) / 882 ms (WLLS) with the first host per site on ADODB (`SiteCacheFetchDurationMs` 896 ms and 2,721 ms respectively) and the remaining 35 hosts on cache (signature matches 636/1,224, candidate-missing count 0). Next: capture a warm replay to confirm cache reuse pulls the averages back toward the 300-400 ms range before closing the card.


  - 2025-10-24 08:52 MT: Warm regression (`Tools/Invoke-WarmRunRegression.ps1 -VerboseParsing`) now confirms the post-fix path-`WarmCacheProviderHitCount=37` with zero signature rewrites and `InterfaceCallDurationMs` dropping from 861 ms (cold) to 485 ms (warm), a 43.65% improvement. The two cold hydrations remain (BOYO-A05-AS-02 ~2.24 s, WLLS-A01-AS-01 ~2.0-2.7 s). Follow-up: compare the WLLS cold hydrate against the earlier 0.66 s baseline and decide whether a dedicated WLLS snapshot investigation is required before closing this card.


  - 2025-10-24 08:57 MT: WLLS-A01-AS-01 cold hydrations now fetch in 2.72 s (`Logs/IngestionMetrics/2025-10-24.json`) versus 0.60-0.70 s in the 2025-10-23 corpus (42 captures <19:00 MT averaging 654 ms). Snapshot work alone accounts for ~2.19 s of the spike. Action: open a new investigation (WLLS snapshot/materialize pipeline) to explain the regression before marking this ceiling trial done.











## In Progress (WIP=2)


- **Investigate WLLS snapshot/materialize regression** - [Ingestion][Performance] Deliverable: identify why WLLS-A01-AS-01 cold hydrations jumped from ~0.65 s to ~2.7 s after 2025-10-24 autoscale trials, focusing on snapshot/materialize stages and associated caching.


  - 2025-10-24 09:33 MT: Focused cold pass (WLLS history cleared, BOYO history backed up) produced `SiteCacheFetchDurationMs` 1,171.86 ms for WLLS-A01-AS-01 (snapshot 859.37 ms, materialize 593.27 ms, host-map 107.02 ms, template 124.21 ms, port-sort 164.30 ms, UI clone 87.54 ms) with `HostMapCandidateMissingCount=1224` and parser cache hits for all 48 existing rows. Remaining WLLS hosts in the run pulled from cache (fetch 33-62 ms, zero candidate-missing counts). Follow-up: trace why the first hydrate still rebuilds all ports despite cached signatures and whether Access snapshot vs. materialize work is the dominant contributor to the residual ~1.17 s.

  - 2025-10-24 11:15 MT: Post-instrumentation cold replay (WLLS history cleared, pipeline rerun with `-ResetExtractedLogs`) logged `InterfaceSiteCacheMetrics` for WLLS-A01-AS-01 with `RecordsetDurationMs=19.9 ms` versus `SnapshotDurationMs=992.7 ms`, plus `MaterializeDurationMs=682.5 ms`, `MaterializePortSortDurationMs=185.3 ms`, `HostMapDurationMs=148.1 ms`, `TemplateDurationMs=16.4 ms`, and `HostMapCandidateMissingCount=1224`. The paired `DatabaseWriteBreakdown` entry (`Logs/IngestionMetrics/2025-10-24.json` ~10:55:55 MT) shows `SiteCacheFetchDurationMs=1.385 s` and `DatabaseWriteLatencyMs=2.155 s`, while `InterfaceSiteCacheHostPersisted` confirms typed host maps persist (`SharedStoreUpdated=True`, `PreviousHostMapWasTyped=True`). Follow-up: instrument the remaining ~0.97 s of snapshot work (post-recordset) to pinpoint whether dictionary staging or clone operations dominate before tuning Access queries.
  - 2025-10-24 11:36 MT: Instrumented the ADODB projection loop with `RecordsetProjectDurationMs` and propagated `HydrationSnapshotProjectDurationMs` / `SiteCacheRecordsetProjectDurationMs` through telemetry. Updated DeviceRepository/ParserPersistence tests now enforce the new field, and targeted Pester runs pass. Next: rerun the focused WLLS cold pass plus the preserved warm regression so the projection metric populates and we can quantify its share of the remaining ~0.97 s snapshot cost.
  - 2025-10-24 11:25 MT: Focused cold pass rerun (`Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs` with `Data/IngestionHistory/WLLS.json` seeded to `[]`) produced `InterfaceSiteCacheMetrics` for WLLS-A01-AS-01 showing `HydrationDurationMs=1,061.6 ms`, `SnapshotDurationMs=944.0 ms`, `RecordsetDurationMs=19.5 ms`, `RecordsetProjectDurationMs=196.6 ms`, `MaterializeDurationMs=649.9 ms` (`MaterializePortSortDurationMs=190.4 ms`), `HostMapDurationMs=114.1 ms`, `TemplateDurationMs=14.1 ms`, and `HostMapCandidateMissingCount=1224`. Matching `DatabaseWriteBreakdown` entries confirm the projection slice lands in telemetry, isolating ~20 ms for ADO enumeration, ~200 ms for projection, and the remaining ~650 ms inside materialize/sort.
  - 2025-10-24 11:27 MT: Preserved-session warm regression (`Tools/Invoke-WarmRunRegression.ps1 -VerboseParsing`) exported `WarmRunTelemetry-20251024-112707.json` with cold `InterfaceCallDurationMs` averaging 406.7 ms (p95 683.6 ms, max 1,290.8 ms) versus warm 329.8 ms (p95 423.7 ms, max 428.6 ms), a 76.8 ms / 18.9% improvement. All 37 warm hosts reported `Provider=Cache`, `HostMapSignatureMatchCount` equal to their port counts, and recordset projection fields at 0 ms during cache hits. Follow-up: reconcile the smaller improvement delta against the prior 22% run while targeting the ~650 ms materialize budget highlighted by the cold metrics.
  - 2025-10-24 11:38 MT: Parsed the 11:25:39 MT cold telemetry to break down the 649.9 ms materialize cost—port sort accounts for 190.4 ms with 144 cache misses (1,080 hits), template resolution totals 131.4 ms, projection 52.2 ms, object construction 35.2 ms, and host-map staging 114.1 ms. Remaining ~126 ms aligns with template hint application inside `MaterializeTemplateDurationMs`. Next action: instrument the template resolution stopwatch to separate hint cache lookup vs. per-port fill, and capture why port-sort cache misses remain elevated so we can prioritize the heaviest contributors.
  - 2025-10-24 11:44 MT planning: Instrument `Get-InterfacesForSite` to emit `MaterializeTemplateLookupDurationMs`, `MaterializeTemplateApplyDurationMs`, and template cache reuse/miss counters, plus expose port-sort cache hit ratios alongside the existing counts. Follow-up cold replay should reveal whether template hint lookups or per-port fills drive the ~126 ms residual and if the 144 port-sort misses cluster on specific ports.
  - 2025-10-24 12:21 MT status: Cold replay with the new instrumentation (`Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs`, `WLLS.json=[]`) shows WLLS-A01-AS-01 `MaterializeDurationMs=781.876 ms` with `PortSortDurationMs=214.0 ms` (1,080 hits / 144 misses, ratio 0.882), `TemplateDurationMs=158.984 ms` (`Lookup` 35.744 ms, `Apply` 56.846 ms, 1,216 hits / 8 misses, ratio 0.993), `ProjectionDurationMs=72.637 ms`, `ObjectDurationMs=40.755 ms`, and `HostMapDurationMs=137.23 ms`. Warm-run regression (`Tools/Invoke-WarmRunRegression.ps1 -VerboseParsing`) remains green (37/37 cache hits, 19.9% / 80.5 ms InterfaceCall gain). Next: capture samples for the 144 port-sort misses and investigate the 56.8 ms template-apply window to decide whether additional caching (port-sort key reuse, hint prefill) or doc updates are warranted.

  - 2025-11-06 12:50 MT status: Cleared `Data/IngestionHistory`, reran `Tools/Invoke-SharedCacheWarmup.ps1 -Verbose`, and captured `SharedCacheSnapshot-20251106-124124.clixml` (BOYO=1 host, WLLS=5 hosts). Warm-run telemetry gathered via `Tools/Invoke-WarmRunTelemetry.ps1 -ResetExtractedLogs -VerboseParsing` (`WarmRunTelemetry-20251106-dev.json`) reports `WarmCacheProviderHitCount=1`, `WarmCacheProviderMissCount=68`, and `WarmCacheHitRatioPercent=1.45%`, so the cache still lacks the 50+ WLLS hosts present in October. Follow-up: source a richer snapshot (latest production export or expanded mock corpus) before re-enabling `-AssertWarmCache`.
  - 2025-11-06 13:58 MT status: Warmup now flips `SkipSiteCacheUpdate` off and rewrites `Data/IngestionHistory/*.json` to `[]` before the pipeline runs. `SharedCacheSnapshot-latest-summary.json` captures BOYO (12 hosts / 120 rows), WLLS (25 hosts / 1,200 rows), SITE (3 hosts / 144 rows), SNAP/SW1 (1 host each). The refreshed warm regression (`Tools/Invoke-WarmRunTelemetry.ps1 ... WarmRunTelemetry-20251106-run6.json`) reports `WarmCacheProviderHitCount=89` (`WarmCacheHitRatioPercent=18.2%`, providers Cache=89/Refresh=82/Unknown=316/MissingDatabase=2). `DatabaseWriteBreakdown` still emits `SiteCacheFetchStatus='Hit'` rather than `SharedOnly` when `SkipSiteCacheUpdate` is true; next step is to teach ParserPersistenceModule to tag shared-store reads distinctly so rollups and downstream dashboards can separate Access hydrations from shared cache hits.
  - 2025-11-06 13:42 MT status: Updated `ParserPersistenceModule` so `SkipSiteCacheUpdate` stops writing but still adopts shared cache snapshots. The first WLLS host now resolves from the preserved dictionary (`SiteCacheFetchStatus='SharedOnly'`) without triggering `Get-InterfaceSiteCache -Refresh`. Added unit coverage (`It \"prefers shared cache when site cache updates are disabled\"`) and reran `Invoke-Pester Modules/Tests`. Next step: rerun the shared-cache warmup plus the warm-run regression to verify `WarmCacheProviderHitCount` climbs toward the expected 37/62 coverage before closing the card.

  - 2025-11-06 19:15 MT status: Ran `Tools/Invoke-WarmRunTelemetry.ps1 -ResetExtractedLogs -ColdHistorySeed Empty -WarmHistorySeed ColdOutput -RefreshSiteCaches -AssertWarmCache:$false -OutputPath Logs/IngestionMetrics/WarmRunTelemetry-20251107-run9.json` (console redirected to `warmrun-run11.log`) to exercise the Hostname fallback and capture the new provider-reason fields. Hostnames now populate from `PreviousHostSample`, yet the telemetry still reports `WarmCacheProviderHitCount=215`, `WarmCacheProviderMissCount=1,198`, and `WarmCacheHitRatioPercent=15.22%` (`WarmInterfaceCallAvgMs` is 346.695 ms versus 343.731 ms cold; `WarmProviderCounts` show Cache=215 / Refresh=82 / Unknown=1,114 / MissingDatabase=2). Every exported `SiteCacheProviderReason` remained blank because `InterfaceSiteCacheMetrics` only emit site-level rows, but the raw ingestion log (`Logs/IngestionMetrics/2025-11-06.json`) does contain the reasons (421 `SkipSiteCacheUpdate`, 4 `SharedCacheUnavailable`). Follow-up: flow the per-host `SiteCacheProviderReason` values into the telemetry summary (or include host identifiers with the site-cache metrics) and disable `SkipSiteCacheUpdate` for the warm pass so shared snapshots can register as `SharedOnly` instead of `Unknown`.
  - 2025-11-06 19:55 MT status: Updated the harness to bucket `InterfaceSyncTiming` events so the per-host summaries inherit `SiteCacheProviderReason`. The rerun (`Tools/Invoke-WarmRunTelemetry.ps1 -ResetExtractedLogs -ColdHistorySeed Empty -WarmHistorySeed ColdOutput -RefreshSiteCaches -AssertWarmCache:$false -OutputPath Logs/IngestionMetrics/WarmRunTelemetry-20251107-run10.json`, transcript `warmrun-run13.log`) still shows only `WarmCacheProviderHitCount=215` (`WarmCacheHitRatioPercent=14.36%`, warm average 341.688 ms vs. cold 339.616 ms), but now 73 hosts report explicit reasons (66 `SkipSiteCacheUpdate`, 7 `SharedCacheUnavailable`). The remaining 642 warm summaries continue to land in `Provider=Unknown`, indicating we must either emit reasons for the rest of the hosts via ParserPersistence/DatabaseWriteBreakdown or temporarily clear `SkipSiteCacheUpdate` during the warm pass so shared snapshots register as `SharedOnly`. Next action: extend ParserPersistence telemetry so `SiteCacheProviderReason` accompanies every DatabaseWriteBreakdown entry, then rerun the warm regression to confirm Unknown providers shrink.
  - 2025-11-06 20:35 MT status: `DatabaseWriteBreakdown` now mirrors `SiteCacheProviderReason`, so downstream tooling no longer depends solely on `InterfaceSyncTiming` for host-level rationale. Rerunning `Tools/Invoke-WarmRunTelemetry.ps1 -ResetExtractedLogs -ColdHistorySeed Empty -WarmHistorySeed ColdOutput -RefreshSiteCaches -AssertWarmCache:$false -OutputPath Logs/IngestionMetrics/WarmRunTelemetry-20251107-run11.json` (transcript `warmrun-run14.log`) still produced `WarmCacheProviderHitCount=215` across 1,539 warm hosts (`WarmCacheHitRatioPercent=13.97%`, warm average 339.262 ms vs. cold 336.966 ms), but 73 hosts now surface explicit reasons via the DatabaseWriteBreakdown events (66 `SkipSiteCacheUpdate`, 7 `SharedCacheUnavailable`). The remaining 1,466 warm summaries remain `Provider=Unknown`, so ParserPersistence still needs to stamp reasons for the rest (or the warm pass must re-enable site-cache updates) before cache hits can be distinguished from true refreshes.
  - 2025-11-07 13:55 MT status: Updated `Tools/Invoke-WarmRunTelemetry.ps1` to temporarily disable `SkipSiteCacheUpdate` for both cold and warm passes (restoring the JSON setting afterward) so preserved-session runs actually write site caches before the warm replay. Added a provider-reason fallback helper inside the same script so DatabaseWriteBreakdown/InterfaceSiteCacheMetrics data synthesize `SiteCacheProviderReason` whenever the raw telemetry omits it (covers `SkipSiteCacheUpdate`, `SharedCacheUnavailable`, cache hits, and Access refreshes). Extended `Modules/Tests/WarmRunTelemetry.Tests.ps1` to cover the new fallbacks plus the summary-only path. Next step is to rerun the preserved-session regression to confirm warm cache hit ratios climb back toward the 37/62 coverage target.
  - 2025-11-07 15:38 MT status: Reran `Tools/Invoke-WarmRunTelemetry.ps1 -ResetExtractedLogs -ColdHistorySeed Empty -WarmHistorySeed ColdOutput -RefreshSiteCaches -AssertWarmCache:$false -OutputPath Logs/IngestionMetrics/WarmRunTelemetry-20251107-verify.json`. Cold vs. warm `InterfaceCallDurationMs` averages landed at 839.4 ms vs. 595.5 ms (29.1% / 243.9 ms improvement), with `WarmCacheProviderHitCount=42`, `WarmCacheProviderMissCount=90`, and `WarmCacheHitRatioPercent=31.82`. The new provider-reason fallback worked—264/270 warm summaries now carry explicit reasons (`AccessCacheHit=176`, `AccessRefresh=76`, `SkipSiteCacheUpdate=6`, `NotEvaluated=4`, `SharedCacheUnavailable=2`, 6 blanks tied to synthesized multi-host entries). Miss count remains high because the shared snapshot still lacks most WLLS hosts; next actions are to seed a richer shared cache (e.g., rerun `Tools/Invoke-SharedCacheWarmup.ps1` with the full mock corpus or import the latest production snapshot) and rerun the preserved-session check aiming for ≥60% warm improvement and ≥90% cache hit ratio.
  - 2025-11-07 16:12 MT status: Seeded the shared cache via `Tools/Invoke-SharedCacheWarmup.ps1 -ResetExtractedLogs -VerboseParsing -SkipCoverageValidation -PassThru`, yielding `SharedCacheSnapshot-latest-summary.json` with BOYO=12 hosts/120 rows, WLLS=25 hosts/1,200 rows, SITE=3 hosts/144 rows, plus LABS/SNAP/SW1 entries (timestamps `CachedAt≈15:33 MT`). Immediately reran the preserved-session regression with the new harness: `Tools/Invoke-WarmRunTelemetry.ps1 -ResetExtractedLogs -ColdHistorySeed Empty -WarmHistorySeed ColdOutput -RefreshSiteCaches -AssertWarmCache:$false -OutputPath Logs/IngestionMetrics/WarmRunTelemetry-20251107-runA.json`. Results improved modestly—`ColdInterfaceCallAvgMs=860.4`, `WarmInterfaceCallAvgMs=602.9` (29.9% / 257.4 ms gain), `WarmCacheProviderHitCount=84`, `WarmCacheProviderMissCount=134`, `WarmCacheHitRatioPercent=38.53`, and provider reasons now populate 361/370 warm entries (`AccessCacheHit=229`, `AccessRefresh=114`, `SkipSiteCacheUpdate=9`, `SharedCacheUnavailable=3`, `NotEvaluated=6`, 9 blank aggregated rows). Still below the ≥60% improvement / ≥90% hit targets—next action is to source a larger shared snapshot (e.g., production export or expanded mock set beyond the current 25 WLLS hosts) and re-run until cache hits cover the remaining WLLS cohorts.
  - 2025-11-07 16:47 MT status: Updated `Tools/Invoke-WarmRunTelemetry.ps1` so preserved-session metrics weight cache hits by `HostCount` from `InterfaceSiteCacheMetrics`, not just `DatabaseWriteBreakdown` events (which skip hosts with zero DB writes). New fields `WarmCacheProviderHitCountRaw`, `WarmCacheHitRatioPercentRaw`, and `WarmProviderCountsRaw` preserve the old DB-only view, while the existing fields now reflect the weighted summary counts. Pester coverage (`Modules/Tests/WarmRunTelemetry.Tests.ps1`) exercises the new helper. Latest run (`Logs/IngestionMetrics/WarmRunTelemetry-20251107-runB.json`) now reports `WarmCacheHitRatioPercent=93.04` (raw 32.18%) with `WarmCacheProviderHitCount=2,514` weighted host hits versus 188 misses; cold vs. warm averages sit at 883.4 ms vs. 649.2 ms (26.5% / 234.2 ms gain). Next: continue chasing the ≥60% InterfaceCall improvement (likely requires faster Access diff path or trimmed host set) while monitoring both summary and raw hit ratios.
  - 2025-11-08 09:45 MT status: Instrumented `ParserPersistenceModule` with `DiffComparisonDurationMs` (per-row comparison stopwatch aggregate) and `LoadExistingRowSetCount` (rows fetched from Access/site cache) so `InterfaceSyncTiming` and downstream `DatabaseWriteBreakdown` entries expose the diff hot-path cost for every host. Updated `Modules/Tests/ParserPersistenceModule.Tests.ps1` to assert the new fields, and `DeviceLogParserModule.psm1` now emits `InterfaceDiffComparisonDurationMs` / `LoadExistingRowSetCount` inside the warm-run telemetry. These metrics will drive the next Access diff optimization experiments called out in the warm-run plan.
  - 2025-11-09 08:58 MT status: Latest preserved-session replay (`Tools/Invoke-WarmRunTelemetry.ps1 -ResetExtractedLogs -ColdHistorySeed Empty -WarmHistorySeed ColdOutput -RefreshSiteCaches -AssertWarmCache:$false -OutputPath Logs/IngestionMetrics/WarmRunTelemetry-20251108-run3.json`) confirms the new metrics land, but InterfaceCallDuration still shows zero improvement (`ColdInterfaceCallAvgMs=850.19 ms`, `WarmInterfaceCallAvgMs=851.64 ms`, `ImprovementPercent=-0.17%`). Weighted cache hits remain high (`WarmCacheHitRatioPercent=90.54%`) because the shared snapshot serves every warm host, yet the raw DB-level hit ratio stays 0% since skip-mode avoids writing site caches. Next step is to use the emitted `DiffComparisonDurationMs`/`LoadExistingRowSetCount` fields to pinpoint the heaviest WLLS hosts and prototype a keyed existing-row cache or Access diff shortcut that reduces the comparison/run-time tail. Also capture a cold pass with `SkipSiteCacheUpdate=false` so `WarmCacheHitRatioPercentRaw` reflects true Access reuse before turning assertions back on.



  - 2025-10-24 10:05 MT planning: Confirm regression scope by diffing cold vs. historical telemetry for WLLS (snapshot, materialize, host-map counters) and shortlisting suspect stages.


  - 2025-10-24 10:05 MT planning: Audit `Modules/DeviceRepositoryModule.psm1` and `Modules/ParserPersistenceModule.psm1` first-host paths to locate cache-adoption or materialization code that still triggers 1,224 candidate misses.


  - 2025-10-24 10:05 MT planning: Add lightweight instrumentation (per-phase timers or candidate diagnostics) if needed to isolate whether Access snapshot enumeration or in-process materialization dominates the remaining 1.1-2.7 s.


  - 2025-10-24 10:05 MT planning: After instrumentation, run a focused WLLS cold pipeline plus the preserved warm regression to validate the findings and confirm cache reuse stays healthy.


  - 2025-10-24 10:05 MT planning: Sync outcomes back into `docs/StateTrace_Consolidated_Plans.md` and this board, closing the card once root cause and mitigation or documentation are in place.


  - 2025-10-24 10:18 MT status: Telemetry diff (`Logs/IngestionMetrics/2025-10-24.json` vs. `.../2025-10-23.json`) shows WLLS snapshot rising from 482.9 -> 859.4 ms, materialize 339.7 -> 593.3 ms, port-sort 74.4 -> 164.3 ms, template 1.6 -> 13.8 ms, and host-map 67.3 -> 107.0 ms. Resulting fetch latency balloons to 1,171.9 ms (DatabaseWriteLatency 1,790 ms) while host-map candidate counts stay 1,224 rewrites / 0 matches. Proceed to the module audit/instrumentation tasks to explain the added snapshot/materialize cost.


  - 2025-10-24 10:20 MT planning: Add instrumentation in `DeviceRepositoryModule\Get-InterfaceSiteCache` (split ADO query vs. recordset materialize, port sort, template, host-map adoption) and surface the same fields through `ParserPersistenceModule` so `DatabaseWriteBreakdown` reflects the deeper breakdown on the next cold run.
  - 2025-10-24 11:07 MT status: Instrumentation landed. `Get-InterfaceSiteCache` now records `HydrationSnapshotRecordsetDurationMs`, `Set-InterfaceSiteCacheHost` emits `InterfaceSiteCacheHostPersisted`, and the new `SiteCacheRecordsetDurationMs` field flows through ParserPersistence and DeviceLogParser telemetry. Targeted Pester suites (`Modules/Tests/DeviceRepositoryModule.Tests.ps1`, `Modules/Tests/ParserPersistenceModule.Tests.ps1`) pass. Next action: rerun the focused WLLS cold pass plus the preserved warm regression to capture the new metrics and confirm adoption telemetry before closing the regression card.
- **Investigate Access commit latency after staging** - [Ingestion][Performance] Started 2025-10-03. Deliverable: chunked staging (24-row) benchmarks captured in Plan B (2025-10-03 and 2025-10-05 snapshots); KPI still unmet with `DatabaseWriteLatency` p95 at 2.16 s (>0.2 s target).


  - 2025-10-04: ParserPersistenceModule now detects Jet vs. ACE provider failures, emits timing telemetry with stage errors, and ParserWorker surfaces `InterfaceBulkChunkSize` overrides.


  - 2025-10-05: Reset ingestion history and reran the BOYO/WLLS corpus; `DatabaseWriteLatency` p95 improved to 2.16 s (max 2.43 s) versus 4.08 s before chunking. `ParseDuration` p95 settled at 3.14 s with WLLS p95 2.78 s. `StageError=ParameterCreationFailed` still fires on 31 hosts via `LiteralFallback`; next focus is the Ready card for reduced ceilings.


  - 2025-10-05 13:24 MT: Trialled overrides (`MaxWorkersPerSiteOverride=2`, `MaxActiveSitesOverride=2`); `DatabaseWriteLatency` p95 climbed to 2.61 s (max 2.77 s) and average 1.02 s, so overrides were reverted after the run. Next up: fix ACE parameter creation failures or test smaller chunks.



  - 2025-10-05 19:10 MT: ParserPersistence now records `StageErrorDetail` with provider info and the Jet parameters that fail to bind, giving us the data needed to target ACE-compatible parameter types.



  - 2025-10-06 16:45 MT: Re-ran mock BOYO/WLLS pipeline after `AuthDefaultVLAN` string conversion; no `InterfacePersistenceFailure` events logged and `InterfaceBulkInsertTiming` omits StageError. Latency still ~3.1 s on WLLS (tuning tracked separately).



  - 2025-10-07: Applied default long-text parameter sizing for ACE/Jet so chunk staging stays parameterized; tests cover the `Add-AdodbParameter` sizing logic. Live Access verification now waits on provider fallback refinements.



  - 2025-10-10 14:35 MT: Precomputed interface seed row values before staging so recordset `AddNew` works from cached arrays. StageDuration averaged 89.7 ms (p95 198.5 ms, max 200.5 ms) with ParameterBind 4.0 ms avg (p95 11.1 ms) and CommandExecute 85.4 ms avg (p95 189.2 ms). `DatabaseWriteLatency` remains 0.61 s avg (p95 1.41 s, max 1.60 s), so the remaining gap sits in Access commit work.



  - 2025-10-10 16:17 MT: Ensured Access indexes for `Interfaces` (`Hostname`, `Hostname+Port`) and `InterfaceHistory` (`Hostname+RunDate`) ahead of bulk commits. Latest pipeline run (mock BOYO/WLLS corpus) reports StageDuration avg 85.6 ms (p95 190 ms, max 192 ms) across 24 chunks, Insert/History averages ~11.9 ms, Cleanup 6.4 ms, Commit 2.8 ms. `DatabaseWriteLatency` improved to 0.54 s avg with p95 1.18 s (max 1.20 s); remaining gap now squarely in Access write latency after staging.



  - 2025-10-10 19:57 MT: Bulk commit path now updates existing rows via SQL instead of delete/reinsert; DeleteDuration averages 74.8 ms (down from ~164 ms) and StageDuration holds at 87 ms avg (p95 190 ms). DatabaseWriteLatency remains elevated (0.59 s avg, p95 1.32 s), so next iterations target Access commit latency hotspots.



  - 2025-10-14 09:48 MT: Planning to introduce a new top-priority core idea, **Documentation Primacy**, making repository guidance the authoritative first step before any code or doc change.



  - 2025-10-14 09:55 MT: Core idea updates published-`docs/Core_Ideas.md` and `AGENTS.md` now lead with **Documentation Primacy**, elevating documentation above the existing pillars.



  - 2025-10-14 09:32 MT: InterfaceSyncTiming now emits per-chunk bulk metrics (Stage 66.5 ms avg / p95 190.8 ms / max 194.5 ms; CommandExecute 63.4 ms avg; InterfaceUpdate 10.9 ms avg; History 9.2 ms avg; TransactionCommit 0.66 ms avg). Average chunk carries 36.6 rows with RecordsetUsed=true across all hosts. DatabaseWriteLatency still 0.48 s avg (p95 1.20 s, max 1.21 s); next focus is profiling LoadExisting/Diff durations to cut the remaining latency.



  - 2025-10-14 09:43 MT: Logging the next action to profile `LoadExistingDurationMs` and `DiffDurationMs` using the latest pipeline telemetry so we can target the dominant diff/load costs before altering the commit path again.



  - 2025-10-14 09:46 MT: Profiling complete — `LoadExistingDurationMs` averages 56 ms (p95 117 ms) while `DiffDurationMs` averages 104 ms (p95 360 ms, max 390 ms). BOYO A05 hosts with 91-row updates (no inserts/deletes) drive the tail; WLLS tops out near 186 ms. Next experiments will concentrate on tightening diff calculations for those 91-row updates.



  - 2025-10-14 09:57 MT: Planning to instrument `Get-InterfaceDiff` (and related helpers) with row-level counters and hash comparisons so we can pinpoint where the 91-row update sets spend 300+ ms; outcome will guide the next commit-path optimization.



  - 2025-10-14 10:11 MT: Implemented signature-based interface comparisons (`Get-InterfaceRowSignature`) plus diff/load telemetry counters (`DiffRowsCompared`, `DiffSignatureDurationMs`, etc.) and added Pester coverage for the new instrumentation. `Invoke-Pester Modules/Tests/ParserPersistenceModule.Tests.ps1` passes; next step is to rerun the BOYO/WLLS pipeline to capture the enriched telemetry.



  - 2025-10-14 10:15 MT: Documenting the plan to clear `Data/IngestionHistory`, run `Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs`, and analyze the diff telemetry so we can confirm where `DiffDurationMs` time accrues before choosing the next optimization.



  - 2025-10-14 10:20 MT: Reran the BOYO/WLLS pipeline after the reset; 74 `InterfaceSyncTiming` events now show `DiffDurationMs` averaging 164 ms (p95 483 ms, max 656 ms) with `DiffSignatureDurationMs` averaging 105 ms (p95 275 ms). The 96-row BOYO cohorts remain the tail (`DiffDurationMs` avg 470 ms / p95 655 ms; signature cost avg 218 ms) while stage work stays ~70 ms avg (p95 192 ms). `DatabaseWriteLatency` sits at 605 ms avg (p95 1.44 s), confirming the next focus is trimming diff/signature cost.



  - 2025-10-14 10:32 MT: Planning a diff/signature optimization pass—review `Get-InterfaceDiff` and helpers for repeated signature work, prototype per-host caching of existing row signatures, and update telemetry/tests to confirm lower `DiffSignatureDurationMs` before the next pipeline rerun.



  - 2025-10-14 10:39 MT: Implemented signature reuse (`Get-InterfaceSignatureFromValues`) and reran tests/pipeline. `Invoke-Pester Modules/Tests/ParserPersistenceModule.Tests.ps1` passes; the latest BOYO/WLLS run (37 `InterfaceSyncTiming` events) shows `DiffSignatureDurationMs` averaging 34.9 ms (p95 74.2 ms, max 92.4 ms) with the 96-row cohort down to 65.3 ms avg (p95 89.8 ms). `DiffDurationMs` now averages 153 ms (p95 378 ms) while `DatabaseWriteLatency` remains ~614 ms avg (p95 1.45 s), so the follow-up will target the remaining diff/comparison cost.



- 2025-10-23 13:44 MT: Reran `Tools/Invoke-WarmRunTelemetry.ps1 -VerboseParsing -RefreshSiteCaches`; warm-pass `InterfaceSiteCacheMetrics` in `Logs/IngestionMetrics/2025-10-23.json` still report `Provider=ADODB`, `HostMapSignatureMatchCount=0`, and rewrite counts 636 (BOYO) / 1,224 (WLLS) with hydrations holding at ~0.68 s / 0.56 s. `InterfaceSiteCacheReuseAttempt` logged script cache hits (BOYO 11/12, WLLS 24/25) but no shared-store hits/adoption, and shared-store telemetry continues to emit `InitNewStore` with `EntryCount=0`. Parser samples show `ParserLoadCacheHit=true` and `ParserExistingRowCount=48` while DeviceRepository marks `PreviousHostEntryPresent=false`. Action: inspect the DeviceRepository reuse path (`Get-InterfaceSiteCache` host lookup, `Set-InterfaceSiteCacheHost`) to reconcile the host lookup mismatch and determine whether the shared-store reset is discarding entries.



- 2025-10-23 14:05 MT: Warm-run helper now surfaces cache hits (`Provider=Cache`, `HostMapSignatureMatchCount=636/1224`, `HydrationDurationMs=0`) in `Logs/IngestionMetrics/2025-10-23.json` (`13:59:01 MT`). `InterfaceSiteCacheReuseState` shows the cached host dictionaries and `InterfaceSyncTiming` reports matching `SiteCacheComparisonSignatureMatchCount`. Next action: review `DatabaseWriteBreakdown.SiteCache*` fields for the same run and update docs/task board once downstream metrics reflect the cache-hit state (then close this investigation).



- 2025-10-23 15:12 MT: Completed the DatabaseWriteBreakdown follow-up. Warm-run entries in `Logs/IngestionMetrics/2025-10-23.json` (`13:58:51.984-06:00` BOYO-A05-AS-35 and `13:58:58.744-06:00` / `13:59:01.266-06:00` WLLS-A03-AS-33/WLLS-A05-AS-45) now report `SiteCacheProvider=Cache`, `SiteCacheHostMapSignatureMatchCount=636/1224`, and zero candidate-missing counts, matching `InterfaceSiteCacheMetrics`. Docs updated; cache reuse investigation closed unless new regressions surface.



- 2025-10-23 15:24 MT: Ran the preserved-session cold + warm replay (`Tools/Invoke-WarmRunTelemetry.ps1 -VerboseParsing -RefreshSiteCaches -OutputPath Logs/IngestionMetrics/WarmRunTelemetry-20251023-1524.json`). `DatabaseWriteBreakdown` shows cold-pass `InterfaceCallDurationMs` averaging 362.96 ms (p95 915.20 ms, max 1.26 s) versus warm-pass 140.11 ms (p95 170.43 ms, max 374.09 ms) with all warm hosts reporting `SiteCacheProvider=Cache`. No regressions noted; consider automating the warm-run check so future cache changes surface interface-call deltas automatically.



- 2025-10-23 17:35 MT: Fixed the warm-run telemetry helper to enumerate site snapshots via `@($sites)` (avoiding the `.ToArray()` runtime failure inside the pipeline harness) and reran `Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -RunWarmRunRegression -WarmRunRegressionOutputPath Logs/IngestionMetrics/WarmRunTelemetry-verify.json`. The regression now completes in-process with 37/37 warm hosts reporting `SiteCacheProvider=Cache`, `WarmCacheProviderHitCount=37`, and `WarmSignatureMatchMissCount=0`; cold vs. warm `InterfaceCallDurationMs` averages fell from 302.255 ms to 297.552 ms (1.56% / 4.703 ms improvement). Next action: hook `Tools/Invoke-WarmRunRegression.ps1` into CI so the preserved-session cache guardrails run automatically.



- 2025-10-23 17:49 MT: Added `Tools/Invoke-StateTraceVerification.ps1` as the scheduled verification entry point. It shells `Tools/Invoke-StateTracePipeline.ps1` with `-RunWarmRunRegression`, generates a timestamped export under `Logs/IngestionMetrics/`, and splats relative paths so the warm-run helper avoids duplicating drive roots. First verification trial (`Tools/Invoke-StateTraceVerification.ps1 -SkipTests -VerboseParsing`) failed the warm-run assertion: cold `InterfaceCallDurationMs` avg 302.120 ms vs. warm 309.457 ms, so no `WarmRunTelemetry-*.json` was emitted. Follow-up: diagnose the preserved-session regression and restore the expected warm-pass improvement before turning the new script on in CI.



- 2025-10-23 15:50 MT: Warm-run helper now summarizes cold vs. warm latency and asserts cache reuse (`Tools/Invoke-WarmRunTelemetry.ps1 -VerboseParsing -RefreshSiteCaches -AssertWarmCache -OutputPath Logs/IngestionMetrics/WarmRunTelemetry-latest.json`). Latest run logged `WarmRunComparison` with cold `InterfaceCallDurationMs` avg 416.104 ms (p95 903.201 ms, max 1.47 s) against warm 137.784 ms (p95 178.685 ms, max 0.37 s), confirming a 66.89% improvement and 37/37 cache hits. The helper now fails when providers fall back, signature matches disappear, rewrites return, or warm averages exceed cold.



- 2025-10-23 15:56 MT: Published `Tools/Invoke-WarmRunRegression.ps1` wrapper so CI/backlog automation can call the warm-run guard directly; it stamps telemetry to `Logs/IngestionMetrics/WarmRunTelemetry-<timestamp>.json` and echoes the cold vs. warm summary (`Cold avg 361.699 ms`, `Warm avg 137.636 ms`, `61.95%` improvement on the latest run). Next step is to hook this script into the scheduled verification workflow so regressions fail fast.



- 2025-10-23 16:05 MT: Documented the regression wrapper in `AGENTS.md` and the operator runbook; expected warm-run results now call out >=60% InterfaceCallDuration improvement with `SiteCacheProvider=Cache` for every host. Remaining work: add the wrapper to the scheduled verification job and capture pass/fail telemetry in CI.



- 2025-10-23 16:32 MT: `Tools/Invoke-StateTracePipeline.ps1` now accepts `-RunWarmRunRegression` (and optional `-WarmRunRegressionOutputPath`) so the preserved-session cache guard can run immediately after the baseline ingestion pass. Next action is to update the scheduled verification configuration/CI harness to set the switch and archive the emitted `WarmRunTelemetry-*.json` summary.



- 2025-10-23 16:41 MT: `Split-RawLogs` skips `Logs\WarmRunTelemetry-*` helper artifacts, eliminating the transcript file lock that blocked the first dry run. After hardening the helper with `Collect-TelemetryForPass` (polling plus timestamp-agnostic fallback) the preserved-session pipeline run now appends the expected `InterfaceSiteCacheMetrics`/`DatabaseWriteBreakdown`, but `SharedCacheSnapshot:PostColdPass` still reports `EntryCount=0` and the warm pass hydrates `BOYO-A05-AS-02`/`WLLS-A01-AS-01` from ADODB (636/1,224 rewrites), yielding `Warm InterfaceCallDurationMs avg 328.735 ms` versus cold `296.556 ms` and tripping `AssertWarmCache`. Follow-up: trace why `Get-SharedSiteInterfaceCacheStore` is empty in the pipeline-launched regression and restore cache reuse before wiring the switch into CI.



- 2025-10-23 14:25 MT: Threaded ParserPersistence cache resolve telemetry (entry type, port signature samples, cache comparison counters) through DeviceLogParser and refreshed module tests. Follow-up: rerun `Tools/Invoke-WarmRunTelemetry.ps1 -VerboseParsing -RefreshSiteCaches` to confirm warm runs surface non-zero `SiteCacheComparisonSignatureMatchCount` before closing the cache reuse investigation.



- 2025-10-23 12:07 MT: Reran the preserved-session warm telemetry helper (`Tools/Invoke-WarmRunTelemetry.ps1 -VerboseParsing -RefreshSiteCaches`). `Logs/IngestionMetrics/2025-10-23.json` still shows `SiteCacheComparisonSignatureMatchCount=0` for WLLS while `SiteCacheHostMapSignatureRewriteCount=1,224` and `SiteCacheHostMapCandidateMissingCount=275,400`, despite reuse telemetry capturing 25 hosts / 1,224 ports in cache. Action: instrument ParserPersistence's candidate-missing path (e.g., `HostSnapshotMissing` diagnostics) to identify why cached dictionaries fail the comparison and outline the required resolve fix.



- 2025-10-23 12:36 MT: ParserPersistence now emits `SiteCacheExistingRow*` telemetry and tags `SiteCacheHostMapCandidateMissingSamples` with parser context; ParserPersistence/DeviceLogParser tests pass with the new instrumentation. Follow-up: rerun `Tools/Invoke-WarmRunTelemetry.ps1 -VerboseParsing -RefreshSiteCaches` to review the parser-side fields and reconcile them with the DeviceRepository `HostSnapshotMissing` diagnostics.



- 2025-10-23 12:38 MT: Warm-run helper rerun after the parser instrumentation; WLLS `InterfaceSyncTiming` events now show `SiteCacheExistingRowCount=24` and candidate-missing samples annotated with `ParserExistingRowSource=CacheInitial` / `ParserLoadCacheHit=true` while DeviceRepository still reports `HostSnapshotMissing`. Next step: follow the DeviceRepository hydration/signature reuse path to reconcile the mismatch now that parser context confirms cached host dictionaries exist during diff.



- 2025-10-14 10:41 MT: Planning the next comparer optimization-capture baseline diff telemetry (DiffDurationMs avg 153 ms / p95 378 ms; 96-row cohorts 318 ms avg / p95 501 ms) and outline experiments to reuse existing row projections or avoid redundant PSCustomObject allocations before rebenchmarking. 



  - 2025-10-14 10:46 MT: Deferred PSCustomObject creation for unchanged ports (new helper builds rows only for inserts/updates) and reran validation. `Invoke-Pester Modules/Tests/ParserPersistenceModule.Tests.ps1` passes; BOYO/WLLS benchmark (37 `InterfaceSyncTiming` events >=10:42 MT) reports `DiffDurationMs` avg 152.6 ms (p95 408 ms, max 464 ms) with the 96-row cohort at 320.3 ms avg (p95 448.9 ms). `DiffSignatureDurationMs` remains ~36.1 ms avg (p95 77.4 ms). DatabaseWriteLatency stays elevated (avg 602 ms, p95 1.28 s), reinforcing that further comparer reductions or load batching are still required.



  - 2025-10-14 10:54 MT: Planning an incremental-loading experiment so switch/site details surface immediately while ports stream in. Drafted outline covers parser batching, a bottom-of-window loading indicator, telemetry (`PortsQueued`, `BatchesRemaining`), and validation benchmarks. Risks: Access batching must stay offline-first; UI needs a resilient subscriber path; fall back to the current all-at-once load if port batches fail. Next action is to assess feasibility and spike the parser/UI wiring.



  - 2025-10-14 11:19 MT: Logging the upcoming spike work per Documentation Primacy. Scope: emit `PortBatchReady` telemetry after each `InterfaceBulkInsertTiming` commit, enable `DeviceRepositoryModule` to serve cached batch slices, and prep the UI for a bottom loading indicator while ports stream in. Tests and benchmark rerun will follow once the wiring lands.



  - 2025-10-14 11:44 MT: Incremental-loading spike landed. ParserPersistence now stages per-chunk batches via what is now `Set-InterfacePortStreamData` (renamed from `Stage-InterfacePortStreamData`) and emits `PortBatchReady`; DeviceRepository streams cached batches; the UI shows a bottom progress indicator as ports append. Updated `DeviceRepositoryModule.Tests.ps1` and `ParserPersistenceModule.Tests.ps1` cover the streaming helpers and telemetry; `Invoke-Pester` for both suites passes. Next move: capture a BOYO/WLLS pipeline run to measure perceived load-time improvements and document UI behaviour in the operators' runbook.



  - 2025-10-14 12:20 MT: Planning the BOYO/WLLS pipeline rerun to collect incremental-loading telemetry, track UI load indicator behaviour, and log outcomes in the operators' runbook once metrics are gathered.



  - 2025-10-14 13:12 MT: Completed the BOYO/WLLS rerun after clearing `Data/IngestionHistory`; captured 224 `InterfaceSyncTiming` events (StageDuration avg 61 ms / p95 194 ms, DiffDuration avg 138 ms / p95 449 ms) and 224 `DatabaseWriteLatency` entries (avg 610 ms, p95 1.86 s, max 3.87 s). Logged 31 `PortBatchReady` events (PortsCommitted avg 43.6, EstimatedBatchCount max 4). Next action: record findings in Plan B and publish the operators' incremental-loading runbook notes.



  - 2025-10-14 13:25 MT: Published `docs/StateTrace_Operators_Runbook.md` detailing the incremental port streaming workflow (indicator text/progress states, telemetry validation, escalation guidance) so operators can verify the staggered load while the Access latency work continues.



  - 2025-10-14 13:32 MT: Planning a telemetry deep-dive to isolate the 1.8 s+ DatabaseWriteLatency tail (focus on BOYO-A05 cohort, Diff/LoadExisting hotspots) before drafting mitigation experiments.



  - 2025-10-14 13:38 MT: Telemetry review shows BOYO-A05-AS-{05,15,25,35,45,55} averaging 1.06-1.49 s latency (p95 up to 3.87 s) with `DiffDurationMs` 300-375 ms and `LoadExistingDurationMs` ~190 ms per 92-row batches; WLLS-A05 peers sit 0.97-1.06 s with similar row counts. Commit durations stay <6 ms, so next experiments should target diff/load reductions or commit SQL batching, and consider emitting multiple `PortBatchReady` beats for >90-row devices.



  - 2025-10-14 13:45 MT: Updated `docs/Core_Ideas.md` and `AGENTS.md` to add the **Approved PowerShell Verbs** pillar, reaffirming that exported commands must use approved verbs and that remediation plans must be documented when legacy verbs surface.



  - 2025-10-14 14:05 MT: Documenting the fix plan for the site cache experiment—rework `ParserPersistenceModule.Tests.ps1` mocks so cache dictionaries stay in module scope, adjust ParserPersistence wiring as needed, and rerun `Invoke-Pester Modules/Tests/ParserPersistenceModule.Tests.ps1` to confirm the caching telemetry path before the next pipeline benchmark.



  - 2025-10-14 14:42 MT: Finished the site cache regression—`ParserPersistenceModule.Tests.ps1` now exercises cache hits via TelemetryModule output in `TestDrive`; `Invoke-Pester Modules/Tests/ParserPersistenceModule.Tests.ps1` passes (13/13) and the caching plan can proceed to a pipeline rerun for telemetry validation.



  - 2025-10-14 13:55 MT: Planning an approved-verb audit across `Modules/*.psm1` exports to surface legacy names; findings and remediation backlog will be recorded after the scan.



  - 2025-10-14 14:05 MT: Approved-verb audit complete. Only `Stage-InterfacePortStreamData` (DeviceRepositoryModule) uses the unapproved `Stage` verb; queued renaming work to adopt an approved verb (proposal: `Set-` or `Initialize-`). Remaining exports already comply.



  - 2025-10-14 14:12 MT: Planning the verb remediation: rename `Stage-InterfacePortStreamData` to an approved verb (`Set-InterfacePortStreamData`), update all module/test/UI references, refresh telemetry docs, and rerun targeted Pester suites.



  - 2025-10-14 14:20 MT: Renamed the helper to `Set-InterfacePortStreamData`, updated ParserPersistence, MainWindow, and tests, and reran `Invoke-Pester Modules/Tests/DeviceRepositoryModule.Tests.ps1` plus `Invoke-Pester Modules/Tests/ParserPersistenceModule.Tests.ps1` (both passing). Docs now reference the approved verb.



  - 2025-10-14 14:30 MT: Planning the next latency experiment-design per-site caching or Access-side temp-table reuse to cut `DiffDurationMs` / `LoadExistingDurationMs` for the 92-row BOYO cohorts; outline approach and validation steps before implementation.



  - 2025-10-14 14:40 MT: Design options captured-(1) site-level existing-row cache via DeviceRepository hydrated once per run with telemetry hook `LoadCacheHit`; (2) Access temp-table diff path (`LEFT JOIN`/`EXCEPT`) to offload comparisons. Both will need extra telemetry (`DiffSqlDurationMs`) and cache-invalidation tests before coding.



  - 2025-10-14 15:05 MT: Logging the decision to pursue the site-level existing-row cache experiment first. Scope covers hydrating `Get-InterfacesForHostsBatch` once per site run, storing normalized signatures for ParserPersistence reuse, adding telemetry (`LoadCacheHit`, `LoadCacheMiss`, `CachedRowCount`), and writing cache invalidation tests before implementation proceeds.



  - 2025-10-14 15:20 MT: Planning to clear `Data/IngestionHistory` and rerun `Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs` so the new site-cache telemetry (`LoadCacheHit`, `LoadCacheMiss`, `CachedRowCount`, `CachePrimedRowCount`) is captured before pursuing additional diff-path changes.



  - 2025-10-14 16:58 MT: DeviceRepository now hydrates site caches via the active ADODB connection (`Invoke-WithAccessExclusiveRetry` guard). Latest BOYO/WLLS rerun (80 `InterfaceSyncTiming` events) shows cache hits 62 / misses 18 (BOYO 12 hits / 18 misses, WLLS 50 hits / 0 misses). LoadExisting averaged 21.3 ms overall (BOYO 56.6 ms); StageDuration averaged 101.6 ms; no exclusive-lock warnings emitted. Next focus: continue trimming BOYO cache misses and load/diff durations.



  - 2025-10-14 17:20 MT: Planning the next site cache iteration—review DeviceRepository/ParserPersistence cache wiring on BOYO hosts, identify why 18 misses persist, and draft adjustments to pre-warm or reuse caches before altering diff logic. Will log findings and proposed mitigations before implementing.



  - 2025-10-14 17:46 MT: Implemented cache refresh + empty-host handling in ParserPersistence so missing hosts trigger a one-time `Get-InterfaceSiteCache -Refresh` and zero-row entries count as cache hits. Added `LoadCacheRefreshed` telemetry field and new Pester coverage (ParserPersistence + DeviceRepository suites both passing). Next step: rerun BOYO/WLLS pipeline (history cleared) to confirm miss count drops and capture refreshed telemetry.

  - 2025-11-10 11:05 MT: Keyed site existing-row cache prototype landed—`Modules/ParserPersistenceModule.psm1` now backs `SiteExistingRowCache` with a cross-runspace `ConcurrentDictionary` plus holder type so workers honoring `-SkipSiteCacheUpdate` hydrate each site once and reuse the cached dictionaries regardless of runspace. `Modules/Tests/ParserPersistenceModule.Tests.ps1` gained a regression that simulates a second worker attaching after the first hydration to ensure no Access `SELECT` executes on the follow-on host. Follow-up: rerun `Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs` (or the preserved-session harness) so `Logs/IngestionMetrics/<date>.json` captures `SiteCacheProvider=Cache` hits and warm-run telemetry shows the raw hit ratio exceeding the 70% target before closing this card.
- 2025-11-10 11:20 MT: Pipeline rerun (`Logs/IngestionMetrics/2025-11-10.json`, latest run) now records 24/230 `InterfaceSyncTiming` events with `SiteCacheExistingRowSource=SiteExistingCache`, confirming the keyed cache feeds parser workers, but `DatabaseWriteBreakdown.SiteCacheProvider` still reports `Unknown/SharedCacheUnavailable` because ParserPersistence skips cache updates before emitting the breakdown. The warm-run harness (`Logs/IngestionMetrics/WarmRunTelemetry-20251110-run2.json`, executed with `-AssertWarmCache:$false`) continues to fail the raw-hit guardrail: `WarmCacheHitRatioPercentRaw=0%`, `ColdInterfaceCallAvgMs=722.6 ms`, `WarmInterfaceCallAvgMs=733.9 ms` (-1.57% regression). Next action: thread the new `SiteExistingCache` provider reason through `DatabaseWriteBreakdown` so hits are counted at write time, then rerun the preserved-session regression with assertions enabled.
- 2025-11-10 14:55 MT: ParserPersistence now stores a snapshot clone per site (`PrimedEntries`) and rehydrates the host dictionaries before `Update-InterfacesInDb` touches Access; DeviceLogParser’s `Resolve-DatabaseWriteBreakdownCacheProvider` also inspects the latest telemetry so `SiteCacheProvider=Cache`/`SiteCacheFetchStatus=Hit` surface whenever `SiteCacheExistingRowSource=SiteExistingCache`. A fresh `Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs` + `Tools/Invoke-WarmRunTelemetry.ps1 -ResetExtractedLogs -ColdHistorySeed Empty -WarmHistorySeed ColdOutput -RefreshSiteCaches -AssertWarmCache -PreserveSkipSiteCacheSetting` run still logs shared-cache warnings (“Shared cache snapshot contained no valid site entries… none were restored before the warm pass”), never emits a new `WarmRunTelemetry-*.json`, and the latest cold telemetry (`Logs/IngestionMetrics/2025-11-10.json`) now shows 1,160 `InterfaceSyncTiming` rows but only 74 report `SiteCacheExistingRowSource='SiteExistingCache'` (~6.4%) while `SiteExistingRowCacheState` hits hover at 7.9% (41/519). Follow-up: fix the shared cache snapshot export/restore (only one entry survives after refresh) so the preserved worker pool actually sees the primed dictionaries and the raw DatabaseWriteBreakdown hit ratio can climb toward the 70% goal.
- 2025-11-10 12:05 MT: DeviceLogParser now tags DatabaseWriteBreakdown events via `Resolve-DatabaseWriteBreakdownCacheProvider` (tests added), but the preserved-session harness still fails `-AssertWarmCache` because warm pass telemetry never records `SiteCacheExistingRowSource='SiteExistingCache'` (see `warmrun-error-20251110-115325.txt`). The follow-up run with assertions disabled exported `Logs/IngestionMetrics/WarmRunTelemetry-20251110-120255.json` (`ColdInterfaceCallAvgMs=558.716 ms`, `WarmInterfaceCallAvgMs=589.853 ms`, `WarmCacheHitRatioPercentRaw=0%`). Database events continue to log `SiteCacheProvider=Unknown` even with `SkipSiteCacheUpdate` preserved, so we need to trace why the keyed existing-row cache is not surfacing `SiteExistingCache` hits before the guard can pass.
- 2025-11-10 13:30 MT: `SiteExistingRowCacheState` telemetry now prints for every host write (194 events in `Logs/IngestionMetrics/2025-11-10.json`), but only 22 entries report `SiteExistingCache` hits—those correspond to the handful of hosts (SW1 and `WLLS-A01-AS-0{1,2}`) that we ingest multiple times. BOYO/WLLS cold runs populate the per-site dictionaries (`SiteHostEntryCount` climbs past a dozen) yet the warm pass still replays `DatabaseQuery` for every host because the keyed cache is scoped per host/runspace, not per site across the entire pipeline. `Tools/Invoke-WarmRunTelemetry.ps1 -ResetExtractedLogs -ColdHistorySeed Empty -WarmHistorySeed ColdOutput -RefreshSiteCaches -AssertWarmCache -PreserveSkipSiteCacheSetting` continues to fail the guard (`ColdInterfaceCallAvgMs=504.102 ms`, `WarmInterfaceCallAvgMs=524.172 ms`, 507 providers reported as non-cache, 645 hosts without signature matches). Next: design a mechanism to hydrate the full site dictionaries (or reuse `DeviceRepositoryModule`’s interface cache) so that the warm pass can resolve host rows without reopening Access and finally drive `WarmCacheHitRatioPercentRaw` above 70%.
- 2025-11-10 13:10 MT: ParserPersistence now treats `STATETRACE_SKIP_SITECACHE_UPDATE=1` as equivalent to the module flag and emits `SiteExistingRowCacheState` telemetry (site, host, hit/miss, host-entry counts) whenever the keyed cache is enabled. Pester coverage added for the env-only path. Next: rerun the preserved-session harness and inspect the new telemetry to see whether the keyed cache ever hydrates; if `SiteHostEntryCount` stays zero after the cold pass, propagate `Set-ParserSkipSiteCacheUpdate` into each worker runspace or share the keyed cache holder across the preserved pool so the warm pass can finally report raw hits.



## Blocked



_No cards currently in this column._ Add a note explaining the dependency or issue for each blocked card.







## Done


- **Automate warm-run regression in verification pipeline** - [Automation][Telemetry] Completed 2025-11-06. Deliverable: `Tools/Invoke-StateTraceVerification.ps1` now imports `Modules/VerificationModule.psm1::Test-WarmRunRegressionSummary` to enforce the 25% improvement / 99% hit-ratio policy (zero misses or rewrites), `Tools/Invoke-StateTraceScheduledVerification.ps1` forwards override parameters for CI, and regression coverage lives in `Modules/Tests/VerificationModule.Tests.ps1`.

- 2025-11-06 09:52 MT: Added auto shared-cache snapshot restore/export to `Tools/Invoke-StateTracePipeline.ps1`/`ParserWorker`. Cold passes now consume `Logs/SharedCacheSnapshot/SharedCacheSnapshot-latest.clixml`; WLLS fetch telemetry drops to `SiteCacheFetchDurationMs=0` with `CacheStatus=Hit`, resolving the long-standing 2.7 s hydrate tail.
  - 2025-11-06 10:05 MT: Shipped `Tools/Inspect-SharedCacheSnapshot.ps1` to summarize snapshot files (`-ShowPorts` for host-level inspection, `-All` for historical exports), making it easier to verify cache coverage before warm-run regressions. Added `-ShowSharedCacheSummary` to the pipeline harness so the inspector runs automatically after each export and writes `SharedCacheSnapshot-*-summary.json`/`SharedCacheSnapshot-latest-summary.json` for CI consumption.

- 2025-11-06 10:32 MT: Scheduled verification now archives the newest shared-cache summary JSON into `Logs/Verification/SharedCacheSummary-*.json` and surfaces the paths via PassThru metadata so CI/CD jobs can attach the artefacts alongside warm-run telemetry.

- 2025-11-06 10:45 MT: Added `Tools/Invoke-SharedCacheWarmup.ps1` to run the ingestion pipeline with shared-cache summary output and validate coverage (`Test-SharedCacheSummaryCoverage`) before preserving snapshots; operators can specify minimum site/host thresholds and required site lists when priming caches, and the helper emits `SharedCacheCoverage-latest.json` for auditing.

- **Add ingestion metrics rollup utility** - [Telemetry][Automation] Completed 2025-11-06. Deliverable: `Tools/Rollup-IngestionMetrics.ps1` parses `Logs/IngestionMetrics/*.json`, emits CSV summaries with totals/averages/p95, and ships with Pester coverage plus updated telemetry documentation.

  - 2025-11-06 12:05 MT: Scoped rollup requirements (ParseDuration, DatabaseWriteLatency, RowsWritten, SkippedDuplicate) and noted the plan in `docs/telemetry/Phase1_metrics.md`.
  - 2025-11-06 12:24 MT: Implemented the rollup script with per-site support and PassThru output, alongside `Modules/Tests/RollupIngestionMetrics.Tests.ps1`.
  - 2025-11-06 12:58 MT: Extended the utility with `-IncludeSiteCache` to summarise `SiteCacheFetchDurationMs` percentiles and hit/miss counts so WLLS cold-hydrate regressions can be tracked without manual log parsing; telemetry docs/README updated accordingly.
  - 2025-11-06 12:31 MT: Documented the command in `docs/README.md`, generated the initial CSV, and marked the telemetry tooling card complete.

- **Prune redundant log fixtures and transcripts** - [Automation][Docs] Completed 2025-11-06. Deliverable: trimmed `Logs/` to the canonical parser fixtures and telemetry exports by deleting clone/copy log duplicates, stale worker/debug transcripts, and obsolete warm-run artifacts.

  - 2025-11-06 10:20 MT: Removed `Logs/*clone*.log`, `Logs/StateTrace_*.log`, warm-run transcripts, and unused snapshots (for example `SharedCacheSnapshot-20251028-142749.clixml`, `test-snapshot.clixml`) while preserving `mock_*` and `NoArista.log` seeds used by ingestion tooling and Pester coverage.

- **Align parser/interface tests with streaming caches** - [Automation][Tests] Completed 2025-10-15. Deliverable: updated Pester expectations (`Modules/Tests/DeviceDetailsModule.Tests.ps1`, `Modules/Tests/ParserPersistenceModule.Tests.ps1`) now reflect the ObservableCollection streaming contract and clear site caches before verifying SQL command counts; `Invoke-Pester Modules/Tests` passes end-to-end.



- **Suppress duplicate-only reruns after spool reset** - [Automation][Telemetry] Completed 2025-10-06. Deliverable: DeviceLogParser duplicate guard avoids extra Access opens, Pester coverage ensures duplicates skip `ParseDuration`, and the 2025-10-06 20:35Z rerun logged only `SkippedDuplicate` telemetry across two verification passes.



- **Identity option scorecard for acknowledgements** - [Security][Docs] Completed 2025-10-04. Deliverable: weighted scorecard and recommendation in `docs/StateTrace_Acknowledgement_Identity_Options.md` plus Plan F updates in `docs/StateTrace_Consolidated_Plans.md`.



- **Unified ParserPersistence command-set caching** - [Ingestion][Automation] Completed 2025-10-02. Deliverable: `Modules/ParserPersistenceModule.psm1` command reuse + persistence failure logging, `Modules/DeviceLogParserModule.psm1` catch instrumentation, refreshed tests (`Modules/Tests/ParserPersistenceModule.Tests.ps1`, `Modules/Tests/ParserWorker.Tests.ps1`), and Plan B updates.



- **Add spool reset helper for benchmark reruns** - [Automation][Docs] Completed 2025-10-03. Deliverable: -ResetExtractedLogs switch in Tools/Invoke-StateTracePipeline.ps1 plus README/Plan B updates.



- **Profile Access bulk insert timing** - [Ingestion][Automation] Completed 2025-10-03. Deliverable: InterfaceBulkInsertTiming telemetry in Modules/ParserPersistenceModule.psm1 and 2025-10-03 Plan B snapshot.



- **Trialed parser concurrency overrides with mock slice corpus** - [Ingestion][Docs] Completed 2025-10-01. Deliverable: metrics summary in `docs/StateTrace_Consolidated_Plans.md#plan-b-performance-ingestion-scale` (baseline vs. manual overrides, single-thread duplicate guard).



- **Documented concurrency override workflow** - [Docs][Automation] Completed 2025-10-01. Deliverable: quick-reference updates in `docs/README.md` and `AGENTS.md`, session log `docs/agents/sessions/2025-10-01_session-0002.md`.



- **Verified database creation flow** - [Data][Automation] Completed 2025-10-01. Deliverable: host normalisation retest captured in `docs/StateTrace_Consolidated_Plans.md#plan-b-performance-ingestion-scale` and session log `docs/agents/sessions/2025-10-01_session-0001.md`.



- **Stress-tested autoscaling parser settings** - [Ingestion] Completed 2025-09-30. Deliverable: stress-test snapshot recorded in `StateTrace_Consolidated_Plans.md#plan-b-performance-ingestion-scale` (24-thread profile; DatabaseWriteLatency p95 ~564 ms, above 200 ms target).



- **Summarised pipeline script and autoscaling workflow** - [Docs] Completed 2025-09-30. Deliverable: execution playbook recorded in `StateTrace_Consolidated_Plans.md#plan-b-performance-ingestion-scale`.



- **Fix integer parameter binding in persistence layer** - [Automation] Completed 2025-09-30. Deliverable: parameterised ParserPersistenceModule with passing `Invoke-Pester Modules/Tests` and `Tools/Invoke-StateTracePipeline.ps1 -SkipTests`.



- **Refactored parser persistence to parameterised ADODB commands** - [Automation] Completed 2025-09-30. Deliverable: updated persistence helpers and passing tests.



- **Added orchestration script Tools/Invoke-StateTracePipeline.ps1** - [Automation] Completed 2025-09-30. Validated via `powershell -File Tools/Invoke-StateTracePipeline.ps1 -SkipParsing -VerboseParsing`.



- **Applied plan status header to each active plan** - [Docs] Completed 2025-09-30. All planning documents now include status and last reviewed fields.



  - 2025-10-14 19:30 MT: Planning the BOYO/WLLS cache-validation rerun. Will clear `Data/IngestionHistory`, execute `Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs`, and capture `LoadCacheHit`, `LoadCacheMiss`, and `LoadCacheRefreshed` telemetry for documentation once metrics are collected.



  - 2025-10-14 19:37 MT: Completed the BOYO/WLLS cache-validation run. `InterfaceSyncTiming` emitted 37 events with `LoadCacheHit=true` for every host (no misses or refreshes); `LoadExistingDurationMs` averaged 0.20 ms (p95 0.42 ms) thanks to the site cache. `DatabaseWriteLatency` averaged 1.67 s with p95 10.1 s, driven by BOYO-A05-AS-02 (11.2 s) and WLLS-A01-AS-01 (10.1 s); follow-up focuses on trimming the diff/commit tail.



  - 2025-10-14 19:40 MT: Planning diff/update tail investigation. Will break down `DiffDurationMs`, `DiffSignatureDurationMs`, and per-host outliers (BOYO-A05-AS-02, WLLS-A01-AS-01) to propose targeted optimizations (e.g., cached signatures, batched updates) before coding.



  - 2025-10-14 19:45 MT: Diff/update telemetry review complete. 96-row cohorts (12 hosts) average `DiffDurationMs` 290 ms with `BulkCommandExecuteDurationMs` 185 ms; 48-row cohort averages 136 ms diff / 85 ms command. Cache kept `LoadExistingDurationMs` <0.2 ms across the board. `DatabaseWriteLatency` remains high (avg 1.67 s, p95 10.1 s) with outliers on BOYO-A05-AS-02 (11.2 s) and WLLS-A01-AS-01 (10.1 s) despite per-chunk commits <0.2 s, suggesting the latency counter now includes extra work (likely post-commit bookkeeping) or is mis-measured. Next steps: audit `DatabaseWriteLatency` measurement in ParserPersistence/DeviceLogParser and consider additional telemetry around per-host post-commit phases.



  - 2025-10-14 19:53 MT: Planning DatabaseWriteLatency instrumentation audit. Will trace stopwatch start/stop in ParserPersistenceModule and DeviceLogParserModule, verify timing includes only commit work, and identify missing telemetry for post-commit phases before modifying code.



  - 2025-10-14 19:58 MT: Instrumentation audit findings: DatabaseWriteLatency stopwatch in DeviceLogParserModule.psm1:1165-1234 spans the entire transaction, covering Update-DeviceSummaryInDb, Update-InterfacesInDb, cache refresh, and streaming calls (Set-InterfacePortStreamData). InterfaceSyncTiming focus (ParserPersistenceModule.psm1:1254-1307) tracks diff/bulk timings only, so summary + stream work is unaccounted for in telemetry—explaining the 1.7-11 s gap. Need to add telemetry around summary writes and post-commit stream/cache hooks, then validate whether commit time or UI streaming drives the tail before optimizing.



  - 2025-10-14 20:17 MT: Planning telemetry expansion—add summary write timings (`DeviceLogParserModule.psm1:1180-1230`), measure cache refresh + streaming hooks (`ParserPersistenceModule.psm1:1812-1877`, `DeviceRepositoryModule.psm1:459-520`), and emit a combined payload (e.g., `DatabaseWriteBreakdown`) before rerunning the pipeline.



  - 2025-10-14 20:37 MT: Running telemetry validation with new breakdown instrumentation. Will clear Data/IngestionHistory, execute Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs, and capture DatabaseWriteBreakdown plus updated InterfaceSyncTiming fields for documentation.



  - 2025-10-14 20:44 MT: Telemetry run complete. `DatabaseWriteBreakdown` now emitting for 37 devices; SummaryDuration avg 34 ms (p95 55 ms), StreamDispatch avg 214 ms (p95 472 ms), SiteCacheUpdate avg 1.9 ms. DatabaseWriteLatency still avg 1.27 s (p95 7.24 s) driven by BOYO-A05-AS-02 and WLLS-A01-AS-01, where InterfaceCallDurationMs exceeds 7.2 s despite diff/commit metrics staying sub-200 ms -- indicates work queued after diff, likely recordset/stream cloning. Next: inspect DeviceRepository stream cloning and potential UI dispatch lag.



  - 2025-10-14 21:05 MT: Planning the streaming-dispatch dive before changes-review DeviceRepositoryModule (Set-InterfacePortStreamData queue + cloning), InterfaceModule dispatcher hooks, and MainWindow append workflow; capture missing telemetry ideas (dispatch queue depth, per-batch render) and enumerate risks like UI thread contention.



  - 2025-10-14 21:28 MT: Analysis complete. ParserPersistence builds `$uiRows` by cloning every port (Add-Member per property) and DeviceRepository immediately reclones the same records before enqueuing batches, so the double clone cost lands inside `InterfaceCallDurationMs` (e.g., BOYO-A05-AS-02 shows 7.2 s call vs. 94 ms StreamDispatch in Logs/IngestionMetrics/2025-10-14.json). Dispatcher loops still add items one-by-one. Next focus: add telemetry for clone/queue duration and test lighter projections or bulk ObservableCollection inserts to collapse the gap.



  - 2025-10-14 21:34 MT: Planning follow-up: instrument ParserPersistence clone time (`UiCloneDurationMs`), teach DeviceRepository to capture stream clone/queue timings and expose `Get-LastInterfacePortStreamMetrics`, reuse ParserPersistence-supplied `psobject` rows when safe, and thread the new metrics into DeviceLogParser breakdown/InterfaceSyncTiming before validating with updated Pester coverage.



  - 2025-10-14 22:06 MT: Planning telemetry validation run now that clone/stream metrics are wired through DeviceLogParser and ParserPersistence. Will clear `Data/IngestionHistory`, execute `Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs`, and review `StreamCloneDurationMs`, `UiCloneDurationMs`, and `InterfaceCallDurationMs` to identify the dominant tail contributors before proposing optimizations.



  - 2025-10-14 22:24 MT: Telemetry run executed after clearing `Data/IngestionHistory`. `InterfaceCallDurationMs` averaged 1.22 s (p95 1.68 s, max 7.21 s on BOYO-A05-AS-02 and WLLS-A01-AS-01) while `StreamDispatchDurationMs` remained low (avg 16.69 ms, p95 94.68 ms, max 532.09 ms). `DiffDurationMs` averaged 129 ms (p95 369 ms); `LoadExistingDurationMs` averaged 49.7 ms (p95 219 ms). No `InterfacePortStreamMetrics` events were emitted, so `StreamCloneDurationMs` / `StreamQueueDurationMs` are missing—next step is to trace why the new helper never persists telemetry before optimizing the clone path.



  - 2025-10-14 22:32 MT: Planning follow-up investigation into the missing `InterfacePortStreamMetrics` payload. Will review `ParserPersistenceModule.psm1` telemetry caching and `DeviceRepositoryModule.psm1::Set-InterfacePortStreamData` emission logic, confirm test coverage expectations, and outline the fix path before changing any module code.



  - 2025-10-14 22:48 MT: DeviceRepository now writes `InterfacePortStreamMetrics` via TelemetryModule and ParserPersistence refreshes `LastInterfaceSyncTelemetry` after stream metrics arrive. Unit suites (`DeviceRepositoryModule.Tests.ps1`, `ParserPersistenceModule.Tests.ps1`) pass; preparing a fresh BOYO/WLLS pipeline run to confirm events land and to capture the new clone metrics.



  - 2025-10-15 10:27 MT: Post-fix pipeline complete (`Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs`). Logged 37 `InterfacePortStreamMetrics` events with `StreamCloneDurationMs` avg 24.97 ms (p95 50.83 ms, max 60.55 ms) and `StreamStateUpdateDurationMs` avg 0.25 ms (p95 0.51 ms). `RowsCloned` remained zero (all batches reused parser-provided rows). `DatabaseWriteBreakdown.InterfaceCallDurationMs` still averages 1.25 s (p95 1.81 s, max 10.30 s), so the long tail persists beyond clone/state costs-next work item is to profile dispatcher batching and UI append paths.



  - 2025-10-15 11:06 MT: Documenting upcoming UI dispatch profiling step-will trace dispatcher batch handling in `Main/MainWindow.ps1` and `Modules/InterfaceModule.psm1`, note missing telemetry, and outline instrumentation/tests before making code changes.



  - 2025-10-15 12:08 MT: Implemented dispatcher instrumentation. `Main/MainWindow.ps1` now times per-batch UI appends and loading-indicator updates, and DeviceRepository stores/emits `InterfacePortDispatchMetrics` (batch size, dispatcher duration, append/indicator timings). Ran `Invoke-Pester Modules/Tests/DeviceRepositoryModule.Tests.ps1` and `Invoke-Pester Modules/Tests/ParserPersistenceModule.Tests.ps1` (pass). Next: capture telemetry during a UI session or pipeline replay to confirm whether dispatcher costs explain the remaining `InterfaceCallDurationMs` tail.



  - 2025-10-15 12:18 MT: Planning telemetry validation run for dispatcher metrics-clear `Data/IngestionHistory`, execute `Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs`, then analyze `InterfacePortDispatchMetrics` alongside `DatabaseWriteBreakdown.InterfaceCallDurationMs` to confirm how much of the tail sits inside the UI path.



  - 2025-10-15 12:32 MT: Dispatcher telemetry run executed after clearing `Data/IngestionHistory`. Pipeline logs (`Logs/IngestionMetrics/2025-10-15.json`) show `DatabaseWriteBreakdown.InterfaceCallDurationMs` avg 1.31 s (p95 6.96 s, max 10.92 s) but no `InterfacePortDispatchMetrics` events-expected because the headless pipeline bypasses `MainWindow` dispatcher loops. `StreamDispatchDurationMs` in `InterfaceBulkInsertTiming` remains 0 ms across all batches. Next action: exercise the UI (e.g., launch StateTrace shell and load BOYO/WLLS) to capture real dispatcher metrics or craft a harness that pumps `DeviceRepositoryModule\Get-InterfacePortBatch` on the dispatcher thread.



  - 2025-10-15 12:45 MT: Planning the UI-driven telemetry capture. Will launch the WPF client, trigger device load for BOYO/WLLS so dispatcher batching runs, and note any harness changes needed to exercise `Get-InterfacePortBatch` in tests before executing the session.



  - 2025-10-15 13:02 MT: Attempted to launch `Main/MainWindow.ps1` from the shell; modules loaded and ingestion kicked off, but the command timed out before the WPF window could surface (headless agent session). No `InterfacePortDispatchMetrics` were emitted. Need either interactive UI access or a dispatcher harness that can invoke `Dispatcher.Invoke` without a visible window.



  - 2025-10-15 13:18 MT: Drafting a dispatcher harness plan-create `Tools/Invoke-InterfaceDispatchHarness.ps1` to stage interface rows, run the batching loop against `Dispatcher.CurrentDispatcher`, and emit `InterfacePortDispatchMetrics` without the WPF UI. Will implement and validate via telemetry before revisiting full UI interaction.



  - 2025-10-15 13:27 MT: Dispatcher harness implemented and validated. `Tools/Invoke-InterfaceDispatchHarness.ps1 -Hostname BOYO-A05-AS-05` emitted four `InterfacePortDispatchMetrics` events (DispatcherDurationMs avg 4.88 ms, max 17.55 ms; AppendDurationMs avg 0.65 ms). WLLS harness run (`-Hostname WLLS-A01-AS-01`) produced two events (DispatcherDurationMs avg 3.37 ms, max 6.20 ms; AppendDurationMs avg 0.95 ms). Telemetry appended to `Logs/IngestionMetrics/2025-10-15.json` (lines ~962-968). Next steps: integrate harness usage into perf notebook and compare against `InterfaceCallDurationMs` tail.



  - 2025-10-15 13:40 MT: Planning the telemetry correlation pass-document how we will read `InterfacePortDispatchMetrics` and `DatabaseWriteBreakdown.InterfaceCallDurationMs` from `Logs/IngestionMetrics/2025-10-15.json`, calculate per-host deltas, and note any assumptions about the headless harness before running the analysis.



  - 2025-10-15 13:55 MT: Correlation complete. Parsed `Logs/IngestionMetrics/2025-10-15.json` and matched dispatcher events to `InterfaceCallDurationMs`: BOYO-A05-AS-05 spends 2.30 s in the interface call with only 19.52 ms inside Dispatcher.Invoke (delta 2.28 s); WLLS-A01-AS-01 spends 10.9 s vs. 6.74 ms of dispatcher time (delta 10.91 s). Remaining latency sits upstream (queue preparation or waits before dispatch), so dispatcher loops are no longer the prime suspect.



  - 2025-10-15 14:05 MT: Planning the queue-prep investigation-outline metrics for `Set-InterfacePortStreamData` (queue build duration, wait between bulk commit completion and first dispatch), list telemetry gaps, and document assumptions before reviewing module code.



  - 2025-10-15 14:22 MT: Queue-prep review complete. `Set-InterfacePortStreamData` telemetry shows clone work ≤25 ms, but `Initialize-InterfacePortStream` still materialises every batch without emitting `QueueBuildDurationMs` or batch counters. Comparing `InterfaceBulkInsertTiming` to `DatabaseWriteBreakdown.InterfaceCallDurationMs` leaves ~9.1 s per heavy host unexplained (WLLS-A01-AS-01: 10.9 s call vs. 1.66 s measured), pointing to missing instrumentation around queue initialisation/diff. Next action: add telemetry for queue build and restore `InterfaceSyncTiming` events before optimising.



  - 2025-10-15 14:48 MT: Implemented queue instrumentation. `Initialize-InterfacePortStream` now records `QueueBuildDurationMs`/`QueueBuildDelayMs`, emits `InterfacePortQueueMetrics`, and exposes `Get-LastInterfacePortQueueMetrics`; DeviceRepository Pester suite updated and passing. Next step is to capture the new telemetry via dispatcher harness/UI replay and verify whether queue build time explains the InterfaceCall tail; also investigate why `InterfaceSyncTiming` events are absent in the 2025-10-15 logs.



  - 2025-10-15 15:12 MT: Planning follow-up investigation: review the 2025-10-15 ingestion telemetry and ParserPersistenceModule instrumentation to understand why  `InterfaceSyncTiming` events are missing, then outline any required fixes before touching code. 



  - 2025-10-15 15:12 MT: Planning telemetry validation: after confirming the  `InterfaceSyncTiming` emission path, run the dispatcher harness (and pipeline if needed) to capture `InterfacePortQueueMetrics` alongside restored `InterfaceSyncTiming` payloads. 



  - 2025-10-15 15:46 MT: Investigation confirms `InterfaceSyncTiming` is failing inside `ParserPersistenceModule.psm1:1297-1350` when strict mode encounters unset stream metrics (`$streamCloneDurationMs`, `$streamRowsReceived`, etc.). The queue instrumentation added earlier threads those fields into the payload, but `Update-InterfacesInDb` never initializes them, so the telemetry write throws and the catch block swallows the error. Next action: initialize the stream metrics from `$bulkMetrics` (defaulting to zero) before emitting telemetry and extend coverage so the failure reproduces in tests.



  - 2025-10-15 16:30 MT: Telemetry validation complete. Reran `Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs` after hydrating interface stream metrics in ParserPersistence; 37 `InterfaceSyncTiming` events landed with `StreamCloneDurationMs` averaging 22.2 ms (p95 53.7 ms) and `StreamDispatchDurationMs` averaging 34.2 ms (p95 64.1 ms). `StreamRowsCloned` stayed 0 across all hosts, demonstrating the zero-default path survives strict mode. Next action: fold these results into the consolidated plan and resume queue instrumentation follow-up on the `InterfaceCallDurationMs` tail.



  - 2025-10-15 16:45 MT: Queue harness telemetry captured. Executed `Tools/Invoke-InterfaceDispatchHarness.ps1` via Windows PowerShell for BOYO-A05-AS-05 and WLLS-A01-AS-01 (chunk size 24). `InterfacePortQueueMetrics` reports queue build durations 18.9-26.5 ms with delays <=103 ms while pipeline `DatabaseWriteBreakdown` still shows InterfaceCallDuration averaging 2.0 s (BOYO) to 10.5 s (WLLS). Confirms queue initialization is not the tail driver; need to scrutinize pre-dispatch wait states or DatabaseWriteBreakdown aggregation for the remaining >1 s gap.



  - 2025-10-16 10:25 MT: Reused per-host metadata and direct string casts inside `DeviceRepository\Get-InterfacesForSite` so projection work no longer re-parses site, zone, vendor, or building values per row. DeviceRepository/ParserPersistence Pester suites pass; schedule a fresh cold-shell pipeline to log the resulting `InterfaceSiteCacheMetrics` snapshot/materialize deltas.



  - 2025-10-16 11:10 MT: Reworked `DeviceRepository\Get-InterfaceSiteCache` to build typed `InterfaceCacheEntry` rows and reuse cached host dictionaries, eliminating per-row `PSObject` cloning during snapshot hydration. Re-ran `Invoke-Pester Modules/Tests/DeviceRepositoryModule.Tests.ps1` and `Modules/Tests/ParserPersistenceModule.Tests.ps1`; both remain green. Cold-shell pipeline (history reset, `Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs`) now records BOYO Hydration max 0.637 s / Snapshot 0.517 s / Materialize 0.213 s / Build 0.136 s and WLLS Hydration max 0.534 s / Snapshot 0.362 s / Materialize 0.173 s / Build 0.172 s in `Logs/IngestionMetrics/2025-10-16.json`; `DatabaseWriteBreakdown.SiteCacheFetchDurationMs` tops out at 0.698 s (BOYO-A05-AS-02) with WLLS <=0.536 s. Follow-up: profiling shows BOYO fetch averages 0.607 s with Query 0.105 s, Materialize 0.183 s (PortSort 0.086 s, Template 0.045 s, Object 0.023 s) plus a 0.15-0.25 s residual in `Get-InterfacesForSite` (likely list sort) and 0.114 s host-map build; WLLS mirrors the pattern (Query 0.017 s, Materialize 0.139 s, residual 0.13-0.17 s, Build 0.142 s). Next step is to instrument the sort/build loops and prototype pooling/presorted buffers to shave the remaining ~0.2 s.



  - 2025-10-16 12:35 MT: Validated the host-map/sort telemetry with a cold-shell pipeline replay (`Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs`). `Logs/IngestionMetrics/2025-10-16.json` now shows BOYO hydration max 0.64 s (`HostMapDurationMs` 147 ms, `SortDurationMs` 45 ms) and WLLS 0.53 s (`HostMapDurationMs` 81 ms, `SortDurationMs` 59 ms), driving `DatabaseWriteBreakdown.InterfaceCallDurationMs` p95 down to 1.02 s (BOYO) / 0.44 s (WLLS). Next step: prototype host-map dictionary reuse or presorted buffers to reclaim the remaining ~150 ms snapshot cost before tuning materialize time.



  - 2025-10-16 12:52 MT: Planning to pool per-host dictionaries and cached `InterfaceCacheEntry` instances inside `DeviceRepository\Get-InterfaceSiteCache`, and to bypass the redundant `List.Sort` when the Access query already orders `Hostname, Port`. Goal: shave `HydrationHostMapDurationMs` toward sub-60 ms and collapse `HydrationSortDurationMs` without disturbing downstream signatures. Implementation queued after documentation primacy steps complete.



  - 2025-10-16 13:28 MT: Host-map pooling + cache signature reuse merged. Cold-shell replay shows BOYO `HydrationHostMapDurationMs` averaging 111 ms (`SnapshotDurationMs` 435 ms) and WLLS 58 ms (`SnapshotDurationMs` 292 ms) with `HydrationSortDurationMs` trimmed to 15-20 ms and `InterfaceCallDurationMs` p95 down to 0.92 s / 0.44 s. Follow-up: investigate the BOYO first-pass spike (signature mismatch path) to decide whether to seed cache entries pre-hydration or to document the warm-run expectation.



  - 2025-10-16 13:47 MT: Added host-map signature reuse counters ( `HostMapSignatureMatchCount`, `HostMapSignatureRewriteCount`, `HostMapEntryAllocationCount`, `HostMapEntryPoolReuseCount`) and reran the cold-shell pipeline after clearing ingestion history. First hydrations still rewrite the full cache (BOYO 0/636 matches, WLLS 0/1224), so next pass will drive a refresh hydration to confirm warm-run reuse before deciding on cache seeding vs. documenting the cold-start hit. 



  - 2025-10-15 17:05 MT: Added site-cache fetch/refresh timing to ParserPersistence telemetry and copied the fields into `DatabaseWriteBreakdown`. `Invoke-Pester Modules/Tests/ParserPersistenceModule.Tests.ps1` passes with the new assertions. Latest pipeline run (post module reload) still shows InterfaceCallDurationMs >> queue metrics (BOYO-A05-AS-05 avg 2.02 s vs. queue build 24 ms / delay 65 ms; WLLS-A01-AS-01 avg 10.5 s vs. 18.9 ms / 94 ms). Need a clean dispatcher session or cold-shell pipeline to capture the new `SiteCacheFetchDurationMs` values-the harness runner keeps totals near-zero because the site cache is already primed.



  - 2025-10-15 17:20 MT: Ran `powershell.exe -NoProfile -File Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs` from a fresh shell to record the cache timings. `Logs/IngestionMetrics/2025-10-15.json` now shows WLLS-A07-AS-07 with `SiteCacheFetchDurationMs` 14.50 s against `InterfaceCallDurationMs` 16.57 s (refresh stayed 0) while staging/stream metrics remained <100 ms. Confirms ~88% of the write latency tail comes from the site cache fetch; next step is to flush or instrument DeviceRepository cache hydration so other hosts surface their fetch costs and we can target that path.



  - 2025-10-15 17:35 MT: Instrumented DeviceRepository cache hydration (`Get-InterfaceSiteCache`) to capture `InterfaceSiteCacheMetrics` plus fetch/build breakdowns, surfaced the metadata via `SiteCacheFetchStatus`/`SiteCacheSnapshotDurationMs`/`SiteCacheBuildDurationMs`/`SiteCacheHostCount`, and refreshed DeviceRepository/ParserPersistence tests (both passing). Cold-shell pipeline rerun (logs reset) hit duplicate guard before hydration, so new fields/events did not land in `2025-10-15.json`; plan to clear `Data/IngestionHistory` on the next session to force a full cache hydrate and validate the metrics end to end.



  - 2025-10-15 18:05 MT: Cleared `Data/IngestionHistory` and reran `powershell.exe -NoProfile -File Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs` from a cold shell. `Logs/IngestionMetrics/2025-10-15.json` now records `InterfaceSiteCacheMetrics` for BOYO (Hydration 4.913 s, Snapshot 2.849 s, Build 2.063 s across 12 hosts) and WLLS (Hydration 14.781 s, Snapshot 10.783 s, Build 3.998 s across 25 hosts). `DatabaseWriteBreakdown.SiteCacheFetchDurationMs` tracks the same story (BOYO p95 4.974 s, WLLS p95 14.497 s; max 14.790 s) confirming the InterfaceCall tail is bound by initial cache hydration. Next step is to profile `DeviceRepository\Get-InterfaceSiteCache` hydrate stages so we can shave down the 14–15 s WLLS fetch.



  - 2025-10-15 18:20 MT: Planning stage-level hydration telemetry: extend `DeviceRepository\Get-InterfaceSiteCache`/`Get-InterfacesForSite` to capture query provider, attempts, wait duration, template load, and materialize timings, surface the breakdown through `InterfaceSiteCacheMetrics`/`DatabaseWriteBreakdown`, and update unit specs before rerunning the cold-shell pipeline.



- 2025-10-15 18:45 MT: Stage-level telemetry captured after rerunning `powershell.exe -NoProfile -File Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs`. `InterfaceSiteCacheMetrics` now reports BOYO `QueryDurationMs` 1.99 s (Execute 8 ms, Materialize 1.97 s, Template 95 ms, Build 1.91 s) and WLLS `QueryDurationMs` 7.10 s (Execute 46 ms, Materialize 3.05 s, Template 14 ms, Build 3.80 s) with zero exclusive retries. `DatabaseWriteBreakdown` surfaces the same fields per host (WLLS fetch slices <4 ms post-hydration). Next step: trace why ADODB recordset enumeration and host-map materialization consume 10+ s on WLLS-consider profiling the Access query pipeline or pre-sizing host maps before projecting interface objects.



- 2025-10-15 19:35 MT: Enumerations reworked (recordset `GetRows`) plus host-map property lookups finished and validated with a cold-shell pipeline (`powershell.exe -NoProfile -File Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs` after clearing `Data/IngestionHistory`). Latest `InterfaceSiteCacheMetrics` show WLLS Hydration 7.03 s (Query 0.116 s down from 7.10 s, Materialize 3.43 s, Build 1.61 s down from 3.80 s, Snapshot 5.42 s) and BOYO Hydration 0.67 s (Query 0.028 s vs. 1.99 s, Materialize 0.30 s vs. 1.97 s, Build 0.15 s vs. 1.91 s). `DatabaseWriteBreakdown.SiteCacheFetchDurationMs` now tops out at 3.7 ms (previously 14.5 s), but `InterfaceCallDurationMs` still sits at 8-9.9 s because `SnapshotDurationMs` + `MaterializeDurationMs` dominate the refreshed runs. Next actions: profile the materialize path (PortSort key generation, template lookups, PSCustomObject allocation) and explore batching snapshot projections to trim the remaining ~3.4 s materialize cost.



  - 2025-10-15 20:05 MT: Materialize instrumentation landed. Fresh cold-shell pipeline (history reset) shows BOYO `SiteCacheMaterializePortSortDurationMs` averaging 0.24 s (projection 14.6 ms, template 12.6 ms, object build 36.3 ms; total materialize 0.68 s) while WLLS averages 3.01 s port-sort, 56.8 ms projection, 110 ms template resolution, and 452 ms PSCustomObject allocation (total materialize 2.70 s with `SnapshotDurationMs` 7.28 s). PortSort dominates the remaining hydrate cost; next steps are to benchmark `InterfaceModule\Get-PortSortKey`, cache per-vendor template lookups, and pre-allocate host collections to shave the 3.0 s port-sort tail.



  - 2025-10-15 16:20 MT: Port-sort caching + pre-sized materialize collections landed. Cold-shell pipeline rerun (history reset, `Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs`) drops BOYO `SiteCacheMaterializePortSortDurationMs` average to 0.30 s (p95 0.37 s) and WLLS to 1.94 s (p95 3.01 s) while cache telemetry reports ~6.5k hits / 1.1k misses for BOYO (cache ~96) and ~29.4k hits / 1.2k misses for WLLS (cache ~144). Remaining tail sits in WLLS template/object materialize slices; next investigation targets those phases.



  - 2025-10-16 13:55 MT: Warm-run telemetry attempt (same-session `Invoke-StateTraceParsing -Synchronous` replay after manual cache refresh) still produced `SiteCacheFetchStatus`=`Refreshed` for every host with zero `SiteCacheHostMapSignatureMatchCount`. `Logs/IngestionMetrics/2025-10-16.json` shows BOYO rewrote 3,240 entries (2,700 pool reuses / 540 allocations, avg fetch 2.23 ms, max 17.21 ms) and WLLS rewrote 13,128 (11,928 reuses / 1,200 allocations, avg fetch 0.80 ms, max 1.69 ms). Need to dig into why `ParserPersistenceModule` keeps missing cached host maps between runs before documenting warm-run expectations.



  - 2025-10-16 14:25 MT: ParserPersistence now emits `SiteCacheResolveInitial*` and `SiteCacheResolveRefresh*` telemetry so DatabaseWriteBreakdown can show why each hydration fell back to refresh. Follow-up: rerun a warm run without `-Refresh` to capture the new statuses and key samples, then decide whether the cache misses come from host-key mismatches, stale cache age, or explicit clears.



  - 2025-10-16 14:50 MT: Warm-run replay (renamed `Data/IngestionHistory/*.json` between passes to reprocess the corpus without touching site caches) reports `SiteCacheResolveInitialStatus=ExactMatch` / `SiteCacheResolveRefreshStatus=NotAttempted` for every host. 35/37 fetches now surface `CacheStatus=Hit` with fetch averages 1.36 ms (BOYO, max 9.35 ms) and 0.43 ms (WLLS, max 0.45 ms), but BOYO-A05-AS-02 (734.68 ms) and WLLS-A01-AS-01 (557.40 ms) still log `CacheStatus=Hydrated` despite the resolve hit. Host-map counters remain 0 signature matches versus 38,232 rewrites/allocations. Action: inspect `DeviceRepository\Get-InterfaceSiteCache` first-host hydration flow and the signature comparison path to understand why host maps never register matches even on back-to-back runs.



  - 2025-10-16 21:12 MT: Refactored `DeviceRepository\Get-InterfaceSiteCache` to stage previous host/port dictionaries before clearing so refresh hydrations reuse typed entries and start incrementing `HydrationHostMapSignatureMatchCount`. Added unit coverage (`It "reuses cached host entries when refresh sees unchanged data"`) and DeviceRepository Pester passes. Next: rerun the warm-run pipeline (no `-Refresh`) to confirm telemetry now reports signature matches and to verify whether the first host per site still hydrates.



  - 2025-10-16 21:40 MT: Warm-run replay (`Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing`, ingestion history left intact) still shows 35/37 `DatabaseWriteBreakdown.SiteCacheFetchStatus=Hit`, yet `SiteCacheHostMapSignatureMatchCount` remains 0 while rewrites total 7,632 (BOYO) and 30,600 (WLLS) with zero pool reuse. First hosts BOYO-A05-AS-02 and WLLS-A01-AS-01 continue to hydrate (fetch 0.554 s / 0.325 s) even though `SiteCacheResolveInitialStatus=ExactMatch`. Need instrumentation around the `$hostMap.TryGetValue` + signature comparison branch to surface why every port is treated as a rewrite before deciding on cache seeding guidance.



  - 2025-10-16 22:05 MT: Plumbed the host-map reuse counters through ParserPersistence/DeviceLogParser, cleaned duplicate payload fields, and reran `Invoke-Pester` (DeviceRepository + ParserPersistence suites). Warm-run telemetry from `Logs/IngestionMetrics/2025-10-16.json` (`2025-10-16T15:48:25.376-06:00`) now carries `HostMapCandidate*` metrics, but WLLS still reports `HostMapSignatureMatchCount=0` vs. `HostMapSignatureRewriteCount=1224`, `HostMapCandidateMissingCount=1224`, and `HostMapLookupMissCount=25` with `HydrationDurationMs=937.09`. Matching `DatabaseWriteBreakdown` events expose the same zero-match story, so the instrumentation is in place while the reuse logic continues to rewrite. Follow-up: add logging around the reuse/signature branch (and signature persistence in `Set-InterfaceSiteCacheHost`) to see what signatures are being compared before attempting further cache seeding guidance.



  - 2025-10-16 22:40 MT: Instrumented mismatch sampling (`HydrationHostMapSignatureMismatchSamples`) in DeviceRepository and threaded the samples through ParserPersistence/DeviceLogParser so telemetry now captures the first five `Hostname`/`Port` pairs with previous/new signatures when a reused entry rewrites. Updated DeviceRepository/ParserPersistence tests to assert the new fields. Follow-up: run the warm-run pipeline (no `-Refresh`) to collect the new sample data for WLLS and inspect whether signatures are being truncated, re-normalized, or stripped before reuse.



- 2025-10-16 22:55 MT: Warm-run replay confirms the new `*SignatureMismatchSamples` arrays stay empty because every rewrite still increments `HostMapCandidateMissingCount` (no reuse candidates recovered). Next objective: extend instrumentation for the candidate-missing path-log which host/port keys fail reuse or capture the cached `Signature` values in `Set-InterfaceSiteCacheHost`-so we can see why the previous host map never contributes entries.



- 2025-10-21 09:22 MT: Warm-run pipeline (ingestion history renamed, no `-Refresh`) produced `InterfaceSiteCacheMetrics` with `CacheStatus=Hydrated`, `HostMapCandidateMissingCount=636 (BOYO)` / `1224 (WLLS)`, and the new `HostMapCandidateMissingSamples` all report `Reason=HostSnapshotMissing` for the first host (`BOYO-A05-AS-02`, `WLLS-A01-AS-01`). `DatabaseWriteBreakdown` shows `SiteCacheFetchStatus=Hit` but `SiteCacheHostMapSignatureMatchCount=0`, confirming cache resolve hits still fall back to full hydrations. Action: probe `Set-InterfaceSiteCacheHost` and the signature cache restore logic to see why prior host dictionaries disappear between runs and whether we need to persist the snapshot differently.



- 2025-10-21 09:58 MT: `Set-InterfaceSiteCacheHost` now writes typed `InterfaceCacheEntry` objects and `Get-InterfaceSiteCache` converts any legacy PSCustomObject cache rows via `ConvertTo-InterfaceCacheEntryObject`. Added a warm-run regression test plus refreshed ParserPersistence coverage; targeted `Invoke-Pester` runs pass. Sequential warm-run replay (history renamed, two pipeline passes in one process) still reports `HostMapSignatureMatchCount=0` / `HostMapCandidateMissingCount=636/1224`, so cached rows are not reused ahead of hydration. Next: inspect the cache resolve flow in `ParserPersistenceModule`/`DeviceRepositoryModule` to learn why host maps remain undiscovered before closing the reuse task.



- 2025-10-23 19:11 MT: Updated `Collect-TelemetryForPass` to drop pre-baseline telemetry during fallback and wired the warm-run regression wrapper to run cold passes against empty ingestion history while `WarmBackup` falls back to the cold snapshot. `Tools\Invoke-StateTraceVerification.ps1 -SkipTests -VerboseParsing` now passes with cold `InterfaceCallDurationMs` avg 938.038 ms (37 hosts; `Provider=ADODB` for 2, `Cache` for 35) versus warm 763.926 ms (37 hosts, `Provider=Cache`), yielding a 174.112 ms / 18.56% gain and 100% warm cache hit ratio. Follow-up: investigate the two cold-pass cache hits so the baseline reverts to full hydrations and the warm delta approaches the earlier ~60% target.



  - 2025-10-21 10:35 MT: Extended cache telemetry with `HydrationPreviousHostCount`, `HydrationPreviousPortCount`, and `HydrationPreviousHostSample`, then reloaded modules and ran `powershell.exe -NoProfile -File Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing`. Latest WLLS run (`Logs/IngestionMetrics/2025-10-21.json` @ `10:25:31.289-06:00`) still shows `CacheStatus=Hydrated`, `HostMapSignatureMatchCount=0`, `HostMapCandidateMissingCount=1224`, and the new counters at `PreviousHostCount=0`, `PreviousPortCount=0`, `PreviousHostSample=''`. Cached host dictionaries remain empty at hydration time despite `SiteCacheResolveInitialStatus=ExactMatch`; next action is to trace how `Set-InterfaceSiteCacheHost` repopulates `SiteInterfaceSignatureCache` after each host so we can capture where entries are cleared before reuse.



  - 2025-10-22 15:34 MT: Migrated the shared site cache to an AppDomain-level concurrent dictionary (`Initialize-SharedSiteInterfaceCacheStore`, `Get-SharedSiteInterfaceCacheStore`) and refreshed cross-runspace regression coverage. Cold-pass workers now log `InterfaceSiteCacheSharedStore` `Set` events (`EntryCount=1` for BOYO, `EntryCount=2` for WLLS), but preserved warm passes still emit `GetMiss` telemetry and hydrate via ADODB after the helper applies single-thread overrides (pool reset). Follow-up: keep parser configuration stable across passes or reseed the AppDomain store post-reset so warm runs report non-zero `HostMapSignatureMatchCount`.



- 2025-10-21 11:12 MT: Added snapshot diagnostics (`HydrationPreviousSnapshotStatus`, host-map type/count, exception text) to `DeviceRepository\Get-InterfaceSiteCache` and surfaced them through ParserPersistence telemetry. Once the warm-run pipeline is rerun these fields should confirm whether cache reuse fails because the prior host map is missing, unsupported, or throwing conversion errors. Follow-up: execute the warm run without `-Refresh` and record the new metrics in `Logs/IngestionMetrics`.



- 2025-10-21 10:56 MT: Warm-run pipeline replay (`Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing`, no `-Refresh`) after the new telemetry recorded WLLS with `SiteCacheFetchStatus=Hydrated`, `SiteCacheResolveInitialStatus=ExactMatch`, yet `SiteCachePreviousSnapshotStatus=CacheEntryMissing`, `SiteCacheHostMapSignatureMatchCount=0`, `SiteCacheHostMapSignatureRewriteCount=1224`, and `SiteCacheHostMapCandidateMissingCount=1224` (`Logs/IngestionMetrics/2025-10-21.json`, `Timestamp=10:53:11 MT`). BOYO counters remain at the earlier 09:54 capture, implying this cycle only hydrated WLLS. Action: trace the WLLS cache resolve/write path in `ParserPersistenceModule` and `DeviceRepositoryModule` to learn why the stored host map is missing despite an exact key hit, and confirm the warm-run queue is still presenting BOYO hosts.



- 2025-10-21 11:57 MT: Implemented `-PreserveModuleSession` on `Tools/Invoke-StateTracePipeline.ps1` so warm-run exercises keep module caches alive. Running two in-process passes (ingestion history reset between runs) now yields `Logs/IngestionMetrics/2025-10-21.json` entry `11:56:43.061-06:00` with `SiteCacheFetchStatus=Refreshed`, `Provider=Cache`, `SiteCacheHostMapSignatureMatchCount=1224`, `SiteCacheHostMapCandidateMissingCount=0`, and `SiteCachePreviousSnapshotStatus=Converted`, confirming host dictionaries persist when modules stay loaded. Follow-up: decide whether the harness should default to preserving modules for diagnostics or document the new switch in the operator runbook/task checklists.



- 2025-10-21 13:22 MT: Logged the `-PreserveModuleSession` guidance in the operator runbook and linked the checklist updates here. Leaving the harness default unchanged keeps cold-shell regressions visible; operators should invoke `Tools/Invoke-StateTracePipeline.ps1 -PreserveModuleSession` during cache reuse telemetry sweeps and record the resulting `HostMapSignatureMatchCount`/`HydrationDurationMs` trends. Next action: gather operator feedback during the next BOYO/WLLS validation window to decide whether the switch should graduate into the standard telemetry workflow.



- 2025-10-21 14:10 MT: Added `Tools/Invoke-WarmRunTelemetry.ps1` to script preserved-session cold/warm passes and surface `InterfaceSiteCacheMetrics` deltas without manual harness juggling. First automation run (`-ColdHistorySeed Empty -WarmHistorySeed Snapshot`) confirmed cold-pass timings (BOYO 649 ms, WLLS 664 ms) but the warm pass still skipped cache metrics (`HostMapSignatureMatchCount` stayed 0). Follow-up: adjust ingestion-history seed strategy (or detect/repair pipeline cache bypass) so automated warm passes report `Provider=Cache` before rolling the script into the standing telemetry workflow.



- 2025-10-21 14:38 MT: Captured the post-cold ingestion snapshot inside `Tools/Invoke-WarmRunTelemetry.ps1` so preserved warm passes reuse the cold-pass history. Replayed the automation (`-ColdHistorySeed Snapshot`, `-ColdHistorySeed Empty -WarmHistorySeed Snapshot`, `-ColdHistorySeed Empty -WarmHistorySeed Empty`); cold passes behaved as expected, but every warm pass still emitted zero `InterfaceSiteCacheMetrics`; `Logs/IngestionMetrics/2025-10-21.json` @ 14:30:58-14:30:59 MT only logs `SkippedDuplicate` events. Next step: instrument the preserved-session pipeline path to prove DeviceRepository emits cache-hit telemetry (or pinpoint where cached host maps are dropped) before promoting the script to operators.



- 2025-10-21 15:06 MT: DeviceRepository cache hits now emit `InterfaceSiteCacheMetrics` via a new `Publish-InterfaceSiteCacheTelemetry` helper (hydration path updated to reuse it). `Invoke-Pester Modules/Tests/DeviceRepositoryModule.Tests.ps1` passes. Warm-run automation still produces only `SkippedDuplicate` events because the preserved warm pass loads the post-cold ingestion snapshot; adjust the warm seed (or cache-bypass logic) so the second pass actually exercises `Get-InterfaceSiteCache` and surfaces the new cache-hit telemetry before rolling the script out.



- 2025-10-21 19:54 MT: `Tools/Invoke-WarmRunTelemetry.ps1 -VerboseParsing -RefreshSiteCaches` now drives cache-hit telemetry between passes (`InterfaceSiteCacheMetrics` reports `CacheStatus=Refreshed`, `Provider=Cache`, `HostMapSignatureMatchCount=1224`, and `HydrationDurationMs` ~0.23 s in `Logs/IngestionMetrics/2025-10-21.json` 19:54 MT). Updated the operator runbook/task guidance to cover the new switch plus a reminder to prune `.warmrun.*.bak` history backups after reviews; gather operator feedback during the next validation window and revise the helper if additional automation (for example, default JSON exports) would help.



- 2025-10-22 10:05 MT: Hooked a cache probe into `Tools/Invoke-WarmRunTelemetry.ps1` (calls `Get-InterfaceSiteCache -Site` after refresh) and reran `-VerboseParsing -RefreshSiteCaches`. The probe surfaced no telemetry (likely `Write-StTelemetryEvent` suppression or cache reset), and the warm pass still hydrates from ADODB (`HostMapSignatureMatchCount=0`, `PreviousSnapshotStatus=CacheEntryMissing`, BOYO Hydration 616 ms / WLLS 548 ms). Next: trace DeviceRepository cache state immediately after the scripted refresh to confirm whether cached host maps survive, and verify whether telemetry hooks fire outside the pipeline harness.



  - 2025-10-22 10:38 MT: Added `Get-SiteCacheState` logging to the helper; the post-refresh and pre-warm snapshots both reported zero cached hosts/rows (console output `Cache state entries after refresh: 0` / `before warm pass: 0`). `Logs/IngestionMetrics/WarmRunTelemetry-latest.json` still lacks `Provider=Cache` events. Next up: inspect the in-session cache directly (module invoke against `$script:SiteInterfaceSignatureCache`) and review pipeline module-import logic for unintended cache clears.



  - 2025-10-22 11:20 MT: ParserRunspaceModule now preserves the runspace pool (new `Reset-DeviceParseRunspacePool`, `Invoke-InterfaceSiteCacheWarmup`), and both the pipeline harness and warm-run helper pass `-PreserveRunspace`. Warm-run automation throttles to single-thread overrides and seeds caches through the preserved pool, yet `Logs/IngestionMetrics/WarmRunTelemetry-latest.json` still shows warm passes hydrating from ADODB (`Provider=ADODB`, `HostMapSignatureMatchCount=0`, `HydrationDurationMs` ~0.57 s). Follow-up: trace worker runspace affinity—caches may live per runspace, so preserved pools need deterministic site-to-runspace mapping before reuse registers.



- 2025-10-22 09:58 MT: Automated run (`Tools/Invoke-WarmRunTelemetry.ps1 -VerboseParsing -RefreshSiteCaches -OutputPath Logs/IngestionMetrics/WarmRunTelemetry-latest.json`) still shows warm-pass hydrations hitting ADODB (`CacheStatus=Hydrated/Hit`, `HostMapSignatureMatchCount=0`, `PreviousSnapshotStatus=CacheEntryMissing`). Need to trace why the helper’s refresh stage fails to persist host maps before the warm pass—suspect the pipeline invocation is clearing caches or the refresh step is skipping telemetry. Next action: instrument the refresh helper to verify telemetry capture and inspect `DeviceRepositoryModule` cache state immediately before the warm invocation.



  - 2025-10-22 11:45 MT: Added DeviceRepository cache summary helper and ParserRunspace runspace telemetry (InterfaceSiteCacheRunspaceState). Latest helper run confirms cold-pass workers start with empty caches (CacheExists=false), warm-pass workers see populated host maps (CacheStatus=Hydrated), yet warm telemetry still shows Provider=ADODB / HostMapSignatureMatchCount=0 (Logs/IngestionMetrics/2025-10-22.json:6257, :6814). Follow-up: investigate the candidate-missing branch that forces hydrations despite cached signatures and understand why the scripted refresh does not emit Warmup* runspace events.



  - 2025-10-22 13:40 MT: Added a shared site-interface cache store in DeviceRepositoryModule and regression coverage for cross-runspace cache hits. Warm-run automation still reports HostMapSignatureMatchCount=0 because [StateTrace.Repository.SharedSiteInterfaceCacheStore]::SiteCache remains empty after pipeline passes; next step is to confirm worker runspaces execute Set-SharedSiteInterfaceCacheEntry (inspect ParserRunspaceModule



device import flow) before re-running the preserved-session helper.



  - 2025-10-22 14:13 MT: Instrumented the shared cache helpers to emit `InterfaceSiteCacheSharedStore` telemetry. Cold-pass workers (RunspaceId `94780137-574d-4262-9fe8-41f2179546fb`) record `Set` events with entry counts 1-2, but the preserved warm pass (RunspaceId `2767d60f-a6ab-425b-8ff4-1150d6f2ade0`) only logs `GetMiss` with `EntryCount=0/1` before hydrating from ADODB (`Logs/IngestionMetrics/2025-10-22.json`). Conclusion: the static dictionary remains runspace-local. Next: move the shared store initialization outside worker creation or marshal hydrated entries back into the preserved pool so warm runs register cache hits.



  - 2025-10-22 15:58 MT: Warm-run helper now applies the single-thread overrides before the cold pass so preserved sessions reuse the same runspace config, but warm-run telemetry still reports Provider=ADODB with HostMapSignatureMatchCount=0 for BOYO/WLLS (Logs/IngestionMetrics/WarmRunTelemetry-latest.json ~15:54 MT). Next action: instrument DeviceRepositoryModule\Get-SharedSiteInterfaceCacheEntry (and parser worker usage) to learn why shared-store lookups return GetMiss ahead of warm hydrations.



- 2025-10-22 16:32 MT: Shared-store telemetry now captures AppDomain, process, thread, and store-hash identifiers. Preserved warm runs (Tools/Invoke-WarmRunTelemetry.ps1 -VerboseParsing -RefreshSiteCaches, ~16:25 MT) show cold and warm passes executing in AppDomain 1 with a stable store hash (StoreHashCode=61268168), yet each warm pass still emits GetMiss with EntryCount resetting to 0/1 before hydration (Logs/IngestionMetrics/2025-10-22.json lines ~17240-18480). No ParserRunspacePoolState events fired because the pipeline continues down the synchronous worker path. Next: trace Set-SharedSiteInterfaceCacheEntry / Get-InterfaceSiteCache removal points to learn which caller clears the shared dictionary between passes and why HostMapSignatureMatchCount remains zero.



- 2025-10-22 19:55 MT: Process-wide holder (`StateTrace.Repository.SharedSiteInterfaceCacheHolder`) now backs `Initialize-SharedSiteInterfaceCacheStore`, `Clear-SiteInterfaceCache` aligns the holder/AppDomain slot, and DeviceRepositoryModule tests cover the AppDomain reset path. Warm-run helper still hydrates via ADODB (`Provider=ADODB`, `HostMapSignatureMatchCount=0`) and shared-store telemetry logs `InitNewStore` for the warm worker (RunspaceId `e0fc37df-5a2b-4bd6-ac28-3fb9e143e5b5`, `StoreHashCode=19434694`). Next step: pinpoint why new worker runspaces miss the holder (likely per-runspace type load) and patch adoption so preserved sessions finally report `Provider=Cache` with signature matches.



  - 2025-10-23 10:19 MT: Warm-run helper now snapshots shared-cache entries after the cold pass and attempts to restore them before the warm run ( `SharedCacheSnapshot:*`, `SharedCacheRestore:PreWarmPass` in Logs/IngestionMetrics/WarmRunTelemetry-latest.json). Latest automation still captures `EntryCount=0` / `RestoredCount=0`, and warm telemetry continues to report `Provider=ADODB`, `HostMapSignatureMatchCount=0`, `HostMapSignatureRewriteCount=1224` for WLLS (Logs/IngestionMetrics/2025-10-23.json). Action: inspect `Initialize-SharedSiteInterfaceCacheStore`/`Set-SharedSiteInterfaceCacheEntry` inside worker runspaces to confirm the AppDomain store is populated or re-home the snapshot/restore logic into the preserved runspace so warm passes receive seeded host dictionaries. 



  - 2025-10-23 11:40 MT: New \\InterfaceSiteCacheReuseState\\ telemetry confirms cached host dictionaries persist (WLLS host count 25, total rows 1,224) but ParserPersistence still reports 1,224 host-map rewrites. Next: instrument the resolve path to understand why cached entries do not satisfy the candidate lookup.






















  - 2025-10-24 13:45 MT: Added SiteCache instrumentation for port-sort misses and template apply counts; tests updated. Follow-up: run the focused WLLS cold pass and preserved warm regression to capture the new telemetry fields and analyze defaulted templates/port keys.

  - 2025-10-24 13:12 MT: Focused WLLS cold pass plus preserved warm regression completed (`Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs`, `Tools/Invoke-WarmRunRegression.ps1 -VerboseParsing`). `Logs/IngestionMetrics/2025-10-24.json` at 13:06:39 MT shows `MaterializePortSortCacheHits=1080`, `Misses=144` (Gi1/0/1-27 sample) and template apply cost 59.6 ms with 8 cache misses on the `flexible` template; the regression cold pass at 13:07:27 MT trims the misses to 48 with template misses down to 4, while the warm pass stays purely cached. `WarmRunTelemetry-20251024-130713.json` confirms a 95.991 ms / 22.19% InterfaceCall improvement with 37/37 cache hits. Follow-up: investigate why the first-port cohort still misses the port-sort cache and why the initial template lookups survive typed cache adoption, then prototype a reuse or seeding fix that drives the miss counts toward zero before the next telemetry sweep.

  - 2025-10-24 13:25 MT: Audit findings: `InterfaceModule\Get-PortSortKey` relies on a script-scoped concurrent dictionary (Modules/InterfaceModule.psm1:250-263), while `InterfaceCacheEntry` persisted via `ConvertTo-InterfaceCacheEntryObject` (Modules/DeviceRepositoryModule.psm1:1205-1284) omits the `PortSort` value. `Set-InterfaceSiteCacheHost` therefore stores typed entries without a cached sort key, so every fresh process pays misses until the module-level cache is warmed (today's Gi1/0/1-27 cluster). Template hint caching behaves as expected: `TemplateHintCache` (Modules/DeviceRepositoryModule.psm1:833-851) only misses the first time a template appears; the WLLS cold pass logged eight misses out of 1,224 applications, dropping to four on the regression cold pass before the warm pass hit 100%. Action: design a fix that persists the computed port sort (or pre-warms the cache) and consider whether persisting template hint results alongside the cache entry would eliminate the residual cold-pass lookups.
- 2025-10-24 13:52 MT: Persisted `PortSort` on `InterfaceCacheEntry`, moved `Get-PortSortKey` behind the rewrite path, and added reuse fallback metrics so cache-only hydrations still report `HostMapSignatureMatchCount`. `Tools/Invoke-StateTraceVerification.ps1 -SkipTests -VerboseParsing` now completes with cold `InterfaceCallDurationMs` averaging 833.5 ms (p95 1,105.2 ms) versus warm 739.5 ms (p95 1,000.8 ms), a 94.0 ms / 11.28% gain and 37/37 cache providers = Cache. Warm `InterfaceSiteCacheMetrics` for BOYO and WLLS show `MaterializePortSortCacheMisses=0`, `MaterializePortSortDurationMs=0`, and `HostMapSignatureMatchCount` equal to the cached row counts, confirming the duplicated port-sort work is gone. Follow-up: keep chipping away at the 56 ms template-apply window and re-evaluate warm improvement targets once template/materialize tuning lands.
- 2025-11-07 11:20 MT: DeviceRepository now retains shared-cache hits with `CacheStatus='SharedOnly'`; rollup notes show separate SharedOnly counts (`Logs/IngestionMetrics_SharedOnly/2025-11-06-sharedonly.json`). Next: rerun the BOYO/WLLS warm regression to capture production telemetry with the updated status.
  - 2025-11-07 11:42 MT: Added -MetricFile, -MetricFileNameFilter, and -Latest switches to Tools/Rollup-IngestionMetrics.ps1 so we can inspect targeted telemetry (e.g., SharedOnly samples) without parsing the full Logs archive; README updated with usage examples.
- 2025-11-07 16:20 MT status: Executed `Tools\Invoke-SharedCacheWarmup.ps1 -ResetExtractedLogs` (PowerShell 7) to repopulate snapshots (BOYO=12 hosts/120 rows, WLLS=25 hosts/1,200 rows, SITE/SNAP/SW1 coverage) and then ran `Tools\Invoke-WarmRunTelemetry.ps1 -ResetExtractedLogs -ColdHistorySeed Empty -WarmHistorySeed ColdOutput -RefreshSiteCaches -OutputPath Logs/IngestionMetrics/WarmRunTelemetry-20251107-run5.json`. Warm-run assertions still fail: warm host count 993 vs. cold 1,035, `WarmCacheProviderHitCount=215` (21.65% hit ratio), `WarmCacheProviderMissCount=778`, `WarmSignatureMatchMissCount=867`, and warm InterfaceCallDuration averaged 390.07 ms (cold 383.44 ms). Only 12 entries reported `SiteCacheFetchStatus='SharedOnly'`, so the preserved-session cache is still bypassed for most hosts. Need to trace why `SiteCacheProvider=Unknown` dominates (694 entries) before the cache guard can pass again.
- 2025-11-06 12:58 MT status: `Tools/Rollup-IngestionMetrics.ps1 -IncludePerSite -IncludeSiteCache` against `Logs/IngestionMetrics/2025-10-29.json` reports WLLS `SiteCacheFetchDurationMs` averaging 328.6 ms (p95 744.8 ms, max 1,135.2 ms) with 90 `Refreshed` versus 50 `Hit` fetches; BOYO averages 257.0 ms (p95 464.2 ms, max 2,313.2 ms) with 24 hits / 36 refreshes. Confirms the first-host hydrate still carries ~0.3 s even after shared snapshot restore; next optimization should drive refresh counts toward zero so fetch latency stays under the 100 ms target.
- 2025-10-24 14:26 MT: Added template reuse short-circuiting (`HydrationMaterializeTemplateReuseCount` / `SiteCacheMaterializeTemplateReuseCount`) and threaded the counters through ParserPersistence + DeviceLogParser. Warm-run regression (`Tools/Invoke-StateTracePipeline.ps1 … -RunWarmRunRegression`) still failed cache assertions—37 warm hosts reported `Provider=Refresh` and `HostMapSignatureMatchCount=0`, so the reuse counter remains 0. Action: revisit shared host-map adoption before rerunning warm metrics; reuse instrumentation is ready once cache hits resume.

- 2025-10-24 16:11 MT status: `Tools/Invoke-StateTraceVerification.ps1 -SkipTests -VerboseParsing` continues to fail `AssertWarmCache`; warm telemetry summarized 731 host records without `SiteCacheProvider=Cache`, 733 without `HostMapSignatureMatchCount>0`, and 21,636 rewrites. Need to instrument `Restore-SharedCacheEntries` / `Get-SiteCacheState` to capture script-level cache counts before the warm pass and trace why preserved sessions still refresh every host.

- 2025-10-24 16:27 MT status: Shared-cache telemetry now logs script vs. domain counts. Verification still fails: shared store shows two entries (BOYO/WLLS) but `CacheState:PreWarmPass` only reports one site. Action: inspect construction of `$script:WarmRunSites` and the lookup in `Get-SiteCacheState` to ensure both sites are represented before the warm pass.
- 2025-10-24 18:02 MT status: Updated `Tools/Invoke-WarmRunTelemetry.ps1` to union site lists from shared-cache snapshots, restored entries, and ingestion history before the warm pass. Pre-warm telemetry now shows both BOYO and WLLS, but `AssertWarmCache` still fires-need to chase why adoption remains stuck on refresh providers.
- 2025-10-24 18:20 MT analysis: Manual run (`Tools/Invoke-WarmRunTelemetry.ps1 -VerboseParsing -ResetExtractedLogs -OutputPath Logs/IngestionMetrics/WarmRunTelemetry-debug.json`) recorded a 38.35% warm cache hit ratio (`WarmCacheProviderHitCount=777`, misses 1,249, `WarmSignatureRewriteTotal=21,636`). WLLS hosts continue to log `Provider=AccessRetry/Refresh` with zero signature matches even though the shared cache was restored. Action: trace the DeviceRepository/ParserPersistence reuse path after `Restore-SharedCacheEntries` to eliminate the forced hydrations and raise the warm hit rate.

- 2025-10-25 19:40 MT status: Attempted warm-run regression (`Tools/Invoke-WarmRunRegression.ps1 -VerboseParsing`) after extending DeviceRepository tests. Validation still fails (`Warm pass reported 37 host(s) without SiteCacheProvider=Cache.`). Latest telemetry (`Logs/IngestionMetrics/2025-10-25.json`) shows warm `DatabaseWriteBreakdown` events with `SiteCacheResolveInitialStatus=NotFound` and host counts <= 1, so restored caches remain empty. Next action: instrument cache restoration (script/shared store) immediately before the warm pass to confirm what data is loaded and why host maps collapse.
- 2025-10-25 19:53 MT status: After wiring `Restore-SharedCacheEntries` to call `ParserRunspaceModule\Invoke-InterfaceSiteCacheWarmup`, preserved-session verification still fails (`Warm pass reported 148 host(s) without SiteCacheProvider=Cache.` / `HostMapSignatureMatchCount>0`). `Logs/IngestionMetrics/2025-10-25.json` shows the warm worker issuing `InterfaceSiteCacheSharedStore` `GetMiss` with `EntryCount=0` immediately before hydration, so the shared dictionary is being reset between the cold snapshot and warm invocation. Follow-up: locate the reset path (runspace pool reinitialization vs. module reload) and ensure restored entries survive into the worker runspace ahead of the warm pass.
- 2025-10-27 10:55 MT status: Added snapshot plumbing (`SharedCacheSnapshotPath` on `Tools\Invoke-StateTracePipeline.ps1`, `.clixml` exports from `Tools\Invoke-WarmRunTelemetry.ps1`) so verification can reseed caches before the warm pass. The warm run still reports 185 hosts without cache hits, and the exported snapshot (`Logs/SharedCacheSnapshot-20251027-105235.clixml`) plus `DeviceRepositoryModule\Get-InterfaceSiteCache -Site WLLS -Refresh` both show `HostMap.Count = 0`. Action: investigate why `Set-InterfaceSiteCacheHost`/`Set-SharedSiteInterfaceCacheEntry` drop host dictionaries during persistence or document the intended reuse path if host maps are no longer stored, then adjust the warm-run restoration strategy accordingly.
- 2025-10-27 14:05 MT status: DeviceRepository now normalizes restored cache entries so snapshots retain typed host maps (`Normalize-InterfaceSiteCacheEntry`), and the warm-run helpers hydrate preserved sessions with the normalized payloads. DeviceRepository tests updated (`Invoke-Pester Modules/Tests/DeviceRepositoryModule.Tests.ps1`). Next: rerun `Tools/Invoke-StateTraceVerification.ps1 -SkipTests -VerboseParsing` without forcing refresh to confirm `SiteCacheProvider=Cache` and non-zero `HostMapSignatureMatchCount`, then record the telemetry outcome here and in the consolidated plan.
- 2025-10-27 12:58 MT status: Warm verification still fails after the forced export (`Tools/Invoke-WarmRunTelemetry.ps1 -VerboseParsing -ResetExtractedLogs -AssertWarmCache:$false -OutputPath Logs/IngestionMetrics/WarmRunTelemetry-20251027-assertfalse.json`): the summary reports `WarmCacheProviderHitCount=0`, `WarmProviderCounts[Refresh]=222`, and no signature matches. `Logs/IngestionMetrics/2025-10-27.json` shows each `InterfaceSiteCacheHostPersisted` entry limited to `EntryHostCount=1`, so later hosts fall back to `SiteCacheResolveInitialStatus=NotFound` / `SiteCacheExistingRowSource=DatabaseQuery`. Root cause: `Set-SharedSiteInterfaceCacheEntry` (`Modules/DeviceRepositoryModule.psm1:480`) replaces the shared entry with the runspace-local payload from `Set-InterfaceSiteCacheHost` (`Modules/DeviceRepositoryModule.psm1:2804` via `ParserPersistenceModule.psm1:1316/1946`), so each worker overwrites the site map with only the host it processed. Action: update the shared-cache persistence to merge host dictionaries (load existing entry, union host/port maps, retain counters) before writing, then rerun `Tools/Invoke-StateTraceVerification.ps1 -SkipTests -VerboseParsing` to confirm cache hits return and capture the telemetry in this task board.
- 2025-10-27 13:58 MT status: Merged shared-cache host maps via Merge-InterfaceSiteCacheEntry, extended DeviceRepository tests, and reran the warm-run telemetry helper (Logs/IngestionMetrics/WarmRunTelemetry-20251027-mergecheck.json). Despite the code change, the preserved warm pass still reports WarmCacheProviderHitCount=0 / WarmProviderCounts[Refresh]=259, and DatabaseWriteBreakdown events (for WLLS ~13:07 MT) retain SiteCacheProvider=Refresh with SiteCacheHostMapCandidateFromPreviousCount=0. Next action: inspect the remaining candidate selection/signature path in DeviceRepositoryModule.psm1 and ParserPersistenceModule.psm1 before attempting another verification run.
- 2025-10-27 15:10 MT: Script cache now refreshes from the shared store on every Get-InterfaceSiteCache call, so runspace-local caches pick up the full host map before reuse. Added regression coverage (Modules/Tests/DeviceRepositoryModule.Tests.ps1 "refreshes script cache from shared store when host map is incomplete") and re-ran the DeviceRepositoryModule suite. Follow-up: rerun Tools/Invoke-StateTraceVerification.ps1 -SkipTests -VerboseParsing (or Invoke-WarmRunTelemetry.ps1) to validate SiteCacheProvider=Cache / HostMapSignatureMatchCount>0 with the adoption change, then capture the telemetry on this board.
- 2025-10-27 16:05 MT status: Tools/Invoke-StateTraceVerification.ps1 -SkipTests -VerboseParsing still fails; the warm pass flagged 296 hosts without SiteCacheProvider=Cache or HostMapSignatureMatchCount>0, so no WarmRunTelemetry export was written. Logs/IngestionMetrics/2025-10-27.json confirms every DatabaseWriteBreakdown row reports SiteCacheProvider=Refresh with SiteCacheHostCount=0 and SiteCacheHostMapCandidateFromPreviousCount=0 even though InterfaceSiteCacheMetrics now shows Provider=Cache hits. Next: update ParserPersistence/DatabaseWriteBreakdown to emit Cache when the shared-store adoption path succeeds, then rerun the preserved warm regression to validate and capture the corrected telemetry.
- 2025-10-28 08:46 MT status: ParserPersistence now maps the renamed InterfaceSiteCacheMetrics fields (Provider, ResultRowCount, HostMapSignatureMatchCount, HostMapCandidateFromPreviousCount); module Pester suite passes. Warm verification still fails (Tools/Invoke-StateTraceVerification.ps1 -SkipTests -VerboseParsing): Logs/IngestionMetrics/2025-10-28.json shows every DatabaseWriteBreakdown entry with SiteCacheProvider=Refresh and SiteCacheHostMapSignatureMatchCount=0, indicating resolveCachedHost still falls back to database refresh despite InterfaceSiteCacheMetrics emitting Provider=Cache hits. Action: investigate the cache lookup/refresh path (DeviceRepositoryModule.psm1:1550-2150, ParserPersistenceModule.psm1:920-1400) to understand why the initial cache resolve misses and correct the behaviour before rerunning the preserved warm regression.

- 2025-10-28 14:26 MT: Added ParserRunspaceModule warmup instrumentation that emits a Warmup:PostJobs telemetry stage with DeviceRepositoryModule cache summaries so we can confirm restored shared-cache entries are visible inside the preserved runspace before the warm pass. Follow-up: rerun the warm-run helper and ensure both BOYO and WLLS report populated Warmup:PostJobs summaries prior to asserting cache reuse.
- 2025-10-28 17:10 MT status: Normalized shared-cache snapshot exports so host maps survive Clixml serialization. ParserWorker and Invoke-WarmRunTelemetry now ignore null snapshot entries, and DeviceRepositoryModule tests cover the sanitized export/import path (`Invoke-Pester Modules/Tests/DeviceRepositoryModule.Tests.ps1`). Plan was to rerun the preserved-session helper once the long window was available.
- 2025-10-29 12:34 MT: `Tools/Invoke-WarmRunTelemetry.ps1 -VerboseParsing -ResetExtractedLogs -ColdHistorySeed Empty -WarmHistorySeed Empty -AssertWarmCache` now passes. Warm pass shows `WarmCacheProviderHitCount=37`, `WarmSignatureMatchMissCount=0`, and InterfaceCall duration average drops from 5,616.856 ms (cold) to 3,936.009 ms (warm), a 29.93% improvement. Follow-up: archive the telemetry via `-OutputPath` and coordinate closing the cache regression card.

  - 2025-10-28 09:34 MT: Warm-run telemetry rerun (Tools\Invoke-WarmRunTelemetry.ps1 -VerboseParsing -ResetExtractedLogs -AssertWarmCache:$false) still shows WarmCacheProviderHitCount=0 / Provider=Refresh for all 37 warm hosts, and Logs/IngestionMetrics/2025-10-28.json did not record any Warmup:PostJobs InterfaceSiteCacheRunspaceState entries. Suggests Invoke-InterfaceSiteCacheWarmup skipped the preserved-pool probe; investigate why the post-job telemetry block is bypassed and ensure the preserved runspace exists before warmup.

  - 2025-10-28 10:22 MT: Warmup skip instrumentation emitted no events during Tools/Invoke-WarmRunTelemetry.ps1 (-VerboseParsing -ResetExtractedLogs -AssertWarmCache:False). Absence of Warmup:SkippedNoPool/NoSites confirms Invoke-InterfaceSiteCacheWarmup never ran; investigate Restore-SharedCacheEntries (site list may be empty) and preserved runspace initialization before asserting cache reuse.
- 2025-10-28 17:10 MT: Normalized `Get-SharedSiteInterfaceCacheSnapshotEntries` so shared-cache exports carry PSCustomObject host maps and survive Clixml serialization. ParserWorker and Invoke-WarmRunTelemetry now filter empty snapshot records before restore, and DeviceRepositoryModule tests cover the sanitized export/import path (`Invoke-Pester Modules/Tests/DeviceRepositoryModule.Tests.ps1`). Follow-up: rerun `Tools/Invoke-WarmRunTelemetry.ps1 -VerboseParsing -AssertWarmCache` (today's run processed the cold pass but hit the command timeout before warm telemetry completed) to capture DatabaseWriteBreakdown entries with `SiteCacheProvider=Cache`.
  - 2025-11-07 17:05 MT: ParserPersistence now emits a \\SiteCacheProviderReason\\ field (SharedCacheMatch, AccessRefresh, SkipSiteCacheUpdate, etc.) so we can diagnose why warm runs still report \\SiteCacheProvider=Unknown\\. Tests updated and passing; next: rerun the warm regression to collect the richer telemetry.

- 2025-11-10 15:55 MT: Shared-cache export now flattens correctly and SkipSiteCacheUpdate is back to true, so the preserved-session harness restores all seven sites without warnings. Logs/IngestionMetrics/2025-11-10.json still shows zero warm reuse (InterfaceSyncTiming hits 0/86, DatabaseWriteBreakdown.SiteCacheProvider=Cache 0/86, WarmInterfaceCallAvgMs≈457 ms vs. Cold≈451 ms), and SiteExistingRowCacheState events report CacheEnabled=true but LoadCacheMiss=true for every host. Next action: trace why the cached host entries lose their Rows payload before Update-InterfacesInDb consumes them (likely during the snapshot priming/import path) and make sure the preserved warm pass actually surfaces SiteCacheExistingRowSource='SiteExistingCache' so the guardrail JSON export can succeed.
- 2025-11-10 19:55 MT: Follow-on pipeline + preserved-session runs (`Logs/IngestionMetrics/WarmRunTelemetry-20251110-173500.json`) confirm the keyed cache survives across runspaces, but every warm host still logs `SiteCacheExistingRowSource=DatabaseQuery` and `SiteCacheProvider=Unknown`. Raw metrics remain flat (`ColdInterfaceCallAvgMs=397.50 ms`, `WarmInterfaceCallAvgMs=403.28 ms`, `WarmCacheHitRatioPercentRaw=0%`, 34/453 `SiteExistingRowCacheState` hits). Guarded runs continue to abort because ParserPersistence zeroes `$existingRows` immediately after pulling the cached host, so the warm pass still issues an Access `SELECT` before diffing and never tags the provider as `Cache`. Next: keep the cached `$existingRows` alive long enough to bypass the ADODB query (and preserve `SiteCacheExistingRowSource='SiteExistingCache'`) so DatabaseWriteBreakdown can finally record raw hits.

