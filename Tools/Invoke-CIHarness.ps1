[CmdletBinding()]
param(
    [string]$RunId,

    [switch]$SkipPester,

    [switch]$SkipDecomposition,

    [switch]$SkipPipeline,

    [switch]$SkipWarmRun,

    [switch]$SkipBundle,

    [switch]$FailOnMissing,

    [int]$TimeoutMinutes = 20,

    [string]$OutputRoot,

    # ST-N-002: Generate session log stub after run
    [switch]$GenerateSessionLog,

    [string[]]$TaskIds,

    [string[]]$PlanReferences,

    [switch]$PassThru
)

<#
.SYNOPSIS
Minimal offline CI harness for StateTrace (ST-K-001).

.DESCRIPTION
Single entrypoint that runs:
1. Pester smoke tests (Modules/Tests -Tag Smoke)
2. Decomposition/MicroBench tests (Modules/Tests -Tag Decomposition)
3. Pipeline on minimal fixture set
4. Warm-run telemetry with diff hotspot report
5. Bundle artifacts via Publish-TelemetryBundle

Emits all artifacts under Logs/CI/<RunId>/ and fails if required
telemetry (queue summary, diversity, shared-cache diagnostics) is missing.

Compatible with PowerShell 5.1 and 7.

.PARAMETER RunId
CI run identifier. Defaults to CI-<timestamp>.

.PARAMETER SkipPester
Skip Pester smoke tests.

.PARAMETER SkipDecomposition
Skip Decomposition/MicroBench tests (parser persistence, diff layer gates).

.PARAMETER SkipPipeline
Skip pipeline execution.

.PARAMETER SkipWarmRun
Skip warm-run telemetry.

.PARAMETER SkipBundle
Skip artifact bundling.

.PARAMETER FailOnMissing
Exit with error if required telemetry artifacts are missing.

.PARAMETER TimeoutMinutes
Maximum time for CI run. Defaults to 20 minutes.

.PARAMETER OutputRoot
Root directory for CI artifacts. Defaults to Logs/CI.

.PARAMETER GenerateSessionLog
ST-N-002: Generate a session log stub under docs/agents/sessions/ with commands,
artifact paths, and plan/task references.

.PARAMETER TaskIds
Task IDs to include in the session log (e.g., ST-K-001, ST-E-002).

.PARAMETER PlanReferences
Plan references to include in the session log (e.g., PlanK, PlanE).

.PARAMETER PassThru
Return the CI result as an object.

.EXAMPLE
pwsh Tools\Invoke-CIHarness.ps1 -FailOnMissing

.EXAMPLE
pwsh Tools\Invoke-CIHarness.ps1 -GenerateSessionLog -TaskIds ST-K-001 -PlanReferences PlanK,PlanE

.EXAMPLE
pwsh Tools\Invoke-CIHarness.ps1 -SkipWarmRun -RunId CI-smoke-20260104
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$startTime = Get-Date

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "CI-$timestamp"
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path -Path $repositoryRoot -ChildPath 'Logs\CI'
}

$runOutputDir = Join-Path -Path $OutputRoot -ChildPath $RunId

# Initialize result
$result = [pscustomobject]@{
    GeneratedAtUtc       = (Get-Date).ToUniversalTime().ToString('o')
    RunId                = $RunId
    PowerShellVersion    = $PSVersionTable.PSVersion.ToString()
    OutputDirectory      = $runOutputDir
    StartTimeUtc         = $startTime.ToUniversalTime().ToString('o')
    EndTimeUtc           = $null
    DurationMinutes      = 0
    TimeoutMinutes       = $TimeoutMinutes
    Phases               = @()
    RequiredArtifacts    = @()
    MissingArtifacts     = @()
    BundlePath           = $null
    OverallStatus        = 'Unknown'
    Message              = ''
}

