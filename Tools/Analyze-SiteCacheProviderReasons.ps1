[CmdletBinding()]
param(
    [string[]]$Path,
    [string]$Directory,
    [string[]]$Site,
    [int]$TopHosts = 10,
    [datetime]$StartTimeUtc,
    [datetime]$EndTimeUtc,
    [switch]$IncludeHostBreakdown
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-LogFiles {
    param(
        [string[]]$ExplicitPaths,
        [string]$DirectoryPath
    )

    $files = @()
    if ($ExplicitPaths -and $ExplicitPaths.Count -gt 0) {
        foreach ($item in $ExplicitPaths) {
            if ([string]::IsNullOrWhiteSpace($item)) { continue }
            $resolved = Resolve-Path -LiteralPath $item -ErrorAction Stop
            foreach ($entry in $resolved) {
                if (Test-Path -LiteralPath $entry.ProviderPath -PathType Leaf) {
                    $files += $entry.ProviderPath
                }
            }
        }
    }

    if (-not $files -and $DirectoryPath) {
        $resolvedDirectory = Resolve-Path -LiteralPath $DirectoryPath -ErrorAction SilentlyContinue
        if ($resolvedDirectory) {
            $files = Get-ChildItem -LiteralPath $resolvedDirectory.ProviderPath -Filter '*.json' -File |
                Sort-Object LastWriteTime -Descending |
                Select-Object -ExpandProperty FullName
        }
    }

    if (-not $files -and -not $DirectoryPath) {
        $defaultDir = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Logs\IngestionMetrics'
        if (Test-Path -LiteralPath $defaultDir) {
            $files = Get-ChildItem -LiteralPath $defaultDir -Filter '*.json' -File |
                Sort-Object LastWriteTime -Descending |
                Select-Object -ExpandProperty FullName
        }
    }

    if (-not $files -or $files.Count -eq 0) {
        throw 'No ingestion metric files were found. Provide -Path or -Directory.'
    }

    return $files
}

function Add-Counter {
    param(
        [hashtable]$Table,
        [string]$Key,
        [int]$Amount = 1
    )

    if ([string]::IsNullOrWhiteSpace($Key)) { return }
    if ($Table.ContainsKey($Key)) {
        $Table[$Key] += $Amount
    } else {
        $Table[$Key] = $Amount
    }
}

# LANDMARK: PS5 compatibility - avoid null-coalescing operator
function Get-CounterValue {
    param(
        [hashtable]$Table,
        [string]$Key
    )

    if (-not $Table) { return 0 }
    if ($Table.ContainsKey($Key)) { return [int]$Table[$Key] }
    return 0
}

$siteFilter = $null
if ($Site -and $Site.Count -gt 0) {
    $siteFilter = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $Site) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        [void]$siteFilter.Add(($entry.Trim()))
    }
}

$startUtc = $null
$endUtc = $null
if ($StartTimeUtc) { $startUtc = $StartTimeUtc.ToUniversalTime() }
if ($EndTimeUtc) { $endUtc = $EndTimeUtc.ToUniversalTime() }
if ($startUtc -and $endUtc -and $startUtc -gt $endUtc) {
    throw "StartTimeUtc must be earlier than or equal to EndTimeUtc."
}
if ($startUtc -or $endUtc) {
    $startLabel = if ($startUtc) { $startUtc.ToString('o') } else { 'start' }
    $endLabel = if ($endUtc) { $endUtc.ToString('o') } else { 'end' }
    Write-Host ("Filtering events between {0} and {1} (UTC)." -f $startLabel, $endLabel) -ForegroundColor DarkGray
}

$siteStats = @{}
$hostStats = @{}

$logFiles = Resolve-LogFiles -ExplicitPaths $Path -DirectoryPath $Directory

