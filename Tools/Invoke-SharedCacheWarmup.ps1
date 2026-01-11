[CmdletBinding()]
param(
    [switch]$ResetExtractedLogs,
    [switch]$VerboseParsing,
    [switch]$RunWarmRunRegression,
    [switch]$IncludeTests,
    [string]$SharedCacheSnapshotDirectory,
    [string[]]$RequiredSites,
    [int]$MinimumSiteCount = 1,
    [int]$MinimumHostCount = 1,
    [int]$MinimumTotalRowCount = 1,
    [switch]$RequireTelemetryIntegrity,
    [switch]$SkipCoverageValidation,
    [switch]$PreserveSkipSiteCacheSetting,
    [switch]$PreserveIngestionHistory,
    [switch]$SkipSchedulerFairnessGuard,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skipSiteCacheGuardModule = Join-Path -Path $PSScriptRoot -ChildPath 'SkipSiteCacheUpdateGuard.psm1'
if (-not (Test-Path -LiteralPath $skipSiteCacheGuardModule)) {
    throw "Skip-site-cache guard module not found at $skipSiteCacheGuardModule."
}
Import-Module -Name $skipSiteCacheGuardModule -Force -ErrorAction Stop

$toolingJsonPath = Join-Path -Path $PSScriptRoot -ChildPath 'ToolingJson.psm1'
if (-not (Test-Path -LiteralPath $toolingJsonPath)) {
    throw "ToolingJson module not found at '$toolingJsonPath'."
}
Import-Module -Name $toolingJsonPath -Force -ErrorAction Stop

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$pipelineScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Invoke-StateTracePipeline.ps1'
if (-not (Test-Path -LiteralPath $pipelineScript)) {
    throw "Pipeline harness not found at $pipelineScript."
}
$verificationModulePath = Join-Path -Path $repositoryRoot -ChildPath 'Modules\VerificationModule.psm1'

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

function Ensure-VerificationModuleLoaded {
    param([Parameter(Mandatory)][string]$ModulePath)

    if (-not (Get-Module -Name VerificationModule)) {
        if (-not (Test-Path -LiteralPath $ModulePath)) {
            throw "Verification module not found at $ModulePath."
        }
        Import-Module -Name $ModulePath -Force
    }
}

$pipelineParameters = @{ ShowSharedCacheSummary = $true }
if (-not $IncludeTests.IsPresent) {
    $pipelineParameters['SkipTests'] = $true
}
if ($ResetExtractedLogs.IsPresent) { $pipelineParameters['ResetExtractedLogs'] = $true }
if ($VerboseParsing.IsPresent) { $pipelineParameters['VerboseParsing'] = $true }
if ($RunWarmRunRegression.IsPresent) { $pipelineParameters['RunWarmRunRegression'] = $true }
if ($RequireTelemetryIntegrity.IsPresent) { $pipelineParameters['RequireTelemetryIntegrity'] = $true }
if ($SharedCacheSnapshotDirectory) {
    $resolvedSnapshotDir = Resolve-OptionalPath -PathValue $SharedCacheSnapshotDirectory
    if ($resolvedSnapshotDir) {
        $pipelineParameters['SharedCacheSnapshotDirectory'] = $resolvedSnapshotDir
    }
}
if ($SkipSchedulerFairnessGuard.IsPresent) {
    $pipelineParameters['FailOnSchedulerFairness'] = $false
    Write-Warning '[SharedCacheWarmup] Parser scheduler fairness guard disabled for this warmup.'
}

$settingsPath = Join-Path -Path $repositoryRoot -ChildPath 'Data\StateTraceSettings.json'
$skipSiteCacheGuard = $null
$ingestionHistoryDir = Join-Path -Path $repositoryRoot -ChildPath 'Data\IngestionHistory'
$ingestionHistoryReset = $false

if (-not $PreserveSkipSiteCacheSetting.IsPresent) {
    $skipSiteCacheGuard = Disable-SkipSiteCacheUpdateSetting -SettingsPath $settingsPath -Label 'SharedCacheWarmup'
}

if (-not $PreserveIngestionHistory.IsPresent) {
    try {
        if (Test-Path -LiteralPath $ingestionHistoryDir) {
            $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            foreach ($file in Get-ChildItem -Path $ingestionHistoryDir -Filter '*.json' -File) {
                $backupPath = Join-Path -Path $ingestionHistoryDir -ChildPath ("{0}.warmup.{1}.bak" -f $file.BaseName, $timestamp)
                Copy-Item -LiteralPath $file.FullName -Destination $backupPath -Force
                Set-Content -LiteralPath $file.FullName -Value '[]' -Encoding utf8
                $ingestionHistoryReset = $true
            }
            if ($ingestionHistoryReset) {
                Write-Host '[SharedCacheWarmup] Reset ingestion history to empty arrays for warmup.' -ForegroundColor Yellow
            }
        } else {
            Write-Warning ("[SharedCacheWarmup] Ingestion history directory not found at '{0}'." -f $ingestionHistoryDir)
        }
    } catch {
        Write-Warning ("[SharedCacheWarmup] Failed to reset ingestion history: {0}" -f $_.Exception.Message)
    }
}

Write-Host '[SharedCacheWarmup] Starting ingestion pipeline...' -ForegroundColor Cyan
try {
    & $pipelineScript @pipelineParameters
    Write-Host '[SharedCacheWarmup] Ingestion pipeline completed.' -ForegroundColor Green
} catch {
    Write-Host '[SharedCacheWarmup] Pipeline execution failed.' -ForegroundColor Red
    throw
} finally {
    if (-not $PreserveSkipSiteCacheSetting.IsPresent -and $skipSiteCacheGuard) {
        Restore-SkipSiteCacheUpdateSetting -Guard $skipSiteCacheGuard
    }
}

$snapshotDirectory = if ($pipelineParameters.ContainsKey('SharedCacheSnapshotDirectory')) {
    $pipelineParameters['SharedCacheSnapshotDirectory']
} else {
    Join-Path -Path $repositoryRoot -ChildPath 'Logs\SharedCacheSnapshot'
}
$latestSummaryPath = Join-Path -Path $snapshotDirectory -ChildPath 'SharedCacheSnapshot-latest-summary.json'
$summaryPath = $latestSummaryPath
try {
    $timestampSummary = Get-ChildItem -Path $snapshotDirectory -Filter 'SharedCacheSnapshot-*-summary.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($timestampSummary) {
        $summaryPath = $timestampSummary.FullName
    }
} catch {
    Write-Warning ("[SharedCacheWarmup] Failed to enumerate summary files under '{0}': {1}" -f $snapshotDirectory, $_.Exception.Message)
}

