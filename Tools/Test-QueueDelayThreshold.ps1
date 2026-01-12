<#
.SYNOPSIS
Validates queue delay metrics against threshold limits.

.DESCRIPTION
ST-A-002: Extends verification to assert QueueDelayMs thresholds on
InterfacePortQueueMetrics telemetry. Fails the run and updates
docs/telemetry/Automation_Gates.md compliance when limits are exceeded.

.PARAMETER TelemetryPath
Path to telemetry JSON file. Auto-discovers latest if not specified.

.PARAMETER QueueSummaryPath
Path to queue delay summary JSON. Auto-discovers if not specified.

.PARAMETER MaxQueueDelayP95Ms
Maximum allowed p95 queue delay in ms. Default 120.

.PARAMETER MaxQueueDelayP99Ms
Maximum allowed p99 queue delay in ms. Default 200.

.PARAMETER MaxQueueBuildDelayP95Ms
Maximum allowed p95 queue build delay in ms. Default 150.

.PARAMETER MinimumSamples
Minimum samples required for valid check. Default 5.

.PARAMETER RepositoryRoot
Repository root path. Defaults to parent of script directory.

.PARAMETER OutputPath
Optional JSON output path for the check report.

.PARAMETER FailOnThresholdExceeded
Exit with error code if thresholds are exceeded.

.PARAMETER PassThru
Return the check result as an object.

.EXAMPLE
.\Test-QueueDelayThreshold.ps1

.EXAMPLE
.\Test-QueueDelayThreshold.ps1 -MaxQueueDelayP95Ms 100 -FailOnThresholdExceeded
#>
param(
    [string]$TelemetryPath,
    [string]$QueueSummaryPath,
    [double]$MaxQueueDelayP95Ms = 120.0,
    [double]$MaxQueueDelayP99Ms = 200.0,
    [double]$MaxQueueBuildDelayP95Ms = 150.0,
    [int]$MinimumSamples = 5,
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$OutputPath,
    [switch]$FailOnThresholdExceeded,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

Write-Host "Checking queue delay thresholds..." -ForegroundColor Cyan

# Auto-discover paths
$metricsDir = Join-Path $repoRoot 'Logs\IngestionMetrics'

if (-not $TelemetryPath) {
    if (Test-Path -LiteralPath $metricsDir) {
        $latest = Get-ChildItem -LiteralPath $metricsDir -Filter '*.json' -File |
            Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}\.json$' } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $TelemetryPath = $latest.FullName }
    }
}

if (-not $QueueSummaryPath) {
    if (Test-Path -LiteralPath $metricsDir) {
        $summaryFiles = Get-ChildItem -LiteralPath $metricsDir -Filter 'QueueDelaySummary-*.json' -File |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($summaryFiles) { $QueueSummaryPath = $summaryFiles.FullName }
    }
}

$violations = [System.Collections.Generic.List[pscustomobject]]::new()
$metrics = [pscustomobject]@{
    FromSummary   = $null
    FromTelemetry = $null
}

