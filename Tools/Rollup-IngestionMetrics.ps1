[CmdletBinding()]
param(
    [string]$MetricsDirectory = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Logs\IngestionMetrics'),
    [string[]]$MetricFile,
    [string[]]$MetricFileNameFilter,
    [int]$Latest = 0,
    [string]$OutputPath,
    [switch]$IncludePerSite,
    [switch]$IncludeSiteCache,
    [switch]$PassThru,
    [switch]$FailOnWarnings,
    [switch]$GenerateHashManifest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$statisticsModulePath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Modules\StatisticsModule.psm1'
if (-not (Test-Path -LiteralPath $statisticsModulePath)) {
    throw "StatisticsModule not found at $statisticsModulePath"
}
Import-Module -Name $statisticsModulePath -Force -ErrorAction Stop

$script:IncludeSiteCacheMetrics = $IncludeSiteCache.IsPresent
$script:RequiredUserActions = @('ScanLogs','LoadFromDb','HelpQuickstart','InterfacesView','CompareView','SpanSnapshot')

# ST-M-004: Warning tracking for hygiene checks
$script:WarningCount = 0
$script:WarningMessages = [System.Collections.Generic.List[string]]::new()
$script:ProcessedFileHashes = @{}

function Get-FileHashSHA256 {
    param([string]$Path)
    try {
        $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop
        return $hash.Hash
    } catch {
        return $null
    }
}

function Add-DictionaryCount {
    param(
        [Parameter(Mandatory)][hashtable]$Dictionary,
        [string]$Key
    )

    if ([string]::IsNullOrWhiteSpace($Key)) {
        return
    }

    if (-not $Dictionary.ContainsKey($Key)) {
        $Dictionary[$Key] = 0
    }
    $Dictionary[$Key] = [int]$Dictionary[$Key] + 1
}

function New-MetricAccumulator {
    $accumulator = @{
        ParseDurations              = [System.Collections.Generic.List[double]]::new()
        ParseDurationSum            = 0.0
        ParseDurationMax            = [double]::NegativeInfinity
        ParseDurationSuccess        = 0
        ParseDurationFailure        = 0
        WriteLatencies              = [System.Collections.Generic.List[double]]::new()
        WriteLatencySum             = 0.0
        WriteLatencyMax             = [double]::NegativeInfinity
        RowsWrittenTotal            = 0.0
        RowsDeletedTotal            = 0.0
        RowsWrittenCount            = 0
        RowsWrittenHosts            = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        SkippedDuplicateCount       = 0
        SkippedDuplicateHosts       = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        SiteCacheFetchDurations     = [System.Collections.Generic.List[double]]::new()
        SiteCacheFetchDurationSum   = 0.0
        SiteCacheFetchDurationMax   = [double]::NegativeInfinity
        SiteCacheFetchCount         = 0
        SiteCacheFetchZeroCount     = 0
        SiteCacheFetchStatusCounts  = @{}
        SiteCacheProviderCounts     = @{}
        UserActionCounts            = @{}
        # LANDMARK: Diff telemetry rollup - accumulator additions for usage rate and drift detection
        DiffUsageCount              = 0
        DiffUsageNumeratorSum       = 0.0
        DiffUsageDenominatorSum     = 0.0
        DiffUsageStatusCounts       = @{}
        DriftDetectionDurations     = [System.Collections.Generic.List[double]]::new()
        DriftDetectionDurationSum   = 0.0
        DriftDetectionDurationMax   = [double]::NegativeInfinity
        # LANDMARK: Rollup ingestion metrics - diff compare accumulators
        DiffCompareDurationValues       = [System.Collections.Generic.List[double]]::new()
        DiffCompareDurationSum          = 0.0
        DiffCompareDurationMax          = [double]::NegativeInfinity
        DiffCompareDurationStatusCounts = @{}
        DiffCompareResultTotals         = [System.Collections.Generic.List[double]]::new()
        DiffCompareResultTotalSum       = 0.0
        DiffCompareResultAddedSum       = 0.0
        DiffCompareResultRemovedSum     = 0.0
        DiffCompareResultChangedSum     = 0.0
        DiffCompareResultUnchangedSum   = 0.0
        DiffCompareResultStatusCounts   = @{}
    }

    return $accumulator
}

function Get-RoundedValue {
    param(
        [AllowNull()]
        [double]$Value,
        [int]$Digits = 3
    )

    if ($null -eq $Value -or [double]::IsNaN($Value)) {
        return $null
    }

    return [Math]::Round($Value, $Digits, [MidpointRounding]::AwayFromZero)
}

function Get-SummaryRowsForAccumulator {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Accumulator,
        [Parameter(Mandatory)]
        [string]$DateKey,
        [Parameter(Mandatory)]
        [string]$Scope
    )

    $rows = [System.Collections.Generic.List[psobject]]::new()

    $parseCount = $Accumulator.ParseDurations.Count
    if ($parseCount -gt 0) {
        $parseValues = $Accumulator.ParseDurations.ToArray()
        $parseAverage = $Accumulator.ParseDurationSum / $parseCount
        $parseP95 = StatisticsModule\Get-PercentileValue -Values $parseValues -Percentile 95
        $parseMax = if ($Accumulator.ParseDurationMax -eq [double]::NegativeInfinity) { $null } else { $Accumulator.ParseDurationMax }
        $parseNotes = if ($Accumulator.ParseDurationFailure -gt 0) { "Failures=$($Accumulator.ParseDurationFailure)" } else { $null }

        $rows.Add([pscustomobject]@{
                Date           = $DateKey
                Scope          = $Scope
                Metric         = 'ParseDurationSeconds'
                Count          = $parseCount
                Average        = Get-RoundedValue -Value $parseAverage
                P95            = Get-RoundedValue -Value $parseP95
                Max            = Get-RoundedValue -Value $parseMax
                Total          = Get-RoundedValue -Value $Accumulator.ParseDurationSum
                SecondaryTotal = $null
                Notes          = $parseNotes
            }) | Out-Null
    }

    $latencyCount = $Accumulator.WriteLatencies.Count
    if ($latencyCount -gt 0) {
        $latencyValues = $Accumulator.WriteLatencies.ToArray()
        $latencyAverage = $Accumulator.WriteLatencySum / $latencyCount
        $latencyP95 = StatisticsModule\Get-PercentileValue -Values $latencyValues -Percentile 95
        $latencyMax = if ($Accumulator.WriteLatencyMax -eq [double]::NegativeInfinity) { $null } else { $Accumulator.WriteLatencyMax }

        $rows.Add([pscustomobject]@{
                Date           = $DateKey
                Scope          = $Scope
                Metric         = 'DatabaseWriteLatencyMs'
                Count          = $latencyCount
                Average        = Get-RoundedValue -Value $latencyAverage
                P95            = Get-RoundedValue -Value $latencyP95
                Max            = Get-RoundedValue -Value $latencyMax
                Total          = Get-RoundedValue -Value $Accumulator.WriteLatencySum
                SecondaryTotal = $null
                Notes          = $null
            }) | Out-Null
    }

    if ($Accumulator.RowsWrittenCount -gt 0 -or $Accumulator.RowsWrittenTotal -gt 0) {
        $rows.Add([pscustomobject]@{
                Date           = $DateKey
                Scope          = $Scope
                Metric         = 'RowsWritten'
                Count          = $Accumulator.RowsWrittenCount
                Average        = $null
                P95            = $null
                Max            = $null
                Total          = [Math]::Round($Accumulator.RowsWrittenTotal, 0)
                SecondaryTotal = if ($Accumulator.RowsDeletedTotal -gt 0) { [Math]::Round($Accumulator.RowsDeletedTotal, 0) } else { $null }
                Notes          = if ($Accumulator.RowsWrittenHosts.Count -gt 0) { "UniqueHosts=$($Accumulator.RowsWrittenHosts.Count)" } else { $null }
            }) | Out-Null
    }

    if ($Accumulator.SkippedDuplicateCount -gt 0) {
        $rows.Add([pscustomobject]@{
                Date           = $DateKey
                Scope          = $Scope
                Metric         = 'SkippedDuplicate'
                Count          = $Accumulator.SkippedDuplicateCount
                Average        = $null
                P95            = $null
                Max            = $null
                Total          = $Accumulator.SkippedDuplicateHosts.Count
                SecondaryTotal = $null
                Notes          = if ($Accumulator.SkippedDuplicateHosts.Count -gt 0) { "UniqueHosts=$($Accumulator.SkippedDuplicateHosts.Count)" } else { $null }
            }) | Out-Null
    }

    if ($script:IncludeSiteCacheMetrics -and (($Accumulator.SiteCacheFetchCount -gt 0) -or ($Accumulator.SiteCacheFetchZeroCount -gt 0) -or $Accumulator.SiteCacheFetchStatusCounts.Count -gt 0)) {
        $fetchAverage = $null
        $fetchP95 = $null
        $fetchMax = $null
        $fetchTotal = $null

        if ($Accumulator.SiteCacheFetchCount -gt 0) {
            $fetchValues = $Accumulator.SiteCacheFetchDurations.ToArray()
            $fetchAverage = $Accumulator.SiteCacheFetchDurationSum / $Accumulator.SiteCacheFetchCount
            $fetchP95 = StatisticsModule\Get-PercentileValue -Values $fetchValues -Percentile 95
            $fetchMax = if ($Accumulator.SiteCacheFetchDurationMax -eq [double]::NegativeInfinity) { $null } else { $Accumulator.SiteCacheFetchDurationMax }
            $fetchTotal = $Accumulator.SiteCacheFetchDurationSum
        }

        $noteParts = [System.Collections.Generic.List[string]]::new()
        if ($Accumulator.SiteCacheFetchStatusCounts.Count -gt 0) {
            $statusSummary = ($Accumulator.SiteCacheFetchStatusCounts.GetEnumerator() | Sort-Object Name | ForEach-Object {
                    '{0}={1}' -f $_.Key, $_.Value
                }) -join ','
            if (-not [string]::IsNullOrWhiteSpace($statusSummary)) {
                $noteParts.Add("Statuses=$statusSummary") | Out-Null
            }
        }

        if ($Accumulator.SiteCacheProviderCounts.Count -gt 0) {
            $providerSummary = ($Accumulator.SiteCacheProviderCounts.GetEnumerator() | Sort-Object Name | ForEach-Object {
                    '{0}={1}' -f $_.Key, $_.Value
                }) -join ','
            if (-not [string]::IsNullOrWhiteSpace($providerSummary)) {
                $noteParts.Add("Providers=$providerSummary") | Out-Null
            }
        }

        if ($Accumulator.SiteCacheFetchZeroCount -gt 0) {
            $noteParts.Add("ZeroCount=$($Accumulator.SiteCacheFetchZeroCount)") | Out-Null
        }

        $rows.Add([pscustomobject]@{
                Date           = $DateKey
                Scope          = $Scope
                Metric         = 'SiteCacheFetchDurationMs'
                Count          = $Accumulator.SiteCacheFetchCount
                Average        = Get-RoundedValue -Value $fetchAverage
                P95            = Get-RoundedValue -Value $fetchP95
                Max            = Get-RoundedValue -Value $fetchMax
                Total          = Get-RoundedValue -Value $fetchTotal
                SecondaryTotal = $null
                Notes          = if ($noteParts.Count -gt 0) { $noteParts -join '; ' } else { $null }
            }) | Out-Null
    }

    # LANDMARK: Diff telemetry rollup - summary rows for usage rate + drift detection
    if ($Accumulator.DiffUsageCount -gt 0) {
        $usageRate = $null
        if ($Accumulator.DiffUsageDenominatorSum -gt 0) {
            $usageRate = $Accumulator.DiffUsageNumeratorSum / $Accumulator.DiffUsageDenominatorSum
        }

        $usageNotes = $null
        if ($Accumulator.DiffUsageStatusCounts.Count -gt 0) {
            $statusSummary = ($Accumulator.DiffUsageStatusCounts.GetEnumerator() |
                Sort-Object Name | ForEach-Object {
                    '{0}={1}' -f $_.Key, $_.Value
                }) -join ','
            if (-not [string]::IsNullOrWhiteSpace($statusSummary)) {
                $usageNotes = "Statuses=$statusSummary"
            }
        }

        $rows.Add([pscustomobject]@{
                Date           = $DateKey
                Scope          = $Scope
                Metric         = 'DiffUsageRate'
                Count          = $Accumulator.DiffUsageCount
                Average        = Get-RoundedValue -Value $usageRate
                P95            = $null
                Max            = $null
                Total          = [Math]::Round($Accumulator.DiffUsageNumeratorSum, 0)
                SecondaryTotal = [Math]::Round($Accumulator.DiffUsageDenominatorSum, 0)
                Notes          = $usageNotes
            }) | Out-Null
    }

    $driftCount = $Accumulator.DriftDetectionDurations.Count
    if ($driftCount -gt 0) {
        $driftValues = $Accumulator.DriftDetectionDurations.ToArray()
        $driftAverage = $Accumulator.DriftDetectionDurationSum / $driftCount    
        $driftP95 = StatisticsModule\Get-PercentileValue -Values $driftValues -Percentile 95
        $driftMax = if ($Accumulator.DriftDetectionDurationMax -eq [double]::NegativeInfinity) { $null } else { $Accumulator.DriftDetectionDurationMax }        

        $rows.Add([pscustomobject]@{
                Date           = $DateKey
                Scope          = $Scope
                Metric         = 'DriftDetectionTimeMinutes'
                Count          = $driftCount
                Average        = Get-RoundedValue -Value $driftAverage
                P95            = Get-RoundedValue -Value $driftP95
                Max            = Get-RoundedValue -Value $driftMax
                Total          = Get-RoundedValue -Value $Accumulator.DriftDetectionDurationSum
                SecondaryTotal = $null
                Notes          = $null
            }) | Out-Null
    }

    # LANDMARK: Rollup ingestion metrics - diff/compare duration and result counts rollups
    # LANDMARK: Rollup ingestion metrics - diff compare summary rows
    $compareDurationCount = $Accumulator.DiffCompareDurationValues.Count
    if ($compareDurationCount -gt 0) {
        $compareValues = $Accumulator.DiffCompareDurationValues.ToArray()
        $compareAverage = $Accumulator.DiffCompareDurationSum / $compareDurationCount
        $compareP95 = StatisticsModule\Get-PercentileValue -Values $compareValues -Percentile 95
        $compareMax = if ($Accumulator.DiffCompareDurationMax -eq [double]::NegativeInfinity) { $null } else { $Accumulator.DiffCompareDurationMax }

        $compareNotes = $null
        if ($Accumulator.DiffCompareDurationStatusCounts.Count -gt 0) {
            $statusSummary = ($Accumulator.DiffCompareDurationStatusCounts.GetEnumerator() |
                Sort-Object Name | ForEach-Object {
                    '{0}={1}' -f $_.Key, $_.Value
                }) -join ','
            if (-not [string]::IsNullOrWhiteSpace($statusSummary)) {
                $compareNotes = "Statuses=$statusSummary"
            }
        }

        $rows.Add([pscustomobject]@{
                Date           = $DateKey
                Scope          = $Scope
                Metric         = 'DiffCompareDurationMs'
                Count          = $compareDurationCount
                Average        = Get-RoundedValue -Value $compareAverage
                P95            = Get-RoundedValue -Value $compareP95
                Max            = Get-RoundedValue -Value $compareMax
                Total          = Get-RoundedValue -Value $Accumulator.DiffCompareDurationSum
                SecondaryTotal = $null
                Notes          = $compareNotes
            }) | Out-Null
    }

    $resultCount = $Accumulator.DiffCompareResultTotals.Count
    if ($resultCount -gt 0) {
        $resultValues = $Accumulator.DiffCompareResultTotals.ToArray()
        $resultAverage = $Accumulator.DiffCompareResultTotalSum / $resultCount
        $resultP95 = StatisticsModule\Get-PercentileValue -Values $resultValues -Percentile 95
        $resultMax = if ($resultValues.Count -gt 0) { ($resultValues | Measure-Object -Maximum).Maximum } else { $null }

        $notesParts = [System.Collections.Generic.List[string]]::new()
        $notesParts.Add("Added=$([Math]::Round($Accumulator.DiffCompareResultAddedSum, 0))") | Out-Null
        $notesParts.Add("Removed=$([Math]::Round($Accumulator.DiffCompareResultRemovedSum, 0))") | Out-Null
        $notesParts.Add("Changed=$([Math]::Round($Accumulator.DiffCompareResultChangedSum, 0))") | Out-Null
        $notesParts.Add("Unchanged=$([Math]::Round($Accumulator.DiffCompareResultUnchangedSum, 0))") | Out-Null

        if ($Accumulator.DiffCompareResultStatusCounts.Count -gt 0) {
            $statusSummary = ($Accumulator.DiffCompareResultStatusCounts.GetEnumerator() |
                Sort-Object Name | ForEach-Object {
                    '{0}={1}' -f $_.Key, $_.Value
                }) -join ','
            if (-not [string]::IsNullOrWhiteSpace($statusSummary)) {
                $notesParts.Add("Statuses=$statusSummary") | Out-Null
            }
        }

        $rows.Add([pscustomobject]@{
                Date           = $DateKey
                Scope          = $Scope
                Metric         = 'DiffCompareResultCounts'
                Count          = $resultCount
                Average        = Get-RoundedValue -Value $resultAverage
                P95            = Get-RoundedValue -Value $resultP95
                Max            = Get-RoundedValue -Value $resultMax
                Total          = [Math]::Round($Accumulator.DiffCompareResultTotalSum, 0)
                SecondaryTotal = $null
                Notes          = if ($notesParts.Count -gt 0) { $notesParts -join '; ' } else { $null }
            }) | Out-Null
    }

    if ($Accumulator.UserActionCounts.Count -gt 0) {
        $totalActions = 0
        foreach ($actionKey in $Accumulator.UserActionCounts.Keys) {
            $count = [int]$Accumulator.UserActionCounts[$actionKey]
            $totalActions += $count
            $rows.Add([pscustomobject]@{
                    Date           = $DateKey
                    Scope          = $Scope
                    Metric         = 'UserAction'
                    Count          = $count
                    Average        = $null
                    P95            = $null
                    Max            = $null
                    Total          = $null
                    SecondaryTotal = $null
                    Notes          = "Action=$actionKey"
                }) | Out-Null
        }

        $missingActions = @($script:RequiredUserActions | Where-Object { -not $Accumulator.UserActionCounts.ContainsKey($_) })
        $rows.Add([pscustomobject]@{
                Date           = $DateKey
                Scope          = $Scope
                Metric         = 'UserActionCoverage'
                Count          = ($script:RequiredUserActions.Count - $missingActions.Count)
                Average        = $null
                P95            = $null
                Max            = $null
                Total          = $script:RequiredUserActions.Count
                SecondaryTotal = if ($missingActions.Count -gt 0) { [string]::Join(',', $missingActions) } else { $null }
                Notes          = if ($missingActions.Count -gt 0) { "Missing=$([string]::Join(',', $missingActions))" } else { 'All required actions present' }
            }) | Out-Null

        if ($totalActions -gt 0) {
            $rows.Add([pscustomobject]@{
                    Date           = $DateKey
                    Scope          = $Scope
                    Metric         = 'UserActionTotal'
                    Count          = $totalActions
                    Average        = $null
                    P95            = $null
                    Max            = $null
                    Total          = $null
                    SecondaryTotal = $null
                    Notes          = $null
                }) | Out-Null
        }
    }

    return $rows
}

