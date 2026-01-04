<#
.SYNOPSIS
Resolves a shared cache snapshot path, falling back to seed if needed.

.DESCRIPTION
ST-Q-002: Detects missing or old snapshots and auto-uses the tracked seed
bundle from Tests/Fixtures/CISmoke/SharedCacheSeed.clixml with a log note.

.PARAMETER SnapshotPath
Explicit snapshot path to use. If not specified, auto-discovers.

.PARAMETER RepositoryRoot
Repository root path. Defaults to parent of script directory.

.PARAMETER MaxAgeHours
Maximum age of snapshot in hours before fallback to seed. Default 168 (1 week).

.PARAMETER SeedPath
Path to seed snapshot. Defaults to Tests/Fixtures/CISmoke/SharedCacheSeed.clixml.

.PARAMETER RequiredSites
Sites that must be present in snapshot. Defaults to BOYO, WLLS.

.PARAMETER MinimumHostCount
Minimum host count required. Default 2.

.PARAMETER PassThru
Return resolution result as an object.
#>
param(
    [string]$SnapshotPath,
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [int]$MaxAgeHours = 168,
    [string]$SeedPath,
    [string[]]$RequiredSites = @('BOYO', 'WLLS'),
    [int]$MinimumHostCount = 2,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

if (-not $SeedPath) {
    $SeedPath = Join-Path $repoRoot 'Tests\Fixtures\CISmoke\SharedCacheSeed.clixml'
}

$result = [pscustomobject]@{
    ResolvedPath    = $null
    Source          = $null
    FallbackReason  = $null
    SnapshotAge     = $null
    SiteCount       = 0
    HostCount       = 0
    Valid           = $false
}

function Test-SnapshotValidity {
    param([string]$Path, [string[]]$RequiredSites, [int]$MinHostCount)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Valid = $false; Reason = 'FileNotFound'; Sites = 0; Hosts = 0 }
    }

    try {
        $entries = Import-Clixml -LiteralPath $Path
        $sites = [System.Collections.Generic.List[string]]::new()
        $hostCount = 0

        foreach ($entry in @($entries)) {
            if (-not $entry) { continue }
            $site = ''
            if ($entry.PSObject.Properties.Name -contains 'Site') { $site = ('' + $entry.Site).Trim() }
            elseif ($entry.PSObject.Properties.Name -contains 'SiteKey') { $site = ('' + $entry.SiteKey).Trim() }

            if (-not [string]::IsNullOrWhiteSpace($site) -and -not $sites.Contains($site)) {
                $sites.Add($site)
            }

            $entryValue = $entry
            if ($entry.PSObject.Properties.Name -contains 'Entry') { $entryValue = $entry.Entry }

            if ($entryValue -and $entryValue.PSObject.Properties.Name -contains 'HostMap') {
                $hostMap = $entryValue.HostMap
                if ($hostMap -is [System.Collections.IDictionary]) {
                    $hostCount += $hostMap.Count
                }
            }
        }

        # Check required sites
        $missingSites = @($RequiredSites | Where-Object { $sites -notcontains $_ })
        if ($missingSites.Count -gt 0) {
            return [pscustomobject]@{
                Valid  = $false
                Reason = "MissingSites: $($missingSites -join ', ')"
                Sites  = $sites.Count
                Hosts  = $hostCount
            }
        }

        # Check minimum hosts
        if ($hostCount -lt $MinHostCount) {
            return [pscustomobject]@{
                Valid  = $false
                Reason = "InsufficientHosts: $hostCount < $MinHostCount"
                Sites  = $sites.Count
                Hosts  = $hostCount
            }
        }

        return [pscustomobject]@{
            Valid  = $true
            Reason = $null
            Sites  = $sites.Count
            Hosts  = $hostCount
        }
    } catch {
        return [pscustomobject]@{
            Valid  = $false
            Reason = "ParseError: $($_.Exception.Message)"
            Sites  = 0
            Hosts  = 0
        }
    }
}

Write-Host "Resolving shared cache snapshot..." -ForegroundColor Cyan

