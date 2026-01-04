[CmdletBinding()]
param(
    [string]$RunId,

    [int]$RetainDays = 7,

    [switch]$SkipCleanup,

    [switch]$SkipBundle,

    [string]$BundleName,

    [string[]]$PlanReferences = @('PlanK', 'PlanE', 'PlanG'),

    [string[]]$TaskBoardIds,

    [string]$Notes,

    [string]$OutputPath,

    [switch]$WhatIf,

    [switch]$PassThru
)

<#
.SYNOPSIS
Cleans up stale artifacts and bundles CI results (ST-K-003).

.DESCRIPTION
Artifact hygiene script that:
1. Removes stale artifacts older than -RetainDays from Logs/ subdirectories
2. Bundles fresh CI artifacts via Publish-TelemetryBundle.ps1

Run this after CI harness completes to package telemetry, shared-cache
analyzers, diff hotspots, and warm-run results.

.PARAMETER RunId
Optional run ID for organizing artifacts. Defaults to timestamp.

.PARAMETER RetainDays
Number of days to retain old artifacts. Defaults to 7.

.PARAMETER SkipCleanup
Skip the cleanup phase and only bundle.

.PARAMETER SkipBundle
Skip the bundle phase and only cleanup.

.PARAMETER BundleName
Custom bundle name. Defaults to CI-<RunId>.

.PARAMETER PlanReferences
Plan references to include in bundle. Defaults to PlanK, PlanE, PlanG.

.PARAMETER TaskBoardIds
Task board IDs to reference in bundle.

.PARAMETER Notes
Notes to include in the bundle.

.PARAMETER OutputPath
Path to save the cleanup/bundle report. Defaults to Logs/CI/<RunId>/ArtifactHygiene.json.

.PARAMETER WhatIf
Preview cleanup actions without deleting files.

.PARAMETER PassThru
Return the result object.

.EXAMPLE
pwsh Tools\Clean-ArtifactsAndBundle.ps1 -RunId CI-20260104 -Notes "Post-smoke bundle"

.EXAMPLE
pwsh Tools\Clean-ArtifactsAndBundle.ps1 -SkipCleanup -BundleName Release-20260104
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "CI-$timestamp"
}

if ([string]::IsNullOrWhiteSpace($BundleName)) {
    $BundleName = $RunId
}

# Directories to clean
$cleanupTargets = @(
    @{ Path = 'Logs\IngestionMetrics'; Pattern = '*.json'; Description = 'Ingestion metrics' }
    @{ Path = 'Logs\Reports'; Pattern = '*.json'; Description = 'Reports' }
    @{ Path = 'Logs\SharedCacheSnapshot'; Pattern = '*.clixml'; Description = 'Cache snapshots' }
    @{ Path = 'Logs\Verification'; Pattern = '*.log'; Description = 'Verification logs' }
    @{ Path = 'Logs\Verification'; Pattern = '*.json'; Description = 'Verification reports' }
    @{ Path = 'Logs\DispatchHarness'; Pattern = '*.json'; Description = 'Dispatch harness' }
    @{ Path = 'Logs\TelemetryBundles'; Pattern = '*'; Description = 'Old bundles'; IsDirectory = $true }
    @{ Path = 'Logs\Accessibility'; Pattern = '*.json'; Description = 'Accessibility reports' }
    @{ Path = 'Logs\Drills'; Pattern = '*.json'; Description = 'Drill results' }
)

# Initialize result
$result = [pscustomobject]@{
    GeneratedAtUtc       = (Get-Date).ToUniversalTime().ToString('o')
    RunId                = $RunId
    RetainDays           = $RetainDays
    CleanupSkipped       = $SkipCleanup.IsPresent
    BundleSkipped        = $SkipBundle.IsPresent
    FilesDeleted         = 0
    BytesReclaimed       = 0
    DirectoriesDeleted   = 0
    CleanupDetails       = @()
    BundlePath           = $null
    BundleResult         = $null
    Status               = 'Unknown'
    Message              = ''
}

Write-Host "`n=== Artifact Hygiene & Bundling (ST-K-003) ===" -ForegroundColor Cyan
Write-Host ("Run ID: {0}" -f $RunId) -ForegroundColor DarkGray
Write-Host ("Retain days: {0}" -f $RetainDays) -ForegroundColor DarkGray
if ($WhatIf.IsPresent) {
    Write-Host "[WhatIf mode - no changes will be made]" -ForegroundColor Yellow
}
Write-Host ""

$cutoffDate = (Get-Date).AddDays(-$RetainDays)

