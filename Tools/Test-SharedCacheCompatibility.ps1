<#
.SYNOPSIS
Validates shared cache snapshot compatibility before import.

.DESCRIPTION
ST-Q-004: Before import, validates schema/version and site list to refuse
incompatible snapshots and suggest regeneration.

Checks performed:
- Schema version compatibility (clixml structure validation)
- Required sites present (configurable list)
- Minimum host/row counts
- Entry structure validation (HostMap, Port entries)
- Age/freshness check

.PARAMETER SnapshotPath
Path to shared cache snapshot (clixml).

.PARAMETER RequiredSites
Sites that must be present in the snapshot.

.PARAMETER MinimumHosts
Minimum total host count required.

.PARAMETER MaxAgeHours
Maximum snapshot age in hours. Default 168 (7 days).

.PARAMETER RepositoryRoot
Repository root path. Defaults to parent of script directory.

.PARAMETER OutputPath
Optional JSON output path for the compatibility report.

.PARAMETER FailOnIncompatible
Exit with error code if snapshot is incompatible.

.PARAMETER PassThru
Return the compatibility result as an object.

.EXAMPLE
.\Test-SharedCacheCompatibility.ps1 -SnapshotPath Logs\SharedCacheSnapshot\SharedCacheSnapshot-latest.clixml

.EXAMPLE
.\Test-SharedCacheCompatibility.ps1 -RequiredSites BOYO,WLLS -FailOnIncompatible
#>
param(
    [string]$SnapshotPath,
    [string[]]$RequiredSites = @('BOYO', 'WLLS'),
    [int]$MinimumHosts = 5,
    [int]$MaxAgeHours = 168,
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$OutputPath,
    [switch]$FailOnIncompatible,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

Write-Host "Validating shared cache snapshot compatibility..." -ForegroundColor Cyan

# Auto-discover snapshot if not provided
if (-not $SnapshotPath) {
    $snapshotDir = Join-Path $repoRoot 'Logs\SharedCacheSnapshot'
    if (Test-Path -LiteralPath $snapshotDir) {
        $latest = Get-ChildItem -LiteralPath $snapshotDir -Filter 'SharedCacheSnapshot-*.clixml' -File |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) {
            $SnapshotPath = $latest.FullName
        }
    }
}

