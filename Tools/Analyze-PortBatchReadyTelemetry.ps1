[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [switch]$IncludeHostBreakdown,

    [string]$OutputPath,

    [string]$BaselineSummaryPath,

    [switch]$PassThru
)

<#
.SYNOPSIS
Summarises incremental-loading telemetry (PortBatchReady + InterfaceSyncTiming events).

.DESCRIPTION
Scans one or more ingestion-metrics JSON files (newline-delimited) and produces aggregate
statistics that describe incremental loading throughput: batch counts, host coverage,
ports per minute, batch interval percentiles, and key InterfaceSyncTiming durations (`UiClone`,
`StreamDispatch`, `DiffDuration`). Use `-IncludeHostBreakdown` to view per-host batch counts/ports.

.EXAMPLE
pwsh Tools\Analyze-PortBatchReadyTelemetry.ps1 -Path Logs\IngestionMetrics\2025-11-13.json `
    -IncludeHostBreakdown -OutputPath Logs\Reports\PortBatchReady-20251113.json
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$statsModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'AnalyzerStats.psm1'
if (Test-Path -LiteralPath $statsModulePath) {
    Import-Module -Name $statsModulePath -Force
} else {
    throw "AnalyzerStats module not found at '$statsModulePath'."
}

$toolingJsonPath = Join-Path -Path $PSScriptRoot -ChildPath 'ToolingJson.psm1'
if (Test-Path -LiteralPath $toolingJsonPath) {
    Import-Module -Name $toolingJsonPath -Force
} else {
    throw "ToolingJson module not found at '$toolingJsonPath'."
}

function Get-TargetFiles {
    param([string]$InputPath)
    if (-not (Test-Path -LiteralPath $InputPath)) {
        throw "Path '$InputPath' does not exist."
    }

    $item = Get-Item -LiteralPath $InputPath
    if ($item -is [System.IO.DirectoryInfo]) {
        $files = Get-ChildItem -LiteralPath $item.FullName -Filter '*.json' -File | Sort-Object FullName
        if (-not $files) { throw "Directory '$($item.FullName)' does not contain any JSON files." }
        return $files.FullName
    }
    elseif ($item -is [System.IO.FileInfo]) {
        if ($item.Extension -notin '.json') {
            Write-Warning ("File '{0}' does not have a .json extension, attempting to read anyway." -f $item.FullName)
        }
        return @($item.FullName)
    }
    else {
        throw "Unsupported path type for '$InputPath'."
    }
}

$files = Get-TargetFiles -InputPath $Path

$portEventCount = 0
$totalPorts = 0
$totalChunk = 0
$hostStats = @{}
$timestamps = New-Object System.Collections.Generic.List[datetime]
$batchIntervals = New-Object System.Collections.Generic.List[double]
$lastBatchTimestamp = $null

$uiCloneDurations = New-Object System.Collections.Generic.List[double]
$streamDispatchDurations = New-Object System.Collections.Generic.List[double]
$diffDurations = New-Object System.Collections.Generic.List[double]

foreach ($file in $files) {
    Get-Content -LiteralPath $file -ReadCount 500 | ForEach-Object {
        foreach ($line in $_) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $evt = $line | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                Write-Warning ("Skipping malformed JSON line in '{0}': {1}" -f $file, $_.Exception.Message)
                continue
            }

            switch ($evt.EventName) {
                'PortBatchReady' {
                    $portEventCount++
                    $portsCommitted = [int]($evt.PortsCommitted)
                    $chunkSize = [int]($evt.ChunkSize)
                    $hostname = $evt.Hostname
                    $timestamp = $null
                    try { $timestamp = [datetime]$evt.Timestamp } catch { continue }
                    if (-not $timestamp) { continue }

                    $totalPorts += $portsCommitted
                    $totalChunk += $chunkSize
                    $timestamps.Add($timestamp)
                    if ($lastBatchTimestamp) {
                        $intervalMs = ($timestamp - $lastBatchTimestamp).TotalMilliseconds
                        if ($intervalMs -gt 0) { $batchIntervals.Add($intervalMs) }
                    }
                    $lastBatchTimestamp = $timestamp

                    if (-not [string]::IsNullOrWhiteSpace($hostname)) {
                        if (-not $hostStats.ContainsKey($hostname)) {
                            $hostStats[$hostname] = [pscustomobject]@{
                                Host          = $hostname
                                BatchCount    = 0
                                PortsCommitted = 0
                            }
                        }
                        $hostStats[$hostname].BatchCount++
                        $hostStats[$hostname].PortsCommitted += $portsCommitted
                    }
                }
                'InterfaceSyncTiming' {
                    $evtProps = $evt.PSObject.Properties.Name
                    if ($evtProps -contains 'UiCloneDurationMs' -and $evt.UiCloneDurationMs -ne $null) {
                        $uiCloneDurations.Add([double]$evt.UiCloneDurationMs) | Out-Null
                    }
                    if ($evtProps -contains 'StreamDispatchDurationMs' -and $evt.StreamDispatchDurationMs -ne $null) {
                        $streamDispatchDurations.Add([double]$evt.StreamDispatchDurationMs) | Out-Null
                    }
                    if ($evtProps -contains 'DiffDurationMs' -and $evt.DiffDurationMs -ne $null) {
                        $diffDurations.Add([double]$evt.DiffDurationMs) | Out-Null
                    }
                }
            }
        }
    }
}

$durationSeconds = $null
$portsPerMinute = $null
if ($timestamps.Count -ge 2) {
    $timestampsSorted = $timestamps | Sort-Object
    $durationSeconds = ($timestampsSorted[-1] - $timestampsSorted[0]).TotalSeconds
    if ($durationSeconds -gt 0) {
        $portsPerMinute = (($totalPorts / $durationSeconds) * 60)
    }
}

$avgPortsPerBatch = if ($portEventCount -gt 0) { [math]::Round($totalPorts / $portEventCount, 3) } else { $null }
$avgChunkSize = if ($portEventCount -gt 0) { [math]::Round($totalChunk / $portEventCount, 3) } else { $null }
$batchIntervalSummary = New-StatsSummary -Values ([double[]]$batchIntervals) -Name 'BatchIntervalMs' -Percentiles @(50,95)
$uiCloneSummary = New-StatsSummary -Values ([double[]]$uiCloneDurations) -Name 'UiCloneDurationMs' -Percentiles @(50,95)
$streamDispatchSummary = New-StatsSummary -Values ([double[]]$streamDispatchDurations) -Name 'StreamDispatchDurationMs' -Percentiles @(50,95)
$diffSummary = New-StatsSummary -Values ([double[]]$diffDurations) -Name 'DiffDurationMs' -Percentiles @(50,95)

$hostBreakdown = $null
if ($IncludeHostBreakdown -and $hostStats.Count -gt 0) {
    $hostBreakdown = $hostStats.Values | Sort-Object PortsCommitted -Descending
}

$summary = [pscustomobject]@{
    GeneratedAtUtc      = (Get-Date).ToUniversalTime().ToString('o')
    FilesAnalyzed        = $files
    PortBatchSummary     = [pscustomobject]@{
        EventCount        = $portEventCount
        UniqueHosts       = $hostStats.Count
        TotalPorts        = $totalPorts
        AveragePortsBatch = $avgPortsPerBatch
        AverageChunkSize  = $avgChunkSize
        DurationSeconds   = if ($durationSeconds) { [math]::Round($durationSeconds, 3) } else { $null }
        PortsPerMinute    = if ($portsPerMinute) { [math]::Round($portsPerMinute, 3) } else { $null }
        BatchIntervalMs   = $batchIntervalSummary
    }
    InterfaceSyncSummary = [pscustomobject]@{
        UiClone          = $uiCloneSummary
        StreamDispatch   = $streamDispatchSummary
        DiffDuration     = $diffSummary
        SampleCount      = $uiCloneDurations.Count
    }
    HostBreakdown       = $hostBreakdown
}

function Resolve-ComparisonValue {
    param(
        [pscustomobject]$CurrentObject,
        [pscustomobject]$BaselineObject,
        [string]$PropertyPath
    )

    $current = $CurrentObject
    $baseline = $BaselineObject

    foreach ($segment in $PropertyPath.Split('.')) {
        if ($current) { $current = $current.$segment }
        if ($baseline) { $baseline = $baseline.$segment }
    }

    return ,@($current, $baseline)
}

$comparisonRows = [System.Collections.Generic.List[pscustomobject]]::new()
if ($BaselineSummaryPath) {
    if (-not (Test-Path -LiteralPath $BaselineSummaryPath)) {
        throw "Baseline summary '$BaselineSummaryPath' was not found."
    }
    $baselineSummary = Read-ToolingJson -Path $BaselineSummaryPath -Label 'Baseline summary'
    if (-not $baselineSummary) {
        throw "Baseline summary '$BaselineSummaryPath' is empty or invalid."
    }

    $metrics = @(
        @{ Name = 'TotalPorts'; Path = 'PortBatchSummary.TotalPorts'; Unit = 'ports' },
        @{ Name = 'PortsPerMinute'; Path = 'PortBatchSummary.PortsPerMinute'; Unit = 'ports/min' },
        @{ Name = 'AveragePortsBatch'; Path = 'PortBatchSummary.AveragePortsBatch'; Unit = 'ports' },
        @{ Name = 'BatchIntervalP95Ms'; Path = 'PortBatchSummary.BatchIntervalMs.P95'; Unit = 'ms' },
        @{ Name = 'UiCloneP95Ms'; Path = 'InterfaceSyncSummary.UiClone.P95'; Unit = 'ms' },
        @{ Name = 'StreamDispatchP95Ms'; Path = 'InterfaceSyncSummary.StreamDispatch.P95'; Unit = 'ms' },
        @{ Name = 'DiffDurationP95Ms'; Path = 'InterfaceSyncSummary.DiffDuration.P95'; Unit = 'ms' }
    )

    foreach ($metric in $metrics) {
        $values = Resolve-ComparisonValue -CurrentObject $summary -BaselineObject $baselineSummary -PropertyPath $metric.Path
        $currentValue = $values[0]
        $baselineValue = $values[1]
        $delta = $null
        if ($currentValue -ne $null -and $baselineValue -ne $null) {
            $delta = [math]::Round(($currentValue - $baselineValue), 3)
        }
        $comparisonRows.Add([pscustomobject]@{
            Metric   = $metric.Name
            Current  = $currentValue
            Baseline = $baselineValue
            Delta    = $delta
            Unit     = $metric.Unit
        })
    }

    $summary | Add-Member -NotePropertyName 'BaselineSummaryPath' -NotePropertyValue (Resolve-Path -LiteralPath $BaselineSummaryPath).Path -Force
    $summary | Add-Member -NotePropertyName 'ComparisonMetrics' -NotePropertyValue $comparisonRows -Force
}

if ($OutputPath) {
    $outputDir = Split-Path -Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8
    Write-Host ("Telemetry performance summary written to {0}" -f (Resolve-Path -LiteralPath $OutputPath)) -ForegroundColor DarkCyan
}

Write-Host "`nPort batch throughput summary:" -ForegroundColor Cyan
$summary.PortBatchSummary | Format-List
Write-Host "`nInterfaceSyncTiming durations (ms):" -ForegroundColor Cyan
$summary.InterfaceSyncSummary | Format-List

if ($IncludeHostBreakdown -and $hostBreakdown) {
    Write-Host "`nHost breakdown (Top hosts by ports committed):" -ForegroundColor Cyan
    $hostBreakdown | Sort-Object PortsCommitted -Descending | Format-Table Host, BatchCount, PortsCommitted -AutoSize
}

if ($comparisonRows.Count -gt 0) {
    Write-Host "`nBaseline comparison:" -ForegroundColor Cyan
    $comparisonRows | Format-Table Metric, Current, Baseline, Delta, Unit -AutoSize
}

if ($PassThru) {
    return $summary
}
