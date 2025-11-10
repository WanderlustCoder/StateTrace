# Warm Run Optimization Plan - 2025-11-07

## Current Baseline
- Latest preserved-session run (`Logs/\IngestionMetrics/\WarmRunTelemetry-20251107-runB.json`) shows cold avg 883.4 ms vs. warm 649.2 ms (26.5% / 234.2 ms gain).
- Weighted cache hits improved to 93.04% after host-count weighting, but raw DatabaseWriteBreakdown hit ratio is still 32.18% (84 hits / 177 misses).
- WLLS hosts dominate the miss pool: 50 hits vs. 72 refreshes plus 3 unknowns; Access diff/load times consume >400 ms per host based on `DatabaseWriteBreakdown` entries.

## Objectives
1. Lift warm-run InterfaceCall improvement to ≥60% (target warm avg ≤350 ms).
2. Maintain weighted cache hit ratio ≥90% and push raw DB-level hit ratio above 70% by ensuring every host writes its cache during the cold pass.

## Proposed Actions
1. **Expand Shared Snapshot Coverage**
   - Merge mock corpora using `Tools/Expand-MockLogCorpus.ps1 -SourceMetricsPath Logs/2025-11-06.json -Force` to synthesize logs for missing WLLS hosts, then rerun `Tools/Invoke-SharedCacheWarmup.ps1`.
   - Import latest production `SharedCacheSnapshot-*.clixml` into `Logs/SharedCacheSnapshot/` when available; accompany with `Inspect-SharedCacheSnapshot.ps1 -ListHosts` to verify ≥60 WLLS entries.

2. **Reduce Access Diff/Load Cost**
   - Instrument `ParserPersistenceModule` diff path with `DiffHotPathDurationMs` and `LoadExistingRowSetCount` to isolate the 400+ ms tail (use host weighting to prioritize WLLS-A05 cohort).
   - Prototype a keyed existing-row cache: hydrate per-site once per warm pass, keyed by `(Site, Hostname)`, so repeated warm hosts don't requery Access even when site caches are skipped.

3. **Pipeline Guardrails**
   - Update CI harness to treat `WarmCacheHitRatioPercentRaw < 70` or `WarmInterfaceCallAvgMs >= Cold` as failures, ensuring snapshot regressions surface immediately.

## Open Questions
- Do we maintain `SkipSiteCacheUpdate=true` in production, or can we flip it during cold passes to keep site caches fresh without touching Access writes?
- Is there a smaller BOYO/WLLS subset we can prioritize for warm-run validation to reduce run time while hitting the 60% target?

## 2025-11-08 Updates
- ParserPersistence now records `DiffComparisonDurationMs` (total time spent comparing incoming vs. existing rows) and `LoadExistingRowSetCount` (rows pulled from Access/site cache) inside each `InterfaceSyncTiming` event. `Tools/DeviceLogParser` forwards both fields into `DatabaseWriteBreakdown`, so warm-run telemetry can rank the heaviest diff/hydration hosts before we prototype the keyed existing-row cache.

## 2025-11-09 Run Summary
- `Tools/Invoke-WarmRunTelemetry.ps1 -ResetExtractedLogs -ColdHistorySeed Empty -WarmHistorySeed ColdOutput -RefreshSiteCaches -AssertWarmCache:$false -OutputPath Logs/IngestionMetrics/WarmRunTelemetry-20251108-run3.json`
  - Cold vs. warm averages: `ColdInterfaceCallAvgMs=850.19 ms`, `WarmInterfaceCallAvgMs=851.64 ms` (`-0.17%` improvement, effectively flat).
  - Weighted cache hits stay high (`WarmCacheHitRatioPercent=90.54%`) because the shared snapshot serves every host, but `WarmCacheHitRatioPercentRaw=0%` since `SkipSiteCacheUpdate` prevents per-host DatabaseWriteBreakdown hits.
  - `DiffComparisonDurationMs` and `LoadExistingRowSetCount` now populate the per-host records; next action is to mine those values for the WLLS tail and prototype the keyed existing-row cache (or temporarily re-enable site-cache updates during the cold pass) so the raw DB hit ratio becomes meaningful again.
