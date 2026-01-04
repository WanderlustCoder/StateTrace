# Plan N - Documentation & Runbook Automation

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

## Objective
Keep plans, task board entries, runbooks, and session logs synchronized automatically so evidence, telemetry paths, and decision records stay current without manual copy/paste.

## Current status (2025-12)
- Plan/task board updates rely on manual edits; drift occurs between plan tables, `docs/StateTrace_TaskBoard.md`, and `docs/taskboard/TaskBoard.csv`.
- Session logs under `docs/agents/sessions/` are not always created for automation runs, making evidence harder to trace.
- `docs/CODEX_DOC_SYNC_PLAYBOOK.md` exists but is not enforced by tooling.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-N-001 | Task board sync helper | PMO | Done - 2026-01-04 | Created `Tools/Sync-TaskBoard.ps1` to update plan tables and TaskBoard.csv from JSON input or inline parameters. Supports `-WhatIf` for preview, auto-detects plan file from task ID, and reports all changes. |
| ST-N-002 | Session log auto-stub | Automation | Done - 2026-01-04 | Created `Tools/New-SessionLogStub.ps1` to generate session log stubs with commands, artifact paths, and plan/task references. Added `-GenerateSessionLog`, `-TaskIds`, and `-PlanReferences` parameters to `Tools/Invoke-CIHarness.ps1`. Logs written to `docs/agents/sessions/<date>_session-XXXX.md`. |
| ST-N-003 | Decision log hook | PMO | Backlog | Wire `docs/adr/` creation/update into the sync helper when module boundaries or gating rules change; include cross-links from plans. |
| ST-N-004 | Drift detector | QA | Done - 2026-01-04 | Created `Tools/Test-PlanTaskBoardDrift.ps1` to detect discrepancies: tasks missing from TaskBoard, tasks missing from plans, and status mismatches. Integrated into `Tools/Invoke-AllChecks.ps1` with `-SkipDriftDetector` and `-FailOnDrift` flags. Reports saved to `Logs/Reports/PlanTaskBoardDrift-*.json`. |

## Recently delivered
- ST-N-002: Created `Tools/New-SessionLogStub.ps1` and added `-GenerateSessionLog` to `Tools/Invoke-CIHarness.ps1` for automatic session log generation.
- Plan created to track doc/task synchronization automation.

## Automation hooks
- Session log stub: `Tools\New-SessionLogStub.ps1 -Role Automation -TaskIds ST-X-001 -Commands 'command' -ArtifactPaths 'path'`
- CI harness with session log: `Tools\Invoke-CIHarness.ps1 -GenerateSessionLog -TaskIds ST-K-001 -PlanReferences PlanK`
- (Proposed) `Tools\Sync-TaskBoard.ps1 -Input tasks.json -UpdatePlans PlanB,PlanE` to update plan rows + task board in one pass.

## Telemetry gates
- Every automation run that produces telemetry/bundles has a matching session log with commands and artifact paths.
- Plan/task board rows remain consistent (IDs, status, artifacts) per lint check before merge/release.

## References
- `docs/CODEX_DOC_SYNC_PLAYBOOK.md` (manual workflow to automate).
- `docs/StateTrace_TaskBoard.md`, `docs/taskboard/TaskBoard.csv` (targets for sync).
- `docs/adr/` (decisions to be updated when sync helper records structural changes).

