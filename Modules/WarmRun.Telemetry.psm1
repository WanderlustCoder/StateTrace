Set-StrictMode -Version Latest

function ConvertTo-NormalizedProviderCounts {
    param(
        [hashtable]$ProviderCounts
    )

    $normalized = @{}
    if (-not $ProviderCounts) {
        return $normalized
    }

    foreach ($key in $ProviderCounts.Keys) {
        $label = ('' + $key).Trim()
        if ([string]::IsNullOrWhiteSpace($label)) {
            $label = 'Unknown'
        }
        $value = 0
        try {
            $value = [int]$ProviderCounts[$key]
        } catch {
            $value = 0
        }
        if ($normalized.ContainsKey($label)) {
            $normalized[$label] += $value
        } else {
            $normalized[$label] = $value
        }
    }

    return $normalized
}

function Convert-MetricsToSummary {
    param(
        [Parameter(Mandatory)]
        [string]$PassLabel,
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable]$Metrics
    )

    $summaries = foreach ($metric in $Metrics | Sort-Object { $_.Timestamp }) {
        $timestamp = $metric.Timestamp
        if ($timestamp -isnot [datetime] -and -not [string]::IsNullOrWhiteSpace($timestamp)) {
            $timestamp = [datetime]::Parse($timestamp)
        }

        $providerReason = $null
        if ($metric -and $metric.PSObject -and $metric.PSObject.Properties.Name -contains 'SiteCacheProviderReason') {
            $providerReason = $metric.SiteCacheProviderReason
        }

        $hostName = $null
        if ($metric -and $metric.PSObject) {
            $metricProperties = $metric.PSObject.Properties.Name
            if ($metricProperties -contains 'Hostname') {
                $hostName = $metric.Hostname
            } elseif ($metricProperties -contains 'HostName') {
                $hostName = $metric.HostName
            } elseif ($metricProperties -contains 'Host') {
                $hostName = $metric.Host
            }

            if ([string]::IsNullOrWhiteSpace($hostName) -and $metricProperties -contains 'PreviousHostSample') {
                $hostName = $metric.PreviousHostSample
            } elseif ([string]::IsNullOrWhiteSpace($hostName) -and $metricProperties -contains 'HostSample') {
                $hostName = $metric.HostSample
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($hostName)) {
            $hostName = ('' + $hostName).Trim()
        } else {
            $hostName = $null
        }

        [pscustomobject]@{
            PassLabel                     = $PassLabel
            Site                          = $metric.Site
            Hostname                      = $hostName
            Timestamp                     = $timestamp
            CacheStatus                   = $metric.CacheStatus
            Provider                      = $metric.Provider
            SiteCacheProviderReason       = $providerReason
            HydrationDurationMs           = $metric.HydrationDurationMs
            SnapshotDurationMs            = $metric.SnapshotDurationMs
            HostMapDurationMs             = $metric.HostMapDurationMs
            HostCount                     = $metric.HostCount
            TotalRows                     = $metric.TotalRows
            HostMapSignatureMatchCount    = $metric.HostMapSignatureMatchCount
            HostMapSignatureRewriteCount  = $metric.HostMapSignatureRewriteCount
            HostMapCandidateMissingCount  = $metric.HostMapCandidateMissingCount
            HostMapCandidateFromPrevious  = $metric.HostMapCandidateFromPreviousCount
            PreviousHostCount             = $metric.PreviousHostCount
            PreviousSnapshotStatus        = $metric.PreviousSnapshotStatus
            PreviousSnapshotHostMapType   = $metric.PreviousSnapshotHostMapType
            Metrics                       = $metric
        }
    }

    return $summaries
}

