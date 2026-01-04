# Codex Session Checklist

Use this one-pager as the quick command-and-control loop for every Codex session. Each checkbox references the deeper instructions in `docs/CODEX_OPERATIONS_GUIDE.md`; keep both files handy.

## Pre-flight
- [ ] Skim `docs/CODEX_QUICK_START.md`, `docs/CODEX_OPERATIONS_GUIDE.md`, or the table in `docs/CODEX_INSTRUCTION_STACK.md` if you need the full flow.
- [ ] Identify a task in `docs/taskboard/TaskBoard.csv` (match its Plan in `docs/plans/PlanIndex.md`).
- [ ] Confirm the same task exists in `docs/CODEX_BACKLOG.md`.
- [ ] Draft/update your session log from `docs/agents/Agent_Session_Template.md`.
- [ ] Record a multi-step plan via `update_plan`, citing the relevant plan file + telemetry gates.
- [ ] Review the Plan’s “Recent timeline” section and linked notes/ADRs for context.

## Execution loop
- [ ] Enumerate target files with `rg`/`Select-String`.
- [ ] Apply code/doc changes, keeping strict mode and guardrails (see AI Agent Ops Guide).
- [ ] Run required commands from `docs/CODEX_RUNBOOK.md` (pipeline, warm regression, autoscale, metrics rollup, etc.).
- [ ] For UI work, complete every row in `docs/UI_Smoke_Checklist.md`.
- [ ] When online mode is needed, set the approved env vars, route downloads via `Tools/NetworkGuard.psm1`, and log NetOps entries.
- [ ] Before wrapping online work, run `Tools\Reset-OnlineModeFlags.ps1 -Reason "<plan/task note>"` so `STATETRACE_AGENT_ALLOW_*` returns to `0`, the reason is captured in `Logs/NetOps/Resets/*.json`, and cite the path in your notes.

## Offline-first verification (ST-F-005)
Every session must answer three questions to maintain offline-first compliance:

### 1. Access database usage
- [ ] **Did you use Access `.accdb` files?** If yes, record which files and their purpose.
- [ ] **File paths:** List any `.accdb` files read or written (e.g., `Data/WLLS/WLLS.accdb`).
- [ ] **Verification:** Confirm no `.accdb` files are staged for commit (`git status` should show none).

### 2. Online-mode status
- [ ] **Was online mode enabled?** (Check `$env:STATETRACE_AGENT_ALLOW_NET` / `$env:STATETRACE_AGENT_ALLOW_INSTALL`)
- [ ] If yes: Record NetOps log path (`Logs/NetOps/<date>.json`) in your session log.
- [ ] If yes: Confirm reset was executed via `Tools\Reset-OnlineModeFlags.ps1 -Reason "<task>"`.
- [ ] If yes: Record reset log path (`Logs/NetOps/Resets/OnlineModeReset-<timestamp>.json`).
- [ ] If no: Confirm session ran fully offline (no external downloads or network calls).

### 3. Sanitized fixture usage
- [ ] **Did you consume or create sanitized fixtures?** If yes, record the paths.
- [ ] For consumption: Reference fixture path (e.g., `Tests/Fixtures/Routing/CliCapture/`).
- [ ] For creation: Run `Tools\Sanitize-PostmortemLogs.ps1` and record report path (`Logs/Sanitization/<id>.json`).
- [ ] Confirm no raw/unsanitized logs are staged for commit.

### Quick validation command
Run this to verify offline-first compliance:
```powershell
pwsh Tools\Test-OfflineFirstEvidence.ps1 -SessionLogPath docs/agents/sessions/<date>_session-XXXX.md [-RequireAccessLog] [-RequireNetOpsLog] [-RequireSanitizationLog]
```

## Validation & telemetry
- [ ] Execute `Invoke-Pester Modules/Tests` plus any script mandated by the plan (pipeline, warm regression, span smoke).
- [ ] Capture outputs/paths in your session log (`Logs/IngestionMetrics/<date>.json`, WarmRunTelemetry, CSV rollups).
- [ ] Compare metrics to `docs/telemetry/Automation_Gates.md`; stop/escalate if thresholds are missed.
- [ ] For telemetry bundle work, run `Tools\Test-TelemetryBundleReadiness.ps1 -BundlePath Logs/TelemetryBundles/<bundle> -Area Telemetry,Routing` (or `Tools\Invoke-AllChecks.ps1 -TelemetryBundlePath Logs/TelemetryBundles/<bundle> -RequireTelemetryBundleReady`) and record the readiness output in your session log.
- [ ] For Plan H bundles, run `Tools\Test-PlanHReadiness.ps1 -BundlePath Logs/TelemetryBundles/<bundle>` (or publish with `-VerifyPlanHReadiness`) and stash `PlanHReadiness.json` inside the bundle; cite the path in your session log.

## Documentation & handoff
- [ ] Update the Plan file (active work or recent timeline) with results + telemetry links.
- [ ] Update `docs/StateTrace_TaskBoard.md` and `docs/taskboard/TaskBoard.csv` (status, notes, links).
- [ ] Update `docs/CODEX_BACKLOG.md` (close or move the row; add follow-ups).
- [ ] Save your session log under `docs/agents/sessions/<date>_session-XXXX.md`.
- [ ] Run `Tools\Test-DocSyncChecklist.ps1 -TaskId <id> -SessionLogPath docs/agents/sessions/<date>_session-XXXX.md -RequireSessionLog -OutputPath Logs/Reports/DocSyncChecklist-<timestamp>.json` (or `Tools\Invoke-AllChecks.ps1 -DocSyncTaskId <id> -DocSyncSessionLogPath ... -RequireDocSyncChecklist`) and record the output path in your session log.
- [ ] Produce the CLI summary (`PATCH SUMMARY`, `TEST RESULTS`, `TASKBOARD UPDATE`, `NEXT STEP`) referencing the plan entry and telemetry artifacts.

Complete every box above and Codex has executed the session end-to-end with the required evidence for autonomous handoff.
