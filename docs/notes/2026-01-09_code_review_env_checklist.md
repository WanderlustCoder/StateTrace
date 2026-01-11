# Code review environment checklist (2026-01-09)

## Offline-first and data hygiene
- [x] Online mode disabled (`STATETRACE_AGENT_ALLOW_NET` and `STATETRACE_AGENT_ALLOW_INSTALL` are unset).
- [x] No network downloads attempted; if online mode is required, use `Tools/NetworkGuard.psm1` and record NetOps logs.
- [x] No `.accdb` files staged for commit (runtime DBs regenerated under `Data/BOYO/BOYO.accdb` and `Data/WLLS/WLLS.accdb` during pipeline).
- [x] Any raw logs are sanitized before sharing (`Tools/Sanitize-PostmortemLogs.ps1`) or not generated.

## Access usage log
- [x] Record any Access DB paths used during testing (runtime `Data/BOYO/BOYO.accdb`, `Data/WLLS/WLLS.accdb`; Pester `TestDrive` temp `WLLS.accdb`).
- [x] Confirm Access DBs are not staged for commit.

## Tooling prerequisites
- [x] PowerShell 5.x available for target runtime compatibility.
- [x] Repo root commands run from `C:\Users\Werem\Projects\StateTrace`.

## Evidence hygiene
- [x] Evidence artifacts stored under `Logs/` and referenced in the evidence log (console-only Pester summary recorded).