foreach ($file in $logFiles) {
    Write-Verbose ("Analyzing site cache provider reasons in '{0}'..." -f $file)
    Get-Content -LiteralPath $file -ReadCount 200 | ForEach-Object {
        foreach ($line in $_) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $event = $null
            try {
                $event = $line | ConvertFrom-Json -ErrorAction Stop
            } catch {
                continue
            }
            if (-not $event -or $event.EventName -ne 'InterfaceSyncTiming') { continue }

            if ($startUtc -or $endUtc) {
                if (-not $event.Timestamp) { continue }
                $timestamp = $null
                try { $timestamp = [datetime]$event.Timestamp } catch { $timestamp = $null }
                if (-not $timestamp) { continue }
                $timestampUtc = $timestamp.ToUniversalTime()
                if ($startUtc -and $timestampUtc -lt $startUtc) { continue }
                if ($endUtc -and $timestampUtc -gt $endUtc) { continue }
            }

            $siteKey = ''
            if ($event.Site) {
                $siteKey = ('' + $event.Site).Trim()
            }
            if ([string]::IsNullOrWhiteSpace($siteKey)) { $siteKey = 'Unknown' }

            if ($siteFilter -and -not $siteFilter.Contains($siteKey)) { continue }

            if (-not $siteStats.ContainsKey($siteKey)) {
                $siteStats[$siteKey] = @{
                    Total          = 0
                    ProviderCounts = @{}
                    ReasonCounts   = @{}
                }
            }

            $provider = if ($event.PSObject.Properties.Name -contains 'SiteCacheProvider') {
                ('' + $event.SiteCacheProvider).Trim()
            } else { '' }
            if ([string]::IsNullOrWhiteSpace($provider)) { $provider = 'Unknown' }

            $reason = if ($event.PSObject.Properties.Name -contains 'SiteCacheProviderReason') {
                ('' + $event.SiteCacheProviderReason).Trim()
            } else { '' }
            if ([string]::IsNullOrWhiteSpace($reason)) { $reason = $provider }
            if ([string]::IsNullOrWhiteSpace($reason)) { $reason = 'Unknown' }

            $siteStats[$siteKey].Total++
            Add-Counter -Table $siteStats[$siteKey].ProviderCounts -Key $provider
            Add-Counter -Table $siteStats[$siteKey].ReasonCounts -Key $reason

            if ($IncludeHostBreakdown) {
                $hostname = if ($event.PSObject.Properties.Name -contains 'Hostname') {
                    ('' + $event.Hostname).Trim()
                } else { '' }
                if ([string]::IsNullOrWhiteSpace($hostname)) { $hostname = 'Unknown' }

                $hostKey = '{0}::{1}' -f $siteKey, $hostname
                if (-not $hostStats.ContainsKey($hostKey)) {
                $hostStats[$hostKey] = [pscustomobject]@{
                    Site          = $siteKey
                    Hostname      = $hostname
                    AccessRefresh = 0
                    AccessCacheHit= 0
                    SharedCacheMatch = 0
                        Total         = 0
                        LastReason    = ''
                        FetchDurations= [System.Collections.Generic.List[double]]::new()
                    }
                }

                $hostStats[$hostKey].Total++
                switch ($reason) {
                    'AccessRefresh' { $hostStats[$hostKey].AccessRefresh++ }
                    'AccessCacheHit' { $hostStats[$hostKey].AccessCacheHit++ }
                    'SharedCacheMatch' { $hostStats[$hostKey].SharedCacheMatch++ }
                }

                if ($event.PSObject.Properties.Name -contains 'SiteCacheFetchDurationMs') {
                    $duration = 0.0
                    try { $duration = [double]$event.SiteCacheFetchDurationMs } catch { $duration = 0.0 }
                    if ($duration -gt 0) {
                        $hostStats[$hostKey].FetchDurations.Add($duration)
                    }
                }

                $hostStats[$hostKey].LastReason = $reason
            }
        }
    }
}

if ($siteStats.Count -eq 0) {
    Write-Warning 'No InterfaceSyncTiming events with provider data were found.'
    return
}

$siteSummary = $siteStats.Keys |
    Sort-Object |
    ForEach-Object {
        $stats = $siteStats[$_]
        $total = [int]$stats.Total

        $reasonCounts = $stats.ReasonCounts
        $accessRefresh = (Get-CounterValue -Table $reasonCounts -Key 'AccessRefresh')
        $accessCacheHit = (Get-CounterValue -Table $reasonCounts -Key 'AccessCacheHit')
        $sharedCacheMatch = (Get-CounterValue -Table $reasonCounts -Key 'SharedCacheMatch')
        $skipUpdate = (Get-CounterValue -Table $reasonCounts -Key 'SkipSiteCacheUpdate')
        $unknown = (Get-CounterValue -Table $reasonCounts -Key 'Unknown')

        [pscustomobject]@{
            Site             = $_
            Total            = $total
            AccessRefresh    = $accessRefresh
            AccessCacheHit   = $accessCacheHit
            SharedCacheMatch = $sharedCacheMatch
            SkipSiteCacheUpdate = $skipUpdate
            Unknown          = $unknown
        }
    }

$siteSummary | Format-Table -AutoSize

if ($IncludeHostBreakdown -and $hostStats.Count -gt 0) {
    $hostEntries = $hostStats.Values | Where-Object { $_.AccessRefresh -gt 0 }
    $topHostEntries = $hostEntries | Sort-Object -Property AccessRefresh -Descending | Select-Object -First $TopHosts
    $topHostList = @()
    foreach ($entry in $topHostEntries) {
        $avgDuration = $null
        if ($entry.FetchDurations.Count -gt 0) {
            $avgDuration = [Math]::Round( ($entry.FetchDurations | Measure-Object -Average).Average, 3)
        }
        $topHostList += [pscustomobject]@{
            Site             = $entry.Site
            Hostname         = $entry.Hostname
            AccessRefresh    = $entry.AccessRefresh
            AccessCacheHit   = $entry.AccessCacheHit
            SharedCacheMatch = $entry.SharedCacheMatch
            Total            = $entry.Total
            AvgFetchMs       = $avgDuration
        }
    }

    if ($topHostList.Count -gt 0) {
        Write-Host ''
        Write-Host ("Top hosts with AccessRefresh (showing {0}):" -f $TopHosts) -ForegroundColor Cyan
        $topHostList | Format-Table -AutoSize
    } else {
        Write-Host ''
        Write-Host 'No hosts reported AccessRefresh events.' -ForegroundColor DarkGray
    }
}

return $siteSummary