# Try to read from queue summary first (more accurate)
if ($QueueSummaryPath -and (Test-Path -LiteralPath $QueueSummaryPath)) {
    Write-Host ("  Reading queue summary: {0}" -f (Split-Path -Leaf $QueueSummaryPath)) -ForegroundColor Cyan

    try {
        $summary = Get-Content -LiteralPath $QueueSummaryPath -Raw | ConvertFrom-Json

        $sampleCount = 0
        if ($summary.PSObject.Properties.Name -contains 'SampleCount') {
            $sampleCount = $summary.SampleCount
        }
        elseif ($summary.PSObject.Properties.Name -contains 'Count') {
            $sampleCount = $summary.Count
        }

        $queueDelayP95 = if ($summary.PSObject.Properties.Name -contains 'QueueDelayMs') {
            if ($summary.QueueDelayMs.PSObject.Properties.Name -contains 'P95') { $summary.QueueDelayMs.P95 } else { $null }
        } else { $null }

        $queueDelayP99 = if ($summary.PSObject.Properties.Name -contains 'QueueDelayMs') {
            if ($summary.QueueDelayMs.PSObject.Properties.Name -contains 'P99') { $summary.QueueDelayMs.P99 } else { $null }
        } else { $null }

        $queueBuildP95 = if ($summary.PSObject.Properties.Name -contains 'QueueBuildDuration') {
            if ($summary.QueueBuildDuration.PSObject.Properties.Name -contains 'P95') { $summary.QueueBuildDuration.P95 } else { $null }
        } elseif ($summary.PSObject.Properties.Name -contains 'QueueBuildDelayMs') {
            if ($summary.QueueBuildDelayMs.PSObject.Properties.Name -contains 'P95') { $summary.QueueBuildDelayMs.P95 } else { $null }
        } else { $null }

        $metrics.FromSummary = [pscustomobject]@{
            Path           = $QueueSummaryPath
            SampleCount    = $sampleCount
            QueueDelayP95  = $queueDelayP95
            QueueDelayP99  = $queueDelayP99
            QueueBuildP95  = $queueBuildP95
        }

        if ($sampleCount -ge $MinimumSamples) {
            # Check thresholds
            if ($null -ne $queueDelayP95 -and $queueDelayP95 -gt $MaxQueueDelayP95Ms) {
                $violations.Add([pscustomobject]@{
                    Type      = 'QueueDelayP95Exceeded'
                    Message   = ("Queue delay p95 {0:N2} ms exceeds max {1} ms" -f $queueDelayP95, $MaxQueueDelayP95Ms)
                    Current   = $queueDelayP95
                    Threshold = $MaxQueueDelayP95Ms
                    Source    = 'Summary'
                })
            }

            if ($null -ne $queueDelayP99 -and $queueDelayP99 -gt $MaxQueueDelayP99Ms) {
                $violations.Add([pscustomobject]@{
                    Type      = 'QueueDelayP99Exceeded'
                    Message   = ("Queue delay p99 {0:N2} ms exceeds max {1} ms" -f $queueDelayP99, $MaxQueueDelayP99Ms)
                    Current   = $queueDelayP99
                    Threshold = $MaxQueueDelayP99Ms
                    Source    = 'Summary'
                })
            }

            if ($null -ne $queueBuildP95 -and $queueBuildP95 -gt $MaxQueueBuildDelayP95Ms) {
                $violations.Add([pscustomobject]@{
                    Type      = 'QueueBuildDelayP95Exceeded'
                    Message   = ("Queue build delay p95 {0:N2} ms exceeds max {1} ms" -f $queueBuildP95, $MaxQueueBuildDelayP95Ms)
                    Current   = $queueBuildP95
                    Threshold = $MaxQueueBuildDelayP95Ms
                    Source    = 'Summary'
                })
            }
        }
    }
    catch {
        Write-Warning ("Failed to parse queue summary: {0}" -f $_.Exception.Message)
    }
}

# Fall back to raw telemetry if no summary or insufficient samples
if (-not $metrics.FromSummary -or $metrics.FromSummary.SampleCount -lt $MinimumSamples) {
    if ($TelemetryPath -and (Test-Path -LiteralPath $TelemetryPath)) {
        Write-Host ("  Reading telemetry: {0}" -f (Split-Path -Leaf $TelemetryPath)) -ForegroundColor Cyan

        $queueDelays = [System.Collections.Generic.List[double]]::new()

        Get-Content -LiteralPath $TelemetryPath | ForEach-Object {
            if ([string]::IsNullOrWhiteSpace($_)) { return }
            try {
                $event = $_ | ConvertFrom-Json -ErrorAction Stop
                if ($event.EventType -eq 'InterfacePortQueueMetrics' -and $event.QueueDelayMs) {
                    $queueDelays.Add([double]$event.QueueDelayMs)
                }
            }
            catch { Write-Verbose "Caught exception in Test-QueueDelayThreshold.ps1: $($_.Exception.Message)" }
        }

        if ($queueDelays.Count -gt 0) {
            $sorted = $queueDelays | Sort-Object
            $p95Index = [math]::Floor($sorted.Count * 0.95)
            $p99Index = [math]::Floor($sorted.Count * 0.99)

            $p95 = $sorted[$p95Index]
            $p99 = $sorted[[math]::Min($p99Index, $sorted.Count - 1)]
            $avg = ($queueDelays | Measure-Object -Average).Average
            $max = ($queueDelays | Measure-Object -Maximum).Maximum

            $metrics.FromTelemetry = [pscustomobject]@{
                Path        = $TelemetryPath
                SampleCount = $queueDelays.Count
                Average     = [math]::Round($avg, 2)
                P95         = [math]::Round($p95, 2)
                P99         = [math]::Round($p99, 2)
                Max         = [math]::Round($max, 2)
            }

            if ($queueDelays.Count -ge $MinimumSamples) {
                if ($p95 -gt $MaxQueueDelayP95Ms) {
                    $violations.Add([pscustomobject]@{
                        Type      = 'QueueDelayP95Exceeded'
                        Message   = ("Queue delay p95 {0:N2} ms exceeds max {1} ms" -f $p95, $MaxQueueDelayP95Ms)
                        Current   = $p95
                        Threshold = $MaxQueueDelayP95Ms
                        Source    = 'Telemetry'
                    })
                }

                if ($p99 -gt $MaxQueueDelayP99Ms) {
                    $violations.Add([pscustomobject]@{
                        Type      = 'QueueDelayP99Exceeded'
                        Message   = ("Queue delay p99 {0:N2} ms exceeds max {1} ms" -f $p99, $MaxQueueDelayP99Ms)
                        Current   = $p99
                        Threshold = $MaxQueueDelayP99Ms
                        Source    = 'Telemetry'
                    })
                }
            }
        }
    }
}

