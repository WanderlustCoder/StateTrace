# Codex Instruction Stack & Flow

This map shows exactly which document to open at each stage of a Codex session. Think of it as the wiring diagram for the automation workflow—every box links to a file that already exists in `docs/`.

| Stage | What you’re doing | Primary doc(s) | Notes |
|-------|-------------------|----------------|-------|
| 0. Orientation | Need the big picture or a TL;DR | `docs/CODEX_OPERATIONS_GUIDE.md`, `docs/CODEX_QUICK_START.md` | Operations Guide = full narrative; Quick Start = condensed three-step view. |
| 1. Guardrails & autonomy | Confirm you’re allowed to run and what approval is needed | `docs/CODEX_AUTONOMY_PLAN.md`, `docs/StateTrace_AI_Agent_Guide.md`, `AGENTS.md` | Review before touching the repo; online mode rules live here. |
| 2. Pick the work | Find a task and its context | `docs/taskboard/TaskBoard.csv`, `docs/CODEX_BACKLOG.md`, `docs/plans/PlanIndex.md` + `Plan*.md` | Task board = current state, backlog = automation view, plan files = objectives/timelines. |
| 3. Plan the session | Record intentions, core ideas, telemetry targets | `docs/agents/Agent_Session_Template.md`, `docs/telemetry/Automation_Gates.md` | Log template + gate lookup; mention the plan you’re touching. |
| 4. Execute | Run commands, edit files | `docs/CODEX_RUNBOOK.md`, `docs/UI_Smoke_Checklist.md` (when UI involved) | Runbook lists every approved script/command; UI checklist verifies WPF shell. |
| 5. Validate | Tests + telemetry capture | `docs/CODEX_RUNBOOK.md` (validation rows), plan file telemetry sections | Record outputs in session log and plan timeline. |
| 6. Document progress | Update plan, task board, backlog | `docs/plans/Plan*.md`, `docs/StateTrace_TaskBoard.md`, `docs/taskboard/TaskBoard.csv`, `docs/CODEX_BACKLOG.md` | Keep all three in sync for autonomous pickup. |
| 7. Wrap up | Ensure nothing is missed | `docs/CODEX_SESSION_CHECKLIST.md` | Tick every box, then produce the CLI summary referencing plans/backlog/gates. |

Keep this file handy if you need to remind yourself where to go next—the quick start tells you *what* to do, this table tells you *which doc* covers that step.