function Update-AccumulatorFromEvent {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Accumulator,
        [Parameter(Mandatory)]
        [pscustomobject]$Event
    )

    $eventName = ('' + $Event.EventName).Trim()
    switch ($eventName) {
        'ParseDuration' {
            if ($Event.PSObject.Properties.Name -contains 'DurationSeconds') {
                try {
                    $duration = [double]$Event.DurationSeconds
                } catch {
                    break
                }

                $Accumulator.ParseDurations.Add($duration) | Out-Null
                $Accumulator.ParseDurationSum += $duration
                if ($duration -gt $Accumulator.ParseDurationMax) {
                    $Accumulator.ParseDurationMax = $duration
                }

                $success = $true
                if ($Event.PSObject.Properties.Name -contains 'Success') {
                    try {
                        $success = [bool]$Event.Success
                    } catch {
                        $success = $true
                    }
                }

                if ($success) {
                    $Accumulator.ParseDurationSuccess++
                } else {
                    $Accumulator.ParseDurationFailure++
                }
            }
        }

        'DatabaseWriteLatency' {
            if ($Event.PSObject.Properties.Name -contains 'LatencyMs') {
                try {
                    $latency = [double]$Event.LatencyMs
                } catch {
                    break
                }

                $Accumulator.WriteLatencies.Add($latency) | Out-Null
                $Accumulator.WriteLatencySum += $latency
                if ($latency -gt $Accumulator.WriteLatencyMax) {
                    $Accumulator.WriteLatencyMax = $latency
                }
            }
        }

        'RowsWritten' {
            $rowsValue = 0.0
            $deletedValue = 0.0

            if ($Event.PSObject.Properties.Name -contains 'Rows') {
                try {
                    $rowsValue = [double]$Event.Rows
                } catch {
                    $rowsValue = 0.0
                }
            }

            if ($Event.PSObject.Properties.Name -contains 'DeletedRows') {
                try {
                    $deletedValue = [double]$Event.DeletedRows
                } catch {
                    $deletedValue = 0.0
                }
            }

            $Accumulator.RowsWrittenCount++
            $Accumulator.RowsWrittenTotal += $rowsValue
            $Accumulator.RowsDeletedTotal += $deletedValue

            if ($Event.PSObject.Properties.Name -contains 'Hostname') {
                $hostname = ('' + $Event.Hostname).Trim()
                if (-not [string]::IsNullOrWhiteSpace($hostname)) {
                    $null = $Accumulator.RowsWrittenHosts.Add($hostname)
                }
            }
        }

        'SkippedDuplicate' {
            $Accumulator.SkippedDuplicateCount++
            if ($Event.PSObject.Properties.Name -contains 'Hostname') {
                $duplicateHost = ('' + $Event.Hostname).Trim()
                if (-not [string]::IsNullOrWhiteSpace($duplicateHost)) {
                    $null = $Accumulator.SkippedDuplicateHosts.Add($duplicateHost)
                }
            }
        }

        'InterfaceSyncTiming' {
            if (-not $script:IncludeSiteCacheMetrics) { break }

            $durationParsed = $false
            $duration = 0.0
            if ($Event.PSObject.Properties.Name -contains 'SiteCacheFetchDurationMs') {
                try {
                    $duration = [double]$Event.SiteCacheFetchDurationMs
                    $durationParsed = $true
                } catch {
                    $duration = 0.0
                }
            }

            if ($durationParsed) {
                if ($duration -gt 0) {
                    $Accumulator.SiteCacheFetchDurations.Add($duration) | Out-Null
                    $Accumulator.SiteCacheFetchDurationSum += $duration
                    if ($duration -gt $Accumulator.SiteCacheFetchDurationMax) {
                        $Accumulator.SiteCacheFetchDurationMax = $duration
                    }
                    $Accumulator.SiteCacheFetchCount++
                } else {
                    $Accumulator.SiteCacheFetchZeroCount++
                }
            }

            if ($Event.PSObject.Properties.Name -contains 'SiteCacheFetchStatus') {
                $statusValue = ('' + $Event.SiteCacheFetchStatus).Trim()
                Add-DictionaryCount -Dictionary $Accumulator.SiteCacheFetchStatusCounts -Key $statusValue
            }

            if ($Event.PSObject.Properties.Name -contains 'SiteCacheProvider') {
                $providerValue = ('' + $Event.SiteCacheProvider).Trim()
                Add-DictionaryCount -Dictionary $Accumulator.SiteCacheProviderCounts -Key $providerValue
            }
        }

        # LANDMARK: Diff telemetry rollup - event accumulation for usage rate + drift detection
        'DiffUsageRate' {
            $numerator = 0.0
            $denominator = 0.0
            $parsed = $false

            if ($Event.PSObject.Properties.Name -contains 'UsageNumerator') {
                try {
                    $numerator = [double]$Event.UsageNumerator
                    $parsed = $true
                } catch {
                    $numerator = 0.0
                }
            }
            if ($Event.PSObject.Properties.Name -contains 'UsageDenominator') {
                try {
                    $denominator = [double]$Event.UsageDenominator
                    $parsed = $true
                } catch {
                    $denominator = 0.0
                }
            }

            if (-not $parsed) { break }

            $Accumulator.DiffUsageCount++
            $Accumulator.DiffUsageNumeratorSum += $numerator
            $Accumulator.DiffUsageDenominatorSum += $denominator

            if ($Event.PSObject.Properties.Name -contains 'Status') {
                $statusValue = ('' + $Event.Status).Trim()
                Add-DictionaryCount -Dictionary $Accumulator.DiffUsageStatusCounts -Key $statusValue
            }
        }

        'DriftDetectionTime' {
            if ($Event.PSObject.Properties.Name -contains 'DurationMinutes') {  
                try {
                    $duration = [double]$Event.DurationMinutes
                } catch {
                    break
                }

                $Accumulator.DriftDetectionDurations.Add($duration) | Out-Null
                $Accumulator.DriftDetectionDurationSum += $duration
                if ($duration -gt $Accumulator.DriftDetectionDurationMax) {     
                    $Accumulator.DriftDetectionDurationMax = $duration
                }
            }
        }

        # LANDMARK: Rollup ingestion metrics - align diff/compare telemetry parsing to emitted schema
        # LANDMARK: Rollup ingestion metrics - diff compare telemetry accumulation
        'DiffCompareDurationMs' {
            $statusValue = ''
            if ($Event.PSObject.Properties.Name -contains 'Status') {
                $statusValue = ('' + $Event.Status).Trim()
                Add-DictionaryCount -Dictionary $Accumulator.DiffCompareDurationStatusCounts -Key $statusValue
            }

            $includeDuration = $true
            if (-not [string]::IsNullOrWhiteSpace($statusValue) -and $statusValue -ne 'Executed') {
                $includeDuration = $false
            }
            if (-not $includeDuration) { break }

            if ($Event.PSObject.Properties.Name -contains 'DurationMs') {
                try {
                    $durationMs = [double]$Event.DurationMs
                } catch {
                    break
                }

                $Accumulator.DiffCompareDurationValues.Add($durationMs) | Out-Null
                $Accumulator.DiffCompareDurationSum += $durationMs
                if ($durationMs -gt $Accumulator.DiffCompareDurationMax) {
                    $Accumulator.DiffCompareDurationMax = $durationMs
                }
            }
        }

        'DiffCompareResultCounts' {
            $statusValue = ''
            if ($Event.PSObject.Properties.Name -contains 'Status') {
                $statusValue = ('' + $Event.Status).Trim()
                Add-DictionaryCount -Dictionary $Accumulator.DiffCompareResultStatusCounts -Key $statusValue
            }

            $includeCounts = $true
            if (-not [string]::IsNullOrWhiteSpace($statusValue) -and $statusValue -ne 'Executed') {
                $includeCounts = $false
            }
            if (-not $includeCounts) { break }

            $totalValue = 0.0
            $addedValue = 0.0
            $removedValue = 0.0
            $changedValue = 0.0
            $unchangedValue = 0.0
            $hasAny = $false

            if ($Event.PSObject.Properties.Name -contains 'TotalCount') {
                try {
                    $totalValue = [double]$Event.TotalCount
                    $hasAny = $true
                } catch {
                    $totalValue = 0.0
                }
            }
            if ($Event.PSObject.Properties.Name -contains 'AddedCount') {
                try {
                    $addedValue = [double]$Event.AddedCount
                    $hasAny = $true
                } catch {
                    $addedValue = 0.0
                }
            }
            if ($Event.PSObject.Properties.Name -contains 'RemovedCount') {
                try {
                    $removedValue = [double]$Event.RemovedCount
                    $hasAny = $true
                } catch {
                    $removedValue = 0.0
                }
            }
            if ($Event.PSObject.Properties.Name -contains 'ChangedCount') {
                try {
                    $changedValue = [double]$Event.ChangedCount
                    $hasAny = $true
                } catch {
                    $changedValue = 0.0
                }
            }
            if ($Event.PSObject.Properties.Name -contains 'UnchangedCount') {
                try {
                    $unchangedValue = [double]$Event.UnchangedCount
                    $hasAny = $true
                } catch {
                    $unchangedValue = 0.0
                }
            }

            if (-not $hasAny) { break }
            if ($totalValue -le 0 -and $hasAny) {
                $totalValue = $addedValue + $removedValue + $changedValue + $unchangedValue
            }

            $Accumulator.DiffCompareResultTotals.Add($totalValue) | Out-Null
            $Accumulator.DiffCompareResultTotalSum += $totalValue
            $Accumulator.DiffCompareResultAddedSum += $addedValue
            $Accumulator.DiffCompareResultRemovedSum += $removedValue
            $Accumulator.DiffCompareResultChangedSum += $changedValue
            $Accumulator.DiffCompareResultUnchangedSum += $unchangedValue
        }

        'UserAction' {
            if ($Event.PSObject.Properties.Name -contains 'Action') {
                $actionValue = ('' + $Event.Action).Trim()
                Add-DictionaryCount -Dictionary $Accumulator.UserActionCounts -Key $actionValue
            } else {
                Add-DictionaryCount -Dictionary $Accumulator.UserActionCounts -Key '(unspecified)'
            }
        }
    }
}

