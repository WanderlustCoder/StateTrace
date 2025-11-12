# StateTrace UI Smoke Checklist

Use this checklist after parser or UI changes to confirm the WPF shell still renders core views. Run it locally before handing work to another agent or opening a release PR.

## Preconditions
- Refresh data with `pwsh Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs` (or reuse a recent run if nothing changed).
- Ensure the PowerShell session you use to launch the UI points at the repo root.
- Optional: set `$Global:StateTraceDebug = $true` before launching to capture extra diagnostics under `Logs/Debug/`.

## Launch
```pwsh
pwsh -NoLogo -NoProfile -File .\Main\MainWindow.ps1
```
- Verify the host dropdown populates; note the hostname used for the remainder of the checklist.

## Checklist
| Step | What to exercise | Expected result / notes |
|------|------------------|-------------------------|
| Summary tab | Select the target host, confirm device metadata (site/zone/building/room) populates immediately. Trigger `Scan Logs` once to ensure the status strip updates. | Site/zone filters should adjust; status text should show `Ready` after parser refresh. |
| Interfaces tab | Observe incremental loading progress bar + message (`Loading ports…`, `Ports loaded (X)`), then try sorting/filtering. | Rows should appear in batches; sorting should stay responsive; `Get-InterfaceViewSnapshot` (from console) should report row count > 0. |
| Search tab | Toggle Regex mode via `DeviceInsightsModule::Set-SearchRegexEnabled`, run a query, and confirm totals update. | `Logs/Debug/InterfaceDiag.log` should capture the search summary. |
| SPAN tab | Use the UI refresh button, then in another console run `Get-SpanViewSnapshot -IncludeRows -SampleCount 5`. | Snapshot output lists row counts and samples; status label in UI should read `Rows: <count> (Updated <time>)`. |
| Templates tab | Load a template, copy text via the provided button, and confirm no errors surface in the console. | Template preview should appear; clipboard operations should not throw. |
| Alerts tab | Toggle status/auth filters, ensure `$global:AlertsList` updates (inspect via console if needed). | Grid refreshes with new counts; no stale bindings. |
| Compare view | Add two hosts, expand the diff list, and confirm configuration text renders. | `Get-InterfaceConfiguration` lookups should not hit Access once caches are primed. |
| Help dialog | Open Help from the toolbar to ensure secondary windows still resolve their resource dictionaries. | Window opens without XAML binding errors. |

## Headless spot-checks (optional)
- `pwsh -STA -File Tools\Invoke-SpanViewSmokeTest.ps1 -Hostname <host> -PassThru` to validate SPAN binding without the main window.
- `Tools\Invoke-AllChecks.ps1` to run Pester + span smoke test in one command.

## Troubleshooting tips
- Use `Get-EventLog -LogName Application -Newest 20` if the WPF app crashes immediately.
- Attach to the process (`Enter-PSHostProcess -Id <pid>`) and inspect globals (`$global:DeviceInterfaceCache.Keys.Count`) when a view shows zero rows.
- All UI smoke results should be noted in your session log and linked from the relevant plan/task entry.
