[CmdletBinding()]
param(
    [switch]$SkipTests,
    [switch]$SkipParsing,
    [string]$DatabasePath,
    [Nullable[int]]$ThreadCeilingOverride = $null,
    [Nullable[int]]$MaxWorkersPerSiteOverride = $null,
    [Nullable[int]]$MaxActiveSitesOverride = $null,
    [Nullable[int]]$JobsPerThreadOverride = $null,
    [Nullable[int]]$MinRunspacesOverride = $null,
    [switch]$VerboseParsing,
    [switch]$ResetExtractedLogs,
    [switch]$PreserveModuleSession,
    [switch]$SkipSchedulerFairnessGuard,
    [switch]$SkipWarmRunRegression,
    [switch]$ForcePortBatchReadySynthesis,
    [switch]$UseBalancedHostOrder,
    [switch]$RawPortDiversityAutoConcurrency,
    [string]$WarmRunTelemetryDirectory,
    [string]$WarmRunRegressionOutputPath,
    [double]$WarmRunMinimumImprovementPercent = 25,
    [double]$WarmRunMinimumCacheHitRatioPercent = 99,
    [int]$WarmRunMaximumCacheMissCount = 0,
    [int]$WarmRunMaximumSignatureMissCount = 0,
    [int]$WarmRunMaximumSignatureRewriteTotal = 0,
    [double]$WarmRunMaximumWarmAverageDeltaMs = 0,
    [switch]$DisableSharedCacheSnapshot,
    [string]$SharedCacheSnapshotDirectory,
    [int]$SharedCacheMinimumSiteCount = 1,
    [int]$SharedCacheMinimumHostCount = 1,
    [int]$SharedCacheMinimumTotalRowCount = 1,
    [string[]]$SharedCacheRequiredSites,
    [string]$SharedCacheCoverageOutputPath,
    [switch]$SkipSharedCacheSummaryEvaluation,
    [switch]$ShowSharedCacheSummary,
    [switch]$RequireSharedCacheSnapshotGuard,
    [switch]$SkipQueueDelayEvaluation,
    [string]$QueueMetricsPath,
    [int]$QueueDelayMinimumSampleCount = 10,
    [double]$QueueDelayP95Maximum = 120,
    [double]$QueueDelayP99Maximum = 200,
    [string]$QueueDelaySummaryPath,
    [switch]$SkipQueueDelaySummaryExport,
    [switch]$GenerateDiffHotspotReport,
    [int]$DiffHotspotTop = 20,
    [string]$DiffHotspotOutputPath,
    [switch]$GenerateSharedCacheDiagnostics,
    [string]$SharedCacheDiagnosticsDirectory,
    [string]$TelemetryBundlePath,
    [string[]]$TelemetryBundleAreas = @('Telemetry','Routing'),
    [switch]$VerifyTelemetryBundleReadiness,
    [switch]$RequireTelemetryIntegrity,
    [switch]$SkipWarmRunAssertions,
    [switch]$QuietSummary,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$pipelineScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Invoke-StateTracePipeline.ps1'
if (-not (Test-Path -LiteralPath $pipelineScript)) {
    throw "Pipeline harness not found at $pipelineScript."
}
$verificationModulePath = Join-Path -Path $repositoryRoot -ChildPath 'Modules\VerificationModule.psm1'
$toolingJsonPath = Join-Path -Path $repositoryRoot -ChildPath 'Tools\ToolingJson.psm1'
if (-not (Test-Path -LiteralPath $toolingJsonPath)) {
    throw "ToolingJson module not found at '$toolingJsonPath'."
}
Import-Module -Name $toolingJsonPath -Force -ErrorAction Stop

function Ensure-VerificationModuleLoaded {
    param([Parameter(Mandatory)][string]$ModulePath)

    if (-not (Get-Module -Name VerificationModule)) {
        if (-not (Test-Path -LiteralPath $ModulePath)) {
            throw "Verification module not found at $ModulePath."
        }
        Import-Module -Name $ModulePath -Force
    }
}

# LANDMARK: Queue gate self-sufficiency - decide when to run queue harness
function Resolve-QueueDelayHarnessPolicy {
    [CmdletBinding()]
    param(
        [switch]$SkipQueueDelayEvaluation,
        [string]$QueueMetricsPath
    )

    $shouldRun = $false
    $reason = ''

    if (-not $SkipQueueDelayEvaluation.IsPresent -and [string]::IsNullOrWhiteSpace($QueueMetricsPath)) {
        $shouldRun = $true
        $reason = 'QueueMetricsPath not specified; run queue delay harness to populate InterfacePortQueueMetrics.'
    }

    return [pscustomobject]@{
        ShouldRun = $shouldRun
        Reason    = $reason
    }
}

$pipelineParameters = @{}

$rawPortDiversityAutoConcurrency = $RawPortDiversityAutoConcurrency.IsPresent
if ($rawPortDiversityAutoConcurrency -and $ForcePortBatchReadySynthesis.IsPresent) {
    throw 'RawPortDiversityAutoConcurrency cannot be combined with ForcePortBatchReadySynthesis. Run raw mode without synthesis.'
}
if ($rawPortDiversityAutoConcurrency) {
    # LANDMARK: Raw diversity auto concurrency - pass scoped mode to pipeline
    $pipelineParameters['RawPortDiversityAutoConcurrency'] = $true
}

if ($SkipTests.IsPresent) { $pipelineParameters['SkipTests'] = $true }
if ($SkipParsing.IsPresent) { $pipelineParameters['SkipParsing'] = $true }
if ($SkipSchedulerFairnessGuard.IsPresent) {
    $pipelineParameters['FailOnSchedulerFairness'] = $false
    Write-Warning 'Parser scheduler fairness guard disabled for this verification run.'
}
if ($ForcePortBatchReadySynthesis.IsPresent) {
    # LANDMARK: PortBatchReady synthesis - force synthesized batches before diversity guard
    Write-Warning 'PortBatchReady synthesis is enabled; telemetry will be modified in-place and a .bak copy will be created.'
    $pipelineParameters['ForcePortBatchReadySynthesis'] = $true
}
if ($UseBalancedHostOrder.IsPresent) {
    # LANDMARK: Host sweep balancing - pass balanced ordering to the pipeline
    $pipelineParameters['UseBalancedHostOrder'] = $true
}

$queueDelayHarnessPolicy = Resolve-QueueDelayHarnessPolicy -SkipQueueDelayEvaluation:$SkipQueueDelayEvaluation -QueueMetricsPath $QueueMetricsPath
if ($queueDelayHarnessPolicy.ShouldRun) {
    # LANDMARK: Queue gate self-sufficiency - ensure summary exists before evaluation
    $pipelineParameters['RunQueueDelayHarness'] = $true
    Write-Host ("Queue delay harness enabled for verification: {0}" -f $queueDelayHarnessPolicy.Reason) -ForegroundColor DarkCyan
}

function Resolve-OptionalPath {
    param([string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $null }
    try {
        $resolved = (Resolve-Path -LiteralPath $PathValue -ErrorAction Stop).Path
        return $resolved
    } catch {
        if ([System.IO.Path]::IsPathRooted($PathValue)) {
            return [System.IO.Path]::GetFullPath($PathValue)
        }
        $basePath = (Get-Location).ProviderPath
        return [System.IO.Path]::GetFullPath((Join-Path -Path $basePath -ChildPath $PathValue))
    }
}

$resolvedDatabasePath = Resolve-OptionalPath -PathValue $DatabasePath
if ($resolvedDatabasePath) {
    $pipelineParameters['DatabasePath'] = $resolvedDatabasePath
}

function Set-NumericParameter {
    param([string]$Name, [Nullable[int]]$Value)
    if ($Value -ne $null) {
        $pipelineParameters[$Name] = [int]$Value
    }
}

function Get-LatestIngestionMetricsFile {
    param([string]$Directory)

    if ([string]::IsNullOrWhiteSpace($Directory) -or -not (Test-Path -LiteralPath $Directory)) {
        return $null
    }

    $pattern = '^(?:\d{4}-\d{2}-\d{2}|\d{8})$'
    $candidate = Get-ChildItem -Path $Directory -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -match $pattern } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($candidate) {
        return $candidate.FullName
    }

    return $null
}

function Read-InterfacePortQueueEvents {
    param([string]$MetricsPath)

    if ([string]::IsNullOrWhiteSpace($MetricsPath) -or -not (Test-Path -LiteralPath $MetricsPath)) {
        return @()
    }

    $events = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($line in [System.IO.File]::ReadLines($MetricsPath)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line.IndexOf('InterfacePortQueueMetrics', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            try {
                $event = $line | ConvertFrom-Json -ErrorAction Stop
                if ($event -and $event.EventName -eq 'InterfacePortQueueMetrics') {
                    $events.Add($event) | Out-Null
                }
            } catch {
                Write-Warning ("Failed to parse InterfacePortQueueMetrics entry from {0}: {1}" -f $MetricsPath, $_.Exception.Message)
            }
        }
    } catch {
        Write-Warning ("Failed to read ingestion metrics from {0}: {1}" -f $MetricsPath, $_.Exception.Message)
    }

    if ($events.Count -eq 0) {
        return @()
    }

    return ,($events.ToArray())
}

function Resolve-QueueMetricsPath {
    param(
        [string]$ExplicitPath,
        [string]$RepositoryRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return Resolve-OptionalPath -PathValue $ExplicitPath
    }

    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        return $null
    }

    $defaultDirectory = Join-Path -Path $RepositoryRoot -ChildPath 'Logs\IngestionMetrics'
    return Get-LatestIngestionMetricsFile -Directory $defaultDirectory
}

