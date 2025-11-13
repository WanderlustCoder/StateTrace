# Codex Runbook – Install, Run, Test

This runbook maps common automation tasks to the exact commands, required inputs, telemetry captures, and follow-up docs. Use it alongside `docs/CODEX_AUTONOMY_PLAN.md` and the per-plan files.

## Command matrix
| Task | Commands | Notes | Telemetry / evidence |
|------|----------|-------|----------------------|
| Full test suite | `Invoke-Pester Modules/Tests` | Run before every commit; capture summary. | Paste final Pester line into session log. |
| Cold ingestion pass | `Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs [-RunSharedCacheDiagnostics]` | Run from repo root; restores shared cache snapshots. When you supply `-SharedCacheSnapshotPath` the harness sets `STATETRACE_SHARED_CACHE_SNAPSHOT` so every parser runspace imports that snapshot before touching Access (set the env var manually if you seed the cache outside the helper). Add `-RunSharedCacheDiagnostics` to automatically call the shared-cache analyzers against the latest `Logs/IngestionMetrics/*.json`. Ensure `Data/StateTraceSettings.json` has `\"SkipSiteCacheUpdate\": false` (or call the warm-run helpers that temporarily disable it) before collecting Plan B telemetry. | Attach `Logs/IngestionMetrics/<date>.json` snippet (ParseDuration, DatabaseWriteLatency, InterfaceSiteCacheMetrics). |
| Cold + warm regression | `Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -RunWarmRunRegression` *or* `Tools\Invoke-WarmRunRegression.ps1 -VerboseParsing` | Harness preserves parser runspaces, exports the shared snapshot after the cold pass, and wires up `STATETRACE_SHARED_CACHE_SNAPSHOT` so the warm pass reuses the exact cache contents. Include overrides when experimenting; reset afterwards. | WarmRunTelemetry JSON + improvement summary recorded in plan/task board. |
| Autoscale profile inspection | `Import-Module .\Modules\ParserRunspaceModule.psm1; Get-AutoScaleConcurrencyProfile -DeviceFiles <paths>` | Use when tuning overrides; log resolved ceilings. | Screenshot or text snippet of resolved profile + overrides. |
| Metrics rollup | `Tools\Rollup-IngestionMetrics.ps1 ...` or `Tools\Invoke-DailyMetricRollup.ps1 -Days 1 -IncludePerSite -IncludeSiteCache` | Run when telemetry changes; the daily wrapper filters the latest files and emits `IngestionMetricsSummary-<timestamp>.csv`. | Mention output path + date in plan/task update (and check summary into docs/Logs when requested). |
| Shared cache warmup | `Tools\Invoke-SharedCacheWarmup.ps1 -ShowSharedCacheSummary -RequiredSites BOYO,WLLS` | Prepares snapshots before verification. | Attach `SharedCacheSnapshot-*-summary.json` stats. |
| Shared cache diagnostics | `Tools\Analyze-SharedCacheStoreState.ps1 -Path Logs\IngestionMetrics\<file>.json [-IncludeSiteBreakdown]` | Summarizes `InterfaceSiteCacheSharedStore*` telemetry (SnapshotImported hits, GetMiss/GetHit ratios, top sites). Run after any cold/warm harness to confirm snapshots were imported and to spot remaining Access hydrations. See `docs/CODEX_SHARED_CACHE_DIAGNOSTICS.md` for the full workflow. | Paste summary table (or note SnapshotImported=0) in plan/task update; link the analyzed log. |
| Provider reason diagnostics | `Tools\Analyze-SiteCacheProviderReasons.ps1 -Path Logs\IngestionMetrics\<file>.json [-IncludeHostBreakdown]` | Aggregates `InterfaceSyncTiming.SiteCacheProvider*` fields so you can see AccessRefresh vs. SharedCacheMatch per site; optional host breakdown surfaces worst offenders + fetch durations (details in `docs/CODEX_SHARED_CACHE_DIAGNOSTICS.md`). | Reference counts (per site) in plan/task updates; attach host table when AccessRefresh persists. |
| Analyze diff hotspots | `Tools\Analyze-WarmRunDiffHotspots.ps1 -TelemetryPath Logs\IngestionMetrics\<warm run>.json -Top 20` | Useful for Plan B + C investigations. | Link exported table or paste top offenders. |
| Incremental loading verification | `Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs` then follow `docs/StateTrace_Operators_Runbook.md` (Interfaces view + telemetry capture). | Confirms streaming UI stays responsive and that `PortBatchReady`/`InterfaceSyncTiming` metrics hit the documented targets. | Record `Logs/IngestionMetrics/<date>.json` path, PortBatchReady count, InterfaceSyncTiming durations, and UI observations in session log/plan update. |
| UI smoke test | Follow `docs/UI_Smoke_Checklist.md` (launch `Main/MainWindow.ps1`, exercise each tab, optional span harness). | Note any view regressions plus span snapshot output. | Checklist completion logged in session notes + plan/task entry. |
| SPAN view smoke test | `pwsh -STA -File Tools\Invoke-SpanViewSmokeTest.ps1 -Hostname <host> -PassThru` | Loads the SPAN view off-screen, triggers `Get-SpanInfo`, and emits a snapshot so regressions surface without the full UI. | Capture the returned object (row count, VLAN samples) and reference the log (`Logs/Debug/SpanDiag.log`) in your plan/session notes. |
| Session wrap | `docs/CODEX_SESSION_CHECKLIST.md` + CLI summary | Use at the end of every run to ensure plan/backlog/task board/session log updates are complete. | CLI summary references plan/backlog IDs + telemetry artifacts. |

## Validation checklist
1. **Commands executed** – capture the exact command (with parameters) per task.
2. **Telemetry saved** – drop JSON/CSV outputs under `Logs/` (already ignored) and reference them in docs.
3. **Docs updated** – edit the relevant plan file, task board entry, and backlog row.
4. **Session logged** – add/update `docs/agents/sessions/<date>_session-XXXX.md`.

## Environment setup
- PowerShell 5.x (already available in the repo’s target environment).
- Optional online dev mode requires `STATETRACE_AGENT_ALLOW_NET=1` and `STATETRACE_AGENT_ALLOW_INSTALL=1`, plus logging via `Tools/NetworkGuard.psm1::Invoke-AllowedDownload`.

## Troubleshooting
- If `Invoke-StateTracePipeline.ps1` fails due to history corruption, clear `Data/IngestionHistory/*.json` (back them up first) and rerun.
- For Access contention, rerun with reduced concurrency overrides (`-ThreadCeilingOverride 1 -MaxWorkersPerSiteOverride 1`) and log the difference in Plan B.

Keep this runbook short and scriptable—extend the table rather than writing prose when you add new tasks.
