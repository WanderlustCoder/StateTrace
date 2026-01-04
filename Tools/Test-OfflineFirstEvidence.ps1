[CmdletBinding()]
param(
    [string]$SessionLogPath,
    [switch]$RequireAccessLog,
    [switch]$RequireNetOpsLog,
    [switch]$RequireSanitizationLog,
    [string]$OutputPath,
    [switch]$PassThru
)

<#
.SYNOPSIS
Validates offline-first compliance evidence for a session (ST-F-005).

.DESCRIPTION
Checks that a session has properly documented:
1. Access database usage (if any)
2. Online-mode status (NetOps logs and reset logs)
3. Sanitized fixture usage (if any)

Also verifies no .accdb files are staged for commit.

.PARAMETER SessionLogPath
Path to the session log markdown file to check for evidence references.

.PARAMETER RequireAccessLog
If set, fails when no Access database usage is documented.

.PARAMETER RequireNetOpsLog
If set, fails when online mode was used but no NetOps/reset logs are documented.

.PARAMETER RequireSanitizationLog
If set, fails when sanitized fixtures were used but no sanitization report is documented.

.PARAMETER OutputPath
If specified, writes the validation results to a JSON file.

.PARAMETER PassThru
Returns the validation results as an object.

.EXAMPLE
pwsh Tools\Test-OfflineFirstEvidence.ps1 -SessionLogPath docs/agents/sessions/2026-01-04_session-0001.md

.EXAMPLE
pwsh Tools\Test-OfflineFirstEvidence.ps1 -RequireNetOpsLog -PassThru
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent

# Initialize results
$results = [pscustomobject]@{
    GeneratedAtUtc       = (Get-Date).ToUniversalTime().ToString('o')
    SessionLogPath       = $SessionLogPath
    OverallStatus        = 'Unknown'
    AccessDatabaseCheck  = [pscustomobject]@{
        Status           = 'NotChecked'
        StagedAccdbFiles = @()
        Message          = ''
    }
    OnlineModeCheck      = [pscustomobject]@{
        Status           = 'NotChecked'
        EnvVarNet        = $null
        EnvVarInstall    = $null
        NetOpsLogs       = @()
        ResetLogs        = @()
        Message          = ''
    }
    SanitizationCheck    = [pscustomobject]@{
        Status           = 'NotChecked'
        SanitizationLogs = @()
        Message          = ''
    }
    Warnings             = @()
    Errors               = @()
}

Write-Host "`n=== Offline-First Evidence Check (ST-F-005) ===" -ForegroundColor Cyan
Write-Host ("Timestamp: {0}" -f $results.GeneratedAtUtc) -ForegroundColor DarkGray
Write-Host ""

# 1. Check for staged .accdb files
Write-Host "--- Access Database Check ---" -ForegroundColor Yellow
try {
    $gitStatusOutput = git status --porcelain 2>&1
    $stagedAccdb = @()
    foreach ($line in $gitStatusOutput) {
        if ($line -match '\.accdb') {
            $stagedAccdb += $line
        }
    }

    if ($stagedAccdb.Count -gt 0) {
        $results.AccessDatabaseCheck.Status = 'Fail'
        $results.AccessDatabaseCheck.StagedAccdbFiles = $stagedAccdb
        $results.AccessDatabaseCheck.Message = "Found $($stagedAccdb.Count) .accdb file(s) in git status - these should not be committed"
        $results.Errors += $results.AccessDatabaseCheck.Message
        Write-Host "  FAIL: $($results.AccessDatabaseCheck.Message)" -ForegroundColor Red
        foreach ($file in $stagedAccdb) {
            Write-Host "    - $file" -ForegroundColor Red
        }
    } else {
        $results.AccessDatabaseCheck.Status = 'Pass'
        $results.AccessDatabaseCheck.Message = 'No .accdb files staged for commit'
        Write-Host "  PASS: $($results.AccessDatabaseCheck.Message)" -ForegroundColor Green
    }
} catch {
    $results.AccessDatabaseCheck.Status = 'Error'
    $results.AccessDatabaseCheck.Message = "Error checking git status: $($_.Exception.Message)"
    $results.Warnings += $results.AccessDatabaseCheck.Message
    Write-Host "  WARNING: $($results.AccessDatabaseCheck.Message)" -ForegroundColor Yellow
}
Write-Host ""

# 2. Check online-mode status
Write-Host "--- Online-Mode Check ---" -ForegroundColor Yellow
$results.OnlineModeCheck.EnvVarNet = $env:STATETRACE_AGENT_ALLOW_NET
$results.OnlineModeCheck.EnvVarInstall = $env:STATETRACE_AGENT_ALLOW_INSTALL

