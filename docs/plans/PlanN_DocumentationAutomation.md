# Plan N - Documentation & Runbook Automation

## Objective
Keep plans, task board entries, runbooks, and session logs synchronized automatically so evidence, telemetry paths, and decision records stay current without manual copy/paste.

## Current status (2025-12)
- Plan/task board updates rely on manual edits; drift occurs between plan tables, `docs/StateTrace_TaskBoard.md`, and `docs/taskboard/TaskBoard.csv`.
- Session logs under `docs/agents/sessions/` are not always created for automation runs, making evidence harder to trace.
- `docs/CODEX_DOC_SYNC_PLAYBOOK.md` exists but is not enforced by tooling.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-N-001 | Task board sync helper | PMO | Ready | Add a script (e.g., `Tools\Sync-TaskBoard.ps1`) that updates plan tables, TaskBoard.md, and taskboard CSV from a single structured input (task IDs, status, artifacts). Emit a diff preview before writing. |
| ST-N-002 | Session log auto-stub | Automation | In Progress | Extend harness scripts (`Invoke-StateTracePipeline`, `Invoke-WarmRunTelemetry`, `Publish-TelemetryBundle`) to optionally emit a session log stub under `docs/agents/sessions/` with commands, artifact paths, and plan/task references. |
| ST-N-003 | Decision log hook | PMO | Backlog | Wire `docs/adr/` creation/update into the sync helper when module boundaries or gating rules change; include cross-links from plans. |
| ST-N-004 | Drift detector | QA | Backlog | Add a lint step that flags discrepancies between plan rows and task board entries (missing task IDs, mismatched status, missing artifact paths) and fails CI/harness until resolved. |

## Recently delivered
- Plan created to track doc/task synchronization automation.

## Automation hooks
- (Proposed) `Tools\Sync-TaskBoard.ps1 -Input tasks.json -UpdatePlans PlanB,PlanE` to update plan rows + task board in one pass.
- Harness stub logging: `Tools\Invoke-StateTracePipeline.ps1 -SessionLog docs/agents/sessions/<date>_session-XXXX.md`.

## Telemetry gates
- Every automation run that produces telemetry/bundles has a matching session log with commands and artifact paths.
- Plan/task board rows remain consistent (IDs, status, artifacts) per lint check before merge/release.

## References
- `docs/CODEX_DOC_SYNC_PLAYBOOK.md` (manual workflow to automate).
- `docs/StateTrace_TaskBoard.md`, `docs/taskboard/TaskBoard.csv` (targets for sync).
- `docs/adr/` (decisions to be updated when sync helper records structural changes).
