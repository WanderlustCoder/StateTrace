[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$QueueSummaryPaths,

    [Parameter(Mandatory = $true)]
    [string]$IntervalReportPath,

    [double]$GapThresholdSeconds = 60,

    [string]$OutputPath,

    [switch]$PassThru
)

<#
.SYNOPSIS
Correlates queue delay summary metrics with PortBatchReady idle intervals.

.DESCRIPTION
Combines dispatcher queue metrics (QueueDelaySummary JSON) with the interval analysis
from `Tools\Analyze-PortBatchIntervals.ps1` so we can see how long each host waits
and which idle gaps drove the throughput drop. Supply the JSON emitted by
`Tools\Analyze-PortBatchIntervals.ps1 -OutputPath ...` via `-IntervalReportPath`.

.EXAMPLE
pwsh Tools\Analyze-DispatcherGaps.ps1 `
    -QueueSummaryPaths Logs/IngestionMetrics/QueueDelaySummary-20251113-114756-1.json `
    -IntervalReportPath Logs/Reports/PortBatchIntervals-20251113.json `
    -GapThresholdSeconds 60 `
    -OutputPath Logs/Reports/DispatcherGapCorrelation-20251113.md
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolingJsonPath = Join-Path -Path $PSScriptRoot -ChildPath 'ToolingJson.psm1'  
if (Test-Path -LiteralPath $toolingJsonPath) {
    Import-Module -Name $toolingJsonPath -Force
} else {
    throw "ToolingJson module not found at '$toolingJsonPath'."
}

$analyzerStatsPath = Join-Path -Path $PSScriptRoot -ChildPath 'AnalyzerStats.psm1'
if (-not (Get-Command -Name Get-SampleCount -ErrorAction SilentlyContinue)) {
    # LANDMARK: ST-D-003 dispatcher gaps - auto-import AnalyzerStats dependency when missing
    if (Test-Path -LiteralPath $analyzerStatsPath) {
        Import-Module -Name $analyzerStatsPath -Force
    } else {
        throw "AnalyzerStats module not found at '$analyzerStatsPath'."
    }
    if (-not (Get-Command -Name Get-SampleCount -ErrorAction SilentlyContinue)) {
        throw "AnalyzerStats module did not expose Get-SampleCount."
    }
}

function Get-QueueSummary {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Queue summary '$Path' does not exist."
    }
    $resolved = Resolve-Path -LiteralPath $Path
    $summary = Read-ToolingJson -Path $resolved.Path -Label 'Queue summary'
    if (-not $summary) {
        throw "Queue summary '$Path' is empty or invalid."
    }
    $summary | Add-Member -NotePropertyName 'ResolvedPath' -NotePropertyValue $resolved.Path -Force
    return $summary
}

function Get-IntervalReport {
    param([string]$ReportPath)
    if (-not (Test-Path -LiteralPath $ReportPath)) {
        throw "Interval report '$ReportPath' does not exist."
    }
    $report = Read-ToolingJson -Path $ReportPath -Label 'Interval report'
    if (-not $report) {
        throw "Interval report '$ReportPath' is empty or invalid."
    }
    return $report
}

function ConvertTo-IntervalEvents {
    param($Report)

    if ($null -eq $Report) { return @() }

    if ($Report.PSObject -and $Report.PSObject.Properties['Intervals']) {
        $intervals = $Report.Intervals
        if ($intervals -is [array]) { return $intervals }
        return @($intervals)
    }

    if ($Report -is [System.Collections.IEnumerable] -and -not ($Report -is [string])) {
        return @($Report)
    }

    return @($Report)
}

$queueSummaries = foreach ($path in $QueueSummaryPaths) {
    Get-QueueSummary -Path $path
}

$intervalReport = Get-IntervalReport -ReportPath $IntervalReportPath
$intervalEvents = ConvertTo-IntervalEvents -Report $intervalReport

function Select-GapsAboveThreshold {
    param([object[]]$Intervals, [double]$Threshold)
    return $Intervals | Where-Object { $_.GapSeconds -ge $Threshold } | Sort-Object GapSeconds -Descending
}

