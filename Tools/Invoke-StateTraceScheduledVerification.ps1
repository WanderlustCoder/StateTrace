[CmdletBinding()]
param(
    [switch]$IncludeTests,
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
[switch]$DisableSharedCacheSnapshot,
[switch]$ShowSharedCacheSummary,
[string]$SharedCacheSnapshotDirectory,
[switch]$RequireTelemetryIntegrity,
[Nullable[int]]$SharedCacheMinimumSiteCount,
[Nullable[int]]$SharedCacheMinimumHostCount,
[Nullable[int]]$SharedCacheMinimumTotalRowCount,
[string[]]$SharedCacheRequiredSites,
[switch]$SkipSharedCacheSummaryEvaluation,
[switch]$SkipWarmRunAssertions,
[switch]$QuietSummary,
[switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$verificationScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Invoke-StateTraceVerification.ps1'
if (-not (Test-Path -LiteralPath $verificationScript)) {
    throw "Verification harness not found at $verificationScript."
}

function Resolve-OptionalPath {
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $null }
    try {
        return (Resolve-Path -LiteralPath $PathValue -ErrorAction Stop).Path
    } catch {
        $basePath = (Get-Location).ProviderPath
        return [System.IO.Path]::GetFullPath($PathValue, $basePath)
    }
}

$verificationParameters = @{}

if (-not $IncludeTests.IsPresent) {
    $verificationParameters['SkipTests'] = $true
}

$verificationParameters['VerboseParsing'] = $true

if ($SkipParsing.IsPresent) { $verificationParameters['SkipParsing'] = $true }
if ($ResetExtractedLogs.IsPresent) { $verificationParameters['ResetExtractedLogs'] = $true }
if ($PreserveModuleSession.IsPresent) { $verificationParameters['PreserveModuleSession'] = $true }
if (-not [string]::IsNullOrWhiteSpace($WarmRunTelemetryDirectory)) {
    $verificationParameters['WarmRunTelemetryDirectory'] = $WarmRunTelemetryDirectory
}
if (-not [string]::IsNullOrWhiteSpace($WarmRunRegressionOutputPath)) {
    $verificationParameters['WarmRunRegressionOutputPath'] = $WarmRunRegressionOutputPath
}
if ($PSBoundParameters.ContainsKey('WarmRunMinimumImprovementPercent')) {
    $verificationParameters['WarmRunMinimumImprovementPercent'] = $WarmRunMinimumImprovementPercent
}
if ($PSBoundParameters.ContainsKey('WarmRunMinimumCacheHitRatioPercent')) {
    $verificationParameters['WarmRunMinimumCacheHitRatioPercent'] = $WarmRunMinimumCacheHitRatioPercent
}
if ($PSBoundParameters.ContainsKey('WarmRunMaximumCacheMissCount')) {
    $verificationParameters['WarmRunMaximumCacheMissCount'] = $WarmRunMaximumCacheMissCount
}
if ($PSBoundParameters.ContainsKey('WarmRunMaximumSignatureMissCount')) {
    $verificationParameters['WarmRunMaximumSignatureMissCount'] = $WarmRunMaximumSignatureMissCount
}
if ($PSBoundParameters.ContainsKey('WarmRunMaximumSignatureRewriteTotal')) {
    $verificationParameters['WarmRunMaximumSignatureRewriteTotal'] = $WarmRunMaximumSignatureRewriteTotal
}
if ($PSBoundParameters.ContainsKey('WarmRunMaximumWarmAverageDeltaMs')) {
    $verificationParameters['WarmRunMaximumWarmAverageDeltaMs'] = $WarmRunMaximumWarmAverageDeltaMs
}
if ($SkipWarmRunAssertions.IsPresent) {
    $verificationParameters['SkipWarmRunAssertions'] = $true
}
if ($DisableSharedCacheSnapshot.IsPresent) {
    $verificationParameters['DisableSharedCacheSnapshot'] = $true
}
if ($ShowSharedCacheSummary.IsPresent) {
    $verificationParameters['ShowSharedCacheSummary'] = $true
}
if ($SharedCacheMinimumSiteCount -ne $null) {
    $verificationParameters['SharedCacheMinimumSiteCount'] = [int]$SharedCacheMinimumSiteCount
}
if ($SharedCacheMinimumHostCount -ne $null) {
    $verificationParameters['SharedCacheMinimumHostCount'] = [int]$SharedCacheMinimumHostCount
}
if ($SharedCacheMinimumTotalRowCount -ne $null) {
    $verificationParameters['SharedCacheMinimumTotalRowCount'] = [int]$SharedCacheMinimumTotalRowCount
}
if ($PSBoundParameters.ContainsKey('SharedCacheRequiredSites')) {
    $verificationParameters['SharedCacheRequiredSites'] = $SharedCacheRequiredSites
}
if ($SkipSharedCacheSummaryEvaluation.IsPresent) {
    $verificationParameters['SkipSharedCacheSummaryEvaluation'] = $true
}
if ($RequireTelemetryIntegrity.IsPresent) {
    $verificationParameters['RequireTelemetryIntegrity'] = $true
}

$sharedCacheSnapshotDirectoryResolved = $null
if (-not [string]::IsNullOrWhiteSpace($SharedCacheSnapshotDirectory)) {
    $sharedCacheSnapshotDirectoryResolved = Resolve-OptionalPath -PathValue $SharedCacheSnapshotDirectory
    if ($sharedCacheSnapshotDirectoryResolved) {
        $verificationParameters['SharedCacheSnapshotDirectory'] = $sharedCacheSnapshotDirectoryResolved
    }
} else {
    $sharedCacheSnapshotDirectoryResolved = Join-Path -Path $repositoryRoot -ChildPath 'Logs\SharedCacheSnapshot'
}

$verificationParameters['PassThru'] = $true

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$verificationLogDir = Join-Path -Path $repositoryRoot -ChildPath 'Logs\Verification'
if (-not (Test-Path -LiteralPath $verificationLogDir)) {
    New-Item -ItemType Directory -Path $verificationLogDir -Force | Out-Null
}
$transcriptPath = Join-Path -Path $verificationLogDir -ChildPath ("StateTraceVerification-{0}.log" -f $timestamp)

Start-Transcript -Path $transcriptPath -Force | Out-Null
try {
    Write-Host ("[{0}] Starting scheduled verification run..." -f (Get-Date).ToString('u')) -ForegroundColor Cyan
    $result = & $verificationScript @verificationParameters
    Write-Host ("[{0}] Verification run completed successfully." -f (Get-Date).ToString('u')) -ForegroundColor Green

    if (-not $QuietSummary.IsPresent -and $null -ne $result) {
        $summary = $result.WarmRunSummary
        if ($null -ne $summary) {
            Write-Host 'Warm-run regression summary:' -ForegroundColor Yellow
            Write-Host ("  Telemetry Path          : {0}" -f $summary.TelemetryPath) -ForegroundColor Yellow
            Write-Host ("  Cold Avg / P95 / Max Ms : {0} / {1} / {2}" -f $summary.ColdInterfaceCallAvgMs, $summary.ColdInterfaceCallP95Ms, $summary.ColdInterfaceCallMaxMs) -ForegroundColor Yellow
            Write-Host ("  Warm Avg / P95 / Max Ms : {0} / {1} / {2}" -f $summary.WarmInterfaceCallAvgMs, $summary.WarmInterfaceCallP95Ms, $summary.WarmInterfaceCallMaxMs) -ForegroundColor Yellow
            Write-Host ("  Improvement (ms / %)    : {0} / {1}" -f $summary.ImprovementAverageMs, $summary.ImprovementPercent) -ForegroundColor Yellow
            Write-Host ("  Warm Cache Hits / Miss  : {0} / {1}" -f $summary.WarmCacheProviderHitCount, $summary.WarmCacheProviderMissCount) -ForegroundColor Yellow
            Write-Host ("  Warm Sig Miss / Rewrite : {0} / {1}" -f $summary.WarmSignatureMatchMissCount, $summary.WarmSignatureRewriteTotal) -ForegroundColor Yellow
            if ($result.WarmRunEvaluation) {
                $thresholds = $result.WarmRunEvaluation.Thresholds
                $improvementThreshold = if ($thresholds -and $thresholds.MinimumImprovementPercent -ne $null) { $thresholds.MinimumImprovementPercent } else { $WarmRunMinimumImprovementPercent }
                if ($improvementThreshold -eq $null) { $improvementThreshold = 25 }
                $hitThreshold = if ($thresholds -and $thresholds.MinimumCacheHitRatioPercent -ne $null) { $thresholds.MinimumCacheHitRatioPercent } else { $WarmRunMinimumCacheHitRatioPercent }
                if ($hitThreshold -eq $null) { $hitThreshold = 99 }
                Write-Host ("  Warm-run policy status  : Pass (Improvement >= {0}%, Hit ratio >= {1}%)" -f `
                    $improvementThreshold, $hitThreshold) -ForegroundColor Green
            }
        } else {
            Write-Warning 'Warm-run summary information was not returned; consult WarmRunTelemetry-latest-summary.json.'
        }

        $sharedCacheEvaluation = $result.SharedCacheSummaryEvaluation
        if ($sharedCacheEvaluation) {
            $stats = $sharedCacheEvaluation.Statistics
            $statusColor = if ($sharedCacheEvaluation.Pass) { 'Green' } else { 'Red' }
            Write-Host 'Shared-cache summary evaluation:' -ForegroundColor Yellow
            Write-Host ("  Summary Path            : {0}" -f $result.SharedCacheSummaryPath) -ForegroundColor Yellow
            if ($stats) {
                Write-Host ("  Site Count / Hosts / Rows : {0} / {1} / {2}" -f $stats.SiteCount, $stats.TotalHostCount, $stats.TotalRowCount) -ForegroundColor Yellow
            }
            Write-Host ("  Status                  : {0}" -f ($sharedCacheEvaluation.Pass ? 'Pass' : 'Fail')) -ForegroundColor $statusColor
            if (-not $sharedCacheEvaluation.Pass -and $sharedCacheEvaluation.Messages) {
                foreach ($msg in $sharedCacheEvaluation.Messages) {
                    Write-Host ("  - {0}" -f $msg) -ForegroundColor Red
                }
            }
        } elseif (-not $SkipSharedCacheSummaryEvaluation.IsPresent) {
            Write-Warning 'Shared-cache summary evaluation did not return results; inspect Logs/SharedCacheSnapshot/ for details.'
        }
    }

    $archivedSharedCacheSummaryPath = $null
    $archivedSharedCacheLatestPath = $null
    $archivedSharedCacheCoveragePath = $null
    if ($sharedCacheSnapshotDirectoryResolved -and (Test-Path -LiteralPath $sharedCacheSnapshotDirectoryResolved)) {
        $latestSummaryPath = Join-Path -Path $sharedCacheSnapshotDirectoryResolved -ChildPath 'SharedCacheSnapshot-latest-summary.json'
        $timestampSummaryPath = $null
        try {
            $timestampSummary = Get-ChildItem -Path $sharedCacheSnapshotDirectoryResolved -Filter 'SharedCacheSnapshot-*-summary.json' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($timestampSummary) {
                $timestampSummaryPath = $timestampSummary.FullName
            }
        } catch {
            Write-Warning ("Failed to enumerate shared-cache snapshot summaries: {0}" -f $_.Exception.Message)
        }

        $primarySummaryPath = $timestampSummaryPath
        if (-not $primarySummaryPath -and (Test-Path -LiteralPath $latestSummaryPath)) {
            $primarySummaryPath = $latestSummaryPath
        }

        if ($primarySummaryPath -and (Test-Path -LiteralPath $primarySummaryPath)) {
            $summaryArchiveName = "SharedCacheSummary-{0}.json" -f $timestamp
            $summaryArchivePath = Join-Path -Path $verificationLogDir -ChildPath $summaryArchiveName
            try {
                Copy-Item -LiteralPath $primarySummaryPath -Destination $summaryArchivePath -Force
                $archivedSharedCacheSummaryPath = $summaryArchivePath
                Write-Host ("Shared-cache snapshot summary archived at {0}" -f $summaryArchivePath) -ForegroundColor DarkYellow

                if ($latestSummaryPath -and (Test-Path -LiteralPath $latestSummaryPath)) {
                    $latestArchiveName = "SharedCacheSummary-{0}-latest.json" -f $timestamp
                    $latestArchivePath = Join-Path -Path $verificationLogDir -ChildPath $latestArchiveName
                    try {
                        Copy-Item -LiteralPath $latestSummaryPath -Destination $latestArchivePath -Force
                        $archivedSharedCacheLatestPath = $latestArchivePath
                    } catch {
                        Write-Warning ("Failed to archive latest shared-cache summary: {0}" -f $_.Exception.Message)
                    }
                }
            } catch {
                Write-Warning ("Failed to archive shared-cache summary: {0}" -f $_.Exception.Message)
            }
        } elseif ($ShowSharedCacheSummary.IsPresent) {
            Write-Warning 'Shared-cache summary was requested, but no summary file was found after the run.'
        }
    } elseif ($ShowSharedCacheSummary.IsPresent) {
        Write-Warning 'Shared-cache summary was requested, but the snapshot directory could not be resolved.'
    }

    if ($result -and $result.SharedCacheCoveragePath) {
        $coverageSource = $result.SharedCacheCoveragePath
        if (Test-Path -LiteralPath $coverageSource) {
            $coverageArchiveName = "SharedCacheCoverage-{0}.json" -f $timestamp
            $coverageArchivePath = Join-Path -Path $verificationLogDir -ChildPath $coverageArchiveName
            try {
                Copy-Item -LiteralPath $coverageSource -Destination $coverageArchivePath -Force
                $archivedSharedCacheCoveragePath = $coverageArchivePath
                $latestCoveragePath = Join-Path -Path $verificationLogDir -ChildPath 'SharedCacheCoverage-latest.json'
                Copy-Item -LiteralPath $coverageArchivePath -Destination $latestCoveragePath -Force
            } catch {
                Write-Warning ("Failed to archive shared-cache coverage summary: {0}" -f $_.Exception.Message)
            }
        } else {
            Write-Warning ("Shared-cache coverage output '{0}' was not found; skipping archive." -f $coverageSource)
        }
    }

    if ($result) {
        try {
            if ($archivedSharedCacheSummaryPath) {
                $result | Add-Member -NotePropertyName 'SharedCacheSummaryPath' -NotePropertyValue $archivedSharedCacheSummaryPath -Force
            }
            if ($archivedSharedCacheLatestPath) {
                $result | Add-Member -NotePropertyName 'SharedCacheSummaryLatestPath' -NotePropertyValue $archivedSharedCacheLatestPath -Force
            }
            if ($archivedSharedCacheCoveragePath) {
                $result | Add-Member -NotePropertyName 'SharedCacheCoverageArchivePath' -NotePropertyValue $archivedSharedCacheCoveragePath -Force
            }
        } catch {
            Write-Warning ("Failed to annotate verification result with shared-cache summary paths: {0}" -f $_.Exception.Message)
        }
    }

    if ($PassThru.IsPresent) {
        $result
    }
} catch {
    Write-Host ("[{0}] Scheduled verification failed: {1}" -f (Get-Date).ToString('u'), $_.Exception.Message) -ForegroundColor Red
    throw
} finally {
    Stop-Transcript | Out-Null
    if (Test-Path -LiteralPath $transcriptPath) {
        Write-Host ("Transcript captured at {0}" -f $transcriptPath) -ForegroundColor DarkGray
    }
}
