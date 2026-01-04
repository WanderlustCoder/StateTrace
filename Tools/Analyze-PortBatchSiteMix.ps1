[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MetricsPath,

    [int]$WindowMinutes = 5,

    [int]$TopWindows = 5,

    [datetime]$StartTimeUtc,

    [datetime]$EndTimeUtc,

    [string]$OutputPath
)

<#
.SYNOPSIS
Summarises PortBatchReady site distribution per time window.

.DESCRIPTION
Reads newline-delimited ingestion metrics JSON, extracts `PortBatchReady` events, and groups them into
`WindowMinutes` buckets (UTC). Emits aggregate counts (total per window, per-site distribution, percent share) so we can
see when one site monopolises the dispatcher. Use this alongside `Tools\Analyze-PortBatchGapTimeline.ps1` /
`Tools\Test-PortBatchSiteDiversity.ps1` to prove scheduler starvation.

.EXAMPLE
pwsh Tools\Analyze-PortBatchSiteMix.ps1 `
    -MetricsPath Logs/IngestionMetrics/2025-11-13.json `
    -WindowMinutes 5 `
    -TopWindows 6 `
    -OutputPath docs/performance/PortBatchSiteMix-20251113.md
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

trap {
    Write-Error ("[SiteMix] Line {0}: {1}" -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
    throw
}

function Resolve-MetricsFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Metrics path '$Path' does not exist."
    }
    $item = Get-Item -LiteralPath $Path
    if ($item -is [System.IO.DirectoryInfo]) {
        $latest = Get-ChildItem -LiteralPath $item.FullName -Filter '*.json' -File | Sort-Object LastWriteTime | Select-Object -Last 1
        if (-not $latest) { throw "Directory '$Path' contains no JSON files." }
        return $latest.FullName
    }
    return $item.FullName
}

function Get-SiteFromHostname {
    param([string]$Hostname)
    if ([string]::IsNullOrWhiteSpace($Hostname)) { return '(unknown)' }
    $parts = $Hostname.Split('-', 2, [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Count -gt 0) { return $parts[0] }
    return $Hostname
}

function Get-WindowStartUtc {
    param([datetime]$TimestampUtc, [int]$WindowMinutes)
    $windowTicks = [TimeSpan]::FromMinutes($WindowMinutes).Ticks
    $quotient = [math]::Floor($TimestampUtc.Ticks / $windowTicks)
    $ticks = $quotient * $windowTicks
    return [datetime]::SpecifyKind([datetime]::MinValue.AddTicks($ticks), [System.DateTimeKind]::Utc)
}

$metricsFile = Resolve-MetricsFile -Path $MetricsPath
$events = New-Object System.Collections.Generic.List[pscustomobject]
$startUtc = $null
$endUtc = $null
if ($StartTimeUtc) { $startUtc = $StartTimeUtc.ToUniversalTime() }
if ($EndTimeUtc) { $endUtc = $EndTimeUtc.ToUniversalTime() }
if ($startUtc -and $endUtc -and $startUtc -gt $endUtc) {
    throw "StartTimeUtc must be earlier than or equal to EndTimeUtc."
}

Get-Content -LiteralPath $metricsFile -ReadCount 500 | ForEach-Object {
    foreach ($line in $_) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $record = $line | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            Write-Warning ("Skipping malformed JSON line: {0}" -f $_.Exception.Message)
            continue
        }
        if ($record.EventName -ne 'PortBatchReady') { continue }
        $utcTime = $null
        try { $utcTime = ([datetime]$record.Timestamp).ToUniversalTime() } catch { continue }
        if (-not $utcTime) { continue }
        if ($startUtc -and $utcTime -lt $startUtc) { continue }
        if ($endUtc -and $utcTime -gt $endUtc) { continue }
        $events.Add([pscustomobject]@{
            Timestamp = $utcTime
            Hostname  = $record.Hostname
            Site      = Get-SiteFromHostname -Hostname $record.Hostname
        }) | Out-Null
    }
}

