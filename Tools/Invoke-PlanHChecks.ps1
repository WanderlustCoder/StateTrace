[CmdletBinding()]
param(
    [string]$BundlePath,
    [string]$ReportPath = 'docs\performance\PlanHReport-latest.md',
    [switch]$FailOnNotReady
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$readinessScript = Join-Path $PSScriptRoot 'Test-PlanHReadiness.ps1'
$reportScript = Join-Path $PSScriptRoot 'Generate-PlanHReport.ps1'

if (-not (Test-Path -LiteralPath $readinessScript)) { throw "Test-PlanHReadiness.ps1 not found at '$readinessScript'." }
if (-not (Test-Path -LiteralPath $reportScript)) { throw "Generate-PlanHReport.ps1 not found at '$reportScript'." }

function Get-LatestBundle {
    $root = Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'Logs\TelemetryBundles'
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    return Get-ChildItem -LiteralPath $root -Directory |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 |
        ForEach-Object { $_.FullName }
}

if (-not $BundlePath) { $BundlePath = Get-LatestBundle }
if (-not $BundlePath -or -not (Test-Path -LiteralPath $BundlePath)) {
    throw "Bundle not found. Provide -BundlePath or ensure Logs\TelemetryBundles has entries."
}

$readiness = & $readinessScript -BundlePath $BundlePath -PassThru
if (-not $readiness.Ready -and $FailOnNotReady) {
    throw "Plan H readiness failed for bundle '$($readiness.BundlePath)': $([string]::Join('; ', $readiness.Failures))"
}

$readinessFile = $null
if ($readiness.BundlePath -and (Test-Path -LiteralPath $readiness.BundlePath)) {
    $candidate = Get-ChildItem -LiteralPath $readiness.BundlePath -Filter 'PlanHReadiness*.json' -Recurse -File | Select-Object -First 1
    if ($candidate) { $readinessFile = $candidate.FullName }
}
if (-not $readinessFile) {
    Write-Warning "PlanHReadiness file not found; skipping report generation."
    if ($FailOnNotReady) { throw "Plan H readiness file missing." }
    return $readiness
}

& $reportScript -ReadinessPath $readinessFile -OutputPath $ReportPath | Out-Null
return $readiness
