[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$ReportPaths,

    [string]$HistoryPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Logs\Reports\InterfaceSyncHistory.csv'),

    [switch]$PassThru
)

<#
.SYNOPSIS
Appends InterfaceSyncTiming analyzer reports to a CSV history.

.DESCRIPTION
Consumes JSON exported by `Tools\Analyze-InterfaceSyncTiming.ps1` and records key stats
(UiClone/Stream dispatch/Diff p95, site hot spots, top host) into a CSV so UI regression
signatures can be trended over time.

.EXAMPLE
pwsh Tools\Update-InterfaceSyncHistory.ps1 `
    -ReportPaths Logs/Reports/InterfaceSyncTiming-20251113-142949.json
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolingJsonPath = Join-Path -Path $PSScriptRoot -ChildPath 'ToolingJson.psm1'
if (-not (Test-Path -LiteralPath $toolingJsonPath)) {
    throw "ToolingJson module not found at '$toolingJsonPath'."
}
Import-Module -Name $toolingJsonPath -Force -ErrorAction Stop

function ConvertTo-HistoryRecord {
    param(
        [string]$ReportPath,
        [pscustomobject]$Report
    )

    $global = $Report.GlobalStats
    $site = $Report.SiteBreakdown | Sort-Object UiCloneP95 -Descending | Select-Object -First 1
    $topHost = $Report.HostBreakdownTop | Select-Object -First 1

    return [pscustomobject]@{
        ReportPath        = (Resolve-Path -LiteralPath $ReportPath).Path
        GeneratedAtUtc    = $Report.GeneratedAtUtc
        MetricsFile       = ($Report.FilesAnalyzed -join ';')
        EventCount        = $Report.EventCount
        UiCloneP95        = $global.UiClone.P95
        StreamDispatchP95 = $global.StreamDispatch.P95
        DiffDurationP95   = $global.DiffDuration.P95
        SiteCacheUpdateP95 = $global.SiteCacheUpdate.P95
        HottestSite       = if ($site) { $site.Site } else { '' }
        HottestSiteUiClone = if ($site) { $site.UiCloneP95 } else { $null }
        HottestHost       = if ($topHost) { $topHost.Host } else { '' }
        HottestHostUiClone = if ($topHost) { $topHost.UiCloneP95 } else { $null }
    }
}

$resolvedHistoryPath = $HistoryPath
if (-not [System.IO.Path]::IsPathRooted($resolvedHistoryPath)) {
    $resolvedHistoryPath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath $HistoryPath
}
$historyDir = Split-Path -Path $resolvedHistoryPath -Parent
if (-not (Test-Path -LiteralPath $historyDir)) {
    New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
}

$existing = @()
if (Test-Path -LiteralPath $resolvedHistoryPath) {
    $existing = Import-Csv -LiteralPath $resolvedHistoryPath
}
$existingLookup = @{}
foreach ($row in $existing) {
    if ($row.ReportPath) { $existingLookup[$row.ReportPath] = $true }
}

$newRows = [System.Collections.Generic.List[pscustomobject]]::new()
foreach ($reportPath in $ReportPaths) {
    if (-not (Test-Path -LiteralPath $reportPath)) {
        Write-Warning ("Report '{0}' not found; skipping." -f $reportPath)
        continue
    }
    $resolvedReport = (Resolve-Path -LiteralPath $reportPath).Path
    if ($existingLookup.ContainsKey($resolvedReport)) {
        Write-Verbose ("Report '{0}' already tracked." -f $resolvedReport)
        continue
    }
    try {
        $reportObject = Read-ToolingJson -Path $resolvedReport -Label 'Interface sync report'
    } catch {
        Write-Warning ("Report '{0}' could not be parsed as JSON: {1}" -f $resolvedReport, $_.Exception.Message)
        continue
    }
    if ($reportObject -is [System.Collections.IEnumerable] -and -not ($reportObject -is [string])) {
        $reportObject = $reportObject | Select-Object -First 1
    }
    if (-not $reportObject) { Write-Warning "Report '$resolvedReport' invalid."; continue }

    $historyRow = ConvertTo-HistoryRecord -ReportPath $resolvedReport -Report $reportObject
    $existingLookup[$resolvedReport] = $true
    $newRows.Add($historyRow)
}

if ($newRows.Count -gt 0) {
    $all = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $existing) { $all.Add($r) }
    foreach ($r in $newRows) { $all.Add($r) }
    $all | Sort-Object GeneratedAtUtc | Export-Csv -LiteralPath $resolvedHistoryPath -NoTypeInformation
    Write-Host ("InterfaceSync history updated: {0}" -f $resolvedHistoryPath) -ForegroundColor DarkCyan
}
else {
    Write-Host "No new InterfaceSync reports were added." -ForegroundColor Yellow
}

if ($PassThru) {
    return $newRows
}
