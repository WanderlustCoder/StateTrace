[CmdletBinding()]
param(
    [string]$BundlePath,
    [switch]$FailOnNotReady
)

<#
.SYNOPSIS
Checks the latest Plan H readiness state.

.DESCRIPTION
Finds the latest telemetry bundle (or uses the supplied -BundlePath) and runs
Tools\Test-PlanHReadiness.ps1. Prints readiness status and paths; optionally fails
when not ready (CI-friendly).

.EXAMPLE
pwsh -NoLogo -File Tools\Check-PlanHStatus.ps1 -BundlePath Logs\TelemetryBundles\UI-20251126-useraction9 -FailOnNotReady
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LatestBundle {
    $root = Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'Logs\TelemetryBundles'
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    return Get-ChildItem -LiteralPath $root -Directory |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 |
        ForEach-Object { $_.FullName }
}

if (-not $BundlePath) {
    $BundlePath = Get-LatestBundle
}

if (-not $BundlePath -or -not (Test-Path -LiteralPath $BundlePath)) {
    throw "Bundle not found. Provide -BundlePath or ensure Logs\TelemetryBundles has entries."
}

$planHScript = Join-Path $PSScriptRoot 'Test-PlanHReadiness.ps1'
if (-not (Test-Path -LiteralPath $planHScript)) {
    throw "Test-PlanHReadiness.ps1 not found at '$planHScript'."
}

$result = & $planHScript -BundlePath $BundlePath -PassThru

Write-Host ("[PlanH] Ready: {0}" -f $result.Ready) -ForegroundColor (if ($result.Ready) { 'Green' } else { 'Yellow' })
Write-Host ("[PlanH] Bundle: {0}" -f $result.BundlePath)
Write-Host ("[PlanH] UserAction summary: {0}" -f $result.UserActionSummaryPath)
Write-Host ("[PlanH] Freshness summary: {0}" -f $result.FreshnessSummaryPath)
if ($result.Failures -and $result.Failures.Count -gt 0) {
    Write-Host "[PlanH] Failures:" -ForegroundColor Yellow
    foreach ($f in $result.Failures) { Write-Host (" - {0}" -f $f) }
}

if ($FailOnNotReady -and -not $result.Ready) {
    throw "Plan H readiness failed for bundle '$($result.BundlePath)'."
}

if ($PassThru) { return $result }