function Get-QueueDelaySummaryPath {
    param(
        [string]$RequestedPath,
        [string]$RepositoryRoot
    )

    $resolved = $null
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $resolved = Resolve-OptionalPath -PathValue $RequestedPath
    }

    if (-not $resolved) {
        if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { return $null }
        $summaryDir = Join-Path -Path $RepositoryRoot -ChildPath 'Logs\IngestionMetrics'
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $resolved = Join-Path -Path $summaryDir -ChildPath ("QueueDelaySummary-{0}.json" -f $timestamp)
    }

    $directory = Split-Path -Path $resolved -Parent
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    return $resolved
}

function Write-QueueDelaySummary {
    param(
        [Parameter(Mandatory = $true)][object]$Evaluation,
        [Parameter(Mandatory = $true)][string]$TelemetryPath,
        [Parameter(Mandatory = $true)][string]$SummaryPath
    )

    $payload = [pscustomobject]@{
        GeneratedAtUtc       = (Get-Date).ToUniversalTime()
        SourceTelemetryPath  = $TelemetryPath
        Pass                 = $Evaluation.Pass
        Result               = $Evaluation.Result
        Thresholds           = $Evaluation.Thresholds
        Statistics           = $Evaluation.Statistics
    }

    $jsonPayload = $payload | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $SummaryPath -Value $jsonPayload -Encoding utf8

    $latestPath = $SummaryPath
    try {
        $summaryDir = Split-Path -Path $SummaryPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($summaryDir)) {
            $latestPath = Join-Path -Path $summaryDir -ChildPath 'QueueDelaySummary-latest.json'
            Set-Content -LiteralPath $latestPath -Value $jsonPayload -Encoding utf8
        }
    } catch {
        Write-Warning ("Failed to update QueueDelaySummary-latest.json: {0}" -f $_.Exception.Message)
    }

    return $SummaryPath
}

# Support dot-sourcing for tests without running the full verification pipeline.
if (Test-Path -LiteralPath variable:global:StateTraceVerificationSkipMain) {
    if ($global:StateTraceVerificationSkipMain) { return }
}

Set-NumericParameter -Name 'ThreadCeilingOverride' -Value $ThreadCeilingOverride
Set-NumericParameter -Name 'MaxWorkersPerSiteOverride' -Value $MaxWorkersPerSiteOverride
Set-NumericParameter -Name 'MaxActiveSitesOverride' -Value $MaxActiveSitesOverride
Set-NumericParameter -Name 'JobsPerThreadOverride' -Value $JobsPerThreadOverride
Set-NumericParameter -Name 'MinRunspacesOverride' -Value $MinRunspacesOverride

