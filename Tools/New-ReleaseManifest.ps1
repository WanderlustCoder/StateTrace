<#
.SYNOPSIS
Creates a release manifest with version stamping and changelog generation.

.DESCRIPTION
ST-P-003: Stamps package/build version into a manifest and generates release notes
that reference telemetry bundle paths and package hashes.

.PARAMETER Version
Semantic version string (e.g., 1.2.0, 2.0.0-beta.1).

.PARAMETER TelemetryBundlePath
Path to telemetry bundle to reference in release notes.

.PARAMETER PackagePath
Path to package file to calculate hash for.

.PARAMETER ChangelogEntries
Array of changelog entries for this release.

.PARAMETER OutputPath
Path to write the release manifest. Defaults to dist/ReleaseManifest-<version>.json.

.PARAMETER ReleaseNotesPath
Path to write release notes markdown. Defaults to dist/RELEASE_NOTES-<version>.md.

.PARAMETER RepositoryRoot
Repository root path. Defaults to parent of script directory.

.PARAMETER GitCommit
Git commit SHA for this release. Auto-detected if not specified.

.PARAMETER PassThru
Return the manifest as an object.
#>
param(
    [Parameter(Mandatory)][string]$Version,
    [string]$TelemetryBundlePath,
    [string]$PackagePath,
    [string[]]$ChangelogEntries = @(),
    [string]$OutputPath,
    [string]$ReleaseNotesPath,
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$GitCommit,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

Write-Host ("Creating release manifest for version {0}..." -f $Version) -ForegroundColor Cyan

# Auto-detect git commit if not provided
if (-not $GitCommit) {
    try {
        $GitCommit = (git -C $repoRoot rev-parse HEAD 2>$null).Trim()
    } catch {
        $GitCommit = 'unknown'
    }
}

# Calculate package hash if path provided
$packageHash = $null
$packageSize = $null
if ($PackagePath -and (Test-Path -LiteralPath $PackagePath)) {
    $hashResult = Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256
    $packageHash = $hashResult.Hash
    $packageSize = (Get-Item -LiteralPath $PackagePath).Length
    Write-Host ("  Package hash: {0}" -f $packageHash.Substring(0, 16) + "...") -ForegroundColor Cyan
}

# Resolve telemetry bundle info
$bundleInfo = $null
if ($TelemetryBundlePath -and (Test-Path -LiteralPath $TelemetryBundlePath)) {
    $bundleManifest = Join-Path $TelemetryBundlePath 'TelemetryBundle.json'
    if (Test-Path -LiteralPath $bundleManifest) {
        try {
            $bundleData = Get-Content -LiteralPath $bundleManifest -Raw | ConvertFrom-Json
            $bundleInfo = [pscustomobject]@{
                Path      = $TelemetryBundlePath
                Name      = if ($bundleData.BundleName) { $bundleData.BundleName } else { Split-Path -Leaf $TelemetryBundlePath }
                Created   = if ($bundleData.CreatedUtc) { $bundleData.CreatedUtc } else { $null }
                FileCount = if ($bundleData.FileCount) { $bundleData.FileCount } else { 0 }
            }
        } catch {
            $bundleInfo = [pscustomobject]@{
                Path = $TelemetryBundlePath
                Name = Split-Path -Leaf $TelemetryBundlePath
            }
        }
    }
}

# Build manifest
$manifest = [pscustomobject]@{
    Version          = $Version
    BuildDate        = Get-Date -Format 'o'
    GitCommit        = $GitCommit
    GitBranch        = (git -C $repoRoot rev-parse --abbrev-ref HEAD 2>$null)
    Package          = if ($PackagePath) {
        [pscustomobject]@{
            Path   = $PackagePath
            Hash   = $packageHash
            Size   = $packageSize
        }
    } else { $null }
    TelemetryBundle  = $bundleInfo
    ChangelogEntries = $ChangelogEntries
    Environment      = [pscustomobject]@{
        MachineName    = $env:COMPUTERNAME
        UserName       = $env:USERNAME
        PSVersion      = $PSVersionTable.PSVersion.ToString()
    }
}

# Determine output paths
$distDir = Join-Path $repoRoot 'dist'
if (-not (Test-Path -LiteralPath $distDir)) {
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
}

if (-not $OutputPath) {
    $OutputPath = Join-Path $distDir ("ReleaseManifest-{0}.json" -f $Version)
}

if (-not $ReleaseNotesPath) {
    $ReleaseNotesPath = Join-Path $distDir ("RELEASE_NOTES-{0}.md" -f $Version)
}

# Write manifest
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host ("Manifest written to: {0}" -f $OutputPath) -ForegroundColor Green

# Generate release notes
$changelogSection = if ($ChangelogEntries.Count -gt 0) {
    ($ChangelogEntries | ForEach-Object { "- $_" }) -join "`n"
} else {
    "- See commit history for changes"
}

$bundleSection = if ($bundleInfo) {
    @"
## Telemetry Bundle

- **Bundle:** $($bundleInfo.Name)
- **Path:** ``$($bundleInfo.Path)``
$(if ($bundleInfo.Created) { "- **Created:** $($bundleInfo.Created)" })
$(if ($bundleInfo.FileCount) { "- **Files:** $($bundleInfo.FileCount)" })
"@
} else {
    ""
}

$packageSection = if ($packageHash) {
    @"
## Package Verification

- **File:** ``$(Split-Path -Leaf $PackagePath)``
- **SHA-256:** ``$packageHash``
- **Size:** $([math]::Round($packageSize / 1KB, 2)) KB
"@
} else {
    ""
}

$releaseNotes = @"
# StateTrace $Version Release Notes

**Release Date:** $(Get-Date -Format 'yyyy-MM-dd')
**Git Commit:** ``$GitCommit``

## Changes

$changelogSection
$bundleSection
$packageSection

## Installation

1. Extract the package to your desired location
2. Run ``Tools\Bootstrap-DevSeat.ps1 -ValidateOnly`` to verify prerequisites
3. Import modules: ``Import-Module .\Modules\DeviceRepositoryModule.psm1``

## Verification

After installation, run the following to verify:
``````powershell
pwsh -File Tools\Invoke-AllChecks.ps1 -SkipSpanHarness -SkipSearchAlertsHarness
``````

---
*Generated by Tools/New-ReleaseManifest.ps1 (ST-P-003)*
"@

Set-Content -LiteralPath $ReleaseNotesPath -Value $releaseNotes -Encoding UTF8
Write-Host ("Release notes written to: {0}" -f $ReleaseNotesPath) -ForegroundColor Green

Write-Host "`nRelease Manifest Summary:" -ForegroundColor Cyan
Write-Host ("  Version: {0}" -f $manifest.Version)
Write-Host ("  Commit: {0}" -f $manifest.GitCommit.Substring(0, [math]::Min(8, $manifest.GitCommit.Length)))
Write-Host ("  Changes: {0}" -f $ChangelogEntries.Count)
if ($packageHash) {
    Write-Host ("  Package hash: {0}..." -f $packageHash.Substring(0, 16))
}

if ($PassThru) {
    return $manifest
}
