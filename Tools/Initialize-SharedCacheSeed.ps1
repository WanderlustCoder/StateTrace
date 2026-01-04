<#
.SYNOPSIS
Initializes shared cache seed from fixtures or creates fallback seed.

.DESCRIPTION
ST-Q-002: Creates a lightweight shared cache seed for fixtures so warm runs
never start from empty cache. Also provides fallback logic to auto-use the
seed when no production snapshot is available.

.PARAMETER RepositoryRoot
Repository root path. Defaults to parent of script directory.

.PARAMETER SeedPath
Path to write the seed snapshot. Defaults to Tests/Fixtures/CISmoke/SharedCacheSeed.clixml.

.PARAMETER Sites
Sites to include in seed. Defaults to BOYO, WLLS.

.PARAMETER HostsPerSite
Number of hosts per site in seed. Defaults to 3.

.PARAMETER PortsPerHost
Number of port entries per host. Defaults to 10.

.PARAMETER CreateSeedFromLogs
If set, attempts to create seed from latest Logs/SharedCacheSnapshot snapshot.

.PARAMETER PassThru
Return the seed summary as an object.
#>
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$SeedPath,
    [string[]]$Sites = @('BOYO', 'WLLS'),
    [int]$HostsPerSite = 3,
    [int]$PortsPerHost = 10,
    [switch]$CreateSeedFromLogs,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

if (-not $SeedPath) {
    $SeedPath = Join-Path $repoRoot 'Tests\Fixtures\CISmoke\SharedCacheSeed.clixml'
}

Write-Host "Initializing shared cache seed..." -ForegroundColor Cyan

$seedEntries = [System.Collections.Generic.List[pscustomobject]]::new()

if ($CreateSeedFromLogs) {
    # Try to extract seed from latest production snapshot
    $snapshotDir = Join-Path $repoRoot 'Logs\SharedCacheSnapshot'
    $latestSnapshot = $null

    if (Test-Path -LiteralPath $snapshotDir) {
        $latestSnapshot = Get-ChildItem -LiteralPath $snapshotDir -Filter 'SharedCacheSnapshot-*.clixml' -File |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    }

    if ($latestSnapshot) {
        Write-Host ("  Using production snapshot: {0}" -f $latestSnapshot.Name) -ForegroundColor Cyan
        try {
            $rawEntries = Import-Clixml -LiteralPath $latestSnapshot.FullName

            foreach ($entry in @($rawEntries)) {
                if (-not $entry) { continue }
                $site = ''
                if ($entry.PSObject.Properties.Name -contains 'Site') { $site = ('' + $entry.Site).Trim() }
                elseif ($entry.PSObject.Properties.Name -contains 'SiteKey') { $site = ('' + $entry.SiteKey).Trim() }

                if ([string]::IsNullOrWhiteSpace($site)) { continue }
                if ($Sites -notcontains $site) { continue }

                # Limit hosts and ports for seed
                $entryValue = $entry
                if ($entry.PSObject.Properties.Name -contains 'Entry') { $entryValue = $entry.Entry }

                $hostMap = @{}
                if ($entryValue -and $entryValue.PSObject.Properties.Name -contains 'HostMap') {
                    $sourceHostMap = $entryValue.HostMap
                    $hostCount = 0
                    foreach ($hostKey in @($sourceHostMap.Keys) | Select-Object -First $HostsPerSite) {
                        $ports = $sourceHostMap[$hostKey]
                        if ($ports -is [System.Collections.IEnumerable] -and -not ($ports -is [string])) {
                            $hostMap[$hostKey] = @($ports | Select-Object -First $PortsPerHost)
                        } else {
                            $hostMap[$hostKey] = @($ports)
                        }
                        $hostCount++
                    }
                }

                $seedEntries.Add([pscustomobject]@{
                    SiteKey = $site
                    Entry   = [pscustomobject]@{
                        HostMap = $hostMap
                    }
                })
            }
        } catch {
            Write-Warning ("Failed to parse production snapshot: {0}" -f $_.Exception.Message)
        }
    }
}

# If no entries from logs, create synthetic seed
if ($seedEntries.Count -eq 0) {
    Write-Host "  Creating synthetic seed..." -ForegroundColor Cyan

    foreach ($site in $Sites) {
        $hostMap = @{}

        for ($h = 1; $h -le $HostsPerSite; $h++) {
            $siteNum = [math]::Ceiling($h / 2)
            $hostName = "{0}-A{1}-AS-{2}" -f $site, ('{0:00}' -f $siteNum), ('{0:00}' -f $h)
            $ports = [System.Collections.Generic.List[pscustomobject]]::new()

            for ($p = 1; $p -le $PortsPerHost; $p++) {
                $ports.Add([pscustomobject]@{
                    PortId       = "Ethernet{0}" -f $p
                    PortName     = "Ethernet{0}" -f $p
                    PortColor    = 'Green'
                    ConfigStatus = 'Compliant'
                    LastUpdated  = (Get-Date).ToString('o')
                })
            }

            $hostMap[$hostName] = $ports
        }

        $seedEntries.Add([pscustomobject]@{
            SiteKey = $site
            Entry   = [pscustomobject]@{
                HostMap = $hostMap
            }
        })
    }
}

# Write seed
$seedDir = Split-Path -Path $SeedPath -Parent
if ($seedDir -and -not (Test-Path -LiteralPath $seedDir)) {
    New-Item -ItemType Directory -Path $seedDir -Force | Out-Null
}

$seedEntries | Export-Clixml -LiteralPath $SeedPath -Force
Write-Host ("Seed written to: {0}" -f $SeedPath) -ForegroundColor Green

# Calculate summary
$totalHosts = 0
$totalPorts = 0

foreach ($entry in $seedEntries) {
    $hostMap = $entry.Entry.HostMap
    if ($hostMap -is [System.Collections.IDictionary]) {
        $totalHosts += $hostMap.Count
        foreach ($hostKey in @($hostMap.Keys)) {
            $ports = $hostMap[$hostKey]
            if ($ports -is [System.Collections.ICollection]) {
                $totalPorts += $ports.Count
            } elseif ($ports -is [System.Collections.IEnumerable] -and -not ($ports -is [string])) {
                $totalPorts += @($ports).Count
            } else {
                $totalPorts++
            }
        }
    }
}

$summary = [pscustomobject]@{
    SeedPath   = $SeedPath
    Sites      = $seedEntries.Count
    TotalHosts = $totalHosts
    TotalPorts = $totalPorts
    Created    = Get-Date -Format 'o'
}

Write-Host "`nSeed Summary:" -ForegroundColor Cyan
Write-Host ("  Sites: {0}" -f $summary.Sites)
Write-Host ("  Hosts: {0}" -f $summary.TotalHosts)
Write-Host ("  Ports: {0}" -f $summary.TotalPorts)

if ($PassThru) {
    return $summary
}
