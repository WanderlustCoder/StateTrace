[CmdletBinding()]
param(
    [string]$ReadinessPath,
    [string]$ScreenshotDirectory = 'docs\performance\screenshots',
    [string]$OutputPath = 'docs\performance\PlanHReport-latest.md'
)

<#
.SYNOPSIS
Generates a quick Plan H evidence report (readiness + screenshots).

.DESCRIPTION
Reads a PlanH readiness JSON (auto-discovers latest under Logs\Reports if omitted),
lists screenshots from the screenshot directory, and writes a markdown summary for
use in plan/task updates.

.EXAMPLE
pwsh -NoLogo -File Tools\Generate-PlanHReport.ps1
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

if (-not $ReadinessPath) { $ReadinessPath = Get-LatestReadiness }
if (-not $ReadinessPath -or -not (Test-Path -LiteralPath $ReadinessPath)) {
    throw "Readiness file not found. Provide -ReadinessPath or ensure Logs\Reports\PlanHReadiness*.json exists."
}

$readiness = Get-Content -LiteralPath $ReadinessPath -Raw | ConvertFrom-Json -ErrorAction Stop
$screens = @()
if ($ScreenshotDirectory -and (Test-Path -LiteralPath $ScreenshotDirectory)) {
    $screens = Get-ChildItem -LiteralPath $ScreenshotDirectory -Filter 'onboarding-*.png' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 6 |
        ForEach-Object { $_.FullName }
}

$lines = @()
$lines += "# Plan H Evidence Summary"
$lines += ""
$lines += "- **Ready:** $($readiness.Ready)"
$lines += "- **Bundle:** $($readiness.BundlePath)"
$lines += "- **UserAction summary:** $($readiness.UserActionSummaryPath)"
$lines += "- **Freshness summary:** $($readiness.FreshnessSummaryPath)"
if ($readiness.Failures -and $readiness.Failures.Count -gt 0) {
    $lines += "- **Failures:** $([string]::Join('; ', $readiness.Failures))"
}
$lines += "- **Screenshots:**"
if ($screens.Count -gt 0) {
    foreach ($s in $screens) { $lines += ("  - {0}" -f $s) }
} else {
    $lines += "  - (none found)"
}
$lines += ""
$lines += "_Generated: $(Get-Date -Format 'u')_"

$dirOut = Split-Path -Path $OutputPath -Parent
if ($dirOut -and -not (Test-Path -LiteralPath $dirOut)) {
    New-Item -ItemType Directory -Path $dirOut -Force | Out-Null
}
[string]::Join([Environment]::NewLine, $lines) | Set-Content -LiteralPath $OutputPath -Encoding UTF8

Write-Host ("[PlanH] Report written to {0}" -f (Resolve-Path -LiteralPath $OutputPath).ProviderPath) -ForegroundColor Green