$metricsBasePath = $null
$metricFiles = @()

if ($MetricFile) {
    $metricFilesList = [System.Collections.Generic.List[object]]::new()
    foreach ($filePath in $MetricFile) {
        if ([string]::IsNullOrWhiteSpace($filePath)) { continue }
        try {
            $resolved = Resolve-Path -LiteralPath $filePath -ErrorAction Stop
            $fileInfo = Get-Item -LiteralPath $resolved.Path -ErrorAction Stop
            if ($fileInfo -and $fileInfo.PSIsContainer -eq $false) {
                [void]$metricFilesList.Add($fileInfo)
            } else {
                Write-Warning ("Metric file '{0}' could not be read." -f $filePath)
            }
        } catch {
            Write-Warning ("Metric file '{0}' could not be resolved: {1}" -f $filePath, $_.Exception.Message)
        }
    }
    $metricFiles = $metricFilesList

    if (-not $metricFiles -or @($metricFiles).Count -eq 0) {
        Write-Warning 'No metric files were resolved from the provided -MetricFile paths.'
        return
    }

    $metricsBasePath = Split-Path -Parent $metricFiles[0].FullName
    $metricFiles = $metricFiles | Sort-Object -Property Name
} else {
    $metricsPath = Resolve-Path -LiteralPath $MetricsDirectory -ErrorAction Stop
    $metricsBasePath = $metricsPath.Path
    $metricFiles = Get-ChildItem -Path $metricsPath.Path -Filter '*.json' -File | Sort-Object -Property Name

    $hasNameFilters = $false
    if ($MetricFileNameFilter) {
        $filterCount = @($MetricFileNameFilter).Count
        if ($filterCount -gt 0) {
            $hasNameFilters = $true
        }
    }

    if ($hasNameFilters) {
        $metricFiles = $metricFiles | Where-Object {
            $name = $_.Name
            foreach ($pattern in $MetricFileNameFilter) {
                if (-not [string]::IsNullOrWhiteSpace($pattern) -and ($name -like $pattern)) {
                    return $true
                }
            }
            return $false
        }
    }

    $metricFiles = @($metricFiles)
    $currentMetricCount = @($metricFiles).Count

    if ($Latest -gt 0 -and $currentMetricCount -gt $Latest) {
        $metricFiles = $metricFiles |
            Sort-Object -Property LastWriteTimeUtc -Descending |
            Select-Object -First $Latest |
            Sort-Object -Property Name
    }

    $currentMetricCount = @($metricFiles).Count
    if (-not $metricFiles -or $currentMetricCount -eq 0) {
        Write-Warning ("No ingestion metrics files were found under '{0}' using the current filters." -f $metricsPath.Path)
        return
    }
}

