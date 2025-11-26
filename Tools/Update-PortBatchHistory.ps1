[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$ReportPaths,

    [string]$HistoryPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Logs\Reports\PortBatchHistory.csv'),

    [switch]$PassThru
)

<#
.SYNOPSIS
Aggregates incremental-loading analyzer reports into a CSV history.

.DESCRIPTION
Reads one or more JSON reports emitted by `Tools\Analyze-PortBatchReadyTelemetry.ps1` and appends
their key metrics (ports/minute, UiClone p95, etc.) to a history CSV so UI performance trends
can be tracked over time. Existing entries (matched by ReportPath) are skipped automatically.

.EXAMPLE
pwsh Tools\Update-PortBatchHistory.ps1 -ReportPaths `
    Logs/Reports/PortBatchReady-20251113.json, `
    Logs/Reports/PortBatchReady-20251113-142949.json
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-HistoryRecord {
    param(
        [string]$ReportPath,
        [pscustomobject]$Report
    )

    $portSummary = $Report.PortBatchSummary
    $interfaceSummary = $Report.InterfaceSyncSummary
    $uiClone = $interfaceSummary.UiClone
    $dispatch = $interfaceSummary.StreamDispatch
    $diff = $interfaceSummary.DiffDuration

    return [pscustomobject]@{
        ReportPath        = (Resolve-Path -LiteralPath $ReportPath).Path
        GeneratedAtUtc    = $Report.GeneratedAtUtc
        MetricsFile       = $Report.FilesAnalyzed
        EventCount        = $portSummary.EventCount
        UniqueHosts       = $portSummary.UniqueHosts
        TotalPorts        = $portSummary.TotalPorts
        PortsPerMinute    = $portSummary.PortsPerMinute
        AvgPortsPerBatch  = $portSummary.AveragePortsBatch
        BatchIntervalP95  = $portSummary.BatchIntervalMs.P95
        UiCloneP95        = $uiClone.P95
        StreamDispatchP95 = $dispatch.P95
        DiffDurationP95   = $diff.P95
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

$existingRecords = @()
if (Test-Path -LiteralPath $resolvedHistoryPath) {
    $existingRecords = Import-Csv -LiteralPath $resolvedHistoryPath
}

$existingLookup = @{}
foreach ($record in $existingRecords) {
    if ($record.ReportPath) {
        $existingLookup[$record.ReportPath] = $true
    }
}

$newRecords = @()
foreach ($reportPath in $ReportPaths) {
    if (-not (Test-Path -LiteralPath $reportPath)) {
        Write-Warning ("Report '{0}' does not exist; skipping." -f $reportPath)
        continue
    }
    $resolvedReport = (Resolve-Path -LiteralPath $reportPath).Path
    if ($existingLookup.ContainsKey($resolvedReport)) {
        Write-Verbose ("Report '{0}' is already in the history. Skipping." -f $resolvedReport)
        continue
    }

    $json = Get-Content -LiteralPath $resolvedReport -Raw -ErrorAction Stop
    $reportObject = $json | ConvertFrom-Json -Depth 6
    if (-not $reportObject) {
        Write-Warning ("Report '{0}' is empty or invalid; skipping." -f $resolvedReport)
        continue
    }

    $historyRecord = ConvertTo-HistoryRecord -ReportPath $resolvedReport -Report $reportObject
    $existingLookup[$resolvedReport] = $true
    $newRecords += $historyRecord
}

if ($newRecords.Count -gt 0) {
    $allRecords = @()
    $allRecords += $existingRecords
    $allRecords += $newRecords
    $allRecords | Sort-Object GeneratedAtUtc | Export-Csv -LiteralPath $resolvedHistoryPath -NoTypeInformation
    Write-Host ("Updated history: {0}" -f $resolvedHistoryPath) -ForegroundColor DarkCyan
}
else {
    Write-Host "No new reports were added to the history." -ForegroundColor Yellow
}

if ($PassThru) {
    return $newRecords
}
