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
    [switch]$SkipCoverageValidation,
    [switch]$PreserveSkipSiteCacheSetting,
    [switch]$PreserveIngestionHistory,
    [switch]$SkipSchedulerFairnessGuard,
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
$originalSettingsText = $null
$skipSettingUpdated = $false
$ingestionHistoryDir = Join-Path -Path $repositoryRoot -ChildPath 'Data\IngestionHistory'
$ingestionHistoryReset = $false

if (-not $PreserveSkipSiteCacheSetting.IsPresent) {
    try {
        if (Test-Path -LiteralPath $settingsPath) {
            $originalSettingsText = Get-Content -LiteralPath $settingsPath -Raw
            if ($originalSettingsText -match '"SkipSiteCacheUpdate"\s*:\s*true') {
                $updatedSettingsText = [System.Text.RegularExpressions.Regex]::Replace(
                    $originalSettingsText,
                    '"SkipSiteCacheUpdate"\s*:\s*true',
                    '"SkipSiteCacheUpdate": false',
                    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
                )
                Set-Content -LiteralPath $settingsPath -Value $updatedSettingsText -Encoding utf8
                $skipSettingUpdated = $true
                Write-Host '[SharedCacheWarmup] Temporarily disabled SkipSiteCacheUpdate for warmup.' -ForegroundColor Yellow
            }
        } else {
            Write-Warning ("[SharedCacheWarmup] Unable to locate StateTraceSettings.json at '{0}'." -f $settingsPath)
        }
    } catch {
        Write-Warning ("[SharedCacheWarmup] Failed to adjust SkipSiteCacheUpdate setting: {0}" -f $_.Exception.Message)
    }
}

if (-not $PreserveIngestionHistory.IsPresent) {
    try {
        if (Test-Path -LiteralPath $ingestionHistoryDir) {
            $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            foreach ($file in Get-ChildItem -Path $ingestionHistoryDir -Filter '*.json' -File) {
                $originalHistory = Get-Content -LiteralPath $file.FullName -Raw
                $backupPath = Join-Path -Path $ingestionHistoryDir -ChildPath ("{0}.warmup.{1}.bak" -f $file.BaseName, $timestamp)
                Set-Content -LiteralPath $backupPath -Value $originalHistory -Encoding utf8
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
    if ($skipSettingUpdated -and $null -ne $originalSettingsText) {
        try {
            Set-Content -LiteralPath $settingsPath -Value $originalSettingsText -Encoding utf8
            Write-Host '[SharedCacheWarmup] Restored SkipSiteCacheUpdate setting.' -ForegroundColor Yellow
        } catch {
            Write-Warning ("[SharedCacheWarmup] Failed to restore StateTraceSettings.json: {0}" -f $_.Exception.Message)
        }
    }
}

$snapshotDirectory = $pipelineParameters.ContainsKey('SharedCacheSnapshotDirectory') ? $pipelineParameters['SharedCacheSnapshotDirectory'] : (Join-Path -Path $repositoryRoot -ChildPath 'Logs\SharedCacheSnapshot')
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
    $summaryEntries = (Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json)
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
    $coverageResult = Test-SharedCacheSummaryCoverage -Summary $summaryPath `
        -MinimumSiteCount $MinimumSiteCount `
        -MinimumHostCount $MinimumHostCount `
        -MinimumTotalRowCount $MinimumTotalRowCount `
        -RequiredSites $RequiredSites

    if ($coverageResult) {
        $statusColor = if ($coverageResult.Pass) { 'Green' } else { 'Red' }
        Write-Host ("[SharedCacheWarmup] Coverage status: {0}" -f ($coverageResult.Pass ? 'Pass' : 'Fail')) -ForegroundColor $statusColor
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
