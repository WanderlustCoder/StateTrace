<#
.SYNOPSIS
Runs the dispatcher harness and captures evidence artifacts.

.DESCRIPTION
ST-A-003: Wrapper that calls Tools\Invoke-InterfaceDispatchHarness.ps1 and
ensures evidence is captured to Logs/DispatchHarness/ with standardized naming.

Evidence captured:
- Dispatcher harness JSON output (RoutingQueueSweep-*.json)
- Queue delay summary (QueueDelaySummary-*.json)
- Telemetry metrics snapshot
- Evidence manifest with paths and hashes

.PARAMETER TaskId
Optional task ID for evidence naming (e.g., ST-A-003).

.PARAMETER HarnessMode
Harness mode: Full, Quick, or Diag. Default Full.

.PARAMETER SkipQueueDelaySummary
Skip generating queue delay summary.

.PARAMETER RepositoryRoot
Repository root path. Defaults to parent of script directory.

.PARAMETER OutputPath
Base output directory. Defaults to Logs/DispatchHarness/.

.PARAMETER PassThru
Return the evidence manifest as an object.

.EXAMPLE
.\Invoke-DispatcherHarnessWithEvidence.ps1 -TaskId ST-A-003

.EXAMPLE
.\Invoke-DispatcherHarnessWithEvidence.ps1 -HarnessMode Quick -PassThru
#>
param(
    [string]$TaskId,
    [ValidateSet('Full', 'Quick', 'Diag')]
    [string]$HarnessMode = 'Full',
    [switch]$SkipQueueDelaySummary,
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$OutputPath,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

Write-Host "Running dispatcher harness with evidence capture..." -ForegroundColor Cyan
if ($TaskId) {
    Write-Host ("  Task ID: {0}" -f $TaskId) -ForegroundColor Cyan
}
Write-Host ("  Mode: {0}" -f $HarnessMode) -ForegroundColor Cyan

# Determine output paths
if (-not $OutputPath) {
    $OutputPath = Join-Path $repoRoot 'Logs\DispatchHarness'
}

if (-not (Test-Path -LiteralPath $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$artifacts = [System.Collections.Generic.List[pscustomobject]]::new()
$errors = [System.Collections.Generic.List[string]]::new()
$startTime = Get-Date

# Generate artifact names
$namePrefix = if ($TaskId) { "{0}-{1}" -f $TaskId, $timestamp } else { $timestamp }

# Step 1: Run dispatcher harness
Write-Host "`n  Step 1: Running dispatcher harness..." -ForegroundColor Cyan

$harnessScript = Join-Path $repoRoot 'Tools\Invoke-InterfaceDispatchHarness.ps1'
$harnessOutput = Join-Path $OutputPath ("RoutingQueueSweep-{0}.json" -f $namePrefix)

$harnessResult = $null
if (Test-Path -LiteralPath $harnessScript) {
    try {
        # Note: Dispatcher harness requires -STA mode for WPF APIs
        # We'll check if it exists and document the command
        $harnessParams = @{
            OutputPath = $harnessOutput
        }

        # Check if harness can run (needs WPF/STA)
        $canRunHarness = $true
        if (-not $host.Runspace.ApartmentState -or $host.Runspace.ApartmentState -ne 'STA') {
            Write-Warning "Dispatcher harness requires -STA mode. Documenting command for manual execution."
            $canRunHarness = $false
        }

        if ($canRunHarness) {
            & $harnessScript -OutputPath $harnessOutput 2>&1 | Out-Null
            if (Test-Path -LiteralPath $harnessOutput) {
                $hash = (Get-FileHash -LiteralPath $harnessOutput -Algorithm SHA256).Hash
                $artifacts.Add([pscustomobject]@{
                    Type = 'DispatcherHarness'
                    Path = $harnessOutput
                    Hash = $hash
                })
                Write-Host ("    Created: {0}" -f (Split-Path -Leaf $harnessOutput)) -ForegroundColor Green
            }
        }
        else {
            # Document the command that should be run
            $manualCommand = "powershell.exe -STA -File `"$harnessScript`" -OutputPath `"$harnessOutput`""
            $artifacts.Add([pscustomobject]@{
                Type = 'DispatcherHarnessCommand'
                Command = $manualCommand
                Note = 'Run this command manually in STA mode'
            })
            Write-Host ("    Manual command documented (requires -STA)") -ForegroundColor Yellow
        }
    }
    catch {
        $errors.Add("Dispatcher harness failed: $($_.Exception.Message)")
        Write-Host ("    Error: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
}
else {
    $errors.Add("Dispatcher harness script not found: $harnessScript")
    Write-Host "    Script not found" -ForegroundColor Red
}

# Step 2: Generate queue delay summary
if (-not $SkipQueueDelaySummary) {
    Write-Host "`n  Step 2: Generating queue delay summary..." -ForegroundColor Cyan

    $queueSummaryScript = Join-Path $repoRoot 'Tools\Analyze-QueueDelaySummary.ps1'
    $queueSummaryOutput = Join-Path (Join-Path $repoRoot 'Logs\IngestionMetrics') ("QueueDelaySummary-{0}.json" -f $namePrefix)

    # Find latest telemetry
    $metricsDir = Join-Path $repoRoot 'Logs\IngestionMetrics'
    $latestTelemetry = Get-ChildItem -LiteralPath $metricsDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}\.json$' } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($latestTelemetry -and (Test-Path -LiteralPath $queueSummaryScript)) {
        try {
            & $queueSummaryScript -Path $latestTelemetry.FullName -OutputPath $queueSummaryOutput 2>&1 | Out-Null
            if (Test-Path -LiteralPath $queueSummaryOutput) {
                $hash = (Get-FileHash -LiteralPath $queueSummaryOutput -Algorithm SHA256).Hash
                $artifacts.Add([pscustomobject]@{
                    Type = 'QueueDelaySummary'
                    Path = $queueSummaryOutput
                    Hash = $hash
                })
                Write-Host ("    Created: {0}" -f (Split-Path -Leaf $queueSummaryOutput)) -ForegroundColor Green
            }
        }
        catch {
            # Try alternate approach - check if summary already exists
            $existingSummary = Get-ChildItem -LiteralPath $metricsDir -Filter 'QueueDelaySummary-*.json' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($existingSummary) {
                $artifacts.Add([pscustomobject]@{
                    Type = 'QueueDelaySummary'
                    Path = $existingSummary.FullName
                    Note = 'Using existing summary'
                })
                Write-Host ("    Using existing: {0}" -f $existingSummary.Name) -ForegroundColor Yellow
            }
            else {
                $errors.Add("Queue delay summary generation failed: $($_.Exception.Message)")
            }
        }
    }
    elseif (-not $latestTelemetry) {
        Write-Host "    No telemetry found for summary" -ForegroundColor Yellow
    }
    else {
        Write-Host "    Summary script not found" -ForegroundColor Yellow
    }
}

# Step 3: Capture telemetry snapshot reference
Write-Host "`n  Step 3: Capturing telemetry reference..." -ForegroundColor Cyan

$metricsDir = Join-Path $repoRoot 'Logs\IngestionMetrics'
$latestTelemetry = Get-ChildItem -LiteralPath $metricsDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}\.json$' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($latestTelemetry) {
    $artifacts.Add([pscustomobject]@{
        Type = 'TelemetryReference'
        Path = $latestTelemetry.FullName
        Name = $latestTelemetry.Name
        LastModified = $latestTelemetry.LastWriteTime.ToString('o')
    })
    Write-Host ("    Referenced: {0}" -f $latestTelemetry.Name) -ForegroundColor Green
}

# Step 4: Run queue delay threshold check
Write-Host "`n  Step 4: Running queue delay threshold check..." -ForegroundColor Cyan

$thresholdScript = Join-Path $repoRoot 'Tools\Test-QueueDelayThreshold.ps1'
$thresholdOutput = Join-Path $OutputPath ("QueueDelayThresholdCheck-{0}.json" -f $namePrefix)

if (Test-Path -LiteralPath $thresholdScript) {
    try {
        $thresholdResult = & $thresholdScript -OutputPath $thresholdOutput -PassThru 2>&1
        if (Test-Path -LiteralPath $thresholdOutput) {
            $artifacts.Add([pscustomobject]@{
                Type = 'QueueDelayThresholdCheck'
                Path = $thresholdOutput
                Status = if ($thresholdResult) { $thresholdResult.Status } else { 'Unknown' }
            })
            Write-Host ("    Status: {0}" -f $(if ($thresholdResult) { $thresholdResult.Status } else { 'Unknown' })) -ForegroundColor $(if ($thresholdResult -and $thresholdResult.Status -eq 'Pass') { 'Green' } else { 'Yellow' })
        }
    }
    catch {
        Write-Host ("    Error: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }
}

# Build evidence manifest
$totalDuration = [math]::Round(((Get-Date) - $startTime).TotalMilliseconds, 0)

$manifest = [pscustomobject]@{
    Timestamp      = Get-Date -Format 'o'
    TaskId         = $TaskId
    HarnessMode    = $HarnessMode
    DurationMs     = $totalDuration
    ArtifactCount  = $artifacts.Count
    ErrorCount     = $errors.Count
    Artifacts      = $artifacts
    Errors         = $errors
    Commands       = [pscustomobject]@{
        DispatcherHarness = "powershell.exe -STA -File Tools\Invoke-InterfaceDispatchHarness.ps1 -OutputPath Logs\DispatchHarness\RoutingQueueSweep-<timestamp>.json"
        QueueDelaySummary = "Tools\Analyze-QueueDelaySummary.ps1 -Path Logs\IngestionMetrics\<date>.json -OutputPath Logs\IngestionMetrics\QueueDelaySummary-<timestamp>.json"
        ThresholdCheck    = "Tools\Test-QueueDelayThreshold.ps1 -FailOnThresholdExceeded"
    }
}

# Write manifest
$manifestPath = Join-Path $OutputPath ("EvidenceManifest-{0}.json" -f $namePrefix)
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Write-Host ("`nEvidence manifest written to: {0}" -f $manifestPath) -ForegroundColor Green

# Display summary
Write-Host "`nDispatcher Harness Evidence Summary:" -ForegroundColor Cyan
Write-Host ("  Duration: {0:N0} ms" -f $totalDuration)
Write-Host ("  Artifacts: {0}" -f $artifacts.Count)

foreach ($artifact in $artifacts) {
    $displayPath = if ($artifact.PSObject.Properties.Name -contains 'Path' -and $artifact.Path) { Split-Path -Leaf $artifact.Path } else { $artifact.Type }
    Write-Host ("    - [{0}] {1}" -f $artifact.Type, $displayPath) -ForegroundColor Gray
}

if ($errors.Count -gt 0) {
    Write-Host ("`nErrors: {0}" -f $errors.Count) -ForegroundColor Red
    foreach ($err in $errors) {
        Write-Host ("    - {0}" -f $err) -ForegroundColor Red
    }
}

Write-Host "`nTo run the full dispatcher harness manually:" -ForegroundColor Cyan
Write-Host "  powershell.exe -STA -File Tools\Invoke-InterfaceDispatchHarness.ps1" -ForegroundColor White

if ($PassThru) {
    return $manifest
}