if (-not (Test-Path -LiteralPath $summaryPath)) {
    throw ("Shared cache summary file not found at '{0}'. Ensure the pipeline emitted SharedCacheSnapshot summaries." -f $summaryPath)
}

$summaryEntries = @()
try {
    $summaryEntries = Read-ToolingJson -Path $summaryPath -Label 'Shared cache summary'
    if ($summaryEntries -and -not ($summaryEntries -is [System.Collections.IEnumerable])) {
        $summaryEntries = @($summaryEntries)
    }
} catch {
    Write-Warning ("[SharedCacheWarmup] Failed to parse summary JSON at '{0}': {1}" -f $summaryPath, $_.Exception.Message)
}

Write-Host '[SharedCacheWarmup] Shared cache summary:' -ForegroundColor Yellow
if ($summaryEntries) {
    $summaryEntries |
        Sort-Object Site |
        Format-Table Site, Hosts, TotalRows, CachedAt -AutoSize
} else {
    Write-Host '  (No entries reported)' -ForegroundColor DarkGray
}

$coverageResult = $null
if (-not $SkipCoverageValidation.IsPresent) {
    Ensure-VerificationModuleLoaded -ModulePath $verificationModulePath
    $snapshotGuardScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Test-SharedCacheSnapshot.ps1'
    if (-not (Test-Path -LiteralPath $snapshotGuardScript)) {
        throw "Shared cache snapshot guard missing at $snapshotGuardScript"
    }
    # Fail fast on snapshot coverage (clixml or summary)
    $snapshotGuardParams = @(
        '-File', $snapshotGuardScript,
        '-Path', $summaryPath,
        '-MinimumSiteCount', $MinimumSiteCount,
        '-MinimumHostCount', $MinimumHostCount,
        '-MinimumTotalRowCount', $MinimumTotalRowCount
    )
    if ($RequiredSites -and $RequiredSites.Count -gt 0) {
        $snapshotGuardParams += @('-RequiredSites')
        $snapshotGuardParams += @($RequiredSites)
    }
    Write-Host ("[SharedCacheWarmup] Validating snapshot coverage via Test-SharedCacheSnapshot.ps1...") -ForegroundColor Cyan
    & pwsh @snapshotGuardParams
    if ($LASTEXITCODE -ne 0) {
        throw "[SharedCacheWarmup] Snapshot coverage guard failed. See console output above."
    }

    $coverageResult = Test-SharedCacheSummaryCoverage -Summary $summaryPath `
        -MinimumSiteCount $MinimumSiteCount `
        -MinimumHostCount $MinimumHostCount `
        -MinimumTotalRowCount $MinimumTotalRowCount `
        -RequiredSites $RequiredSites

    if ($coverageResult) {
        $statusColor = if ($coverageResult.Pass) { 'Green' } else { 'Red' }
        $coverageStatus = if ($coverageResult.Pass) { 'Pass' } else { 'Fail' }
        Write-Host ("[SharedCacheWarmup] Coverage status: {0}" -f $coverageStatus) -ForegroundColor $statusColor
        if (-not $coverageResult.Pass -and $coverageResult.Messages) {
            foreach ($msg in $coverageResult.Messages) {
                Write-Warning ("[SharedCacheWarmup] {0}" -f $msg)
            }
            $violationList = if ($coverageResult.Violations) { ($coverageResult.Violations -join ', ') } else { 'Unknown' }
            throw ("Shared-cache coverage validation failed (violations: {0})." -f $violationList)
        }
    }
}

if ($PassThru.IsPresent) {
    [pscustomobject]@{
        SnapshotDirectory = $snapshotDirectory
        SummaryPath       = $summaryPath
        SummaryEntries    = $summaryEntries
        CoverageResult    = $coverageResult
        Parameters        = $pipelineParameters
    }
}
