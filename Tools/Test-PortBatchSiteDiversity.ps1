[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MetricsPath,

    [int]$MaxAllowedConsecutive = 8,

    [switch]$AllowEmpty,

    [switch]$AllowNoParse,

    [switch]$IgnoreSynthesizedEvents,

    [datetime]$SinceTimestamp,

    [datetime]$UntilTimestamp,

    [string]$OutputPath,
    [Nullable[bool]]$ManualOverridesApplied,
    [psobject]$ConcurrencyProfile,
    [switch]$RawAutoConcurrencyMode
)

<#
.SYNOPSIS
Validates that PortBatchReady events are not dominated by a single site.

.DESCRIPTION
Reads newline-delimited ingestion metrics JSON, extracts `PortBatchReady` events, and measures the longest consecutive
sequence per site. If any site repeats more than `-MaxAllowedConsecutive` times, the script throws (fail-fast guard for
Plan D ST-D-003/ST-D-010). Optionally writes the summary to JSON for telemetry bundles.
.PARAMETER AllowNoParse
Allow empty PortBatchReady results when no parse events are present but SkippedDuplicate entries exist.
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
$parseEventNames = @(
    'ParseDuration',
    'DatabaseWriteBreakdown',
    'DeviceParsingTiming',
    'InterfaceSyncTiming',
    'InterfaceBulkInsert',
    'InterfaceBulkInsertTiming'
)
$parseEventCount = 0
$skippedDuplicateCount = 0
$sinceUtc = $null
if ($PSBoundParameters.ContainsKey('SinceTimestamp')) {
    $sinceUtc = $SinceTimestamp.ToUniversalTime()
}
$untilUtc = $null
if ($PSBoundParameters.ContainsKey('UntilTimestamp')) {
    $untilUtc = $UntilTimestamp.ToUniversalTime()
}

Get-Content -LiteralPath $metricsFile -ReadCount 500 | ForEach-Object {
    foreach ($line in $_) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $record = $line | ConvertFrom-Json -ErrorAction Stop }
        catch { Write-Warning ("Skipping malformed line: {0}" -f $_.Exception.Message); continue }
        $eventName = $record.EventName
        $timestamp = [datetime]$record.Timestamp
        if ($sinceUtc -and $timestamp.ToUniversalTime() -lt $sinceUtc) { continue }
        # LANDMARK: Port diversity window - support upper bound for warm-run isolation
        if ($untilUtc -and $timestamp.ToUniversalTime() -gt $untilUtc) { continue }
        if ($eventName -eq 'SkippedDuplicate') {
            $skippedDuplicateCount++
        } elseif ($parseEventNames -contains $eventName) {
            $parseEventCount++
        }
        if ($eventName -ne 'PortBatchReady') { continue }
        $isSynthesized = $false
        if ($record.PSObject.Properties.Name -contains 'Synthesized') {
            $isSynthesized = [bool]$record.Synthesized
        }
        $events.Add([pscustomobject]@{
            Timestamp   = $timestamp
            Hostname    = $record.Hostname
            Site        = Get-Site $record.Hostname
            Synthesized = $isSynthesized
        }) | Out-Null
    }
}

$totalEventCount = $events.Count
$observedEventCount = if ($totalEventCount -gt 0) { @($events | Where-Object { -not $_.Synthesized }).Count } else { 0 }
$synthesizedEventCount = $totalEventCount - $observedEventCount
$ignoredSynthesized = $IgnoreSynthesizedEvents.IsPresent
$usedSynthesized = $false
if ($totalEventCount -gt 0) {
    # LANDMARK: Port diversity raw mode - optionally ignore synthesized events
    if ($ignoredSynthesized) {
        if ($synthesizedEventCount -gt 0) {
            Write-Host ("Ignoring {0} synthesized PortBatchReady event(s) for diversity evaluation." -f $synthesizedEventCount) -ForegroundColor DarkGray
        }
        $events = @($events | Where-Object { -not $_.Synthesized })
    } else {
        $synthesizedEvents = @($events | Where-Object { $_.Synthesized })
        if ($synthesizedEvents.Count -gt 0) {
            $events = $synthesizedEvents
            $usedSynthesized = $true
            Write-Host ("Using {0} synthesized PortBatchReady event(s) for diversity evaluation." -f $events.Count) -ForegroundColor DarkGray
        }
    }
}

