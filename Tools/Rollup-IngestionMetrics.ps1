[CmdletBinding()]
param(
    [string]$MetricsDirectory = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Logs\IngestionMetrics'),
    [string[]]$MetricFile,
    [string[]]$MetricFileNameFilter,
    [int]$Latest = 0,
    [string]$OutputPath,
    [switch]$IncludePerSite,
    [switch]$IncludeSiteCache,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:IncludeSiteCacheMetrics = $IncludeSiteCache.IsPresent
$script:RequiredUserActions = @('ScanLogs','LoadFromDb','HelpQuickstart','InterfacesView','CompareView','SpanSnapshot')

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
    }

    return $accumulator
}

function Get-PercentileValue {
    param(
        [Parameter(Mandatory)]
        [double[]]$Values,
        [Parameter(Mandatory)]
        [ValidateRange(0, 100)]
        [double]$Percentile
    )

    if (-not $Values -or $Values.Length -eq 0) {
        return $null
    }

    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 0) {
        return $null
    }

    $position = ($Percentile / 100.0) * ($sorted.Count - 1)
    $lowerIndex = [Math]::Floor($position)
    $upperIndex = [Math]::Ceiling($position)

    if ($lowerIndex -lt 0) { $lowerIndex = 0 }
    if ($upperIndex -ge $sorted.Count) { $upperIndex = $sorted.Count - 1 }

    if ($lowerIndex -eq $upperIndex) {
        return $sorted[$lowerIndex]
    }

    $fraction = $position - $lowerIndex
    $lowerValue = $sorted[$lowerIndex]
    $upperValue = $sorted[$upperIndex]

    return $lowerValue + ($fraction * ($upperValue - $lowerValue))
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
        $parseP95 = Get-PercentileValue -Values $parseValues -Percentile 95
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
        $latencyP95 = Get-PercentileValue -Values $latencyValues -Percentile 95
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
            $fetchP95 = Get-PercentileValue -Values $fetchValues -Percentile 95
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
    foreach ($filePath in $MetricFile) {
        if ([string]::IsNullOrWhiteSpace($filePath)) { continue }
        try {
            $resolved = Resolve-Path -LiteralPath $filePath -ErrorAction Stop
            $fileInfo = Get-Item -LiteralPath $resolved.Path -ErrorAction Stop
            if ($fileInfo -and $fileInfo.PSIsContainer -eq $false) {
                $metricFiles += $fileInfo
            } else {
                Write-Warning ("Metric file '{0}' could not be read." -f $filePath)
            }
        } catch {
            Write-Warning ("Metric file '{0}' could not be resolved: {1}" -f $filePath, $_.Exception.Message)
        }
    }

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
            Write-Warning ("Skipping malformed telemetry line in {0}: {1}" -f $file.Name, $_.Exception.Message)
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

if ($PassThru.IsPresent) {
    return $summaryRows
}
