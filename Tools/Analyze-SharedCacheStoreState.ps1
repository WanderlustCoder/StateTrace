[CmdletBinding()]
param(
    [string[]]$Path,
    [string]$Directory,
    [int]$TopSites = 10,
    # LANDMARK: Shared cache diagnostics - allow null time filters
    [Nullable[datetime]]$StartTimeUtc,
    [Nullable[datetime]]$EndTimeUtc,
    [switch]$IncludeSiteBreakdown
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

function New-SiteOperationEntry {
    return @{
        GetHit  = 0
        GetMiss = 0
        Set     = 0
        Remove  = 0
        Other   = 0
        Total   = 0
    }
}

function Summarize-SharedCacheEvents {
    param(
        [string]$FilePath,
        [Nullable[datetime]]$StartTimeUtc,
        [Nullable[datetime]]$EndTimeUtc
    )

    $stateCounters = @{}
    $storeCounters = @{}
    $siteCounters  = @{}
    $firstTimestamp = $null
    $lastTimestamp  = $null

    Get-Content -LiteralPath $FilePath -ReadCount 200 | ForEach-Object {
        foreach ($line in $_) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $event = $null
            try {
                $event = $line | ConvertFrom-Json -ErrorAction Stop
            } catch {
                continue
            }
            if (-not $event -or -not $event.EventName) { continue }

            $ts = $null
            $tsUtc = $null
            if ($event.Timestamp) {
                try { $ts = [datetime]$event.Timestamp } catch { $ts = $null }
                if ($ts) {
                    $tsUtc = $ts.ToUniversalTime()
                }
            }
            if ($StartTimeUtc -or $EndTimeUtc) {
                if (-not $tsUtc) { continue }
                if ($StartTimeUtc -and $tsUtc -lt $StartTimeUtc) { continue }
                if ($EndTimeUtc -and $tsUtc -gt $EndTimeUtc) { continue }
            }
            if ($ts) {
                if (-not $firstTimestamp -or $ts -lt $firstTimestamp) { $firstTimestamp = $ts }
                if (-not $lastTimestamp -or $ts -gt $lastTimestamp) { $lastTimestamp = $ts }
            }

            switch ($event.EventName) {
                'InterfaceSiteCacheSharedStoreState' {
                    $operation = if ($event.PSObject.Properties.Name -contains 'Operation' -and
                        -not [string]::IsNullOrWhiteSpace($event.Operation)) { $event.Operation } else { 'Unknown' }
                    Add-Counter -Table $stateCounters -Key $operation
                }
                'InterfaceSiteCacheSharedStore' {
                    $operation = if ($event.Operation) { ('' + $event.Operation).Trim() } else { 'Unknown' }
                    Add-Counter -Table $storeCounters -Key $operation
                    $siteKey = if ($event.Site) { ('' + $event.Site).Trim() } else { 'Unknown' }
                    if (-not $siteCounters.ContainsKey($siteKey)) {
                        $siteCounters[$siteKey] = New-SiteOperationEntry
                    }
                    if ($siteCounters[$siteKey].ContainsKey($operation)) {
                        $siteCounters[$siteKey][$operation] += 1
                    } elseif ($operation -eq 'GetHit' -or $operation -eq 'GetMiss' -or
                          $operation -eq 'Set' -or $operation -eq 'Remove') {
                        $siteCounters[$siteKey][$operation] += 1
                    } else {
                        $siteCounters[$siteKey]['Other'] += 1
                    }
                    $siteCounters[$siteKey]['Total'] += 1
                }
            }
        }
    }

    $otherOps = 0
    foreach ($op in $storeCounters.Keys) {
        if ($op -notin @('GetMiss','GetHit','Set','Remove')) {
            $otherOps += [int]$storeCounters[$op]
        }
    }

    $summary = [pscustomobject]@{
        File                = $FilePath
        SnapshotImported    = (Get-CounterValue -Table $stateCounters -Key 'SnapshotImported')
        InitDelegatedStore  = (Get-CounterValue -Table $stateCounters -Key 'InitDelegatedStore')
        InitNewStore        = (Get-CounterValue -Table $stateCounters -Key 'InitNewStore')
        InitAdoptedStore    = (Get-CounterValue -Table $stateCounters -Key 'InitAdoptedStore')
        InitReuseStore      = (Get-CounterValue -Table $stateCounters -Key 'InitReuseStore')
        ClearRequested      = (Get-CounterValue -Table $stateCounters -Key 'ClearRequested')
        Cleared             = (Get-CounterValue -Table $stateCounters -Key 'Cleared')
        GetMiss             = (Get-CounterValue -Table $storeCounters -Key 'GetMiss')
        GetHit              = (Get-CounterValue -Table $storeCounters -Key 'GetHit')
        Set                 = (Get-CounterValue -Table $storeCounters -Key 'Set')
        Remove              = (Get-CounterValue -Table $storeCounters -Key 'Remove')
        OtherOperations     = $otherOps
        FirstTimestamp      = $firstTimestamp
        LastTimestamp       = $lastTimestamp
        StartTimeUtc        = $StartTimeUtc
        EndTimeUtc          = $EndTimeUtc
        TopSites            = @()
        SiteOperations      = $siteCounters
    }

    if ($siteCounters.Count -gt 0) {
        $topSites = $siteCounters.GetEnumerator() |
            Sort-Object { $_.Value.Total } -Descending |
            Select-Object -First $TopSites |
            ForEach-Object {
                [pscustomobject]@{
                    Site    = $_.Key
                    Total   = $_.Value.Total
                    Set     = $_.Value.Set
                    GetHit  = $_.Value.GetHit
                    GetMiss = $_.Value.GetMiss
                    Remove  = $_.Value.Remove
                    Other   = $_.Value.Other
                }
            }
        $summary.TopSites = $topSites
    }

    return $summary
}

$logFiles = Resolve-LogFiles -ExplicitPaths $Path -DirectoryPath $Directory     
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
$summaries = @()

foreach ($file in $logFiles) {
    Write-Verbose ("Analyzing shared cache events in '{0}'..." -f $file)        
    $summaries += Summarize-SharedCacheEvents -FilePath $file -StartTimeUtc $startUtc -EndTimeUtc $endUtc
}

if (-not $summaries -or $summaries.Count -eq 0) {
    Write-Warning 'No shared cache events were discovered in the supplied files.'
    return
}

$summaries |
    Select-Object File, SnapshotImported, InitDelegatedStore, InitNewStore, InitAdoptedStore, InitReuseStore,
                  GetMiss, GetHit, Set, Remove, FirstTimestamp, LastTimestamp |
    Format-Table -AutoSize

if ($IncludeSiteBreakdown) {
    foreach ($entry in $summaries) {
        Write-Host ''
        Write-Host ("Top shared cache sites for {0} (showing {1}):" -f $entry.File, $TopSites) -ForegroundColor Cyan
        if (-not $entry.TopSites -or $entry.TopSites.Count -eq 0) {
            Write-Host '  (no site activity recorded)' -ForegroundColor DarkGray
            continue
        }
        $entry.TopSites | Format-Table -AutoSize
    }
}

return $summaries