$onlineModeActive = ($env:STATETRACE_AGENT_ALLOW_NET -eq '1') -or ($env:STATETRACE_AGENT_ALLOW_INSTALL -eq '1')

$netValue = if ($env:STATETRACE_AGENT_ALLOW_NET) { $env:STATETRACE_AGENT_ALLOW_NET } else { '(not set)' }
$installValue = if ($env:STATETRACE_AGENT_ALLOW_INSTALL) { $env:STATETRACE_AGENT_ALLOW_INSTALL } else { '(not set)' }
Write-Host ("  STATETRACE_AGENT_ALLOW_NET: {0}" -f $netValue) -ForegroundColor DarkGray
Write-Host ("  STATETRACE_AGENT_ALLOW_INSTALL: {0}" -f $installValue) -ForegroundColor DarkGray

if ($onlineModeActive) {
    Write-Host "  Online mode is currently ACTIVE" -ForegroundColor Yellow
    $results.Warnings += "Online mode is currently active - ensure it is reset before session ends"
}

# Check for NetOps logs
$netOpsDir = Join-Path -Path $repositoryRoot -ChildPath 'Logs\NetOps'
$resetDir = Join-Path -Path $netOpsDir -ChildPath 'Resets'

if (Test-Path -LiteralPath $netOpsDir) {
    $netOpsLogs = Get-ChildItem -Path $netOpsDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike 'Resets*' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 5
    $results.OnlineModeCheck.NetOpsLogs = @($netOpsLogs | ForEach-Object { $_.Name })
    if ($netOpsLogs.Count -gt 0) {
        Write-Host ("  Found {0} recent NetOps log(s)" -f $netOpsLogs.Count) -ForegroundColor DarkGray
    }
}

if (Test-Path -LiteralPath $resetDir) {
    $resetLogs = Get-ChildItem -Path $resetDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 5
    $results.OnlineModeCheck.ResetLogs = @($resetLogs | ForEach-Object { $_.Name })
    if ($resetLogs.Count -gt 0) {
        Write-Host ("  Found {0} recent reset log(s)" -f $resetLogs.Count) -ForegroundColor DarkGray
    }
}

if ($RequireNetOpsLog.IsPresent -and $onlineModeActive) {
    if ($results.OnlineModeCheck.ResetLogs.Count -eq 0) {
        $results.OnlineModeCheck.Status = 'Fail'
        $results.OnlineModeCheck.Message = 'Online mode is active but no reset logs found - run Tools\Reset-OnlineModeFlags.ps1'
        $results.Errors += $results.OnlineModeCheck.Message
        Write-Host "  FAIL: $($results.OnlineModeCheck.Message)" -ForegroundColor Red
    }
}

if (-not $onlineModeActive) {
    $results.OnlineModeCheck.Status = 'Pass'
    $results.OnlineModeCheck.Message = 'Session is running in offline mode'
    Write-Host "  PASS: $($results.OnlineModeCheck.Message)" -ForegroundColor Green
} elseif ($results.OnlineModeCheck.Status -ne 'Fail') {
    $results.OnlineModeCheck.Status = 'Warning'
    $results.OnlineModeCheck.Message = 'Online mode active - remember to reset before session ends'
    Write-Host "  WARNING: $($results.OnlineModeCheck.Message)" -ForegroundColor Yellow
}
Write-Host ""

# 3. Check sanitization evidence
Write-Host "--- Sanitization Check ---" -ForegroundColor Yellow
$sanitizationDir = Join-Path -Path $repositoryRoot -ChildPath 'Logs\Sanitization'

if (Test-Path -LiteralPath $sanitizationDir) {
    $sanitizationLogs = Get-ChildItem -Path $sanitizationDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 5
    $results.SanitizationCheck.SanitizationLogs = @($sanitizationLogs | ForEach-Object { $_.Name })

    if ($sanitizationLogs.Count -gt 0) {
        $results.SanitizationCheck.Status = 'Pass'
        $results.SanitizationCheck.Message = "Found $($sanitizationLogs.Count) sanitization log(s)"
        Write-Host "  PASS: $($results.SanitizationCheck.Message)" -ForegroundColor Green
        foreach ($log in $sanitizationLogs) {
            Write-Host ("    - {0}" -f $log.Name) -ForegroundColor DarkGray
        }
    } else {
        $results.SanitizationCheck.Status = 'NotApplicable'
        $results.SanitizationCheck.Message = 'No sanitization logs found (may not be required for this session)'
        Write-Host "  INFO: $($results.SanitizationCheck.Message)" -ForegroundColor DarkGray
    }
} else {
    $results.SanitizationCheck.Status = 'NotApplicable'
    $results.SanitizationCheck.Message = 'Sanitization directory does not exist'
    Write-Host "  INFO: $($results.SanitizationCheck.Message)" -ForegroundColor DarkGray
}

