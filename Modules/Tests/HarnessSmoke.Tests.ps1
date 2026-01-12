Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Test-HarnessSmoke.ps1'

Describe 'Test-HarnessSmoke' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            throw "Harness smoke script not found at $scriptPath"
        }
    }

    # LANDMARK: Harness smoke tests - minimal metrics fixture coverage
    It 'writes a passing summary for a minimal valid metrics file' {
        $metricsPath = Join-Path -Path $TestDrive -ChildPath 'metrics.json'
        $summaryPath = Join-Path -Path $TestDrive -ChildPath 'HarnessSmokeSummary.json'
        $queueSummaryPath = Join-Path -Path $TestDrive -ChildPath 'QueueDelaySummary.json'
        $portDiversityPath = Join-Path -Path $TestDrive -ChildPath 'PortBatchSiteDiversity.json'
        $portBatchReportPath = Join-Path -Path $TestDrive -ChildPath 'PortBatchReady.json'
        $interfaceSyncReportPath = Join-Path -Path $TestDrive -ChildPath 'InterfaceSyncTiming.json'
        $schedulerReportPath = Join-Path -Path $TestDrive -ChildPath 'ParserSchedulerLaunch.json'
        $sharedCacheStoreStatePath = Join-Path -Path $TestDrive -ChildPath 'SharedCacheStoreState.json'
        $siteCacheProviderReasonsPath = Join-Path -Path $TestDrive -ChildPath 'SiteCacheProviderReasons.json'

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
            EventName = 'PortBatchReady'
            Timestamp = $now.AddSeconds(30).ToString('o')
            Hostname = 'WLLS-A01-AS-01'
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
            EventName = 'InterfaceSyncTiming'
            Timestamp = $now.AddSeconds(35).ToString('o')
            Site = 'WLLS'
            Hostname = 'WLLS-A01-AS-01'
            UiCloneDurationMs = 1
            StreamDispatchDurationMs = 1
            DiffDurationMs = 1
            SiteCacheUpdateDurationMs = 3
            SiteCacheProvider = 'Cache'
            SiteCacheProviderReason = 'SharedCacheMatch'
            SiteCacheFetchDurationMs = 12
        } | ConvertTo-Json -Compress)) | Out-Null
        $lines.Add((@{
            EventName = 'ParserSchedulerLaunch'
            Timestamp = $now.AddSeconds(40).ToString('o')
            Site = 'BOYO'
            ActiveWorkers = 1
            ActiveSites = 2
            ThreadBudget = 8
            QueuedJobs = 0
            QueuedSites = 2
        } | ConvertTo-Json -Compress)) | Out-Null
        $lines.Add((@{
            EventName = 'ParserSchedulerLaunch'
            Timestamp = $now.AddSeconds(50).ToString('o')
            Site = 'WLLS'
            ActiveWorkers = 1
            ActiveSites = 2
            ThreadBudget = 8
            QueuedJobs = 0
            QueuedSites = 2
        } | ConvertTo-Json -Compress)) | Out-Null
        $lines.Add((@{
            EventName = 'InterfaceSiteCacheSharedStoreState'
            Timestamp = $now.AddSeconds(60).ToString('o')
            Operation = 'SnapshotImported'
        } | ConvertTo-Json -Compress)) | Out-Null
        $lines.Add((@{
            EventName = 'InterfaceSiteCacheSharedStore'
            Timestamp = $now.AddSeconds(61).ToString('o')
            Operation = 'GetHit'
            Site = 'BOYO'
        } | ConvertTo-Json -Compress)) | Out-Null

        Set-Content -LiteralPath $metricsPath -Value $lines -Encoding utf8

        $result = & $scriptPath -MetricsPath $metricsPath `
            -QueueSummaryPath $queueSummaryPath `
            -PortDiversityOutputPath $portDiversityPath `
            -PortBatchReportPath $portBatchReportPath `
            -InterfaceSyncReportPath $interfaceSyncReportPath `
            -SchedulerReportPath $schedulerReportPath `
            -SharedCacheStoreStatePath $sharedCacheStoreStatePath `
            -SiteCacheProviderReasonsPath $siteCacheProviderReasonsPath `
            -SummaryPath $summaryPath `
            -PassThru

        $result.Passed | Should Be $true
        $result.QueueSummary.Pass | Should Be $true
        $result.PortDiversity.Pass | Should Be $true
        $result.PortDiversity.Mode | Should Be 'Synth'
        $result.PortDiversity.UsedSynthesizedEvents | Should Be $true
        $result.UsedSynthesizedEvents | Should Be $true
        (Test-Path -LiteralPath $summaryPath) | Should Be $true
        (Test-Path -LiteralPath $queueSummaryPath) | Should Be $true
        (Test-Path -LiteralPath $portDiversityPath) | Should Be $true
        (Test-Path -LiteralPath $sharedCacheStoreStatePath) | Should Be $true
        (Test-Path -LiteralPath $siteCacheProviderReasonsPath) | Should Be $true
    }

    It 'records Existing mode when an explicit diversity report is supplied' {
        $metricsPath = Join-Path -Path $TestDrive -ChildPath 'metrics-existing.json'
        $summaryPath = Join-Path -Path $TestDrive -ChildPath 'HarnessSmokeSummary-existing.json'
        $queueSummaryPath = Join-Path -Path $TestDrive -ChildPath 'QueueDelaySummary-existing.json'
        $portDiversityPath = Join-Path -Path $TestDrive -ChildPath 'PortBatchSiteDiversity-existing.json'
        $portBatchReportPath = Join-Path -Path $TestDrive -ChildPath 'PortBatchReady-existing.json'
        $interfaceSyncReportPath = Join-Path -Path $TestDrive -ChildPath 'InterfaceSyncTiming-existing.json'
        $schedulerReportPath = Join-Path -Path $TestDrive -ChildPath 'ParserSchedulerLaunch-existing.json'
        $sharedCacheStoreStatePath = Join-Path -Path $TestDrive -ChildPath 'SharedCacheStoreState-existing.json'
        $siteCacheProviderReasonsPath = Join-Path -Path $TestDrive -ChildPath 'SiteCacheProviderReasons-existing.json'

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
            Timestamp = $now.AddSeconds(5).ToString('o')
            Hostname = 'BOYO-A01-AS-01'
            PortsCommitted = 5
            ChunkSize = 5
            Synthesized = $true
        } | ConvertTo-Json -Compress)) | Out-Null
        $lines.Add((@{
            EventName = 'InterfaceSyncTiming'
            Timestamp = $now.AddSeconds(6).ToString('o')
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
            Timestamp = $now.AddSeconds(7).ToString('o')
            Site = 'BOYO'
            ActiveWorkers = 1
            ActiveSites = 1
            ThreadBudget = 4
            QueuedJobs = 0
            QueuedSites = 1
        } | ConvertTo-Json -Compress)) | Out-Null
        $lines.Add((@{
            EventName = 'InterfaceSiteCacheSharedStoreState'
            Timestamp = $now.AddSeconds(6).ToString('o')
            Operation = 'SnapshotImported'
        } | ConvertTo-Json -Compress)) | Out-Null
        Set-Content -LiteralPath $metricsPath -Value $lines -Encoding utf8

        $portSummary = [pscustomobject]@{
            MaxAllowedConsecutive = 8
            UsedSynthesizedEvents = $false
            SiteStreaks = @(
                [pscustomobject]@{
                    Site = 'BOYO'
                    MaxCount = 1
                }
            )
        }
        $portSummary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $portDiversityPath -Encoding utf8

        $schedulerSummary = [pscustomobject]@{
            GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            FilesAnalyzed = $metricsPath
            TotalLaunchEvents = 1
            UniqueSites = 1
            MaxObservedStreak = 1
            Violations = @()
        }
        $schedulerSummary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $schedulerReportPath -Encoding utf8

        $result = & $scriptPath -MetricsPath $metricsPath `
            -PortDiversityMode Existing `
            -PortDiversityOutputPath $portDiversityPath `
            -QueueSummaryPath $queueSummaryPath `
            -PortBatchReportPath $portBatchReportPath `
            -InterfaceSyncReportPath $interfaceSyncReportPath `
            -SchedulerReportPath $schedulerReportPath `
            -SharedCacheStoreStatePath $sharedCacheStoreStatePath `
            -SiteCacheProviderReasonsPath $siteCacheProviderReasonsPath `
            -SummaryPath $summaryPath `
            -PassThru

        $result.PortDiversity.Mode | Should Be 'Existing'
        $result.PortDiversity.UsedExistingReport | Should Be $true
        $result.PortDiversity.Pass | Should Be $true
    }

    It 'throws when Existing mode report is missing' {
        $metricsPath = Join-Path -Path $TestDrive -ChildPath 'metrics-missing-report.json'
        $summaryPath = Join-Path -Path $TestDrive -ChildPath 'HarnessSmokeSummary-missing.json'
        $lines = New-Object System.Collections.Generic.List[string]
        $now = Get-Date
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
            Timestamp = $now.AddSeconds(12).ToString('o')
            Hostname = 'BOYO-A01-AS-01'
            PortsCommitted = 5
            ChunkSize = 5
            Synthesized = $true
        } | ConvertTo-Json -Compress)) | Out-Null
        Set-Content -LiteralPath $metricsPath -Value $lines -Encoding utf8

        $threw = $false
        try {
            & $scriptPath -MetricsPath $metricsPath -PortDiversityMode Existing -PortDiversityOutputPath (Join-Path -Path $TestDrive -ChildPath 'missing.json') -SummaryPath $summaryPath
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
    }

    It 'throws when the metrics file is missing' {
        $threw = $false
        try {
            & $scriptPath -MetricsPath (Join-Path -Path $TestDrive -ChildPath 'missing.json') -SummaryPath (Join-Path -Path $TestDrive -ChildPath 'summary.json')
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
    }
}
