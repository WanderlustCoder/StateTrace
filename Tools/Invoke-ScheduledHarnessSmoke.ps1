[CmdletBinding()]
param(
    [string]$MetricsPath,
    [string]$OutputRoot,
    [string]$SummaryPath,
    [string]$LatestSummaryPath,
    [string]$DatasetId,
    [string]$DatasetRoot,
    [string]$DatasetVersion,
    [ValidateSet('Synth','RawAuto','Raw','Existing')]
    [string]$PortDiversityMode = 'Synth'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-OutputRoot {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return Split-Path -Parent $PSScriptRoot
    }
    try {
        return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    } catch {
        if ([System.IO.Path]::IsPathRooted($Path)) {
            return [System.IO.Path]::GetFullPath($Path)
        }
        $basePath = (Get-Location).ProviderPath
        return [System.IO.Path]::GetFullPath((Join-Path -Path $basePath -ChildPath $Path))
    }
}

function Resolve-MetricsPath {
    param(
        [string]$ExplicitPath,
        [string]$MetricsDirectory
    )
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return (Resolve-Path -LiteralPath $ExplicitPath -ErrorAction Stop).Path
    }

    if (-not (Test-Path -LiteralPath $MetricsDirectory)) {
        throw "Metrics directory '$MetricsDirectory' does not exist."
    }

    $todayName = (Get-Date -Format 'yyyy-MM-dd') + '.json'
    $todayPath = Join-Path -Path $MetricsDirectory -ChildPath $todayName
    if (Test-Path -LiteralPath $todayPath) {
        return (Resolve-Path -LiteralPath $todayPath).Path
    }

    $files = Get-ChildItem -LiteralPath $MetricsDirectory -Filter '*.json' -File
    if (-not $files -or $files.Count -eq 0) {
        throw "No ingestion metrics JSON files found in '$MetricsDirectory'."
    }
    return ($files | Sort-Object LastWriteTime | Select-Object -Last 1).FullName
}

# LANDMARK: Synthetic smoke runner - dataset resolution + isolated output roots
function Resolve-DatasetRoot {
    param(
        [string]$ExplicitRoot,
        [string]$Version,
        [string]$RepositoryRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitRoot)) {
        try {
            return (Resolve-Path -LiteralPath $ExplicitRoot -ErrorAction Stop).Path
        } catch {
            if ([System.IO.Path]::IsPathRooted($ExplicitRoot)) {
                return [System.IO.Path]::GetFullPath($ExplicitRoot)
            }
            return [System.IO.Path]::GetFullPath((Join-Path -Path $RepositoryRoot -ChildPath $ExplicitRoot))
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        return [System.IO.Path]::GetFullPath((Join-Path -Path $RepositoryRoot -ChildPath ("Tests\\Fixtures\\Synthetic\\{0}" -f $Version)))
    }

    return $null
}

function Resolve-DatasetMetricsPath {
    param(
        [string]$ExplicitPath,
        [string]$DatasetRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return (Resolve-Path -LiteralPath $ExplicitPath -ErrorAction Stop).Path
    }

    if (-not $DatasetRoot) {
        return $null
    }

    $candidates = @(
        'IngestionMetrics.json',
        'Metrics.json',
        'metrics.json'
    )
    foreach ($name in $candidates) {
        $candidatePath = Join-Path -Path $DatasetRoot -ChildPath $name
        if (Test-Path -LiteralPath $candidatePath) {
            return (Resolve-Path -LiteralPath $candidatePath).Path
        }
    }

    throw "No metrics file found under dataset root '$DatasetRoot' (expected IngestionMetrics.json or Metrics.json)."
}

# LANDMARK: Scheduled harness smoke runner - timestamped outputs + latest pointer
$repositoryRoot = Split-Path -Parent $PSScriptRoot
# LANDMARK: Scheduled harness smoke runner - resolve tooling from repo root while allowing output overrides
$outputRoot = Resolve-OutputRoot -Path $OutputRoot
$logsRoot = Join-Path -Path $outputRoot -ChildPath 'Logs'
$reportsRoot = Join-Path -Path $logsRoot -ChildPath 'Reports'
$metricsRoot = Join-Path -Path $logsRoot -ChildPath 'IngestionMetrics'
$sharedCacheRoot = Join-Path -Path $logsRoot -ChildPath 'SharedCacheDiagnostics'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

$datasetRoot = Resolve-DatasetRoot -ExplicitRoot $DatasetRoot -Version $DatasetVersion -RepositoryRoot $repositoryRoot
if ([string]::IsNullOrWhiteSpace($datasetRoot)) {
    $datasetRoot = $null
}
if ($datasetRoot -and -not (Test-Path -LiteralPath $datasetRoot)) {
    throw "Synthetic dataset root '$datasetRoot' does not exist."
}

$datasetLabel = $DatasetId
if (-not $datasetRoot -and -not [string]::IsNullOrWhiteSpace($DatasetId)) {
    throw 'DatasetId requires DatasetRoot or DatasetVersion.'
}

