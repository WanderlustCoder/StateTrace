[CmdletBinding()]
param(
    [string]$MetricsPath,
    [string]$DatasetId,
    [string]$DatasetRoot,
    [string]$QueueSummaryPath,
    [string]$PortDiversityOutputPath,
    [switch]$UseExistingPortDiversityReport,
    [ValidateSet('Synth','RawAuto','Raw','Existing')]
    [string]$PortDiversityMode = 'Synth',
    [string]$PortBatchReportPath,
    [string]$InterfaceSyncReportPath,
    [string]$SchedulerReportPath,
    [string]$SharedCacheStoreStatePath,
    [string]$SiteCacheProviderReasonsPath,
    [string]$SummaryPath,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Resolve-PathFromRoot {
    param(
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return [System.IO.Path]::GetFullPath((Join-Path -Path $repositoryRoot -ChildPath $Path))
}

function Resolve-LatestMetricsPath {
    param(
        [string]$MetricsDirectory
    )
    if (-not (Test-Path -LiteralPath $MetricsDirectory)) {
        throw "Metrics directory '$MetricsDirectory' does not exist."
    }
    $files = Get-ChildItem -LiteralPath $MetricsDirectory -Filter '*.json' -File
    $dateNamed = @($files | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}\.json$' })
    $candidates = if ($dateNamed.Count -gt 0) { $dateNamed } else { $files }
    if (-not $candidates -or $candidates.Count -eq 0) {
        throw "No ingestion metrics JSON files found in '$MetricsDirectory'."
    }
    return ($candidates | Sort-Object LastWriteTime | Select-Object -Last 1).FullName
}

function Ensure-Directory {
    param(
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Get-MaxStreak {
    param(
        [pscustomobject]$PortSummary
    )
    if (-not $PortSummary -or -not $PortSummary.SiteStreaks) { return 0 }
    $worst = $PortSummary.SiteStreaks | Sort-Object MaxCount -Descending | Select-Object -First 1
    if (-not $worst) { return 0 }
    return [int]$worst.MaxCount
}

function Get-LatestPortBatchReadyTimestamp {
    param(
        [string]$MetricsPath
    )
    if ([string]::IsNullOrWhiteSpace($MetricsPath) -or -not (Test-Path -LiteralPath $MetricsPath)) {
        return $null
    }
    $latest = $null
    foreach ($line in [System.IO.File]::ReadLines($MetricsPath)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.IndexOf('PortBatchReady', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        try {
            $record = $line | ConvertFrom-Json -ErrorAction Stop
        } catch {
            continue
        }
        if (-not $record -or $record.EventName -ne 'PortBatchReady') { continue }
        if (-not $record.Timestamp) { continue }
        $stamp = [datetime]$record.Timestamp
        if (-not $latest -or $stamp -gt $latest) {
            $latest = $stamp
        }
    }
    return $latest
}

$logsRoot = Join-Path -Path $repositoryRoot -ChildPath 'Logs'
$reportsRoot = Join-Path -Path $logsRoot -ChildPath 'Reports'
$metricsRoot = Join-Path -Path $logsRoot -ChildPath 'IngestionMetrics'
$sharedCacheRoot = Join-Path -Path $logsRoot -ChildPath 'SharedCacheDiagnostics'

$metricsFile = if ($MetricsPath) {
    (Resolve-Path -LiteralPath $MetricsPath).Path
} else {
    Resolve-LatestMetricsPath -MetricsDirectory $metricsRoot
}

if (-not $SummaryPath) {
    $SummaryPath = Join-Path -Path $reportsRoot -ChildPath ("HarnessSmokeSummary-{0}.json" -f $timestamp)
}
$SummaryPath = Resolve-PathFromRoot -Path $SummaryPath
Ensure-Directory -Path (Split-Path -Parent $SummaryPath)

$summary = [ordered]@{
    GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    MetricsPath    = $metricsFile
    DatasetId      = $DatasetId
    DatasetRoot    = $null
    QueueSummary   = $null
    PortDiversity  = $null
    History        = $null
    SharedCacheDiagnostics = $null
    PortDiversityMode = $null
    UsedSynthesizedEvents = $null
    QueueDelaySummaryPath = $null
    PortDiversityReportPath = $null
    SharedCacheStoreStatePath = $null
    SiteCacheProviderReasonsPath = $null
    Passed         = $false
    Failures       = @()
}

$failures = New-Object System.Collections.Generic.List[string]

# LANDMARK: Harness smoke summary - dataset metadata for synthetic runs
if ($DatasetRoot) {
    $summary.DatasetRoot = Resolve-PathFromRoot -Path $DatasetRoot
}

$queueSummaryScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Generate-QueueDelaySummary.ps1'
$portDiversityScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Test-PortBatchSiteDiversity.ps1'
$portBatchAnalyzerScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Analyze-PortBatchReadyTelemetry.ps1'
$interfaceSyncAnalyzerScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Analyze-InterfaceSyncTiming.ps1'
$schedulerAnalyzerScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Analyze-ParserSchedulerLaunch.ps1'
$queueHistoryScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Update-QueueDelayHistory.ps1'
$portBatchHistoryScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Update-PortBatchHistory.ps1'
$interfaceSyncHistoryScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Update-InterfaceSyncHistory.ps1'
$schedulerHistoryScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Update-ParserSchedulerHistory.ps1'
$sharedCacheStoreScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Analyze-SharedCacheStoreState.ps1'
$siteCacheProviderScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Analyze-SiteCacheProviderReasons.ps1'

# LANDMARK: Harness smoke inputs - resolve default output paths per run
if (-not $QueueSummaryPath) {
    $QueueSummaryPath = Join-Path -Path $metricsRoot -ChildPath ("QueueDelaySummary-smoke-{0}.json" -f $timestamp)
}
if (-not $PortDiversityOutputPath) {
    $PortDiversityOutputPath = Join-Path -Path $reportsRoot -ChildPath ("PortBatchSiteDiversity-smoke-{0}.json" -f $timestamp)
}
if (-not $PortBatchReportPath) {
    $PortBatchReportPath = Join-Path -Path $reportsRoot -ChildPath ("PortBatchReady-smoke-{0}.json" -f $timestamp)
}
if (-not $InterfaceSyncReportPath) {
    $InterfaceSyncReportPath = Join-Path -Path $reportsRoot -ChildPath ("InterfaceSyncTiming-smoke-{0}.json" -f $timestamp)
}
if (-not $SchedulerReportPath) {
    $SchedulerReportPath = Join-Path -Path $reportsRoot -ChildPath ("ParserSchedulerLaunch-smoke-{0}.json" -f $timestamp)
}
if (-not $SharedCacheStoreStatePath) {
    $SharedCacheStoreStatePath = Join-Path -Path $sharedCacheRoot -ChildPath ("SharedCacheStoreState-smoke-{0}.json" -f $timestamp)
}
if (-not $SiteCacheProviderReasonsPath) {
    $SiteCacheProviderReasonsPath = Join-Path -Path $sharedCacheRoot -ChildPath ("SiteCacheProviderReasons-smoke-{0}.json" -f $timestamp)
}

$QueueSummaryPath = Resolve-PathFromRoot -Path $QueueSummaryPath
$PortDiversityOutputPath = Resolve-PathFromRoot -Path $PortDiversityOutputPath
$PortBatchReportPath = Resolve-PathFromRoot -Path $PortBatchReportPath
$InterfaceSyncReportPath = Resolve-PathFromRoot -Path $InterfaceSyncReportPath
$SchedulerReportPath = Resolve-PathFromRoot -Path $SchedulerReportPath
$SharedCacheStoreStatePath = Resolve-PathFromRoot -Path $SharedCacheStoreStatePath
$SiteCacheProviderReasonsPath = Resolve-PathFromRoot -Path $SiteCacheProviderReasonsPath

Ensure-Directory -Path (Split-Path -Parent $QueueSummaryPath)
Ensure-Directory -Path (Split-Path -Parent $PortDiversityOutputPath)
Ensure-Directory -Path (Split-Path -Parent $PortBatchReportPath)
Ensure-Directory -Path (Split-Path -Parent $InterfaceSyncReportPath)
Ensure-Directory -Path (Split-Path -Parent $SchedulerReportPath)
Ensure-Directory -Path (Split-Path -Parent $SharedCacheStoreStatePath)
Ensure-Directory -Path (Split-Path -Parent $SiteCacheProviderReasonsPath)

# LANDMARK: Harness smoke port diversity mode - default to Synth and record mode metadata
$effectivePortDiversityMode = $PortDiversityMode
if ($UseExistingPortDiversityReport.IsPresent) {
    if (-not $PSBoundParameters.ContainsKey('PortDiversityMode')) {
        Write-Warning 'UseExistingPortDiversityReport is deprecated; use -PortDiversityMode Existing.'
        $effectivePortDiversityMode = 'Existing'
    } elseif ($PortDiversityMode -ne 'Existing') {
        throw 'UseExistingPortDiversityReport cannot be combined with PortDiversityMode values other than Existing.'
    }
}

$summary.PortDiversityMode = $effectivePortDiversityMode
$summary.QueueDelaySummaryPath = $QueueSummaryPath
$summary.PortDiversityReportPath = $PortDiversityOutputPath
$summary.SharedCacheStoreStatePath = $SharedCacheStoreStatePath
$summary.SiteCacheProviderReasonsPath = $SiteCacheProviderReasonsPath

# LANDMARK: Harness smoke port diversity window - focus synth mode on recent events
$portDiversityLookbackMinutes = 10
$portDiversitySinceTimestamp = $null
if ($effectivePortDiversityMode -eq 'Synth') {
    $latestPortBatchReady = Get-LatestPortBatchReadyTimestamp -MetricsPath $metricsFile
    if ($latestPortBatchReady) {
        $portDiversitySinceTimestamp = $latestPortBatchReady.AddMinutes(-1 * $portDiversityLookbackMinutes)
    }
}

# LANDMARK: Harness smoke queue summary - generate or load the queue delay summary
$queueSummaryGenerated = $false
try {
    if (-not (Test-Path -LiteralPath $QueueSummaryPath)) {
        & $queueSummaryScript -MetricsPath $metricsFile -OutputPath $QueueSummaryPath | Out-Null
        $queueSummaryGenerated = $true
    }
    $queueSummary = (Get-Content -LiteralPath $QueueSummaryPath -Raw) | ConvertFrom-Json -ErrorAction Stop
    $sampleCount = $null
    if ($queueSummary.PSObject.Properties.Name -contains 'Statistics' -and $queueSummary.Statistics.PSObject.Properties.Name -contains 'SampleCount') {
        $sampleCount = [int]$queueSummary.Statistics.SampleCount
    }
    $summary.QueueSummary = [pscustomobject]@{
        Path          = $QueueSummaryPath
        Generated     = $queueSummaryGenerated
        SampleCount   = $sampleCount
        Pass          = [bool]$queueSummary.Pass
        Result        = '' + $queueSummary.Result
    }
} catch {
    $failures.Add("QueueDelaySummary: $($_.Exception.Message)") | Out-Null
    $summary.QueueSummary = [pscustomobject]@{
        Path          = $QueueSummaryPath
        Generated     = $queueSummaryGenerated
        SampleCount   = $null
        Pass          = $false
        Result        = 'Fail'
        Error         = $_.Exception.Message
    }
}

# LANDMARK: Harness smoke port diversity - validate PortBatchReady streaks
try {
    $usedExistingReport = $false
    switch ($effectivePortDiversityMode) {
        'Existing' {
            if (-not $PortDiversityOutputPath) {
                throw 'PortDiversityOutputPath is required when PortDiversityMode is Existing.'
            }
            if (-not (Test-Path -LiteralPath $PortDiversityOutputPath)) {
                throw ("Port diversity report '{0}' does not exist." -f $PortDiversityOutputPath)
            }
            $portSummary = (Get-Content -LiteralPath $PortDiversityOutputPath -Raw) | ConvertFrom-Json -ErrorAction Stop
            $usedExistingReport = $true
        }
        'Synth' {
            $diversityArgs = @{
                MetricsPath = $metricsFile
                OutputPath  = $PortDiversityOutputPath
            }
            if ($portDiversitySinceTimestamp) {
                $diversityArgs['SinceTimestamp'] = $portDiversitySinceTimestamp
            }
            $portSummary = & $portDiversityScript @diversityArgs
        }
        'Raw' {
            $portSummary = & $portDiversityScript -MetricsPath $metricsFile -OutputPath $PortDiversityOutputPath -IgnoreSynthesizedEvents
        }
        'RawAuto' {
            $portSummary = & $portDiversityScript -MetricsPath $metricsFile -OutputPath $PortDiversityOutputPath -IgnoreSynthesizedEvents -RawAutoConcurrencyMode
        }
        Default {
            $portSummary = & $portDiversityScript -MetricsPath $metricsFile -OutputPath $PortDiversityOutputPath
        }
    }

    $maxStreak = Get-MaxStreak -PortSummary $portSummary
    $allowedStreak = if ($portSummary.PSObject.Properties.Name -contains 'MaxAllowedConsecutive') {
        [int]$portSummary.MaxAllowedConsecutive
    } else {
        8
    }
    if ($portSummary.PSObject.Properties.Name -contains 'Skipped' -and $portSummary.Skipped) {
        throw "Port diversity report '$PortDiversityOutputPath' was skipped (reason: $($portSummary.SkipReason))."
    }

    $summary.PortDiversity = [pscustomobject]@{
        Mode                  = $effectivePortDiversityMode
        Path                  = $PortDiversityOutputPath
        MaxStreak             = $maxStreak
        AllowedStreak         = $allowedStreak
        UsedSynthesizedEvents = if ($portSummary.PSObject.Properties.Name -contains 'UsedSynthesizedEvents') { [bool]$portSummary.UsedSynthesizedEvents } else { $false }
        EvaluationWindowStartUtc = if ($portSummary.PSObject.Properties.Name -contains 'EvaluationWindowStartUtc') { $portSummary.EvaluationWindowStartUtc } else { $null }
        EvaluationWindowEndUtc   = if ($portSummary.PSObject.Properties.Name -contains 'EvaluationWindowEndUtc') { $portSummary.EvaluationWindowEndUtc } else { $null }
        UsedExistingReport    = $usedExistingReport
        Pass                  = ($maxStreak -le $allowedStreak)
    }
    $summary.UsedSynthesizedEvents = $summary.PortDiversity.UsedSynthesizedEvents

    if (-not $summary.PortDiversity.Pass) {
        $message = ("PortBatchDiversity max streak {0} exceeds limit {1}." -f $maxStreak, $allowedStreak)
        if ($effectivePortDiversityMode -eq 'Raw') {
            $message = "$message Use -PortDiversityMode RawAuto to evaluate raw data with auto concurrency."
        }
        throw $message
    }
} catch {
    $failures.Add("PortBatchDiversity: $($_.Exception.Message)") | Out-Null
    $summary.PortDiversity = [pscustomobject]@{
        Mode                  = $effectivePortDiversityMode
        Path                  = $PortDiversityOutputPath
        MaxStreak             = $null
        AllowedStreak         = $null
        UsedSynthesizedEvents = $false
        EvaluationWindowStartUtc = $null
        EvaluationWindowEndUtc   = $null
        UsedExistingReport    = $effectivePortDiversityMode -eq 'Existing'
        Pass                  = $false
        Error                 = $_.Exception.Message
    }
    $summary.UsedSynthesizedEvents = $summary.PortDiversity.UsedSynthesizedEvents
}

# LANDMARK: Harness smoke reports - generate analyzer outputs for history updates
try {
    if (-not (Test-Path -LiteralPath $PortBatchReportPath)) {
        & $portBatchAnalyzerScript -Path $metricsFile -OutputPath $PortBatchReportPath | Out-Null
    }
} catch {
    $failures.Add("PortBatchReport: $($_.Exception.Message)") | Out-Null
}

try {
    if (-not (Test-Path -LiteralPath $InterfaceSyncReportPath)) {
        & $interfaceSyncAnalyzerScript -Path $metricsFile -OutputPath $InterfaceSyncReportPath | Out-Null
    }
} catch {
    $failures.Add("InterfaceSyncReport: $($_.Exception.Message)") | Out-Null
}

try {
    if (-not (Test-Path -LiteralPath $SchedulerReportPath)) {
        & $schedulerAnalyzerScript -Path $metricsFile -OutputPath $SchedulerReportPath | Out-Null
    }
} catch {
    $failures.Add("ParserSchedulerReport: $($_.Exception.Message)") | Out-Null
}

# LANDMARK: Harness smoke history updates - append queue/port/sync/scheduler histories
$historyStatus = [ordered]@{
    QueueDelayHistoryPath      = (Join-Path -Path $reportsRoot -ChildPath 'QueueDelayHistory.csv')
    PortBatchHistoryPath       = (Join-Path -Path $reportsRoot -ChildPath 'PortBatchHistory.csv')
    InterfaceSyncHistoryPath   = (Join-Path -Path $reportsRoot -ChildPath 'InterfaceSyncHistory.csv')
    ParserSchedulerHistoryPath = (Join-Path -Path $reportsRoot -ChildPath 'ParserSchedulerHistory.csv')
    QueueDelayAppended         = 0
    PortBatchAppended          = 0
    InterfaceSyncAppended      = 0
    ParserSchedulerAppended    = 0
}

try {
    $queueHistoryRecords = & $queueHistoryScript -QueueSummaryPaths $QueueSummaryPath
    $historyStatus.QueueDelayAppended = if ($queueHistoryRecords) { @($queueHistoryRecords).Count } else { 0 }
} catch {
    $failures.Add("QueueDelayHistory: $($_.Exception.Message)") | Out-Null
}

try {
    $portHistoryRecords = & $portBatchHistoryScript -ReportPaths $PortBatchReportPath -PassThru
    $historyStatus.PortBatchAppended = if ($portHistoryRecords) { @($portHistoryRecords).Count } else { 0 }
} catch {
    $failures.Add("PortBatchHistory: $($_.Exception.Message)") | Out-Null
}

try {
    $interfaceHistoryRecords = & $interfaceSyncHistoryScript -ReportPaths $InterfaceSyncReportPath -PassThru
    $historyStatus.InterfaceSyncAppended = if ($interfaceHistoryRecords) { @($interfaceHistoryRecords).Count } else { 0 }
} catch {
    $failures.Add("InterfaceSyncHistory: $($_.Exception.Message)") | Out-Null
}

try {
    $schedulerHistoryRecords = & $schedulerHistoryScript -SchedulerReportPaths $SchedulerReportPath
    $historyStatus.ParserSchedulerAppended = if ($schedulerHistoryRecords) { @($schedulerHistoryRecords).Count } else { 0 }
} catch {
    $failures.Add("ParserSchedulerHistory: $($_.Exception.Message)") | Out-Null
}

$summary.History = [pscustomobject]$historyStatus

# LANDMARK: Harness smoke shared cache diagnostics - ensure analyzer outputs exist
try {
    $storeSummary = & $sharedCacheStoreScript -Path $metricsFile -IncludeSiteBreakdown
    if (-not $storeSummary) { throw 'No shared cache store events found.' }
    $storeSummary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $SharedCacheStoreStatePath -Encoding utf8
} catch {
    $failures.Add("SharedCacheStoreState: $($_.Exception.Message)") | Out-Null
}

try {
    $providerSummary = & $siteCacheProviderScript -Path $metricsFile
    if (-not $providerSummary) { throw 'No site cache provider reason events found.' }
    $providerSummary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $SiteCacheProviderReasonsPath -Encoding utf8
} catch {
    $failures.Add("SiteCacheProviderReasons: $($_.Exception.Message)") | Out-Null
}

$summary.SharedCacheDiagnostics = [pscustomobject]@{
    StoreStatePath      = $SharedCacheStoreStatePath
    ProviderReasonsPath = $SiteCacheProviderReasonsPath
}

$summary.Passed = ($failures.Count -eq 0)
$summary.Failures = @($failures)

$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $SummaryPath -Encoding utf8
Write-Host ("Harness smoke summary written to {0}" -f $SummaryPath) -ForegroundColor DarkCyan

if ($failures.Count -gt 0) {
    throw ("Harness smoke failed: {0}" -f ($failures -join '; '))
}

if ($PassThru) {
    return $summary
}
