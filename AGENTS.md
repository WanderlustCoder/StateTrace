# Repository Guidelines

This quick reference now mirrors the canonical **StateTrace AI Agent Operations Guide** (`docs/StateTrace_AI_Agent_Guide.md`). Read that guide first; the sections below simply highlight where to look for more detail.

## Core ideas
- **Documentation primacy**, **Approved PowerShell verbs**, **Offline-first & Access-backed**, **Telemetry & verification**, **Plan-first collaboration**, **Security & data hygiene**, **Parser/UI separation**.
- Full wording and enforcement steps live in `docs/StateTrace_AI_Agent_Guide.md` and are duplicated in `docs/Core_Ideas.md` for inline linking.

## Where things live
- `Modules/` – parser, repository, and UI modules + `Modules/Tests/` coverage.
- `Data/` – per-site `.accdb` stores plus `StateTraceSettings.json`.
- `Logs/` – ingestion + telemetry exports (see `docs/telemetry/Automation_Gates.md` for required metrics).
- `docs/` – plans, runbooks, and automation references (`docs/plans/`, `docs/CODEX_*.md`, etc.).

## Run & test commands
Use the automation matrix in `docs/CODEX_RUNBOOK.md` for the authoritative command list. Common anchors:
- `Invoke-Pester Modules/Tests` – full unit suite.
- `Import-Module .\Modules\ParserWorker.psm1; Invoke-StateTraceParsing -Synchronous` – ad-hoc parser run.
- `Tools\Invoke-StateTracePipeline.ps1 [-RunWarmRunRegression]` – cold pass (and optional preserved warm pass).
- `Tools\Invoke-WarmRunRegression.ps1 -VerboseParsing` – cached regression harness.
- `Import-Module .\Modules\ParserRunspaceModule.psm1; Get-AutoScaleConcurrencyProfile ...` – scheduler inspection.
- `Tools\Analyze-SharedCacheStoreState.ps1 -Path Logs\IngestionMetrics\<file>.json [-IncludeSiteBreakdown]` – summarizes shared cache store telemetry (SnapshotImported, GetHit/GetMiss, top sites) after pipeline runs. See `docs/CODEX_SHARED_CACHE_DIAGNOSTICS.md` for the full workflow.
- `Tools\Analyze-SiteCacheProviderReasons.ps1 -Path Logs\IngestionMetrics\<file>.json [-IncludeHostBreakdown]` – aggregates `InterfaceSyncTiming` provider reasons so you can quickly see which sites/hosts still report `AccessRefresh` (details in `docs/CODEX_SHARED_CACHE_DIAGNOSTICS.md`).

## Style, testing, and reviews
- PowerShell strict mode everywhere, 4-space indentation, PascalCase exports, camelCase locals, module-qualified calls (`DeviceRepositoryModule\Get-DbPathForSite`, etc.).
- Keep diffs intentional and small; run `Invoke-Pester Modules/Tests` before every commit.
- Never commit `.accdb` files or generated logs; log metrics and overrides in the corresponding plan/task entries.

## Overrides & online mode
- Record every concurrency override (`-ThreadCeilingOverride`, `-MaxWorkersPerSiteOverride`, etc.) in your plan/task updates and reset them to `0` after experiments.
- Limited online dev mode is allowed only when `STATETRACE_AGENT_ALLOW_NET=1` / `STATETRACE_AGENT_ALLOW_INSTALL=1` are explicitly set. Route downloads through `Tools/NetworkGuard.psm1::Invoke-AllowedDownload` and log actions under `docs/agents/sessions/` and `Logs/NetOps/<date>.json`.

For anything not covered above, jump to `docs/StateTrace_AI_Agent_Guide.md`, `docs/CODEX_RUNBOOK.md`, or the relevant plan under `docs/plans/`.
