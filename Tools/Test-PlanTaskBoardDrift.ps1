[CmdletBinding()]
param(
    [string]$PlansDirectory = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'docs\plans'),

    [string]$TaskBoardCsvPath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'docs\taskboard\TaskBoard.csv'),

    [string]$OutputPath,

    [switch]$FailOnDrift,

    [switch]$PassThru
)

<#
.SYNOPSIS
Detects drift between plan files and TaskBoard.csv entries (ST-N-004).

.DESCRIPTION
Compares task IDs and statuses between plan markdown files and the TaskBoard.csv
to identify inconsistencies:
- Task IDs in plans but missing from TaskBoard
- Task IDs in TaskBoard but missing from plans
- Status mismatches between plan and TaskBoard

.PARAMETER PlansDirectory
Directory containing plan markdown files. Defaults to docs/plans.

.PARAMETER TaskBoardCsvPath
Path to TaskBoard.csv. Defaults to docs/taskboard/TaskBoard.csv.

.PARAMETER OutputPath
If specified, writes the drift report to a JSON file.

.PARAMETER FailOnDrift
If set, exits with code 1 when drift is detected.

.PARAMETER PassThru
Returns the drift report as an object.

.EXAMPLE
pwsh Tools\Test-PlanTaskBoardDrift.ps1 -FailOnDrift

.EXAMPLE
pwsh Tools\Test-PlanTaskBoardDrift.ps1 -OutputPath Logs\Reports\PlanDrift.json -PassThru
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Initialize result
$result = [pscustomobject]@{
    GeneratedAtUtc       = (Get-Date).ToUniversalTime().ToString('o')
    PlansDirectory       = $PlansDirectory
    TaskBoardCsvPath     = $TaskBoardCsvPath
    PlansScanned         = 0
    TasksInPlans         = 0
    TasksInTaskBoard     = 0
    Status               = 'Unknown'
    Discrepancies        = @()
    MissingFromTaskBoard = @()
    MissingFromPlans     = @()
    StatusMismatches     = @()
    Message              = ''
}

Write-Host "`n=== Plan/TaskBoard Drift Detector (ST-N-004) ===" -ForegroundColor Cyan
Write-Host ("Timestamp: {0}" -f $result.GeneratedAtUtc) -ForegroundColor DarkGray
Write-Host ""

# Validate paths
if (-not (Test-Path -LiteralPath $PlansDirectory)) {
    throw "Plans directory not found: $PlansDirectory"
}

if (-not (Test-Path -LiteralPath $TaskBoardCsvPath)) {
    throw "TaskBoard.csv not found: $TaskBoardCsvPath"
}

# Parse plan files for task entries
Write-Host "--- Scanning Plan Files ---" -ForegroundColor Yellow
$planTasks = @{}

$planFiles = Get-ChildItem -LiteralPath $PlansDirectory -Filter 'Plan*.md' -File
$result.PlansScanned = $planFiles.Count

foreach ($planFile in $planFiles) {
    $content = Get-Content -LiteralPath $planFile.FullName -Raw

    # Match table rows with task IDs like ST-X-NNN
    # Pattern: | ST-X-NNN | Title | Status | ...
    $matches = [regex]::Matches($content, '\|\s*(ST-[A-Z]+-\d+)\s*\|([^|]+)\|([^|]+)\|')

    foreach ($match in $matches) {
        $taskId = $match.Groups[1].Value.Trim()
        $title = $match.Groups[2].Value.Trim()
        $status = $match.Groups[3].Value.Trim()

        if (-not $planTasks.ContainsKey($taskId)) {
            $planTasks[$taskId] = [pscustomobject]@{
                TaskId     = $taskId
                Title      = $title
                Status     = $status
                PlanFile   = $planFile.Name
            }
        }
    }
}

$result.TasksInPlans = $planTasks.Count
Write-Host ("  Plans scanned: {0}" -f $result.PlansScanned) -ForegroundColor DarkGray
Write-Host ("  Tasks found: {0}" -f $result.TasksInPlans) -ForegroundColor DarkGray
Write-Host ""

# Parse TaskBoard.csv
Write-Host "--- Scanning TaskBoard.csv ---" -ForegroundColor Yellow
$taskBoardTasks = @{}

$csvContent = Import-Csv -LiteralPath $TaskBoardCsvPath
foreach ($row in $csvContent) {
    $taskId = $row.Id
    if ([string]::IsNullOrWhiteSpace($taskId)) { continue }
    if ($taskId -notmatch '^ST-[A-Z]+-\d+$') { continue }

    $taskBoardTasks[$taskId] = [pscustomobject]@{
        TaskId  = $taskId
        Title   = $row.Title
        Status  = $row.Status
    }
}

