<#
.SYNOPSIS
Creates a release evidence bundle with governance artifacts.

.DESCRIPTION
ST-G-004: Defines and populates Logs/ReleaseEvidence/<version>/ containing:
- Cold vs warm telemetry
- Verification summaries
- Shared-cache summaries
- Doc-sync checklist outputs
- Risk reviews per CODEX_DOC_SYNC_PLAYBOOK.md

.PARAMETER Version
Version identifier for the evidence bundle.

.PARAMETER TelemetryBundlePath
Path to telemetry bundle to include.

.PARAMETER VerificationSummaryPath
Path to verification summary JSON.

.PARAMETER WarmRunTelemetryPath
Path to warm run telemetry JSON.

.PARAMETER SharedCacheSummaryPath
Path to shared cache summary/snapshot.

.PARAMETER DocSyncChecklistPath
Path to doc-sync checklist JSON.

.PARAMETER RiskRegisterPath
Path to risk register file to include.

.PARAMETER OutputPath
Base output path. Defaults to Logs/ReleaseEvidence/<version>.

.PARAMETER RepositoryRoot
Repository root path. Defaults to parent of script directory.

.PARAMETER PassThru
Return the bundle manifest as an object.
#>
param(
    [Parameter(Mandatory)][string]$Version,
    [string]$TelemetryBundlePath,
    [string]$VerificationSummaryPath,
    [string]$WarmRunTelemetryPath,
    [string]$SharedCacheSummaryPath,
    [string]$DocSyncChecklistPath,
    [string]$RiskRegisterPath,
    [string]$OutputPath,
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

Write-Host ("Creating release evidence bundle for version {0}..." -f $Version) -ForegroundColor Cyan

# Determine output path
if (-not $OutputPath) {
    $OutputPath = Join-Path $repoRoot "Logs\ReleaseEvidence\$Version"
}

if (Test-Path -LiteralPath $OutputPath) {
    Write-Warning "Evidence bundle already exists at $OutputPath - will merge/overwrite"
}

New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

$artifacts = [System.Collections.Generic.List[pscustomobject]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

function Copy-ArtifactIfExists {
    param(
        [string]$SourcePath,
        [string]$TargetName,
        [string]$Category,
        [switch]$Required
    )

    if (-not $SourcePath) {
        if ($Required) {
            $warnings.Add("Required artifact missing: $Category ($TargetName)")
        }
        return $null
    }

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        if ($Required) {
            $warnings.Add("Required artifact not found: $SourcePath")
        }
        return $null
    }

    $targetPath = Join-Path $OutputPath $TargetName
    $targetDir = Split-Path -Parent $targetPath
    if ($targetDir -and -not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    if ((Get-Item -LiteralPath $SourcePath).PSIsContainer) {
        Copy-Item -LiteralPath $SourcePath -Destination $targetPath -Recurse -Force
    } else {
        Copy-Item -LiteralPath $SourcePath -Destination $targetPath -Force
    }

    $hash = $null
    if (-not (Get-Item -LiteralPath $SourcePath).PSIsContainer) {
        $hash = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
    }

    $artifacts.Add([pscustomobject]@{
        Category   = $Category
        SourcePath = $SourcePath
        TargetName = $TargetName
        Hash       = $hash
        Copied     = $true
    })

    Write-Host ("  Copied: {0}" -f $TargetName) -ForegroundColor Green
    return $targetPath
}

# Auto-discover artifacts if not provided
$logsDir = Join-Path $repoRoot 'Logs'

# Verification summary
if (-not $VerificationSummaryPath) {
    $verificationDir = Join-Path $logsDir 'Verification'
    if (Test-Path -LiteralPath $verificationDir) {
        $latest = Get-ChildItem -LiteralPath $verificationDir -Filter 'VerificationSummary-*.json' -File |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $VerificationSummaryPath = $latest.FullName }
    }
}

# Warm run telemetry
if (-not $WarmRunTelemetryPath) {
    $metricsDir = Join-Path $logsDir 'IngestionMetrics'
    if (Test-Path -LiteralPath $metricsDir) {
        $latest = Get-ChildItem -LiteralPath $metricsDir -Filter 'WarmRunTelemetry-*.json' -File |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $WarmRunTelemetryPath = $latest.FullName }
    }
}

# Shared cache summary
if (-not $SharedCacheSummaryPath) {
    $snapshotDir = Join-Path $logsDir 'SharedCacheSnapshot'
    if (Test-Path -LiteralPath $snapshotDir) {
        $latest = Get-ChildItem -LiteralPath $snapshotDir -Filter 'SharedCacheSnapshot-*.clixml' -File |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $SharedCacheSummaryPath = $latest.FullName }
    }
}

