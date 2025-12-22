[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MetricsPath,

    [int]$MaxAllowedConsecutive = 8,

    [switch]$AllowEmpty,

    [string]$OutputPath
)

<#
.SYNOPSIS
Validates that PortBatchReady events are not dominated by a single site.

.DESCRIPTION
Reads newline-delimited ingestion metrics JSON, extracts `PortBatchReady` events, and measures the longest consecutive
sequence per site. If any site repeats more than `-MaxAllowedConsecutive` times, the script throws (fail-fast guard for
Plan D ST-D-003/ST-D-010). Optionally writes the summary to JSON for telemetry bundles.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-MetricsFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Metrics path '$Path' not found." }
    $item = Get-Item -LiteralPath $Path
    if ($item -is [System.IO.DirectoryInfo]) {
        $latest = Get-ChildItem -LiteralPath $item.FullName -Filter '*.json' -File | Sort-Object LastWriteTime | Select-Object -Last 1
        if (-not $latest) { throw "No JSON files found in '$Path'." }
        return $latest.FullName
    }
    return $item.FullName
}

function Get-Site([string]$Hostname) {
    if ([string]::IsNullOrWhiteSpace($Hostname)) { return '(unknown)' }
    return $Hostname.Split('-', 2, [System.StringSplitOptions]::RemoveEmptyEntries)[0]
}

$metricsFile = Resolve-MetricsFile -Path $MetricsPath
$events = New-Object System.Collections.Generic.List[pscustomobject]

Get-Content -LiteralPath $metricsFile -ReadCount 500 | ForEach-Object {
    foreach ($line in $_) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $record = $line | ConvertFrom-Json -ErrorAction Stop }
        catch { Write-Warning ("Skipping malformed line: {0}" -f $_.Exception.Message); continue }
        if ($record.EventName -ne 'PortBatchReady') { continue }
        $isSynthesized = $false
        if ($record.PSObject.Properties.Name -contains 'Synthesized') {
            $isSynthesized = [bool]$record.Synthesized
        }
        $events.Add([pscustomobject]@{
            Timestamp   = [datetime]$record.Timestamp
            Hostname    = $record.Hostname
            Site        = Get-Site $record.Hostname
            Synthesized = $isSynthesized
        }) | Out-Null
    }
}

$totalEventCount = $events.Count
$usedSynthesized = $false
if ($totalEventCount -gt 0) {
    $synthesizedEvents = @($events | Where-Object { $_.Synthesized })
    if ($synthesizedEvents.Count -gt 0) {
        $events = $synthesizedEvents
        $usedSynthesized = $true
        Write-Host ("Using {0} synthesized PortBatchReady event(s) for diversity evaluation." -f $events.Count) -ForegroundColor DarkGray
    }
}

if ($events.Count -eq 0) {
    if (-not $AllowEmpty.IsPresent) {
        throw "No PortBatchReady events found in '$metricsFile'."
    }

    $result = [pscustomobject]@{
        MetricsFile              = (Resolve-Path -LiteralPath $metricsFile).Path
        GeneratedAtUtc           = (Get-Date).ToUniversalTime().ToString('o')
        MaxAllowedConsecutive    = $MaxAllowedConsecutive
        EvaluationEnd            = $null
        TerminalSite             = $null
        SitesRemainingWhenStopped= 0
        PortBatchReadyCount      = 0
        EvaluatedPortBatchReadyCount = 0
        UsedSynthesizedEvents    = $false
        SiteStreaks              = @()
        Skipped                  = $true
        SkipReason               = 'NoPortBatchReadyEvents'
    }

    if ($OutputPath) {
        $dir = Split-Path -Path $OutputPath -Parent
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding utf8
        Write-Host ("Site diversity summary written to {0}" -f (Resolve-Path -LiteralPath $OutputPath)) -ForegroundColor DarkCyan
    }

    Write-Warning ("No PortBatchReady events found in '{0}'; skipping site diversity evaluation." -f $metricsFile)
    return $result
}

$sorted = $events | Sort-Object Timestamp
$streaks = @()
$currentSite = $null
$currentHosts = @()
$currentStart = $null
$lastProcessedIndex = -1
$terminalSite = $null
$terminalActiveSites = 0

