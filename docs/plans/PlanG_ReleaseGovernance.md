# Plan G – Release & Governance

## Objective
Maintain a predictable release cadence, ensure warm-run verification passes before packaging, and document rollout decisions (approvals, risk assessments, governance).

## Current status (2025-11)
- Release process documented in `docs/Release.md`; risk register in `docs/RiskRegister.md`.
- Warm-run verification integrated with `Tools/Invoke-StateTracePipeline.ps1 -RunWarmRunRegression` and `Tools/Invoke-StateTraceVerification.ps1`.
- Quarterly roadmap (`docs/StateTrace_Quarterly_Roadmap.md`) lists upcoming governance checkpoints.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-G-001 | Update release checklist with shared cache snapshot policy | Release | Ready | Add `Logs/SharedCacheSnapshot/*` expectations to `docs/Release.md`. |
| ST-G-002 | Link roadmap milestones to task board IDs | PMO | Backlog | Keep `docs/StateTrace_TaskBoard.md` and roadmap in sync for Codex automation. |

## Recent timeline (migrated highlights)
| Date (MT) | Summary | Evidence / Metrics | Source |
|-----------|---------|--------------------|--------|
| 2025-10-23 15:56 | Introduced `Tools/Invoke-WarmRunRegression.ps1` plus the `-RunWarmRunRegression` switch in `Tools/Invoke-StateTracePipeline.ps1`, making cold+warm deltas part of the standard release harness. | Console summary reported cold avg 361.7 ms vs warm 137.6 ms (61.95% improvement); helper exports `WarmRunTelemetry-*.json`. | docs/StateTrace_Consolidated_Plans.md:2025-10-23 entries |
| 2025-10-23 17:49 | Created `Tools/Invoke-StateTraceVerification.ps1` to wrap pipeline + warm regression with assertions, producing timestamped telemetry for governance reviews. | Script splats parameters, archives telemetry, and becomes the entry point for scheduled verification jobs. | docs/StateTrace_Consolidated_Plans.md:2025-10-23 17:49 entry |
| 2025-11-06 09:15 | Verification harness now imports `Test-WarmRunRegressionSummary`, enforcing cache-hit and improvement thresholds (≥25% improvement, ≥99% cache hits) for CI and scheduled releases. | `Tools/Invoke-StateTraceVerification.ps1` + `Tools/Invoke-StateTraceScheduledVerification.ps1` updated; coverage in `Modules/Tests/VerificationModule.Tests.ps1`. | docs/StateTrace_Consolidated_Plans.md:36 |
| 2025-11-06 09:52 | `Tools/Invoke-StateTracePipeline.ps1` automatically restores/exports shared cache snapshots so release runs ship with repeatable cache state (`SharedCacheSnapshot-latest*.clixml`). | Cold pass after change shows WLLS hosts hydrating from cache (`SiteCacheFetchDurationMs=0`). | docs/StateTrace_Consolidated_Plans.md:37 |

## Automation hooks
- `Tools/Invoke-StateTracePipeline.ps1 -RunWarmRunRegression -ShowSharedCacheSummary` before any candidate build.
- `Tools/Invoke-StateTraceVerification.ps1 -SharedCacheMinimumSiteCount 2 -SharedCacheRequiredSites BOYO,WLLS` to enforce governance gates.

## Telemetry gates
- Warm vs. cold regression improvement ≥60% (shared with Plan B); capture details in release notes.
- Shared cache snapshot summary (site count, host count, row count) exported alongside every release package.

## References & history
- Release doc: `docs/Release.md`.
- Governance + roadmap: `docs/StateTrace_Quarterly_Roadmap.md`, `docs/RiskRegister.md`.
- Historical decisions: `docs/StateTrace_Consolidated_Plans.md` (Plan G sections).
