[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TaskId,
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')),
    [string]$TaskBoardPath,
    [string]$TaskBoardCsvPath,
    [int]$TaskBoardMinimumRowCount = 10,
    [int]$TaskBoardMaxDeletedRows = 20,
    [string]$TaskBoardIntegrityOutputPath,
    [string]$BacklogPath,
    [string]$PlanPath,
    [string]$SessionLogPath,
    [switch]$RequireBacklogEntry,
    [switch]$RequireSessionLog,
    [switch]$AllowLargeTaskBoardEdits,
    [string]$OutputPath,
    [switch]$PassThru,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoPath {
    param([string]$PathValue, [string]$RepositoryRoot)
    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $null
    }
    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }
    return (Join-Path -Path $RepositoryRoot -ChildPath $PathValue)
}

function Test-TaskIdInFile {
    param([string]$PathValue, [string]$TaskId)
    if (-not (Test-Path -LiteralPath $PathValue)) {
        return [pscustomobject]@{
            Exists         = $false
            ContainsTaskId = $false
        }
    }
    $content = Get-Content -LiteralPath $PathValue -Raw -ErrorAction Stop
    $contains = [regex]::IsMatch($content, [regex]::Escape($TaskId), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    return [pscustomobject]@{
        Exists         = $true
        ContainsTaskId = $contains
    }
}

function Convert-ToRelativePath {
    param([string]$BasePath, [string]$FullPath)
    if ([string]::IsNullOrWhiteSpace($BasePath) -or [string]::IsNullOrWhiteSpace($FullPath)) {
        return $FullPath
    }
    $normalizedBase = $BasePath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    if ($FullPath.StartsWith($normalizedBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $FullPath.Substring($normalizedBase.Length).TrimStart('\', '/')
    }
    return $FullPath
}

function Get-PathPattern {
    param([string]$PathText)
    if ([string]::IsNullOrWhiteSpace($PathText)) {
        return $null
    }
    $normalized = $PathText -replace '/', '\'
    $escaped = [regex]::Escape($normalized)
    return ($escaped -replace '\\\\', '[\\\\/]')
}

function Test-SessionReference {
    param(
        [string]$Text,
        [string]$RepoRoot,
        [string]$PathValue
    )
    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($PathValue)) {
        return $false
    }

    $patterns = @()
    $relative = Convert-ToRelativePath -BasePath $RepoRoot -FullPath $PathValue
    $relativePattern = Get-PathPattern -PathText $relative
    if ($relativePattern) {
        $patterns += $relativePattern
    }
    $leaf = Split-Path -Path $PathValue -Leaf
    if ($leaf) {
        $patterns += [regex]::Escape($leaf)
    }

    foreach ($pattern in $patterns) {
        if ([regex]::IsMatch($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            return $true
        }
    }
    return $false
}

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

if ([string]::IsNullOrWhiteSpace($TaskBoardPath)) {
    $TaskBoardPath = Join-Path -Path $repoRoot -ChildPath 'docs\StateTrace_TaskBoard.md'
}
if ([string]::IsNullOrWhiteSpace($TaskBoardCsvPath)) {
    $TaskBoardCsvPath = Join-Path -Path $repoRoot -ChildPath 'docs\taskboard\TaskBoard.csv'
}
if ([string]::IsNullOrWhiteSpace($BacklogPath)) {
    $BacklogPath = Join-Path -Path $repoRoot -ChildPath 'docs\CODEX_BACKLOG.md'
}

$taskBoardCsvRow = $null
if (Test-Path -LiteralPath $TaskBoardCsvPath) {
    try {
        $taskBoardCsvRow = Import-Csv -LiteralPath $TaskBoardCsvPath | Where-Object { $_.ID -eq $TaskId } | Select-Object -First 1
    } catch {
        throw "Unable to parse TaskBoard CSV at '$TaskBoardCsvPath': $($_.Exception.Message)"
    }
}

$planSource = 'Parameter'
$planLink = if ($taskBoardCsvRow) { $taskBoardCsvRow.PlanLink } else { $null }
if ([string]::IsNullOrWhiteSpace($PlanPath) -and -not [string]::IsNullOrWhiteSpace($planLink)) {
    $PlanPath = Resolve-RepoPath -PathValue $planLink -RepositoryRoot $repoRoot
    $planSource = 'TaskBoardCsv'
}
else {
    $PlanPath = Resolve-RepoPath -PathValue $PlanPath -RepositoryRoot $repoRoot
}

$result = [ordered]@{
    TaskId        = $TaskId
    TaskBoard     = [ordered]@{ Path = $TaskBoardPath; Exists = $false; ContainsTaskId = $false }
    TaskBoardCsv  = [ordered]@{ Path = $TaskBoardCsvPath; Exists = $false; ContainsTaskId = $false; PlanLink = $planLink }
    TaskBoardIntegrity = [ordered]@{ Path = $null; Passed = $false; Error = $null; RowCount = $null; MinimumRowCount = $TaskBoardMinimumRowCount }
    Plan          = [ordered]@{ Path = $PlanPath; Exists = $false; ContainsTaskId = $false; Source = $planSource }
    Backlog       = [ordered]@{ Path = $BacklogPath; Exists = $false; ContainsTaskId = $false; Required = $RequireBacklogEntry.IsPresent }
    SessionLog    = [ordered]@{ Path = $SessionLogPath; Exists = $false; ContainsTaskId = $false; References = @(); Required = $RequireSessionLog.IsPresent }
    Passed        = $true
    Missing       = @()
}

$taskBoardCheck = Test-TaskIdInFile -PathValue $TaskBoardPath -TaskId $TaskId
$result.TaskBoard.Exists = $taskBoardCheck.Exists
$result.TaskBoard.ContainsTaskId = $taskBoardCheck.ContainsTaskId
if (-not $taskBoardCheck.Exists) {
    $result.Missing += 'TaskBoardMissing'
}
elseif (-not $taskBoardCheck.ContainsTaskId) {
    $result.Missing += 'TaskBoardRowMissing'
}

if (Test-Path -LiteralPath $TaskBoardCsvPath) {
    $result.TaskBoardCsv.Exists = $true
    $result.TaskBoardCsv.ContainsTaskId = ($null -ne $taskBoardCsvRow)
    if (-not $taskBoardCsvRow) {
        $result.Missing += 'TaskBoardCsvRowMissing'
    }
}
else {
    $result.Missing += 'TaskBoardCsvMissing'
}

# LANDMARK: Doc sync - enforce TaskBoard integrity guard
$integrityScript = Join-Path $repoRoot 'Tools\Test-TaskBoardIntegrity.ps1'
if (-not (Test-Path -LiteralPath $integrityScript)) {
    $result.Missing += 'TaskBoardIntegrityScriptMissing'
}
else {
    $integrityOutput = $TaskBoardIntegrityOutputPath
    if ([string]::IsNullOrWhiteSpace($integrityOutput)) {
        $integrityOutput = Join-Path $repoRoot ("Logs\Reports\TaskBoardIntegrity-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }

    $integrityParams = @{
        RepositoryRoot  = $repoRoot
        TaskBoardCsvPath = $TaskBoardCsvPath
        MinimumRowCount = $TaskBoardMinimumRowCount
        MaxDeletedRows  = $TaskBoardMaxDeletedRows
        OutputPath      = $integrityOutput
        PassThru        = $true
        Quiet           = $true
    }
    if ($AllowLargeTaskBoardEdits) {
        $integrityParams['AllowLargeTaskBoardEdits'] = $true
    }

    $integrityError = $null
    $integrityResult = $null
    try {
        $integrityResult = & $integrityScript @integrityParams
    } catch {
        $integrityError = $_.Exception.Message
    }

    $result.TaskBoardIntegrity.Path = $integrityOutput
    if ($integrityResult) {
        $result.TaskBoardIntegrity.Passed = [bool]$integrityResult.Passed
        $result.TaskBoardIntegrity.RowCount = $integrityResult.RowCount
    }
    $result.TaskBoardIntegrity.Error = $integrityError
    if (-not $integrityResult -or -not $integrityResult.Passed) {
        $result.Missing += 'TaskBoardIntegrityFailed'
    }
}

if (-not [string]::IsNullOrWhiteSpace($PlanPath)) {
    $planCheck = Test-TaskIdInFile -PathValue $PlanPath -TaskId $TaskId
    $result.Plan.Exists = $planCheck.Exists
    $result.Plan.ContainsTaskId = $planCheck.ContainsTaskId
    if (-not $planCheck.Exists) {
        $result.Missing += 'PlanMissing'
    }
    elseif (-not $planCheck.ContainsTaskId) {
        $result.Missing += 'PlanEntryMissing'
    }
}
else {
    $result.Missing += 'PlanPathMissing'
}

$backlogCheck = Test-TaskIdInFile -PathValue $BacklogPath -TaskId $TaskId
$result.Backlog.Exists = $backlogCheck.Exists
$result.Backlog.ContainsTaskId = $backlogCheck.ContainsTaskId
if ($RequireBacklogEntry -and (-not $backlogCheck.Exists -or -not $backlogCheck.ContainsTaskId)) {
    $result.Missing += 'BacklogEntryMissing'
}

$requireSessionLogChecks = $RequireSessionLog.IsPresent -or -not [string]::IsNullOrWhiteSpace($SessionLogPath)
$result.SessionLog.Required = $requireSessionLogChecks

if ($requireSessionLogChecks -and [string]::IsNullOrWhiteSpace($SessionLogPath)) {
    $result.Missing += 'SessionLogPathMissing'
}

if (-not [string]::IsNullOrWhiteSpace($SessionLogPath)) {
    if (-not (Test-Path -LiteralPath $SessionLogPath)) {
        $result.Missing += 'SessionLogMissing'
    }
    else {
        $result.SessionLog.Exists = $true
        $sessionText = Get-Content -LiteralPath $SessionLogPath -Raw -ErrorAction Stop
        $containsTask = [regex]::IsMatch($sessionText, [regex]::Escape($TaskId), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $result.SessionLog.ContainsTaskId = $containsTask
        if (-not $containsTask) {
            $result.Missing += 'SessionLogTaskMissing'
        }

        $referenceMap = @{
            TaskBoard    = $TaskBoardPath
            TaskBoardCsv = $TaskBoardCsvPath
            Backlog      = $BacklogPath
            Plan         = $PlanPath
        }
        foreach ($entry in $referenceMap.GetEnumerator()) {
            if ($entry.Value -and (Test-Path -LiteralPath $entry.Value)) {
                if (Test-SessionReference -Text $sessionText -RepoRoot $repoRoot -PathValue $entry.Value) {
                    $result.SessionLog.References += $entry.Key
                }
            }
        }

        if ($result.SessionLog.References.Count -eq 0) {
            $result.Missing += 'SessionLogReferencesMissing'
        }
    }
}

if ($result.Missing.Count -gt 0) {
    $result.Passed = $false
}

if ($OutputPath) {
    $outputDirectory = Split-Path -Path $OutputPath -Parent
    if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $OutputPath -Encoding utf8
    if (-not $Quiet) {
        Write-Host ("Doc-sync checklist written to {0}" -f (Resolve-Path -LiteralPath $OutputPath)) -ForegroundColor DarkCyan
    }
}

if (-not $result.Passed) {
    $missingText = $result.Missing -join ', '
    throw "Doc-sync checklist failed for $TaskId. Missing: $missingText"
}

if (-not $Quiet) {
    Write-Host ("Doc-sync checklist passed for {0}." -f $TaskId) -ForegroundColor Green
}

if ($PassThru) {
    return [pscustomobject]$result
}