$result.TasksInTaskBoard = $taskBoardTasks.Count
Write-Host ("  Tasks found: {0}" -f $result.TasksInTaskBoard) -ForegroundColor DarkGray
Write-Host ""

# Compare: Tasks in plans but not in TaskBoard
Write-Host "--- Checking for Drift ---" -ForegroundColor Yellow
foreach ($taskId in $planTasks.Keys) {
    if (-not $taskBoardTasks.ContainsKey($taskId)) {
        $planTask = $planTasks[$taskId]
        $result.MissingFromTaskBoard += [pscustomobject]@{
            TaskId   = $taskId
            Title    = $planTask.Title
            Status   = $planTask.Status
            PlanFile = $planTask.PlanFile
            Issue    = 'Task in plan but missing from TaskBoard.csv'
        }
    }
}

# Compare: Tasks in TaskBoard but not in plans
foreach ($taskId in $taskBoardTasks.Keys) {
    if (-not $planTasks.ContainsKey($taskId)) {
        $tbTask = $taskBoardTasks[$taskId]
        $result.MissingFromPlans += [pscustomobject]@{
            TaskId = $taskId
            Title  = $tbTask.Title
            Status = $tbTask.Status
            Issue  = 'Task in TaskBoard.csv but missing from plans'
        }
    }
}

# Compare: Status mismatches
foreach ($taskId in $planTasks.Keys) {
    if ($taskBoardTasks.ContainsKey($taskId)) {
        $planStatus = $planTasks[$taskId].Status
        $tbStatus = $taskBoardTasks[$taskId].Status

        # Normalize statuses for comparison (ignore date suffixes)
        $planStatusNorm = $planStatus -replace '\s*-\s*\d{4}-\d{2}-\d{2}.*$', ''
        $tbStatusNorm = $tbStatus -replace '\s*-\s*\d{4}-\d{2}-\d{2}.*$', ''

        if ($planStatusNorm -ne $tbStatusNorm) {
            $result.StatusMismatches += [pscustomobject]@{
                TaskId       = $taskId
                PlanStatus   = $planStatus
                BoardStatus  = $tbStatus
                PlanFile     = $planTasks[$taskId].PlanFile
                Issue        = 'Status mismatch between plan and TaskBoard'
            }
        }
    }
}

# Aggregate discrepancies
$result.Discrepancies = @()
$result.Discrepancies += $result.MissingFromTaskBoard
$result.Discrepancies += $result.MissingFromPlans
$result.Discrepancies += $result.StatusMismatches

# Determine status
$totalIssues = $result.Discrepancies.Count

if ($totalIssues -eq 0) {
    $result.Status = 'Pass'
    $result.Message = "No drift detected. Plans and TaskBoard are synchronized ($($result.TasksInPlans) tasks)."
    Write-Host ("PASS: {0}" -f $result.Message) -ForegroundColor Green
} else {
    $result.Status = 'Fail'
    $result.Message = "Drift detected: $totalIssues issue(s) found."
    Write-Host ("FAIL: {0}" -f $result.Message) -ForegroundColor Red

    if ($result.MissingFromTaskBoard.Count -gt 0) {
        Write-Host ("`n  Missing from TaskBoard.csv ({0}):" -f $result.MissingFromTaskBoard.Count) -ForegroundColor Yellow
        foreach ($item in $result.MissingFromTaskBoard) {
            Write-Host ("    - {0}: {1} [{2}] (from {3})" -f $item.TaskId, $item.Title, $item.Status, $item.PlanFile) -ForegroundColor DarkYellow
        }
    }

    if ($result.MissingFromPlans.Count -gt 0) {
        Write-Host ("`n  Missing from Plans ({0}):" -f $result.MissingFromPlans.Count) -ForegroundColor Yellow
        foreach ($item in $result.MissingFromPlans) {
            Write-Host ("    - {0}: {1} [{2}]" -f $item.TaskId, $item.Title, $item.Status) -ForegroundColor DarkYellow
        }
    }

    if ($result.StatusMismatches.Count -gt 0) {
        Write-Host ("`n  Status Mismatches ({0}):" -f $result.StatusMismatches.Count) -ForegroundColor Yellow
        foreach ($item in $result.StatusMismatches) {
            Write-Host ("    - {0}: Plan='{1}' vs Board='{2}'" -f $item.TaskId, $item.PlanStatus, $item.BoardStatus) -ForegroundColor DarkYellow
        }
    }
}

Write-Host ""

# Write output
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    try {
        $outputDir = Split-Path -Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8
        Write-Host "Report saved to: $OutputPath" -ForegroundColor DarkCyan
    } catch {
        Write-Warning "Failed to save report: $($_.Exception.Message)"
    }
}

if ($PassThru.IsPresent) {
    return $result
}

if ($FailOnDrift.IsPresent -and $result.Status -eq 'Fail') {
    exit 1
}
