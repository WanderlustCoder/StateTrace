[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$SchedulerReportPaths,

    [string]$HistoryPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Logs\Reports\ParserSchedulerHistory.csv'),

    [int]$MaxAllowedStreak = 8,

    [switch]$Force
)

<#
.SYNOPSIS
Adds parser scheduler rotation summaries to the historical CSV.

.DESCRIPTION
Reads one or more `ParserSchedulerLaunch-*.json` reports (produced by
`Tools\Analyze-ParserSchedulerLaunch.ps1`) and appends their key values
to `Logs\Reports\ParserSchedulerHistory.csv`. Duplicate entries (matching
`FilesAnalyzed`) are skipped unless `-Force` is provided.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $SchedulerReportPaths -or $SchedulerReportPaths.Count -eq 0) {
    throw 'Specify at least one scheduler report path.'
}

$resolvedHistoryPath = [System.IO.Path]::GetFullPath($HistoryPath)
$historyDirectory = Split-Path -Parent $resolvedHistoryPath
if (-not (Test-Path -LiteralPath $historyDirectory)) {
    New-Item -Path $historyDirectory -ItemType Directory -Force | Out-Null
}

$existingSources = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
if (Test-Path -LiteralPath $resolvedHistoryPath) {
    try {
        foreach ($row in (Import-Csv -LiteralPath $resolvedHistoryPath)) {
            if ($row.FilesAnalyzed) {
                [void]$existingSources.Add($row.FilesAnalyzed)
            }
        }
    } catch {
        Write-Warning ("Failed to load existing scheduler history '{0}': {1}" -f $resolvedHistoryPath, $_.Exception.Message)
    }
}

$records = New-Object System.Collections.Generic.List[psobject]

foreach ($reportPath in $SchedulerReportPaths) {
    if ([string]::IsNullOrWhiteSpace($reportPath)) { continue }
    if (-not (Test-Path -LiteralPath $reportPath)) {
        Write-Warning ("Scheduler report '{0}' not found; skipping." -f $reportPath)
        continue
    }

    $summary = $null
    try {
        $summary = (Get-Content -LiteralPath $reportPath -Raw) | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Warning ("Failed to parse scheduler report '{0}': {1}" -f $reportPath, $_.Exception.Message)
        continue
    }

    $filesAnalyzed = '' + $summary.FilesAnalyzed
    if (-not $Force -and -not [string]::IsNullOrWhiteSpace($filesAnalyzed) -and $existingSources.Contains($filesAnalyzed)) {
        Write-Verbose ("Scheduler report '{0}' already recorded (source '{1}'); skipping." -f $reportPath, $filesAnalyzed)
        continue
    }

    $violationCount = 0
    if ($summary.Violations) {
        $violationCount = ($summary.Violations | Measure-Object).Count
    }

    $pass = ($summary.MaxObservedStreak -le $MaxAllowedStreak) -and ($violationCount -eq 0)

    $record = [pscustomobject]@{
        GeneratedAtUtc    = '' + $summary.GeneratedAtUtc
        FilesAnalyzed     = $filesAnalyzed
        ReportPath        = (Resolve-Path -LiteralPath $reportPath).Path
        TotalLaunchEvents = [int]$summary.TotalLaunchEvents
        UniqueSites       = [int]$summary.UniqueSites
        MaxObservedStreak = [int]$summary.MaxObservedStreak
        ViolationCount    = [int]$violationCount
        Pass              = [bool]$pass
    }

    $records.Add($record) | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($filesAnalyzed)) {
        [void]$existingSources.Add($filesAnalyzed)
    }
}

if ($records.Count -eq 0) {
    Write-Verbose 'No scheduler history entries were appended.'
    return
}

$exportParams = @{
    LiteralPath      = $resolvedHistoryPath
    NoTypeInformation = $true
}
if (Test-Path -LiteralPath $resolvedHistoryPath) {
    $exportParams['Append'] = $true
}

$records | Export-Csv @exportParams
Write-Host ("Appended {0} scheduler entr{1} to {2}" -f $records.Count, $(if ($records.Count -eq 1) { 'y' } else { 'ies' }), $resolvedHistoryPath) -ForegroundColor Green

if ($PSCmdlet.ParameterSetName -eq '' -and $records.Count -gt 0) {
    return $records
}
