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
[switch]$SkipWarmRunRegression,
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
    [switch]$SkipWarmRunAssertions,
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

function Ensure-VerificationModuleLoaded {
    param([Parameter(Mandatory)][string]$ModulePath)

    if (-not (Get-Module -Name VerificationModule)) {
        if (-not (Test-Path -LiteralPath $ModulePath)) {
            throw "Verification module not found at $ModulePath."
        }
        Import-Module -Name $ModulePath -Force
    }
}

$pipelineParameters = @{}

if ($SkipTests.IsPresent) { $pipelineParameters['SkipTests'] = $true }
if ($SkipParsing.IsPresent) { $pipelineParameters['SkipParsing'] = $true }

function Resolve-OptionalPath {
    param([string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $null }
    try {
        $resolved = (Resolve-Path -LiteralPath $PathValue -ErrorAction Stop).Path
        return $resolved
    } catch {
        return [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location) -ChildPath $PathValue))
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

Set-NumericParameter -Name 'ThreadCeilingOverride' -Value $ThreadCeilingOverride
Set-NumericParameter -Name 'MaxWorkersPerSiteOverride' -Value $MaxWorkersPerSiteOverride
Set-NumericParameter -Name 'MaxActiveSitesOverride' -Value $MaxActiveSitesOverride
Set-NumericParameter -Name 'JobsPerThreadOverride' -Value $JobsPerThreadOverride
Set-NumericParameter -Name 'MinRunspacesOverride' -Value $MinRunspacesOverride

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

$computedWarmRunPath = $null
$warmRunTelemetryDirectoryUsed = $null
$warmRunSummaryPath = $null
$warmRunSummaryData = $null
$warmRunEvaluation = $null
$sharedCacheSnapshotDirectoryUsed = $null
$sharedCacheCoverageOutputPathResolved = $null
$sharedCacheSummaryPath = $null
$sharedCacheSummaryEvaluation = $null
if (-not $SkipWarmRunRegression.IsPresent) {
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
        $targetPath = Join-Path -Path $telemetryDir -ChildPath ("WarmRunTelemetry-{0}.json" -f $timestamp)
        $warmRunTelemetryDirectoryUsed = $telemetryDir
    } else {
        $targetPath = Resolve-OptionalPath -PathValue $targetPath
        $targetDirectory = Split-Path -Path $targetPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($targetDirectory) -and -not (Test-Path -LiteralPath $targetDirectory)) {
            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        }
        $warmRunTelemetryDirectoryUsed = $targetDirectory
    }

    $computedWarmRunPath = $targetPath
    $relativeOutput = $targetPath
    try {
        $candidate = [System.IO.Path]::GetRelativePath($repositoryRoot, $targetPath)
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $candidate.StartsWith('..')) {
            $relativeOutput = $candidate
        }
    } catch {
        $relativeOutput = $targetPath
    }
    $pipelineParameters['WarmRunRegressionOutputPath'] = $relativeOutput
}

$argumentPreview = @()
foreach ($entry in $pipelineParameters.GetEnumerator()) {
    if ($entry.Value -is [bool]) {
        if ($entry.Value) {
            $argumentPreview += ("-{0}" -f $entry.Key)
        }
    } else {
        $argumentPreview += ("-{0}={1}" -f $entry.Key, $entry.Value)
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
            $rawTelemetry = Get-Content -LiteralPath $computedWarmRunPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($rawTelemetry)) {
                $telemetryObjects = $rawTelemetry | ConvertFrom-Json
                $comparison = $telemetryObjects | Where-Object {
                    $_.PassLabel -eq 'WarmRunComparison' -and $_.SummaryType -eq 'InterfaceCallDuration'
                } | Select-Object -First 1
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

$sharedCacheSummaryDefaultPath = Join-Path -Path $repositoryRoot -ChildPath 'Logs\SharedCacheSnapshot\SharedCacheSnapshot-latest-summary.json'
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
            Write-Host ("  Status                  : {0}" -f ($sharedCacheSummaryEvaluation.Pass ? 'Pass' : 'Fail')) -ForegroundColor $statusColor
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

if ($PassThru.IsPresent) {
    [pscustomobject]@{
        WarmRunTelemetryPath = $computedWarmRunPath
        WarmRunTelemetrySummaryPath = $warmRunSummaryPath
        WarmRunSummary      = $warmRunSummaryData
        WarmRunEvaluation   = $warmRunEvaluation
        SharedCacheSnapshotDirectory = $sharedCacheSnapshotDirectoryUsed
        SharedCacheSummaryPath = $sharedCacheSummaryPath
        SharedCacheCoveragePath = $sharedCacheCoverageOutputPathResolved
        SharedCacheSummaryEvaluation = $sharedCacheSummaryEvaluation
        Parameters           = $pipelineParameters
    }
}
