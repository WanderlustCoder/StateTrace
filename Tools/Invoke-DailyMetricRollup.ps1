[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$MetricsDirectory = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Logs\IngestionMetrics'),

    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Logs\IngestionMetrics'),

    [ValidateRange(1, 30)]
    [int]$Days = 1,

    [switch]$IncludePerSite,
    [switch]$IncludeSiteCache,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedMetricsPath = Resolve-Path -LiteralPath $MetricsDirectory -ErrorAction Stop

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
}
$resolvedOutputPath = Resolve-Path -LiteralPath $OutputDirectory

$datePatterns = for ($i = 0; $i -lt $Days; $i++) {
    (Get-Date).AddDays(-$i).ToString('yyyy-MM-dd') + '.json'
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$summaryFileName = "IngestionMetricsSummary-$timestamp.csv"
$summaryOutputPath = Join-Path -Path $resolvedOutputPath.Path -ChildPath $summaryFileName

$rollupScript = Join-Path -Path $PSScriptRoot -ChildPath 'Rollup-IngestionMetrics.ps1'
if (-not (Test-Path -LiteralPath $rollupScript)) {
    throw "Unable to locate Rollup-IngestionMetrics.ps1 at '$rollupScript'."
}

$splat = @{
    MetricsDirectory     = $resolvedMetricsPath.Path
    MetricFileNameFilter = $datePatterns
    OutputPath           = $summaryOutputPath
    IncludePerSite       = $IncludePerSite.IsPresent
    IncludeSiteCache     = $IncludeSiteCache.IsPresent
    PassThru             = $PassThru.IsPresent
}

if (-not $IncludePerSite.IsPresent) { $splat.Remove('IncludePerSite') }
if (-not $IncludeSiteCache.IsPresent) { $splat.Remove('IncludeSiteCache') }
if (-not $PassThru.IsPresent) { $splat.Remove('PassThru') }

Write-Verbose ("Aggregating metrics from '{0}' for the last {1} day(s)." -f $resolvedMetricsPath.Path, $Days)
$rollupResult = & $rollupScript @splat

if (-not (Test-Path -LiteralPath $summaryOutputPath)) {
    throw "Metric rollup did not create the expected output file: $summaryOutputPath"
}

Write-Host ("Daily metrics rollup written to {0}" -f $summaryOutputPath) -ForegroundColor Cyan

if ($PassThru.IsPresent) {
    return $rollupResult
}
