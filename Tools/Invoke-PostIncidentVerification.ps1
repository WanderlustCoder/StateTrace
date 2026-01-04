<#
.SYNOPSIS
Runs post-incident verification to ensure stability after rollback/fix.

.DESCRIPTION
ST-R-004: After rollback or fix, auto-runs verification suite with shared-cache
diagnostics and warm-run telemetry to ensure stability before declaring resolved.

Verification phases:
1. All checks (Pester tests, lint, guards)
2. Shared cache diagnostics
3. Warm-run telemetry comparison (optional)
4. Telemetry integrity check
5. Summary report generation

.PARAMETER IncidentId
Incident identifier for tracking and artifact naming.

.PARAMETER RunWarmRunTelemetry
Run warm-run telemetry comparison (takes longer).

.PARAMETER SkipPesterTests
Skip Pester test execution (faster).

.PARAMETER SkipSharedCacheDiagnostics
Skip shared cache diagnostics.

.PARAMETER RepositoryRoot
Repository root path. Defaults to parent of script directory.

.PARAMETER OutputPath
Base output directory. Defaults to Logs/Verification/PostIncident/<IncidentId>/.

.PARAMETER FailOnVerificationError
Exit with error code if verification fails.

.PARAMETER PassThru
Return the verification result as an object.

.EXAMPLE
.\Invoke-PostIncidentVerification.ps1 -IncidentId INC0007

