[CmdletBinding()]
param(
    [int]$MaxHosts = 12,
    [string[]]$SiteFilter = @('WLLS','BOYO'),
    [switch]$SkipPipeline,
    [switch]$SkipHarness,
    [string]$MetricsPath,
    [switch]$ForceTelemetrySynthesis,
    [switch]$VerbosePipeline
)

<#
.SYNOPSIS
Runs the incremental-loading verification checklist without launching the WPF UI.

.DESCRIPTION
Automates the parser pipeline, dispatcher harness sweep, telemetry synthesis, and
guard scripts so Plan D/A can gather PortBatchReady evidence in headless environments.
Captures the key artifacts:
  * Ingestion metrics JSON (parser pipeline output)
  * Dispatcher sweep summary (`Logs/DispatchHarness/...json`)
  * Port batch diversity report (`Logs/Reports/PortBatchSiteDiversity-*.json`)
  * Scheduler vs. Port diversity correlation (`Logs/Reports/SchedulerVsPortDiversity-*.json`
    + matching markdown under `docs/performance/`)

.EXAMPLE
pwsh Tools\Invoke-IncrementalLoadingChecklist.ps1

Runs the full checklist: parser pipeline, dispatcher sweep for balanced WLLS/BOYO hosts,
telemetry synthesis, telemetry completeness test, diversity guard, and scheduler comparison.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$ingestionDir = Join-Path $repoRoot 'Logs\IngestionMetrics'
$dispatchDir = Join-Path $repoRoot 'Logs\DispatchHarness'

