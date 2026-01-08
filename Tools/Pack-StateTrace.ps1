param(
    [string]$Version,
    [string]$Destination = 'dist',
    [switch]$VerifyContents,
    [switch]$FailOnMissing
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
$hash.Hash | Set-Content -Path $hashFile -Encoding UTF8

# ST-P-001: Generate package manifest with file hashes
Write-Host "Generating package manifest ..."

$manifestFiles = [System.Collections.Generic.List[pscustomobject]]::new()
$keyFiles = @(
    'Modules\DeviceLogParserModule.psm1',
    'Modules\InterfaceModule.psm1',
    'Modules\TelemetryModule.psm1',
    'Modules\FilterStateModule.psm1',
    'Modules\DeviceRepositoryModule.psm1',
    'Main\MainWindow.ps1',
    'Main\MainWindow.xaml',
    'Tools\Invoke-StateTracePipeline.ps1',
    'Tools\Invoke-AllChecks.ps1',
    'docs\README.md',
    'docs\CODEX_RUNBOOK.md'
)

$missingFiles = [System.Collections.Generic.List[string]]::new()
$hashedCount = 0

# Hash all files in build directory
Get-ChildItem -LiteralPath $buildDir -Recurse -File | ForEach-Object {
    $relPath = $_.FullName.Substring($buildDir.Length + 1)
    $fileHash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    [void]$manifestFiles.Add([pscustomobject]@{
        Path = $relPath
        Hash = $fileHash
        SizeBytes = $_.Length
    })
    $hashedCount++
}

# Verify key files are present
if ($VerifyContents.IsPresent -or $FailOnMissing.IsPresent) {
    foreach ($keyFile in $keyFiles) {
        $keyFilePath = Join-Path -Path $buildDir -ChildPath $keyFile
        if (-not (Test-Path -LiteralPath $keyFilePath)) {
            [void]$missingFiles.Add($keyFile)
            Write-Warning "Missing key file: $keyFile"
        }
    }
}

# Build manifest
$manifest = [pscustomobject]@{
    GeneratedAtUtc    = (Get-Date).ToUniversalTime().ToString('o')
    Version           = $Version
    PackageFile       = $zipName
    PackageHash       = $hash.Hash
    TotalFiles        = $hashedCount
    KeyFilesChecked   = $keyFiles.Count
    MissingKeyFiles   = $missingFiles
    Files             = $manifestFiles
}

$manifestPath = Join-Path -Path $distDir -ChildPath "StateTrace_$Version.manifest.json"
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8

Write-Host "Package manifest saved to $manifestPath"
Write-Host "Total files: $hashedCount"

if ($missingFiles.Count -gt 0) {
    Write-Host ("Missing key files: {0}" -f ($missingFiles -join ', ')) -ForegroundColor Yellow
    if ($FailOnMissing.IsPresent) {
        throw "Package verification failed: $($missingFiles.Count) key file(s) missing."
    }
}

Write-Host ""
Write-Host "Package created at $zipPath"
Write-Host "SHA-256: $($hash.Hash) (saved to $hashFile)"
