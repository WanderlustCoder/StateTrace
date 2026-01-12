Set-StrictMode -Version Latest

Describe 'WarmRun.Telemetry helper functions' {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSCommandPath) "..\WarmRun.Telemetry.psm1"
        Import-Module (Resolve-Path $modulePath) -Force
    }

    AfterAll {
        Remove-Module WarmRun.Telemetry -Force -ErrorAction SilentlyContinue
    }

    function New-SampleInterfaceSiteCacheMetric {
        param(
            [string]$Site = 'TEST',
            [string]$CacheStatus = 'Hit',
            [string]$Provider = 'Cache',
            [nullable[double]]$HydrationDurationMs = 0,
            [string]$PreviousHostSample = $null
        )

        $metric = [pscustomobject]@{
            EventName                       = 'InterfaceSiteCacheMetrics'
            Timestamp                       = Get-Date
            Site                            = $Site
            CacheStatus                     = $CacheStatus
            Provider                        = $Provider
            HydrationDurationMs             = $HydrationDurationMs
            SnapshotDurationMs              = 0
            HostMapDurationMs               = 0
            HostCount                       = 1
            TotalRows                       = 1
            HostMapSignatureMatchCount      = 1
            HostMapSignatureRewriteCount    = 0
            HostMapCandidateMissingCount    = 0
            HostMapCandidateFromPreviousCount = 1
            PreviousHostCount               = 1
            PreviousSnapshotStatus          = 'CacheHit'
            PreviousSnapshotHostMapType     = 'Dictionary'
        }

        if ($PreviousHostSample) {
            Add-Member -InputObject $metric -MemberType NoteProperty -Name 'PreviousHostSample' -Value $PreviousHostSample
        }

        return $metric
    }

    It 'sets Hostname from PreviousHostSample when InterfaceSiteCacheMetrics lacks Hostname' {
        $metric = New-SampleInterfaceSiteCacheMetric -PreviousHostSample 'TEST-A01-AS-01'
        $result = @(
            WarmRun.Telemetry\Convert-MetricsToSummary -PassLabel 'TestPass' -Metrics @($metric)
        )

        @($result).Count | Should Be 1
        $result[0].Hostname | Should Be 'TEST-A01-AS-01'
    }

    It 'still exposes a Hostname property when no host data is present' {
        $metric = New-SampleInterfaceSiteCacheMetric
        $result = @(
            WarmRun.Telemetry\Convert-MetricsToSummary -PassLabel 'TestPass' -Metrics @($metric)
        )

        @($result).Count | Should Be 1
        { $null = $result[0].Hostname } | Should Not Throw
        $result[0].Hostname | Should Be $null
    }

    It 'propagates provider reasons from InterfaceSyncTiming events when metrics lack hostnames' {
        $summary = [pscustomobject]@{
            Site                    = 'TEST'
            Hostname                = $null
            SiteCacheProviderReason = $null
            Metrics                 = [pscustomobject]@{
                PreviousHostSample = 'TEST-A01-AS-01'
            }
        }

        $syncEvent = [pscustomobject]@{
            EventName               = 'InterfaceSyncTiming'
            Site                    = 'TEST'
            Hostname                = 'TEST-A01-AS-01'
            SiteCacheProviderReason = 'SkipSiteCacheUpdate'
        }

        $result = WarmRun.Telemetry\Resolve-SiteCacheProviderReasons -Summaries @($summary) -InterfaceSyncEvents @($syncEvent)
        @($result).Count | Should Be 1
        $result[0].SiteCacheProviderReason | Should Be 'SkipSiteCacheUpdate'
    }

    It 'propagates provider reasons from DatabaseWriteBreakdown events when present' {
        $summary = [pscustomobject]@{
            Site                    = 'TEST'
            Hostname                = 'TEST-A01-AS-02'
            SiteCacheProviderReason = $null
            Metrics                 = [pscustomobject]@{}
        }

        $dbEvent = [pscustomobject]@{
            EventName               = 'DatabaseWriteBreakdown'
            Site                    = 'TEST'
            Hostname                = 'TEST-A01-AS-02'
            SiteCacheProviderReason = 'SharedCacheUnavailable'
        }

        $result = WarmRun.Telemetry\Resolve-SiteCacheProviderReasons -Summaries @($summary) -DatabaseEvents @($dbEvent)
        @($result).Count | Should Be 1
        $result[0].SiteCacheProviderReason | Should Be 'SharedCacheUnavailable'
    }

    It 'does not override an existing provider reason on the summary' {
        $summary = [pscustomobject]@{
            Site                    = 'TEST'
            Hostname                = 'TEST-A01-AS-02'
            SiteCacheProviderReason = 'SharedCacheOnly'
        }

        $dbEvent = [pscustomobject]@{
            EventName               = 'DatabaseWriteBreakdown'
            Site                    = 'TEST'
            Hostname                = 'TEST-A01-AS-02'
            SiteCacheProviderReason = 'SkipSiteCacheUpdate'
        }

        $result = WarmRun.Telemetry\Resolve-SiteCacheProviderReasons -Summaries @($summary) -DatabaseEvents @($dbEvent)
        $result[0].SiteCacheProviderReason | Should Be 'SharedCacheOnly'
    }

    It 'infers SkipSiteCacheUpdate when database telemetry omits the reason' {
        $summary = [pscustomobject]@{
            Site                    = 'TEST'
            Hostname                = 'TEST-A01-AS-03'
            SiteCacheProviderReason = $null
            Metrics                 = [pscustomobject]@{}
        }

        $dbEvent = [pscustomobject]@{
            EventName            = 'DatabaseWriteBreakdown'
            Site                 = 'TEST'
            Hostname             = 'TEST-A01-AS-03'
            SiteCacheProvider    = 'Unknown'
            SiteCacheFetchStatus = 'Disabled'
            SkipSiteCacheUpdate  = $true
        }

        $result = WarmRun.Telemetry\Resolve-SiteCacheProviderReasons -Summaries @($summary) -DatabaseEvents @($dbEvent)
        $result[0].SiteCacheProviderReason | Should Be 'SkipSiteCacheUpdate'
    }

    It 'flags SharedCacheUnavailable when cache fetch is skipped without the skip flag' {
        $summary = [pscustomobject]@{
            Site                    = 'TEST'
            Hostname                = 'TEST-A01-AS-04'
            SiteCacheProviderReason = $null
            Metrics                 = [pscustomobject]@{}
        }

        $dbEvent = [pscustomobject]@{
            EventName            = 'DatabaseWriteBreakdown'
            Site                 = 'TEST'
            Hostname             = 'TEST-A01-AS-04'
            SiteCacheProvider    = 'Unknown'
            SiteCacheFetchStatus = 'SkippedEmpty'
            SkipSiteCacheUpdate  = $false
        }

        $result = WarmRun.Telemetry\Resolve-SiteCacheProviderReasons -Summaries @($summary) -DatabaseEvents @($dbEvent)
        $result[0].SiteCacheProviderReason | Should Be 'SharedCacheUnavailable'
    }

    It 'falls back to summary provider data when no telemetry events match' {
        $metric = New-SampleInterfaceSiteCacheMetric -Provider 'Cache' -PreviousHostSample 'TEST-A01-AS-05'
        $summary = WarmRun.Telemetry\Convert-MetricsToSummary -PassLabel 'TestPass' -Metrics @($metric)

        $result = WarmRun.Telemetry\Resolve-SiteCacheProviderReasons -Summaries @($summary)
        @($result).Count | Should Be 1
        $result[0].SiteCacheProviderReason | Should Be 'AccessCacheHit'
    }

    It 'weights provider metrics using HostCount when summarizing' {
        $summaries = @(
            [pscustomobject]@{ Provider = 'Cache'; HostCount = 2 },
            [pscustomobject]@{ Provider = 'Refresh'; HostCount = 1 },
            [pscustomobject]@{ Provider = $null; HostCount = 0 }
        )

        $metrics = WarmRun.Telemetry\Measure-ProviderMetricsFromSummaries -Summaries $summaries
        $metrics | Should Not Be $null
        $metrics.ProviderCounts['Cache'] | Should Be 2
        $metrics.ProviderCounts['Refresh'] | Should Be 1
        $metrics.ProviderCounts['Unknown'] | Should Be 1
        $metrics.HitCount | Should Be 2
        $metrics.MissCount | Should Be 2
        $metrics.HitRatio | Should Be 50
    }
}
