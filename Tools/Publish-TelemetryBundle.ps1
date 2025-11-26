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
    [string]$HistoryDirectory = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Logs\Reports'),

    [string[]]$ColdTelemetryPath,
    [string[]]$WarmTelemetryPath,
    [string[]]$AnalyzerPath,
    [string[]]$DiffHotspotsPath,
    [string[]]$UserActionSummaryPath,
    [string[]]$FreshnessSummaryPath,
    [string[]]$RollupPath,
    [string[]]$DocSyncPath,
    [string[]]$QueueSummaryPath,
    [string[]]$AdditionalPath,
    [string]$QueueDelayHistoryFile = 'QueueDelayHistory.csv',
    [string]$ParserSchedulerHistoryFile = 'ParserSchedulerHistory.csv',
    [string]$PortBatchHistoryFile = 'PortBatchHistory.csv',
    [string]$InterfaceSyncHistoryFile = 'InterfaceSyncHistory.csv',

    [string]$PerformanceDocsDirectory = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'docs\performance'),
    [string]$SchedulerDiversityReportFilter = 'SchedulerVsPortDiversity-*.json',
    [string]$SchedulerDiversityMarkdownFilter = 'SchedulerVsPortDiversity-*.md',

    [string[]]$PlanReferences,
    [string[]]$TaskBoardIds,
    [string]$Notes,

    [string]$ColdTelemetryFilter = '20*.json',
    [string]$WarmTelemetryFilter = 'WarmRunTelemetry*.json',
    [string[]]$AnalyzerFilter = @('SharedCache*.json'),
    [string]$DiffHotspotsFilter = 'WarmRunDiffHotspots*.csv',
    [string]$RollupFilter = 'IngestionMetricsSummary*.csv',
    [string]$QueueSummaryFilter = 'QueueDelaySummary*.json',
    [string]$UserActionSummaryFilter = 'UserActionSummary*.json',
    [string]$FreshnessSummaryFilter = 'FreshnessTelemetrySummary*.json',

    [int]$AnalyzerMaxCount = 2,
    [int]$RollupMaxCount = 1,
    [int]$QueueSummaryMaxCount = 2,

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
        $items = @(Get-ChildItem -LiteralPath $Directory -Filter $pattern -File -ErrorAction Stop |
            Sort-Object LastWriteTime -Descending)
        if (-not $items -or $items.Count -eq 0) {
            if ($Optional) {
                Write-Warning "[$Description] No files matching '$pattern' were found under '$Directory'."
                continue
            }
            throw "[$Description] Unable to locate files matching '$pattern' under '$Directory'."
        }
        $results += $items | Select-Object -First $MaxCount
    }

    if ($results.Count -eq 0) {
        if ($Optional) {
            return @()
        }
        throw "[$Description] No artifacts found after scanning filters '$($Filter -join ', ')'."
    }

    return ($results | Select-Object -Unique).FullName
}

$resolvedCold = if ($ColdTelemetryPath) { $ColdTelemetryPath } else { Get-LatestArtifacts -Directory $IngestionMetricsDirectory -Filter @($ColdTelemetryFilter) -Description 'Cold telemetry' }
$resolvedWarm = if ($WarmTelemetryPath) { $WarmTelemetryPath } else { Get-LatestArtifacts -Directory $IngestionMetricsDirectory -Filter @($WarmTelemetryFilter) -Description 'Warm telemetry' }
$resolvedAnalyzer = if ($AnalyzerPath) { $AnalyzerPath } else { Get-LatestArtifacts -Directory $IngestionMetricsDirectory -Filter $AnalyzerFilter -Description 'Shared cache analyzer output' -MaxCount $AnalyzerMaxCount -Optional }
$resolvedDiff = if ($DiffHotspotsPath) { $DiffHotspotsPath } else { Get-LatestArtifacts -Directory $IngestionMetricsDirectory -Filter @($DiffHotspotsFilter) -Description 'Diff hotspot telemetry' -Optional }
$resolvedRollup = if ($RollupPath) { $RollupPath } else { Get-LatestArtifacts -Directory $RollupDirectory -Filter @($RollupFilter) -Description 'Rollup CSV' -MaxCount $RollupMaxCount -Optional }
$resolvedUserAction = if ($UserActionSummaryPath) { $UserActionSummaryPath } else { Get-LatestArtifacts -Directory $HistoryDirectory -Filter @($UserActionSummaryFilter) -Description 'UserAction summary' -Optional }
$resolvedFreshness = if ($FreshnessSummaryPath) { $FreshnessSummaryPath } else { Get-LatestArtifacts -Directory $HistoryDirectory -Filter @($FreshnessSummaryFilter) -Description 'Freshness telemetry summary' -Optional }
$resolvedQueueSummary = @()
if ($QueueSummaryPath) {
    $resolvedQueueSummary = $QueueSummaryPath
} elseif ($AreaName -and $AreaName -like 'Routing*') {
    $resolvedQueueSummary = Get-LatestArtifacts -Directory $IngestionMetricsDirectory -Filter @($QueueSummaryFilter) -Description 'Queue delay summary' -MaxCount $QueueSummaryMaxCount -Optional
}

