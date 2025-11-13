# Plan G - Release & Governance

## Objective
Maintain a predictable release cadence, ensure warm-run verification passes before packaging, and document rollout decisions (approvals, risk assessments, governance) so every build is auditable.

## Current status (2025-11)
- Release guide (`docs/Release.md`) plus the Codex documentation controls (`docs/CODEX_DOC_SYNC_PLAYBOOK.md`, `docs/CODEX_PLAN_AUTOMATION_MATRIX.md`, `docs/CODEX_SESSION_CHECKLIST.md`) describe the governance loop, but the release checklist still lacks explicit shared-cache snapshot and verification evidence requirements.
- Governance artifacts live in `docs/RiskRegister.md`, `docs/StateTrace_Quarterly_Roadmap.md`, and `docs/StateTrace_TaskBoard.md`; Plan G must keep those aligned by mirroring TaskBoard IDs inside the roadmap and referencing the same IDs when publishing release notes.
- Warm-run verification is part of the standard harness (`Tools/Invoke-StateTracePipeline.ps1 -RunWarmRunRegression`, `Tools/Invoke-StateTraceVerification.ps1`, `Tools/Invoke-StateTraceScheduledVerification.ps1`), yet we do not consistently archive the resulting telemetry (cold vs warm JSON, verification summaries, shared-cache summaries) in a release evidence bundle.
- Shared cache analyzers (`Tools/Analyze-SharedCacheStoreState.ps1`, `Tools/Analyze-SiteCacheProviderReasons.ps1`) and rollups feed governance calls, but Plan G still needs a standing task that captures their output for every release candidate.
- Plan E’s telemetry bundles and Plan B’s analyzer outputs are prerequisites for sign-off; Plan G must enforce that every candidate build references `Logs/TelemetryBundles/<date>/` (created via `Tools\Publish-TelemetryBundle.ps1`) before approvals.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-G-001 | Update release checklist with shared cache snapshot policy | Release | Ready | Add `Logs/SharedCacheSnapshot/*` expectations and a verification line item to `docs/Release.md`, referencing the exported `SharedCacheSnapshot-*-summary.json`. |
| ST-G-002 | Link roadmap milestones to task board IDs | PMO | Backlog | Ensure each milestone in `docs/StateTrace_Quarterly_Roadmap.md` points to a TaskBoard ID and that `docs/StateTrace_TaskBoard.md` lists the same governance checkpoints. |
| ST-G-003 | Schedule verification runs | Release / Ops | Ready | Configure `Tools/Invoke-StateTraceScheduledVerification.ps1` (or CI) to emit `Logs/Verification/VerificationSummary-<timestamp>.json` nightly; attach summaries to this plan and the TaskBoard. |
| ST-G-004 | Governance evidence bundle | Release | Backlog | Define `Logs/ReleaseEvidence/<version>/` containing cold vs warm telemetry, verification summaries, shared-cache summaries, doc-sync checklist outputs, and risk reviews per `docs/CODEX_DOC_SYNC_PLAYBOOK.md`. |
| ST-G-005 | Release readiness dashboard | PMO | Backlog | Combine metrics from rollups + verification runs into a readiness view (warm-run improvement, cache-hit ratio, telemetry gate status) and link it from this plan. |
| ST-G-006 | Doc-sync enforcement hook | Docs / Release | Backlog | Automate `docs/CODEX_DOC_SYNC_PLAYBOOK.md` checklist (plan update + backlog + task board + session log) so release candidates fail when doc sync artifacts are missing. |
| ST-G-007 | Telemetry bundle integration | Release + Telemetry | Backlog | Consume Plan E ST-E-007 bundles inside the release checklist; verify each bundle contains rollup CSVs, shared-cache analyzers, warm-run summaries, and risk deltas before sign-off. |
| ST-G-008 | Risk register linkage | PMO | Backlog | Ensure every release candidate references the relevant `docs/RiskRegister.md` entries (e.g., Plan B performance regressions) and that the release notes list mitigations/owners before approvals. |

