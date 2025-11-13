# Plan F â€“ Security, Identity, & Online Mode

## Objective
Keep StateTrace offline-first and Access-backed while providing a documented path for optional online development (guarded downloads, dev seat bootstrapping, RBAC/identity options, and sanitisation tooling).

## Current status (2025-11)
- Security guidelines (`docs/Security.md`), incident intake steps (`docs/StateTrace_IncidentPostmortem_Intake.md`), and identity options (`docs/StateTrace_Acknowledgement_Identity_Options.md`) reflect ADR 0004, but NetOps logging steps remain scattered across the autonomy plan, operations guide, and checklist—Plan F must consolidate them under an actionable workflow with sample JSON/schema references.
- Online dev mode guardrails (`STATETRACE_AGENT_ALLOW_NET`, `STATETRACE_AGENT_ALLOW_INSTALL`, `Tools/NetworkGuard.psm1::Invoke-AllowedDownload`, `Tools/Bootstrap-DevSeat.psm1`) are documented in `docs/CODEX_AUTONOMY_PLAN.md` and `docs/CODEX_RUNBOOK.md`, yet session logs rarely attach the resulting `Logs/NetOps/<date>.json` files or mention how/when the env vars were reset.
- Sanitisation tooling (`Tools/Sanitize-PostmortemLogs.ps1`) is referenced in the Risk Register, incident intake doc, and kickoff tasks (`docs/agents/Agent_Kickoff_Tasks.md`), but there is no automated checklist ensuring sanitized fixtures reach `Data/Postmortems` / `Tests/Fixtures` before UI or parser development uses them.
- `docs/CODEX_PLAN_AUTOMATION_MATRIX.md` and `docs/CODEX_SESSION_CHECKLIST.md` now call out Plan F deliverables (NetOps logs, scrubber evidence, ADR references), so this plan must enumerate the artifacts per task and make sure session logs + task board rows cite them.
- Plan C and Plan D depend on Plan F's sanitized incidents; until ST-F-006 completes, change-tracking and guided-runbook efforts cannot proceed.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-F-001 | Document NetOps logging expectations for online mode | Security | In Progress | Capture the env-var + `Invoke-AllowedDownload` workflow in `docs/CODEX_AUTONOMY_PLAN.md`, `docs/Security.md`, and `docs/CODEX_SESSION_CHECKLIST.md`; provide a sample `Logs/NetOps/<date>.json` schema and reference it here. |
| ST-F-002 | Access scrubber automation | Data | Backlog | Wrap `Tools/Sanitize-PostmortemLogs.ps1` usage into a reproducible script (inputs, destination, report path) and add a nightly fixture refresh entry to the task board; link sanitized bundles in this plan. |
| ST-F-003 | NetOps session log enforcement | Automation | Ready | Build a lint-style check/script that verifies `STATETRACE_AGENT_ALLOW_NET`/`_INSTALL` usage is mirrored by `Logs/NetOps/<date>.json` + `docs/agents/sessions/`; hook it into `Tools/Invoke-AllChecks.ps1` or CI. |
| ST-F-004 | Identity/RBAC rollout playbook | Security / Platform | Backlog | Translate the recommendations in `docs/StateTrace_Acknowledgement_Identity_Options.md` into a runnable playbook (dev seat bootstrap, RBAC switch verification) and link it from this plan and `docs/Security.md`. |
| ST-F-005 | Offline-first verification checklist | Ops | Backlog | Extend `docs/CODEX_SESSION_CHECKLIST.md` / `docs/StateTrace_AI_Agent_Guide.md` so every session records whether it touched Access, downloads, or sanitized data; capture evidence paths (Accdb hash, sanitized log path) in this plan.
| ST-F-006 | Sanitized incident intake grind | Data / Docs | Backlog | Follow `docs/StateTrace_IncidentPostmortem_Intake.md` + kickoff task #2 (`docs/agents/Agent_Kickoff_Tasks.md`) to collect six sanitized incidents, drop them under `Data/Postmortems/<IncidentId>/Sanitized`, and reference the sanitizer reports + tracking rows here. |
| ST-F-007 | NetOps + sanitizer evidence template | Automation | Done - 2025-11-13 | Added `docs/templates/NetOpsLogTemplate.json` + `docs/templates/SanitizationEvidenceTemplate.md` so sessions have ready-made evidence snippets for Plan F guardrails. |
| ST-F-008 | NetOps schema + sample log | Security / Docs | Done - 2025-11-13 | Published the sample NetOps log template referenced above (fields cover timestamp, action, URI, hash, session/task IDs). Integrate into automation hooks + Security doc. |
| ST-F-009 | Online-mode reset automation | Automation | Backlog | Add a helper (or checklist step) that automatically resets `STATETRACE_AGENT_ALLOW_NET/INSTALL` to 0 at the end of every session and records the reset in the session log/task board; surface warnings when env vars remain set. |

