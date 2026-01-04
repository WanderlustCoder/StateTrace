<#
.SYNOPSIS
Validates that incident closure evidence requirements are met.

.DESCRIPTION
ST-R-003: Integrates online-mode evidence enforcement into incident closure.
Blocks closure without NetOps evidence and reset flags. Validates:
- NetOps log presence (if online mode was used)
- Reset log with reason
- Session log references
- Post-incident verification artifacts

.PARAMETER IncidentId
Optional incident identifier for tracking.

.PARAMETER SessionLogPath
Path to session log that should reference NetOps logs.

.PARAMETER RequireNetOpsEvidence
Require NetOps logs and reset logs with reasons.

.PARAMETER RequirePostIncidentVerification
Require verification artifacts (AllChecks, shared-cache diagnostics).

.PARAMETER MaxNetOpsAgeHours
Maximum age for NetOps logs. Default 24.

.PARAMETER RepositoryRoot
Repository root path. Defaults to parent of script directory.

.PARAMETER OutputPath
Optional JSON output path for the closure report.

.PARAMETER FailOnMissingEvidence
Exit with error code if evidence is missing.

.PARAMETER PassThru
Return the closure result as an object.

.EXAMPLE
.\Test-IncidentClosureEvidence.ps1 -IncidentId INC0007 -RequireNetOpsEvidence -FailOnMissingEvidence

