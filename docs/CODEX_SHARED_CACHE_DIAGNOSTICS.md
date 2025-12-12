# Codex Playbook – Shared Cache Diagnostics

Use this checklist any time you run the cold/warm harnesses or investigate Plan B cache regressions. It stitches together the snapshot plumbing and the analyzer scripts so you can prove caches were hydrated (or quickly spot why they were not).

## 1. Seed the shared cache snapshot
1. Prefer the automation built into the harnesses:
   - `Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -SharedCacheSnapshotPath Logs\SharedCacheSnapshot-latest.clixml`
   - `Tools\Invoke-WarmRunTelemetry.ps1 -VerboseParsing -SharedCacheSnapshotPath Logs\SharedCacheSnapshot-latest.clixml -IncludeTests:$false`
   These commands automatically set `STATETRACE_SHARED_CACHE_SNAPSHOT` so every parser runspace imports the snapshot before touching Access.
2. When running ad-hoc scripts outside the harness, manually point the env var at the snapshot before launching the parser worker:
   ```powershell
   $env:STATETRACE_SHARED_CACHE_SNAPSHOT = 'Logs\SharedCacheSnapshot-latest.clixml'
   ```
   Clear or reset the variable afterwards to avoid contaminating other sessions.

## 2. Analyze shared-store telemetry
Run the analyzer against the newest `Logs\IngestionMetrics\<timestamp>.json` produced by the cold/warm pass.

```powershell
pwsh Tools\Analyze-SharedCacheStoreState.ps1 `
    -Path Logs\IngestionMetrics\2025-11-12.json `
    -IncludeSiteBreakdown
```

> Shortcut: append `-RunSharedCacheDiagnostics [-SharedCacheDiagnosticsTopHosts <N>]` to `Tools\Invoke-StateTracePipeline.ps1` and the harness will automatically execute both analyzers against the freshest log file once the cold (and optional warm) pass finishes.

Key signals:
- `SnapshotImported` > 0 confirms the snapshot was restored into the shared store before parsing. `0` means the env var/snapshot was missing.
- `InitDelegatedStore` (newer telemetry) tracks runspace store initialization/binding; older logs may instead report `InitNewStore`/`InitReuseStore`.
- Compare `GetHit` vs. `GetMiss` for overall reuse, then review the "Top sites" table to see which sites still drive Access hydrations.

Include the summary table (or at least SnapshotImported/GetHit/GetMiss counts) in your plan/task update whenever you run the harness.

## 3. Analyze provider reasons per site/host
After the cold/warm run, aggregate the `InterfaceSyncTiming.SiteCacheProvider*` fields:

```powershell
pwsh Tools\Analyze-SiteCacheProviderReasons.ps1 `
    -Path Logs\IngestionMetrics\2025-11-12.json `
    -IncludeHostBreakdown `
    -TopHosts 10
```

This command reports, per site:
- `AccessRefresh` vs. `AccessCacheHit` vs. `SharedCacheMatch`
- `SkipSiteCacheUpdate` counts (helpful when overrides or settings suppressed cache writes)

When `-IncludeHostBreakdown` is supplied, the tool also lists the hosts with the highest `AccessRefresh` counts plus their average fetch durations, which makes it clear where Access hydrations still dominate.

Log the per-site counts in your plan/task update and paste the host table when AccessRefresh persists.

## 4. Triage & follow-up
- If `SnapshotImported=0`, confirm `STATETRACE_SHARED_CACHE_SNAPSHOT` was set (or that the harness received `-SharedCacheSnapshotPath`) and rerun the cold pass. DeviceRepository now hydrates any empty shared store (`Ensure-SharedSiteInterfaceCacheSnapshotImported` + hoisted `StateTrace.Models.*` types), so a zero count usually means the env var/path was missing. Quick check:
  ```powershell
  pwsh -NoLogo -Command "$env:STATETRACE_SHARED_CACHE_SNAPSHOT='Logs/SharedCacheSnapshot-<timestamp>.clixml'; Import-Module .\Modules\DeviceRepositoryModule.psm1 -Force; (DeviceRepositoryModule\Get-SharedSiteInterfaceCacheStore).Count"
  ```
  The count should match the snapshot entry total (7 for the current `Logs/SharedCacheSnapshot-20251110-192915.clixml`).
- When you need to understand *why* the shared store keeps clearing, search the same ingestion metrics for `InterfaceSiteCacheClearInvocation`. Each telemetry record now includes the reason (if supplied), caller function/script, and call stack depth, so you can correlate `ClearRequested` bursts with the module or helper forcing the reset.
- If SnapshotImported succeeded but `GetMiss` still dwarfs `GetHit`, use the host breakdown to inspect those specific Access hydrations (e.g., inspect `Data/IngestionHistory/<site>.json` or rerun with verbose parser logging).
- Record all findings in Plan B (`docs/plans/PlanB_Performance.md`) and the task board so future runs can compare against these baselines.

## Quick reference
| Task | Command | Notes |
|------|---------|-------|
| Snapshot seeding (automatic) | `Tools\Invoke-StateTracePipeline.ps1 -SharedCacheSnapshotPath ...` | Harness manages `STATETRACE_SHARED_CACHE_SNAPSHOT` for you. |
| Shared store summary | `Tools\Analyze-SharedCacheStoreState.ps1 -Path Logs\IngestionMetrics\<file>.json -IncludeSiteBreakdown` | Confirm SnapshotImported hit and review GetHit/GetMiss + top sites. |
| Provider reason summary | `Tools\Analyze-SiteCacheProviderReasons.ps1 -Path Logs\IngestionMetrics\<file>.json -IncludeHostBreakdown -TopHosts 10` | Quantify AccessRefresh vs. SharedCacheMatch and list worst hosts. |
| Manual snapshot sanity check | `pwsh -NoLogo -Command "$env:STATETRACE_SHARED_CACHE_SNAPSHOT='Logs/SharedCacheSnapshot-<timestamp>.clixml'; Import-Module .\Modules\DeviceRepositoryModule.psm1 -Force; (DeviceRepositoryModule\Get-SharedSiteInterfaceCacheStore).Count"` | Confirms DeviceRepository hydrates the expected number of entries before running the harness. |

Keep this playbook alongside `docs/CODEX_RUNBOOK.md` whenever you run the cold/warm harnesses so cache regressions are diagnosed with consistent evidence.
