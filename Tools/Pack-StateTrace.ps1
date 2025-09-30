param(
    [string]$Version,
    [string]$Destination = 'dist'
)

<#
.SYNOPSIS
    Build and package StateTrace for distribution.
.DESCRIPTION
    This script creates a self‑contained zip archive of the StateTrace tool.  It collects modules, views, tools and documentation, embeds the specified version number and produces a SHA‑256 checksum.  Run this script from the repository root when preparing a release.
    Example:
        ./Tools/Pack-StateTrace.ps1 -Version 1.2.0
.NOTES
    Requires PowerShell 5.x.  Ensure unit and smoke tests have passed before packaging.
#>

if (-not $Version) {
    throw 'You must supply a semantic version via -Version.'
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$distDir = Resolve-Path -Path $Destination
if (-not (Test-Path -LiteralPath $distDir)) {
    $null = New-Item -ItemType Directory -Path $distDir -Force
}

$buildDir = Join-Path $distDir 'build'
if (Test-Path -LiteralPath $buildDir) {
    Remove-Item -LiteralPath $buildDir -Recurse -Force
}
$null = New-Item -ItemType Directory -Path $buildDir

Write-Host "Building StateTrace version $Version ..."

function Copy-Content {
    param(
        [string]$Source,
        [string]$Target
    )
    Get-ChildItem -LiteralPath $Source -Recurse | ForEach-Object {
        $dest = $_.FullName.Replace($Source, $Target)
        if ($_.PsIsContainer) {
            if (-not (Test-Path -LiteralPath $dest)) {
                $null = New-Item -ItemType Directory -Path $dest -Force
            }
        } else {
            $dir = Split-Path -Parent $dest
            if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
            Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
        }
    }
}

# Copy core components
$root = Split-Path -Parent $PSScriptRoot
Copy-Content -Source (Join-Path $root 'Modules')    -Target (Join-Path $buildDir 'Modules')
Copy-Content -Source (Join-Path $root 'Views')      -Target (Join-Path $buildDir 'Views')
Copy-Content -Source (Join-Path $root 'Tools')      -Target (Join-Path $buildDir 'Tools')
Copy-Content -Source (Join-Path $root 'docs')       -Target (Join-Path $buildDir 'docs')
Copy-Content -Source (Join-Path $root 'Data')       -Target (Join-Path $buildDir 'Data')

# Exclude logs and backups
Remove-Item -Path (Join-Path $buildDir 'Logs') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $buildDir 'Data\Backups') -Recurse -Force -ErrorAction SilentlyContinue

# Write version file
$versionFile = Join-Path $buildDir 'VERSION.txt'
$Version | Set-Content -Path $versionFile -Encoding UTF8

# Create archive
$zipName = "StateTrace_$Version.zip"
$zipPath = Join-Path $distDir $zipName
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $buildDir '*') -DestinationPath $zipPath

# Compute hash
$hash = Get-FileHash -Algorithm SHA256 -Path $zipPath
$hashFile = "$zipPath.sha256"
$hash.Hash | Set-Content -Path $hashFile -Encoding ASCII

Write-Host "Package created at $zipPath"
Write-Host "SHA-256: $($hash.Hash) (saved to $hashFile)"