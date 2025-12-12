<#
.SYNOPSIS
Validates a shared cache snapshot (clixml or summary JSON) for coverage and required sites.

.PARAMETER Path
Snapshot file path (`SharedCacheSnapshot-*.clixml` or `*-summary.json`).

.PARAMETER MinimumSiteCount
Fail if site count is below this value.

.PARAMETER MinimumHostCount
Fail if total host count is below this value.

.PARAMETER MinimumTotalRowCount
Fail if total row count is below this value (best-effort when row data is present).

.PARAMETER RequiredSites
Fail if any of these site codes are missing.

.PARAMETER PassThru
Return the summary object instead of only writing/throwing.
#>
param(
    [Parameter(Mandatory)][string]$Path,
    [int]$MinimumSiteCount = 1,
    [int]$MinimumHostCount = 1,
    [int]$MinimumTotalRowCount = 1,
    [string[]]$RequiredSites = @(),
    [switch]$PassThru
)

Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $Path)) {
    throw ("Snapshot file not found: {0}" -f $Path)
}

$resolvedPath = (Resolve-Path -LiteralPath $Path).Path
$ext = [System.IO.Path]::GetExtension($resolvedPath).ToLowerInvariant()

function Convert-SnapshotToSummary {
    param($Entries)

    $summary = @()
    foreach ($entry in @($Entries)) {
        if (-not $entry) { continue }
        $site = ''
        if ($entry.PSObject.Properties.Name -contains 'Site') { $site = ('' + $entry.Site).Trim() }
        elseif ($entry.PSObject.Properties.Name -contains 'SiteKey') { $site = ('' + $entry.SiteKey).Trim() }
        if ([string]::IsNullOrWhiteSpace($site)) { continue }

        $hostCount = 0
        $rowCount = 0

        $entryValue = $entry
        if ($entry.PSObject.Properties.Name -contains 'Entry') { $entryValue = $entry.Entry }

        if ($entryValue) {
            if ($entryValue.PSObject.Properties.Name -contains 'Hosts') {
                $hostCount = @($entryValue.Hosts).Count
            } elseif ($entryValue.PSObject.Properties.Name -contains 'HostMap') {
                $hostCount = @($entryValue.HostMap.Keys).Count

                $hostMap = $entryValue.HostMap
                if ($hostMap -is [System.Collections.IDictionary]) {
                    foreach ($hostKey in @($hostMap.Keys)) {
                        $ports = $hostMap[$hostKey]
                        if ($null -eq $ports) { continue }

                        if ($ports -is [System.Collections.ICollection]) {
                            try { $rowCount += [int]$ports.Count } catch { $rowCount++ }
                        } elseif ($ports -is [System.Collections.IEnumerable] -and -not ($ports -is [string])) {
                            try { $rowCount += @($ports).Count } catch { $rowCount++ }
                        } else {
                            $rowCount++
                        }
                    }
                } elseif ($hostMap -is [System.Collections.ICollection]) {
                    try { $rowCount = [int]$hostMap.Count } catch { $rowCount = 0 }
                } elseif ($hostMap -is [System.Collections.IEnumerable] -and -not ($hostMap -is [string])) {
                    try { $rowCount = @($hostMap).Count } catch { $rowCount = 0 }
                }
            }

            if ($rowCount -le 0 -and $entryValue.PSObject.Properties.Name -contains 'TotalRows') {
                $rowCount = [int]$entryValue.TotalRows
            }
        }

        $summary += [pscustomobject]@{
            Site      = $site
            Hosts     = $hostCount
            TotalRows = $rowCount
        }
    }

    $summary
}

$summaryEntries = @()

if ($ext -eq '.json') {
    try {
        $summaryEntries = Get-Content -LiteralPath $resolvedPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw ("Failed to parse snapshot summary JSON '{0}': {1}" -f $resolvedPath, $_.Exception.Message)
    }
} else {
    try {
        $rawEntries = Import-Clixml -LiteralPath $resolvedPath
    } catch {
        throw ("Failed to import snapshot '{0}': {1}" -f $resolvedPath, $_.Exception.Message)
    }
    $summaryEntries = Convert-SnapshotToSummary -Entries $rawEntries
}

$siteCount = @($summaryEntries).Count
$hostCount = @($summaryEntries | ForEach-Object { $_.Hosts }) | Measure-Object -Sum | Select-Object -ExpandProperty Sum
$rowCount = @($summaryEntries | ForEach-Object { $_.TotalRows }) | Measure-Object -Sum | Select-Object -ExpandProperty Sum

if ($null -eq $hostCount) { $hostCount = 0 }
if ($null -eq $rowCount) { $rowCount = 0 }

$missingSites = @()
if ($RequiredSites -and $RequiredSites.Count -gt 0) {
    $present = @($summaryEntries | ForEach-Object { $_.Site }) | Select-Object -Unique
    foreach ($req in $RequiredSites) {
        if ($present -notcontains $req) { $missingSites += $req }
    }
}

$summary = [pscustomobject]@{
    Path       = $resolvedPath
    SiteCount  = $siteCount
    HostCount  = $hostCount
    TotalRows  = $rowCount
    MissingSites = $missingSites
}

$errors = @()
if ($siteCount -lt $MinimumSiteCount) { $errors += "SiteCount {0} < minimum {1}" -f $siteCount, $MinimumSiteCount }
if ($hostCount -lt $MinimumHostCount) { $errors += "HostCount {0} < minimum {1}" -f $hostCount, $MinimumHostCount }
if ($rowCount -lt $MinimumTotalRowCount) { $errors += "TotalRows {0} < minimum {1}" -f $rowCount, $MinimumTotalRowCount }
if ($missingSites -and $missingSites.Count -gt 0) { $errors += ("Missing required sites: {0}" -f ($missingSites -join ', ')) }

if ($errors -and $errors.Count -gt 0) {
    $msg = $errors -join '; '
    throw ("Shared cache snapshot check failed: {0}" -f $msg)
}

Write-Host ("Shared cache snapshot check passed. Sites={0}, Hosts={1}, Rows={2}" -f $siteCount, $hostCount, $rowCount) -ForegroundColor Green
if ($PassThru) { return $summary }