# Helper to add phase result
function Add-PhaseResult {
    param(
        [string]$Name,
        [string]$Status,
        [double]$DurationSeconds,
        [string]$Message,
        [string[]]$Artifacts
    )

    $phase = [pscustomobject]@{
        Name            = $Name
        Status          = $Status
        DurationSeconds = [math]::Round($DurationSeconds, 2)
        Message         = $Message
        Artifacts       = if ($Artifacts) { $Artifacts } else { @() }
    }

    $script:result.Phases += $phase

    $color = switch ($Status) {
        'Pass' { 'Green' }
        'Fail' { 'Red' }
        'Skip' { 'Yellow' }
        default { 'DarkGray' }
    }

    Write-Host ("  [{0}] {1} ({2:N1}s): {3}" -f $Status, $Name, $DurationSeconds, $Message) -ForegroundColor $color
}

Write-Host "`n=== CI Harness (ST-K-001) ===" -ForegroundColor Cyan
Write-Host ("Run ID: {0}" -f $RunId) -ForegroundColor DarkGray
Write-Host ("PowerShell: {0}" -f $PSVersionTable.PSVersion) -ForegroundColor DarkGray
Write-Host ("Timeout: {0} minutes" -f $TimeoutMinutes) -ForegroundColor DarkGray
Write-Host ("Output: {0}" -f $runOutputDir) -ForegroundColor DarkGray
Write-Host ""

# Create output directory
if (-not (Test-Path -LiteralPath $runOutputDir)) {
    New-Item -ItemType Directory -Path $runOutputDir -Force | Out-Null
}

# Check timeout helper
function Test-Timeout {
    $elapsed = (Get-Date) - $startTime
    return $elapsed.TotalMinutes -ge $TimeoutMinutes
}

Write-Host "--- Running CI Phases ---" -ForegroundColor Yellow