if ($QueueDelayMinimumSampleCount -lt 1) {
    $QueueDelayMinimumSampleCount = 1
}

if ($VerboseParsing.IsPresent) { $pipelineParameters['VerboseParsing'] = $true }
if ($ResetExtractedLogs.IsPresent) { $pipelineParameters['ResetExtractedLogs'] = $true }
if ($PreserveModuleSession.IsPresent) { $pipelineParameters['PreserveModuleSession'] = $true }
if ($DisableSharedCacheSnapshot.IsPresent) { $pipelineParameters['DisableSharedCacheSnapshot'] = $true }
if (-not [string]::IsNullOrWhiteSpace($SharedCacheSnapshotDirectory)) {
    $resolvedSnapshotDirectory = Resolve-OptionalPath -PathValue $SharedCacheSnapshotDirectory
    if ($resolvedSnapshotDirectory) {
        $pipelineParameters['SharedCacheSnapshotDirectory'] = $resolvedSnapshotDirectory
    }
}
if ($pipelineParameters.ContainsKey('SharedCacheSnapshotDirectory')) {
    $sharedCacheSnapshotDirectoryUsed = $pipelineParameters['SharedCacheSnapshotDirectory']
} else {
    $sharedCacheSnapshotDirectoryUsed = Join-Path -Path $repositoryRoot -ChildPath 'Logs\SharedCacheSnapshot'
}
if ($ShowSharedCacheSummary.IsPresent) {
    $pipelineParameters['ShowSharedCacheSummary'] = $true
}
if ($RequireSharedCacheSnapshotGuard.IsPresent) {
    $pipelineParameters['ShowSharedCacheSummary'] = $true
}
if ($RequireTelemetryIntegrity.IsPresent) {
    $pipelineParameters['RequireTelemetryIntegrity'] = $true
}

$computedWarmRunPath = $null
$warmRunTelemetryDirectoryUsed = $null
$warmRunSummaryPath = $null
$warmRunSummaryData = $null
$warmRunTimestamp = $null
$diffHotspotReportPath = $null
$shouldGenerateDiffHotspots = $GenerateDiffHotspotReport.IsPresent -or -not [string]::IsNullOrWhiteSpace($DiffHotspotOutputPath)
$sharedCacheDiagnosticsDirectoryResolved = $null
$sharedCacheStoreDiagnosticsPath = $null
$siteCacheProviderDiagnosticsPath = $null
    # LANDMARK: ST-B-007 shared cache diagnostics gating - evaluation state
$sharedCacheDiagnosticsEvaluation = $null
$shouldGenerateSharedCacheDiagnostics = $GenerateSharedCacheDiagnostics.IsPresent -or -not [string]::IsNullOrWhiteSpace($SharedCacheDiagnosticsDirectory)
$warmRunEvaluation = $null
$sharedCacheSnapshotDirectoryUsed = $null
$sharedCacheCoverageOutputPathResolved = $null
$sharedCacheSummaryPath = $null
$sharedCacheSummaryEvaluation = $null
$queueMetricsPathUsed = $null
$queueDelayEvaluation = $null
$queueDelaySummaryPathUsed = $null
$skipWarmRunForRawDiversity = $rawPortDiversityAutoConcurrency
if ($skipWarmRunForRawDiversity -and -not $SkipWarmRunRegression.IsPresent) {
    # LANDMARK: Raw diversity auto concurrency - avoid warm-run regression overrides
    Write-Warning 'Raw port diversity auto concurrency enabled; skipping warm-run regression for this run.'
}
if (-not $SkipWarmRunRegression.IsPresent -and -not $skipWarmRunForRawDiversity) {
    $pipelineParameters['RunWarmRunRegression'] = $true

    $targetPath = $WarmRunRegressionOutputPath
    if ([string]::IsNullOrWhiteSpace($targetPath)) {
        $telemetryDir = $WarmRunTelemetryDirectory
        if ([string]::IsNullOrWhiteSpace($telemetryDir)) {
            $telemetryDir = Join-Path -Path $repositoryRoot -ChildPath 'Logs\IngestionMetrics'
        } else {
            $telemetryDir = Resolve-OptionalPath -PathValue $telemetryDir
        }
        if (-not (Test-Path -LiteralPath $telemetryDir)) {
            New-Item -ItemType Directory -Path $telemetryDir -Force | Out-Null
        }
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $warmRunTimestamp = $timestamp
        $targetPath = Join-Path -Path $telemetryDir -ChildPath ("WarmRunTelemetry-{0}.json" -f $timestamp)
        $warmRunTelemetryDirectoryUsed = $telemetryDir
    } else {
        $targetPath = Resolve-OptionalPath -PathValue $targetPath
        $targetDirectory = Split-Path -Path $targetPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($targetDirectory) -and -not (Test-Path -LiteralPath $targetDirectory)) {
            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        }
        $warmRunTelemetryDirectoryUsed = $targetDirectory
        if (-not $warmRunTimestamp) {
            $leafName = Split-Path -Path $targetPath -Leaf
            $match = [System.Text.RegularExpressions.Regex]::Match($leafName, '(?<ts>\d{8}-\d{6})')
            if ($match.Success) {
                $warmRunTimestamp = $match.Groups['ts'].Value
            } else {
                $warmRunTimestamp = (Get-Date -Format 'yyyyMMdd-HHmmss')
            }
        }
    }

    $computedWarmRunPath = $targetPath
    $pipelineParameters['WarmRunRegressionOutputPath'] = $targetPath
}

$argumentPreview = [System.Collections.Generic.List[string]]::new()
foreach ($entry in $pipelineParameters.GetEnumerator()) {
    if ($entry.Value -is [bool]) {
        if ($entry.Value) {
            [void]$argumentPreview.Add(("-{0}" -f $entry.Key))
        }
    } else {
        [void]$argumentPreview.Add(("-{0}={1}" -f $entry.Key, $entry.Value))
    }
}

