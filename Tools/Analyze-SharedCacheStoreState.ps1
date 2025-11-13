[CmdletBinding()]
param(
    [string[]]$Path,
    [string]$Directory,
    [int]$TopSites = 10,
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
    param([string]$FilePath)

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

            if ($event.Timestamp) {
                $ts = $null
                try { $ts = [datetime]$event.Timestamp } catch { $ts = $null }
                if ($ts) {
                    if (-not $firstTimestamp -or $ts -lt $firstTimestamp) { $firstTimestamp = $ts }
                    if (-not $lastTimestamp -or $ts -gt $lastTimestamp) { $lastTimestamp = $ts }
                }
            }

            switch ($event.EventName) {
                'InterfaceSiteCacheSharedStoreState' {
                    Add-Counter -Table $stateCounters -Key ($event.Operation ?? 'Unknown')
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
        SnapshotImported    = ($stateCounters['SnapshotImported']  ?? 0)
        InitNewStore        = ($stateCounters['InitNewStore'] ?? 0)
        InitAdoptedStore    = ($stateCounters['InitAdoptedStore'] ?? 0)
        InitReuseStore      = ($stateCounters['InitReuseStore'] ?? 0)
        ClearRequested      = ($stateCounters['ClearRequested'] ?? 0)
        Cleared             = ($stateCounters['Cleared'] ?? 0)
        GetMiss             = ($storeCounters['GetMiss'] ?? 0)
        GetHit              = ($storeCounters['GetHit'] ?? 0)
        Set                 = ($storeCounters['Set'] ?? 0)
        Remove              = ($storeCounters['Remove'] ?? 0)
        OtherOperations     = $otherOps
        FirstTimestamp      = $firstTimestamp
        LastTimestamp       = $lastTimestamp
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
$summaries = @()

foreach ($file in $logFiles) {
    Write-Verbose ("Analyzing shared cache events in '{0}'..." -f $file)
    $summaries += Summarize-SharedCacheEvents -FilePath $file
}

if (-not $summaries -or $summaries.Count -eq 0) {
    Write-Warning 'No shared cache events were discovered in the supplied files.'
    return
}

$summaries |
    Select-Object File, SnapshotImported, InitNewStore, InitAdoptedStore, InitReuseStore,
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
