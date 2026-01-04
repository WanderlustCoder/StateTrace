# Plan F - Security, Identity, & Online Mode

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

## Objective
Keep StateTrace offline-first and Access-backed while providing a documented path for optional online development (guarded downloads, dev seat bootstrapping, RBAC/identity options, and sanitisation tooling).

## Current status (2025-11)
- Security guidelines (`docs/Security.md`), incident intake steps (`docs/StateTrace_IncidentPostmortem_Intake.md`), and identity options (`docs/StateTrace_Acknowledgement_Identity_Options.md`) reflect ADR 0004, but NetOps logging steps remain scattered across the autonomy plan, operations guide, and checklist???Plan F must consolidate them under an actionable workflow with sample JSON/schema references.
- Online dev mode guardrails (`STATETRACE_AGENT_ALLOW_NET`, `STATETRACE_AGENT_ALLOW_INSTALL`, `Tools/NetworkGuard.psm1::Invoke-AllowedDownload`, `Tools/Bootstrap-DevSeat.psm1`) are documented in `docs/CODEX_AUTONOMY_PLAN.md` and `docs/CODEX_RUNBOOK.md`, yet session logs rarely attach the resulting `Logs/NetOps/<date>.json` files or mention how/when the env vars were reset.
- Sanitisation tooling (`Tools/Sanitize-PostmortemLogs.ps1`) is referenced in the Risk Register, incident intake doc, and kickoff tasks (`docs/agents/Agent_Kickoff_Tasks.md`), but there is no automated checklist ensuring sanitized fixtures reach `Data/Postmortems` / `Tests/Fixtures` before UI or parser development uses them.
- `docs/CODEX_PLAN_AUTOMATION_MATRIX.md` and `docs/CODEX_SESSION_CHECKLIST.md` now call out Plan F deliverables (NetOps logs, scrubber evidence, ADR references), so this plan must enumerate the artifacts per task and make sure session logs + task board rows cite them.
- Plan C and Plan D depend on Plan F's sanitized incidents; until ST-F-006 completes, change-tracking and guided-runbook efforts cannot proceed.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-F-001 | Document NetOps logging expectations for online mode | Security | Done - 2026-01-04 | Documented complete NetOps workflow in `docs/Security.md` (comprehensive "Online Mode & NetOps Logging" section with env vars, download flow, reset, validation commands) and `docs/CODEX_AUTONOMY_PLAN.md` (L3 workflow with step-by-step instructions). References `docs/templates/NetOpsLogTemplate.json` (schema), `Tools/Reset-OnlineModeFlags.ps1` (reset), and `Tools/Test-NetOpsEvidence.ps1` (validation). Session checklist already updated in ST-F-005. |
| ST-F-002 | Access scrubber automation | Data | Backlog | Wrap `Tools/Sanitize-PostmortemLogs.ps1` usage into a reproducible script (inputs, destination, report path) and add a nightly fixture refresh entry to the task board; link sanitized bundles in this plan. |
| ST-F-003 | NetOps session log enforcement | Automation | Done - 2025-11-13 | Added `Tools\Test-NetOpsEvidence.ps1` + `Tools\Invoke-AllChecks.ps1 -RequireNetOpsEvidence` so online-mode sessions must cite NetOps/reset logs (with reasons) and optionally the session log reference; lint now skips directory resolution when offline so AllChecks can run without `Logs/NetOps`. |
| ST-F-004 | Identity/RBAC rollout playbook | Security / Platform | Backlog | Translate the recommendations in `docs/StateTrace_Acknowledgement_Identity_Options.md` into a runnable playbook (dev seat bootstrap, RBAC switch verification) and link it from this plan and `docs/Security.md`. |
| ST-F-005 | Offline-first verification checklist | Ops | Done - 2026-01-04 | Extended `docs/CODEX_SESSION_CHECKLIST.md` with detailed offline-first verification section covering: (1) Access database usage - confirm no `.accdb` staged for commit, (2) Online-mode status - check env vars, NetOps logs, and reset logs, (3) Sanitized fixture usage - reference sanitization reports. Created `Tools/Test-OfflineFirstEvidence.ps1` to automate validation with `-RequireAccessLog`, `-RequireNetOpsLog`, `-RequireSanitizationLog` flags and JSON output. |
| ST-F-006 | Sanitized incident intake grind | Data / Docs | Backlog | Follow `docs/StateTrace_IncidentPostmortem_Intake.md` + kickoff task #2 (`docs/agents/Agent_Kickoff_Tasks.md`) to collect six sanitized incidents, drop them under `Data/Postmortems/<IncidentId>/Sanitized`, and reference the sanitizer reports + tracking rows here. |
| ST-F-007 | NetOps + sanitizer evidence template | Automation | Done - 2025-11-13 | Added `docs/templates/NetOpsLogTemplate.json` + `docs/templates/SanitizationEvidenceTemplate.md` so sessions have ready-made evidence snippets for Plan F guardrails. |
| ST-F-008 | NetOps schema + sample log | Security / Docs | Done - 2025-11-13 | Published the sample NetOps log template referenced above (fields cover timestamp, action, URI, hash, session/task IDs). Integrate into automation hooks + Security doc. |
| ST-F-009 | Online-mode reset automation | Automation | Done - 2025-11-13 | Added `Tools\Reset-OnlineModeFlags.ps1` (writes `Logs/NetOps/Resets/OnlineModeReset-<timestamp>.json`) so sessions can clear `STATETRACE_AGENT_ALLOW_*`, capture the provided `-Reason`, and cite the reset evidence in plans/task board/session logs. |

