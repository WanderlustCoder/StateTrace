# Common Failures and Remedies

This page lists common developer seat and harness failures with concrete remediation steps.
Update it whenever a new failure mode appears more than once.

## LANDMARK: PowerShell execution policy blocks scripts

**Symptoms**
- Script fails with "running scripts is disabled on this system" or similar.

**Fix (CurrentUser)**
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
Get-ExecutionPolicy -List
```

## LANDMARK: Required PowerShell module missing

**Symptoms**
- `Import-Module` fails
- Pester not found
- Harness scripts attempt to `Install-Module` (should not happen in offline mode)

**Fix**
- Ensure the required module is vendored in-repo (preferred), or document the offline source.
- Validate modules with `Get-Module -ListAvailable` before running the harness.
- Use `Tools/Bootstrap-DevSeat.ps1` only when online mode is explicitly approved.

## LANDMARK: Access provider / OLE DB errors

**Symptoms**
- "Provider cannot be found"
- Bitness mismatch errors
- Connection failures when caching Access connections

**Fix**
- Install the correct Access Database Engine (x64 recommended).
- Ensure PowerShell process bitness matches provider.
- Confirm connection string in `docs/schemas/access/Access_DB_Schema.md`.

## LANDMARK: Harness produces empty queue summaries (0 samples)

**Symptoms**
- `QueueDelaySummary` exists but contains 0 samples
- Verification harness flags missing summary sections

**Likely causes**
- Dispatcher sweep order regression
- Fixture set too small / does not exercise paths that emit queue events
- Queue delay harness not executed

**Fix**
- Ensure `Tools/Invoke-StateTracePipeline.ps1` is run with `-RunQueueDelayHarness`.
- Re-run with a clean telemetry directory (`STATETRACE_TELEMETRY_DIR`) to avoid mixed runs.
- Expand the fixture set just enough to trigger the summary.
- Add a unit/integration test asserting non-zero sample counts.

## LANDMARK: Port diversity guard fails (streak > 8)

**Symptoms**
- Warm-run or CI smoke halts with diversity guard failure

**Fix**
- Run `Tools/Test-PortBatchSiteDiversity.ps1 -Path Logs/IngestionMetrics/<file>.json` to confirm the streaks.
- Adjust the fixture set or warm-run host selection to increase site diversity.
- Document the fixture changes in `docs/fixtures/README.md`.
- If temporarily waiving, record the waiver in:
  - the relevant plan page (Plan I/J/K)
  - the Task Board row with a timebox

## LANDMARK: Shared cache diagnostics show unavailable/unknown

**Symptoms**
- Providers report `SharedCacheUnavailable` or `Unknown`
- SnapshotImported is 0

**Fix**
- Confirm snapshot import step exists and runs before diagnostics.
- Validate snapshot directory paths and permissions.
- Run diagnostics via `Tools/Invoke-StateTraceVerification.ps1 -GenerateSharedCacheDiagnostics` and capture the JSON outputs.
- Consider priming with `Tools/Invoke-SharedCacheWarmup.ps1` before the run.

## LANDMARK: Telemetry bundle publish fails or manifest is incomplete

**Symptoms**
- `Publish-TelemetryBundle` errors
- bundle missing `TelemetryBundle.json` or README

**Fix**
- Validate the bundle with `Tools/Test-TelemetryBundleReadiness.ps1`.
- Ensure artifact paths are relative and exist.
- Ensure the bundler records:
  - plan references
  - Task Board IDs
  - run IDs / notes
