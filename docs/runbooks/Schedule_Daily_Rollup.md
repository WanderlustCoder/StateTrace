# Schedule Daily Ingestion Rollups

Use this runbook to create a Windows Task Scheduler job that executes `Tools/Invoke-DailyMetricRollup.ps1` every day and archives the CSV under `Logs/IngestionMetrics/`.

## Prerequisites
- PowerShell 5+ with permission to register scheduled tasks.
- Repository cloned locally (script resolves relative paths).
- `Tools/Invoke-DailyMetricRollup.ps1` committed (Plan E ST-E-002 deliverable).

## Steps
1. **Preview the task**
   ```powershell
   pwsh Tools/Schedule-DailyRollupTask.ps1 -TaskName StateTraceDailyRollup \
       -StartTime 02:00 -DaysBack 1 -DryRun
   ```
   The command prints the underlying `schtasks.exe` invocation without registering anything.

2. **Register the task**
   ```powershell
   pwsh Tools/Schedule-DailyRollupTask.ps1 -TaskName StateTraceDailyRollup \
       -StartTime 02:00 -MetricsDirectory "C:\StateTrace\Logs\IngestionMetrics" \
       -OutputDirectory "C:\StateTrace\Logs\IngestionMetrics" -Force
   ```
   The script wraps `schtasks.exe /Create` and points it at `Invoke-DailyRollup.ps1` with `-Days 1 -IncludePerSite -IncludeSiteCache`.

3. **Validate the scheduled task**
   ```powershell
   schtasks /Query /TN StateTraceDailyRollup /V /FO LIST
   ```
   Confirm the `Run As User`, trigger time, and command line.

4. **Test manually (optional)**
   ```powershell
   schtasks /Run /TN StateTraceDailyRollup
   ```
   After the test, verify `Logs/IngestionMetrics/IngestionMetricsSummary-<timestamp>.csv` exists and update Plan E timeline + Task Board row ST-E-003.

## Removal
```powershell
schtasks /Delete /TN StateTraceDailyRollup /F
```

## Documentation updates
- Add the scheduled cadence + summary path to `docs/plans/PlanE_Telemetry.md` (timeline section).
- Update Task Board row ST-E-003 with the task name / schedule.
- Mention the bundle path inside `docs/StateTrace_TaskBoard.md` row ST-E-007 if the rollup feeds release bundles.