if ($argumentPreview.Count -gt 0) {
    Write-Host ("Pipeline arguments: {0}" -f ($argumentPreview -join ' ')) -ForegroundColor DarkGray
} else {
    Write-Host 'Pipeline arguments: (none)' -ForegroundColor DarkGray
}
Write-Host 'Starting StateTrace verification pipeline...' -ForegroundColor Cyan
try {
    & $pipelineScript @pipelineParameters
} catch {
    Write-Host 'StateTrace verification pipeline failed.' -ForegroundColor Red
    throw
}

Write-Host 'StateTrace verification pipeline completed successfully.' -ForegroundColor Green
if (-not [string]::IsNullOrWhiteSpace($sharedCacheSnapshotDirectoryUsed) -and (Test-Path -LiteralPath $sharedCacheSnapshotDirectoryUsed)) {
    $sharedCacheSummaryPath = Join-Path -Path $sharedCacheSnapshotDirectoryUsed -ChildPath 'SharedCacheSnapshot-latest-summary.json'
    try {
        $latestSummaryFile = Get-ChildItem -Path $sharedCacheSnapshotDirectoryUsed -Filter 'SharedCacheSnapshot-*-summary.json' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($latestSummaryFile) {
            $sharedCacheSummaryPath = $latestSummaryFile.FullName
        }
    } catch {
        Write-Warning ("Failed to enumerate shared-cache summaries under '{0}': {1}" -f $sharedCacheSnapshotDirectoryUsed, $_.Exception.Message)
    }
} elseif (-not $DisableSharedCacheSnapshot.IsPresent) {
    $sharedCacheSummaryPath = Join-Path -Path $repositoryRoot -ChildPath 'Logs\SharedCacheSnapshot\SharedCacheSnapshot-latest-summary.json'
}

if ($computedWarmRunPath) {
    Write-Host ("Warm-run regression telemetry stored at {0}" -f $computedWarmRunPath) -ForegroundColor DarkYellow
    if (-not [string]::IsNullOrWhiteSpace($warmRunTelemetryDirectoryUsed)) {
        $latestTelemetryPath = Join-Path -Path $warmRunTelemetryDirectoryUsed -ChildPath 'WarmRunTelemetry-latest.json'
        try {
            if ($latestTelemetryPath -ne $computedWarmRunPath) {
                Copy-Item -LiteralPath $computedWarmRunPath -Destination $latestTelemetryPath -Force
            }
        } catch {
            Write-Warning ("Failed to update warm-run telemetry latest pointer: {0}" -f $_.Exception.Message)
        }
        try {
            $telemetryObjects = Read-ToolingJson -Path $computedWarmRunPath -Label 'Warm-run telemetry' -FilterScript {
                param($obj)
                $obj -and $obj.PassLabel -eq 'WarmRunComparison' -and $obj.SummaryType -eq 'InterfaceCallDuration'
            }
            if ($telemetryObjects) {
                if ($telemetryObjects -is [System.Collections.IEnumerable] -and -not ($telemetryObjects -is [string])) {
                    $comparison = $telemetryObjects | Select-Object -First 1
                } else {
                    $comparison = $telemetryObjects
                }
                if ($null -ne $comparison) {
                    $warmRunSummaryData = [pscustomobject]@{
                        GeneratedAtUtc                = (Get-Date).ToUniversalTime()
                        ColdInterfaceCallAvgMs        = $comparison.ColdInterfaceCallAvgMs
                        ColdInterfaceCallP95Ms        = $comparison.ColdInterfaceCallP95Ms
                        ColdInterfaceCallMaxMs        = $comparison.ColdInterfaceCallMaxMs
                        WarmInterfaceCallAvgMs        = $comparison.WarmInterfaceCallAvgMs
                        WarmInterfaceCallP95Ms        = $comparison.WarmInterfaceCallP95Ms
                        WarmInterfaceCallMaxMs        = $comparison.WarmInterfaceCallMaxMs
                        ImprovementAverageMs          = $comparison.ImprovementAverageMs
                        ImprovementPercent            = $comparison.ImprovementPercent
                        WarmCacheProviderHitCount     = $comparison.WarmCacheProviderHitCount
                        WarmCacheProviderMissCount    = $comparison.WarmCacheProviderMissCount
                        WarmCacheHitRatioPercent      = $comparison.WarmCacheHitRatioPercent
                        WarmSignatureMatchMissCount   = $comparison.WarmSignatureMatchMissCount
                        WarmSignatureRewriteTotal     = $comparison.WarmSignatureRewriteTotal
                        WarmProviderCounts            = $comparison.WarmProviderCounts
                        ColdProviderCounts            = $comparison.ColdProviderCounts
                        TelemetryPath                 = $computedWarmRunPath
                    }
                    $warmRunSummaryPath = Join-Path -Path $warmRunTelemetryDirectoryUsed -ChildPath 'WarmRunTelemetry-latest-summary.json'
                    $warmRunSummaryData | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $warmRunSummaryPath -Encoding utf8
                    Write-Host ("Warm-run regression summary stored at {0}" -f $warmRunSummaryPath) -ForegroundColor DarkYellow
                } else {
                    Write-Warning 'Warm-run telemetry did not include an InterfaceCallDuration summary; summary export skipped.'
                }
            }
        } catch {
            Write-Warning ("Failed to process warm-run telemetry: {0}" -f $_.Exception.Message)
        }
    }

    if ($warmRunSummaryData -and -not $SkipWarmRunAssertions.IsPresent) {
        Ensure-VerificationModuleLoaded -ModulePath $verificationModulePath

        $warmRunEvaluation = Test-WarmRunRegressionSummary -Summary $warmRunSummaryData `
            -MinimumImprovementPercent $WarmRunMinimumImprovementPercent `
            -MinimumCacheHitRatioPercent $WarmRunMinimumCacheHitRatioPercent `
            -MaximumWarmCacheMissCount $WarmRunMaximumCacheMissCount `
            -MaximumSignatureMissCount $WarmRunMaximumSignatureMissCount `
            -MaximumSignatureRewriteTotal $WarmRunMaximumSignatureRewriteTotal `
            -MaximumWarmAverageDeltaMs $WarmRunMaximumWarmAverageDeltaMs

        if (-not $warmRunEvaluation.Pass) {
            foreach ($message in $warmRunEvaluation.Messages) {
                Write-Warning $message
            }
            $violationList = if ($warmRunEvaluation.Violations.Count -gt 0) {
                [string]::Join(', ', $warmRunEvaluation.Violations)
            } else {
                'Unknown'
            }
            throw ("Warm-run regression failed verification (violations: {0})." -f $violationList)
        }
        if ($warmRunSummaryData -and $warmRunEvaluation.Thresholds) {
            $warmRunSummaryData | Add-Member -NotePropertyName 'PolicyThresholds' -NotePropertyValue $warmRunEvaluation.Thresholds -Force
        }
    }
}

