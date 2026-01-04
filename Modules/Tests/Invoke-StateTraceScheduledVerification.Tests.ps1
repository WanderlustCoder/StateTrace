Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Invoke-StateTraceScheduledVerification.ps1'

Describe 'Invoke-StateTraceScheduledVerification' {
    It 'emits a verification summary and latest pointer' {
        $fakeRoot = Join-Path -Path $TestDrive -ChildPath 'Repo'
        $toolsRoot = Join-Path -Path $fakeRoot -ChildPath 'Tools'
        $logsRoot = Join-Path -Path $fakeRoot -ChildPath 'Logs'
        $sharedCacheDir = Join-Path -Path $logsRoot -ChildPath 'SharedCacheSnapshot'

        New-Item -ItemType Directory -Path $toolsRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $sharedCacheDir -Force | Out-Null

        Copy-Item -LiteralPath $scriptPath -Destination (Join-Path $toolsRoot 'Invoke-StateTraceScheduledVerification.ps1') -Force

        $fakeVerificationScript = @'
[CmdletBinding()]
param(
    [switch]$SkipTests,
    [switch]$VerboseParsing,
    [switch]$SkipParsing,
    [switch]$ResetExtractedLogs,
    [switch]$PreserveModuleSession,
    [string]$WarmRunTelemetryDirectory,
    [string]$WarmRunRegressionOutputPath,
    [double]$WarmRunMinimumImprovementPercent,
    [double]$WarmRunMinimumCacheHitRatioPercent,
    [int]$WarmRunMaximumCacheMissCount,
    [int]$WarmRunMaximumSignatureMissCount,
    [int]$WarmRunMaximumSignatureRewriteTotal,
    [double]$WarmRunMaximumWarmAverageDeltaMs,
    [switch]$SkipWarmRunAssertions,
    [switch]$DisableSharedCacheSnapshot,
    [switch]$ShowSharedCacheSummary,
    [int]$SharedCacheMinimumSiteCount,
    [int]$SharedCacheMinimumHostCount,
    [int]$SharedCacheMinimumTotalRowCount,
    [string[]]$SharedCacheRequiredSites,
    [switch]$SkipSharedCacheSummaryEvaluation,
    [switch]$RequireTelemetryIntegrity,
    [switch]$RequireSharedCacheSnapshotGuard,
    [string]$SharedCacheSnapshotDirectory,
    # LANDMARK: ST-B-007 shared cache diagnostics pass-through test
    [switch]$GenerateSharedCacheDiagnostics,
    [string]$SharedCacheDiagnosticsDirectory,
    [switch]$PassThru
)

if ($PassThru) {
    [pscustomobject]@{
        WarmRunTelemetryPath = 'Logs\IngestionMetrics\WarmRunTelemetry-TEST.json'
        WarmRunTelemetrySummaryPath = 'Logs\IngestionMetrics\WarmRunTelemetry-latest-summary.json'
        WarmRunSummary = [pscustomobject]@{
            ImprovementPercent = 50
            WarmCacheProviderHitCount = 10
        }
        WarmRunEvaluation = [pscustomobject]@{
            Pass = $true
            Thresholds = [pscustomobject]@{
                MinimumImprovementPercent = 25
                MinimumCacheHitRatioPercent = 99
            }
        }
        QueueMetricsPath = 'Logs\IngestionMetrics\2025-12-22.json'
        QueueDelayEvaluation = [pscustomobject]@{
            Pass = $true
            Statistics = [pscustomobject]@{
                SampleCount = 10
            }
        }
        QueueDelaySummaryPath = 'Logs\IngestionMetrics\QueueDelaySummary-TEST.json'
        SharedCacheSnapshotDirectory = $SharedCacheSnapshotDirectory
        SharedCacheSummaryPath = 'Logs\SharedCacheSnapshot\SharedCacheSnapshot-latest-summary.json'
        SharedCacheCoveragePath = $null
        SharedCacheSnapshotGuardPath = $null
        SharedCacheSummaryEvaluation = [pscustomobject]@{
            Pass = $true
            Statistics = [pscustomobject]@{
                SiteCount = 2
                TotalHostCount = 5
                TotalRowCount = 100
            }
        }
        # LANDMARK: ST-B-007 shared cache diagnostics pass-through test
        SharedCacheDiagnosticsDirectory = $SharedCacheDiagnosticsDirectory
        SharedCacheStoreDiagnosticsPath = $null
        SiteCacheProviderDiagnosticsPath = $null
        DiffHotspotReportPath = $null
        TelemetryBundleReadiness = $null
    }
}
'@

        Set-Content -LiteralPath (Join-Path $toolsRoot 'Invoke-StateTraceVerification.ps1') -Value $fakeVerificationScript -Encoding utf8
        Set-Content -LiteralPath (Join-Path $sharedCacheDir 'SharedCacheSnapshot-latest-summary.json') -Value '{}' -Encoding utf8

        $scheduledScript = Join-Path $toolsRoot 'Invoke-StateTraceScheduledVerification.ps1'
        # LANDMARK: Shared cache diagnostics pass-through test
        $sharedCacheDiagnosticsDir = Join-Path -Path $logsRoot -ChildPath 'SharedCacheDiagnostics'
        & $scheduledScript -SkipParsing -SkipWarmRunAssertions -QuietSummary -GenerateSharedCacheDiagnostics -SharedCacheDiagnosticsDirectory $sharedCacheDiagnosticsDir | Out-Null

        $verificationDir = Join-Path $logsRoot 'Verification'
        $summaryFiles = @(Get-ChildItem -Path $verificationDir -Filter 'VerificationSummary-*.json' -File |
            Where-Object { $_.Name -notlike '*latest*' })
        $summaryFiles.Count | Should Be 1
        (Test-Path -LiteralPath (Join-Path $verificationDir 'VerificationSummary-latest.json')) | Should Be $true

        $summary = Get-Content -LiteralPath $summaryFiles[0].FullName -Raw | ConvertFrom-Json
        $summary.Status | Should Be 'Pass'
        $summary.WarmRun.Summary.ImprovementPercent | Should Be 50
        $summary.SharedCache.SummaryPath | Should Match 'SharedCacheSummary-'
        # LANDMARK: Shared cache diagnostics pass-through test
        $summary.SharedCacheDiagnostics.Directory | Should Be $sharedCacheDiagnosticsDir
    }
}