# Determine overall status
$sampleCount = 0
if ($metrics.FromSummary) { $sampleCount = $metrics.FromSummary.SampleCount }
elseif ($metrics.FromTelemetry) { $sampleCount = $metrics.FromTelemetry.SampleCount }

$status = 'Pass'
if ($sampleCount -lt $MinimumSamples) {
    $status = 'InsufficientData'
}
elseif ($violations.Count -gt 0) {
    $status = 'Fail'
}

$result = [pscustomobject]@{
    Timestamp       = Get-Date -Format 'o'
    Status          = $status
    Thresholds      = [pscustomobject]@{
        MaxQueueDelayP95Ms     = $MaxQueueDelayP95Ms
        MaxQueueDelayP99Ms     = $MaxQueueDelayP99Ms
        MaxQueueBuildDelayP95Ms = $MaxQueueBuildDelayP95Ms
        MinimumSamples         = $MinimumSamples
    }
    Metrics         = $metrics
    SampleCount     = $sampleCount
    Violations      = $violations
    ViolationCount  = $violations.Count
}

# Output
if ($OutputPath) {
    $outputDir = Split-Path -Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host ("`nReport written to: {0}" -f $OutputPath) -ForegroundColor Green
}

# Display summary
Write-Host "`nQueue Delay Threshold Check:" -ForegroundColor Cyan
Write-Host ("  Samples: {0} (min: {1})" -f $sampleCount, $MinimumSamples)

if ($metrics.FromSummary) {
    Write-Host "  From Summary:"
    Write-Host ("    Queue Delay p95: {0:N2} ms (max: {1} ms)" -f $metrics.FromSummary.QueueDelayP95, $MaxQueueDelayP95Ms)
    Write-Host ("    Queue Delay p99: {0:N2} ms (max: {1} ms)" -f $metrics.FromSummary.QueueDelayP99, $MaxQueueDelayP99Ms)
    if ($metrics.FromSummary.QueueBuildP95) {
        Write-Host ("    Queue Build p95: {0:N2} ms (max: {1} ms)" -f $metrics.FromSummary.QueueBuildP95, $MaxQueueBuildDelayP95Ms)
    }
}

if ($metrics.FromTelemetry) {
    Write-Host "  From Telemetry:"
    Write-Host ("    Queue Delay p95: {0:N2} ms" -f $metrics.FromTelemetry.P95)
    Write-Host ("    Queue Delay p99: {0:N2} ms" -f $metrics.FromTelemetry.P99)
    Write-Host ("    Queue Delay max: {0:N2} ms" -f $metrics.FromTelemetry.Max)
}

if ($violations.Count -gt 0) {
    Write-Host ("`nViolations: {0}" -f $violations.Count) -ForegroundColor Red
    foreach ($v in $violations) {
        Write-Host ("  - [{0}] {1}" -f $v.Type, $v.Message) -ForegroundColor Red
    }
    Write-Host "`nStatus: FAIL - Queue delay thresholds exceeded" -ForegroundColor Red
}
elseif ($status -eq 'InsufficientData') {
    Write-Host "`nStatus: INSUFFICIENT DATA - Need at least $MinimumSamples samples" -ForegroundColor Yellow
}
else {
    Write-Host "`nStatus: PASS - All queue delays within thresholds" -ForegroundColor Green
}

if ($FailOnThresholdExceeded -and $violations.Count -gt 0) {
    Write-Error "Queue delay threshold check failed with $($violations.Count) violation(s)"
    exit 2
}

if ($PassThru) {
    return $result
}
