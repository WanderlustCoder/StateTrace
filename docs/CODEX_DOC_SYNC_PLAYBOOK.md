# Codex Documentation Sync Playbook

Use this playbook every time you close or hand off a task. It ensures the plan file, Task Board (Markdown + CSV), Codex backlog, and session log stay consistent so future agents can resume work without spelunking through git history.

## When to run it
- After finishing or pausing a task from `docs/taskboard/TaskBoard.csv`.
- Whenever telemetry changes require plan/timeline updates.
- Before writing the CLI summary for a Codex session.

## Step-by-step flow
| Step | Action | Where | Notes / Evidence |
|------|--------|-------|------------------|
| 1 | Capture telemetry references | `Logs/`, command output, screenshots | Record file paths (JSON/CSV), command parameters, and timestamps. |
| 2 | Update plan file | `docs/plans/Plan*.md` | Move rows between Active/Recently Delivered, extend the timeline table, and cite telemetry artifacts. |
| 3 | Update Task Board (Markdown) | `docs/StateTrace_TaskBoard.md` | Modify the board table row (Column, Deliverable, Links). Include plan link + evidence snippet. |
| 4 | Update Task Board CSV | `docs/taskboard/TaskBoard.csv` | Mirror the same info in CSV form (quotes around fields with commas). |
| 5 | Update Codex backlog (if applicable) | `docs/CODEX_BACKLOG.md` | Keep the backlog table aligned with the task board (status, definition of done notes, plan references). |
| 6 | Log the session | `docs/agents/sessions/<date>_<id>.md` | Paste command transcripts, telemetry excerpts, and doc links. |
| 7 | Append historical note | `docs/StateTrace_Consolidated_Plans.md` | Optional but recommended when the work adds narrative context or multi-step investigations. |

## Templates & snippets

### Plan timeline entry
````markdown
| 2025-11-12 14:05 | Summary of the change | Evidence (Logs/..., commands) | Source doc/section |
````
> Always cite at least one telemetry artifact (JSON/CSV path or command) plus the doc you touched.

### Task board Markdown row
````markdown
| ST-X-123 | Title | Column | Owner | Deliverable | docs/plans/PlanX_Something.md |
````

### Task board CSV row
````csv
ST-X-123,Title,Column,Owner,"Deliverable or status sentence.",docs/plans/PlanX_Something.md,"Extra notes or evidence pointer."
````

### Session log evidence block
````markdown
#### Telemetry
- `Logs/IngestionMetrics/2025-11-12.json` (ParseDuration p95 612 ms)
- `Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs`

#### Documentation edits
- `docs/plans/PlanB_Performance.md` (Active work row ST-B-001 updated)
- `docs/taskboard/TaskBoard.csv` (ST-B-001 column -> Done)
````

## Validation checklist
- [ ] Plan file updated (Active/Recently Delivered, timeline, automation hooks if needed).
- [ ] `docs/StateTrace_TaskBoard.md` matches the new state.
- [ ] `docs/taskboard/TaskBoard.csv` mirrors the Markdown board.
- [ ] `docs/CODEX_BACKLOG.md` reflects the same status (if the ID exists there).
- [ ] Session log captures commands + telemetry.
- [ ] Consolidated log (optional) updated for historical trace.
- [ ] CLI summary references the plan ID and telemetry artifacts.

## Automation helper
- Run `pwsh -NoLogo -File Tools\Test-DocSyncChecklist.ps1 -TaskId <id> -SessionLogPath docs\agents\sessions\<date>_session-XXXX.md -RequireSessionLog -OutputPath Logs\Reports\DocSyncChecklist-<timestamp>.json` to validate the checklist and emit a JSON summary.
- Use `pwsh -NoLogo -File Tools\Invoke-AllChecks.ps1 -DocSyncTaskId <id> -DocSyncSessionLogPath docs\agents\sessions\<date>_session-XXXX.md -RequireDocSyncChecklist` when you want the checklist enforced alongside other CI-ready guards.
- Copy the JSON output into `Logs\TelemetryBundles\<bundle>\DocSync\DocSyncChecklist.json` when producing release evidence bundles.

## Tips
- Use `rg -n "ST-X-123" docs/StateTrace_TaskBoard.md` to jump straight to the row you need.
- Prefer copying Markdown table rows into a temp buffer, editing, then pasting back to avoid alignment issues.
- When multiple tasks move simultaneously, update the CSV first (easier to diff), then mirror those edits into the Markdown board.
- Commit documentation changes only after every box above is checked, ensuring future agents inherit a consistent state.

Pair this playbook with `docs/CODEX_PLAN_AUTOMATION_MATRIX.md` (what to run) and `docs/CODEX_RUNBOOK.md` (how to run it) for fully autonomous sessions.
