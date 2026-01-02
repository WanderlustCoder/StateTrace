[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')),
    [string]$TaskBoardCsvPath,
    [int]$MaxDeletedRows = 20,
    [int]$MinimumRowCount = 10,
    [switch]$AllowLargeTaskBoardEdits,
    [switch]$SkipGitDiff,
    [hashtable]$GitDiffOverride,
    [string]$OutputPath,
    [switch]$PassThru,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DefaultOutputPath {
    param([string]$RootPath)
    $reportDir = Join-Path -Path $RootPath -ChildPath 'Logs\Reports'
    if (-not (Test-Path -LiteralPath $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }
    return (Join-Path -Path $reportDir -ChildPath ("TaskBoardIntegrity-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss')))
}

function Get-CsvHeader {
    param([string]$HeaderLine)
    $reader = New-Object System.IO.StringReader($HeaderLine)
    $parser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($reader)
    $parser.TextFieldType = 'Delimited'
    $parser.SetDelimiters(',')
    $parser.HasFieldsEnclosedInQuotes = $true
    $fields = $parser.ReadFields()
    $parser.Close()
    $reader.Close()
    return $fields
}

function Get-RelativePath {
    param([string]$BasePath, [string]$FullPath)
    try {
        return [System.IO.Path]::GetRelativePath($BasePath, $FullPath)
    } catch {
        return $FullPath
    }
}

function Get-GitDiffStats {
    param(
        [string]$RepoRoot,
        [string]$RelativePath,
        [switch]$SkipGitDiff,
        [hashtable]$GitDiffOverride
    )
    $stats = [ordered]@{
        Available    = $false
        Used         = $false
        HasDiff      = $false
        Added        = 0
        Deleted      = 0
        HeadRowCount = $null
        Error        = $null
    }

    if ($GitDiffOverride) {
        $stats.Available = $true
        $stats.Used = $true
        $stats.HasDiff = [bool]$GitDiffOverride.HasDiff
        $stats.Added = [int]$GitDiffOverride.Added
        $stats.Deleted = [int]$GitDiffOverride.Deleted
        if ($GitDiffOverride.ContainsKey('HeadRowCount')) {
            $stats.HeadRowCount = $GitDiffOverride.HeadRowCount
        }
        return $stats
    }

    if ($SkipGitDiff) {
        return $stats
    }

    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        return $stats
    }
    $stats.Available = $true

    $inside = & git -C $RepoRoot rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or $inside -notmatch 'true') {
        return $stats
    }

    $gitPath = $RelativePath -replace '\\', '/'
    $status = & git -C $RepoRoot status --porcelain -- $gitPath 2>$null
    if ($status) {
        $numstat = & git -C $RepoRoot diff --numstat -- $gitPath 2>$null
        if ($numstat) {
            $parts = ($numstat -split '\s+')
            if ($parts.Count -ge 2) {
                $stats.Added = [int]($parts[0] -replace '[^\d]', '0')
                $stats.Deleted = [int]($parts[1] -replace '[^\d]', '0')
                $stats.HasDiff = $true
                $stats.Used = $true
            }
        }
    }

    $headContent = & git -C $RepoRoot show ("HEAD:{0}" -f $gitPath) 2>$null
    if ($LASTEXITCODE -eq 0 -and $headContent) {
        $headLines = @($headContent)
        if ($headLines.Count -gt 1) {
            $stats.HeadRowCount = ($headLines | Select-Object -Skip 1 | Measure-Object).Count
        }
        else {
            $stats.HeadRowCount = 0
        }
    }
    return $stats
}

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($TaskBoardCsvPath)) {
    $TaskBoardCsvPath = Join-Path -Path $repoRoot -ChildPath 'docs\taskboard\TaskBoard.csv'
}
$resolvedTaskBoardCsv = (Resolve-Path -LiteralPath $TaskBoardCsvPath -ErrorAction Stop).Path

$expectedColumns = @('ID','Title','Column','OwnerRole','Deliverable','PlanLink','Notes')
$failureReasons = @()
$missingColumns = @()
$duplicateIds = @()
$emptyIdCount = 0

$rawLines = Get-Content -LiteralPath $resolvedTaskBoardCsv -ErrorAction Stop
if (-not $rawLines -or $rawLines.Count -eq 0) {
    $failureReasons += 'TaskBoardCsvEmpty'
    $headerColumns = @()
    $rowCount = 0
    $rows = @()
}
else {
    $headerColumns = Get-CsvHeader -HeaderLine $rawLines[0]
    $rows = @(Import-Csv -LiteralPath $resolvedTaskBoardCsv)
    $rowCount = $rows.Count
}

# LANDMARK: TaskBoard integrity - structural validation and unique TaskId enforcement
foreach ($required in $expectedColumns) {
    if (-not ($headerColumns -contains $required)) {
        $missingColumns += $required
    }
}
if ($missingColumns.Count -gt 0) {
    $failureReasons += 'MissingColumns'
}

if ($headerColumns -notcontains 'ID') {
    $failureReasons += 'MissingIdColumn'
}
else {
    $idValues = @()
    foreach ($row in $rows) {
        $value = if ($null -ne $row.ID) { [string]$row.ID } else { '' }
        if ([string]::IsNullOrWhiteSpace($value)) {
            $emptyIdCount++
            continue
        }
        $idValues += $value.Trim()
    }

    if ($emptyIdCount -gt 0) {
        $failureReasons += 'EmptyTaskId'
    }

    $groups = $idValues | Group-Object { $_.ToUpperInvariant() } | Where-Object { $_.Count -gt 1 }
    if ($groups) {
        $duplicateIds = $groups | ForEach-Object { $_.Name }
        $failureReasons += 'DuplicateTaskId'
    }
}

if ($rowCount -lt $MinimumRowCount) {
    $failureReasons += 'RowCountBelowMinimum'
}

$relativePath = Get-RelativePath -BasePath $repoRoot -FullPath $resolvedTaskBoardCsv
$gitStats = Get-GitDiffStats -RepoRoot $repoRoot -RelativePath $relativePath -SkipGitDiff:$SkipGitDiff -GitDiffOverride $GitDiffOverride
$deletedRowsFromHead = $null
if ($gitStats.HeadRowCount -ne $null -and $rowCount -ge 0) {
    $deletedRowsFromHead = [math]::Max(0, ($gitStats.HeadRowCount - $rowCount))
}

# LANDMARK: TaskBoard integrity - block large unintended deletions unless explicitly allowed
if (-not $AllowLargeTaskBoardEdits) {
    if ($deletedRowsFromHead -ne $null) {
        if ($deletedRowsFromHead -gt $MaxDeletedRows) {
            $failureReasons += 'LargeDeletionDetected'
        }
    }
    elseif ($gitStats.Used -and $gitStats.HasDiff -and $gitStats.Deleted -gt $MaxDeletedRows) {
        $failureReasons += 'LargeDeletionDetected'
    }
}

$result = [ordered]@{
    TaskBoardCsvPath   = $resolvedTaskBoardCsv
    Passed             = ($failureReasons.Count -eq 0)
    RowCount           = $rowCount
    MinimumRowCount    = $MinimumRowCount
    RequiredColumns    = $expectedColumns
    MissingColumns     = $missingColumns
    EmptyIdCount       = $emptyIdCount
    DuplicateIds       = $duplicateIds
    FailureReasons     = $failureReasons
    Git               = [ordered]@{
        Available        = $gitStats.Available
        Used             = $gitStats.Used
        HasDiff          = $gitStats.HasDiff
        Added            = $gitStats.Added
        Deleted          = $gitStats.Deleted
        HeadRowCount     = $gitStats.HeadRowCount
        DeletedFromHead  = $deletedRowsFromHead
        MaxDeletedRows   = $MaxDeletedRows
        AllowLargeEdits  = $AllowLargeTaskBoardEdits.IsPresent
        RelativePath     = $relativePath
    }
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Get-DefaultOutputPath -RootPath $repoRoot
}
else {
    $outputDir = Split-Path -Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8

if (-not $Quiet) {
    Write-Host ("TaskBoard integrity report written to {0}" -f (Resolve-Path -LiteralPath $OutputPath)) -ForegroundColor DarkCyan
}

if (-not $result.Passed) {
    $deletionText = if ($gitStats.Used) {
        "Added=$($gitStats.Added), Deleted=$($gitStats.Deleted)"
    } elseif ($deletedRowsFromHead -ne $null) {
        "DeletedFromHead=$deletedRowsFromHead"
    } else {
        "Deleted=Unknown"
    }
    $message = "TaskBoard integrity check failed: {0}. RowCount={1}. {2}. Recover with `git checkout -- docs/taskboard/TaskBoard.csv` or `git restore docs/taskboard/TaskBoard.csv`." -f ($failureReasons -join ', '), $rowCount, $deletionText
    throw $message
}

if ($PassThru) {
    return [pscustomobject]$result
}
