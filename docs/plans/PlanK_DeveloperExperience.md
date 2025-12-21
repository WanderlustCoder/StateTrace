# Plan K - Developer Experience & CI Readiness

## Objective
Deliver a repeatable, offline-friendly developer experience and minimal CI harness that exercises parser, warm-run, and UI smoke paths on tracked fixtures under PowerShell 5.1 and 7, producing telemetry artifacts ready for Plans E/G without manual cleanup.

## Current status (2025-12)
- No repository CI or scheduled smoke exists; all gates run manually via runbooks.
- Harness scripts support telemetry bundle generation, but they assume local gitignored fixtures and do not fail fast when logs are malformed.
- Developer seat bootstrap script exists but lacks validation that required PowerShell modules and execution policies are set for automation runs.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-K-001 | Add minimal offline CI harness | Automation | Ready | Create a single entrypoint (PowerShell 5.1 and 7) that runs `Invoke-Pester Modules/Tests -Tag Smoke`, `Tools\Invoke-StateTracePipeline.ps1` on the minimal fixture set, and `Tools\Invoke-WarmRunTelemetry.ps1 -GenerateDiffHotspotReport` with guards on. Emit artifacts under `Logs/CI/<run>/` and fail if queue summary, diversity, or shared-cache diagnostics are missing. |
| ST-K-002 | Harden developer bootstrap | Platform | In Progress | Extend `Tools\Bootstrap-DevSeat.ps1` to validate execution policy, required modules, and presence of tracked fixture seeds; emit remediation steps and log under `docs/agents/sessions/`. |
| ST-K-003 | Artifact hygiene & bundling | PMO | Ready | After CI harness completes, call `Tools\Publish-TelemetryBundle.ps1 -PlanReferences PlanK,PlanE,PlanG -TaskBoardIds ST-K-003,ST-E-00X,ST-G-00X` to package cold/warm telemetry, shared-cache analyzers, diff hotspots, and README hashes. |
| ST-K-004 | Offline guardrails | Security | Backlog | Add a preflight to CI harness that asserts `STATETRACE_AGENT_ALLOW_NET` and `STATETRACE_AGENT_ALLOW_INSTALL` are unset; if set, log reason and exit. Document the policy in this plan and `docs/CODEX_RUNBOOK.md`. |
| ST-K-005 | Code review findings remediation (batch 1) | Automation | In Progress | Address high-severity items in `docs/notes/2025-12-21_code_review_findings.md`; findings 55-63 done (cache sync, AllInterfaces merge, view locks). |

## Recently delivered
- Plan created to formalize developer experience and CI readiness.

## Automation hooks
- Smoke tests: `Invoke-Pester Modules/Tests -Tag Smoke -SkipErrorActionPreference`; extend tags as coverage grows.
- Cold pass: `Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs -RunSharedCacheDiagnostics -FailOnTelemetryMissing -FailOnSchedulerFairness`.
- Warm pass: `Tools\Invoke-WarmRunTelemetry.ps1 -GenerateDiffHotspotReport -DisablePreservedRunspacePool -OutputPath Logs/CI/<run>/WarmRunTelemetry.json` (guards on by default).
- Bundle: `Tools\Publish-TelemetryBundle.ps1 -BundleName CI-<timestamp> -PlanReferences PlanK,PlanE,PlanG -TaskBoardIds ST-K-003,ST-E-00X,ST-G-00X -Notes "CI smoke artifacts"`.
- Developer seat validation: `Tools\Bootstrap-DevSeat.ps1 -ValidateOnly` (proposed flag) to check prerequisites without mutating state.

## Telemetry gates
- CI smoke completes in <= 20 minutes on a fresh seat with tracked fixtures only.
- Queue summary present with p95 <= 120 ms / p99 <= 200 ms; diversity guard passes (streak <= 8).
- Shared-cache diagnostics show `SnapshotImported > 0` and `GetHit` exceeds `GetMiss` for fixture sites.
- Warm run emits diff hotspot CSV and `WarmCacheHitRatioPercentRaw > 0`.
- CI artifacts stored under `Logs/CI/<run>/` and bundled via `Publish-TelemetryBundle`.

## References
- `docs/CODEX_RUNBOOK.md` (automation matrix and bundle workflow).
- `docs/plans/PlanI_HarnessStability.md` (guard health expectations).
- `docs/plans/PlanJ_TestFixtureReliability.md` (fixture seeds relied on by CI).
