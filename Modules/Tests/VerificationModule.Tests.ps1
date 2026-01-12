Set-StrictMode -Version Latest

$modulePath = Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath '..\VerificationModule.psm1'
Import-Module -Name $modulePath -Force

Describe 'Test-WarmRunRegressionSummary' {
    It 'passes when summary meets default thresholds' {
        $summary = [pscustomobject]@{
            ImprovementPercent             = 48.5
            WarmInterfaceCallAvgMs         = 180.0
            ColdInterfaceCallAvgMs         = 420.0
            WarmCacheProviderHitCount      = 37
            WarmCacheProviderMissCount     = 0
            WarmCacheHitRatioPercent       = 100
            WarmSignatureMatchMissCount    = 0
            WarmSignatureRewriteTotal      = 0
        }

        $result = Test-WarmRunRegressionSummary -Summary $summary
        $result.Pass | Should Be $true
        $result.Messages | Should BeNullOrEmpty
        $result.Thresholds.MinimumImprovementPercent | Should Be 25
    }

    It 'fails when improvement percent is below minimum' {
        $summary = [pscustomobject]@{
            ImprovementPercent             = 10
            WarmInterfaceCallAvgMs         = 390.0
            ColdInterfaceCallAvgMs         = 400.0
            WarmCacheProviderHitCount      = 37
            WarmCacheProviderMissCount     = 0
            WarmCacheHitRatioPercent       = 100
            WarmSignatureMatchMissCount    = 0
            WarmSignatureRewriteTotal      = 0
        }

        $result = Test-WarmRunRegressionSummary -Summary $summary
        $result.Pass | Should Be $false
        ($result.Violations -contains 'ImprovementPercent') | Should Be $true
    }

    It 'fails when cache misses exceed maximum' {
        $summary = [pscustomobject]@{
            ImprovementPercent             = 55
            WarmInterfaceCallAvgMs         = 180.0
            ColdInterfaceCallAvgMs         = 420.0
            WarmCacheProviderHitCount      = 30
            WarmCacheProviderMissCount     = 7
            WarmCacheHitRatioPercent       = 81
            WarmSignatureMatchMissCount    = 0
            WarmSignatureRewriteTotal      = 0
        }

        $result = Test-WarmRunRegressionSummary -Summary $summary -MinimumImprovementPercent 40 -MinimumCacheHitRatioPercent 95 -MaximumWarmCacheMissCount 0
        $result.Pass | Should Be $false
        ($result.Violations -contains 'WarmCacheMissCount') | Should Be $true
        ($result.Violations -contains 'HitRatio') | Should Be $true
    }
}

Describe 'Test-SharedCacheSummaryCoverage' {
    It 'passes when summary meets minimum thresholds and required sites' {
        $entries = @(
            [pscustomobject]@{ Site = 'BOYO'; Hosts = 12; TotalRows = 480; CachedAt = (Get-Date) },
            [pscustomobject]@{ Site = 'WLLS'; Hosts = 20; TotalRows = 960; CachedAt = (Get-Date) }
        )

        $result = Test-SharedCacheSummaryCoverage -Summary $entries -MinimumSiteCount 2 -MinimumHostCount 10 -MinimumTotalRowCount 500 -RequiredSites @('BOYO','WLLS')
        $result.Pass | Should Be $true
        $result.Statistics.SiteCount | Should Be 2
        $result.RequiredSitesMissing | Should BeNullOrEmpty
    }

    It 'parses JSON summary from disk and fails when required site missing' {
        $entries = @(
            [pscustomobject]@{ Site = 'WLLS'; Hosts = 1; TotalRows = 48; CachedAt = (Get-Date) }
        )
        $json = $entries | ConvertTo-Json -Depth 3
        $jsonPath = Join-Path -Path $TestDrive -ChildPath 'SharedCacheSnapshot-20251106-summary.json'
        Set-Content -LiteralPath $jsonPath -Value $json -Encoding utf8

        $result = Test-SharedCacheSummaryCoverage -Summary $jsonPath -MinimumSiteCount 2 -RequiredSites @('BOYO','WLLS')
        $result.Pass | Should Be $false
        ($result.Violations -contains 'SiteCount') | Should Be $true
        ($result.Violations -contains 'RequiredSites') | Should Be $true
        ($result.RequiredSitesMissing -contains 'BOYO') | Should Be $true
    }
}

