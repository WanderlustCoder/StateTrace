# 2025-11-26 – UI capture constraints and workaround

## Problem
- CLI shells here time out after ~14 seconds; launching `Main\MainWindow.ps1` blocks the caller and the process is terminated before interaction is possible.
- The environment appears non-interactive (no visible desktop), so the WPF window cannot be manipulated directly from this session.

## Workaround
- Use the detached launcher to start the UI outside the CLI timeout:
  ```pwsh
  pwsh -NoLogo -File Tools\Launch-MainWindow.ps1 -NoExit
  ```
- Run this from an interactive desktop-capable session (RDP/console). The new `powershell.exe` process keeps the UI open for manual use.

## Next steps (Plan H ST-H-001)
- From an interactive session, follow `docs/runbooks/PlanH_UI_Capture_Local.md` to capture freshness tooltip/help/Interfaces screenshots and emit cache-provider telemetry.
- After capture, publish a readiness-enforced bundle via `Tools\Invoke-PlanHBundle.ps1 -Force` and run `Tools\Invoke-PlanHChecks.ps1` to generate the report.

## Notes
- If still headless, continue using headless helpers for telemetry/summaries, but live screenshots require a desktop session. If allowed, attach via RDP to `powershell.exe` started by `Tools\Launch-MainWindow.ps1`.
