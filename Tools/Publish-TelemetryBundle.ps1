[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$BundleName = (Get-Date -Format 'yyyyMMdd-HHmmss'),

    [ValidateNotNullOrEmpty()]
    [string]$OutputRoot = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Logs/TelemetryBundles'),

    [string]$AreaName = 'Performance',

    [string]$IngestionMetricsDirectory = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Logs\IngestionMetrics'),
    [string]$RollupDirectory = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Logs\IngestionMetrics'),
    [string]$DocSyncDirectory = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'docs\agents\sessions'),

    [string[]]$ColdTelemetryPath,
    [string[]]$WarmTelemetryPath,
    [string[]]$AnalyzerPath,
    [string[]]$DiffHotspotsPath,
    [string[]]$RollupPath,
    [string[]]$DocSyncPath,
    [string[]]$AdditionalPath,

    [string[]]$PlanReferences,
    [string[]]$TaskBoardIds,
    [string]$Notes,

    [string]$ColdTelemetryFilter = '20*.json',
    [string]$WarmTelemetryFilter = 'WarmRunTelemetry*.json',
    [string[]]$AnalyzerFilter = @('SharedCache*.json'),
    [string]$DiffHotspotsFilter = 'WarmRunDiffHotspots*.csv',
    [string]$RollupFilter = 'IngestionMetricsSummary*.csv',

    [int]$AnalyzerMaxCount = 2,
    [int]$RollupMaxCount = 1,

    [switch]$Force,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LatestArtifacts {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string[]]$Filter,
        [Parameter(Mandatory = $true)][string]$Description,
        [int]$MaxCount = 1,
        [switch]$Optional
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        if ($Optional) {
            Write-Warning "[$Description] Directory '$Directory' was not found. Skipping."
            return @()
        }
        throw "[$Description] Directory '$Directory' was not found."
    }

    $results = @()
    foreach ($pattern in $Filter) {
        $items = Get-ChildItem -LiteralPath $Directory -Filter $pattern -File -ErrorAction Stop |
            Sort-Object LastWriteTime -Descending
        if (-not $items -or $items.Count -eq 0) {
            if ($Optional) {
                Write-Warning "[$Description] No files matching '$pattern' were found under '$Directory'."
                continue
            }
            throw "[$Description] Unable to locate files matching '$pattern' under '$Directory'."
        }
        $results += $items | Select-Object -First $MaxCount
    }

    return ($results | Select-Object -Unique).FullName
}

$resolvedCold = if ($ColdTelemetryPath) { $ColdTelemetryPath } else { Get-LatestArtifacts -Directory $IngestionMetricsDirectory -Filter @($ColdTelemetryFilter) -Description 'Cold telemetry' }
$resolvedWarm = if ($WarmTelemetryPath) { $WarmTelemetryPath } else { Get-LatestArtifacts -Directory $IngestionMetricsDirectory -Filter @($WarmTelemetryFilter) -Description 'Warm telemetry' }
$resolvedAnalyzer = if ($AnalyzerPath) { $AnalyzerPath } else { Get-LatestArtifacts -Directory $IngestionMetricsDirectory -Filter $AnalyzerFilter -Description 'Shared cache analyzer output' -MaxCount $AnalyzerMaxCount -Optional }
$resolvedDiff = if ($DiffHotspotsPath) { $DiffHotspotsPath } else { Get-LatestArtifacts -Directory $IngestionMetricsDirectory -Filter @($DiffHotspotsFilter) -Description 'Diff hotspot telemetry' -Optional }
$resolvedRollup = if ($RollupPath) { $RollupPath } else { Get-LatestArtifacts -Directory $RollupDirectory -Filter @($RollupFilter) -Description 'Rollup CSV' -MaxCount $RollupMaxCount -Optional }

if (@($DocSyncPath).Count -eq 0) {
    if (Test-Path -LiteralPath $DocSyncDirectory) {
        $latestSession = Get-ChildItem -LiteralPath $DocSyncDirectory -Filter '*.md' -File |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($latestSession) {
            $DocSyncPath = @($latestSession.FullName)
        } else {
            Write-Warning "[Doc sync] No session logs found under '$DocSyncDirectory'."
        }
    } else {
        Write-Warning "[Doc sync] Directory '$DocSyncDirectory' was not found."
    }
}

$bundleScript = Join-Path -Path $PSScriptRoot -ChildPath 'New-TelemetryBundle.ps1'
if (-not (Test-Path -LiteralPath $bundleScript)) {
    throw "Unable to locate New-TelemetryBundle.ps1 at '$bundleScript'."
}

$bundleParams = @{
    BundleName = $BundleName
    OutputRoot = $OutputRoot
    Force = $Force
}
if ($AreaName) { $bundleParams['AreaName'] = $AreaName }
if ($resolvedCold) { $bundleParams['ColdTelemetryPath'] = $resolvedCold }
if ($resolvedWarm) { $bundleParams['WarmTelemetryPath'] = $resolvedWarm }
if (@($resolvedAnalyzer).Count -gt 0) { $bundleParams['AnalyzerPath'] = $resolvedAnalyzer }
if (@($resolvedDiff).Count -gt 0) { $bundleParams['DiffHotspotsPath'] = $resolvedDiff }
if (@($resolvedRollup).Count -gt 0) { $bundleParams['RollupPath'] = $resolvedRollup }
if (@($DocSyncPath).Count -gt 0) { $bundleParams['DocSyncPath'] = $DocSyncPath }
if (@($AdditionalPath).Count -gt 0) { $bundleParams['AdditionalPath'] = $AdditionalPath }
if (@($PlanReferences).Count -gt 0) { $bundleParams['PlanReferences'] = $PlanReferences }
if (@($TaskBoardIds).Count -gt 0) { $bundleParams['TaskBoardIds'] = $TaskBoardIds }
if ($Notes) { $bundleParams['Notes'] = $Notes }
if ($PassThru) { $bundleParams['PassThru'] = $true }

Write-Verbose "Publishing telemetry bundle '$BundleName' (Area='$AreaName')."
$bundleResult = & $bundleScript @bundleParams

if ($PassThru) {
    return $bundleResult
}
else {
    if ($bundleResult) {
        Write-Host "Bundle created at $($bundleResult.Path)" -ForegroundColor Green
    } else {
        Write-Host "Bundle '$BundleName' created." -ForegroundColor Green
    }
}
