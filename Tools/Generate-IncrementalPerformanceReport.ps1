[CmdletBinding()]
param(
    [string]$PortHistoryPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Logs\Reports\PortBatchHistory.csv'),
    [string]$InterfaceHistoryPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Logs\Reports\InterfaceSyncHistory.csv'),
    [string]$QueueDelayHistoryPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Logs\Reports\QueueDelayHistory.csv'),
    [string]$SchedulerHistoryPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Logs\Reports\ParserSchedulerHistory.csv'),
    [string]$OutputPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'docs\performance\IncrementalLoading_Report.md'),
    [int]$Recent = 10
)

<#
.SYNOPSIS
Generates a markdown summary of incremental-loading performance history.

.DESCRIPTION
Reads `PortBatchHistory.csv` and `InterfaceSyncHistory.csv` (produced by
`Tools\Update-PortBatchHistory.ps1` / `Tools\Update-InterfaceSyncHistory.ps1`) and emits a markdown
report showing the most recent runs (ports/minute, total ports, UiClone p95, hot hosts, etc.).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-History {
    param(
        [string]$Path,
        [string]$Name
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Name history '$Path' does not exist. Run the corresponding Update-*History script first."
    }
    return Import-Csv -LiteralPath $Path | Sort-Object GeneratedAtUtc
}

$portHistory = Resolve-History -Path $PortHistoryPath -Name 'Port batch'
$interfaceHistory = Resolve-History -Path $InterfaceHistoryPath -Name 'InterfaceSync'

function Add-MarkdownTable {
    param(
        [System.Collections.Generic.List[string]]$Builder,
        [string]$Title,
        [object[]]$Rows,
        [string[]]$Headers,
        [scriptblock]$RowFormatter
    )

    $Builder.Add("### $Title")
    $Builder.Add('')
    $Builder.Add('|' + ($Headers -join '|') + '|')
    $Builder.Add('|' + (($Headers | ForEach-Object { '---' }) -join '|') + '|')
    foreach ($row in $Rows) {
        $Builder.Add((& $RowFormatter $row))
    }
    $Builder.Add('')
}

$builder = New-Object System.Collections.Generic.List[string]
$builder.Add('# Incremental Loading Performance History')
$builder.Add('')
$builder.Add("> Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')")
$builder.Add('')

$recentPorts = ($portHistory | Select-Object -Last $Recent | Sort-Object GeneratedAtUtc -Descending)
Add-MarkdownTable -Builder $builder `
    -Title 'PortBatchReady Summary' `
    -Rows $recentPorts `
    -Headers @('Generated (UTC)','Ports/min','Total Ports','Events','Hosts','Batch p95 (ms)','UiClone p95 (ms)','Report') `
    -RowFormatter {
        param($row)
        $generated = [DateTime]::Parse($row.GeneratedAtUtc).ToString('yyyy-MM-dd HH:mm:ss')
        return "| $generated | {0:N2} | {1} | {2} | {3} | {4} | {5} | `{6}` |" -f `
            [double]$row.PortsPerMinute,
            $row.TotalPorts,
            $row.EventCount,
            $row.UniqueHosts,
            $row.BatchIntervalP95,
            $row.UiCloneP95,
            (Split-Path -Path $row.ReportPath -Leaf)
    }

$recentInterface = ($interfaceHistory | Select-Object -Last $Recent | Sort-Object GeneratedAtUtc -Descending)
Add-MarkdownTable -Builder $builder `
    -Title 'InterfaceSyncTiming Summary' `
    -Rows $recentInterface `
    -Headers @('Generated (UTC)','UiClone p95 (ms)','Stream p95 (ms)','Diff p95 (ms)','Hot Site','Hot Host','Report') `
    -RowFormatter {
        param($row)
        $generated = [DateTime]::Parse($row.GeneratedAtUtc).ToString('yyyy-MM-dd HH:mm:ss')
        return "| $generated | {0} | {1} | {2} | {3} ({4}) | {5} ({6}) | `{7}` |" -f `
            $row.UiCloneP95,
            $row.StreamDispatchP95,
            $row.DiffDurationP95,
            $row.HottestSite,
            $row.HottestSiteUiClone,
            $row.HottestHost,
            $row.HottestHostUiClone,
            (Split-Path -Path $row.ReportPath -Leaf)
    }

