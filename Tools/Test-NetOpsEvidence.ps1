[CmdletBinding()]
param(
    [string]$NetOpsDirectory = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Logs\NetOps'),
    [string]$ResetDirectory,
    [int]$MaxHours = 12,
    [switch]$RequireEvidence,
    [switch]$RequireReason,
    [string]$SessionLogPath,
    [switch]$RequireSessionReference,
    [switch]$PassThru,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ExistingDirectory {
    param([string]$PathValue, [string]$Description)
    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        throw ("{0} directory is not defined." -f $Description)
    }
    $resolved = Resolve-Path -LiteralPath $PathValue -ErrorAction Stop
    return $resolved.Path
}

if ($MaxHours -lt 1) {
    $MaxHours = 12
}

$netOpsDirResolved = Resolve-ExistingDirectory -PathValue $NetOpsDirectory -Description 'NetOps'
if ([string]::IsNullOrWhiteSpace($ResetDirectory)) {
    $ResetDirectory = Join-Path -Path $netOpsDirResolved -ChildPath 'Resets'
}
$resetDirResolved = Resolve-Path -LiteralPath $ResetDirectory -ErrorAction SilentlyContinue

$allowNet = [Environment]::GetEnvironmentVariable('STATETRACE_AGENT_ALLOW_NET')
$allowInstall = [Environment]::GetEnvironmentVariable('STATETRACE_AGENT_ALLOW_INSTALL')
$onlineModeActive = $RequireEvidence.IsPresent -or `
    ((-not [string]::IsNullOrWhiteSpace($allowNet)) -and ($allowNet -ne '0')) -or `
    ((-not [string]::IsNullOrWhiteSpace($allowInstall)) -and ($allowInstall -ne '0'))

$result = [ordered]@{
    OnlineModeActive          = $onlineModeActive
    EvidenceRequired          = $RequireEvidence.IsPresent
    ReasonRequired            = $RequireReason.IsPresent
    LatestLogPath             = $null
    LatestLogAgeHours         = $null
    LatestResetLogPath        = $null
    LatestResetAgeHours       = $null
    LatestResetReason         = $null
    SessionLogPath            = $SessionLogPath
    SessionReferenceSatisfied = $false
    Message                   = $null
}

if (-not $onlineModeActive) {
    $result.Message = 'NetOps lint skipped because STATETRACE_AGENT_ALLOW_* is not enabled and -RequireEvidence was not supplied.'
    if (-not $Quiet) {
        Write-Host $result.Message -ForegroundColor DarkGray
    }
    if ($PassThru) {
        return [pscustomobject]$result
    }
    return
}

$threshold = (Get-Date).AddHours(-1 * $MaxHours)
$generalLogs = Get-ChildItem -LiteralPath $netOpsDirResolved -Filter '*.json' -File -ErrorAction Stop |
    Where-Object { $_.DirectoryName -ne $resetDirResolved }

if (-not $generalLogs -or $generalLogs.Count -eq 0) {
    throw ("NetOps lint failed: no JSON logs found under '{0}'." -f $netOpsDirResolved)
}

$recentGeneral = $generalLogs | Where-Object { $_.LastWriteTime -ge $threshold }
if (-not $recentGeneral -or $recentGeneral.Count -eq 0) {
    throw ("NetOps lint failed: no NetOps log newer than {0} hours (directory: {1})." -f $MaxHours, $netOpsDirResolved)
}

$latestGeneral = $generalLogs | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$result.LatestLogPath = $latestGeneral.FullName
$result.LatestLogAgeHours = [math]::Round(((Get-Date) - $latestGeneral.LastWriteTime).TotalHours, 3)

$recentReset = @()
if ($resetDirResolved) {
    $resetLogs = Get-ChildItem -LiteralPath $resetDirResolved -Filter '*.json' -File -ErrorAction SilentlyContinue
    if ($resetLogs) {
        $recentReset = $resetLogs | Where-Object { $_.LastWriteTime -ge $threshold }
        $latestReset = $resetLogs | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $result.LatestResetLogPath = $latestReset.FullName
        $result.LatestResetAgeHours = [math]::Round(((Get-Date) - $latestReset.LastWriteTime).TotalHours, 3)

        try {
            $resetPayload = Get-Content -LiteralPath $latestReset.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $resetReason = $resetPayload.Reason
            if ($resetReason) {
                $resetReason = $resetReason.ToString().Trim()
            }
            $result.LatestResetReason = $resetReason
            if ($RequireReason -and [string]::IsNullOrWhiteSpace($resetReason)) {
                throw ("NetOps lint failed: latest reset log '{0}' is missing the 'Reason' field. Re-run Tools\Reset-OnlineModeFlags.ps1 -Reason \"<plan/task>\" before proceeding." -f $latestReset.Name)
            }
        }
        catch {
            if ($RequireReason) {
                throw
            }
            if (-not $Quiet) {
                Write-Warning ("Unable to parse reset log '{0}' for reason metadata: {1}" -f $latestReset.FullName, $_.Exception.Message)
            }
        }
    }
}

if (-not $recentReset -or $recentReset.Count -eq 0) {
    throw ("NetOps lint failed: no reset logs newer than {0} hours were found under '{1}'. Run Tools\Reset-OnlineModeFlags.ps1 before finishing an online session." -f $MaxHours, $ResetDirectory)
}

if ($RequireSessionReference.IsPresent) {
    if ([string]::IsNullOrWhiteSpace($SessionLogPath)) {
        throw 'NetOps lint failed: -RequireSessionReference was supplied but -SessionLogPath is not set.'
    }
    if (-not (Test-Path -LiteralPath $SessionLogPath)) {
        throw ("NetOps lint failed: session log '{0}' was not found." -f $SessionLogPath)
    }
    $sessionText = Get-Content -LiteralPath $SessionLogPath -Raw -ErrorAction Stop
    $needle = [regex]::Escape($latestGeneral.Name)
    $result.SessionReferenceSatisfied = [regex]::IsMatch($sessionText, $needle, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $result.SessionReferenceSatisfied) {
        throw ("NetOps lint failed: session log '{0}' does not mention '{1}'. Record the NetOps log path in the session log before proceeding." -f $SessionLogPath, $latestGeneral.Name)
    }
}

if (-not $Quiet) {
    Write-Host ("NetOps lint passed. Latest log: {0}" -f $result.LatestLogPath) -ForegroundColor Green
    Write-Host ("Latest reset log: {0}" -f $result.LatestResetLogPath) -ForegroundColor Green
    if ($result.SessionReferenceSatisfied) {
        Write-Host ("Session log '{0}' references {1}." -f $SessionLogPath, $latestGeneral.Name) -ForegroundColor Green
    }
}

if ($PassThru) {
    return [pscustomobject]$result
}