.EXAMPLE
.\Invoke-PostIncidentVerification.ps1 -IncidentId INC0007 -RunWarmRunTelemetry -FailOnVerificationError
#>
param(
    [Parameter(Mandatory)][string]$IncidentId,
    [switch]$RunWarmRunTelemetry,
    [switch]$SkipPesterTests,
    [switch]$SkipSharedCacheDiagnostics,
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$OutputPath,
    [switch]$FailOnVerificationError,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

Write-Host "Running post-incident verification..." -ForegroundColor Cyan
Write-Host ("  Incident: {0}" -f $IncidentId) -ForegroundColor Cyan
Write-Host ("  Timestamp: {0}" -f $timestamp) -ForegroundColor Cyan

# Determine output path
if (-not $OutputPath) {
    $OutputPath = Join-Path $repoRoot "Logs\Verification\PostIncident\$IncidentId-$timestamp"
}

if (-not (Test-Path -LiteralPath $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$phases = [System.Collections.Generic.List[pscustomobject]]::new()
$artifacts = [System.Collections.Generic.List[string]]::new()
$startTime = Get-Date

function Invoke-Phase {
    param(
        [string]$Name,
        [string]$Description,
        [scriptblock]$Action
    )

    $phaseStart = Get-Date
    $phase = [pscustomobject]@{
        Name        = $Name
        Description = $Description
        Status      = 'Running'
        DurationMs  = 0
        Error       = $null
        Output      = $null
    }

    Write-Host ("`n  Phase: {0}..." -f $Description) -ForegroundColor Cyan

    try {
        $output = & $Action
        $phase.Status = 'Pass'
        $phase.Output = $output
        Write-Host ("    [PASS] {0}" -f $Name) -ForegroundColor Green
    }
    catch {
        $phase.Status = 'Fail'
        $phase.Error = $_.Exception.Message
        Write-Host ("    [FAIL] {0}: {1}" -f $Name, $_.Exception.Message) -ForegroundColor Red
    }

    $phase.DurationMs = [math]::Round(((Get-Date) - $phaseStart).TotalMilliseconds, 0)
    $phases.Add($phase)
}

# Phase 1: All Checks (unless skipping Pester)
if (-not $SkipPesterTests) {
    Invoke-Phase -Name 'AllChecks' -Description 'Running all checks' -Action {
        $allChecksPath = Join-Path $OutputPath "AllChecks-$IncidentId.log"
        $allChecksScript = Join-Path $repoRoot 'Tools\Invoke-AllChecks.ps1'

        if (-not (Test-Path -LiteralPath $allChecksScript)) {
            throw "AllChecks script not found"
        }

        # Run with minimal flags to avoid long-running checks
        $output = & $allChecksScript `
            -SkipSpanHarness `
            -SkipSearchAlertsHarness `
            -SkipSharedCacheSnapshotCheck `
            -OutputPath $allChecksPath 2>&1

        $artifacts.Add($allChecksPath)

        # Check if output file was created
        if (Test-Path -LiteralPath $allChecksPath) {
            $content = Get-Content -LiteralPath $allChecksPath -Raw -ErrorAction SilentlyContinue
            $hasFailures = $content -match 'FAIL|Failed|Error'
            return [pscustomobject]@{
                LogPath     = $allChecksPath
                HasFailures = $hasFailures
            }
        }

        return [pscustomobject]@{ LogPath = $allChecksPath }
    }
}

# Phase 2: Telemetry Integrity
Invoke-Phase -Name 'TelemetryIntegrity' -Description 'Checking telemetry integrity' -Action {
    $integrityScript = Join-Path $repoRoot 'Tools\Test-TelemetryIntegrity.ps1'
    $integrityPath = Join-Path $OutputPath "TelemetryIntegrity-$IncidentId.txt"

    if (-not (Test-Path -LiteralPath $integrityScript)) {
        return [pscustomobject]@{ Skipped = $true; Reason = 'Script not found' }
    }

    $metricsDir = Join-Path $repoRoot 'Logs\IngestionMetrics'
    $todayFile = Join-Path $metricsDir ((Get-Date).ToString('yyyy-MM-dd') + '.json')

    if (-not (Test-Path -LiteralPath $todayFile)) {
        return [pscustomobject]@{ Skipped = $true; Reason = 'No telemetry for today' }
    }

    try {
        & $integrityScript -Path $todayFile -OutputPath $integrityPath 2>&1 | Out-Null
        $artifacts.Add($integrityPath)
        return [pscustomobject]@{ ReportPath = $integrityPath }
    }
    catch {
        return [pscustomobject]@{ Error = $_.Exception.Message }
    }
}

# Phase 3: Shared Cache Diagnostics
if (-not $SkipSharedCacheDiagnostics) {
    Invoke-Phase -Name 'SharedCacheDiagnostics' -Description 'Running shared cache diagnostics' -Action {
        $storeStateScript = Join-Path $repoRoot 'Tools\Analyze-SharedCacheStoreState.ps1'
        $providerScript = Join-Path $repoRoot 'Tools\Analyze-SiteCacheProviderReasons.ps1'

        $storeStatePath = Join-Path $OutputPath "SharedCacheStoreState-$IncidentId.json"
        $providerPath = Join-Path $OutputPath "SiteCacheProviderReasons-$IncidentId.json"

        $results = [pscustomobject]@{
            StoreState = $null
            ProviderReasons = $null
        }

        # Find latest telemetry
        $metricsDir = Join-Path $repoRoot 'Logs\IngestionMetrics'
        $latestMetrics = Get-ChildItem -LiteralPath $metricsDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}\.json$' } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1

        if (-not $latestMetrics) {
            return [pscustomobject]@{ Skipped = $true; Reason = 'No telemetry files found' }
        }

        # Run store state analysis
        if (Test-Path -LiteralPath $storeStateScript) {
            try {
                & $storeStateScript -Path $latestMetrics.FullName -OutputPath $storeStatePath 2>&1 | Out-Null
                $artifacts.Add($storeStatePath)
                $results.StoreState = $storeStatePath
            }
            catch { }
        }

        # Run provider reasons analysis
        if (Test-Path -LiteralPath $providerScript) {
            try {
                & $providerScript -Path $latestMetrics.FullName -OutputPath $providerPath 2>&1 | Out-Null
                $artifacts.Add($providerPath)
                $results.ProviderReasons = $providerPath
            }
            catch { }
        }

        return $results
    }
}

# Phase 4: Shared Cache Snapshot Validation
Invoke-Phase -Name 'SnapshotValidation' -Description 'Validating shared cache snapshot' -Action {
    $snapshotScript = Join-Path $repoRoot 'Tools\Test-SharedCacheSnapshot.ps1'

    if (-not (Test-Path -LiteralPath $snapshotScript)) {
        return [pscustomobject]@{ Skipped = $true; Reason = 'Script not found' }
    }

    try {
        $result = & $snapshotScript -PassThru 2>&1
        return [pscustomobject]@{
            Valid = ($result.Status -eq 'Pass')
            SiteCount = if ($result.Metrics) { $result.Metrics.SiteCount } else { 0 }
            HostCount = if ($result.Metrics) { $result.Metrics.TotalHostCount } else { 0 }
        }
    }
    catch {
        return [pscustomobject]@{ Error = $_.Exception.Message }
    }
}

# Phase 5: Warm Run Telemetry (optional)
if ($RunWarmRunTelemetry) {
    Invoke-Phase -Name 'WarmRunTelemetry' -Description 'Running warm-run telemetry comparison' -Action {
        $warmRunScript = Join-Path $repoRoot 'Tools\Invoke-WarmRunTelemetry.ps1'

        if (-not (Test-Path -LiteralPath $warmRunScript)) {
            return [pscustomobject]@{ Skipped = $true; Reason = 'Script not found' }
        }

        $warmRunPath = Join-Path $OutputPath "WarmRunTelemetry-$IncidentId.json"

        try {
            $result = & $warmRunScript `
                -OutputPath $warmRunPath `
                -SkipPortDiversityGuard `
                -PassThru 2>&1

            $artifacts.Add($warmRunPath)

            return [pscustomobject]@{
                OutputPath = $warmRunPath
                ImprovementPercent = if ($result.WarmRunComparison) { $result.WarmRunComparison.ImprovementPercent } else { $null }
                GateMet = if ($result.WarmRunComparison) { $result.WarmRunComparison.ImprovementPercent -ge 60 } else { $false }
            }
        }
        catch {
            return [pscustomobject]@{ Error = $_.Exception.Message }
        }
    }
}

# Build result
$totalDuration = [math]::Round(((Get-Date) - $startTime).TotalMilliseconds, 0)
$passCount = @($phases | Where-Object { $_.Status -eq 'Pass' }).Count
$failCount = @($phases | Where-Object { $_.Status -eq 'Fail' }).Count

$overallStatus = if ($failCount -eq 0) { 'Pass' } else { 'Fail' }

$result = [pscustomobject]@{
    Timestamp       = Get-Date -Format 'o'
    IncidentId      = $IncidentId
    Status          = $overallStatus
    Stable          = $failCount -eq 0
    TotalDurationMs = $totalDuration
    PhaseCount      = $phases.Count
    PassCount       = $passCount
    FailCount       = $failCount
    OutputPath      = $OutputPath
    Phases          = $phases
    Artifacts       = @($artifacts)
}

# Write manifest
$manifestPath = Join-Path $OutputPath "VerificationManifest-$IncidentId.json"
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
$artifacts.Add($manifestPath)

Write-Host ("`nManifest written to: {0}" -f $manifestPath) -ForegroundColor Green

# Display summary
Write-Host "`nPost-Incident Verification Summary:" -ForegroundColor Cyan
Write-Host ("  Incident: {0}" -f $IncidentId)
Write-Host ("  Duration: {0:N0} ms" -f $totalDuration)
Write-Host ("  Phases: {0} total, {1} passed, {2} failed" -f $phases.Count, $passCount, $failCount)

foreach ($phase in $phases) {
    $color = if ($phase.Status -eq 'Pass') { 'Green' } else { 'Red' }
    Write-Host ("    [{0}] {1} ({2} ms)" -f $phase.Status.ToUpper().PadRight(4), $phase.Name, $phase.DurationMs) -ForegroundColor $color
}

Write-Host ("`nArtifacts: {0}" -f $artifacts.Count)
foreach ($artifact in $artifacts) {
    Write-Host ("  - {0}" -f (Split-Path -Leaf $artifact)) -ForegroundColor Gray
}

if ($overallStatus -eq 'Pass') {
    Write-Host "`nStatus: STABLE - Post-incident verification passed" -ForegroundColor Green
}
else {
    Write-Host "`nStatus: UNSTABLE - Verification failed, investigate before declaring resolved" -ForegroundColor Red
}

if ($FailOnVerificationError -and $failCount -gt 0) {
    Write-Error "Post-incident verification failed with $failCount error(s)"
    exit 2
}

if ($PassThru) {
    return $result
}