$queueHistory = @()
if (Test-Path -LiteralPath $QueueDelayHistoryPath) {
    try {
        $queueHistory = Import-Csv -LiteralPath $QueueDelayHistoryPath | Sort-Object GeneratedAtUtc
    } catch {
        Write-Warning ("Failed to parse queue delay history '{0}': {1}" -f $QueueDelayHistoryPath, $_.Exception.Message)
        $queueHistory = @()
    }
}

if ($queueHistory.Count -gt 0) {
    $recentQueue = $queueHistory | Select-Object -Last $Recent | Sort-Object GeneratedAtUtc -Descending
    Add-MarkdownTable -Builder $builder `
        -Title 'QueueDelaySummary History' `
        -Rows $recentQueue `
        -Headers @('Generated (UTC)','Samples','Avg Delay (ms)','p95 (ms)','p99 (ms)','Result','Summary','Telemetry') `
        -RowFormatter {
            param($row)
            $generated = ''
            if ($row.GeneratedAtUtc) {
                try { $generated = [DateTime]::Parse($row.GeneratedAtUtc).ToString('yyyy-MM-dd HH:mm:ss') } catch { $generated = '' + $row.GeneratedAtUtc }
            }
            $result = if ([System.Convert]::ToBoolean($row.Pass)) { 'Pass' } else { 'Fail' }
            $summaryName = if ($row.SummaryPath) { (Split-Path -Path $row.SummaryPath -Leaf) } else { '' }
            $metricsName = if ($row.SourceTelemetryPath) { (Split-Path -Path $row.SourceTelemetryPath -Leaf) } else { '' }
            return "| $generated | {0} | {1:N2} | {2:N2} | {3:N2} | {4} | `{5}` | `{6}` |" -f `
                $row.SampleCount,
                [double]$row.AverageQueueDelayMs,
                [double]$row.QueueDelayP95Ms,
                [double]$row.QueueDelayP99Ms,
                $result,
                $summaryName,
                $metricsName
        }
} else {
    $builder.Add('> Queue delay history is unavailable. Run `Tools\Update-QueueDelayHistory.ps1` after generating queue summaries to populate this table.')
    $builder.Add('')
}

$schedulerHistory = @()
if (Test-Path -LiteralPath $SchedulerHistoryPath) {
    try {
        $schedulerHistory = Import-Csv -LiteralPath $SchedulerHistoryPath | Sort-Object GeneratedAtUtc
    } catch {
        Write-Warning ("Failed to parse parser scheduler history '{0}': {1}" -f $SchedulerHistoryPath, $_.Exception.Message)
        $schedulerHistory = @()
    }
}

if ($schedulerHistory.Count -gt 0) {
    $recentScheduler = $schedulerHistory | Select-Object -Last $Recent | Sort-Object GeneratedAtUtc -Descending
    Add-MarkdownTable -Builder $builder `
        -Title 'ParserSchedulerLaunch History' `
        -Rows $recentScheduler `
        -Headers @('Generated (UTC)','Total Launches','Unique Sites','Max Streak','Violations','Result','Report','Telemetry') `
        -RowFormatter {
            param($row)
            $generated = ''
            if ($row.GeneratedAtUtc) {
                try { $generated = [DateTime]::Parse($row.GeneratedAtUtc).ToString('yyyy-MM-dd HH:mm:ss') } catch { $generated = '' + $row.GeneratedAtUtc }
            }
            $result = if ([System.Convert]::ToBoolean($row.Pass)) { 'Pass' } else { 'Fail' }
            $reportName = if ($row.ReportPath) { (Split-Path -Path $row.ReportPath -Leaf) } else { '' }
            $telemetryName = if ($row.FilesAnalyzed) { (Split-Path -Path $row.FilesAnalyzed -Leaf) } else { '' }
            return "| $generated | {0} | {1} | {2} | {3} | {4} | `{5}` | `{6}` |" -f `
                $row.TotalLaunchEvents,
                $row.UniqueSites,
                $row.MaxObservedStreak,
                $row.ViolationCount,
                $result,
                $reportName,
                $telemetryName
        }
} else {
    $builder.Add('> Parser scheduler history is unavailable. Run `Tools\Update-ParserSchedulerHistory.ps1` (or rerun the pipeline) after generating rotation reports to populate this table.')
    $builder.Add('')
}

$outputDir = Split-Path -Path $OutputPath -Parent
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

Set-Content -LiteralPath $OutputPath -Value ($builder -join [Environment]::NewLine) -Encoding utf8
Write-Host ("Performance report written to {0}" -f (Resolve-Path -LiteralPath $OutputPath)) -ForegroundColor DarkCyan
