# Schedule Daily Ingestion Rollups

Use this runbook to create a Windows Task Scheduler job that executes the wrapper (`Tools/Invoke-DailyRollupScheduled.ps1`, which calls `Tools/Invoke-DailyMetricRollup.ps1`) every day and archives the CSV under `Logs/IngestionMetrics/`.

## Prerequisites
- PowerShell 5+ with permission to register scheduled tasks.
- Repository cloned locally (script resolves relative paths).
- `Tools/Invoke-DailyMetricRollup.ps1` + `Tools/Invoke-DailyRollupScheduled.ps1` committed (Plan E ST-E-002/ST-E-003 deliverables).

## Steps
1. **Preview the task**
   ```powershell
   pwsh Tools/Schedule-DailyRollupTask.ps1 -TaskName StateTraceDailyRollup \
       -StartTime 02:00 -DaysBack 1 -DryRun
   ```
   The command prints the underlying `schtasks.exe` invocation without registering anything.

2. **Register the task**
   ```powershell
   pwsh Tools/Schedule-DailyRollupTask.ps1 -TaskName StateTraceDailyRollup `
       -StartTime 02:00 -DaysBack 1 -Force
   ```
   By default the task now runs the wrapper (`Tools/Invoke-DailyRollupScheduled.ps1`) so the scheduled command stays within the Windows 261-character `/TR` limit while still resolving repo-relative `Logs\IngestionMetrics` paths. Supply `-MetricsDirectory` / `-OutputDirectory` if the metrics live elsewhere.

3. **Validate the scheduled task**
   ```powershell
   schtasks /Query /TN StateTraceDailyRollup /V /FO LIST
   ```
   Confirm the `Run As User`, trigger time, and command line.

4. **Test manually (optional)**
   ```powershell
   schtasks /Run /TN StateTraceDailyRollup
   ```
   After the test (or the next scheduled trigger), confirm `Logs/IngestionMetrics/IngestionMetricsSummary-<timestamp>.csv` was created by `Tools/Invoke-DailyRollupScheduled.ps1` and update Plan E timeline + Task Board row ST-E-003 with the timestamp and bundle reference.

## Removal
```powershell
schtasks /Delete /TN StateTraceDailyRollup /F
```

## Documentation updates
- Add the scheduled cadence + summary path to `docs/plans/PlanE_Telemetry.md` (timeline section).
- Update Task Board row ST-E-003 with the task name / schedule.
- Mention the bundle path inside `docs/StateTrace_TaskBoard.md` row ST-E-007 if the rollup feeds release bundles.