# Phase 1: Cleanup
if (-not $SkipCleanup.IsPresent) {
    Write-Host "--- Phase 1: Cleanup Stale Artifacts ---" -ForegroundColor Yellow
    Write-Host ("  Cutoff date: {0:yyyy-MM-dd}" -f $cutoffDate) -ForegroundColor DarkGray

    foreach ($target in $cleanupTargets) {
        $targetPath = Join-Path -Path $repositoryRoot -ChildPath $target.Path

        if (-not (Test-Path -LiteralPath $targetPath)) {
            continue
        }

        $isDirectory = if ($target.ContainsKey('IsDirectory')) { $target.IsDirectory } else { $false }

        if ($isDirectory) {
            # Clean old directories (e.g., telemetry bundles)
            $oldDirs = Get-ChildItem -LiteralPath $targetPath -Directory |
                Where-Object { $_.LastWriteTime -lt $cutoffDate }

            foreach ($dir in $oldDirs) {
                $result.CleanupDetails += [pscustomobject]@{
                    Type = 'Directory'
                    Path = $dir.FullName
                    Age = [math]::Round(((Get-Date) - $dir.LastWriteTime).TotalDays, 1)
                }
                $result.DirectoriesDeleted++

                if (-not $WhatIf.IsPresent) {
                    Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
                Write-Host ("    Removed dir: {0} ({1:N0} days old)" -f $dir.Name, ((Get-Date) - $dir.LastWriteTime).TotalDays) -ForegroundColor DarkGray
            }
        } else {
            # Clean old files
            $oldFiles = Get-ChildItem -LiteralPath $targetPath -Filter $target.Pattern -File |
                Where-Object { $_.LastWriteTime -lt $cutoffDate }

            foreach ($file in $oldFiles) {
                $result.CleanupDetails += [pscustomobject]@{
                    Type = 'File'
                    Path = $file.FullName
                    SizeBytes = $file.Length
                    Age = [math]::Round(((Get-Date) - $file.LastWriteTime).TotalDays, 1)
                }
                $result.FilesDeleted++
                $result.BytesReclaimed += $file.Length

                if (-not $WhatIf.IsPresent) {
                    Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
                }
            }

            if ($oldFiles.Count -gt 0) {
                Write-Host ("  {0}: {1} file(s) removed" -f $target.Description, $oldFiles.Count) -ForegroundColor DarkCyan
            }
        }
    }

    $reclaimedMB = [math]::Round($result.BytesReclaimed / 1MB, 2)
    Write-Host ""
    Write-Host ("  Total: {0} file(s), {1} dir(s), {2} MB reclaimed" -f $result.FilesDeleted, $result.DirectoriesDeleted, $reclaimedMB) -ForegroundColor Green
    Write-Host ""
}

# Phase 2: Bundle
if (-not $SkipBundle.IsPresent) {
    Write-Host "--- Phase 2: Create Telemetry Bundle ---" -ForegroundColor Yellow

    # Ensure CI output directory exists
    $ciOutputDir = Join-Path -Path $repositoryRoot -ChildPath "Logs\CI\$RunId"
    if (-not (Test-Path -LiteralPath $ciOutputDir)) {
        New-Item -ItemType Directory -Path $ciOutputDir -Force | Out-Null
    }

    # Build Publish-TelemetryBundle arguments
    $publishArgs = @{
        BundleName = $BundleName
    }

    if ($PlanReferences) {
        $publishArgs['PlanReferences'] = $PlanReferences
    }

    if ($TaskBoardIds) {
        $publishArgs['TaskBoardIds'] = $TaskBoardIds
    }

    if ($Notes) {
        $publishArgs['Notes'] = $Notes
    }

    $publishArgs['PassThru'] = $true

    try {
        $publishScript = Join-Path -Path $PSScriptRoot -ChildPath 'Publish-TelemetryBundle.ps1'

        if (-not $WhatIf.IsPresent) {
            $bundleResult = & $publishScript @publishArgs

            if ($bundleResult) {
                $result.BundleResult = $bundleResult
                $result.BundlePath = $bundleResult.BundlePath
                Write-Host ("  Bundle created: {0}" -f $bundleResult.BundlePath) -ForegroundColor Green
            }
        } else {
            Write-Host "  [WhatIf] Would create bundle: $BundleName" -ForegroundColor Yellow
        }
    } catch {
        Write-Warning "Bundle creation failed: $($_.Exception.Message)"
        $result.BundleResult = [pscustomobject]@{
            Status = 'Failed'
            Error = $_.Exception.Message
        }
    }

    Write-Host ""
}

# Summary
$result.Status = if ($result.BundleResult -and $result.BundleResult.Status -eq 'Failed') { 'PartialFail' }
                 elseif ($result.FilesDeleted -gt 0 -or $result.BundlePath) { 'Success' }
                 else { 'NoChanges' }

$result.Message = "Cleanup: {0} file(s), {1} dir(s) removed. Bundle: {2}." -f `
    $result.FilesDeleted, $result.DirectoriesDeleted, `
    $(if ($result.BundlePath) { 'created' } elseif ($SkipBundle) { 'skipped' } else { 'none' })

Write-Host "--- Summary ---" -ForegroundColor Yellow
Write-Host ("  Files deleted: {0}" -f $result.FilesDeleted)
Write-Host ("  Directories deleted: {0}" -f $result.DirectoriesDeleted)
Write-Host ("  Bytes reclaimed: {0:N0}" -f $result.BytesReclaimed)
if ($result.BundlePath) {
    Write-Host ("  Bundle path: {0}" -f $result.BundlePath) -ForegroundColor Green
}

Write-Host ""

# Save output
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputDir = Join-Path -Path $repositoryRoot -ChildPath "Logs\CI\$RunId"
    if (-not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $OutputPath = Join-Path -Path $outputDir -ChildPath 'ArtifactHygiene.json'
}

$outputDir = Split-Path -Path $OutputPath -Parent
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8
Write-Host "Report saved to: $OutputPath" -ForegroundColor DarkCyan
Write-Host ""

if ($PassThru.IsPresent) {
    return $result
}
