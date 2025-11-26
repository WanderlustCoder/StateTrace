# Codex Autonomy Plan

This document defines when Codex (or any autonomous agent) may execute work without a human in the loop, which safeguards stay in force, and how to escalate. Use it together with `docs/StateTrace_AI_Agent_Guide.md`, `docs/CODEX_RUNBOOK.md`, and the per-plan pages in `docs/plans/`.

## Mission
Enable Codex to develop and validate StateTrace changes end-to-end while remaining offline-ready, Access-backed, and fully auditable. Autonomy is granted only when the preconditions below are satisfied.

## Preconditions
1. **Scope clarity** – The work is represented in `docs/plans/*` and mirrored as a task board/backlog entry (ID referenced in session log).
2. **Telemetry gates defined** – Applicable metrics exist in `docs/telemetry/Automation_Gates.md`.
3. **Tooling available offline** – Required scripts/tests live in the repo; no external downloads are necessary unless the operator has enabled online mode.
4. **Session log ready** – `docs/agents/Agent_Session_Template.md` file prepared for the upcoming session.

## Autonomy levels
| Level | Description | Allowed actions | Extra requirements |
|-------|-------------|-----------------|--------------------|
| L0 – Observe | Read-only analysis | `rg`, `Select-String`, `Get-Content` | None |
| L1 – Edit & test | Modify code/docs, run tests | PowerShell scripts listed in `docs/CODEX_RUNBOOK.md` | Must attach telemetry + task board update |
| L2 – Experiment | Run ingestion pipelines with overrides | Any `Tools\Invoke-StateTracePipeline.ps1` variants, warm-run regression, Access maintenance scripts | Log commands, overrides, metrics; reset overrides to defaults |
| L3 – Online | Perform guarded downloads or dev seat installs | `Tools/NetworkGuard.psm1::Invoke-AllowedDownload`, `Tools/Bootstrap-DevSeat.ps1` | Operator opt-in, environment variables set, NetOps log updated |

Default sessions operate at **L1**. Escalate to L2/L3 only when documented in the plan/task entry and approved by the operator.

## Guardrails
- Follow `docs/StateTrace_AI_Agent_Guide.md` for the operating loop, security rules, and deliverables.
- When editing, keep diffs tight, maintain strict mode, and avoid compiled components or new stores.
- Never commit `.accdb`, raw logs, or secrets; sanitise via `Tools/Sanitize-PostmortemLogs.ps1`.
- Record every command that mutates data or runs ingestion in the session log.
- For online mode, set `STATETRACE_AGENT_ALLOW_NET=1` (and `_INSTALL=1` if needed), then route all downloads through `Tools/NetworkGuard.psm1::Invoke-AllowedDownload` and write `Logs/NetOps/<date>.json`.

## Escalation & stop conditions
- **Blockers** – move the task board card (and CSV entry) to Blocked, capture the dependency, and note it in the plan file.
- **Telemetry gaps** – if metrics cannot be captured, stop and log the missing artifact; do not guess.
- **Schema or compiled-code requirement** – stop and open an ADR (`docs/adr/`) before continuing.
- **Test failures** – if you cannot fix within the session’s command budget, stop with the failing command output included in the log.

## Reporting
- Summaries must use the CLI formatting (`PATCH SUMMARY`, `TEST RESULTS`, `TASKBOARD UPDATE`, `NEXT STEP`).
- Every autonomous run must update:
  - Relevant plan file under `docs/plans/`.
  - Task table (`docs/StateTrace_TaskBoard.md`) and CSV (`docs/taskboard/TaskBoard.csv`).
  - Session log under `docs/agents/sessions/`.
  - The steps in `docs/CODEX_OPERATIONS_GUIDE.md` (and tick off `docs/CODEX_SESSION_CHECKLIST.md`) before closing the session.

## References
- `docs/CODEX_BACKLOG.md` – automation-ready tasks.
- `docs/CODEX_RUNBOOK.md` – command & validation matrix.
- `docs/telemetry/Automation_Gates.md` – numeric success criteria.
- `docs/plans/PlanIndex.md` – objective map for Plans A–G.