# Phase 1: Pester Smoke Tests
if (-not $SkipPester.IsPresent) {
    $phaseStart = Get-Date
    $pesterLog = Join-Path -Path $runOutputDir -ChildPath 'PesterSmoke.log'

    try {
        Write-Host "  Running Pester smoke tests..." -ForegroundColor DarkCyan

        $pesterArgs = @{
            Script = Join-Path -Path $repositoryRoot -ChildPath 'Modules\Tests'
            Tag = 'Smoke'
            PassThru = $true
        }

        # Capture output to log
        $pesterResult = Invoke-Pester @pesterArgs 2>&1 | Tee-Object -FilePath $pesterLog

        $pesterDuration = ((Get-Date) - $phaseStart).TotalSeconds
        $passed = ($pesterResult | Where-Object { $_ -is [Pester.OutputTypes.TestResult] -and $_.Passed }).Count
        $failed = ($pesterResult | Where-Object { $_ -is [Pester.OutputTypes.TestResult] -and -not $_.Passed }).Count

        if ($failed -eq 0) {
            Add-PhaseResult -Name 'Pester Smoke' -Status 'Pass' -DurationSeconds $pesterDuration `
                -Message "All tests passed" -Artifacts @($pesterLog)
        } else {
            Add-PhaseResult -Name 'Pester Smoke' -Status 'Fail' -DurationSeconds $pesterDuration `
                -Message "$failed test(s) failed" -Artifacts @($pesterLog)
        }
    } catch {
        $pesterDuration = ((Get-Date) - $phaseStart).TotalSeconds
        Add-PhaseResult -Name 'Pester Smoke' -Status 'Fail' -DurationSeconds $pesterDuration `
            -Message $_.Exception.Message -Artifacts @($pesterLog)
    }
} else {
    Add-PhaseResult -Name 'Pester Smoke' -Status 'Skip' -DurationSeconds 0 -Message 'Skipped by parameter'
}

if (Test-Timeout) {
    $result.OverallStatus = 'Timeout'
    $result.Message = 'CI run exceeded timeout after Pester phase'
    Write-Warning $result.Message
} else {

    # Phase 1.5: Decomposition/MicroBench Tests (ST-L-005)
    if (-not $SkipDecomposition.IsPresent) {
        $phaseStart = Get-Date
        $decompositionLog = Join-Path -Path $runOutputDir -ChildPath 'Decomposition.log'

        try {
            Write-Host "  Running Decomposition/MicroBench tests..." -ForegroundColor DarkCyan

            $pesterArgs = @{
                Script = Join-Path -Path $repositoryRoot -ChildPath 'Modules\Tests'
                Tag = 'Decomposition'
                PassThru = $true
            }

            # Capture output to log
            $pesterResult = Invoke-Pester @pesterArgs 2>&1 | Tee-Object -FilePath $decompositionLog

            $decompositionDuration = ((Get-Date) - $phaseStart).TotalSeconds
            $passed = ($pesterResult | Where-Object { $_ -is [Pester.OutputTypes.TestResult] -and $_.Passed }).Count
            $failed = ($pesterResult | Where-Object { $_ -is [Pester.OutputTypes.TestResult] -and -not $_.Passed }).Count

            if ($failed -eq 0) {
                Add-PhaseResult -Name 'Decomposition Tests' -Status 'Pass' -DurationSeconds $decompositionDuration `
                    -Message "All tests passed" -Artifacts @($decompositionLog)
            } else {
                Add-PhaseResult -Name 'Decomposition Tests' -Status 'Fail' -DurationSeconds $decompositionDuration `
                    -Message "$failed test(s) failed" -Artifacts @($decompositionLog)
            }
        } catch {
            $decompositionDuration = ((Get-Date) - $phaseStart).TotalSeconds
            Add-PhaseResult -Name 'Decomposition Tests' -Status 'Fail' -DurationSeconds $decompositionDuration `
                -Message $_.Exception.Message -Artifacts @($decompositionLog)
        }
    } else {
        Add-PhaseResult -Name 'Decomposition Tests' -Status 'Skip' -DurationSeconds 0 -Message 'Skipped by parameter'
    }

    if (Test-Timeout) {
        $result.OverallStatus = 'Timeout'
        $result.Message = 'CI run exceeded timeout after Decomposition phase'
        Write-Warning $result.Message
    } else {

    # Phase 2: Pipeline
    if (-not $SkipPipeline.IsPresent) {
        $phaseStart = Get-Date
        $pipelineLog = Join-Path -Path $runOutputDir -ChildPath 'Pipeline.log'

        try {
            Write-Host "  Running pipeline..." -ForegroundColor DarkCyan

            $pipelineScript = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-StateTracePipeline.ps1'
            $pipelineArgs = @(
                '-SkipTests',
                '-VerboseParsing',
                '-RunSharedCacheDiagnostics'
            )

            & $pipelineScript @pipelineArgs 2>&1 | Tee-Object -FilePath $pipelineLog

            $pipelineDuration = ((Get-Date) - $phaseStart).TotalSeconds

            if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
                Add-PhaseResult -Name 'Pipeline' -Status 'Pass' -DurationSeconds $pipelineDuration `
                    -Message 'Pipeline completed' -Artifacts @($pipelineLog)
            } else {
                Add-PhaseResult -Name 'Pipeline' -Status 'Fail' -DurationSeconds $pipelineDuration `
                    -Message "Exit code: $LASTEXITCODE" -Artifacts @($pipelineLog)
            }
        } catch {
            $pipelineDuration = ((Get-Date) - $phaseStart).TotalSeconds
            Add-PhaseResult -Name 'Pipeline' -Status 'Fail' -DurationSeconds $pipelineDuration `
                -Message $_.Exception.Message -Artifacts @($pipelineLog)
        }
    } else {
        Add-PhaseResult -Name 'Pipeline' -Status 'Skip' -DurationSeconds 0 -Message 'Skipped by parameter'
    }
}

if (-not (Test-Timeout) -and $result.OverallStatus -ne 'Timeout') {

    # Phase 3: Warm Run
    if (-not $SkipWarmRun.IsPresent) {
        $phaseStart = Get-Date
        $warmRunOutput = Join-Path -Path $runOutputDir -ChildPath 'WarmRunTelemetry.json'
        $warmRunLog = Join-Path -Path $runOutputDir -ChildPath 'WarmRun.log'

        try {
            Write-Host "  Running warm-run telemetry..." -ForegroundColor DarkCyan

            $warmRunScript = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-WarmRunTelemetry.ps1'
            $warmRunArgs = @(
                '-GenerateDiffHotspotReport',
                '-OutputPath', $warmRunOutput
            )

            & $warmRunScript @warmRunArgs 2>&1 | Tee-Object -FilePath $warmRunLog

            $warmRunDuration = ((Get-Date) - $phaseStart).TotalSeconds

            if (Test-Path -LiteralPath $warmRunOutput) {
                Add-PhaseResult -Name 'Warm Run' -Status 'Pass' -DurationSeconds $warmRunDuration `
                    -Message 'Telemetry generated' -Artifacts @($warmRunOutput, $warmRunLog)
            } else {
                Add-PhaseResult -Name 'Warm Run' -Status 'Fail' -DurationSeconds $warmRunDuration `
                    -Message 'Output file not created' -Artifacts @($warmRunLog)
            }
        } catch {
            $warmRunDuration = ((Get-Date) - $phaseStart).TotalSeconds
            Add-PhaseResult -Name 'Warm Run' -Status 'Fail' -DurationSeconds $warmRunDuration `
                -Message $_.Exception.Message -Artifacts @($warmRunLog)
        }
    } else {
        Add-PhaseResult -Name 'Warm Run' -Status 'Skip' -DurationSeconds 0 -Message 'Skipped by parameter'
    }
}

