# 2025-09-22 Multi-Agent Workflow Protocol

## Session Context
- Timestamp (-06:00): 2025-09-22 14:32:08
- AI Agent: Codex (GPT-5)
- Objective: Establish multi-agent collaboration workflow, backup expectations, and documentation duties.
- Repository Path: C:\Users\Werem\OneDrive\Documents\StateTrace
- Backup Directory: C:\Users\Werem\StateTraceBackups

## Action Log
| Timestamp (-06:00) | Agent | Action | Status |
| --- | --- | --- | --- |
| 2025-09-22 14:32:08 | Codex | Planned multi-agent workflow and documentation strategy for concurrent AI contributions. | Planned |
| 2025-09-22 14:32:44 | Codex | Finalized workflow protocol document and shared guidance with collaborators. | Committed |

## Multi-Agent Workflow Overview
1. Triage and Plan
   - Assign a coordinating agent to review backlog items and open docs before other agents begin.
   - Record the planned change in a new or existing doc under "Action Log" with `Status = Planned`.
   - Identify required backups and testing scope during planning.
2. Implementation Phase
   - Work on dedicated git branches named `feature/<yyyymmdd>_<shortname>` to isolate concurrent efforts.
   - Before editing, ensure the doc contains the planned scope and verify no conflicting status from other agents.
   - Update the doc with interim notes or checkpoints if the scope shifts.
3. Review and Validation
   - A reviewing agent documents findings in the same doc, tagging entries with their name and timestamp.
   - Tests and validation steps are logged, including commands run and outcomes.
   - Upon approval, change status transitions to `Ready` then `Committed`.
4. Completion or Rollback
   - When committing, note the git commit hash, merge target, and backup folder in the doc.
   - If rescinded, mark status as `Rescinded`, summarize rationale, and reference cleanup actions.

## Documentation Protocol
- Maintain change docs in `docs/` using the template `docs/YYYYMMDD_<shortname>.md`.
- Each doc must contain sections: Session Context, Action Log, Plan, Implementation Notes, Testing, Backups, Decision/Status.
- Agents must append to the Action Log whenever they plan, commit, or rescind work, including timestamps and agent identifiers.
- Retain succinct bullet summaries; keep detailed logs in the Action Log table to avoid ambiguity.

## Backup Procedure
- Perform a filesystem backup before any major code or data modification using:
  `Copy-Item -Path "C:\Users\Werem\OneDrive\Documents\StateTrace" -Destination "C:\Users\Werem\StateTraceBackups\<timestamp>_<shortname>" -Recurse`
- Record the destination path and verification outcome in the doc's Backups section.
- Store incremental backups for each major milestone; prune only with user approval.

## Concurrency Safeguards
- Run `git status` before starting to confirm a clean workspace or note pre-existing changes in the doc.
- Use `rg` for fast searches and avoid accidental global edits.
- Communicate dependencies between agents explicitly in the doc, noting files likely to conflict.
- Schedule merges sequentially: Plan -> Implement -> Review -> Commit, ensuring only one agent merges at a time.

## Follow-Up
- Share this protocol with all collaborating agents and require acknowledgement in their first Action Log entry.
- Consider automating doc scaffolding and backup creation to reduce manual effort in future sessions.
