[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$TaskName = 'StateTraceDailyRollup',

    [ValidatePattern('^\d{2}:\d{2}$')]
    [string]$StartTime = '02:00',

    [ValidateNotNullOrEmpty()]
    [string]$Days = 'DAILY',

    [ValidateNotNullOrEmpty()]
    [string]$RepoRoot = (Split-Path -Path $PSScriptRoot -Parent),

    [ValidateNotNullOrEmpty()]
    [string]$ScriptPath = 'Tools\Invoke-DailyRollupScheduled.ps1',

    [string]$MetricsDirectory,
    [string]$OutputDirectory,

    [int]$DaysBack = 1,

    [switch]$IncludePerSite = $true,
    [switch]$IncludeSiteCache = $true,

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

$rollupScript = Join-Path -Path $RepoRoot -ChildPath $ScriptPath
if (-not (Test-Path -LiteralPath $rollupScript)) {
    throw "Unable to locate rollup script at '$rollupScript'."
}

$rollupArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$rollupScript`"",'-Days', $DaysBack)
if ($IncludePerSite) { $rollupArgs += '-IncludePerSite' }
if ($IncludeSiteCache) { $rollupArgs += '-IncludeSiteCache' }

if ($MetricsDirectory) {
    $rollupArgs += '-MetricsDirectory'
    $rollupArgs += "`"$MetricsDirectory`""
}
if ($OutputDirectory) {
    $rollupArgs += '-OutputDirectory'
    $rollupArgs += "`"$OutputDirectory`""
}
if ($AdditionalArguments) {
    $rollupArgs += $AdditionalArguments
}

$escapedCommand = $rollupArgs -join ' '
$taskCommand = "powershell.exe $escapedCommand"

$arguments = @('/Create','/SC','DAILY','/TN',$TaskName,'/TR',"`"$taskCommand`"",'/ST',$StartTime)
if ($Force) { $arguments += '/F' }

$commandPreview = "$schtasks " + ($arguments -join ' ')

if ($DryRun) {
    Write-Host '[DryRun] Scheduled task command:'
    Write-Host $commandPreview
    return
}

Write-Verbose "Registering scheduled task '$TaskName' at $StartTime."
$process = Start-Process -FilePath $schtasks -ArgumentList $arguments -NoNewWindow -Wait -PassThru
if ($process.ExitCode -ne 0) {
    throw "schtasks.exe exited with code $($process.ExitCode)."
}

Write-Host "Scheduled task '$TaskName' created to run at $StartTime (command: $taskCommand)."