$usingSyntheticDataset = -not [string]::IsNullOrWhiteSpace($datasetRoot)
if ($usingSyntheticDataset) {
    if (-not $datasetLabel) {
        if (-not [string]::IsNullOrWhiteSpace($DatasetVersion)) {
            $datasetLabel = "Synthetic-$DatasetVersion"
        } else {
            $datasetLabel = "Synthetic-" + (Split-Path -Path $datasetRoot -Leaf)
        }
    }
    foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
        if ($datasetLabel.Contains($char)) {
            throw "DatasetId '$datasetLabel' contains invalid path characters."
        }
    }

    $syntheticSubdir = Join-Path -Path 'SyntheticSmoke' -ChildPath $datasetLabel
    $reportsRoot = Join-Path -Path $reportsRoot -ChildPath $syntheticSubdir
    $metricsRoot = Join-Path -Path $metricsRoot -ChildPath $syntheticSubdir
    $sharedCacheRoot = Join-Path -Path $sharedCacheRoot -ChildPath $syntheticSubdir
}

$metricsFile = if ($datasetRoot) {
    Resolve-DatasetMetricsPath -ExplicitPath $MetricsPath -DatasetRoot $datasetRoot
} else {
    Resolve-MetricsPath -ExplicitPath $MetricsPath -MetricsDirectory $metricsRoot
}

if (-not $SummaryPath) {
    $SummaryPath = Join-Path -Path $reportsRoot -ChildPath ("HarnessSmokeSummary-{0}.json" -f $timestamp)
}
if (-not $LatestSummaryPath) {
    # LANDMARK: Synthetic smoke latest pointer - deterministic surfacing path
    $LatestSummaryPath = Join-Path -Path $reportsRoot -ChildPath 'HarnessSmokeSummary-latest.json'
}

$queueSummaryPath = Join-Path -Path $metricsRoot -ChildPath ("QueueDelaySummary-smoke-{0}.json" -f $timestamp)
$portDiversityPath = Join-Path -Path $reportsRoot -ChildPath ("PortBatchSiteDiversity-smoke-{0}.json" -f $timestamp)
$portBatchReportPath = Join-Path -Path $reportsRoot -ChildPath ("PortBatchReady-smoke-{0}.json" -f $timestamp)
$interfaceSyncReportPath = Join-Path -Path $reportsRoot -ChildPath ("InterfaceSyncTiming-smoke-{0}.json" -f $timestamp)
$schedulerReportPath = Join-Path -Path $reportsRoot -ChildPath ("ParserSchedulerLaunch-smoke-{0}.json" -f $timestamp)
$sharedCacheStoreStatePath = Join-Path -Path $sharedCacheRoot -ChildPath ("SharedCacheStoreState-smoke-{0}.json" -f $timestamp)
$siteCacheProviderReasonsPath = Join-Path -Path $sharedCacheRoot -ChildPath ("SiteCacheProviderReasons-smoke-{0}.json" -f $timestamp)

$summaryDir = Split-Path -Parent $SummaryPath
if (-not (Test-Path -LiteralPath $summaryDir)) {
    New-Item -ItemType Directory -Path $summaryDir -Force | Out-Null
}

$harnessScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Test-HarnessSmoke.ps1'
if (-not (Test-Path -LiteralPath $harnessScript)) {
    throw "Harness smoke script not found at $harnessScript."
}

$summary = & $harnessScript -MetricsPath $metricsFile `
    -QueueSummaryPath $queueSummaryPath `
    -PortDiversityOutputPath $portDiversityPath `
    -PortDiversityMode $PortDiversityMode `
    -PortBatchReportPath $portBatchReportPath `
    -InterfaceSyncReportPath $interfaceSyncReportPath `
    -SchedulerReportPath $schedulerReportPath `
    -SharedCacheStoreStatePath $sharedCacheStoreStatePath `
    -SiteCacheProviderReasonsPath $siteCacheProviderReasonsPath `
    -DatasetId $datasetLabel `
    -DatasetRoot $datasetRoot `
    -SummaryPath $SummaryPath `
    -PassThru

$latestDir = Split-Path -Parent $LatestSummaryPath
if ($latestDir -and -not (Test-Path -LiteralPath $latestDir)) {
    New-Item -ItemType Directory -Path $latestDir -Force | Out-Null
}
Copy-Item -LiteralPath $SummaryPath -Destination $LatestSummaryPath -Force
Write-Host ("Scheduled harness smoke summary written to {0}" -f $SummaryPath) -ForegroundColor DarkCyan
Write-Host ("Latest harness smoke summary updated at {0}" -f $LatestSummaryPath) -ForegroundColor DarkCyan

$summary | Add-Member -NotePropertyName LatestSummaryPath -NotePropertyValue $LatestSummaryPath -Force
return $summary