$historyFiles = @()
if (-not [string]::IsNullOrWhiteSpace($HistoryDirectory)) {
    $queueHistoryPath = $QueueDelayHistoryFile
    if (-not [System.IO.Path]::IsPathRooted($queueHistoryPath)) {
        $queueHistoryPath = Join-Path -Path $HistoryDirectory -ChildPath $QueueDelayHistoryFile
    }
    if (Test-Path -LiteralPath $queueHistoryPath) {
        $historyFiles += (Resolve-Path -LiteralPath $queueHistoryPath).Path
    } else {
        Write-Verbose ("[History] Queue delay history file '{0}' not found; skipping." -f $queueHistoryPath)
    }

    $schedulerHistoryPath = $ParserSchedulerHistoryFile
    if (-not [System.IO.Path]::IsPathRooted($schedulerHistoryPath)) {
        $schedulerHistoryPath = Join-Path -Path $HistoryDirectory -ChildPath $ParserSchedulerHistoryFile
    }
    if (Test-Path -LiteralPath $schedulerHistoryPath) {
        $historyFiles += (Resolve-Path -LiteralPath $schedulerHistoryPath).Path
    } else {
        Write-Verbose ("[History] Parser scheduler history file '{0}' not found; skipping." -f $schedulerHistoryPath)
    }

    $portHistoryPath = $PortBatchHistoryFile
    if (-not [System.IO.Path]::IsPathRooted($portHistoryPath)) {
        $portHistoryPath = Join-Path -Path $HistoryDirectory -ChildPath $PortBatchHistoryFile
    }
    if (Test-Path -LiteralPath $portHistoryPath) {
        $historyFiles += (Resolve-Path -LiteralPath $portHistoryPath).Path
    } else {
        Write-Verbose ("[History] Port batch history file '{0}' not found; skipping." -f $portHistoryPath)
    }

    $interfaceHistoryPath = $InterfaceSyncHistoryFile
    if (-not [System.IO.Path]::IsPathRooted($interfaceHistoryPath)) {
        $interfaceHistoryPath = Join-Path -Path $HistoryDirectory -ChildPath $InterfaceSyncHistoryFile
    }
    if (Test-Path -LiteralPath $interfaceHistoryPath) {
        $historyFiles += (Resolve-Path -LiteralPath $interfaceHistoryPath).Path
    } else {
        Write-Verbose ("[History] InterfaceSync history file '{0}' not found; skipping." -f $interfaceHistoryPath)
    }
}

function Get-OptionalArtifacts {
    param(
        [string]$Directory,
        [string[]]$Filter,
        [string]$Description
    )
    if (-not $Directory -or -not (Test-Path -LiteralPath $Directory)) {
        Write-Verbose ("[{0}] Directory '{1}' not found; skipping." -f $Description, $Directory)
        return @()
    }
    try {
        return Get-LatestArtifacts -Directory $Directory -Filter $Filter -Description $Description -Optional -MaxCount 1
    } catch {
        Write-Warning ("[{0}] Collection failed: {1}" -f $Description, $_.Exception.Message)
        return @()
    }
}

$schedulerComparisonJson = Get-OptionalArtifacts -Directory $HistoryDirectory -Filter @($SchedulerDiversityReportFilter) -Description 'Scheduler vs Port (JSON)'
$schedulerComparisonMarkdown = Get-OptionalArtifacts -Directory $PerformanceDocsDirectory -Filter @($SchedulerDiversityMarkdownFilter) -Description 'Scheduler vs Port (Markdown)'

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
if (@($resolvedUserAction).Count -gt 0) { $bundleParams['UserActionSummaryPath'] = $resolvedUserAction }
if (@($resolvedFreshness).Count -gt 0) { $bundleParams['FreshnessSummaryPath'] = $resolvedFreshness }
if (@($resolvedRollup).Count -gt 0) { $bundleParams['RollupPath'] = $resolvedRollup }
if (@($DocSyncPath).Count -gt 0) { $bundleParams['DocSyncPath'] = $DocSyncPath }
if (@($resolvedQueueSummary).Count -gt 0) { $bundleParams['QueueSummaryPath'] = $resolvedQueueSummary }
$aggregatedAdditional = @()
if (@($historyFiles).Count -gt 0) { $aggregatedAdditional += $historyFiles }
if (@($schedulerComparisonJson).Count -gt 0) { $aggregatedAdditional += $schedulerComparisonJson }
if (@($schedulerComparisonMarkdown).Count -gt 0) { $aggregatedAdditional += $schedulerComparisonMarkdown }
if (@($AdditionalPath).Count -gt 0) { $aggregatedAdditional += $AdditionalPath }
if (@($aggregatedAdditional).Count -gt 0) { $bundleParams['AdditionalPath'] = $aggregatedAdditional }
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