.EXAMPLE
.\Test-IncidentClosureEvidence.ps1 -SessionLogPath docs\agents\sessions\2026-01-04_session-0001.md
#>
param(
    [string]$IncidentId,
    [string]$SessionLogPath,
    [switch]$RequireNetOpsEvidence,
    [switch]$RequirePostIncidentVerification,
    [int]$MaxNetOpsAgeHours = 24,
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$OutputPath,
    [switch]$FailOnMissingEvidence,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

Write-Host "Validating incident closure evidence..." -ForegroundColor Cyan
if ($IncidentId) {
    Write-Host ("  Incident: {0}" -f $IncidentId) -ForegroundColor Cyan
}

$checks = [System.Collections.Generic.List[pscustomobject]]::new()
$issues = [System.Collections.Generic.List[pscustomobject]]::new()
$suggestions = [System.Collections.Generic.List[string]]::new()

# Check 1: Online mode flags status
$onlineModeCheck = [pscustomobject]@{
    Name       = 'OnlineModeStatus'
    Status     = 'Pass'
    Details    = $null
}

$allowNet = [Environment]::GetEnvironmentVariable('STATETRACE_AGENT_ALLOW_NET')
$allowInstall = [Environment]::GetEnvironmentVariable('STATETRACE_AGENT_ALLOW_INSTALL')
$onlineModeActive = ((-not [string]::IsNullOrWhiteSpace($allowNet)) -and ($allowNet -ne '0')) -or `
    ((-not [string]::IsNullOrWhiteSpace($allowInstall)) -and ($allowInstall -ne '0'))

$onlineModeCheck.Details = [pscustomobject]@{
    STATETRACE_AGENT_ALLOW_NET = $allowNet
    STATETRACE_AGENT_ALLOW_INSTALL = $allowInstall
    OnlineModeActive = $onlineModeActive
}

if ($onlineModeActive) {
    $onlineModeCheck.Status = 'Warning'
    $issues.Add([pscustomobject]@{
        Type    = 'OnlineModeStillActive'
        Message = 'Online mode flags are still active - run Tools\Reset-OnlineModeFlags.ps1 before closing'
    })
    $suggestions.Add('Run: Tools\Reset-OnlineModeFlags.ps1 -Reason "Incident closure <IncidentId>"')
}

$checks.Add($onlineModeCheck)

# Check 2: NetOps evidence (if required or online mode was detected)
if ($RequireNetOpsEvidence -or $onlineModeActive) {
    $netOpsCheck = [pscustomobject]@{
        Name    = 'NetOpsEvidence'
        Status  = 'Checking'
        Details = $null
    }

    $netOpsDir = Join-Path $repoRoot 'Logs\NetOps'
    $resetDir = Join-Path $netOpsDir 'Resets'

    $netOpsLogs = @()
    $resetLogs = @()

    if (Test-Path -LiteralPath $netOpsDir) {
        $netOpsLogs = @(Get-ChildItem -LiteralPath $netOpsDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -ne $resetDir })
    }

    if (Test-Path -LiteralPath $resetDir) {
        $resetLogs = @(Get-ChildItem -LiteralPath $resetDir -Filter '*.json' -File -ErrorAction SilentlyContinue)
    }

    $threshold = (Get-Date).AddHours(-$MaxNetOpsAgeHours)
    $recentNetOps = @($netOpsLogs | Where-Object { $_.LastWriteTime -ge $threshold })
    $recentResets = @($resetLogs | Where-Object { $_.LastWriteTime -ge $threshold })

    $latestNetOps = $netOpsLogs | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $latestReset = $resetLogs | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    $hasRecentNetOps = $recentNetOps.Count -gt 0
    $hasRecentReset = $recentResets.Count -gt 0

    # Check reset reason
    $resetReason = $null
    if ($latestReset) {
        try {
            $resetPayload = Get-Content -LiteralPath $latestReset.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
            $resetReason = if ($resetPayload.Reason) { $resetPayload.Reason.ToString().Trim() } else { $null }
        }
        catch { }
    }

    $netOpsCheck.Details = [pscustomobject]@{
        TotalNetOpsLogs = $netOpsLogs.Count
        TotalResetLogs  = $resetLogs.Count
        RecentNetOps    = $recentNetOps.Count
        RecentResets    = $recentResets.Count
        LatestNetOps    = if ($latestNetOps) { $latestNetOps.Name } else { $null }
        LatestReset     = if ($latestReset) { $latestReset.Name } else { $null }
        ResetReason     = $resetReason
    }

    if ($RequireNetOpsEvidence) {
        if (-not $hasRecentNetOps) {
            $netOpsCheck.Status = 'Fail'
            $issues.Add([pscustomobject]@{
                Type    = 'MissingNetOpsLog'
                Message = ("No NetOps logs found within {0} hours" -f $MaxNetOpsAgeHours)
            })
            $suggestions.Add('Capture NetOps evidence using docs\templates\NetOpsLogTemplate.json')
        }
        elseif (-not $hasRecentReset) {
            $netOpsCheck.Status = 'Fail'
            $issues.Add([pscustomobject]@{
                Type    = 'MissingResetLog'
                Message = ("No reset logs found within {0} hours" -f $MaxNetOpsAgeHours)
            })
            $suggestions.Add('Run: Tools\Reset-OnlineModeFlags.ps1 -Reason "<plan/task>"')
        }
        elseif ([string]::IsNullOrWhiteSpace($resetReason)) {
            $netOpsCheck.Status = 'Fail'
            $issues.Add([pscustomobject]@{
                Type    = 'MissingResetReason'
                Message = 'Latest reset log is missing the Reason field'
            })
            $suggestions.Add('Re-run: Tools\Reset-OnlineModeFlags.ps1 -Reason "<plan/task>"')
        }
        else {
            $netOpsCheck.Status = 'Pass'
        }
    }
    else {
        $netOpsCheck.Status = if ($hasRecentReset -and -not [string]::IsNullOrWhiteSpace($resetReason)) { 'Pass' } else { 'Warning' }
    }

    $checks.Add($netOpsCheck)
}

# Check 3: Post-incident verification (if required)
if ($RequirePostIncidentVerification) {
    $verificationCheck = [pscustomobject]@{
        Name    = 'PostIncidentVerification'
        Status  = 'Checking'
        Details = $null
    }

    $verificationDir = Join-Path $repoRoot 'Logs\Verification'
    $reportsDir = Join-Path $repoRoot 'Logs\Reports'

    $hasAllChecks = $false
    $hasSharedCacheDiag = $false
    $latestAllChecks = $null
    $latestDiag = $null

    if (Test-Path -LiteralPath $verificationDir) {
        $allChecksLogs = @(Get-ChildItem -LiteralPath $verificationDir -Filter 'AllChecks-*.log' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending)
        if ($allChecksLogs.Count -gt 0) {
            $latestAllChecks = $allChecksLogs[0]
            $hasAllChecks = $latestAllChecks.LastWriteTime -ge (Get-Date).AddHours(-$MaxNetOpsAgeHours)
        }
    }

    if (Test-Path -LiteralPath $reportsDir) {
        $diagReports = @(Get-ChildItem -LiteralPath $reportsDir -Filter 'SharedCache*.json' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending)
        if ($diagReports.Count -gt 0) {
            $latestDiag = $diagReports[0]
            $hasSharedCacheDiag = $latestDiag.LastWriteTime -ge (Get-Date).AddHours(-$MaxNetOpsAgeHours)
        }
    }

    $verificationCheck.Details = [pscustomobject]@{
        HasAllChecks       = $hasAllChecks
        LatestAllChecks    = if ($latestAllChecks) { $latestAllChecks.Name } else { $null }
        HasSharedCacheDiag = $hasSharedCacheDiag
        LatestDiag         = if ($latestDiag) { $latestDiag.Name } else { $null }
    }

    if (-not $hasAllChecks) {
        $verificationCheck.Status = 'Fail'
        $issues.Add([pscustomobject]@{
            Type    = 'MissingAllChecks'
            Message = ("No AllChecks verification within {0} hours" -f $MaxNetOpsAgeHours)
        })
        $suggestions.Add('Run: Tools\Invoke-AllChecks.ps1 -OutputPath Logs\Verification\AllChecks-postincident.log')
    }
    elseif (-not $hasSharedCacheDiag) {
        $verificationCheck.Status = 'Warning'
        $issues.Add([pscustomobject]@{
            Type    = 'MissingSharedCacheDiag'
            Message = 'No recent shared cache diagnostics report'
        })
        $suggestions.Add('Run: Tools\Analyze-SharedCacheStoreState.ps1 -OutputPath Logs\Reports\SharedCachePostIncident.json')
    }
    else {
        $verificationCheck.Status = 'Pass'
    }

    $checks.Add($verificationCheck)
}

# Check 4: Session log reference (if provided)
if ($SessionLogPath) {
    $sessionCheck = [pscustomobject]@{
        Name    = 'SessionLogReference'
        Status  = 'Checking'
        Details = $null
    }

    if (-not (Test-Path -LiteralPath $SessionLogPath)) {
        $sessionCheck.Status = 'Fail'
        $issues.Add([pscustomobject]@{
            Type    = 'SessionLogNotFound'
            Message = ("Session log not found: {0}" -f $SessionLogPath)
        })
    }
    else {
        $sessionContent = Get-Content -LiteralPath $SessionLogPath -Raw -ErrorAction SilentlyContinue

        $hasIncidentRef = $false
        $hasEvidenceRef = $false

        if ($IncidentId) {
            $hasIncidentRef = $sessionContent -match [regex]::Escape($IncidentId)
        }

        # Check for evidence references (NetOps logs, verification logs)
        $hasEvidenceRef = $sessionContent -match 'NetOps|AllChecks|Verification|SharedCache'

        $sessionCheck.Details = [pscustomobject]@{
            Path             = $SessionLogPath
            HasIncidentRef   = $hasIncidentRef
            HasEvidenceRef   = $hasEvidenceRef
        }

        if ($IncidentId -and -not $hasIncidentRef) {
            $sessionCheck.Status = 'Warning'
            $issues.Add([pscustomobject]@{
                Type    = 'MissingIncidentReference'
                Message = ("Session log does not reference incident: {0}" -f $IncidentId)
            })
        }
        elseif (-not $hasEvidenceRef) {
            $sessionCheck.Status = 'Warning'
            $issues.Add([pscustomobject]@{
                Type    = 'MissingEvidenceReference'
                Message = 'Session log does not reference verification/evidence artifacts'
            })
        }
        else {
            $sessionCheck.Status = 'Pass'
        }
    }

    $checks.Add($sessionCheck)
}

# Build result
$passCount = @($checks | Where-Object { $_.Status -eq 'Pass' }).Count
$failCount = @($checks | Where-Object { $_.Status -eq 'Fail' }).Count
$warnCount = @($checks | Where-Object { $_.Status -eq 'Warning' }).Count

$result = [pscustomobject]@{
    Timestamp   = Get-Date -Format 'o'
    IncidentId  = $IncidentId
    Status      = if ($failCount -gt 0) { 'Fail' } elseif ($warnCount -gt 0) { 'Warning' } else { 'Pass' }
    CanClose    = $failCount -eq 0
    CheckCount  = $checks.Count
    PassCount   = $passCount
    FailCount   = $failCount
    WarnCount   = $warnCount
    Checks      = $checks
    Issues      = $issues
    Suggestions = $suggestions
}

# Output
if ($OutputPath) {
    $outputDir = Split-Path -Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host ("Report written to: {0}" -f $OutputPath) -ForegroundColor Green
}

# Display summary
Write-Host "`nIncident Closure Evidence Summary:" -ForegroundColor Cyan

foreach ($check in $checks) {
    $color = switch ($check.Status) {
        'Pass' { 'Green' }
        'Warning' { 'Yellow' }
        'Fail' { 'Red' }
        default { 'White' }
    }
    Write-Host ("  [{0}] {1}" -f $check.Status.ToUpper().PadRight(7), $check.Name) -ForegroundColor $color
}

if ($issues.Count -gt 0) {
    Write-Host ("`nIssues: {0}" -f $issues.Count) -ForegroundColor Yellow
    foreach ($issue in $issues) {
        Write-Host ("  - [{0}] {1}" -f $issue.Type, $issue.Message) -ForegroundColor Yellow
    }
}

if ($suggestions.Count -gt 0 -and $failCount -gt 0) {
    Write-Host "`nSuggestions:" -ForegroundColor Cyan
    foreach ($sug in ($suggestions | Select-Object -Unique)) {
        Write-Host ("  - {0}" -f $sug) -ForegroundColor Cyan
    }
}

if ($result.CanClose) {
    Write-Host "`nStatus: READY TO CLOSE - Evidence requirements met" -ForegroundColor Green
}
else {
    Write-Host "`nStatus: BLOCKED - Cannot close without resolving issues" -ForegroundColor Red
}

if ($FailOnMissingEvidence -and -not $result.CanClose) {
    Write-Error "Incident closure blocked - missing evidence requirements"
    exit 2
}

if ($PassThru) {
    return $result
}