## Recent timeline (migrated highlights)
| Date (MT) | Summary | Evidence / Metrics | Source |
|-----------|---------|--------------------|--------|
| 2025-11-12 13:45 | Authored the Codex Documentation Sync Playbook so every handoff follows the same plan/task board/backlog update procedure. | `docs/CODEX_DOC_SYNC_PLAYBOOK.md` plus README/Instruction Stack/Operations Guide references; logged as task ST-G-004. | docs/CODEX_DOC_SYNC_PLAYBOOK.md |
| 2025-11-12 13:10 | Published the Codex Plan Automation Matrix to map each plan to its scripts, telemetry, and documentation hooks so governance checks can be executed autonomously. | `docs/CODEX_PLAN_AUTOMATION_MATRIX.md` plus README/operations guide cross-links; task board card ST-G-003 documents the update. | docs/CODEX_PLAN_AUTOMATION_MATRIX.md, docs/README.md |
| 2025-10-23 15:56 | Introduced `Tools/Invoke-WarmRunRegression.ps1` plus the `-RunWarmRunRegression` switch in `Tools/Invoke-StateTracePipeline.ps1`, making cold+warm deltas part of the standard release harness. | Console summary reported cold avg 361.7 ms vs warm 137.6 ms (61.95% improvement); helper exports `WarmRunTelemetry-*.json`. | docs/StateTrace_Consolidated_Plans.md (2025-10-23 entries) |
| 2025-10-23 17:49 | Created `Tools/Invoke-StateTraceVerification.ps1` to wrap pipeline + warm regression with assertions, producing timestamped telemetry for governance reviews. | Script splats parameters, archives telemetry, and becomes the entry point for scheduled verification jobs. | docs/StateTrace_Consolidated_Plans.md (2025-10-23 17:49 entry) |
| 2025-11-06 09:15 | Verification harness now imports `Test-WarmRunRegressionSummary`, enforcing cache-hit and improvement thresholds (>=25% improvement, >=99% cache hits) for CI and scheduled releases. | `Tools/Invoke-StateTraceVerification.ps1` + `Tools/Invoke-StateTraceScheduledVerification.ps1` updated; coverage in `Modules/Tests/VerificationModule.Tests.ps1`. | docs/StateTrace_Consolidated_Plans.md (2025-11-06 entry) |
| 2025-11-06 09:52 | `Tools/Invoke-StateTracePipeline.ps1` automatically restores/exports shared cache snapshots so release runs ship with repeatable cache state (`SharedCacheSnapshot-latest*.clixml`). | Cold pass after change shows WLLS hosts hydrating from cache (`SiteCacheFetchDurationMs = 0`). | docs/StateTrace_Consolidated_Plans.md (2025-11-06 entry) |
| 2025-11-13 | Telemetry bundle + doc-sync dependency documented: release candidates must cite `Logs/TelemetryBundles/<version>/` and attach doc-sync checklist outputs before approvals. | Plan E ST-E-007/ST-E-008 entries, TaskBoard links, `docs/CODEX_DOC_SYNC_PLAYBOOK.md`. | docs/plans/PlanE_Telemetry.md, docs/StateTrace_TaskBoard.md |

## Automation hooks
- `Tools\Invoke-StateTracePipeline.ps1 -RunWarmRunRegression -ShowSharedCacheSummary [-SharedCacheSnapshotPath Logs\SharedCacheSnapshot\SharedCacheSnapshot-latest.clixml]` before tagging any build; archive the cold and warm telemetry JSON files under `Logs/ReleaseEvidence/<version>/`.
- `Tools\Invoke-StateTraceVerification.ps1 -SharedCacheMinimumSiteCount 2 -SharedCacheRequiredSites BOYO,WLLS -EmitWarmRunTelemetry` to enforce gates and produce `VerificationSummary-*.json` for the evidence bundle.
- `Tools\Invoke-StateTraceScheduledVerification.ps1 -Daily -WarmRun -OutputDirectory Logs\Verification` so governance has fresh telemetry even outside manual release windows.
- `Tools\Invoke-SharedCacheWarmup.ps1 -ShowSharedCacheSummary -RequiredSites BOYO,WLLS` prior to packaging; attach the summary output.
- `Tools\Analyze-SharedCacheStoreState.ps1 -Path Logs\IngestionMetrics\<file>.json -IncludeSiteBreakdown` and `Tools\Analyze-SiteCacheProviderReasons.ps1 -IncludeHostBreakdown` after each candidate to document shared-cache health alongside the release record.
- `Tools\Invoke-DailyMetricRollup.ps1` / `Tools\Rollup-IngestionMetrics.ps1` + `Tools\Publish-TelemetryBundle.ps1`: gather the latest rollup CSV, analyzer output, warm-run summaries, and doc-sync checklist reports into `Logs/TelemetryBundles/<date>/` and reference the folder inside the release checklist.
- Apply `docs/CODEX_DOC_SYNC_PLAYBOOK.md` before approvals (plan entry, task board, backlog + session log updates) and record the checklist output in the telemetry bundle README.

## Telemetry gates
- Warm vs cold regression improvement >= 60 percent with `WarmProviderCounts.Cache` covering every processed host; copy the improvement line into the release notes.
- Shared cache snapshot summary (`SharedCacheSnapshot-*-summary.json`) shows minimum site count 2, host count 37, row count >= 1200 before release artifacts are signed.
- `Logs/Verification/VerificationSummary-*.json` (or CLI output) shows `Tools\Invoke-StateTraceVerification.ps1` passed with zero skipped assertions; failures block release until resolved.
- Release checklist (`docs/Release.md`) completed and linked to the TaskBoard along with the doc-sync checklist output (per `docs/CODEX_DOC_SYNC_PLAYBOOK.md`).
- Risk register entry updated if the release introduces new mitigations or residual risk; link the row number in the release announcement.
- Telemetry bundle check: `Logs/TelemetryBundles/<version>/` exists and includes rollup CSV, shared-cache analyzer output, warm-run telemetry summary, diff hotspot CSV, and doc-sync checklist artifact before sign-off.
- Doc-sync evidence recorded: bundle README lists plan/backlog/task-board/session-log links per `docs/CODEX_DOC_SYNC_PLAYBOOK.md`.

## References & history
- Release guide and checklist: `docs/Release.md`.
- Governance + roadmap: `docs/StateTrace_Quarterly_Roadmap.md`, `docs/RiskRegister.md`, `docs/StateTrace_TaskBoard.md`, `docs/taskboard/TaskBoard.csv`.
- Automation + doc sync guides: `docs/CODEX_PLAN_AUTOMATION_MATRIX.md`, `docs/CODEX_DOC_SYNC_PLAYBOOK.md`, `docs/CODEX_SESSION_CHECKLIST.md`, `docs/CODEX_RUNBOOK.md`.
- Historical decisions: `docs/StateTrace_Consolidated_Plans.md` (Plan G sections).

