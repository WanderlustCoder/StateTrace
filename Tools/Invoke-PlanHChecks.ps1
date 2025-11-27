[CmdletBinding()]
param(
    [string]$BundlePath,
    [string]$ReadinessPath,
    [string]$ReportPath = 'docs\performance\PlanHReport-latest.md',
    [switch]$FailOnNotReady
)

<#
.SYNOPSIS
Runs Plan H readiness on a bundle and emits a markdown report.

.DESCRIPTION
Calls Tools\Check-PlanHStatus.ps1 (wraps Test-PlanHReadiness.ps1) against the supplied bundle
or the latest bundle under Logs\TelemetryBundles. If ready, writes a markdown summary via
Tools\Generate-PlanHReport.ps1 using the discovered readiness file and screenshot list.

.EXAMPLE
pwsh -NoLogo -File Tools\Invoke-PlanHChecks.ps1 -BundlePath Logs\TelemetryBundles\UI-20251126-useraction9
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$checkScript = Join-Path $PSScriptRoot 'Check-PlanHStatus.ps1'
$reportScript = Join-Path $PSScriptRoot 'Generate-PlanHReport.ps1'

if (-not (Test-Path -LiteralPath $checkScript)) { throw "Check-PlanHStatus.ps1 not found at '$checkScript'." }
if (-not (Test-Path -LiteralPath $reportScript)) { throw "Generate-PlanHReport.ps1 not found at '$reportScript'." }

$checkParams = @{
    BundlePath      = $BundlePath
    FailOnNotReady  = $FailOnNotReady
    PassThru        = $true
}
$status = & $checkScript @checkParams

$resolvedReadiness = $ReadinessPath
if (-not $resolvedReadiness) {
    if ($status.BundlePath -and (Test-Path -LiteralPath $status.BundlePath)) {
        $candidate = Get-ChildItem -LiteralPath $status.BundlePath -Filter 'PlanHReadiness*.json' -Recurse -File | Select-Object -First 1
        if ($candidate) { $resolvedReadiness = $candidate.FullName }
    }
}

if (-not $resolvedReadiness -and $status.UserActionSummaryPath) {
    # Try to locate readiness near the summaries
    $bundleDir = Split-Path -Parent $status.UserActionSummaryPath
    $candidate = Get-ChildItem -LiteralPath $bundleDir -Filter 'PlanHReadiness*.json' -File | Select-Object -First 1
    if ($candidate) { $resolvedReadiness = $candidate.FullName }
}

if (-not $resolvedReadiness) {
    Write-Warning "PlanHReadiness file not found; skipping report generation."
    if ($FailOnNotReady) { throw "Plan H readiness file missing." }
    return $status
}

& $reportScript -ReadinessPath $resolvedReadiness -OutputPath $ReportPath | Out-Null
return $status
