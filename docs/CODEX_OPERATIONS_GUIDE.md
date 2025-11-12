# Codex Operations Guide

This guide stitches together every artifact Codex needs to execute StateTrace work with minimal human input. Follow it top-to-bottom whenever you start a session; each step links to the deeper references that already live in `docs/`.

## 0. Reference map
| Artifact | Purpose |
|----------|---------|
| `docs/CODEX_AUTONOMY_PLAN.md` | Autonomy levels, guardrails, escalation rules. |
| `docs/CODEX_BACKLOG.md` + `docs/taskboard/TaskBoard.csv` | Automation-ready work queue aligned with plan files. |
| `docs/plans/PlanIndex.md` + `docs/plans/Plan*.md` | Strategic objectives, active work, timelines, telemetry hooks. |
| `docs/CODEX_RUNBOOK.md` | Command/validation matrix for parser, tests, metrics, UI smoke. |
| `docs/UI_Smoke_Checklist.md` | Per-view verification of the WPF shell. |
| `docs/telemetry/Automation_Gates.md` | Success criteria per plan/task. |
| `docs/agents/Agent_Session_Template.md` | Log template for every session. |
| `docs/CODEX_SESSION_CHECKLIST.md` | Quick checkbox flow for the entire session (pre-flight through handoff). |
| `docs/CODEX_QUICK_START.md` | TL;DR version of this guide (three-step flow: pick & plan, execute, hand off). |
| `docs/CODEX_INSTRUCTION_STACK.md` | Table showing which doc applies to each stage (guardrails → wrap-up). |

Keep these open while you work; the instructions below assume you can jump to them quickly.

## 1. Choose the work item
1. Open `docs/taskboard/TaskBoard.csv` (or the table at the top of `docs/StateTrace_TaskBoard.md`) and pick an item that matches the Plan you intend to advance.
2. Cross-check the corresponding plan file under `docs/plans/` to understand objectives, active work, and telemetry gates.
3. Confirm the same task exists in `docs/CODEX_BACKLOG.md`; if not, add it there before proceeding.

## 2. Record the plan
1. Create or update your session log via `docs/agents/Agent_Session_Template.md` (store it under `docs/agents/sessions/` when done).
2. Use `update_plan` to write a 3–6 bullet plan that explicitly references the relevant plan file and Automation Gates.
3. Note which core ideas (from `docs/StateTrace_AI_Agent_Guide.md`) your work addresses.

## 3. Gather context
1. Read the “Recent timeline” table in the plan file plus any linked notes (e.g., span investigation, diff prototype).
2. If you need additional background, consult `docs/StateTrace_Functions_Features.md`, ADRs, or the plan archive (`docs/StateTrace_Consolidated_Plans.md`).
3. Enumerate target files with `rg`/`Select-String` before editing.

## 4. Execute
Follow these sub-steps for every change:
1. Implement code/doc updates, keeping diffs focused (strict mode remains on everywhere).
2. For parser/ingestion/scheduler work, rely on the commands in `docs/CODEX_RUNBOOK.md` (pipeline, warm regression, autoscale profile, shared cache warmup, metrics rollup, diff hotspot analyzer).
3. For UI work, always complete the `docs/UI_Smoke_Checklist.md` after running the pipeline so cached data is fresh.
4. When touching security/online mode, ensure environment flags and NetOps logs comply with ADR 0004 as described in Plan F.

## 5. Validate & capture telemetry
1. Run the required tests: `Invoke-Pester Modules/Tests` plus any plan-specific scripts (pipeline, warm regression, span smoke).
2. Record outputs in your session log and attach relevant snippets (`Logs/IngestionMetrics/<date>.json`, warm-run summaries, CSV rollups).
3. Compare results against `docs/telemetry/Automation_Gates.md`; if you miss a gate, stop and treat the task as blocked.

## 6. Update documentation
1. Edit the corresponding plan file’s “Active work” or “Recent timeline” entry with metrics, commands, and references.
2. Update the task board table and CSV row (status, notes, links).
3. When behaviour changes, also update any affected runbooks (`docs/StateTrace_Operators_Runbook.md`, `docs/CODEX_RUNBOOK.md`, `docs/UI_Smoke_Checklist.md`, etc.).

## 7. Finalise the session
1. Save your session log in `docs/agents/sessions/<date>_session-XXXX.md`.
2. Ensure `docs/CODEX_BACKLOG.md` reflects the new state (move the row, add follow-ups).
3. Produce the CLI summary (`PATCH SUMMARY`, `TEST RESULTS`, `TASKBOARD UPDATE`, `NEXT STEP`) referencing the plan/backlog entries you touched.

## Blockers & escalation
- If a gate cannot be met (telemetry missing, tests failing, schema change required), move the task to **Blocked**, document the dependency in the plan file, and reference it in your summary.
- For online/dependency work, log every download/install per the Autonomy Plan and record the NetOps file path in your session notes.

## Checklist for “nearly automatic” runs
1. Task selected from `TaskBoard.csv` + plan file reviewed.
2. Plan recorded via `update_plan` + session log draft.
3. Implementation aligned with `docs/CODEX_RUNBOOK.md` commands.
4. Telemetry captured and compared to Automation Gates.
5. Plan file / task board / backlog / session log all updated.
6. UI smoke checklist completed when UI changed.
7. CLI summary references plan + telemetry artifacts.

If every box is checked, Codex has everything required to deliver the change autonomously.