$gaps = Select-GapsAboveThreshold -Intervals $intervalEvents -Threshold $GapThresholdSeconds

$builder = New-Object System.Collections.Generic.List[string]
$builder.Add("# Dispatcher / PortBatch gap correlation")
$builder.Add("")
$builder.Add("> Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')")
$builder.Add("")
$builder.Add("## Queue summaries")
$builder.Add("")
foreach ($summary in $queueSummaries) {
    $pathDisplay = if ($summary.ResolvedPath) { $summary.ResolvedPath } else { '(unknown)' }
    # LANDMARK: ST-D-003 dispatcher gaps - guard optional SourceTelemetryPath field
    $sourceTelemetry = if ($summary.PSObject.Properties['SourceTelemetryPath'] -and $summary.SourceTelemetryPath) { $summary.SourceTelemetryPath } else { '(unknown)' }
    $builder.Add(('- Summary file: `{0}`' -f $pathDisplay))
    $builder.Add(('  - Source telemetry: `{0}`' -f $sourceTelemetry))

    # LANDMARK: ST-D-003 dispatcher gaps - allow queue summary without Statistics wrapper
    $stats = if ($summary.PSObject.Properties['Statistics']) { $summary.Statistics } else { $summary }
    $sampleCount = Get-SampleCount -Stats $stats -FallbackContainer $summary    
    $builder.Add(('  - Samples: {0}' -f $sampleCount))

    # LANDMARK: ST-D-003 dispatcher gaps - guard optional queue delay stats
    $delayStats = if ($stats.PSObject.Properties['QueueBuildDelayMs']) { $stats.QueueBuildDelayMs } else { $null }
    $durationStats = if ($stats.PSObject.Properties['QueueBuildDurationMs']) { $stats.QueueBuildDurationMs } else { $null }
    if ($delayStats) {
        $builder.Add("  - QueueBuildDelay p95/p99: $($delayStats.P95) ms / $($delayStats.P99) ms")
    }
    if ($durationStats) {
        $builder.Add("  - QueueBuildDuration p95/p99: $($durationStats.P95) ms / $($durationStats.P99) ms")
    }

    # LANDMARK: ST-D-003 dispatcher gaps - guard optional Thresholds payload
    if ($summary.PSObject.Properties['Thresholds'] -and $summary.Thresholds) {
        $builder.Add("  - Thresholds (p95/p99): $($summary.Thresholds.MaximumQueueDelayP95Ms) ms / $($summary.Thresholds.MaximumQueueDelayP99Ms) ms")
    }
}
$builder.Add("")

$builder.Add("## Idle gaps >= $GapThresholdSeconds seconds")
$builder.Add("")
if (-not $gaps -or $gaps.Count -eq 0) {
    $builder.Add("None detected.")
}
else {
    $builder.Add("| Start (UTC) | End (UTC) | Gap seconds | Gap minutes | Start host | End host |")
    $builder.Add("|---|---|---|---|---|---|")
    foreach ($gap in $gaps) {
        $builder.Add("| $($gap.StartTimeUtc) | $($gap.EndTimeUtc) | $($gap.GapSeconds) | $($gap.GapMinutes) | $($gap.StartHost) | $($gap.EndHost) |")
    }
    $largestGap = $gaps | Select-Object -First 1
    if ($largestGap) {
        $builder.Add("")
        $builder.Add("> Largest gap: $($largestGap.GapSeconds) seconds ($($largestGap.GapMinutes) minutes) from $($largestGap.StartHost) ($($largestGap.StartTimeUtc)) to $($largestGap.EndHost) ($($largestGap.EndTimeUtc)).")
        $builder.Add("")
    }
}

if ($OutputPath) {
    $outputDir = Split-Path -Path $OutputPath -Parent
    if (-not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    Set-Content -LiteralPath $OutputPath -Value ($builder -join [Environment]::NewLine) -Encoding utf8
    Write-Host ("Dispatcher gap report written to {0}" -f (Resolve-Path -LiteralPath $OutputPath)) -ForegroundColor DarkCyan
}
else {
    $builder -join [Environment]::NewLine | Write-Host
}

if ($PassThru) {
    return $gaps
}
