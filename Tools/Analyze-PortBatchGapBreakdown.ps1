[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$IntervalReportPath,

    [int]$TopGaps = 10,

    [string]$OutputPath,

    [switch]$PassThru
)

<#
.SYNOPSIS
Summarises PortBatchReady idle gaps by site pair.

.DESCRIPTION
Takes the JSON emitted by `Tools\Analyze-PortBatchIntervals.ps1 -OutputPath ...` and groups every interval by the
origin/destination site (derived from the hostname prefix). Produces aggregate counts, averages, and maximum gaps so we
can quickly see which site transitions stall incremental loading (e.g., WLLS -> BOYO). Also emits the top N individual
gaps for timeline inspection.

.EXAMPLE
pwsh Tools\Analyze-PortBatchGapBreakdown.ps1 `
    -IntervalReportPath Logs/Reports/PortBatchIntervals-20251113.json `
    -TopGaps 5 `
    -OutputPath docs/performance/PortBatchSiteGapSummary-20251113.md
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolingJsonPath = Join-Path -Path $PSScriptRoot -ChildPath 'ToolingJson.psm1'
if (Test-Path -LiteralPath $toolingJsonPath) {
    Import-Module -Name $toolingJsonPath -Force
} else {
    throw "ToolingJson module not found at '$toolingJsonPath'."
}

if (-not (Test-Path -LiteralPath $IntervalReportPath)) {
    throw "Interval report '$IntervalReportPath' does not exist."
}

$report = Read-ToolingJson -Path $IntervalReportPath -Label 'Interval report'
if (-not $report) {
    throw "Interval report '$IntervalReportPath' could not be parsed."
}

function Get-IntervalsFromReport {
    param($ReportObject)
    if ($null -eq $ReportObject) { return @() }
    if ($ReportObject.PSObject -and $ReportObject.PSObject.Properties['Intervals']) {
        return @($ReportObject.Intervals)
    }
    if ($ReportObject -is [System.Collections.IEnumerable] -and -not ($ReportObject -is [string])) {
        return @($ReportObject)
    }
    return @($ReportObject)
}

$intervals = Get-IntervalsFromReport -ReportObject $report
if (-not $intervals -or $intervals.Count -eq 0) {
    throw "Interval report '$IntervalReportPath' does not contain any intervals."
}

function Get-SiteFromHostname {
    param([string]$Hostname)
    if ([string]::IsNullOrWhiteSpace($Hostname)) { return '(unknown)' }
    $parts = $Hostname.Split('-', 2, [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Count -gt 0) { return $parts[0] }
    return $Hostname
}

$enriched = foreach ($interval in $intervals) {
    $startSite = Get-SiteFromHostname -Hostname $interval.StartHost
    $endSite = Get-SiteFromHostname -Hostname $interval.EndHost
    [pscustomobject]@{
        StartTimeUtc = [datetime]$interval.StartTimeUtc
        EndTimeUtc   = [datetime]$interval.EndTimeUtc
        GapSeconds   = [double]$interval.GapSeconds
        GapMinutes   = [double]$interval.GapMinutes
        StartHost    = $interval.StartHost
        EndHost      = $interval.EndHost
        StartSite    = $startSite
        EndSite      = $endSite
    }
}

$grouped = $enriched | Group-Object StartSite, EndSite | ForEach-Object {
    $items = $_.Group | Sort-Object GapSeconds -Descending
    $max = $items[0]
    $avg = [math]::Round(($items.GapSeconds | Measure-Object -Average).Average, 3)
    [pscustomobject]@{
        StartSite     = $items[0].StartSite
        EndSite       = $items[0].EndSite
        GapCount      = $items.Count
        AverageGapSec = $avg
        MaxGapSec     = $max.GapSeconds
        MaxGapStart   = $max.StartTimeUtc
        MaxGapEnd     = $max.EndTimeUtc
        MaxGapStartHost = $max.StartHost
        MaxGapEndHost   = $max.EndHost
    }
} | Sort-Object MaxGapSec -Descending

Write-Verbose ("TopGaps input: {0} (Type={1})" -f $TopGaps, $TopGaps.GetType().FullName)
$gapSamples = $enriched | Sort-Object GapSeconds -Descending | Select-Object -First $TopGaps

$builder = New-Object System.Collections.Generic.List[string]
$builder.Add("# PortBatch site gap summary")
$builder.Add("")
$builder.Add( ('> Source intervals: `{0}`' -f (Resolve-Path -LiteralPath $IntervalReportPath)) )
$builder.Add( ('> Generated {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')) )
$builder.Add("")
$builder.Add("## Site-to-site gap aggregates")
$builder.Add("")
$builder.Add("| Start site | End site | Count | Avg gap (s) | Max gap (s) | Max gap start | Max gap end | Start host | End host |")
$builder.Add("|---|---|---|---|---|---|---|---|---|")
foreach ($row in $grouped) {
    $builder.Add( ('| {0} | {1} | {2} | {3} | {4} | {5:u} | {6:u} | {7} | {8} |' -f `
        $row.StartSite,
        $row.EndSite,
        $row.GapCount,
        $row.AverageGapSec,
        $row.MaxGapSec,
        $row.MaxGapStart,
        $row.MaxGapEnd,
        $row.MaxGapStartHost,
        $row.MaxGapEndHost) )
}
$builder.Add("")
$builder.Add("## Top {0} gaps" -f $TopGaps)
$builder.Add("")
$builder.Add("| Gap (s) | Gap (min) | Start (UTC) | End (UTC) | Start site | End site | Start host | End host |")
$builder.Add("|---|---|---|---|---|---|---|---|")
foreach ($gap in $gapSamples) {
    $builder.Add( ('| {0} | {1} | {2:u} | {3:u} | {4} | {5} | {6} | {7} |' -f `
        $gap.GapSeconds,
        $gap.GapMinutes,
        $gap.StartTimeUtc,
        $gap.EndTimeUtc,
        $gap.StartSite,
        $gap.EndSite,
        $gap.StartHost,
        $gap.EndHost) )
}
$builder.Add("")

if ($OutputPath) {
    $outputDir = Split-Path -Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    Set-Content -LiteralPath $OutputPath -Value ($builder -join [Environment]::NewLine) -Encoding utf8
    Write-Host ("Gap breakdown written to {0}" -f (Resolve-Path -LiteralPath $OutputPath)) -ForegroundColor DarkCyan
}
else {
    $builder -join [Environment]::NewLine | Write-Host
}

if ($PassThru) {
    return [pscustomobject]@{
        Groups  = $grouped
        TopGaps = $gapSamples
    }
}
