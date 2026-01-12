Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Test-CompareTelemetrySmoke.ps1'
$latestPath = Join-Path -Path $repoRoot -ChildPath 'Logs\Reports\CompareTelemetrySmoke\CompareTelemetrySmoke-latest.json'

# LANDMARK: Compare telemetry smoke tests - Pester v3 compatibility adjustments
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Compare telemetry smoke script not found at $scriptPath"
}

Describe 'Test-CompareTelemetrySmoke' {
    # LANDMARK: Compare telemetry smoke tests - pass/fail/latest pointer
    It 'returns Pass with required metrics when comparison executes' {
        $summaryPath = Join-Path -Path $TestDrive -ChildPath 'CompareTelemetrySmokeSummary.json'

        $result = & $scriptPath -OutputPath $summaryPath -PassThru

        $result.Status | Should Be 'Pass'
        $result.RequiredMetrics | Should BeExactly @('DiffUsageRate','DiffCompareDurationMs','DiffCompareResultCounts')
        @($result.MissingMetrics).Count | Should Be 0
        $result.ObservedMetrics.DiffUsageRate.Present | Should Be $true
        $result.ObservedMetrics.DiffCompareDurationMs.Present | Should Be $true
        $result.ObservedMetrics.DiffCompareResultCounts.Present | Should Be $true
        $result.ObservedMetrics.DiffCompareResultCounts.LastEvent.TotalCount | Should Be 4
        $result.ObservedMetrics.DiffCompareResultCounts.LastEvent.AddedCount | Should Be 1
        $result.ObservedMetrics.DiffCompareResultCounts.LastEvent.RemovedCount | Should Be 1
        $result.ObservedMetrics.DiffCompareResultCounts.LastEvent.UnchangedCount | Should Be 2
        (Test-Path -LiteralPath $summaryPath) | Should Be $true
    }

    It 'returns Fail when comparison is skipped' {
        $summaryPath = Join-Path -Path $TestDrive -ChildPath 'CompareTelemetrySmokeSummary-fail.json'

        $result = & $scriptPath -OutputPath $summaryPath -SkipCompare -PassThru

        $result.Status | Should Be 'Fail'
        @($result.MissingMetrics).Count | Should Be 3
        $result.ObservedMetrics.DiffUsageRate.Present | Should Be $false
        (Test-Path -LiteralPath $summaryPath) | Should Be $true
    }

    It 'writes the latest pointer when requested' {
        $summaryPath = Join-Path -Path $TestDrive -ChildPath 'CompareTelemetrySmokeSummary-latest.json'

        $null = & $scriptPath -OutputPath $summaryPath -UpdateLatest -PassThru

        (Test-Path -LiteralPath $latestPath) | Should Be $true
        $latest = (Get-Content -LiteralPath $latestPath -Raw) | ConvertFrom-Json -ErrorAction Stop
        @($latest.RequiredMetrics).Count | Should Be 3
    }
}
