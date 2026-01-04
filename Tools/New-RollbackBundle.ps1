[CmdletBinding()]
param(
    [string]$OutputRoot = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Logs\RollbackBundles'),

    [string]$BundleName,

    [string]$IncidentId,

    [string]$Reason,

    [switch]$IncludeSharedCacheSnapshot,

    [switch]$PassThru
)

<#
.SYNOPSIS
Creates a rollback bundle capturing current state before rollback (ST-R-002).

.DESCRIPTION
Captures current configuration, telemetry bundle paths, shared-cache snapshots,
and package hashes into a timestamped bundle for incident recovery.

Contents:
- RollbackManifest.json: Bundle metadata and captured paths
- StateTraceSettings.json: Copy of current settings
- TelemetryBundleRefs.json: Latest telemetry bundle paths/hashes
- SharedCacheSnapshot-*.clixml: Copy of latest snapshot (if -IncludeSharedCacheSnapshot)
- PackageHashes.json: Hashes of key modules/scripts

.PARAMETER OutputRoot
Root directory for rollback bundles. Defaults to Logs/RollbackBundles.

.PARAMETER BundleName
Optional bundle name. Defaults to Rollback-<timestamp>.

.PARAMETER IncidentId
Optional incident ID to associate with the bundle.

.PARAMETER Reason
Optional reason for creating the rollback bundle.

.PARAMETER IncludeSharedCacheSnapshot
If set, copies the latest shared-cache snapshot into the bundle.

.PARAMETER PassThru
Returns the bundle manifest as an object.

.EXAMPLE
pwsh Tools\New-RollbackBundle.ps1 -IncidentId INC-2026-0104 -Reason "Parser regression"

.EXAMPLE
pwsh Tools\New-RollbackBundle.ps1 -IncludeSharedCacheSnapshot -PassThru
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

if ([string]::IsNullOrWhiteSpace($BundleName)) {
    $BundleName = "Rollback-$timestamp"
}

$bundlePath = Join-Path -Path $OutputRoot -ChildPath $BundleName

# Initialize manifest
$manifest = [pscustomobject]@{
    GeneratedAtUtc      = (Get-Date).ToUniversalTime().ToString('o')
    BundleName          = $BundleName
    BundlePath          = $bundlePath
    IncidentId          = $IncidentId
    Reason              = $Reason
    MachineName         = $env:COMPUTERNAME
    UserName            = $env:USERNAME
    RepositoryRoot      = $repositoryRoot
    CapturedFiles       = @()
    TelemetryBundleRefs = @()
    PackageHashes       = @()
    Status              = 'Unknown'
    Message             = ''
}

Write-Host "`n=== Creating Rollback Bundle (ST-R-002) ===" -ForegroundColor Cyan
Write-Host ("Timestamp: {0}" -f $manifest.GeneratedAtUtc) -ForegroundColor DarkGray
Write-Host ("Bundle: {0}" -f $BundleName) -ForegroundColor DarkGray
if ($IncidentId) { Write-Host ("Incident: {0}" -f $IncidentId) -ForegroundColor DarkGray }
if ($Reason) { Write-Host ("Reason: {0}" -f $Reason) -ForegroundColor DarkGray }
Write-Host ""

# Create bundle directory
if (-not (Test-Path -LiteralPath $bundlePath)) {
    New-Item -ItemType Directory -Path $bundlePath -Force | Out-Null
}

Write-Host "--- Capturing State ---" -ForegroundColor Yellow

# 1. Copy StateTraceSettings.json
$settingsPath = Join-Path -Path $repositoryRoot -ChildPath 'Data\StateTraceSettings.json'
if (Test-Path -LiteralPath $settingsPath) {
    $destSettings = Join-Path -Path $bundlePath -ChildPath 'StateTraceSettings.json'
    Copy-Item -LiteralPath $settingsPath -Destination $destSettings -Force
    $manifest.CapturedFiles += [pscustomobject]@{
        Name   = 'StateTraceSettings.json'
        Source = $settingsPath
        Dest   = $destSettings
        Hash   = (Get-FileHash -LiteralPath $destSettings -Algorithm SHA256).Hash
    }
    Write-Host "  Captured: StateTraceSettings.json" -ForegroundColor Green
} else {
    Write-Host "  Skipped: StateTraceSettings.json (not found)" -ForegroundColor DarkGray
}

# 2. Find and reference latest telemetry bundles
$telemetryBundlesDir = Join-Path -Path $repositoryRoot -ChildPath 'Logs\TelemetryBundles'
if (Test-Path -LiteralPath $telemetryBundlesDir) {
    $latestBundles = Get-ChildItem -LiteralPath $telemetryBundlesDir -Directory |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 3

    foreach ($bundle in $latestBundles) {
        $verificationPath = Join-Path -Path $bundle.FullName -ChildPath 'VerificationSummary.json'
        $verificationHash = $null
        if (Test-Path -LiteralPath $verificationPath) {
            $verificationHash = (Get-FileHash -LiteralPath $verificationPath -Algorithm SHA256).Hash
        }

        $manifest.TelemetryBundleRefs += [pscustomobject]@{
            Name             = $bundle.Name
            Path             = $bundle.FullName
            LastWriteTime    = $bundle.LastWriteTime.ToString('o')
            VerificationHash = $verificationHash
        }
    }
    Write-Host ("  Referenced: {0} telemetry bundle(s)" -f $latestBundles.Count) -ForegroundColor Green
} else {
    Write-Host "  Skipped: TelemetryBundles directory not found" -ForegroundColor DarkGray
}

