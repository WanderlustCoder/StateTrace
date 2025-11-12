# Codex Quick Start (TL;DR)

Need to start a Codex session fast? Keep this cheat sheet open. It collapses the flow from the operations guide into three clusters with the most relevant links.

## 1. Pick & plan
1. `docs/taskboard/TaskBoard.csv` → choose a row (confirm same ID exists in `docs/CODEX_BACKLOG.md`).
2. Open the matching plan file (see `docs/plans/PlanIndex.md`) and read its “Recent timeline.”
3. Create/update your session log (`docs/agents/Agent_Session_Template.md`) and record a plan via `update_plan`.
4. Skim `docs/telemetry/Automation_Gates.md` for the gates that apply to this plan.

## 2. Execute & validate
1. Make code/doc changes; rely on the commands in `docs/CODEX_RUNBOOK.md`.
2. For UI work, run through `docs/UI_Smoke_Checklist.md`.
3. Run required tests (`Invoke-Pester Modules/Tests`, pipeline/warm regression as listed in the plan).
4. Capture telemetry (`Logs/IngestionMetrics/<date>.json`, WarmRunTelemetry, rollups) and compare to Automation Gates.

## 3. Document & hand off
1. Update the plan file (active work + timeline), the task board table + CSV, and `docs/CODEX_BACKLOG.md`.
2. Finish the session log (`docs/agents/sessions/<date>_session-XXXX.md`).
3. Tick every box in `docs/CODEX_SESSION_CHECKLIST.md`.
4. Publish the CLI summary (`PATCH SUMMARY`, `TEST RESULTS`, `TASKBOARD UPDATE`, `NEXT STEP`) referencing the plan/backlog entries and telemetry artifacts.

For the full narrative, see `docs/CODEX_OPERATIONS_GUIDE.md`. This quick start exists so you can keep a single window open during execution.