## Near-term execution detail

### ST-F-001 - NetOps logging workflow
- **Pre-flight guardrails:** Default `STATETRACE_AGENT_ALLOW_NET` / `_INSTALL` to `0`. When an online action is unavoidable, set `$env:STATETRACE_AGENT_ALLOW_NET = 1` (and `_INSTALL`) immediately before calling the approved download cmdlet and log the change in the session entry for ST-F-001.
- **Approved download flow:** Wrap every download/install step in `Tools/NetworkGuard.psm1::Invoke-AllowedDownload`. Example:\
  ```powershell
  Import-Module Tools/NetworkGuard.psm1
  Invoke-AllowedDownload `
      -Uri https://vendor.example.com/tool.zip `
      -Destination Downloads\tool.zip `
      -ExpectedSha256 <hash> `
      -Reason 'Plan F ST-F-001 NetOps evidence refresh'
  ```
  Immediately capture the action using `docs/templates/NetOpsLogTemplate.json` as the schema and save the log to `Logs/NetOps/<date>-<session>.json`. Reference the log path/hash in this plan, on the Task Board row, and inside the relevant session log per `docs/CODEX_DOC_SYNC_PLAYBOOK.md`.
- **Reset + lint:** After the download completes, run `pwsh Tools\Reset-OnlineModeFlags.ps1 -Reason "ST-F-001 download complete"` to force `STATETRACE_AGENT_ALLOW_*` back to `0` and emit `Logs/NetOps/Resets/OnlineModeReset-<timestamp>.json` (the JSON now records the reason so session/task notes can link to it). Finish the task with `pwsh Tools\Test-NetOpsEvidence.ps1 -RequireEvidence -RequireReason -SessionLogPath docs/agents/sessions/<id>.md` (or `Tools\Invoke-AllChecks.ps1 -RequireNetOpsEvidence`) to prove both NetOps and reset logs are present and that the reason metadata exists.
- **Documentation sync:** Each time ST-F-001 moves, update `docs/CODEX_AUTONOMY_PLAN.md`, `docs/Security.md`, and `docs/CODEX_SESSION_CHECKLIST.md` pointers so they cite the latest NetOps log filename/hash. Record those doc links inside the Plan F timeline and Task Board note for traceability.

### ST-F-005 - Offline-first verification checklist
- **Checklist updates:** Expand `docs/CODEX_SESSION_CHECKLIST.md` and `docs/StateTrace_AI_Agent_Guide.md` with three mandatory answers per session: (1) Access `.accdb` usage (include file hash), (2) online-mode status (NetOps log + reset log paths), and (3) sanitized fixture consumption/creation (point to `Logs/Sanitization/<incident>.json` or `Data/Postmortems/<incident>/Sanitized`). Reference `docs/templates/SanitizationEvidenceTemplate.md` for wording.
- **Task board hooks:** Every ST-F-005 Task Board update must link to the exact checklist section/anchor and note the evidence paths. Missing entries should trigger `Tools\Invoke-AllChecks.ps1 -RequireNetOpsEvidence` with a failure that blocks merges until the checklist is completed.
- **Automation tie-in:** Track a follow-up to extend `Tools\Test-NetOpsEvidence.ps1` so it also validates Access hash + sanitization references inside the supplied session log. Document the enhancement in this plan before coding so auditors understand the coverage delta.

### ST-F-006 - Sanitized incident intake grind
- **Acquisition loop:** Follow `docs/StateTrace_IncidentPostmortem_Intake.md` to select six incidents. Store raw evidence offline (never committed) and log the secure path inside the session note. Each incident gets a permanent `Data\Postmortems/<IncidentId>/Sanitized` folder (safe to commit) plus corresponding `Logs/Sanitization/<IncidentId>.json`.
- **Sanitization command:** Use the evidence template and run:\
  ```powershell
  pwsh Tools\Sanitize-PostmortemLogs.ps1 `
      -SourcePath D:\SecureDrop\INC2025-1103\Raw `
      -DestinationPath Data\Postmortems\INC2025-1103\Sanitized `
      -ReportPath Logs\Sanitization\INC2025-1103.json `
      -RedactPatterns @('password','community','token','snmpv3')
  ```
  Attach the resulting evidence block to the session log, update this plan + Task Board with the sanitized bundle path, and link the same artifact from Plan C ST-C-005 and Plan D ST-D-009 so downstream work can rely on the fixtures.
- **Validation + publication:** After each sanitization run, execute `Invoke-Pester Tests/Sanitize-PostmortemLogs.Tests.ps1` and `Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -InputPath Data\Postmortems/<IncidentId>/Sanitized` to prove the sanitized data is usable. Record the report hash in `docs/StateTrace_IncidentPostmortem_Intake.md` and surface the incident ID + hash in `docs/StateTrace_TaskBoard.md`.

## Recent timeline (migrated highlights)
| Date (MT) | Summary | Evidence / Metrics | Source |
|-----------|---------|--------------------|--------|
| 2025-12-19 | NetOps lint now skips directory resolution when online mode is inactive, preventing offline AllChecks runs from failing when `Logs/NetOps` is absent. | `pwsh Tools\Invoke-AllChecks.ps1 -SkipPester` now completes NetOps lint when offline. | Tools/Test-NetOpsEvidence.ps1, Tools/Invoke-AllChecks.ps1 |
| 2025-11-13 12:05 | Built NetOps lint (`Tools\Test-NetOpsEvidence.ps1`) and hooked it into `Tools\Invoke-AllChecks.ps1` so online-mode sessions prove NetOps/reset logs (and optional session references) exist before closing. | Command: `pwsh Tools\Test-NetOpsEvidence.ps1 -RequireEvidence -SessionLogPath docs/agents/sessions/<id>.md`; `Tools\Invoke-AllChecks.ps1 -RequireNetOpsEvidence`. | Tools/Test-NetOpsEvidence.ps1, Tools/Invoke-AllChecks.ps1 |
| 2025-11-13 13:50 | Updated `Tools\Test-NetOpsEvidence.ps1` + `Tools\Invoke-AllChecks.ps1` to require the new reset-log `Reason` field so NetOps lint fails if agents forget to cite the plan/task justification. | Script output referencing `-RequireReason`, plan/task board updates. | Tools/Test-NetOpsEvidence.ps1, Tools/Invoke-AllChecks.ps1 |
| 2025-11-13 11:58 | Shipped `Tools\Reset-OnlineModeFlags.ps1` to automatically clear `STATETRACE_AGENT_ALLOW_*`, capture the provided `-Reason`, and emit `Logs/NetOps/Resets/OnlineModeReset-<timestamp>.json`, satisfying ST-F-009. | Script output + reset log example referenced in Task Board row ST-F-009. | Tools/Reset-OnlineModeFlags.ps1 |
| 2025-11-13 11:52 | Added `docs/templates/NetOpsLogTemplate.json` + `docs/templates/SanitizationEvidenceTemplate.md` so every Plan F task has copy/paste scaffolding for NetOps + sanitization evidence. | Template files committed; referenced from Plan F, Plan A, Plan E, and session logs. | docs/templates/NetOpsLogTemplate.json, docs/templates/SanitizationEvidenceTemplate.md |
| 2025-09-30 | ADR 0004 captured the approved-online-mode policy (allowlisted downloads, log requirements, rollback expectations). | `docs/adr/0004-online-mode-and-tooling.md`. | docs/adr/0004-online-mode-and-tooling.md |

## Automation hooks
- Run `pwsh Tools\Test-NetOpsEvidence.ps1 -RequireEvidence -RequireReason [-SessionLogPath <log>]` (or `pwsh Tools\Invoke-AllChecks.ps1 -RequireNetOpsEvidence`) before signing off so NetOps and reset logs (plus session references and reason metadata) are validated.
- `pwsh Tools\Invoke-AllChecks.ps1 -RequireNetOpsEvidence [-NetOpsSessionLogPath <log>]` runs the NetOps lint alongside the existing harness (use `-SkipNetOpsLint` only when offline sessions truly do not require evidence).
- `pwsh Tools\Reset-OnlineModeFlags.ps1 -Reason "<task or plan>"` after any online session so reset logs are generated automatically (with the reason embedded) and stored under `Logs/NetOps/Resets/`.
- `pwsh Tools\Sanitize-PostmortemLogs.ps1 -SourcePath <raw> -DestinationPath Data\Postmortems\<Incident>\Sanitized -ReportPath Logs\Sanitization\<Incident>.json` (plus the evidence template) whenever new incidents are prepared for Plans C/D.

## Telemetry / compliance gates
- Zero `.accdb` or raw log files committed; reviewers must confirm sanitized outputs reference `Tools/Sanitize-PostmortemLogs.ps1` reports.
- Run `Tools\Test-NetOpsEvidence.ps1 -RequireEvidence -RequireReason` (or `Tools\Invoke-AllChecks.ps1 -RequireNetOpsEvidence`) whenever online mode is used to prove NetOps/reset logs, reasons, and session references exist.
- Every online session produces `Logs/NetOps/<date>.json` plus a matching entry in `docs/agents/sessions/`; missing logs block merges until resolved.
- Any use of `STATETRACE_AGENT_ALLOW_NET` / `_INSTALL` is reset to `0` via `Tools\Reset-OnlineModeFlags.ps1` at the end of the session, and the generated `Logs/NetOps/Resets/OnlineModeReset-<timestamp>.json` path is cited in the plan/task board + session log.
- Identity/RBAC changes require a referenced ADR (or playbook entry) and a rollback plan before landing.
- Sanitized incident intake: `docs/StateTrace_IncidentPostmortem_Intake.md` table updated for each bundle, sanitizer reports stored under `Logs/Sanitization/`, and fixture provenance noted in the session/task board entry.
- Dev-seat manifests + allowed downloads must cite the approved manifest (`Tools/Bootstrap\ApprovedManifest.json`), download hashes, and allowlist rationale per `docs/adr/0004-online-mode-and-tooling.md`.

## References & history
- Policy: `docs/Security.md`, `docs/StateTrace_Acknowledgement_Identity_Options.md`.
- Optional mode ADR: `docs/adr/0004-online-mode-and-tooling.md`.
- Supporting guides: `docs/CODEX_AUTONOMY_PLAN.md`, `docs/CODEX_PLAN_AUTOMATION_MATRIX.md`, `docs/CODEX_SESSION_CHECKLIST.md`, `docs/CODEX_RUNBOOK.md`, `docs/StateTrace_AI_Agent_Guide.md`, `docs/RiskRegister.md`, `docs/StateTrace_IncidentPostmortem_Intake.md`, `docs/agents/Agent_Kickoff_Tasks.md`, `docs/templates/NetOpsLogTemplate.json`, `docs/templates/SanitizationEvidenceTemplate.md`.
- Pending artifacts: sanitized incident intake (ST-F-006).

