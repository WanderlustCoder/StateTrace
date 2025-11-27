[CmdletBinding()]
param(
    [string]$BundlePath,
    [string]$ReadinessPath
)

<#
.SYNOPSIS
Displays Plan H readiness results.

.DESCRIPTION
Reads a PlanH readiness JSON (from a bundle or a standalone summary) and prints the
Ready state plus key paths. If no paths are supplied, the script looks for the latest
PlanHReadiness*.json under Logs/Reports.

.EXAMPLE
pwsh -NoLogo -File Tools\Show-PlanHReadiness.ps1 -BundlePath Logs\TelemetryBundles\UI-20251126-useraction9
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LatestReadiness {
    $dir = Join-Path (Resolve-Path '.').Path 'Logs\Reports'
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    return Get-ChildItem -LiteralPath $dir -Filter 'PlanHReadiness*.json' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 |
        ForEach-Object { $_.FullName }
}

if ($BundlePath -and -not $ReadinessPath) {
    $resolvedBundle = Resolve-Path -LiteralPath $BundlePath -ErrorAction Stop
    $bundleDir = $resolvedBundle.ProviderPath
    $readinessCandidate = Get-ChildItem -LiteralPath $bundleDir -Filter 'PlanHReadiness*.json' -Recurse -File | Select-Object -First 1
    if ($readinessCandidate) { $ReadinessPath = $readinessCandidate.FullName }
}

if (-not $ReadinessPath) {
    $ReadinessPath = Get-LatestReadiness
}

if (-not $ReadinessPath) {
    throw "No PlanH readiness file found. Provide -ReadinessPath or -BundlePath."
}

$resolvedPath = Resolve-Path -LiteralPath $ReadinessPath -ErrorAction Stop
$data = Get-Content -LiteralPath $resolvedPath -Raw | ConvertFrom-Json -ErrorAction Stop

Write-Host ("[PlanH] Ready: {0}" -f $data.Ready) -ForegroundColor (if ($data.Ready) { 'Green' } else { 'Yellow' })
Write-Host ("[PlanH] Bundle: {0}" -f $data.BundlePath)
Write-Host ("[PlanH] UserAction summary: {0}" -f $data.UserActionSummaryPath)
Write-Host ("[PlanH] Freshness summary: {0}" -f $data.FreshnessSummaryPath)
if ($data.Failures -and $data.Failures.Count -gt 0) {
    Write-Host "[PlanH] Failures:" -ForegroundColor Yellow
    foreach ($f in $data.Failures) { Write-Host (" - {0}" -f $f) }
}

return $data