# Phase 4: Verify Required Artifacts
Write-Host ""
Write-Host "--- Verifying Required Artifacts ---" -ForegroundColor Yellow

$requiredArtifacts = @(
    @{ Name = 'Queue Summary'; Pattern = 'Logs\IngestionMetrics\QueueDelaySummary*.json' }
    @{ Name = 'Shared Cache State'; Pattern = 'Logs\IngestionMetrics\SharedCacheStoreState*.json' }
    @{ Name = 'Site Cache Providers'; Pattern = 'Logs\IngestionMetrics\SiteCacheProviderReasons*.json' }
    @{ Name = 'Port Batch Ready'; Pattern = 'Logs\Reports\PortBatchReady*.json' }
)

foreach ($artifact in $requiredArtifacts) {
    $fullPattern = Join-Path -Path $repositoryRoot -ChildPath $artifact.Pattern
    $matches = Get-ChildItem -Path $fullPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    $artifactResult = [pscustomobject]@{
        Name = $artifact.Name
        Pattern = $artifact.Pattern
        Found = $null -ne $matches
        Path = if ($matches) { $matches.FullName } else { $null }
    }

    $result.RequiredArtifacts += $artifactResult

    if ($matches) {
        Write-Host ("  [FOUND] {0}: {1}" -f $artifact.Name, $matches.Name) -ForegroundColor Green
    } else {
        Write-Host ("  [MISSING] {0}" -f $artifact.Name) -ForegroundColor Yellow
        $result.MissingArtifacts += $artifact.Name
    }
}

