[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$TaskName = 'StateTraceVerification',

    [ValidatePattern('^\d{2}:\d{2}$')]
    [string]$StartTime = '03:00',

    [ValidateNotNullOrEmpty()]
    [string]$Schedule = 'DAILY',

    [ValidateNotNullOrEmpty()]
    [string]$RepoRoot = (Split-Path -Path $PSScriptRoot -Parent),

    [ValidateNotNullOrEmpty()]
    [string]$ScriptPath = 'Tools\Invoke-StateTraceScheduledVerification.ps1',

    [switch]$IncludeTests,
    [switch]$SkipParsing,
    [switch]$DisableSharedCacheSnapshot,
    [switch]$ShowSharedCacheSummary,
    [string]$SharedCacheSnapshotDirectory,

    [string]$AdditionalArguments,
    [switch]$Force,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$schtasks = Join-Path -Path $env:SystemRoot -ChildPath 'System32\schtasks.exe'
if (-not (Test-Path -LiteralPath $schtasks)) {
    throw "Unable to locate schtasks.exe at '$schtasks'."
}

$verificationScript = Join-Path -Path $RepoRoot -ChildPath $ScriptPath
if (-not (Test-Path -LiteralPath $verificationScript)) {
    throw "Unable to locate verification script at '$verificationScript'."
}

$verificationArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$verificationScript`"")
if ($IncludeTests) { $verificationArgs += '-IncludeTests' }
if ($SkipParsing) { $verificationArgs += '-SkipParsing' }
if ($DisableSharedCacheSnapshot) { $verificationArgs += '-DisableSharedCacheSnapshot' }
if ($ShowSharedCacheSummary) { $verificationArgs += '-ShowSharedCacheSummary' }
if ($SharedCacheSnapshotDirectory) {
    $verificationArgs += '-SharedCacheSnapshotDirectory'
    $verificationArgs += "`"$SharedCacheSnapshotDirectory`""
}
if ($AdditionalArguments) {
    $verificationArgs += $AdditionalArguments
}

$escapedCommand = $verificationArgs -join ' '
$taskCommand = "powershell.exe $escapedCommand"

$arguments = @('/Create','/SC',$Schedule,'/TN',$TaskName,'/TR',"`"$taskCommand`"",'/ST',$StartTime)
if ($Force) { $arguments += '/F' }

$commandPreview = "$schtasks " + ($arguments -join ' ')

if ($DryRun) {
    Write-Host '[DryRun] Scheduled task command:'
    Write-Host $commandPreview
    return $commandPreview
}

Write-Verbose "Registering scheduled task '$TaskName' at $StartTime."
$process = Start-Process -FilePath $schtasks -ArgumentList $arguments -NoNewWindow -Wait -PassThru
if ($process.ExitCode -ne 0) {
    throw "schtasks.exe exited with code $($process.ExitCode)."
}

Write-Host "Scheduled task '$TaskName' created to run at $StartTime (command: $taskCommand)."
