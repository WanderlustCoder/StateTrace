[CmdletBinding()]
param(
    [Parameter(Mandatory, ParameterSetName = 'InputFile')]
    [string]$InputPath,

    [Parameter(Mandatory, ParameterSetName = 'Inline')]
    [string]$TaskId,

    [Parameter(ParameterSetName = 'Inline')]
    [string]$Title,

    [Parameter(ParameterSetName = 'Inline')]
    [string]$Status,

    [Parameter(ParameterSetName = 'Inline')]
    [string]$Owner,

    [Parameter(ParameterSetName = 'Inline')]
    [string]$Notes,

    [Parameter(ParameterSetName = 'Inline')]
    [string[]]$Artifacts,

    [string]$PlansDirectory,

    [string]$TaskBoardCsvPath,

    [switch]$WhatIf,

    [switch]$PassThru
)

<#
.SYNOPSIS
Syncs task updates to plan files and TaskBoard.csv (ST-N-001).

.DESCRIPTION
Updates plan markdown tables and TaskBoard.csv from structured input.
Emits a diff preview before writing. Use -WhatIf to preview only.

.PARAMETER InputPath
Path to JSON file with task updates. Expected format:
[
  {
    "TaskId": "ST-X-001",
    "Title": "Task title",
    "Status": "Done - 2026-01-04",
    "Owner": "PMO",
    "Notes": "Completion notes...",
    "Artifacts": ["path/to/file1", "path/to/file2"]
  }
]

.PARAMETER TaskId
Task ID for inline update (e.g., ST-B-001).

.PARAMETER Title
Task title (optional for inline update).

.PARAMETER Status
New status (e.g., "Done - 2026-01-04", "In Progress", "Backlog").

.PARAMETER Owner
Owner role (e.g., "PMO", "QA", "Automation").

.PARAMETER Notes
Completion or status notes.

.PARAMETER Artifacts
List of artifact paths to include in notes.

.PARAMETER PlansDirectory
Directory containing plan markdown files. Defaults to docs/plans.

.PARAMETER TaskBoardCsvPath
Path to TaskBoard.csv. Defaults to docs/taskboard/TaskBoard.csv.

.PARAMETER WhatIf
Preview changes without writing.

.PARAMETER PassThru
Return the sync result as an object.

.EXAMPLE
pwsh Tools\Sync-TaskBoard.ps1 -TaskId ST-B-001 -Status "Done - 2026-01-04" -Notes "Completed with tests" -WhatIf

.EXAMPLE
pwsh Tools\Sync-TaskBoard.ps1 -InputPath tasks-update.json
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent

if ([string]::IsNullOrWhiteSpace($PlansDirectory)) {
    $PlansDirectory = Join-Path -Path $repositoryRoot -ChildPath 'docs\plans'
}

if ([string]::IsNullOrWhiteSpace($TaskBoardCsvPath)) {
    $TaskBoardCsvPath = Join-Path -Path $repositoryRoot -ChildPath 'docs\taskboard\TaskBoard.csv'
}

# Initialize result
$result = [pscustomobject]@{
    GeneratedAtUtc    = (Get-Date).ToUniversalTime().ToString('o')
    TasksProcessed    = 0
    PlansUpdated      = @()
    TaskBoardUpdated  = $false
    Changes           = @()
    Status            = 'Unknown'
    Message           = ''
}

# Parse input
$tasks = @()
if ($PSCmdlet.ParameterSetName -eq 'InputFile') {
    if (-not (Test-Path -LiteralPath $InputPath)) {
        throw "Input file not found: $InputPath"
    }
    $tasks = Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json
    if ($tasks -isnot [System.Array]) {
        $tasks = @($tasks)
    }
} else {
    # Inline mode
    $task = [pscustomobject]@{
        TaskId    = $TaskId
        Title     = $Title
        Status    = $Status
        Owner     = $Owner
        Notes     = $Notes
        Artifacts = if ($Artifacts) { $Artifacts } else { @() }
    }
    $tasks = @($task)
}

Write-Host "`n=== Task Board Sync (ST-N-001) ===" -ForegroundColor Cyan
Write-Host ("Tasks to process: {0}" -f $tasks.Count) -ForegroundColor DarkGray
if ($WhatIf.IsPresent) {
    Write-Host "[WhatIf mode - no changes will be written]" -ForegroundColor Yellow
}
Write-Host ""

# Helper to extract plan letter from task ID
function Get-PlanFromTaskId {
    param([string]$TaskId)
    if ($TaskId -match '^ST-([A-Z])-\d+$') {
        return $Matches[1]
    }
    return $null
}

