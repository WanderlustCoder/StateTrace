[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [int]$MaxAllowedStreak = 8,

    [string]$OutputPath,

    [switch]$PassThru
)

<#
.SYNOPSIS
Summarises `ParserSchedulerLaunch` telemetry to verify site rotation fairness.

.DESCRIPTION
Scans ingestion-metrics JSON (newline-delimited) files for `ParserSchedulerLaunch` events,
computes launch counts per site, consecutive streak lengths, and aggregate scheduler metrics
(`ActiveWorkers`, `ActiveSites`, `ThreadBudget`, `QueuedJobs`, `QueuedSites`). The report flags
any streak that exceeds `-MaxAllowedStreak` so incremental-loading sweeps can confirm
dispatcher fairness alongside `Tools/Test-PortBatchSiteDiversity.ps1`.

.EXAMPLE
pwsh Tools\Analyze-ParserSchedulerLaunch.ps1 `
    -Path Logs\IngestionMetrics\2025-11-14.json `
    -MaxAllowedStreak 8 `
    -OutputPath Logs\Reports\ParserSchedulerLaunch-20251114.json
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$statisticsModulePath = Join-Path -Path $repositoryRoot -ChildPath 'Modules\StatisticsModule.psm1'
if (-not (Test-Path -LiteralPath $statisticsModulePath)) {
    throw "StatisticsModule not found at $statisticsModulePath"
}
Import-Module -Name $statisticsModulePath -Force -ErrorAction Stop

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
    } elseif ($item -is [System.IO.FileInfo]) {
        return @($item.FullName)
    } else {
        throw "Unsupported path type for '$InputPath'."
    }
}

function New-ScalarSummary {
    param(
        [string]$Name,
        [double[]]$Values
    )

    if (-not $Values -or $Values.Count -eq 0) {
        return [pscustomobject]@{
            Name   = $Name
            Count  = 0
            Min    = $null
            Average = $null
            P50    = $null
            P95    = $null
            Max    = $null
        }
    }

    $sorted = $Values | Sort-Object
    $count = $sorted.Count
    $avg = ($sorted | Measure-Object -Average).Average

    return [pscustomobject]@{
        Name    = $Name
        Count   = $count
        Min     = $sorted[0]
        Average = [math]::Round($avg, 3)
        P50     = [math]::Round((StatisticsModule\Get-PercentileValue -Values $sorted -Percentile 50), 3)
        P95     = [math]::Round((StatisticsModule\Get-PercentileValue -Values $sorted -Percentile 95), 3)
        Max     = $sorted[-1]
    }
}

$files = Get-TargetFiles -InputPath $Path
$hasRealLaunch = $false
$hasSynthLaunch = $false
$scanComplete = $false
foreach ($file in $files) {
    Get-Content -LiteralPath $file -ReadCount 500 | ForEach-Object {
        foreach ($line in $_) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $evt = $null
            try { $evt = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            if ($evt.EventName -ne 'ParserSchedulerLaunch') { continue }
            $isSynth = $false
            if ($evt.PSObject.Properties.Name -contains 'Synthesized') {
                try { $isSynth = [bool]$evt.Synthesized } catch { $isSynth = $false }
            }
            if ($isSynth) { $hasSynthLaunch = $true } else { $hasRealLaunch = $true }
            if ($hasRealLaunch -and $hasSynthLaunch) { $scanComplete = $true; break }
        }
        if ($scanComplete) { break }
    }
    if ($scanComplete) { break }
}
$preferRealEvents = $hasRealLaunch
$siteStats = @{}
$violations = New-Object System.Collections.Generic.List[psobject]
$activeWorkersValues = New-Object System.Collections.Generic.List[double]
$activeSitesValues = New-Object System.Collections.Generic.List[double]
$threadBudgetValues = New-Object System.Collections.Generic.List[double]
$queuedJobsValues = New-Object System.Collections.Generic.List[double]
$queuedSitesValues = New-Object System.Collections.Generic.List[double]

$prevSite = $null
$prevTimestamp = $null
$currentStreakCount = 0
$currentStreakStart = $null
$launchCount = 0
$timestampList = New-Object System.Collections.Generic.List[datetime]

function Complete-Streak {
    param(
        [string]$Site,
        [int]$Count,
        [datetime]$StartTime,
        [datetime]$EndTime,
        [hashtable]$StatsTable,
        [int]$StreakLimit,
        [System.Collections.Generic.List[psobject]]$ViolationList
    )

    if (-not $Site) { return }
    if (-not $StatsTable.ContainsKey($Site)) {
        $StatsTable[$Site] = [pscustomobject]@{
            Site                 = $Site
            LaunchCount          = 0
            MaxConsecutive       = 0
            MaxConsecutiveStart  = $null
            MaxConsecutiveEnd    = $null
        }
    }

    $stat = $StatsTable[$Site]
    if ($Count -gt $stat.MaxConsecutive) {
        $stat.MaxConsecutive = $Count
        $stat.MaxConsecutiveStart = $StartTime
        $stat.MaxConsecutiveEnd = $EndTime
    }

    if ($Count -gt $StreakLimit) {
        $ViolationList.Add([pscustomobject]@{
            Site       = $Site
            Count      = $Count
            StartTime  = $StartTime
            EndTime    = $EndTime
        }) | Out-Null
    }
}

foreach ($file in $files) {
    Get-Content -LiteralPath $file -ReadCount 500 | ForEach-Object {
        foreach ($line in $_) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $evt = $null
            try {
                $evt = $line | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Write-Warning ("Skipping malformed JSON line in '{0}': {1}" -f $file, $_.Exception.Message)
                continue
            }

            if ($evt.EventName -ne 'ParserSchedulerLaunch') { continue }        
            if ($preferRealEvents -and $evt.PSObject.Properties.Name -contains 'Synthesized' -and $evt.Synthesized) { continue }

            $launchCount++
            $timestamp = $null
            try { $timestamp = [datetime]$evt.Timestamp } catch { $timestamp = $null }
            if ($timestamp) { $timestampList.Add($timestamp) | Out-Null }

            $site = $evt.Site
            if ([string]::IsNullOrWhiteSpace($site)) { $site = 'Unknown' }

            if (-not $siteStats.ContainsKey($site)) {
                $siteStats[$site] = [pscustomobject]@{
                    Site                 = $site
                    LaunchCount          = 0
                    MaxConsecutive       = 0
                    MaxConsecutiveStart  = $null
                    MaxConsecutiveEnd    = $null
                }
            }
            $siteStats[$site].LaunchCount++

            if ($evt.ActiveWorkers -ne $null) { $activeWorkersValues.Add([double]$evt.ActiveWorkers) | Out-Null }
            if ($evt.ActiveSites -ne $null) { $activeSitesValues.Add([double]$evt.ActiveSites) | Out-Null }
            if ($evt.ThreadBudget -ne $null) { $threadBudgetValues.Add([double]$evt.ThreadBudget) | Out-Null }
            if ($evt.QueuedJobs -ne $null) { $queuedJobsValues.Add([double]$evt.QueuedJobs) | Out-Null }
            if ($evt.QueuedSites -ne $null) { $queuedSitesValues.Add([double]$evt.QueuedSites) | Out-Null }

            $queuedSiteCountForEvent = $null
            if ($evt.PSObject.Properties.Name -contains 'QueuedSites' -and $evt.QueuedSites -ne $null) {
                $queuedSiteCountForEvent = [int]$evt.QueuedSites
            }

            $shouldIgnoreStreak = ($queuedSiteCountForEvent -ne $null -and $queuedSiteCountForEvent -le 1)
            if ($shouldIgnoreStreak -and $prevSite) {
                Complete-Streak -Site $prevSite -Count $currentStreakCount -StartTime $currentStreakStart -EndTime $prevTimestamp -StatsTable $siteStats -StreakLimit $MaxAllowedStreak -ViolationList $violations
                $prevSite = $null
                $currentStreakCount = 0
                $currentStreakStart = $null
            }

            if ($site -ne $prevSite) {
                if ($prevSite) {
                    Complete-Streak -Site $prevSite -Count $currentStreakCount -StartTime $currentStreakStart -EndTime $prevTimestamp -StatsTable $siteStats -StreakLimit $MaxAllowedStreak -ViolationList $violations
                }
                $prevSite = $site
                $currentStreakCount = 1
                $currentStreakStart = $timestamp
            } else {
                $currentStreakCount++
            }
            $prevTimestamp = $timestamp
        }
    }
}

if ($prevSite) {
    Complete-Streak -Site $prevSite -Count $currentStreakCount -StartTime $currentStreakStart -EndTime $prevTimestamp -StatsTable $siteStats -StreakLimit $MaxAllowedStreak -ViolationList $violations
}

$durationSeconds = $null
if ($timestampList.Count -ge 2) {
    $timestampsOrdered = $timestampList | Sort-Object
    $durationSeconds = ($timestampsOrdered[-1] - $timestampsOrdered[0]).TotalSeconds
}

$siteSummaries = @($siteStats.Values | Sort-Object LaunchCount -Descending)
$maxStreak = if ($siteSummaries) { ($siteSummaries | Measure-Object -Property MaxConsecutive -Maximum).Maximum } else { 0 }
$uniqueSiteCount = ($siteSummaries | Measure-Object).Count
$violationCount = ($violations | Measure-Object).Count
$passStatus = ($violationCount -eq 0)

$summary = [pscustomobject]@{
    GeneratedAtUtc     = (Get-Date).ToUniversalTime().ToString('o')
    FilesAnalyzed      = $files
    TotalLaunchEvents  = $launchCount
    UniqueSites        = $uniqueSiteCount
    DurationSeconds    = $durationSeconds
    MaxObservedStreak  = $maxStreak
    MaxAllowedStreak   = $MaxAllowedStreak
    SiteSummaries      = $siteSummaries
    Violations         = $violations
    ViolationCount     = $violationCount
    Pass               = $passStatus
    Metrics            = @{
        ActiveWorkers = (New-ScalarSummary -Name 'ActiveWorkers' -Values ([double[]]$activeWorkersValues))
        ActiveSites    = (New-ScalarSummary -Name 'ActiveSites' -Values ([double[]]$activeSitesValues))
        ThreadBudget   = (New-ScalarSummary -Name 'ThreadBudget' -Values ([double[]]$threadBudgetValues))
        QueuedJobs     = (New-ScalarSummary -Name 'QueuedJobs' -Values ([double[]]$queuedJobsValues))
        QueuedSites    = (New-ScalarSummary -Name 'QueuedSites' -Values ([double[]]$queuedSitesValues))
    }
}

if ($OutputPath) {
    $outputDir = Split-Path -Parent $OutputPath
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }
    $summary | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host ("Parser scheduler launch summary written to {0}" -f $OutputPath) -ForegroundColor Green
}

if ($PassThru -or -not $OutputPath) {
    return $summary
}