function Measure-ProviderMetricsFromSummaries {
    param(
        [System.Collections.IEnumerable]$Summaries
    )

    if (-not $Summaries) {
        return $null
    }

    $providerCounts = @{}
    $totalWeight = 0

    foreach ($summary in $Summaries) {
        if (-not $summary) { continue }

        $providerValue = ''
        if ($summary.PSObject.Properties.Name -contains 'Provider') {
            $providerValue = ('' + $summary.Provider).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($providerValue)) {
            $providerValue = 'Unknown'
        }

        $weight = 1
        if ($summary.PSObject.Properties.Name -contains 'HostCount') {
            try {
                $hostWeight = [int]$summary.HostCount
                if ($hostWeight -gt 0) {
                    $weight = $hostWeight
                }
            } catch { }
        }

        if ($providerCounts.ContainsKey($providerValue)) {
            $providerCounts[$providerValue] += $weight
        } else {
            $providerCounts[$providerValue] = $weight
        }
        $totalWeight += $weight
    }

    $hitCount = 0
    foreach ($cacheKey in @('Cache','SharedCache')) {
        if ($providerCounts.ContainsKey($cacheKey)) {
            $hitCount += [int]$providerCounts[$cacheKey]
        }
    }
    $missCount = [Math]::Max(0, $totalWeight - $hitCount)
    $hitRatio = $null
    if ($totalWeight -gt 0) {
        $hitRatio = [Math]::Round(($hitCount / $totalWeight) * 100, 2)
    }

    return [pscustomobject]@{
        ProviderCounts = $providerCounts
        TotalWeight    = $totalWeight
        HitCount       = $hitCount
        MissCount      = $missCount
        HitRatio       = $hitRatio
    }
}