# Doc-sync checklist
if (-not $DocSyncChecklistPath) {
    $reportsDir = Join-Path $logsDir 'Reports'
    if (Test-Path -LiteralPath $reportsDir) {
        $latest = Get-ChildItem -LiteralPath $reportsDir -Filter 'DocSyncChecklist-*.json' -File |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $DocSyncChecklistPath = $latest.FullName }
    }
}

# Risk register
if (-not $RiskRegisterPath) {
    $riskPath = Join-Path $repoRoot 'docs\RiskRegister.md'
    if (Test-Path -LiteralPath $riskPath) { $RiskRegisterPath = $riskPath }
}

# Copy artifacts
Write-Host "`nCopying artifacts..." -ForegroundColor Cyan

Copy-ArtifactIfExists -SourcePath $TelemetryBundlePath -TargetName 'TelemetryBundle' -Category 'Telemetry' | Out-Null
Copy-ArtifactIfExists -SourcePath $VerificationSummaryPath -TargetName 'VerificationSummary.json' -Category 'Verification' -Required | Out-Null
Copy-ArtifactIfExists -SourcePath $WarmRunTelemetryPath -TargetName 'WarmRunTelemetry.json' -Category 'WarmRun' -Required | Out-Null
Copy-ArtifactIfExists -SourcePath $SharedCacheSummaryPath -TargetName 'SharedCacheSnapshot.clixml' -Category 'SharedCache' | Out-Null
Copy-ArtifactIfExists -SourcePath $DocSyncChecklistPath -TargetName 'DocSyncChecklist.json' -Category 'DocSync' | Out-Null
Copy-ArtifactIfExists -SourcePath $RiskRegisterPath -TargetName 'RiskRegister.md' -Category 'Governance' | Out-Null

# Also copy latest cold telemetry
$coldTelemetryPath = Join-Path (Join-Path $logsDir 'IngestionMetrics') ((Get-Date).ToString('yyyy-MM-dd') + '.json')
if (Test-Path -LiteralPath $coldTelemetryPath) {
    Copy-ArtifactIfExists -SourcePath $coldTelemetryPath -TargetName 'ColdTelemetry.json' -Category 'Telemetry' | Out-Null
}

# Build manifest
$manifest = [pscustomobject]@{
    Version     = $Version
    CreatedUtc  = (Get-Date).ToUniversalTime().ToString('o')
    CreatedBy   = $env:USERNAME
    Machine     = $env:COMPUTERNAME
    OutputPath  = $OutputPath
    Artifacts   = $artifacts
    Warnings    = $warnings
    Complete    = $warnings.Count -eq 0
}

# Write manifest
$manifestPath = Join-Path $OutputPath 'EvidenceManifest.json'
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Write-Host ("`nManifest written to: {0}" -f $manifestPath) -ForegroundColor Green

# Generate README
$readmeContent = @"
# Release Evidence Bundle - $Version

**Created:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
**Machine:** $env:COMPUTERNAME

## Contents

| Category | File | SHA-256 |
|----------|------|---------|
$(($artifacts | ForEach-Object { "| $($_.Category) | $($_.TargetName) | $($_.Hash.Substring(0, 16))... |" }) -join "`n")

## Verification Checklist

- [ ] Warm run improvement >= 60%
- [ ] Cache hit ratio >= 99%
- [ ] Shared cache sites >= 2, hosts >= 37
- [ ] Doc-sync checklist complete
- [ ] Risk register reviewed

$(if ($warnings.Count -gt 0) {
@"

## Warnings

$(($warnings | ForEach-Object { "- $_" }) -join "`n")
"@
})

---
*Generated by Tools/New-ReleaseEvidenceBundle.ps1 (ST-G-004)*
"@

$readmePath = Join-Path $OutputPath 'README.md'
Set-Content -LiteralPath $readmePath -Value $readmeContent -Encoding UTF8
Write-Host ("README written to: {0}" -f $readmePath) -ForegroundColor Green

# Summary
Write-Host "`nEvidence Bundle Summary:" -ForegroundColor Cyan
Write-Host ("  Version: {0}" -f $Version)
Write-Host ("  Path: {0}" -f $OutputPath)
Write-Host ("  Artifacts: {0}" -f $artifacts.Count)

if ($warnings.Count -gt 0) {
    Write-Host ("  Warnings: {0}" -f $warnings.Count) -ForegroundColor Yellow
    foreach ($w in $warnings) {
        Write-Host ("    - {0}" -f $w) -ForegroundColor Yellow
    }
}

if ($PassThru) {
    return $manifest
}