if ($events.Count -eq 0) {
    throw "No PortBatchReady events found in '$metricsFile'."
}

$windows = @{}
foreach ($evt in $events) {
    $windowStart = Get-WindowStartUtc -TimestampUtc $evt.Timestamp -WindowMinutes $WindowMinutes
    $key = $windowStart.ToString('o')
    if (-not $windows.ContainsKey($key)) {
        $windows[$key] = [pscustomobject]@{
            Start = $windowStart
            End   = $windowStart.AddMinutes($WindowMinutes)
            Counts = @{}
            Total  = 0
        }
    }
    $windowEntry = $windows[$key]
    $windowEntry.Total++
    if (-not $windowEntry.Counts.ContainsKey($evt.Site)) {
        $windowEntry.Counts[$evt.Site] = 0
    }
    $windowEntry.Counts[$evt.Site]++
}

$windowList = $windows.Values | Sort-Object Start

function Convert-ToSummary {
    param($WindowEntry)
    $counts = $WindowEntry.Counts.GetEnumerator() | Sort-Object Value -Descending
    $topSite = $counts | Select-Object -First 1
    $siteShares = @{}
    foreach ($entry in $counts) {
        $siteShares[$entry.Key] = [math]::Round(($entry.Value / [double]$WindowEntry.Total) * 100, 2)
    }
    return [pscustomobject]@{
        WindowStart = $WindowEntry.Start
        WindowEnd   = $WindowEntry.End
        TotalEvents = $WindowEntry.Total
        TopSite     = if ($topSite) { $topSite.Key } else { $null }
        TopSiteCount= if ($topSite) { $topSite.Value } else { 0 }
        TopSiteShare= if ($topSite) { $siteShares[$topSite.Key] } else { 0 }
        SiteShares  = $siteShares
    }
}

$summaries = $windowList | ForEach-Object { Convert-ToSummary -WindowEntry $_ } | Sort-Object TotalEvents -Descending
$topSummaries = $summaries | Select-Object -First $TopWindows

$builder = New-Object System.Collections.Generic.List[string]
$builder.Add("# PortBatch site mix summary")
$builder.Add("")
$builder.Add([string]::Format('> Metrics file: `{0}`', (Resolve-Path -LiteralPath $metricsFile)))
if ($startUtc -or $endUtc) {
    $builder.Add([string]::Format('> Filter (UTC): {0} -> {1}', ($startUtc ? $startUtc.ToString('o') : 'start'), ($endUtc ? $endUtc.ToString('o') : 'end')))
}
$builder.Add([string]::Format('> Window size: {0} minutes', $WindowMinutes))
$builder.Add([string]::Format('> Generated {0}', (Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')))
$builder.Add("")
$builder.Add([string]::Format("## Top {0} windows by event count", $TopWindows))
$builder.Add("")
$builder.Add("| Window start (UTC) | Window end (UTC) | Total batches | Top site | Top share (%) | Site shares |")
$builder.Add("|---|---|---|---|---|---|")
foreach ($row in $topSummaries) {
    $sharesText = ($row.SiteShares.GetEnumerator() | Sort-Object Name | ForEach-Object { [string]::Format("{0}:{1}%", $_.Key, $_.Value) }) -join "; "
    $builder.Add([string]::Format("| {0:u} | {1:u} | {2} | {3} | {4} | {5} |",
        $row.WindowStart,
        $row.WindowEnd,
        $row.TotalEvents,
        $row.TopSite,
        $row.TopSiteShare,
        $sharesText))
}
$builder.Add("")

if ($OutputPath) {
    $outDir = Split-Path -Path $OutputPath -Parent
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    Set-Content -LiteralPath $OutputPath -Value ($builder -join [Environment]::NewLine) -Encoding utf8
    Write-Host ("Wrote site mix report to {0}" -f (Resolve-Path -LiteralPath $OutputPath)) -ForegroundColor DarkCyan
}
else {
    $builder -join [Environment]::NewLine | Write-Host
}