function Get-HostKeyFromTelemetryEvent {
    param(
        [Parameter(Mandatory)]
        $Event
    )

    if (-not $Event -or -not $Event.PSObject) {
        return $null
    }

    $hostKey = $null
    foreach ($property in @('Hostname','HostName','Host','PreviousHostSample','HostSample')) {
        if ($Event.PSObject.Properties.Name -contains $property) {
            $candidate = ('' + $Event.$property).Trim()
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                $hostKey = $candidate
                break
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($hostKey)) {
        return $null
    }

    return $hostKey
}

function Get-HostKeyFromMetricsSummary {
    param(
        [Parameter(Mandatory)]
        $Summary
    )

    if (-not $Summary -or -not $Summary.PSObject) {
        return $null
    }

    $hostKey = $null
    if ($Summary.PSObject.Properties.Name -contains 'Hostname') {
        $hostKey = ('' + $Summary.Hostname).Trim()
    }

    if ([string]::IsNullOrWhiteSpace($hostKey) -and $Summary.PSObject.Properties.Name -contains 'Metrics') {
        $metricsRecord = $Summary.Metrics
        if ($metricsRecord -and $metricsRecord.PSObject) {
            foreach ($property in @('PreviousHostSample','Hostname','HostName','Host','HostSample')) {
                if ($metricsRecord.PSObject.Properties.Name -contains $property) {
                    $candidate = ('' + $metricsRecord.$property).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                        $hostKey = $candidate
                        break
                    }
                }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($hostKey)) {
        return $null
    }

    return $hostKey
}

function Get-SiteCacheProviderReasonFallback {
    param(
        $Record
    )

    if (-not $Record -or -not $Record.PSObject) {
        return $null
    }

    $getTrimmedValue = {
        param($target, [string[]]$PropertyNames)

        if (-not $target -or -not $target.PSObject) { return $null }
        foreach ($name in $PropertyNames) {
            if ($target.PSObject.Properties.Name -contains $name) {
                $candidate = ('' + $target.$name)
                if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                    return $candidate.Trim()
                }
            }
        }
        return $null
    }

    $provider = & $getTrimmedValue $Record @('SiteCacheProvider','Provider')
    $status = & $getTrimmedValue $Record @('SiteCacheFetchStatus','CacheStatus')
    $skipFlag = $false
    if ($Record.PSObject.Properties.Name -contains 'SkipSiteCacheUpdate') {
        try {
            $skipFlag = [bool]$Record.SkipSiteCacheUpdate
        } catch {
            $skipFlag = $false
        }
    }

    $normalize = {
        param($value)
        if ([string]::IsNullOrWhiteSpace($value)) { return $null }
        return $value.Trim().ToLowerInvariant()
    }

    $providerKey = & $normalize $provider
    $statusKey = & $normalize $status

    switch ($providerKey) {
        'sharedcache' { return 'SharedCacheMatch' }
        'sharedonly' { return 'SharedCacheMatch' }
        'cache' { return 'AccessCacheHit' }
        'refreshed' { return 'AccessRefresh' }
        'refresh' { return 'AccessRefresh' }
        'missingdatabase' { return 'SharedCacheUnavailable' }
    }

    if ($skipFlag) {
        return 'SkipSiteCacheUpdate'
    }

    switch ($statusKey) {
        'sharedonly' { return 'SharedCacheMatch' }
        'hit' { return 'AccessCacheHit' }
        'refreshed' { return 'AccessRefresh' }
        'disabled' { return 'SkipSiteCacheUpdate' }
        'skippedempty' { return 'SharedCacheUnavailable' }
    }

    if ($providerKey -eq 'unknown') {
        if ($statusKey -eq 'skippedempty') {
            return 'SharedCacheUnavailable'
        }
        return 'DatabaseQueryFallback'
    }

    return $null
}

function Resolve-SiteCacheProviderReasons {
    param(
        [System.Collections.IEnumerable]$Summaries,
        [System.Collections.IEnumerable]$DatabaseEvents,
        [System.Collections.IEnumerable]$InterfaceSyncEvents
    )

    $results = @()
    if ($Summaries) {
        $results = @($Summaries)
    }
    if (-not $results -or $results.Count -eq 0) {
        return $results
    }

    $providerReasonMap = @{}
    $addReason = {
        param($eventRecord)
        if (-not $eventRecord) { return }

        $reasonValue = $null
        if ($eventRecord.PSObject.Properties.Name -contains 'SiteCacheProviderReason') {
            $reasonValue = ('' + $eventRecord.SiteCacheProviderReason).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($reasonValue)) {
            $reasonValue = Get-SiteCacheProviderReasonFallback -Record $eventRecord
        }
        if ([string]::IsNullOrWhiteSpace($reasonValue)) { return }

        $siteKey = ''
        if ($eventRecord.PSObject.Properties.Name -contains 'Site') {
            $siteKey = ('' + $eventRecord.Site).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($siteKey)) { return }

        $hostKey = Get-HostKeyFromTelemetryEvent -Event $eventRecord
        if ([string]::IsNullOrWhiteSpace($hostKey)) { return }

        $mapKey = '{0}|{1}' -f $siteKey, $hostKey
        if (-not $providerReasonMap.ContainsKey($mapKey)) {
            $providerReasonMap[$mapKey] = $reasonValue
        }
    }

    foreach ($eventRecord in @($InterfaceSyncEvents)) {
        & $addReason $eventRecord
    }
    foreach ($eventRecord in @($DatabaseEvents)) {
        & $addReason $eventRecord
    }

    foreach ($summary in $results) {
        if (-not $summary) { continue }
        $currentReason = $summary.SiteCacheProviderReason
        if (-not [string]::IsNullOrWhiteSpace($currentReason)) { continue }

        $siteKey = ''
        if ($summary.PSObject.Properties.Name -contains 'Site') {
            $siteKey = ('' + $summary.Site).Trim()
        }
        $mapApplied = $false
        if (-not [string]::IsNullOrWhiteSpace($siteKey)) {
            $hostKey = Get-HostKeyFromMetricsSummary -Summary $summary
            if (-not [string]::IsNullOrWhiteSpace($hostKey)) {
                $mapKey = '{0}|{1}' -f $siteKey, $hostKey
                if ($providerReasonMap.ContainsKey($mapKey)) {
                    $summary.SiteCacheProviderReason = $providerReasonMap[$mapKey]
                    $mapApplied = $true
                }
            }
        }

        if (-not $mapApplied -and [string]::IsNullOrWhiteSpace($summary.SiteCacheProviderReason)) {
            $fallbackReason = Get-SiteCacheProviderReasonFallback -Record $summary
            if (-not [string]::IsNullOrWhiteSpace($fallbackReason)) {
                $summary.SiteCacheProviderReason = $fallbackReason
            }
        }
    }

    return $results
}

Export-ModuleMember -Function `
    ConvertTo-NormalizedProviderCounts, `
    Convert-MetricsToSummary, `
    Measure-ProviderMetricsFromSummaries, `
    Resolve-SiteCacheProviderReasons, `
    Get-HostKeyFromTelemetryEvent, `
    Get-HostKeyFromMetricsSummary
