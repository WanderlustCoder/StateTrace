# Schedule Verification Run

Use this runbook to create a Windows Task Scheduler job that executes `Tools/Invoke-StateTraceScheduledVerification.ps1` on a nightly cadence and writes verification summaries under `Logs/Verification/`.

## Prerequisites
- PowerShell 5+ with permission to register scheduled tasks.
- Repository cloned locally (script resolves relative paths).
- `Tools/Invoke-StateTraceScheduledVerification.ps1` + `Tools/Schedule-VerificationTask.ps1` committed (Plan G ST-G-009/ST-G-010 deliverables).

## Steps
1. **Preview the task**
   ```powershell
   pwsh Tools/Schedule-VerificationTask.ps1 -TaskName StateTraceVerification `
       -StartTime 03:00 -IncludeTests -DryRun
   ```
   The command prints the underlying `schtasks.exe` invocation without registering anything. Omit `-IncludeTests` for faster runs, but include it for new features/functions that must be validated end-to-end.

2. **Register the task**
   ```powershell
   pwsh Tools/Schedule-VerificationTask.ps1 -TaskName StateTraceVerification `
       -StartTime 03:00 -IncludeTests -Force
   ```
   Supply `-SkipParsing`, `-DisableSharedCacheSnapshot`, `-SharedCacheSnapshotDirectory`, or `-AdditionalArguments` when you need to adjust the verification harness behavior. To validate telemetry bundles, pass `-AdditionalArguments '-TelemetryBundlePath Logs\TelemetryBundles\<bundle> -VerifyTelemetryBundleReadiness'` so the scheduled summary captures the readiness output.

3. **Validate the scheduled task**
   ```powershell
   schtasks /Query /TN StateTraceVerification /V /FO LIST
   ```
   Confirm the `Run As User`, trigger time, and command line.

4. **Test manually (optional)**
   ```powershell
   schtasks /Run /TN StateTraceVerification
   ```
   After the test (or the next scheduled trigger), confirm `Logs/Verification/VerificationSummary-<timestamp>.json`, `Logs/Verification/VerificationSummary-latest.json`, and `Logs/Verification/StateTraceVerification-<timestamp>.log` were created.

## Removal
```powershell
schtasks /Delete /TN StateTraceVerification /F
```

## Documentation updates
- Add the scheduled cadence + latest summary path to the Plan G timeline.
- Update Task Board row ST-G-010 with the task name, schedule, and latest summary file.
- Reference the verification summary path in the session log.
