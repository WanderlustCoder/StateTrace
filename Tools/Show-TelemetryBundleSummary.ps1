[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BundlePath,

    [string]$SummaryPath,

    [switch]$PassThru
)

<#
.SYNOPSIS
Displays the README hash and requirement status recorded in a telemetry bundle verification summary.

.DESCRIPTION
`Tools\Test-TelemetryBundleReadiness.ps1` can emit a `VerificationSummary.json` file that captures the
README hash plus the per-requirement status for each telemetry bundle area. This helper loads that
summary (defaulting to `<bundle>/VerificationSummary.json`) and prints concise tables so operators can
reference the hashes and requirement status without re-running the readiness script. Use `-PassThru`
to return the parsed summary to callers/automation.

.EXAMPLE
pwsh Tools\Show-TelemetryBundleSummary.ps1 -BundlePath Logs\TelemetryBundles\Release-20251113

.EXAMPLE
pwsh Tools\Show-TelemetryBundleSummary.ps1 `
    -BundlePath Logs\TelemetryBundles\Release-20251113 `
    -SummaryPath Logs\TelemetryBundles\Release-20251113\VerificationSummary.json `
    -PassThru
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolingJsonPath = Join-Path -Path $PSScriptRoot -ChildPath 'ToolingJson.psm1'
if (Test-Path -LiteralPath $toolingJsonPath) {
    Import-Module -Name $toolingJsonPath -Force
} else {
    throw "ToolingJson module not found at '$toolingJsonPath'."
}

function Resolve-SummaryPath {
    param(
        [string]$BundlePath,
        [string]$SummaryPath
    )

    $bundleResolved = Resolve-Path -LiteralPath $BundlePath -ErrorAction Stop | Select-Object -First 1
    $bundlePathValue = $bundleResolved.Path
    if (-not [string]::IsNullOrWhiteSpace($SummaryPath)) {
        $resolvedSummary = Resolve-Path -LiteralPath $SummaryPath -ErrorAction Stop | Select-Object -First 1
        return $resolvedSummary.Path
    }

    $candidates = @(
        (Join-Path -Path $bundlePathValue -ChildPath 'VerificationSummary.json')
        (Join-Path -Path $bundlePathValue -ChildPath 'Telemetry\VerificationSummary.json')
        (Join-Path -Path $bundlePathValue -ChildPath 'Routing\VerificationSummary.json')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop | Select-Object -First 1).Path
        }
    }

    throw "Unable to locate VerificationSummary.json under '$bundlePathValue'. Supply -SummaryPath to point at the summary file."
}

$resolvedBundle = Resolve-Path -LiteralPath $BundlePath -ErrorAction Stop | Select-Object -First 1
$resolvedBundlePath = $resolvedBundle.Path
$resolvedSummaryPath = Resolve-SummaryPath -BundlePath $resolvedBundlePath -SummaryPath $SummaryPath

Write-Host ("Using verification summary: {0}" -f $resolvedSummaryPath) -ForegroundColor DarkCyan

$summaryObjects = Read-ToolingJson -Path $resolvedSummaryPath -Label 'Telemetry bundle summary'
if (-not $summaryObjects) {
    throw "Summary file '$resolvedSummaryPath' did not contain any entries."
}

$areas = @()
if ($summaryObjects -is [System.Array]) {
    $areas = @($summaryObjects)
}
else {
    $areas = @($summaryObjects)
}

$hashRows = $areas | ForEach-Object {
    [pscustomobject]@{
        Area          = $_.Area
        BundlePath    = $_.BundlePath
        ManifestPath  = $_.ManifestPath
        ReadmePath    = $_.ReadmePath
        HashAlgorithm = $_.HashAlgorithm
        ReadmeHash    = $_.ReadmeHash
    }
}

if (-not $hashRows -or $hashRows.Count -eq 0) {
    Write-Warning 'Verification summary did not include README hash metadata.'
}
else {
    Write-Host "`nREADME hashes:" -ForegroundColor Cyan
    $hashRows | Format-Table Area, HashAlgorithm, ReadmeHash, ReadmePath -AutoSize
}

$requirementRows = @()
foreach ($area in $areas) {
    if (-not $area.RequirementState) { continue }
    foreach ($requirement in $area.RequirementState) {
        $requirementRows += [pscustomobject]@{
            Area        = $area.Area
            Requirement = $requirement.Requirement
            Status      = $requirement.Status
            Files       = $requirement.Files
        }
    }
}

if ($requirementRows.Count -gt 0) {
    Write-Host "`nRequirement status:" -ForegroundColor Cyan
    $requirementRows | Format-Table Area, Requirement, Status, Files -AutoSize
}
else {
    Write-Warning 'Verification summary did not include requirement status entries.'
}

if ($PassThru) {
    return $areas
}