if ($RequireSanitizationLog.IsPresent -and $results.SanitizationCheck.SanitizationLogs.Count -eq 0) {
    $results.SanitizationCheck.Status = 'Fail'
    $results.SanitizationCheck.Message = 'Sanitization log required but none found'
    $results.Errors += $results.SanitizationCheck.Message
    Write-Host "  FAIL: $($results.SanitizationCheck.Message)" -ForegroundColor Red
}
Write-Host ""

# 4. Check session log for evidence references (if provided)
if (-not [string]::IsNullOrWhiteSpace($SessionLogPath)) {
    Write-Host "--- Session Log Evidence Check ---" -ForegroundColor Yellow
    $sessionLogFullPath = if ([System.IO.Path]::IsPathRooted($SessionLogPath)) {
        $SessionLogPath
    } else {
        Join-Path -Path $repositoryRoot -ChildPath $SessionLogPath
    }

    if (Test-Path -LiteralPath $sessionLogFullPath) {
        $sessionContent = Get-Content -Raw -LiteralPath $sessionLogFullPath

        $hasAccessRef = $sessionContent -match '\.accdb|Access.*database|database.*Access'
        $hasNetOpsRef = $sessionContent -match 'NetOps|STATETRACE_AGENT_ALLOW|online.*mode|Reset-OnlineModeFlags'
        $hasSanitizationRef = $sessionContent -match 'Sanitiz|sanitiz|Logs/Sanitization|Tests/Fixtures'

        $accessStatus = if ($hasAccessRef) { 'Found' } else { 'Not found' }
        $netOpsStatus = if ($hasNetOpsRef) { 'Found' } else { 'Not found' }
        $sanitizationStatus = if ($hasSanitizationRef) { 'Found' } else { 'Not found' }
        Write-Host ("  Access database references: {0}" -f $accessStatus) -ForegroundColor DarkGray
        Write-Host ("  NetOps/online-mode references: {0}" -f $netOpsStatus) -ForegroundColor DarkGray
        Write-Host ("  Sanitization references: {0}" -f $sanitizationStatus) -ForegroundColor DarkGray

        if ($RequireAccessLog.IsPresent -and -not $hasAccessRef) {
            $results.Warnings += 'Session log does not mention Access database usage'
        }
    } else {
        Write-Host "  Session log not found at: $sessionLogFullPath" -ForegroundColor Yellow
        $results.Warnings += "Session log not found: $SessionLogPath"
    }
    Write-Host ""
}

# Calculate overall status
$hasErrors = $results.Errors.Count -gt 0
$hasWarnings = $results.Warnings.Count -gt 0

if ($hasErrors) {
    $results.OverallStatus = 'Fail'
} elseif ($hasWarnings) {
    $results.OverallStatus = 'Warning'
} else {
    $results.OverallStatus = 'Pass'
}

# Summary
Write-Host "=== Summary ===" -ForegroundColor Cyan
$overallColor = switch ($results.OverallStatus) {
    'Pass' { 'Green' }
    'Warning' { 'Yellow' }
    'Fail' { 'Red' }
    default { 'DarkGray' }
}
Write-Host ("Overall Status: {0}" -f $results.OverallStatus) -ForegroundColor $overallColor

if ($results.Errors.Count -gt 0) {
    Write-Host "`nErrors:" -ForegroundColor Red
    foreach ($err in $results.Errors) {
        Write-Host "  - $err" -ForegroundColor Red
    }
}

if ($results.Warnings.Count -gt 0) {
    Write-Host "`nWarnings:" -ForegroundColor Yellow
    foreach ($warn in $results.Warnings) {
        Write-Host "  - $warn" -ForegroundColor Yellow
    }
}
Write-Host ""

# Output
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    try {
        $outputDir = Split-Path -Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        $results | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8
        Write-Host "Results saved to: $OutputPath" -ForegroundColor DarkCyan
    } catch {
        Write-Warning "Failed to save results: $($_.Exception.Message)"
    }
}

if ($PassThru.IsPresent) {
    return $results
}

# Exit with appropriate code
if ($results.OverallStatus -eq 'Fail') {
    exit 1
}