if ($shouldGenerateDiffHotspots) {
    if ($computedWarmRunPath -and (Test-Path -LiteralPath $computedWarmRunPath)) {
        $analyzerScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Analyze-WarmRunDiffHotspots.ps1'
        if (-not (Test-Path -LiteralPath $analyzerScript)) {
            throw "Unable to locate diff hotspot analyzer at '$analyzerScript'."
        }

        $diffOutputPath = $DiffHotspotOutputPath
        if ([string]::IsNullOrWhiteSpace($diffOutputPath)) {
            $diffDir = if ($warmRunTelemetryDirectoryUsed) { $warmRunTelemetryDirectoryUsed } else { Split-Path -Path $computedWarmRunPath -Parent }
            if ([string]::IsNullOrWhiteSpace($diffDir)) {
                $diffDir = Join-Path -Path $repositoryRoot -ChildPath 'Logs\IngestionMetrics'
            }
            $diffTimestamp = if ($warmRunTimestamp) { $warmRunTimestamp } else { Get-Date -Format 'yyyyMMdd-HHmmss' }
            $diffOutputPath = Join-Path -Path $diffDir -ChildPath ("DiffHotspots-{0}.csv" -f $diffTimestamp)
        } else {
            $diffOutputPath = Resolve-OptionalPath -PathValue $diffOutputPath
        }

        $diffDirEnsure = Split-Path -Path $diffOutputPath -Parent
        if ($diffDirEnsure -and -not (Test-Path -LiteralPath $diffDirEnsure)) {
            New-Item -ItemType Directory -Path $diffDirEnsure -Force | Out-Null
        }

        try {
            & $analyzerScript -TelemetryPath $computedWarmRunPath -Top $DiffHotspotTop -OutputPath $diffOutputPath
            if ($LASTEXITCODE -ne 0) {
                throw "Analyze-WarmRunDiffHotspots exited with code $LASTEXITCODE."
            }
            $diffHotspotReportPath = (Resolve-Path -LiteralPath $diffOutputPath -ErrorAction Stop).Path
            if (-not $QuietSummary.IsPresent) {
                Write-Host ("Warm-run diff hotspot report stored at {0}" -f $diffHotspotReportPath) -ForegroundColor DarkYellow
            }
        } catch {
            throw ("Failed to generate warm-run diff hotspot report: {0}" -f $_.Exception.Message)
        }
    } else {
        Write-Warning 'Skipped diff hotspot report generation because warm-run telemetry was unavailable.'
    }
}

if ($shouldGenerateSharedCacheDiagnostics -and -not $queueMetricsPathUsed) {
    $queueMetricsPathUsed = Resolve-QueueMetricsPath -ExplicitPath $QueueMetricsPath -RepositoryRoot $repositoryRoot
}

