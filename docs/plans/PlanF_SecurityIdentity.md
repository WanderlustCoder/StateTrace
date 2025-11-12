# Plan F – Security, Identity, & Online Mode

## Objective
Keep StateTrace offline-first and Access-backed while providing a documented path for optional online development (guarded downloads, dev seat bootstrapping, RBAC/identity options, and sanitisation tooling).

## Current status (2025-11)
- Security guidelines (`docs/Security.md`) and identity options (`docs/StateTrace_Acknowledgement_Identity_Options.md`) are current.
- Online Dev Mode guardrails exist (environment variables + `Tools/NetworkGuard.psm1` usage) but adoption is inconsistent; Codex autonomy plan now references them directly.
- Sanitisation scripts (`Tools/Sanitize-PostmortemLogs.ps1`) remain the standard for fixture creation.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-F-001 | Document NetOps logging expectations for online mode | Security | Ready | Add concrete steps to `docs/CODEX_AUTONOMY_PLAN.md` and `docs/Security.md`. |
| ST-F-002 | Access scrubber automation | Data | Backlog | Wrap sanitiser script usage into a task board card so nightly sanitised fixtures are reproducible. |

## Recent timeline (migrated highlights)
| Date (MT) | Summary | Evidence / Metrics | Source |
|-----------|---------|--------------------|--------|
| 2025-09-30 | ADR 0004 accepted: defined opt-in online dev mode with guardrails (`STATETRACE_AGENT_ALLOW_NET`, `Tools/NetworkGuard.psm1`, `Tools/Bootstrap-DevSeat.ps1`) while keeping runtime offline-first. | ADR captures the dual-mode policy, guardrails, and follow-up tasks to update security docs and prompts. | docs/adr/0004-online-mode-and-tooling.md |
| 2025-10-03 | Identity options scorecard completed; recommended AD-integrated accounts backed by a tightly scoped local fallback for air-gapped installs. | Scoring table, recommendation, and next actions (Access audit table, safeguards) documented. | docs/StateTrace_Acknowledgement_Identity_Options.md |

## Automation hooks
- Enabling online mode: set `STATETRACE_AGENT_ALLOW_NET=1`, `STATETRACE_AGENT_ALLOW_INSTALL=1`, then call `Tools/NetworkGuard.psm1::Invoke-AllowedDownload` and `Tools/Bootstrap-DevSeat.ps1`.
- Log every net action under `Logs/NetOps/<date>.json` and `docs/agents/sessions/`.

## Telemetry / compliance gates
- Zero `.accdb` or raw log files committed; enforce via pre-commit or review checklist.
- `Logs/NetOps/<date>.json` must exist for any online session.

## References & history
- Policy: `docs/Security.md`, `docs/StateTrace_Acknowledgement_Identity_Options.md`.
- Optional mode ADR: `docs/adr/0004-online-mode-and-tooling.md`.
