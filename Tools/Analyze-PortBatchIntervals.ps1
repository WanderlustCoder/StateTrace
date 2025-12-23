[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [int]$TopIntervals = 10,

    [double]$ThresholdSeconds = 5,

    [datetime]$StartTimeUtc,

    [datetime]$EndTimeUtc,

    [switch]$PassThru,

    [string]$OutputPath
)

<#
.SYNOPSIS
Finds the largest gaps between PortBatchReady events.

.DESCRIPTION
Reads newline-delimited ingestion metrics JSON, extracts `PortBatchReady` events, sorts them by timestamp,
and reports the longest intervals between consecutive events. Useful for identifying idle periods that shrink
ports-per-minute even when p95 batch intervals look healthy.

.NOTES
Use `-OutputPath` to persist every computed interval to JSON so other tooling (for example,
`Tools\Analyze-DispatcherGaps.ps1`) can correlate idle gaps with queue telemetry.

.EXAMPLE
pwsh Tools\Analyze-PortBatchIntervals.ps1 -Path Logs\IngestionMetrics\2025-11-13.json -TopIntervals 15 -ThresholdSeconds 60
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-InputFiles {
    param([string]$InputPath)
    if (-not (Test-Path -LiteralPath $InputPath)) {
        throw "Path '$InputPath' does not exist."
    }
    $item = Get-Item -LiteralPath $InputPath
    if ($item -is [System.IO.DirectoryInfo]) {
        return (Get-ChildItem -LiteralPath $item.FullName -Filter '*.json' -File | Sort-Object FullName).FullName
    }
    return @($item.FullName)
}

$files = Resolve-InputFiles -InputPath $Path
$events = New-Object System.Collections.Generic.List[pscustomobject]
$startUtc = $null
$endUtc = $null
if ($StartTimeUtc) { $startUtc = $StartTimeUtc.ToUniversalTime() }
if ($EndTimeUtc) { $endUtc = $EndTimeUtc.ToUniversalTime() }
if ($startUtc -and $endUtc -and $startUtc -gt $endUtc) {
    throw "StartTimeUtc must be earlier than or equal to EndTimeUtc."
}

foreach ($file in $files) {
    Get-Content -LiteralPath $file -ReadCount 500 | ForEach-Object {
        foreach ($line in $_) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $obj = $line | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                Write-Warning ("Skipping malformed JSON in '{0}': {1}" -f $file, $_.Exception.Message)
                continue
            }
            if ($obj.EventName -ne 'PortBatchReady') { continue }
            $timestamp = [datetime]$obj.Timestamp
            $timestampUtc = $timestamp.ToUniversalTime()
            if ($startUtc -and $timestampUtc -lt $startUtc) { continue }
            if ($endUtc -and $timestampUtc -gt $endUtc) { continue }
            $events.Add([pscustomobject]@{
                Timestamp = $timestampUtc
                Hostname  = $obj.Hostname
            }) | Out-Null
        }
    }
}

if ($events.Count -lt 2) {
    throw "Need at least 2 PortBatchReady events to compute intervals (found $($events.Count))."
}

$sorted = @($events | Sort-Object Timestamp)
$intervals = New-Object System.Collections.Generic.List[pscustomobject]

for ($i = 1; $i -lt $sorted.Count; $i++) {
    $prev = $sorted[$i-1]
    $curr = $sorted[$i]
    $gapMs = ($curr.Timestamp - $prev.Timestamp).TotalMilliseconds
    $intervals.Add([pscustomobject]@{
        StartTimeUtc = $prev.Timestamp.ToUniversalTime()
        EndTimeUtc   = $curr.Timestamp.ToUniversalTime()
        GapSeconds   = [math]::Round($gapMs / 1000.0, 3)
        GapMinutes   = [math]::Round($gapMs / 60000.0, 3)
        StartHost    = $prev.Hostname
        EndHost      = $curr.Hostname
    }) | Out-Null
}

$top = $intervals | Sort-Object GapSeconds -Descending | Select-Object -First $TopIntervals
$threshold = @($intervals | Where-Object { $_.GapSeconds -ge $ThresholdSeconds })

function Get-Count($collection) {
    return ( $collection | Measure-Object ).Count
}

$sortedCount = Get-Count $sorted
$fileCount = Get-Count $files
$thresholdCount = Get-Count $threshold
if ($startUtc -or $endUtc) {
    Write-Host ("Filtering events between {0} and {1} (UTC)." -f ($startUtc ? $startUtc.ToString('o') : 'start'), ($endUtc ? $endUtc.ToString('o') : 'end')) -ForegroundColor DarkGray
}

Write-Host ("Analyzed {0} PortBatchReady events across {1} file(s)." -f $sortedCount, $fileCount)
Write-Host ("Largest gaps between events (top {0}):" -f $TopIntervals) -ForegroundColor Cyan
$top | Format-Table StartTimeUtc, EndTimeUtc, GapSeconds, StartHost, EndHost -AutoSize

Write-Host ("`nGaps >= {0} seconds (count {1}):" -f $ThresholdSeconds, $thresholdCount) -ForegroundColor Cyan
if ($thresholdCount -gt 0) {
    $threshold | Format-Table StartTimeUtc, EndTimeUtc, GapSeconds, StartHost, EndHost -AutoSize
}
else {
    Write-Host 'None above threshold.'
}

if ($OutputPath) {
    $outputDir = Split-Path -Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $payload = [pscustomobject]@{
        GeneratedAtUtc    = (Get-Date).ToUniversalTime().ToString('o')
        SourceFiles       = $files
        EventCount        = $sortedCount
        IntervalCount     = $intervals.Count
        TopSampleSize     = $TopIntervals
        ThresholdSeconds  = $ThresholdSeconds
        ThresholdGapCount = $thresholdCount
        FilterStartUtc    = if ($startUtc) { $startUtc.ToString('o') } else { $null }
        FilterEndUtc      = if ($endUtc) { $endUtc.ToString('o') } else { $null }
        Intervals         = $intervals
    }

    $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8
    Write-Host ("Wrote interval report to {0}" -f (Resolve-Path -LiteralPath $OutputPath)) -ForegroundColor DarkCyan
}

if ($PassThru) {
    return $top
}
