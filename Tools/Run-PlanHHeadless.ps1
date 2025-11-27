[CmdletBinding()]
param(
    [string]$TelemetryPath,
    [string[]]$Sites = @('WLLS','BOYO'),
    [string]$Timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss'),
    [switch]$Force
)

<#
.SYNOPSIS
Runs the full Plan H flow headlessly (telemetry, screenshots, bundle, report).

.DESCRIPTION
Invokes `Simulate-PlanHUIRun.ps1` to emit UserAction + freshness telemetry,
generate headless screenshots, publish a readiness-enforced bundle, and write
a Plan H report. Use when an interactive WPF session is unavailable.

.EXAMPLE
pwsh -NoLogo -File Tools\Run-PlanHHeadless.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$simulate = Join-Path $PSScriptRoot 'Simulate-PlanHUIRun.ps1'
if (-not (Test-Path -LiteralPath $simulate)) { throw "Simulate-PlanHUIRun.ps1 not found at $simulate" }

$env:PLANH_TIMESTAMP = $Timestamp

& $simulate -TelemetryPath $TelemetryPath -Sites $Sites -BundleName ("UI-{0}-planh-sim" -f (Get-Date -Format 'yyyyMMdd')) | Out-Null

Write-Host "[PlanH] Headless run complete (timestamp $Timestamp)." -ForegroundColor Green
