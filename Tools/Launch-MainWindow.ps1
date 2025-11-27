[CmdletBinding()]
param(
    [string]$WorkingDirectory = (Split-Path -Parent $PSScriptRoot),
    [switch]$NoExit
)

<#
.SYNOPSIS
Launches the WPF UI in an interactive PowerShell (detached from CLI timeouts).

.DESCRIPTION
Starts `Main\MainWindow.ps1` in a new `powershell.exe` process with `-STA`
and an optional `-NoExit` so the window remains open even if the caller exits.
Use this when running inside a CLI that imposes execution timeouts; the new
process is detached so the UI can stay open for manual interaction.

.EXAMPLE
pwsh -NoLogo -File Tools\Launch-MainWindow.ps1 -NoExit
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$mainPath = Join-Path $WorkingDirectory 'Main\MainWindow.ps1'
if (-not (Test-Path -LiteralPath $mainPath)) {
    throw "Main window script not found at $mainPath"
}

$argsList = @('-NoLogo','-Sta','-File',"`"$mainPath`"")
if ($NoExit) { $argsList = @('-NoLogo','-NoExit','-Sta','-File',"`"$mainPath`"") }

Write-Host ("[PlanH] Launching interactive UI: {0}" -f $mainPath) -ForegroundColor Cyan
Start-Process -FilePath 'powershell.exe' -ArgumentList $argsList -WorkingDirectory $WorkingDirectory -WindowStyle Normal
