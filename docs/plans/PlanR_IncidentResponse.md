# Plan R - Incident Response & Rollback Readiness

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

## Objective
Codify fast incident response, rollback, and mitigation workflows: consistent runbooks, evidence capture, rollback bundles, and drills that keep routing/parser/UI stable under regressions.

## Current status (2025-12)
- Incident intake template exists, but drills are ad-hoc; rollback paths (previous package, snapshot restore) are not automated.
- NetOps/online-mode evidence requirements are documented but not enforced during incident handling.
- No standardized ???rollback bundle??? capturing prior telemetry, package hashes, and configuration before reverting.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-R-001 | Incident drill cadence | PMO | Done - 2026-01-04 | Created `docs/runbooks/Incident_Drill_Schedule.md` with monthly drill cadence (7 scenarios rotating), success criteria, and drill result template. Added `Tools/Invoke-IncidentDrill.ps1` to execute/record drills with timing capture, gap identification, and JSON output under `Logs/Drills/`. |
| ST-R-002 | Rollback bundle automation | Automation | Done - 2026-01-04 | Created `Tools/New-RollbackBundle.ps1` to capture state before rollback: StateTraceSettings.json, telemetry bundle refs (latest 3), shared-cache snapshot (optional), package hashes (6 key files), git info. Stores under `Logs/RollbackBundles/<BundleName>/` with RollbackManifest.json. |
| ST-R-003 | Online-mode evidence enforcement | Security | Done - 2026-01-04 | Created `Tools\Test-IncidentClosureEvidence.ps1` to validate closure requirements: online-mode flag status, NetOps/reset logs with reasons, post-incident verification (AllChecks, shared-cache diagnostics), session log references. Use `-RequireNetOpsEvidence`, `-RequirePostIncidentVerification`, `-FailOnMissingEvidence` for enforcement. |
| ST-R-004 | Post-incident verification | QA | Done - 2026-01-04 | Created `Tools\Invoke-PostIncidentVerification.ps1` to run verification suite after rollback/fix: AllChecks, telemetry integrity, shared-cache diagnostics, snapshot validation, warm-run telemetry (optional). Outputs to `Logs\Verification\PostIncident\<IncidentId>/`. Use `-FailOnVerificationError` for CI. |

## Recently delivered
- Plan created to track incident and rollback readiness work.

## Automation hooks
- Incident intake: `docs/StateTrace_IncidentPostmortem_Intake.md` template; attach telemetry bundle paths.
- Rollback bundle (proposed): `Tools\New-RollbackBundle.ps1 -OutputPath Logs\RollbackBundles\<date>` capturing hashes, snapshots, configs.
- Evidence checks: `Tools\Test-NetOpsEvidence.ps1 -RequireEvidence -RequireReason`; `Tools\Reset-OnlineModeFlags.ps1 -Reason "<incident>"`.
- Verification: `Tools\Invoke-StateTraceVerification.ps1 -VerifyTelemetryBundleReadiness -GenerateSharedCacheDiagnostics -EmitWarmRunTelemetry`.

## Telemetry gates
- Incident closure requires telemetry bundle + rollback bundle paths and NetOps evidence (if online mode used).
- Post-rollback verification passes shared-cache and warm-run gates before declaring stable.
- Drill outcomes logged with timings and action items; runbook updates follow each drill.

## References
- `docs/StateTrace_IncidentPostmortem_Intake.md` (intake template).
- `docs/plans/PlanF_SecurityIdentity.md` (online-mode/evidence policies).
- `docs/plans/PlanG_ReleaseGovernance.md` (release gating that depends on rollback readiness).

