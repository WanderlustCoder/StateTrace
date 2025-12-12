[CmdletBinding()]
param(
    [string]$SnapshotPath,
    [switch]$All,
    [switch]$ListHosts,
    [switch]$ShowPorts,
    [switch]$Raw
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DefaultSnapshotDirectory {
    try {
        $projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    } catch {
        $projectRoot = (Split-Path -Parent $PSScriptRoot)
    }
    return (Join-Path $projectRoot 'Logs\SharedCacheSnapshot')
}

function Get-SnapshotFiles {
    param(
        [string]$PathValue,
        [switch]$AllFiles
    )

    $resolvedPaths = @()
    if (-not [string]::IsNullOrWhiteSpace($PathValue)) {
        try {
            $resolved = (Resolve-Path -LiteralPath $PathValue -ErrorAction Stop).Path
            $resolvedPaths += $resolved
        } catch {
            throw "Snapshot path '$PathValue' was not found."
        }
    } else {
        $snapshotDir = Get-DefaultSnapshotDirectory
        if (-not (Test-Path -LiteralPath $snapshotDir)) {
            throw "Snapshot directory '$snapshotDir' does not exist. Run the pipeline at least once to generate a snapshot."
        }

        if ($AllFiles) {
            $resolvedPaths += Get-ChildItem -LiteralPath $snapshotDir -Filter 'SharedCacheSnapshot-*.clixml' |
                Sort-Object LastWriteTime -Descending |
                Select-Object -ExpandProperty FullName
        }

        if (-not $resolvedPaths) {
            $latestPath = Join-Path -Path $snapshotDir -ChildPath 'SharedCacheSnapshot-latest.clixml'
            if (-not (Test-Path -LiteralPath $latestPath)) {
                throw "No snapshot files found under '$snapshotDir'. Ensure the pipeline exported snapshots successfully."
            }
            $resolvedPaths = @([System.IO.Path]::GetFullPath($latestPath))
        }
    }

    return $resolvedPaths
}

function Read-SnapshotEntries {
    param([string]$FilePath)

    try {
        $entries = Import-Clixml -Path $FilePath
        if ($entries -is [System.Collections.IEnumerable]) {
            return @($entries)
        }
        return @($entries)
    } catch {
        throw "Failed to import snapshot '$FilePath': $($_.Exception.Message)"
    }
}

function Get-EntrySummary {
    param(
        [object]$Entry,
        [string]$SourcePath
    )

    $hostCount = 0
    $rowCount = 0
    $cachedAt = $null
    $hostMapType = ''
    $siteValue = ''

    if ($Entry.PSObject.Properties.Name -contains 'Entry') {
        $snapshotEntry = $Entry.Entry
    } else {
        $snapshotEntry = $Entry
    }

    if ($Entry.PSObject.Properties.Name -contains 'Site') {
        try { $siteValue = ('' + $Entry.Site).Trim() } catch { $siteValue = '' }
    } elseif ($Entry.PSObject.Properties.Name -contains 'SiteKey') {
        try { $siteValue = ('' + $Entry.SiteKey).Trim() } catch { $siteValue = '' }
    } elseif ($snapshotEntry -and $snapshotEntry.PSObject.Properties.Name -contains 'SiteKey') {
        try { $siteValue = ('' + $snapshotEntry.SiteKey).Trim() } catch { $siteValue = '' }
    }

    if ($snapshotEntry -and $snapshotEntry.PSObject.Properties.Name -contains 'HostCount') {
        try { $hostCount = [int]$snapshotEntry.HostCount } catch { $hostCount = 0 }
    }
    if ($snapshotEntry -and $snapshotEntry.PSObject.Properties.Name -contains 'TotalRows') {
        try { $rowCount = [int]$snapshotEntry.TotalRows } catch { $rowCount = 0 }
    }
    if ($snapshotEntry -and $snapshotEntry.PSObject.Properties.Name -contains 'CachedAt') {
        $cachedAt = $snapshotEntry.CachedAt
    }
    if ($snapshotEntry -and $snapshotEntry.PSObject.Properties.Name -contains 'HostMap') {
        $hostMap = $null
        try { $hostMap = $snapshotEntry.HostMap } catch { $hostMap = $null }
        try {
            if ($hostMap) {
                $hostMapType = $hostMap.GetType().FullName
            }
        } catch {
            $hostMapType = ''
        }
        if ($hostCount -le 0 -and $hostMap -is [System.Collections.IDictionary]) {
            try { $hostCount = [int]$hostMap.Count } catch { $hostCount = 0 }
        }
        if ($rowCount -le 0 -and $hostMap -is [System.Collections.IDictionary]) {
            foreach ($value in $hostMap.Values) {
                if ($value -is [System.Collections.IDictionary] -or $value -is [System.Collections.ICollection]) {
                    try { $rowCount += [int]$value.Count } catch { }
                } elseif ($null -ne $value) {
                    $rowCount++
                }
            }
        }
    }

    [pscustomobject]@{
        Site        = $siteValue
        Hosts       = $hostCount
        TotalRows   = $rowCount
        CachedAt    = $cachedAt
        HostMapType = $hostMapType
        Source      = $SourcePath
        Entry       = $snapshotEntry
    }
}

function Write-EntryDetail {
    param(
        [pscustomobject]$Summary,
        [switch]$IncludePorts
    )

    Write-Host ("Site: {0}  Hosts: {1}  Rows: {2}  CachedAt: {3}" -f `
        $Summary.Site, $Summary.Hosts, $Summary.TotalRows, $Summary.CachedAt) -ForegroundColor Cyan

    if (-not $IncludePorts) {
        return
    }

    $hostMap = $Summary.Entry.HostMap
    if (-not $hostMap) {
        Write-Host '  (Host map unavailable)' -ForegroundColor DarkGray
        return
    }

    foreach ($hostKey in ($hostMap.Keys | Sort-Object)) {
        $ports = $hostMap[$hostKey]
        $portCount = 0
        if ($ports -is [System.Collections.ICollection]) {
            try { $portCount = $ports.Count } catch { $portCount = 0 }
        }
        Write-Host ("  Host {0} ({1} port{2})" -f `
            $hostKey, $portCount, $(if ($portCount -eq 1) { '' } else { 's' })) -ForegroundColor DarkGray

        if ($IncludePorts) {
            $portKeys = @()
            if ($ports -is [System.Collections.IDictionary]) {
                $portKeys = $ports.Keys
            } elseif ($ports -is [System.Collections.IEnumerable]) {
                $portKeys = $ports | ForEach-Object { $_.Name }
            }
            foreach ($portKey in ($portKeys | Sort-Object)) {
                Write-Host ("    - {0}" -f $portKey) -ForegroundColor DarkGray
            }
        }
    }
}

$filesToInspect = Get-SnapshotFiles -PathValue $SnapshotPath -AllFiles:$All
$summaries = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($file in $filesToInspect) {
    $entries = Read-SnapshotEntries -FilePath $file
    foreach ($entry in $entries) {
        if (-not $entry) { continue }
        $summaries.Add((Get-EntrySummary -Entry $entry -SourcePath $file)) | Out-Null
    }
}

if ($Raw) {
    $summaries
    return
}

if (-not $summaries) {
    Write-Host 'No shared cache entries found in the selected snapshot(s).' -ForegroundColor Yellow
    return
}

$summaries |
    Sort-Object Source, Site |
    Select-Object Source, Site, Hosts, TotalRows, CachedAt |
    Format-Table -AutoSize

if ($ListHosts -or $ShowPorts) {
    foreach ($summary in $summaries) {
        Write-EntryDetail -Summary $summary -IncludePorts:$ShowPorts
    }
}