# LANDMARK: ST-B-007 shared cache diagnostics gating tests
Describe 'Test-SharedCacheDiagnostics' {
    It 'passes when snapshot imported and access refresh is within threshold' {
        $storeSummary = [pscustomobject]@{ SnapshotImported = 4 }
        $providerSummary = [pscustomobject]@{ AccessRefresh = 0 }

        $result = Test-SharedCacheDiagnostics -StoreSummary @($storeSummary) -ProviderSummary @($providerSummary)
        $result.Pass | Should Be $true
        $result.SnapshotImportedTotal | Should Be 4
        $result.AccessRefreshTotal | Should Be 0
    }

    It 'fails when snapshot imported count is zero' {
        $storeSummary = [pscustomobject]@{ SnapshotImported = 0 }
        $providerSummary = [pscustomobject]@{ AccessRefresh = 0 }

        $result = Test-SharedCacheDiagnostics -StoreSummary @($storeSummary) -ProviderSummary @($providerSummary)
        $result.Pass | Should Be $false
        ($result.Violations -contains 'SnapshotImported') | Should Be $true
    }

    It 'fails when access refresh exceeds the maximum' {
        $storeSummary = [pscustomobject]@{ SnapshotImported = 2 }
        $providerSummary = [pscustomobject]@{ AccessRefresh = 1 }

        $result = Test-SharedCacheDiagnostics -StoreSummary @($storeSummary) -ProviderSummary @($providerSummary) -MaximumAccessRefreshCount 0
        $result.Pass | Should Be $false
        ($result.Violations -contains 'AccessRefresh') | Should Be $true
    }
}

Describe 'Test-InterfacePortQueueDelay' {
    It 'passes when delays stay under thresholds' {
        $events = @(
            [pscustomobject]@{ QueueBuildDelayMs = 45; QueueBuildDurationMs = 18 },
            [pscustomobject]@{ QueueBuildDelayMs = 60; QueueBuildDurationMs = 19 },
            [pscustomobject]@{ QueueBuildDelayMs = 72; QueueBuildDurationMs = 21 },
            [pscustomobject]@{ QueueBuildDelayMs = 48; QueueBuildDurationMs = 17 }
        )

        $result = Test-InterfacePortQueueDelay -Events $events -MaximumP95Ms 120 -MaximumP99Ms 200 -MinimumEventCount 3
        $result.Pass | Should Be $true
        $result.Result | Should Be 'Pass'
        $result.Statistics.QueueBuildDelayMs.SampleCount | Should Be 4
        $result.Violations | Should BeNullOrEmpty
    }

    # LANDMARK: Queue delay sample floor - validate insufficient data handling
    It 'flags insufficient data when sample count is below the minimum' {
        $events = @(
            [pscustomobject]@{ QueueBuildDelayMs = 15 },
            [pscustomobject]@{ QueueBuildDelayMs = 20 },
            [pscustomobject]@{ QueueBuildDelayMs = 18 },
            [pscustomobject]@{ QueueBuildDelayMs = 22 }
        )

        $result = Test-InterfacePortQueueDelay -Events $events -MaximumP95Ms 120 -MaximumP99Ms 200 -MinimumEventCount 6
        $result.Pass | Should Be $false
        $result.Result | Should Be 'InsufficientData'
        ($result.Violations -contains 'InsufficientData') | Should Be $true
    }

    It 'passes when delays meet thresholds and sample count meets minimum' {
        $events = 1..10 | ForEach-Object { [pscustomobject]@{ QueueBuildDelayMs = 18 } }

        $result = Test-InterfacePortQueueDelay -Events $events -MaximumP95Ms 120 -MaximumP99Ms 200 -MinimumEventCount 10
        $result.Pass | Should Be $true
        $result.Result | Should Be 'Pass'
        $result.Statistics.QueueBuildDelayMs.SampleCount | Should Be 10
    }

    It 'fails when P95 exceeds maximum or events missing' {
        $events = @(
            [pscustomobject]@{ QueueDelayMs = 90 },
            [pscustomobject]@{ QueueBuildDelayMs = 250 },
            [pscustomobject]@{ QueueBuildDelayMs = 130 }
        )

        $result = Test-InterfacePortQueueDelay -Events $events -MaximumP95Ms 100 -MaximumP99Ms 180 -MinimumEventCount 3
        $result.Pass | Should Be $false
        $result.Result | Should Be 'Fail'
        ($result.Violations -contains 'QueueDelayP95') | Should Be $true
    }
}
