# CI Smoke (Offline-Friendly)

This document defines the minimum "CI smoke" workflow referenced in Plan K.
The intent is a repeatable, offline-first run that validates:
- pipeline entrypoint health
- verification harness health
- warm-run telemetry generation
- gates (queue summary, diversity, cache diagnostics)
- bundle publishing

## LANDMARK: CI smoke workflow

**Inputs**
- Fixture corpus: tracked Access DBs under `Data/<site>/<site>.accdb` (BOYO/WLLS by default).
- Toolchain: Windows PowerShell 5.1 (primary runner) plus `pwsh` for helper scripts.
- Working directory: repo root.

**Outputs**
- Stored under `Logs/` (IngestionMetrics, Reports, SharedCacheDiagnostics, TelemetryBundles).
- If you want run-scoped output, set `STATETRACE_TELEMETRY_DIR=Logs/CI/<runId>` before running.

## LANDMARK: Commands

### 1) Preflight / bootstrap validation
`Tools\Bootstrap-DevSeat.ps1` is install-only (requires online mode). For offline CI, validate manually:
```powershell
# LANDMARK: Preflight checks
$PSVersionTable.PSVersion
Get-Command Invoke-Pester -ErrorAction Stop
Get-Command powershell.exe -ErrorAction Stop
Get-Command pwsh.exe -ErrorAction Stop
```

### 2) Cold pipeline with telemetry
```powershell
# LANDMARK: CI pipeline
Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs -RunSharedCacheDiagnostics -RunQueueDelayHarness -VerifyTelemetryCompleteness -FailOnTelemetryMissing
```

Capture the latest ingestion metrics path from `Logs/IngestionMetrics/` and record it in the CI log output.

### 3) Verification harness
```powershell
# LANDMARK: CI verification
Tools\Invoke-StateTraceVerification.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs -GenerateSharedCacheDiagnostics -GenerateDiffHotspotReport
```

### 4) Warm-run telemetry (guarded)
```powershell
# LANDMARK: CI warm-run telemetry
Tools\Invoke-WarmRunTelemetry.ps1 -VerboseParsing -ResetExtractedLogs -GenerateDiffHotspotReport
```

### 5) Bundle publish
```powershell
# LANDMARK: CI bundle publish
Tools\Publish-TelemetryBundle.ps1 -BundleName CI-<timestamp> -PlanReferences PlanK,PlanE,PlanG -TaskBoardIds ST-K-006 -Notes "Offline CI smoke artifacts"
```

## LANDMARK: Pass criteria

CI smoke is a pass when:

- [ ] All commands complete with exit code 0.
- [ ] Queue delay summary exists and meets thresholds:
  - p95 <= 120 ms, p99 <= 200 ms
  - non-zero samples
- [ ] Port diversity report exists and passes:
  - max streak <= 8 (or waiver recorded)
- [ ] Shared cache diagnostics exist and pass:
  - SnapshotImported > 0
  - GetHit > GetMiss (for key fixture sites BOYO/WLLS)
- [ ] Warm-run diff hotspot CSV exists (when enabled).
- [ ] Telemetry bundle manifest exists and is readable:
  - `Logs/TelemetryBundles/<bundle>/<Area>/TelemetryBundle.json`

## LANDMARK: Failure handling

On failure:
- The harness must surface the exact input/fixture path that caused the issue.
- The run should emit a summary JSON documenting:
  - failing gate(s)
  - missing artifacts
  - remediation suggestions
- If a run-scoped directory is configured, archive `Logs/CI/<runId>` for triage.
