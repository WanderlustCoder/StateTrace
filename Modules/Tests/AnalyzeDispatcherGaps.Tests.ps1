Set-StrictMode -Version Latest

Describe 'Analyze-DispatcherGaps' {
    It 'runs without manual module import' {
        # LANDMARK: ST-D-003 dispatcher gaps tests - runs without manual module import
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath '..\..'))
        $scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Analyze-DispatcherGaps.ps1'
        $metricsPath = Join-Path -Path $repoRoot -ChildPath 'Tests\Fixtures\CISmoke\IngestionMetrics.json'
        $queueSummaryPath = Join-Path -Path $TestDrive -ChildPath 'QueueDelaySummary.json'
        $intervalPath = Join-Path -Path $TestDrive -ChildPath 'PortBatchIntervals.json'
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'DispatcherGapReport.md'
        $queueSummaryScript = Join-Path -Path $repoRoot -ChildPath 'Tools\Generate-QueueDelaySummary.ps1'
        $intervalScript = Join-Path -Path $repoRoot -ChildPath 'Tools\Analyze-PortBatchIntervals.ps1'

        if (-not (Test-Path -LiteralPath $metricsPath)) {
            Set-TestInconclusive -Message "Missing CISmoke ingestion fixture at $metricsPath"
            return
        }

        & $queueSummaryScript -MetricsPath $metricsPath -OutputPath $queueSummaryPath -MinimumEventCount 10 | Out-Null
        & $intervalScript -Path $metricsPath -OutputPath $intervalPath -ThresholdSeconds 60 | Out-Null

        $escapedScriptPath = $scriptPath -replace "'", "''"
        $escapedQueuePath = $queueSummaryPath -replace "'", "''"
        $escapedIntervalPath = $intervalPath -replace "'", "''"
        $escapedOutputPath = $outputPath -replace "'", "''"

        $command = ("try {{ & '{0}' -QueueSummaryPaths '{1}' -IntervalReportPath '{2}' -OutputPath '{3}' -GapThresholdSeconds 60 | Out-Null; exit 0 }} catch {{ Write-Error `$_; exit 1 }}" -f $escapedScriptPath, $escapedQueuePath, $escapedIntervalPath, $escapedOutputPath)

        $pwshPath = (Get-Command pwsh).Source
        & $pwshPath -NoProfile -Command $command | Out-Null
        $exitCode = $LASTEXITCODE

        $exitCode | Should Be 0
        Test-Path -LiteralPath $outputPath | Should Be $true
        (Get-Item -LiteralPath $outputPath).Length | Should BeGreaterThan 0
    }
}