## Recent timeline (migrated highlights)
| Date (MT) | Summary | Evidence / Metrics | Source |
|-----------|---------|--------------------|--------|
| 2025-09-30 | ADR 0004 accepted: defined opt-in online dev mode with guardrails (`STATETRACE_AGENT_ALLOW_NET`, `Tools/NetworkGuard.psm1`, `Tools/Bootstrap-DevSeat.ps1`) while keeping runtime offline-first. | ADR captures the dual-mode policy, guardrails, and follow-up tasks to update security docs and prompts. | docs/adr/0004-online-mode-and-tooling.md |
| 2025-10-03 | Identity options scorecard completed; recommended AD-integrated accounts backed by a tightly scoped local fallback for air-gapped installs. | Scoring table, recommendation, and next actions (Access audit table, safeguards) documented. | docs/StateTrace_Acknowledgement_Identity_Options.md |
| 2025-10-03 | Feature-expansion planning required six sanitized postmortems feeding guided troubleshooting content; kickoff tasks now include "Seed tiny sanitized fixtures." | Notes emphasize sanitization automation + runbook template usage before Plan D work. | docs/notes/2025-10-03_feature-expansion.md, docs/agents/Agent_Kickoff_Tasks.md |
| 2025-11-12 | Codex Plan Automation Matrix + session checklist tie Plan F deliverables (NetOps logs, sanitizer evidence, ADR references) to every automation run. | Matrix + checklist call out NetOps logging and sanitized fixture expectations. | docs/CODEX_PLAN_AUTOMATION_MATRIX.md, docs/CODEX_SESSION_CHECKLIST.md |
| 2025-11-13 | Added NetOps log + sanitization evidence templates under `docs/templates/` so sessions can quickly log downloads and redaction proof. | `docs/templates/NetOpsLogTemplate.json`, `docs/templates/SanitizationEvidenceTemplate.md`, Plan F ST-F-007/008 marked done. | docs/templates/NetOpsLogTemplate.json, docs/templates/SanitizationEvidenceTemplate.md |

## Automation hooks
- Enable online mode only after approval: set `STATETRACE_AGENT_ALLOW_NET=1`, `STATETRACE_AGENT_ALLOW_INSTALL=1`, then route downloads via `Import-Module .\Tools\NetworkGuard.psm1; Invoke-AllowedDownload -Uri <url> -Reason <task> -OutPath Downloads\ -PassThru` so the NetOps entry captures URI, hash, and justification (see `docs/templates/NetOpsLogTemplate.json`).
- Provision dev seats with `Tools\Bootstrap-DevSeat.ps1 -Manifest Tools\Bootstrap\ApprovedManifest.json`; attach the manifest + transcript (or NetOps entry) to the session log/task board card.
- Sanitize fixtures via `Tools\Sanitize-PostmortemLogs.ps1 -SourcePath <raw> -DestinationPath Data\Postmortems\<IncidentId>\Sanitized -ReportPath Logs\Sanitization\<IncidentId>.json -RedactPatterns @(...)` before sharing logs; cite the report plus `docs/StateTrace_IncidentPostmortem_Intake.md` row in Plan F updates (use `docs/templates/SanitizationEvidenceTemplate.md` when recording evidence).
- After each online or sanitization action, append the evidence to `docs/agents/sessions/<date>_session-XXXX.md`, include the NetOps JSON path, and link both under the relevant TaskBoard entry. Reset `STATETRACE_AGENT_ALLOW_NET/INSTALL` to 0 and note the command (`Remove-Item Env:STATETRACE_AGENT_ALLOW_*`) in the session log (ST-F-009).
- `pwsh Tools\Invoke-AllChecks.ps1 -SecurityLintOnly` (future ST-F-003 deliverable) once the NetOps/sanitizer lint check exists.

## Telemetry / compliance gates
- Zero `.accdb` or raw log files committed; reviewers must confirm sanitized outputs reference `Tools/Sanitize-PostmortemLogs.ps1` reports.
- Every online session produces `Logs/NetOps/<date>.json` plus a matching entry in `docs/agents/sessions/`; missing logs block merges until resolved.
- Any use of `STATETRACE_AGENT_ALLOW_NET` / `_INSTALL` is reset to `0` (or removed) at the end of the session, and the reset is documented in the plan/task board.
- Identity/RBAC changes require a referenced ADR (or playbook entry) and a rollback plan before landing.
- Sanitized incident intake: `docs/StateTrace_IncidentPostmortem_Intake.md` table updated for each bundle, sanitizer reports stored under `Logs/Sanitization/`, and fixture provenance noted in the session/task board entry.
- Dev-seat manifests + allowed downloads must cite the approved manifest (`Tools/Bootstrap\ApprovedManifest.json`), download hashes, and allowlist rationale per `docs/adr/0004-online-mode-and-tooling.md`.

## References & history
- Policy: `docs/Security.md`, `docs/StateTrace_Acknowledgement_Identity_Options.md`.
- Optional mode ADR: `docs/adr/0004-online-mode-and-tooling.md`.
- Supporting guides: `docs/CODEX_AUTONOMY_PLAN.md`, `docs/CODEX_PLAN_AUTOMATION_MATRIX.md`, `docs/CODEX_SESSION_CHECKLIST.md`, `docs/CODEX_RUNBOOK.md`, `docs/StateTrace_AI_Agent_Guide.md`, `docs/RiskRegister.md`, `docs/StateTrace_IncidentPostmortem_Intake.md`, `docs/agents/Agent_Kickoff_Tasks.md`, `docs/templates/NetOpsLogTemplate.json`, `docs/templates/SanitizationEvidenceTemplate.md`.
- Pending artifacts: online-mode reset helper (ST-F-009).

