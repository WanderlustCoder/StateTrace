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

$root = Split-Path -Parent $PSScriptRoot
$distDir = if ([System.IO.Path]::IsPathRooted($Destination)) {
    [System.IO.Path]::GetFullPath($Destination)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $root $Destination))
}
if (-not (Test-Path -LiteralPath $distDir)) {
    $null = New-Item -ItemType Directory -Path $distDir -Force
}

function Assert-SafeRemovalPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $resolvedPath.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove '$resolvedPath' because it is outside '$resolvedRoot'."
    }
    if ([System.StringComparer]::OrdinalIgnoreCase.Equals($resolvedPath, $resolvedRoot)) {
        throw "Refusing to remove root path '$resolvedRoot'."
    }
    return $resolvedPath
}

$buildDir = Join-Path $distDir 'build'
if (Test-Path -LiteralPath $buildDir) {
    $safeBuildDir = Assert-SafeRemovalPath -Path $buildDir -Root $distDir
    Remove-Item -LiteralPath $safeBuildDir -Recurse -Force
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
Copy-Content -Source (Join-Path $root 'Modules')    -Target (Join-Path $buildDir 'Modules')
Copy-Content -Source (Join-Path $root 'Views')      -Target (Join-Path $buildDir 'Views')
Copy-Content -Source (Join-Path $root 'Tools')      -Target (Join-Path $buildDir 'Tools')
Copy-Content -Source (Join-Path $root 'docs')       -Target (Join-Path $buildDir 'docs')
Copy-Content -Source (Join-Path $root 'Data')       -Target (Join-Path $buildDir 'Data')

# Exclude logs and backups
$logsPath = Join-Path $buildDir 'Logs'
if (Test-Path -LiteralPath $logsPath) {
    $safeLogsPath = Assert-SafeRemovalPath -Path $logsPath -Root $buildDir
    Remove-Item -LiteralPath $safeLogsPath -Recurse -Force -ErrorAction SilentlyContinue
}
$backupsPath = Join-Path $buildDir 'Data\Backups'
if (Test-Path -LiteralPath $backupsPath) {
    $safeBackupsPath = Assert-SafeRemovalPath -Path $backupsPath -Root $buildDir
    Remove-Item -LiteralPath $safeBackupsPath -Recurse -Force -ErrorAction SilentlyContinue
}

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