# Try explicit path first
if ($SnapshotPath -and (Test-Path -LiteralPath $SnapshotPath)) {
    $validation = Test-SnapshotValidity -Path $SnapshotPath -RequiredSites $RequiredSites -MinHostCount $MinimumHostCount
    $fileInfo = Get-Item -LiteralPath $SnapshotPath
    $ageHours = [math]::Round(((Get-Date) - $fileInfo.LastWriteTime).TotalHours, 1)

    if ($validation.Valid -and $ageHours -le $MaxAgeHours) {
        $result.ResolvedPath = $SnapshotPath
        $result.Source = 'Explicit'
        $result.SnapshotAge = $ageHours
        $result.SiteCount = $validation.Sites
        $result.HostCount = $validation.Hosts
        $result.Valid = $true
        Write-Host ("  Using explicit snapshot: {0}" -f (Split-Path -Leaf $SnapshotPath)) -ForegroundColor Green
    } else {
        $result.FallbackReason = if (-not $validation.Valid) { $validation.Reason } else { "TooOld: ${ageHours}h > ${MaxAgeHours}h" }
        Write-Warning ("Explicit snapshot invalid: {0}" -f $result.FallbackReason)
    }
}

# Try auto-discovery from Logs
if (-not $result.Valid) {
    $snapshotDir = Join-Path $repoRoot 'Logs\SharedCacheSnapshot'
    if (Test-Path -LiteralPath $snapshotDir) {
        $candidates = Get-ChildItem -LiteralPath $snapshotDir -Filter 'SharedCacheSnapshot-*.clixml' -File |
            Sort-Object LastWriteTime -Descending

        foreach ($candidate in $candidates) {
            $validation = Test-SnapshotValidity -Path $candidate.FullName -RequiredSites $RequiredSites -MinHostCount $MinimumHostCount
            $ageHours = [math]::Round(((Get-Date) - $candidate.LastWriteTime).TotalHours, 1)

            if ($validation.Valid -and $ageHours -le $MaxAgeHours) {
                $result.ResolvedPath = $candidate.FullName
                $result.Source = 'AutoDiscovered'
                $result.SnapshotAge = $ageHours
                $result.SiteCount = $validation.Sites
                $result.HostCount = $validation.Hosts
                $result.Valid = $true
                Write-Host ("  Using discovered snapshot: {0} (age: {1}h)" -f $candidate.Name, $ageHours) -ForegroundColor Green
                break
            }
        }

        if (-not $result.Valid -and $candidates.Count -gt 0) {
            $result.FallbackReason = 'NoValidSnapshot: All candidates failed validation or too old'
        }
    }
}

# Fall back to seed
if (-not $result.Valid) {
    if (Test-Path -LiteralPath $SeedPath) {
        $validation = Test-SnapshotValidity -Path $SeedPath -RequiredSites $RequiredSites -MinHostCount $MinimumHostCount

        if ($validation.Valid) {
            $result.ResolvedPath = $SeedPath
            $result.Source = 'Seed'
            $result.FallbackReason = if ($result.FallbackReason) { $result.FallbackReason } else { 'NoProductionSnapshot' }
            $result.SiteCount = $validation.Sites
            $result.HostCount = $validation.Hosts
            $result.Valid = $true
            Write-Host ("  FALLBACK: Using seed snapshot: {0}" -f (Split-Path -Leaf $SeedPath)) -ForegroundColor Yellow
            Write-Host ("  Reason: {0}" -f $result.FallbackReason) -ForegroundColor Yellow
        } else {
            Write-Warning ("Seed snapshot also invalid: {0}" -f $validation.Reason)
            $result.FallbackReason = "SeedInvalid: $($validation.Reason)"
        }
    } else {
        Write-Warning "No seed snapshot found. Run Initialize-SharedCacheSeed.ps1 first."
        $result.FallbackReason = 'SeedNotFound'
    }
}

if (-not $result.Valid) {
    Write-Host "`nNo valid snapshot resolved. Warm runs may start from empty cache." -ForegroundColor Red
} else {
    Write-Host "`nResolution Summary:" -ForegroundColor Cyan
    Write-Host ("  Path: {0}" -f $result.ResolvedPath)
    Write-Host ("  Source: {0}" -f $result.Source)
    Write-Host ("  Sites: {0}, Hosts: {1}" -f $result.SiteCount, $result.HostCount)
    if ($result.FallbackReason) {
        Write-Host ("  Fallback reason: {0}" -f $result.FallbackReason) -ForegroundColor Yellow
    }
}

if ($PassThru) {
    return $result
}