# Helper to find and update plan file
function Update-PlanFile {
    param(
        [string]$PlanLetter,
        [pscustomobject]$Task,
        [switch]$WhatIf
    )

    $planFiles = Get-ChildItem -Path $PlansDirectory -Filter "Plan${PlanLetter}_*.md" -File
    if ($planFiles.Count -eq 0) {
        Write-Warning "No plan file found for letter: $PlanLetter"
        return $null
    }

    $planFile = $planFiles[0]
    $content = Get-Content -LiteralPath $planFile.FullName -Raw
    $originalContent = $content

    # Find the task row in the plan table
    $taskId = $Task.TaskId
    $pattern = "(\| $taskId \|[^\|]+\|[^\|]+\|)([^\|]+)(\|[^\n]+)"

    if ($content -match $pattern) {
        $oldStatus = $Matches[2].Trim()
        $newStatus = $Task.Status

        if ($oldStatus -ne $newStatus) {
            # Build new row content
            $newNotes = if ($Task.Notes) { " $($Task.Notes) |" } else { $Matches[3] }
            $replacement = "$($Matches[1]) $newStatus |$newNotes"

            $content = $content -replace [regex]::Escape($Matches[0]), $replacement

            $change = [pscustomobject]@{
                Type     = 'PlanUpdate'
                File     = $planFile.Name
                TaskId   = $taskId
                OldValue = $oldStatus
                NewValue = $newStatus
            }

            if (-not $WhatIf.IsPresent) {
                Set-Content -LiteralPath $planFile.FullName -Value $content -Encoding utf8 -NoNewline
            }

            return $change
        }
    } else {
        Write-Warning "Task $taskId not found in $($planFile.Name)"
    }

    return $null
}

# Process each task
Write-Host "--- Processing Tasks ---" -ForegroundColor Yellow

foreach ($task in $tasks) {
    $taskId = $task.TaskId
    Write-Host ("  Processing: {0}" -f $taskId) -ForegroundColor DarkCyan

    # Extract plan letter
    $planLetter = Get-PlanFromTaskId -TaskId $taskId
    if (-not $planLetter) {
        Write-Warning "  Cannot extract plan letter from task ID: $taskId"
        continue
    }

    # Update plan file
    $planChange = Update-PlanFile -PlanLetter $planLetter -Task $task -WhatIf:$WhatIf.IsPresent
    if ($planChange) {
        $result.Changes += $planChange
        if ($planChange.File -notin $result.PlansUpdated) {
            $result.PlansUpdated += $planChange.File
        }
        Write-Host ("    Plan: {0} -> {1}" -f $planChange.OldValue, $planChange.NewValue) -ForegroundColor Green
    }

    $result.TasksProcessed++
}

# Update TaskBoard.csv
Write-Host ""
Write-Host "--- Updating TaskBoard.csv ---" -ForegroundColor Yellow

if (Test-Path -LiteralPath $TaskBoardCsvPath) {
    $csvContent = Get-Content -LiteralPath $TaskBoardCsvPath
    $newCsvContent = @()
    $csvUpdated = $false

    foreach ($line in $csvContent) {
        $updatedLine = $line
        foreach ($task in $tasks) {
            if ($line -match "^`"$($task.TaskId)`"") {
                # Parse existing CSV line
                $fields = $line -split '","'
                if ($fields.Count -ge 3 -and $task.Status) {
                    $oldStatus = $fields[2] -replace '^"|"$', ''
                    if ($oldStatus -ne $task.Status) {
                        $fields[2] = $task.Status
                        $updatedLine = $fields -join '","'

                        $result.Changes += [pscustomobject]@{
                            Type     = 'TaskBoardUpdate'
                            File     = 'TaskBoard.csv'
                            TaskId   = $task.TaskId
                            OldValue = $oldStatus
                            NewValue = $task.Status
                        }
                        $csvUpdated = $true
                        Write-Host ("  {0}: {1} -> {2}" -f $task.TaskId, $oldStatus, $task.Status) -ForegroundColor Green
                    }
                }
                break
            }
        }
        $newCsvContent += $updatedLine
    }

    if ($csvUpdated -and -not $WhatIf.IsPresent) {
        Set-Content -LiteralPath $TaskBoardCsvPath -Value $newCsvContent -Encoding utf8
        $result.TaskBoardUpdated = $true
    } elseif ($csvUpdated) {
        $result.TaskBoardUpdated = $true
    }
}

Write-Host ""

# Summary
$result.Status = if ($result.Changes.Count -gt 0) { 'Changed' } else { 'NoChanges' }
$result.Message = "{0} task(s) processed, {1} change(s) detected, {2} plan(s) updated." -f $result.TasksProcessed, $result.Changes.Count, $result.PlansUpdated.Count

Write-Host "--- Summary ---" -ForegroundColor Yellow
Write-Host ("  Tasks processed: {0}" -f $result.TasksProcessed)
Write-Host ("  Changes detected: {0}" -f $result.Changes.Count)
Write-Host ("  Plans updated: {0}" -f ($result.PlansUpdated -join ', '))
Write-Host ("  TaskBoard updated: {0}" -f $result.TaskBoardUpdated)

if ($WhatIf.IsPresent -and $result.Changes.Count -gt 0) {
    Write-Host ""
    Write-Host "[WhatIf] No changes were written. Run without -WhatIf to apply." -ForegroundColor Yellow
}

Write-Host ""

if ($PassThru.IsPresent) {
    return $result
}