# Phase 5: Bundle (optional)
if (-not $SkipBundle.IsPresent -and $result.MissingArtifacts.Count -eq 0) {
    $phaseStart = Get-Date

    try {
        Write-Host ""
        Write-Host "  Creating telemetry bundle..." -ForegroundColor DarkCyan

        $bundleScript = Join-Path -Path $PSScriptRoot -ChildPath 'Publish-TelemetryBundle.ps1'
        $bundleArgs = @{
            BundleName = $RunId
            PlanReferences = @('PlanK', 'PlanE', 'PlanG')
            Notes = "CI harness run $RunId"
            PassThru = $true
        }

        $bundleResult = & $bundleScript @bundleArgs

        $bundleDuration = ((Get-Date) - $phaseStart).TotalSeconds

        if ($bundleResult -and $bundleResult.BundlePath) {
            $result.BundlePath = $bundleResult.BundlePath
            Add-PhaseResult -Name 'Bundle' -Status 'Pass' -DurationSeconds $bundleDuration `
                -Message 'Bundle created' -Artifacts @($bundleResult.BundlePath)
        } else {
            Add-PhaseResult -Name 'Bundle' -Status 'Fail' -DurationSeconds $bundleDuration `
                -Message 'Bundle creation returned no path'
        }
    } catch {
        $bundleDuration = ((Get-Date) - $phaseStart).TotalSeconds
        Add-PhaseResult -Name 'Bundle' -Status 'Fail' -DurationSeconds $bundleDuration `
            -Message $_.Exception.Message
    }
} elseif ($SkipBundle.IsPresent) {
    Add-PhaseResult -Name 'Bundle' -Status 'Skip' -DurationSeconds 0 -Message 'Skipped by parameter'
} else {
    Add-PhaseResult -Name 'Bundle' -Status 'Skip' -DurationSeconds 0 `
        -Message "Skipped due to missing artifacts: $($result.MissingArtifacts -join ', ')"
}

# Finalize
$endTime = Get-Date
$result.EndTimeUtc = $endTime.ToUniversalTime().ToString('o')
$result.DurationMinutes = [math]::Round(($endTime - $startTime).TotalMinutes, 2)

$failedPhases = $result.Phases | Where-Object { $_.Status -eq 'Fail' }

if ($result.OverallStatus -eq 'Timeout') {
    # Already set
} elseif ($failedPhases.Count -gt 0) {
    $result.OverallStatus = 'Fail'
    $result.Message = "{0} phase(s) failed: {1}" -f $failedPhases.Count, ($failedPhases.Name -join ', ')
} elseif ($result.MissingArtifacts.Count -gt 0 -and $FailOnMissing.IsPresent) {
    $result.OverallStatus = 'Fail'
    $result.Message = "Missing required artifacts: $($result.MissingArtifacts -join ', ')"
} elseif ($result.MissingArtifacts.Count -gt 0) {
    $result.OverallStatus = 'Warning'
    $result.Message = "Completed with missing artifacts: $($result.MissingArtifacts -join ', ')"
} else {
    $result.OverallStatus = 'Pass'
    $result.Message = "All phases completed successfully in $($result.DurationMinutes) minutes"
}

# Save result
$resultPath = Join-Path -Path $runOutputDir -ChildPath 'CIHarness.json'
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding utf8

# ST-N-002: Generate session log stub if requested
if ($GenerateSessionLog.IsPresent) {
    $sessionLogScript = Join-Path -Path $PSScriptRoot -ChildPath 'New-SessionLogStub.ps1'
    if (Test-Path -LiteralPath $sessionLogScript) {
        $artifactList = @($resultPath)
        if ($result.BundlePath) { $artifactList += $result.BundlePath }
        foreach ($phase in $result.Phases) {
            if ($phase.Artifacts) { $artifactList += $phase.Artifacts }
        }

        $sessionArgs = @{
            Role = 'Automation'
            Commands = @("Invoke-CIHarness.ps1 -RunId $RunId")
            ArtifactPaths = $artifactList
            Notes = "CI harness run completed: $($result.OverallStatus)"
        }
        if ($TaskIds) { $sessionArgs.TaskIds = $TaskIds }
        if ($PlanReferences) { $sessionArgs.PlanReferences = $PlanReferences }

        $sessionResult = & $sessionLogScript @sessionArgs -PassThru
        $result.SessionLogPath = $sessionResult.OutputPath
        Write-Host ("  Session log: {0}" -f $sessionResult.OutputPath) -ForegroundColor DarkCyan
    }
}

Write-Host ""
Write-Host "--- CI Summary ---" -ForegroundColor Yellow
Write-Host ("  Status: {0}" -f $result.OverallStatus) -ForegroundColor $(if ($result.OverallStatus -eq 'Pass') { 'Green' } elseif ($result.OverallStatus -eq 'Fail') { 'Red' } else { 'Yellow' })
Write-Host ("  Duration: {0:N1} minutes" -f $result.DurationMinutes)
Write-Host ("  Phases: {0} pass, {1} fail, {2} skip" -f `
    ($result.Phases | Where-Object { $_.Status -eq 'Pass' }).Count,
    ($result.Phases | Where-Object { $_.Status -eq 'Fail' }).Count,
    ($result.Phases | Where-Object { $_.Status -eq 'Skip' }).Count)
if ($result.BundlePath) {
    Write-Host ("  Bundle: {0}" -f $result.BundlePath) -ForegroundColor Green
}
Write-Host ("  Report: {0}" -f $resultPath) -ForegroundColor DarkCyan
Write-Host ""

if ($PassThru.IsPresent) {
    return $result
}

if ($result.OverallStatus -eq 'Fail') {
    exit 1
}