function Get-SitePrefix {
    param([string]$Hostname)
    if ([string]::IsNullOrWhiteSpace($Hostname)) { return '(unknown)' }
    $parts = $Hostname.Split('-', 2, [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Count -gt 0) { return $parts[0] }
    return $Hostname
}

function Get-LatestMetricsFile {
    $candidates = Get-ChildItem -LiteralPath $ingestionDir -Filter '*.json' -File |
        Where-Object { $_.Name -notmatch 'QueueDelaySummary|Summary' }
    if (-not $candidates) {
        throw "No ingestion metrics JSON files found in '$ingestionDir'."
    }
    return ($candidates | Sort-Object LastWriteTime | Select-Object -Last 1).FullName
}

function Invoke-ParserPipeline {
    param([switch]$VerbosePipeline)
    $pipelineScript = Join-Path $repoRoot 'Tools\Invoke-StateTracePipeline.ps1'
    if (-not (Test-Path -LiteralPath $pipelineScript)) {
        throw "Pipeline script '$pipelineScript' not found."
    }
    Write-Host "[Checklist] Running parser pipeline..." -ForegroundColor Cyan
    if ($VerbosePipeline) {
        & $pipelineScript -SkipTests -VerboseParsing -ResetExtractedLogs -VerifyTelemetryCompleteness -FailOnTelemetryMissing -FailOnSchedulerFairness -Verbose
    } else {
        & $pipelineScript -SkipTests -VerboseParsing -ResetExtractedLogs -VerifyTelemetryCompleteness -FailOnTelemetryMissing -FailOnSchedulerFairness
    }
}

function Get-TargetHosts {
    param([int]$MaxHosts, [string[]]$SiteFilter)

    $deviceCatalogPath = Join-Path $repoRoot 'Modules\DeviceCatalogModule.psm1'
    if (-not (Get-Module -Name DeviceCatalogModule -ErrorAction SilentlyContinue)) {
        Import-Module $deviceCatalogPath -ErrorAction Stop
    }
    $catalog = $null
    try {
        if ($SiteFilter -and $SiteFilter.Count -gt 0) {
            $catalog = DeviceCatalogModule\Get-DeviceSummaries -SiteFilter $SiteFilter
        } else {
            $catalog = DeviceCatalogModule\Get-DeviceSummaries
        }
    } catch { $catalog = $null }
    if (-not $catalog -or -not $catalog.Hostnames) {
        throw "Device catalog did not return any hostnames; ensure the parser pipeline populated the Access databases."
    }
    $hosts = @($catalog.Hostnames)
    if ($SiteFilter -and $SiteFilter.Count -gt 0) {
        $filterSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($site in $SiteFilter) {
            if (-not [string]::IsNullOrWhiteSpace($site)) { $filterSet.Add($site) | Out-Null }
        }
        $hosts = $hosts | Where-Object {
            if ($filterSet.Count -eq 0) { return $true }
            return $filterSet.Contains((Get-SitePrefix $_))
        }
    }
    if (-not $hosts -or $hosts.Count -eq 0) {
        throw "No hostnames matched the requested site filters ($SiteFilter)."
    }
    if ($MaxHosts -gt 0 -and $hosts.Count -gt $MaxHosts) {
        $hosts = $hosts | Select-Object -First $MaxHosts
    }
    return $hosts
}

function Invoke-DispatcherSweep {
    param([string[]]$Hosts)
    if (-not $Hosts -or $Hosts.Count -eq 0) {
        throw "Dispatcher sweep requires at least one hostname."
    }
    if (-not (Test-Path -LiteralPath $dispatchDir)) {
        New-Item -ItemType Directory -Path $dispatchDir -Force | Out-Null
    }
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $summaryPath = Join-Path $dispatchDir ("RoutingQueueSweep-checklist-{0}.json" -f $timestamp)
    $sweepScript = Join-Path $repoRoot 'Tools\Invoke-RoutingQueueSweep.ps1'
    Write-Host ("[Checklist] Running dispatcher harness for {0} host(s)..." -f $Hosts.Count) -ForegroundColor Cyan
    & $sweepScript `
        -Hosts $Hosts `
        -QueueDelayWarningMs 120 `
        -QueueDelayCriticalMs 200 `
        -OutputDirectory $dispatchDir `
        -SummaryPath $summaryPath | Out-Null
    if (-not (Test-Path -LiteralPath $summaryPath)) {
        throw "Dispatcher sweep summary '$summaryPath' was not created."
    }
    return $summaryPath
}

function Ensure-Telemetry {
    param([string]$MetricsFile, [switch]$ForceSyn)
    $portScript = Join-Path $repoRoot 'Tools\Add-PortBatchReadyTelemetry.ps1'
    & $portScript -MetricsPath $MetricsFile -InPlace -Force:$ForceSyn
    $syncScript = Join-Path $repoRoot 'Tools\Synthesize-InterfaceSyncTelemetry.ps1'
    & $syncScript -MetricsPath $MetricsFile -InPlace -Force:$ForceSyn
}

function Invoke-DiversityGuards {
    param([string]$MetricsFile)
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $diversityReport = Join-Path $repoRoot ("Logs\Reports\PortBatchSiteDiversity-{0}.json" -f $timestamp)
    $diversityScript = Join-Path $repoRoot 'Tools\Test-PortBatchSiteDiversity.ps1'
    Write-Host "[Checklist] Running PortBatch site diversity guard..." -ForegroundColor Cyan
    & $diversityScript -MetricsPath $MetricsFile -MaxAllowedConsecutive 8 -OutputPath $diversityReport | Out-Null

    # LANDMARK: Scheduler vs port diversity inputs - align scheduler report to metrics file
    $schedulerAnalyzer = Join-Path $repoRoot 'Tools\Analyze-ParserSchedulerLaunch.ps1'
    if (-not (Test-Path -LiteralPath $schedulerAnalyzer)) {
        throw "Parser scheduler analyzer not found at '$schedulerAnalyzer'."
    }
    $schedulerReport = Join-Path $repoRoot ("Logs\Reports\ParserSchedulerLaunch-{0}.json" -f $timestamp)
    Write-Host ("[Checklist] Summarising parser scheduler telemetry into '{0}'..." -f $schedulerReport) -ForegroundColor Cyan
    & $schedulerAnalyzer -Path $MetricsFile -MaxAllowedStreak 8 -OutputPath $schedulerReport | Out-Null
    $schedulerVsJson = Join-Path $repoRoot ("Logs\Reports\SchedulerVsPortDiversity-{0}.json" -f $timestamp)
    $schedulerVsMd = Join-Path $repoRoot ("docs\performance\SchedulerVsPortDiversity-{0}.md" -f $timestamp)
    $compareScript = Join-Path $repoRoot 'Tools\Compare-SchedulerAndPortDiversity.ps1'
    # LANDMARK: Checklist compare path - pass scheduler report path string
    Write-Host "[Checklist] Comparing scheduler streaks with PortBatchReady streaks..." -ForegroundColor Cyan
    & $compareScript `
        -SchedulerReportPath $schedulerReport `
        -PortDiversityReportPath $diversityReport `
        -OutputPath $schedulerVsJson `
        -MarkdownPath $schedulerVsMd | Out-Null

    return @{
        DiversityReport = $diversityReport
        SchedulerVsJson = $schedulerVsJson
        SchedulerVsMarkdown = $schedulerVsMd
    }
}

if (-not $SkipPipeline) {
    Invoke-ParserPipeline -VerbosePipeline:$VerbosePipeline
}

$metricsFile = if ($MetricsPath) {
    (Resolve-Path -LiteralPath $MetricsPath).Path
} else {
    Get-LatestMetricsFile
}
Write-Host ("[Checklist] Using ingestion metrics file: {0}" -f $metricsFile) -ForegroundColor Cyan

$hostList = @()
if (-not $SkipHarness) {
    $hostList = Get-TargetHosts -MaxHosts $MaxHosts -SiteFilter $SiteFilter
    $sweepSummary = Invoke-DispatcherSweep -Hosts $hostList
    Write-Host ("[Checklist] Dispatcher sweep summary: {0}" -f $sweepSummary) -ForegroundColor DarkCyan
} else {
    $sweepSummary = $null
}

Ensure-Telemetry -MetricsFile $metricsFile -ForceSyn:$ForceTelemetrySynthesis

Write-Host "[Checklist] Validating telemetry completeness..." -ForegroundColor Cyan
$completenessScript = Join-Path $repoRoot 'Tools\Test-IncrementalTelemetryCompleteness.ps1'
& $completenessScript `
    -MetricsPath $metricsFile `
    -RequirePortBatchReady `
    -RequireInterfaceSync `
    -RequireSchedulerLaunch `
    -ThrowOnMissing | Out-Null

$guardArtifacts = Invoke-DiversityGuards -MetricsFile $metricsFile

$result = [pscustomobject]@{
    ChecklistCompletedAt     = (Get-Date).ToString('s')
    MetricsPath              = $metricsFile
    HostSampleUsed           = if ($hostList) { ($hostList | Select-Object -First ([Math]::Min(5, $hostList.Count))) } else { @() }
    DispatcherSummaryPath    = $sweepSummary
    PortDiversityReportPath  = $guardArtifacts.DiversityReport
    SchedulerVsPortJsonPath  = $guardArtifacts.SchedulerVsJson
    SchedulerVsPortMarkdown  = $guardArtifacts.SchedulerVsMarkdown
}

Write-Host "[Checklist] Done." -ForegroundColor Green
$result
