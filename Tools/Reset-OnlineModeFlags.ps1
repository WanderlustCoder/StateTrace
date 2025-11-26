[CmdletBinding()]
param(
    [string[]]$EnvVarNames = @('STATETRACE_AGENT_ALLOW_NET', 'STATETRACE_AGENT_ALLOW_INSTALL'),
    [string]$OutputDirectory = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Logs\NetOps'),
    [string]$LogPrefix = 'OnlineModeReset',
    [string]$Reason,
    [switch]$PassThru,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $EnvVarNames -or $EnvVarNames.Count -eq 0) {
    throw 'Provide at least one environment variable to reset.'
}

$resolvedOutput = $OutputDirectory
if ([string]::IsNullOrWhiteSpace($resolvedOutput)) {
    $resolvedOutput = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Logs\NetOps'
}
$resetDirectory = Join-Path -Path $resolvedOutput -ChildPath 'Resets'
if (-not (Test-Path -LiteralPath $resetDirectory)) {
    New-Item -ItemType Directory -Path $resetDirectory -Force | Out-Null
}

$timestamp = Get-Date
$timestampFragment = $timestamp.ToString('yyyyMMdd-HHmmss')
$entries = New-Object System.Collections.Generic.List[object]

foreach ($name in $EnvVarNames) {
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    $trimmed = $name.Trim()
    $previous = $null
    if (Test-Path -Path ("Env:{0}" -f $trimmed)) {
        $previous = (Get-Item -Path ("Env:{0}" -f $trimmed)).Value
    }

    [Environment]::SetEnvironmentVariable($trimmed, '0', 'Process')
    if (Test-Path -Path ("Env:{0}" -f $trimmed)) {
        Set-Item -Path ("Env:{0}" -f $trimmed) -Value '0'
    }

    $entries.Add([pscustomobject]@{
            Name          = $trimmed
            PreviousValue = $previous
            NewValue      = '0'
            WasDefined    = [bool]($previous)
        }) | Out-Null
}

$record = [pscustomobject]@{
    TimestampUtc = $timestamp.ToUniversalTime().ToString('o')
    User         = $env:USERNAME
    Machine      = $env:COMPUTERNAME
    Script       = 'Tools/Reset-OnlineModeFlags.ps1'
    Entries      = $entries
}

if ($Reason) {
    $record | Add-Member -NotePropertyName 'Reason' -NotePropertyValue $Reason.Trim() -Force
}

$logName = '{0}-{1}.json' -f $LogPrefix, $timestampFragment
$logPath = Join-Path -Path $resetDirectory -ChildPath $logName
$json = $record | ConvertTo-Json -Depth 4
Set-Content -LiteralPath $logPath -Value $json -Encoding utf8

if (-not $Quiet) {
    $reasonSuffix = ''
    if ($Reason) {
        $reasonSuffix = " (Reason: {0})" -f $Reason.Trim()
    }
    Write-Host ("Online-mode flags reset{0}. Log recorded at {1}" -f $reasonSuffix, $logPath) -ForegroundColor Green
}

if ($PassThru) {
    $record | Add-Member -NotePropertyName 'LogPath' -NotePropertyValue $logPath -Force
    return $record
}