if (-not $SkipQueueDelayEvaluation.IsPresent) {
    $queueMetricsPathUsed = Resolve-QueueMetricsPath -ExplicitPath $QueueMetricsPath -RepositoryRoot $repositoryRoot
    if (-not $queueMetricsPathUsed) {
        throw 'Queue delay evaluation could not locate an ingestion metrics file. Provide -QueueMetricsPath explicitly or ensure Logs\IngestionMetrics contains a dated JSON export.'
    }
    if (-not (Test-Path -LiteralPath $queueMetricsPathUsed)) {
        throw ("Queue delay evaluation file '{0}' was not found." -f $queueMetricsPathUsed)
    }

    # LANDMARK: Gate artifact traceability - log exact input paths used for evaluation
    Write-Host ("Queue delay evaluation metrics file: {0}" -f $queueMetricsPathUsed) -ForegroundColor DarkCyan
    $queueEvents = Read-InterfacePortQueueEvents -MetricsPath $queueMetricsPathUsed
    $queueEventCount = if ($queueEvents) { $queueEvents.Count } else { 0 }
    Ensure-VerificationModuleLoaded -ModulePath $verificationModulePath
    $queueDelayEvaluation = Test-InterfacePortQueueDelay -Events $queueEvents `
        -MaximumP95Ms $QueueDelayP95Maximum `
        -MaximumP99Ms $QueueDelayP99Maximum `
        -MinimumEventCount $QueueDelayMinimumSampleCount

    $delayStats = $null
    if ($queueDelayEvaluation -and $queueDelayEvaluation.Statistics -and $queueDelayEvaluation.Statistics.QueueBuildDelayMs) {
        $delayStats = $queueDelayEvaluation.Statistics.QueueBuildDelayMs
        $avgDisplay = if ($delayStats.Average -ne $null) { ('{0:N3}' -f $delayStats.Average) } else { 'n/a' }
        $p95Display = if ($delayStats.P95 -ne $null) { ('{0:N3}' -f $delayStats.P95) } else { 'n/a' }
        $p99Display = if ($delayStats.P99 -ne $null) { ('{0:N3}' -f $delayStats.P99) } else { 'n/a' }
        $maxDisplay = if ($delayStats.Max -ne $null) { ('{0:N3}' -f $delayStats.Max) } else { 'n/a' }
        Write-Host 'InterfacePortQueueMetrics evaluation:' -ForegroundColor Yellow
        Write-Host ("  Source file             : {0}" -f $queueMetricsPathUsed) -ForegroundColor Yellow
        Write-Host ("  Samples                 : {0}" -f $delayStats.SampleCount) -ForegroundColor Yellow
        Write-Host ("  Minimum samples required: {0}" -f $QueueDelayMinimumSampleCount) -ForegroundColor Yellow
        Write-Host ("  Queue delay avg/p95/p99/max (ms): {0} / {1} / {2} / {3}" -f $avgDisplay, $p95Display, $p99Display, $maxDisplay) -ForegroundColor Yellow
    }

    if ($queueDelayEvaluation -and $queueDelayEvaluation.Result -eq 'InsufficientData') {
        # LANDMARK: Queue delay sample floor - fail verification on insufficient samples
        $reportedCount = $queueEventCount
        if ($delayStats -and $delayStats.SampleCount -ne $null) {
            $reportedCount = $delayStats.SampleCount
        }
        throw ("Queue delay evaluation found {0} InterfacePortQueueMetrics sample(s) in '{1}' (need at least {2})." -f $reportedCount, $queueMetricsPathUsed, $QueueDelayMinimumSampleCount)
    }

    if ($queueDelayEvaluation -and -not $queueDelayEvaluation.Pass) {
        foreach ($message in $queueDelayEvaluation.Messages) {
            Write-Warning $message
        }
        $queueViolationList = if ($queueDelayEvaluation.Violations -and $queueDelayEvaluation.Violations.Count -gt 0) {
            $queueDelayEvaluation.Violations -join ', '
        } else {
            'Unknown'
        }
        throw ("InterfacePortQueueMetrics queue delay gate failed (violations: {0})." -f $queueViolationList)
    }

    if ($queueDelayEvaluation -and $queueDelayEvaluation.Pass -and -not $SkipQueueDelaySummaryExport.IsPresent) {
        $queueDelaySummaryPathUsed = Get-QueueDelaySummaryPath -RequestedPath $QueueDelaySummaryPath -RepositoryRoot $repositoryRoot
        if ($queueDelaySummaryPathUsed) {
            try {
                Write-QueueDelaySummary -Evaluation $queueDelayEvaluation -TelemetryPath $queueMetricsPathUsed -SummaryPath $queueDelaySummaryPathUsed | Out-Null
                Write-Host ("Queue delay summary stored at {0}" -f $queueDelaySummaryPathUsed) -ForegroundColor DarkYellow
            } catch {
                Write-Warning ("Failed to write queue delay summary: {0}" -f $_.Exception.Message)
                $queueDelaySummaryPathUsed = $null
            }
        }
    }
}

$sharedCacheSummaryDefaultPath = Join-Path -Path $repositoryRoot -ChildPath 'Logs\SharedCacheSnapshot\SharedCacheSnapshot-latest-summary.json'
if ($shouldGenerateSharedCacheDiagnostics) {
    if (-not $queueMetricsPathUsed -or -not (Test-Path -LiteralPath $queueMetricsPathUsed)) {
        Write-Warning 'Shared-cache diagnostics skipped because queue/ingestion metrics were not available.'
    } else {
        $sharedCacheDiagnosticsDirectoryResolved = $SharedCacheDiagnosticsDirectory
        if ([string]::IsNullOrWhiteSpace($sharedCacheDiagnosticsDirectoryResolved)) {
            $sharedCacheDiagnosticsDirectoryResolved = Join-Path -Path $repositoryRoot -ChildPath 'Logs\SharedCacheDiagnostics'
        } else {
            $sharedCacheDiagnosticsDirectoryResolved = Resolve-OptionalPath -PathValue $sharedCacheDiagnosticsDirectoryResolved
        }

        if (-not (Test-Path -LiteralPath $sharedCacheDiagnosticsDirectoryResolved)) {
            New-Item -ItemType Directory -Path $sharedCacheDiagnosticsDirectoryResolved -Force | Out-Null
        }

        $diagTimestamp = if ($warmRunTimestamp) { $warmRunTimestamp } else { Get-Date -Format 'yyyyMMdd-HHmmss' }

        $sharedCacheStoreScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Analyze-SharedCacheStoreState.ps1'
        if (-not (Test-Path -LiteralPath $sharedCacheStoreScript)) {
            throw "Unable to locate Analyze-SharedCacheStoreState.ps1 at '$sharedCacheStoreScript'."
        }

        $siteCacheProviderScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Analyze-SiteCacheProviderReasons.ps1'
        if (-not (Test-Path -LiteralPath $siteCacheProviderScript)) {
            throw "Unable to locate Analyze-SiteCacheProviderReasons.ps1 at '$siteCacheProviderScript'."
        }

        $storeSummary = $null
        $providerSummary = $null
        try {
            $storeSummary = & $sharedCacheStoreScript -Path $queueMetricsPathUsed -IncludeSiteBreakdown
            $sharedCacheStoreDiagnosticsPath = Join-Path -Path $sharedCacheDiagnosticsDirectoryResolved -ChildPath ("SharedCacheStoreState-{0}.json" -f $diagTimestamp)
            $storeSummary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $sharedCacheStoreDiagnosticsPath -Encoding utf8
            if (-not $QuietSummary.IsPresent) {
                Write-Host ("Shared-cache store diagnostics written to {0}" -f $sharedCacheStoreDiagnosticsPath) -ForegroundColor DarkYellow
            }
        } catch {
            throw ("Failed to generate shared-cache store diagnostics: {0}" -f $_.Exception.Message)
        }

        try {
            $providerSummary = & $siteCacheProviderScript -Path $queueMetricsPathUsed
            $siteCacheProviderDiagnosticsPath = Join-Path -Path $sharedCacheDiagnosticsDirectoryResolved -ChildPath ("SiteCacheProviderReasons-{0}.json" -f $diagTimestamp)
            $providerSummary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $siteCacheProviderDiagnosticsPath -Encoding utf8
            if (-not $QuietSummary.IsPresent) {
                Write-Host ("Site cache provider diagnostics written to {0}" -f $siteCacheProviderDiagnosticsPath) -ForegroundColor DarkYellow
            }
        } catch {
            throw ("Failed to generate site cache provider diagnostics: {0}" -f $_.Exception.Message)
        }

        # LANDMARK: ST-B-007 shared cache diagnostics gating - fail on snapshot/import or access refresh
        Ensure-VerificationModuleLoaded -ModulePath $verificationModulePath
        $sharedCacheDiagnosticsEvaluation = VerificationModule\Test-SharedCacheDiagnostics -StoreSummary $storeSummary -ProviderSummary $providerSummary
        if (-not $sharedCacheDiagnosticsEvaluation.Pass) {
            $failureSummary = $sharedCacheDiagnosticsEvaluation.Messages -join ' '
            throw ("Shared-cache diagnostics failed: {0}" -f $failureSummary)
        }
    }
}

if (-not $sharedCacheSummaryPath) {
    $sharedCacheSummaryPath = $sharedCacheSummaryDefaultPath
}

if (-not [string]::IsNullOrWhiteSpace($SharedCacheCoverageOutputPath)) {
    $sharedCacheCoverageOutputPathResolved = Resolve-OptionalPath -PathValue $SharedCacheCoverageOutputPath
} elseif ($sharedCacheSummaryPath) {
    try {
        $summaryDir = Split-Path -Parent $sharedCacheSummaryPath
        if (-not [string]::IsNullOrWhiteSpace($summaryDir)) {
            $sharedCacheCoverageOutputPathResolved = Join-Path -Path $summaryDir -ChildPath 'SharedCacheCoverage-latest.json'
        }
    } catch { }
}

if ($RequireSharedCacheSnapshotGuard.IsPresent) {
    $snapshotGuardScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Test-SharedCacheSnapshot.ps1'
    if (-not (Test-Path -LiteralPath $snapshotGuardScript)) {
        throw "Shared cache snapshot guard script not found at $snapshotGuardScript"
    }

    $snapshotTarget = $sharedCacheSummaryPath
    if (-not ($snapshotTarget -and (Test-Path -LiteralPath $snapshotTarget))) {
        if (-not [string]::IsNullOrWhiteSpace($sharedCacheSnapshotDirectoryUsed) -and (Test-Path -LiteralPath $sharedCacheSnapshotDirectoryUsed)) {
            $latestSummaryFile = Get-ChildItem -Path $sharedCacheSnapshotDirectoryUsed -Filter 'SharedCacheSnapshot-*-summary.json' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($latestSummaryFile) { $snapshotTarget = $latestSummaryFile.FullName }
        }
    }

    if (-not ($snapshotTarget -and (Test-Path -LiteralPath $snapshotTarget))) {
        throw "Shared cache snapshot guard requested but no summary file was found. Run warmup to produce snapshots before verification."
    }

    $guardParams = @(
        '-File', $snapshotGuardScript,
        '-Path', $snapshotTarget,
        '-MinimumSiteCount', $SharedCacheMinimumSiteCount,
        '-MinimumHostCount', $SharedCacheMinimumHostCount,
        '-MinimumTotalRowCount', $SharedCacheMinimumTotalRowCount,
        '-PassThru'
    )
    if ($SharedCacheRequiredSites -and $SharedCacheRequiredSites.Count -gt 0) {
        $guardParams += @('-RequiredSites')
        $guardParams += @($SharedCacheRequiredSites)
    }

    Write-Host ("Shared cache snapshot guard: validating {0}..." -f $snapshotTarget) -ForegroundColor Cyan
    $guardResult = & pwsh @guardParams
    if ($LASTEXITCODE -ne 0) {
        throw "Shared cache snapshot guard failed. See console output above."
    }

    $guardSummaryPath = $null
    if ($guardResult) {
        try {
            $guardTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $targetDir = Split-Path -Parent $snapshotTarget
            if (-not [string]::IsNullOrWhiteSpace($targetDir)) {
                $guardSummaryPath = Join-Path -Path $targetDir -ChildPath ("SharedCacheSnapshotGuard-{0}.json" -f $guardTimestamp)
                $guardResult | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $guardSummaryPath -Encoding utf8
            }
        } catch {
            Write-Warning ("Failed to write shared cache snapshot guard summary: {0}" -f $_.Exception.Message)
            $guardSummaryPath = $null
        }
    }
}

if (-not $SkipSharedCacheSummaryEvaluation.IsPresent) {
    $snapshotSummaryExists = $sharedCacheSummaryPath -and (Test-Path -LiteralPath $sharedCacheSummaryPath)
    if ($DisableSharedCacheSnapshot.IsPresent -and -not $snapshotSummaryExists) {
        Write-Warning 'Shared-cache summary evaluation skipped because snapshots were disabled and no summary was generated.'
    } else {
        Ensure-VerificationModuleLoaded -ModulePath $verificationModulePath
        $sharedCacheSummaryEvaluation = Test-SharedCacheSummaryCoverage -Summary $sharedCacheSummaryPath `
            -MinimumSiteCount $SharedCacheMinimumSiteCount `
            -MinimumHostCount $SharedCacheMinimumHostCount `
            -MinimumTotalRowCount $SharedCacheMinimumTotalRowCount `
            -RequiredSites $SharedCacheRequiredSites

        if (-not $QuietSummary.IsPresent -and $sharedCacheSummaryEvaluation) {
            $stats = $sharedCacheSummaryEvaluation.Statistics
            $statusColor = if ($sharedCacheSummaryEvaluation.Pass) { 'Green' } else { 'Red' }
            Write-Host 'Shared-cache summary evaluation:' -ForegroundColor Yellow
            Write-Host ("  Summary Path            : {0}" -f $sharedCacheSummaryPath) -ForegroundColor Yellow
            if ($stats) {
                Write-Host ("  Site Count / Hosts / Rows : {0} / {1} / {2}" -f $stats.SiteCount, $stats.TotalHostCount, $stats.TotalRowCount) -ForegroundColor Yellow
            }
            $summaryStatus = if ($sharedCacheSummaryEvaluation.Pass) { 'Pass' } else { 'Fail' }
            Write-Host ("  Status                  : {0}" -f $summaryStatus) -ForegroundColor $statusColor
            if (-not $sharedCacheSummaryEvaluation.Pass -and $sharedCacheSummaryEvaluation.Messages) {
                foreach ($msg in $sharedCacheSummaryEvaluation.Messages) {
                    Write-Host ("  - {0}" -f $msg) -ForegroundColor Red
                }
            }
        }

        if ($sharedCacheSummaryEvaluation -and -not $sharedCacheSummaryEvaluation.Pass) {
            foreach ($message in $sharedCacheSummaryEvaluation.Messages) {
                Write-Warning $message
            }
            $violationSummary = if ($sharedCacheSummaryEvaluation.Violations.Count -gt 0) { ($sharedCacheSummaryEvaluation.Violations -join ', ') } else { 'Unknown' }
            throw ("Shared-cache summary failed verification (violations: {0})." -f $violationSummary)
        }

        if ($sharedCacheSummaryEvaluation -and -not [string]::IsNullOrWhiteSpace($sharedCacheCoverageOutputPathResolved)) {
            try {
                $coverageDir = Split-Path -Parent $sharedCacheCoverageOutputPathResolved
                if (-not [string]::IsNullOrWhiteSpace($coverageDir) -and -not (Test-Path -LiteralPath $coverageDir)) {
                    New-Item -ItemType Directory -Path $coverageDir -Force | Out-Null
                }
                $coveragePayload = [pscustomobject]@{
                    GeneratedAtUtc = (Get-Date).ToUniversalTime()
                    SummaryPath    = $sharedCacheSummaryPath
                    Evaluation     = $sharedCacheSummaryEvaluation
                }
                $coveragePayload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $sharedCacheCoverageOutputPathResolved -Encoding utf8
                if (-not $QuietSummary.IsPresent) {
                    Write-Host ("Shared-cache coverage summary stored at {0}" -f $sharedCacheCoverageOutputPathResolved) -ForegroundColor DarkYellow
                }
            } catch {
                Write-Warning ("Failed to write shared-cache coverage summary: {0}" -f $_.Exception.Message)
                $sharedCacheCoverageOutputPathResolved = $null
            }
        }
    }
}

$bundleReadinessResults = $null
if ($VerifyTelemetryBundleReadiness.IsPresent -or -not [string]::IsNullOrWhiteSpace($TelemetryBundlePath)) {
    if ([string]::IsNullOrWhiteSpace($TelemetryBundlePath)) {
        throw 'Specify -TelemetryBundlePath when requesting telemetry bundle readiness verification.'
    }

    $bundleScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Test-TelemetryBundleReadiness.ps1'
    if (-not (Test-Path -LiteralPath $bundleScript)) {
        throw "Telemetry bundle readiness script not found at $bundleScript."
    }

    $resolvedBundlePath = (Resolve-Path -LiteralPath $TelemetryBundlePath -ErrorAction Stop).Path
    $bundleParams = @{
        BundlePath = $resolvedBundlePath
        PassThru   = $true
    }
    if ($TelemetryBundleAreas -and $TelemetryBundleAreas.Count -gt 0) {
        $bundleParams['Area'] = $TelemetryBundleAreas
    }

    $bundleReadinessResults = & $bundleScript @bundleParams
    if (-not $bundleReadinessResults) {
        throw "Telemetry bundle readiness script returned no results for '$resolvedBundlePath'."
    }

    $missingArtifacts = @($bundleReadinessResults | Where-Object { $_.Status -eq 'Missing' })
    if ($missingArtifacts.Count -gt 0) {
        $summary = $missingArtifacts | Format-Table Area, Requirement -AutoSize | Out-String
        throw ("Telemetry bundle readiness failed:`n{0}" -f $summary)
    }

    $optionalMissing = @($bundleReadinessResults | Where-Object { $_.Status -like 'Missing*Optional*' })
    if ($optionalMissing.Count -gt 0) {
        $names = $optionalMissing | ForEach-Object { '{0}:{1}' -f $_.Area, $_.Requirement }
        Write-Warning ("Telemetry bundle readiness: optional artifacts missing ({0})." -f ($names -join ', '))
    }

    if (-not $QuietSummary.IsPresent) {
        $areas = ($bundleReadinessResults.Area | Sort-Object -Unique) -join ', '
        Write-Host ("Telemetry bundle readiness passed ({0})" -f $areas) -ForegroundColor Green
    }
}