$metricFiles = @($metricFiles)

$summaryRows = [System.Collections.Generic.List[psobject]]::new()

foreach ($file in $metricFiles) {
    $dateKey = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    if ([string]::IsNullOrWhiteSpace($dateKey)) {
        $dateKey = $file.Name
    }

    # ST-M-004: Compute and track input file hash for traceability
    $fileHash = Get-FileHashSHA256 -Path $file.FullName
    if ($fileHash) {
        $script:ProcessedFileHashes[$file.FullName] = $fileHash
    }

    $globalAccumulator = New-MetricAccumulator
    $siteAccumulators = @{}

    foreach ($line in Get-Content -Path $file.FullName -ErrorAction Stop) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $eventObject = $null
        try {
            $eventObject = $line | ConvertFrom-Json -ErrorAction Stop
        } catch {
            # ST-M-004: Track warning for hygiene check
            $warnMsg = "Skipping malformed telemetry line in {0}: {1}" -f $file.Name, $_.Exception.Message
            Write-Warning $warnMsg
            $script:WarningCount++
            $script:WarningMessages.Add($warnMsg) | Out-Null
            continue
        }

        if (-not $eventObject) { continue }

        Update-AccumulatorFromEvent -Accumulator $globalAccumulator -Event $eventObject

        if ($IncludePerSite.IsPresent -and $eventObject.PSObject.Properties.Name -contains 'Site') {
            $siteName = ('' + $eventObject.Site).Trim()
            if (-not [string]::IsNullOrWhiteSpace($siteName)) {
                if (-not $siteAccumulators.ContainsKey($siteName)) {
                    $siteAccumulators[$siteName] = New-MetricAccumulator
                }
                Update-AccumulatorFromEvent -Accumulator $siteAccumulators[$siteName] -Event $eventObject
            }
        }
    }

    foreach ($row in (Get-SummaryRowsForAccumulator -Accumulator $globalAccumulator -DateKey $dateKey -Scope 'All')) {
        $summaryRows.Add($row) | Out-Null
    }

    if ($IncludePerSite.IsPresent -and $siteAccumulators.Count -gt 0) {
        foreach ($siteKey in ($siteAccumulators.Keys | Sort-Object)) {
            foreach ($row in (Get-SummaryRowsForAccumulator -Accumulator $siteAccumulators[$siteKey] -DateKey $dateKey -Scope $siteKey)) {
                $summaryRows.Add($row) | Out-Null
            }
        }
    }
}