$issues = [System.Collections.Generic.List[pscustomobject]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$suggestions = [System.Collections.Generic.List[string]]::new()

$result = [pscustomobject]@{
    Timestamp     = Get-Date -Format 'o'
    SnapshotPath  = $SnapshotPath
    Compatible    = $true
    SchemaValid   = $false
    SitesValid    = $false
    HostsValid    = $false
    AgeValid      = $false
    Issues        = $issues
    Warnings      = $warnings
    Suggestions   = $suggestions
    Metrics       = $null
}

# Check if snapshot exists
if (-not $SnapshotPath) {
    $issues.Add([pscustomobject]@{
        Type    = 'SnapshotMissing'
        Message = 'No snapshot found for compatibility check'
    })
    $suggestions.Add('Run Tools\Invoke-SharedCacheWarmup.ps1 to generate a snapshot')
    $result.Compatible = $false
}
elseif (-not (Test-Path -LiteralPath $SnapshotPath)) {
    $issues.Add([pscustomobject]@{
        Type    = 'SnapshotNotFound'
        Message = ("Snapshot file not found: {0}" -f $SnapshotPath)
    })
    $suggestions.Add('Verify the snapshot path or run Tools\Invoke-SharedCacheWarmup.ps1')
    $result.Compatible = $false
}
else {
    Write-Host ("  Checking: {0}" -f (Split-Path -Leaf $SnapshotPath)) -ForegroundColor Cyan

    $fileInfo = Get-Item -LiteralPath $SnapshotPath

    # Age check
    $ageHours = ((Get-Date) - $fileInfo.LastWriteTime).TotalHours
    if ($ageHours -gt $MaxAgeHours) {
        $issues.Add([pscustomobject]@{
            Type     = 'SnapshotTooOld'
            Message  = ("Snapshot is {0:N1} hours old, exceeds max {1} hours" -f $ageHours, $MaxAgeHours)
            AgeHours = [math]::Round($ageHours, 1)
            MaxAge   = $MaxAgeHours
        })
        $suggestions.Add('Regenerate snapshot using Tools\Invoke-SharedCacheWarmup.ps1 -ExportSharedCacheSnapshot')
        $result.Compatible = $false
    }
    else {
        $result.AgeValid = $true
    }

    # Try to import and validate schema
    $entries = $null
    try {
        $entries = Import-Clixml -LiteralPath $SnapshotPath
        $result.SchemaValid = $true
    }
    catch {
        $issues.Add([pscustomobject]@{
            Type    = 'SchemaInvalid'
            Message = ("Failed to import snapshot: {0}" -f $_.Exception.Message)
        })
        $suggestions.Add('Snapshot file may be corrupted. Regenerate using Tools\Invoke-SharedCacheWarmup.ps1')
        $result.Compatible = $false
    }

    if ($entries) {
        # Validate entry structure
        $sites = [System.Collections.Generic.Dictionary[string,pscustomobject]]::new()
        $totalHosts = 0
        $totalRows = 0
        $structureIssues = 0

        foreach ($entry in @($entries)) {
            if (-not $entry) { continue }

            $entryValue = $entry
            if ($entry.PSObject.Properties.Name -contains 'Entry') {
                $entryValue = $entry.Entry
            }

            # Extract site info
            $siteName = $null
            if ($entry.PSObject.Properties.Name -contains 'Key') {
                $siteName = $entry.Key
            }
            elseif ($entryValue -and $entryValue.PSObject.Properties.Name -contains 'SiteKey') {
                $siteName = $entryValue.SiteKey
            }

            if (-not $siteName) {
                $structureIssues++
                continue
            }

            # Extract host map
            $hostCount = 0
            $rowCount = 0

            if ($entryValue -and $entryValue.PSObject.Properties.Name -contains 'HostMap') {
                $hostMap = $entryValue.HostMap
                if ($hostMap -is [System.Collections.IDictionary]) {
                    $hostCount = $hostMap.Count
                    foreach ($hostKey in @($hostMap.Keys)) {
                        $ports = $hostMap[$hostKey]
                        if ($ports -is [System.Collections.ICollection]) {
                            $rowCount += $ports.Count
                        }
                        elseif ($ports -is [System.Collections.IEnumerable] -and -not ($ports -is [string])) {
                            $rowCount += @($ports).Count
                        }
                        else {
                            $rowCount++
                        }
                    }
                }
            }

            $totalHosts += $hostCount
            $totalRows += $rowCount

            $sites[$siteName] = [pscustomobject]@{
                SiteName  = $siteName
                HostCount = $hostCount
                RowCount  = $rowCount
            }
        }

        # Record metrics
        $result.Metrics = [pscustomobject]@{
            SiteCount       = $sites.Count
            TotalHostCount  = $totalHosts
            TotalRowCount   = $totalRows
            AgeHours        = [math]::Round($ageHours, 1)
            SizeBytes       = $fileInfo.Length
            StructureIssues = $structureIssues
            Sites           = @($sites.Values)
        }

        if ($structureIssues -gt 0) {
            $warnings.Add(("Found {0} entries with missing site keys" -f $structureIssues))
        }

        # Validate required sites
        $missingSites = [System.Collections.Generic.List[string]]::new()
        foreach ($requiredSite in $RequiredSites) {
            if (-not $sites.ContainsKey($requiredSite)) {
                $missingSites.Add($requiredSite)
            }
        }

        if ($missingSites.Count -gt 0) {
            $issues.Add([pscustomobject]@{
                Type         = 'MissingSites'
                Message      = ("Missing required sites: {0}" -f ($missingSites -join ', '))
                MissingSites = @($missingSites)
            })
            $suggestions.Add(("Regenerate snapshot with coverage for: {0}" -f ($missingSites -join ', ')))
            $result.Compatible = $false
        }
        else {
            $result.SitesValid = $true
        }

        # Validate host count
        if ($totalHosts -lt $MinimumHosts) {
            $issues.Add([pscustomobject]@{
                Type    = 'InsufficientHosts'
                Message = ("Host count {0} is below minimum {1}" -f $totalHosts, $MinimumHosts)
                Current = $totalHosts
                Minimum = $MinimumHosts
            })
            $suggestions.Add('Regenerate snapshot with more host coverage')
            $result.Compatible = $false
        }
        else {
            $result.HostsValid = $true
        }

        # Validate schema version (check for expected structure)
        $hasValidStructure = $true
        foreach ($site in $sites.Values) {
            if ($site.HostCount -eq 0 -and $site.RowCount -eq 0) {
                $warnings.Add(("Site {0} has no host/row data" -f $site.SiteName))
            }
        }

        if ($sites.Count -eq 0) {
            $issues.Add([pscustomobject]@{
                Type    = 'EmptySnapshot'
                Message = 'Snapshot contains no valid site entries'
            })
            $suggestions.Add('Regenerate snapshot using Tools\Invoke-SharedCacheWarmup.ps1')
            $result.Compatible = $false
            $hasValidStructure = $false
        }

        if (-not $hasValidStructure) {
            $result.SchemaValid = $false
        }
    }
}

# Output
if ($OutputPath) {
    $outputDir = Split-Path -Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host ("Report written to: {0}" -f $OutputPath) -ForegroundColor Green
}

# Display summary
Write-Host "`nCompatibility Check Summary:" -ForegroundColor Cyan

if ($result.Metrics) {
    Write-Host ("  Sites: {0}" -f $result.Metrics.SiteCount)
    Write-Host ("  Hosts: {0} (min: {1})" -f $result.Metrics.TotalHostCount, $MinimumHosts)
    Write-Host ("  Rows: {0}" -f $result.Metrics.TotalRowCount)
    Write-Host ("  Age: {0:N1} hours (max: {1})" -f $result.Metrics.AgeHours, $MaxAgeHours)
    Write-Host ("  Size: {0:N0} KB" -f ($result.Metrics.SizeBytes / 1KB))
}

Write-Host "`n  Checks:" -ForegroundColor Cyan
$checks = @(
    @{ Name = 'Schema'; Valid = $result.SchemaValid }
    @{ Name = 'Sites'; Valid = $result.SitesValid }
    @{ Name = 'Hosts'; Valid = $result.HostsValid }
    @{ Name = 'Age'; Valid = $result.AgeValid }
)
foreach ($check in $checks) {
    $status = if ($check.Valid) { 'OK' } else { 'FAIL' }
    $color = if ($check.Valid) { 'Green' } else { 'Red' }
    Write-Host ("    [{0}] {1}" -f $status, $check.Name) -ForegroundColor $color
}

if ($warnings.Count -gt 0) {
    Write-Host ("`nWarnings: {0}" -f $warnings.Count) -ForegroundColor Yellow
    foreach ($w in $warnings) {
        Write-Host ("  - {0}" -f $w) -ForegroundColor Yellow
    }
}

if ($issues.Count -gt 0) {
    Write-Host ("`nIssues: {0}" -f $issues.Count) -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host ("  - [{0}] {1}" -f $issue.Type, $issue.Message) -ForegroundColor Red
    }

    Write-Host "`nSuggestions:" -ForegroundColor Yellow
    foreach ($sug in ($suggestions | Select-Object -Unique)) {
        Write-Host ("  - {0}" -f $sug) -ForegroundColor Yellow
    }
}

if ($result.Compatible) {
    Write-Host "`nStatus: COMPATIBLE - Snapshot is valid for import" -ForegroundColor Green
}
else {
    Write-Host "`nStatus: INCOMPATIBLE - Snapshot should not be imported" -ForegroundColor Red
}

if ($FailOnIncompatible -and -not $result.Compatible) {
    Write-Error "Compatibility check failed with $($issues.Count) issue(s)"
    exit 2
}

if ($PassThru) {
    return $result
}