if ($PassThru.IsPresent) {
    [pscustomobject]@{
        WarmRunTelemetryPath = $computedWarmRunPath
        WarmRunTelemetrySummaryPath = $warmRunSummaryPath
        WarmRunSummary      = $warmRunSummaryData
        WarmRunEvaluation   = $warmRunEvaluation
        QueueMetricsPath    = $queueMetricsPathUsed
        QueueDelayEvaluation = $queueDelayEvaluation
        QueueDelaySummaryPath = $queueDelaySummaryPathUsed
        SharedCacheSnapshotDirectory = $sharedCacheSnapshotDirectoryUsed
        SharedCacheSummaryPath = $sharedCacheSummaryPath
        SharedCacheCoveragePath = $sharedCacheCoverageOutputPathResolved
        SharedCacheSnapshotGuardPath = $guardSummaryPath
        SharedCacheSummaryEvaluation = $sharedCacheSummaryEvaluation
        SharedCacheDiagnosticsDirectory = $sharedCacheDiagnosticsDirectoryResolved
        SharedCacheStoreDiagnosticsPath = $sharedCacheStoreDiagnosticsPath
        SiteCacheProviderDiagnosticsPath = $siteCacheProviderDiagnosticsPath
        # LANDMARK: ST-B-007 shared cache diagnostics gating - surface evaluation
        SharedCacheDiagnosticsEvaluation = $sharedCacheDiagnosticsEvaluation
        DiffHotspotReportPath = $diffHotspotReportPath
        TelemetryBundleReadiness = $bundleReadinessResults
        Parameters           = $pipelineParameters
    }
}