# Save telemetry bundle refs
$telemetryRefsPath = Join-Path -Path $bundlePath -ChildPath 'TelemetryBundleRefs.json'
$manifest.TelemetryBundleRefs | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $telemetryRefsPath -Encoding utf8

# 3. Copy shared-cache snapshot (optional)
if ($IncludeSharedCacheSnapshot.IsPresent) {
    $snapshotDir = Join-Path -Path $repositoryRoot -ChildPath 'Logs\SharedCacheSnapshot'
    $latestSnapshot = Join-Path -Path $snapshotDir -ChildPath 'SharedCacheSnapshot-latest.clixml'

    if (Test-Path -LiteralPath $latestSnapshot) {
        $snapshotDest = Join-Path -Path $bundlePath -ChildPath 'SharedCacheSnapshot-latest.clixml'
        Copy-Item -LiteralPath $latestSnapshot -Destination $snapshotDest -Force
        $manifest.CapturedFiles += [pscustomobject]@{
            Name   = 'SharedCacheSnapshot-latest.clixml'
            Source = $latestSnapshot
            Dest   = $snapshotDest
            Hash   = (Get-FileHash -LiteralPath $snapshotDest -Algorithm SHA256).Hash
        }
        Write-Host "  Captured: SharedCacheSnapshot-latest.clixml" -ForegroundColor Green
    } else {
        Write-Host "  Skipped: SharedCacheSnapshot-latest.clixml (not found)" -ForegroundColor DarkGray
    }
}

# 4. Calculate hashes for key modules/scripts
$keyFiles = @(
    'Modules\DeviceLogParserModule.psm1',
    'Modules\InterfaceModule.psm1',
    'Modules\TelemetryModule.psm1',
    'Modules\FilterStateModule.psm1',
    'Main\MainWindow.ps1',
    'Main\MainWindow.xaml'
)

foreach ($relPath in $keyFiles) {
    $fullPath = Join-Path -Path $repositoryRoot -ChildPath $relPath
    if (Test-Path -LiteralPath $fullPath) {
        $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash
        $manifest.PackageHashes += [pscustomobject]@{
            File = $relPath
            Hash = $hash
        }
    }
}
Write-Host ("  Hashed: {0} key file(s)" -f $manifest.PackageHashes.Count) -ForegroundColor Green

# Save package hashes
$hashesPath = Join-Path -Path $bundlePath -ChildPath 'PackageHashes.json'
$manifest.PackageHashes | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $hashesPath -Encoding utf8

# 5. Capture git status
try {
    $gitBranch = git rev-parse --abbrev-ref HEAD 2>$null
    $gitCommit = git rev-parse HEAD 2>$null
    $gitStatus = git status --porcelain 2>$null

    $gitInfo = [pscustomobject]@{
        Branch        = $gitBranch
        CommitHash    = $gitCommit
        HasUncommitted = ($gitStatus -and $gitStatus.Count -gt 0)
        UncommittedCount = if ($gitStatus) { @($gitStatus).Count } else { 0 }
    }

    $gitInfoPath = Join-Path -Path $bundlePath -ChildPath 'GitInfo.json'
    $gitInfo | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $gitInfoPath -Encoding utf8
    $manifest.CapturedFiles += [pscustomobject]@{
        Name   = 'GitInfo.json'
        Source = 'git commands'
        Dest   = $gitInfoPath
        Hash   = (Get-FileHash -LiteralPath $gitInfoPath -Algorithm SHA256).Hash
    }
    Write-Host ("  Captured: GitInfo.json (branch: {0}, commit: {1})" -f $gitBranch, $gitCommit.Substring(0, 7)) -ForegroundColor Green
} catch {
    Write-Host "  Skipped: GitInfo.json (git not available)" -ForegroundColor DarkGray
}

# Finalize manifest
$manifest.Status = 'Success'
$manifest.Message = "Rollback bundle created with $($manifest.CapturedFiles.Count) files, $($manifest.TelemetryBundleRefs.Count) bundle refs, $($manifest.PackageHashes.Count) hashes."

# Save manifest
$manifestPath = Join-Path -Path $bundlePath -ChildPath 'RollbackManifest.json'
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8

Write-Host ""
Write-Host ("SUCCESS: {0}" -f $manifest.Message) -ForegroundColor Green
Write-Host ("Bundle path: {0}" -f $bundlePath) -ForegroundColor DarkCyan
Write-Host ""

if ($PassThru.IsPresent) {
    return $manifest
}