$noParseActivity = ($parseEventCount -le 0 -and $skippedDuplicateCount -gt 0)
if ($events.Count -eq 0) {
    $skipForNoParse = ($AllowNoParse.IsPresent -and $noParseActivity)
    if (-not $AllowEmpty.IsPresent -and -not $skipForNoParse) {
        throw "No PortBatchReady events found in '$metricsFile'."
    }

    $skipReason = if ($skipForNoParse) {
        'NoParseActivity'
    } elseif ($ignoredSynthesized -and $totalEventCount -gt 0 -and $observedEventCount -le 0) {
        'NoObservedPortBatchReadyEvents'
    } else {
        'NoPortBatchReadyEvents'
    }

    $result = [pscustomobject]@{
        MetricsFile              = (Resolve-Path -LiteralPath $metricsFile).Path
        GeneratedAtUtc           = (Get-Date).ToUniversalTime().ToString('o')
        EvaluationWindowStartUtc = $sinceUtc
        EvaluationWindowEndUtc   = $untilUtc
        MaxAllowedConsecutive    = $MaxAllowedConsecutive
        EvaluationEnd            = $null
        TerminalSite             = $null
        SitesRemainingWhenStopped= 0
        PortBatchReadyCount      = $totalEventCount
        EvaluatedPortBatchReadyCount = 0
        UsedSynthesizedEvents    = $false
        IgnoredSynthesizedEvents = $ignoredSynthesized
        ManualOverridesApplied   = $ManualOverridesApplied
        ConcurrencyProfile       = $ConcurrencyProfile
        RawAutoConcurrencyMode   = $RawAutoConcurrencyMode.IsPresent
        ObservedPortBatchReadyCount = $observedEventCount
        SynthesizedPortBatchReadyCount = $synthesizedEventCount
        SiteStreaks              = @()
        Skipped                  = $true
        SkipReason               = $skipReason
        ParseEventCount          = $parseEventCount
        SkippedDuplicateCount    = $skippedDuplicateCount
    }

    if ($OutputPath) {
        $dir = Split-Path -Path $OutputPath -Parent
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding utf8
        Write-Host ("Site diversity summary written to {0}" -f (Resolve-Path -LiteralPath $OutputPath)) -ForegroundColor DarkCyan
    }

    if ($skipForNoParse) {
        Write-Warning ("No parse events detected (SkippedDuplicate only) in '{0}'; skipping site diversity evaluation." -f $metricsFile)
    } elseif ($skipReason -eq 'NoObservedPortBatchReadyEvents') {
        Write-Warning ("No observed PortBatchReady events found in '{0}' (synthesized ignored); skipping site diversity evaluation." -f $metricsFile)
    } else {
        Write-Warning ("No PortBatchReady events found in '{0}'; skipping site diversity evaluation." -f $metricsFile)
    }
    return $result
}

$sorted = $events | Sort-Object Timestamp
$streaks = @()
$currentSite = $null
$currentHosts = @()
$currentStart = $null
$currentStartIndex = 0
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

function Add-Streak($site, $start, $end, [string[]]$hosts, [int]$startIndex, [int]$endIndex) {
    $hostArray = @()
    if ($hosts) {
        $hostArray = @($hosts)
    }
    $sequenceSample = @()
    if ($hostArray.Count -gt 0) {
        $sequenceSample = @($hostArray | Select-Object -First 12)
    }
    $script:streaks += [pscustomobject]@{
        Site      = $site
        Count     = $hostArray.Count
        StartTime = $start.ToUniversalTime()
        EndTime   = $end.ToUniversalTime()
        StartIndex = $startIndex
        EndIndex   = $endIndex
        HostSample= ($hostArray | Select-Object -Unique | Select-Object -First 5) -join ', '
        HostSequenceSample = $sequenceSample -join ', '
    }
}

for ($i = 0; $i -lt $sorted.Count; $i++) {
    $evt = $sorted[$i]

    if ($evt.Site -eq $currentSite) {
        $currentHosts += $evt.Hostname
    } else {
        if ($currentSite) {
            Add-Streak -site $currentSite -start $currentStart -end $evt.Timestamp -hosts $currentHosts -startIndex $currentStartIndex -endIndex ($i - 1)
        }
        $currentSite = $evt.Site
        $currentStart = $evt.Timestamp
        $currentStartIndex = $i
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
    $endIndex = if ($lastProcessedIndex -ge 0) { $lastProcessedIndex } else { $sorted.Count - 1 }
    Add-Streak -site $currentSite -start $currentStart -end $endTimestamp -hosts $currentHosts -startIndex $currentStartIndex -endIndex $endIndex
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

$maxSegment = $null
if ($streaks.Count -gt 0) {
    $maxSegment = $streaks | Sort-Object Count -Descending | Select-Object -First 1
}

$evaluationEnd = if ($lastProcessedIndex -ge 0) { $sorted[$lastProcessedIndex].Timestamp.ToUniversalTime() } else { $sorted[-1].Timestamp.ToUniversalTime() }
$result = [pscustomobject]@{
    MetricsFile = (Resolve-Path -LiteralPath $metricsFile).Path
    GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    EvaluationWindowStartUtc = $sinceUtc
    EvaluationWindowEndUtc = $untilUtc
    MaxAllowedConsecutive = $MaxAllowedConsecutive
    EvaluationEnd = $evaluationEnd
    TerminalSite = $terminalSite
    SitesRemainingWhenStopped = $terminalActiveSites
    PortBatchReadyCount = $totalEventCount
    EvaluatedPortBatchReadyCount = $events.Count
    UsedSynthesizedEvents = $usedSynthesized
    IgnoredSynthesizedEvents = $ignoredSynthesized
    ManualOverridesApplied = $ManualOverridesApplied
    ConcurrencyProfile = $ConcurrencyProfile
    RawAutoConcurrencyMode = $RawAutoConcurrencyMode.IsPresent
    ObservedPortBatchReadyCount = $observedEventCount
    SynthesizedPortBatchReadyCount = $synthesizedEventCount
    ParseEventCount = $parseEventCount
    SkippedDuplicateCount = $skippedDuplicateCount
    SiteStreaks = $summary
    MaxStreakSegment = $maxSegment
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

# LANDMARK: Port diversity output - keep table output on host while returning summary object
Write-Host "Max consecutive PortBatchReady events per site:" -ForegroundColor Cyan
$summaryTable = $summary | Format-Table Site, MaxCount, StartTime, EndTime, HostSample -AutoSize | Out-String
Write-Host $summaryTable

$worst = $summary | Select-Object -First 1
if ($worst.MaxCount -gt $MaxAllowedConsecutive) {
    throw ("Site '{0}' exceeded the max consecutive threshold (found {1}, limit {2})." -f $worst.Site, $worst.MaxCount, $MaxAllowedConsecutive)
}

return $result
