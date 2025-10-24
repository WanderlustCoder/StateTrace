[CmdletBinding()]
param(
    [switch]$IncludeTests,
    [switch]$VerboseParsing,
    [switch]$ResetExtractedLogs,
    [string]$OutputPath,
    [switch]$SkipRefresh,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$helperPath = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Invoke-WarmRunTelemetry.ps1'
if (-not (Test-Path -LiteralPath $helperPath)) {
    throw "Warm-run telemetry helper not found at $helperPath."
}

$effectiveOutputPath = $OutputPath
if ([string]::IsNullOrWhiteSpace($effectiveOutputPath)) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $effectiveOutputPath = Join-Path -Path $repositoryRoot -ChildPath ("Logs\IngestionMetrics\WarmRunTelemetry-{0}.json" -f $timestamp)
}

$arguments = @{
    AssertWarmCache    = $true
    OutputPath         = $effectiveOutputPath
    ColdHistorySeed    = 'Empty'
    WarmHistorySeed    = 'ColdOutput'
}

if (-not $SkipRefresh.IsPresent) {
    $arguments['RefreshSiteCaches'] = $true
}
if ($IncludeTests.IsPresent) {
    $arguments['IncludeTests'] = $true
}
if ($VerboseParsing.IsPresent) {
    $arguments['VerboseParsing'] = $true
}
if ($ResetExtractedLogs.IsPresent) {
    $arguments['ResetExtractedLogs'] = $true
}

$results = & $helperPath @arguments

$summary = $null
if ($results) {
    $summary = $results | Where-Object { $_.PassLabel -eq 'WarmRunComparison' } | Select-Object -First 1
    if ($summary) {
        Write-Host ("Cold average InterfaceCallDurationMs: {0:N3} ms (p95 {1:N3} ms, max {2:N3} ms)." -f $summary.ColdInterfaceCallAvgMs, $summary.ColdInterfaceCallP95Ms, $summary.ColdInterfaceCallMaxMs) -ForegroundColor Cyan
        Write-Host ("Warm average InterfaceCallDurationMs: {0:N3} ms (p95 {1:N3} ms, max {2:N3} ms)." -f $summary.WarmInterfaceCallAvgMs, $summary.WarmInterfaceCallP95Ms, $summary.WarmInterfaceCallMaxMs) -ForegroundColor Cyan
        if ($summary.ImprovementAverageMs -ne $null -and $summary.ImprovementPercent -ne $null) {
            Write-Host ("Improvement: {0:N3} ms ({1:N2}%)." -f $summary.ImprovementAverageMs, $summary.ImprovementPercent) -ForegroundColor Green
        }
        $providerDisplay = 'n/a'
        if ($summary.WarmProviderCounts) {
            $providerDisplay = (@($summary.WarmProviderCounts.GetEnumerator() | ForEach-Object {
                '{0}={1}' -f $_.Key, $_.Value
            }) -join ', ')
            if ([string]::IsNullOrWhiteSpace($providerDisplay)) {
                $providerDisplay = 'n/a'
            }
        }
        Write-Host ("Warm cache providers: {0}" -f $providerDisplay) -ForegroundColor DarkCyan
        Write-Host ("Telemetry exported to {0}" -f $effectiveOutputPath) -ForegroundColor DarkYellow
    }
}

if ($PassThru.IsPresent) {
    return $results
}
