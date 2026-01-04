[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$BundleName = (Get-Date -Format 'yyyyMMdd-HHmmss'),

    [ValidateNotNullOrEmpty()]
    [string]$OutputRoot = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Logs/TelemetryBundles'),

    [switch]$AllowCustomOutputRoot,

    # LANDMARK: Publish telemetry bundle - default to Telemetry area for readiness compliance
    [string]$AreaName = 'Telemetry',

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
    # LANDMARK: Telemetry bundle publish - forward risk register references
    [string[]]$RiskRegisterEntries,
    [string]$Notes,

    [string]$ColdTelemetryFilter = '20*.json',
    [string]$WarmTelemetryFilter = 'WarmRunTelemetry*.json',
    # LANDMARK: Publish telemetry bundle - include shared-cache analyzers required by readiness
    [string[]]$AnalyzerFilter = @('SharedCacheStoreState*.json','SiteCacheProviderReasons*.json'),
    [string]$DiffHotspotsFilter = 'WarmRunDiffHotspots*.csv',
    [string]$RollupFilter = 'IngestionMetricsSummary*.csv',
    [string]$QueueSummaryFilter = 'QueueDelaySummary*.json',
    [string]$UserActionSummaryFilter = 'UserActionSummary*.json',
    [string]$FreshnessSummaryFilter = 'FreshnessTelemetrySummary*.json',

    [int]$AnalyzerMaxCount = 2,
    [int]$RollupMaxCount = 1,
    [int]$QueueSummaryMaxCount = 2,

    [switch]$Force,
    [switch]$PassThru,

    [switch]$VerifyPlanHReadiness,
    [string[]]$PlanHRequiredActions = @('ScanLogs','LoadFromDb','HelpQuickstart','InterfacesView','CompareView','SpanSnapshot'),
    [string]$PlanHReadinessOutputName = 'PlanHReadiness.json',

    # LANDMARK: ST-M-003 redaction enforcement
    [switch]$RequireRedaction,
    [string[]]$RedactionPatterns = @('password', 'secret', 'token', 'community', 'snmpv3', 'credential', 'api[_-]?key'),
    [string]$RedactionComplianceOutputName = 'RedactionCompliance.json'
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

    $results = [System.Collections.Generic.List[object]]::new()
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
        foreach ($item in ($items | Select-Object -First $MaxCount)) { $results.Add($item) }
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

$historyFiles = [System.Collections.Generic.List[string]]::new()
if (-not [string]::IsNullOrWhiteSpace($HistoryDirectory)) {
    $queueHistoryPath = $QueueDelayHistoryFile
    if (-not [System.IO.Path]::IsPathRooted($queueHistoryPath)) {
        $queueHistoryPath = Join-Path -Path $HistoryDirectory -ChildPath $QueueDelayHistoryFile
    }
    if (Test-Path -LiteralPath $queueHistoryPath) {
        $historyFiles.Add((Resolve-Path -LiteralPath $queueHistoryPath).Path)
    } else {
        Write-Verbose ("[History] Queue delay history file '{0}' not found; skipping." -f $queueHistoryPath)
    }

    $schedulerHistoryPath = $ParserSchedulerHistoryFile
    if (-not [System.IO.Path]::IsPathRooted($schedulerHistoryPath)) {
        $schedulerHistoryPath = Join-Path -Path $HistoryDirectory -ChildPath $ParserSchedulerHistoryFile
    }
    if (Test-Path -LiteralPath $schedulerHistoryPath) {
        $historyFiles.Add((Resolve-Path -LiteralPath $schedulerHistoryPath).Path)
    } else {
        Write-Verbose ("[History] Parser scheduler history file '{0}' not found; skipping." -f $schedulerHistoryPath)
    }

    $portHistoryPath = $PortBatchHistoryFile
    if (-not [System.IO.Path]::IsPathRooted($portHistoryPath)) {
        $portHistoryPath = Join-Path -Path $HistoryDirectory -ChildPath $PortBatchHistoryFile
    }
    if (Test-Path -LiteralPath $portHistoryPath) {
        $historyFiles.Add((Resolve-Path -LiteralPath $portHistoryPath).Path)
    } else {
        Write-Verbose ("[History] Port batch history file '{0}' not found; skipping." -f $portHistoryPath)
    }

    $interfaceHistoryPath = $InterfaceSyncHistoryFile
    if (-not [System.IO.Path]::IsPathRooted($interfaceHistoryPath)) {
        $interfaceHistoryPath = Join-Path -Path $HistoryDirectory -ChildPath $InterfaceSyncHistoryFile
    }
    if (Test-Path -LiteralPath $interfaceHistoryPath) {
        $historyFiles.Add((Resolve-Path -LiteralPath $interfaceHistoryPath).Path)
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

# LANDMARK: Publish telemetry bundle - auto-select latest session log for doc-sync evidence
# Use @() wrapper for PowerShell 5.1 compatibility (string parameters lack .Count)
if (-not $DocSyncPath -or @($DocSyncPath).Count -eq 0) {
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
if ($AllowCustomOutputRoot) { $bundleParams['AllowCustomOutputRoot'] = $true }
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
$aggregatedAdditional = [System.Collections.Generic.List[string]]::new()
# Use foreach for safe iteration (handles scalars and arrays in PS5.1)
foreach ($f in $historyFiles) { if ($f) { $aggregatedAdditional.Add($f) } }
foreach ($f in $schedulerComparisonJson) { if ($f) { $aggregatedAdditional.Add($f) } }
foreach ($f in $schedulerComparisonMarkdown) { if ($f) { $aggregatedAdditional.Add($f) } }
foreach ($f in $AdditionalPath) { if ($f) { $aggregatedAdditional.Add($f) } }
if ($aggregatedAdditional.Count -gt 0) { $bundleParams['AdditionalPath'] = $aggregatedAdditional }
# Use $null check for PS5.1 compatibility with string[] parameters
if ($PlanReferences -and ($PlanReferences -is [array] -or -not [string]::IsNullOrWhiteSpace($PlanReferences))) { $bundleParams['PlanReferences'] = @($PlanReferences) }
if ($TaskBoardIds -and ($TaskBoardIds -is [array] -or -not [string]::IsNullOrWhiteSpace($TaskBoardIds))) { $bundleParams['TaskBoardIds'] = @($TaskBoardIds) }
if ($RiskRegisterEntries -and ($RiskRegisterEntries -is [array] -or -not [string]::IsNullOrWhiteSpace($RiskRegisterEntries))) { $bundleParams['RiskRegisterEntries'] = @($RiskRegisterEntries) }
if ($Notes) { $bundleParams['Notes'] = $Notes }
if ($PassThru -or $VerifyPlanHReadiness) { $bundleParams['PassThru'] = $true }

Write-Verbose "Publishing telemetry bundle '$BundleName' (Area='$AreaName')."
$bundleResult = & $bundleScript @bundleParams

if ($VerifyPlanHReadiness) {
    $planHScript = Join-Path -Path $PSScriptRoot -ChildPath 'Test-PlanHReadiness.ps1'
    if (-not (Test-Path -LiteralPath $planHScript)) {
        throw "Plan H readiness script not found at '$planHScript'."
    }
    $planHParams = @{
        BundlePath            = $bundleResult.Path
        RequiredActions       = $PlanHRequiredActions
        ErrorAction           = 'Stop'
        OutputPath            = if ($bundleResult.Path -and $PlanHReadinessOutputName) { Join-Path -Path $bundleResult.Path -ChildPath $PlanHReadinessOutputName } else { $null }
        PassThru              = $true
    }
    $planHResult = & $planHScript @planHParams
    if ($planHResult.Ready -ne $true) {
        throw "Plan H readiness failed for bundle '$($bundleResult.Path)': $([string]::Join('; ', $planHResult.Failures))"
    }
    Write-Host ("Plan H readiness: Ready (UserAction + freshness evidence present).") -ForegroundColor Green
}

# LANDMARK: ST-M-003 redaction compliance check
if ($RequireRedaction) {
    $redactionScript = Join-Path -Path $PSScriptRoot -ChildPath 'Test-RedactionCompliance.ps1'
    if (-not (Test-Path -LiteralPath $redactionScript)) {
        throw "Redaction compliance script not found at '$redactionScript'."
    }
    $redactionOutputPath = $null
    if ($bundleResult.Path -and $RedactionComplianceOutputName) {
        $redactionOutputPath = Join-Path -Path $bundleResult.Path -ChildPath $RedactionComplianceOutputName
    }
    $redactionParams = @{
        Path            = $bundleResult.Path
        RedactPatterns  = $RedactionPatterns
        OutputPath      = $redactionOutputPath
        FailOnMatch     = $true
        PassThru        = $true
    }
    $redactionResult = & $redactionScript @redactionParams
    if ($redactionResult.Status -ne 'Pass') {
        throw "Redaction compliance failed for bundle '$($bundleResult.Path)': $($redactionResult.Message)"
    }
    Write-Host ("Redaction compliance: Pass ({0} files scanned, no sensitive patterns detected)." -f $redactionResult.FilesScanned) -ForegroundColor Green
}

if ($PassThru) {
    return $bundleResult
} else {
    if ($bundleResult) {
        Write-Host "Bundle created at $($bundleResult.Path)" -ForegroundColor Green
    } else {
        Write-Host "Bundle '$BundleName' created." -ForegroundColor Green
    }
}
