Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Ensure-Directory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Invoke-ScheduledHarnessSmoke.ps1'

Describe 'Invoke-ScheduledHarnessSmoke' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            throw "Scheduled harness smoke script not found at $scriptPath"
        }
    }

    # LANDMARK: Harness smoke tests - default synth mode and latest-pointer behavior
    It 'writes a latest pointer summary in the output root' {
        $metricsPath = Join-Path -Path $TestDrive -ChildPath 'metrics.json'
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'OutputRoot'
        $now = Get-Date
        $lines = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt 10; $i++) {
            $lines.Add((@{
                EventName = 'InterfacePortQueueMetrics'
                Timestamp = $now.AddSeconds($i).ToString('o')
                QueueBuildDelayMs = 10
                QueueBuildDurationMs = 20
            } | ConvertTo-Json -Compress)) | Out-Null
        }
        $lines.Add((@{
            EventName = 'PortBatchReady'
            Timestamp = $now.AddSeconds(20).ToString('o')
            Hostname = 'BOYO-A01-AS-01'
            PortsCommitted = 5
            ChunkSize = 5
            Synthesized = $true
        } | ConvertTo-Json -Compress)) | Out-Null
        $lines.Add((@{
            EventName = 'InterfaceSyncTiming'
            Timestamp = $now.AddSeconds(25).ToString('o')
            Site = 'BOYO'
            Hostname = 'BOYO-A01-AS-01'
            UiCloneDurationMs = 1
            StreamDispatchDurationMs = 1
            DiffDurationMs = 1
            SiteCacheUpdateDurationMs = 2
            SiteCacheProvider = 'Cache'
            SiteCacheProviderReason = 'SharedCacheMatch'
            SiteCacheFetchDurationMs = 10
        } | ConvertTo-Json -Compress)) | Out-Null
        $lines.Add((@{
            EventName = 'ParserSchedulerLaunch'
            Timestamp = $now.AddSeconds(30).ToString('o')
            Site = 'BOYO'
            ActiveWorkers = 1
            ActiveSites = 1
            ThreadBudget = 4
            QueuedJobs = 0
            QueuedSites = 1
        } | ConvertTo-Json -Compress)) | Out-Null
        $lines.Add((@{
            EventName = 'InterfaceSiteCacheSharedStoreState'
            Timestamp = $now.AddSeconds(40).ToString('o')
            Operation = 'SnapshotImported'
        } | ConvertTo-Json -Compress)) | Out-Null
        $lines.Add((@{
            EventName = 'InterfaceSiteCacheSharedStore'
            Timestamp = $now.AddSeconds(41).ToString('o')
            Operation = 'GetHit'
            Site = 'BOYO'
        } | ConvertTo-Json -Compress)) | Out-Null

        Ensure-Directory -Path $outputRoot
        Set-Content -LiteralPath $metricsPath -Value $lines -Encoding utf8

        $result = & $scriptPath -MetricsPath $metricsPath -OutputRoot $outputRoot

        $latestPath = Join-Path -Path $outputRoot -ChildPath 'Logs\Reports\HarnessSmokeSummary-latest.json'
        (Test-Path -LiteralPath $latestPath) | Should Be $true
        $latest = Get-Content -LiteralPath $latestPath -Raw | ConvertFrom-Json
        $latest.PortDiversityMode | Should Be 'Synth'
        $latest.PortDiversity.UsedSynthesizedEvents | Should Be $true
        $result.LatestSummaryPath | Should Be $latestPath
    }

    # LANDMARK: Harness smoke tests - synthetic dataset resolution + latest-pointer behavior
    It 'writes dataset-scoped outputs for synthetic dataset version 5.1' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'SyntheticOutput'
        Ensure-Directory -Path $outputRoot

        $result = & $scriptPath -DatasetVersion '5.1' -OutputRoot $outputRoot

        $datasetLatest = Join-Path -Path $outputRoot -ChildPath 'Logs\Reports\SyntheticSmoke\Synthetic-5.1\HarnessSmokeSummary-latest.json'
        (Test-Path -LiteralPath $datasetLatest) | Should Be $true
        $latest = Get-Content -LiteralPath $datasetLatest -Raw | ConvertFrom-Json
        $latest.DatasetId | Should Be 'Synthetic-5.1'
        $latest.PortDiversityMode | Should Be 'Synth'
        $result.LatestSummaryPath | Should Be $datasetLatest
    }

    It 'fails with a clear error when the synthetic dataset root is missing' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'MissingOutput'
        Ensure-Directory -Path $outputRoot

        $threw = $false
        try {
            & $scriptPath -DatasetVersion '9.9' -OutputRoot $outputRoot
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
    }
}
