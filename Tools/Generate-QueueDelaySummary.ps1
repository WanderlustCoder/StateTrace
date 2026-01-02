[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MetricsPath,

    [string]$OutputPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath ('Logs\IngestionMetrics\QueueDelaySummary-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [double]$MaximumQueueDelayP95Ms = 120,

    [double]$MaximumQueueDelayP99Ms = 200,

    [int]$MinimumEventCount = 10
)

<#
.SYNOPSIS
Creates a queue-delay readiness summary from InterfacePortQueueMetrics telemetry.

.DESCRIPTION
Reads newline-delimited telemetry JSON, extracts InterfacePortQueueMetrics events,
computes summary statistics (average, p95, p99, min, max), and emits a summary JSON
matching the format produced by Invoke-StateTraceVerification. This provides a
lightweight alternative when the full verification harness cannot be run.

.EXAMPLE
pwsh Tools\Generate-QueueDelaySummary.ps1 `
    -MetricsPath Logs\IngestionMetrics\2025-11-14.json `
    -OutputPath Logs\IngestionMetrics\QueueDelaySummary-20251114.json
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$statsModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'AnalyzerStats.psm1'
if (Test-Path -LiteralPath $statsModulePath) {
    Import-Module -Name $statsModulePath -Force
} else {
    throw "AnalyzerStats module not found at '$statsModulePath'."
}

if (-not (Test-Path -LiteralPath $MetricsPath)) {
    throw "Metrics file '$MetricsPath' does not exist."
}

$delaySamples = New-Object System.Collections.Generic.List[double]
$durationSamples = New-Object System.Collections.Generic.List[double]

Get-Content -LiteralPath $MetricsPath -ReadCount 500 | ForEach-Object {
    foreach ($line in $_) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $obj = $line | ConvertFrom-Json -ErrorAction Stop
        } catch {
            continue
        }
        if ($obj.EventName -ne 'InterfacePortQueueMetrics') { continue }
        if ($obj.PSObject.Properties.Name -contains 'QueueBuildDelayMs') {
            $delaySamples.Add([double]$obj.QueueBuildDelayMs) | Out-Null
        }
        if ($obj.PSObject.Properties.Name -contains 'QueueBuildDurationMs') {
            $durationSamples.Add([double]$obj.QueueBuildDurationMs) | Out-Null
        }
    }
}

# LANDMARK: Queue delay sample floor - require minimum sample count
if ($delaySamples.Count -lt $MinimumEventCount) {
    throw ("Queue delay summary requires at least {0} sample(s); found {1} in '{2}'." -f $MinimumEventCount, $delaySamples.Count, $MetricsPath)
}

$delayStats = New-SampleStats -Values $delaySamples -Name 'QueueBuildDelayMs' -Percentiles @(50,95,99)
$durationStats = if ($durationSamples.Count -gt 0) {
    New-SampleStats -Values $durationSamples -Name 'QueueBuildDurationMs' -Percentiles @(50,95,99)
} else {
    $null
}

$pass = ($delayStats.P95 -le $MaximumQueueDelayP95Ms) -and ($delayStats.P99 -le $MaximumQueueDelayP99Ms)

$summary = [pscustomobject]@{
    GeneratedAtUtc     = (Get-Date).ToUniversalTime().ToString('o')
    SourceTelemetryPath = (Resolve-Path -LiteralPath $MetricsPath).Path
    Pass               = $pass
    Result             = if ($pass) { 'Pass' } else { 'Fail' }
    Thresholds         = [pscustomobject]@{
        MinimumEventCount      = $MinimumEventCount
        MaximumQueueDelayP95Ms = $MaximumQueueDelayP95Ms
        MaximumQueueDelayP99Ms = $MaximumQueueDelayP99Ms
    }
    Statistics         = [pscustomobject]@{
        SampleCount        = $delaySamples.Count
        QueueBuildDelayMs  = $delayStats
        QueueBuildDurationMs = $durationStats
    }
}

$outputDir = Split-Path -Path $OutputPath -Parent
if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8
Write-Host ("Queue delay summary written to {0}" -f (Resolve-Path -LiteralPath $OutputPath)) -ForegroundColor DarkCyan