if (-not $summaryRows -or $summaryRows.Count -eq 0) {
    Write-Warning 'No summary rows were produced from the available telemetry.'
    if ($PassThru.IsPresent) {
        return @()
    }
    return
}

$targetOutputPath = $OutputPath
if ([string]::IsNullOrWhiteSpace($targetOutputPath)) {
    $basePath = if (-not [string]::IsNullOrWhiteSpace($metricsBasePath)) { $metricsBasePath } else { (Get-Location).Path }
    $targetOutputPath = Join-Path -Path $basePath -ChildPath 'IngestionMetricsSummary.csv'
}

$outputDirectory = Split-Path -Path $targetOutputPath -Parent
if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -LiteralPath $outputDirectory)) {
    $null = New-Item -ItemType Directory -Path $outputDirectory -Force
}

$summaryRows |
Sort-Object -Property @{Expression = 'Date'; Descending = $false }, @{Expression = 'Scope'; Descending = $false }, @{Expression = 'Metric'; Descending = $false } |
Export-Csv -Path $targetOutputPath -NoTypeInformation -Encoding UTF8

Write-Host ("Ingestion metrics summary written to {0}" -f $targetOutputPath) -ForegroundColor Cyan

# ST-M-004: Generate hash manifest for input traceability
if ($GenerateHashManifest -and $script:ProcessedFileHashes.Count -gt 0) {
    $hashManifestPath = [System.IO.Path]::ChangeExtension($targetOutputPath, '.hashes.json')
    $hashManifest = [pscustomobject]@{
        GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        OutputFile     = $targetOutputPath
        InputFiles     = @($script:ProcessedFileHashes.GetEnumerator() | ForEach-Object {
            [pscustomobject]@{
                Path   = $_.Key
                SHA256 = $_.Value
            }
        })
        WarningCount   = $script:WarningCount
    }
    $hashManifest | ConvertTo-Json -Depth 5 | Set-Content -Path $hashManifestPath -Encoding UTF8
    Write-Host ("Input hash manifest written to {0}" -f $hashManifestPath) -ForegroundColor Cyan
}

# ST-M-004: Fail on warnings if requested
if ($FailOnWarnings -and $script:WarningCount -gt 0) {
    $warningPreview = $script:WarningMessages | Select-Object -First 5
    $previewText = ($warningPreview -join "`n")
    throw ("Rollup failed: {0} warning(s) encountered during processing.`n{1}" -f $script:WarningCount, $previewText)
}

if ($PassThru.IsPresent) {
    return $summaryRows
}