$remainingCounts = @{}
foreach ($evt in $sorted) {
    $siteKey = $evt.Site
    if (-not $remainingCounts.ContainsKey($siteKey)) {
        $remainingCounts[$siteKey] = 0
    }
    $remainingCounts[$siteKey]++
}

function Add-Streak($site, $start, $end, [string[]]$hosts) {
    $hostArray = @()
    if ($hosts) {
        $hostArray = @($hosts)
    }
    $script:streaks += [pscustomobject]@{
        Site      = $site
        Count     = $hostArray.Count
        StartTime = $start.ToUniversalTime()
        EndTime   = $end.ToUniversalTime()
        HostSample= ($hostArray | Select-Object -Unique | Select-Object -First 5) -join ', '
    }
}

for ($i = 0; $i -lt $sorted.Count; $i++) {
    $evt = $sorted[$i]

    if ($evt.Site -eq $currentSite) {
        $currentHosts += $evt.Hostname
    } else {
        if ($currentSite) {
            Add-Streak -site $currentSite -start $currentStart -end $evt.Timestamp -hosts $currentHosts
        }
        $currentSite = $evt.Site
        $currentStart = $evt.Timestamp
        $currentHosts = @($evt.Hostname)
    }

    $lastProcessedIndex = $i

    if ($remainingCounts.ContainsKey($evt.Site)) {
        $remainingCounts[$evt.Site]--
    }
    $activeSites = @($remainingCounts.GetEnumerator() | Where-Object { $_.Value -gt 0 }).Count
    if ($activeSites -le 1) {
        $terminalSite = $evt.Site
        $terminalActiveSites = $activeSites
        break
    }
}

if ($currentSite) {
    $endTimestamp = if ($lastProcessedIndex -ge 0) { $sorted[$lastProcessedIndex].Timestamp } else { $sorted[-1].Timestamp }
    Add-Streak -site $currentSite -start $currentStart -end $endTimestamp -hosts $currentHosts
}

$summary = $streaks | Sort-Object Count -Descending | Group-Object Site | ForEach-Object {
    $top = $_.Group | Sort-Object Count -Descending | Select-Object -First 1
    [pscustomobject]@{
        Site      = $_.Name
        MaxCount  = $top.Count
        StartTime = $top.StartTime
        EndTime   = $top.EndTime
        HostSample= $top.HostSample
    }
} | Sort-Object MaxCount -Descending

$evaluationEnd = if ($lastProcessedIndex -ge 0) { $sorted[$lastProcessedIndex].Timestamp.ToUniversalTime() } else { $sorted[-1].Timestamp.ToUniversalTime() }
$result = [pscustomobject]@{
    MetricsFile = (Resolve-Path -LiteralPath $metricsFile).Path
    GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    MaxAllowedConsecutive = $MaxAllowedConsecutive
    EvaluationEnd = $evaluationEnd
    TerminalSite = $terminalSite
    SitesRemainingWhenStopped = $terminalActiveSites
    PortBatchReadyCount = $totalEventCount
    EvaluatedPortBatchReadyCount = $events.Count
    UsedSynthesizedEvents = $usedSynthesized
    SiteStreaks = $summary
}

if ($terminalSite -and $terminalActiveSites -le 1) {
    Write-Host ("Stopped streak evaluation once only one site remained (last multi-site event '{0}' at {1})." -f $terminalSite, $evaluationEnd) -ForegroundColor DarkGray
}

if ($OutputPath) {
    $dir = Split-Path -Path $OutputPath -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding utf8
    Write-Host ("Site diversity summary written to {0}" -f (Resolve-Path -LiteralPath $OutputPath)) -ForegroundColor DarkCyan
}

Write-Host "Max consecutive PortBatchReady events per site:" -ForegroundColor Cyan
$summary | Format-Table Site, MaxCount, StartTime, EndTime, HostSample -AutoSize

$worst = $summary | Select-Object -First 1
if ($worst.MaxCount -gt $MaxAllowedConsecutive) {
    throw ("Site '{0}' exceeded the max consecutive threshold (found {1}, limit {2})." -f $worst.Site, $worst.MaxCount, $MaxAllowedConsecutive)
}
