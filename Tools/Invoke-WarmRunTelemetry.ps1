[CmdletBinding()]
param(
    [switch]$IncludeTests,
    [switch]$VerboseParsing,
    [switch]$ResetExtractedLogs,
    [string]$OutputPath,
    [ValidateSet('Empty','Snapshot')]
    [string]$ColdHistorySeed = 'Snapshot',
    [ValidateSet('Empty','Snapshot','ColdOutput','WarmBackup')]
    [string]$WarmHistorySeed = 'WarmBackup',
    [switch]$RefreshSiteCaches,
    [switch]$AssertWarmCache
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$pipelineScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Invoke-StateTracePipeline.ps1'
if (-not (Test-Path -LiteralPath $pipelineScript)) {
    throw "Pipeline harness not found at $pipelineScript."
}

$ingestionHistoryDir = Join-Path -Path $repositoryRoot -ChildPath 'Data\IngestionHistory'
if (-not (Test-Path -LiteralPath $ingestionHistoryDir)) {
    throw "Ingestion history directory not found at $ingestionHistoryDir."
}

$metricsDirectory = Join-Path -Path $repositoryRoot -ChildPath 'Logs\IngestionMetrics'
if (-not (Test-Path -LiteralPath $metricsDirectory)) {
    throw "Telemetry directory not found at $metricsDirectory."
}

$script:PassInterfaceAnalysis = @{}

function Get-IngestionHistorySnapshot {
    param(
        [string]$DirectoryPath
    )

    $snapshot = @()
    foreach ($file in Get-ChildItem -Path $DirectoryPath -Filter '*.json' -File) {
        $content = [System.IO.File]::ReadAllText($file.FullName)
        $snapshot += [pscustomobject]@{
            Path    = $file.FullName
            Content = $content
        }
    }
    if (-not $snapshot) {
        throw "No ingestion history JSON files found under $DirectoryPath."
    }
    return ,$snapshot
}

function Get-IngestionHistoryWarmRunSnapshot {
    param(
        [Parameter(Mandatory)]
        [string]$DirectoryPath,
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable]$FallbackSnapshot
    )

    $warmRunSnapshot = @()
    foreach ($entry in $FallbackSnapshot) {
        $targetPath = $entry.Path
        $fileName = [System.IO.Path]::GetFileName($targetPath)
        $pattern = "${fileName}.warmrun.*.bak"
        $backup = Get-ChildItem -Path $DirectoryPath -Filter $pattern -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($backup) {
            $content = [System.IO.File]::ReadAllText($backup.FullName)
            if (-not [string]::IsNullOrWhiteSpace($content)) {
                try {
                    $parsed = $content | ConvertFrom-Json -ErrorAction Stop
                    if ($parsed) {
                        $records = if ($parsed -is [System.Array]) { @($parsed) } else { @($parsed) }
                        if ($records.Count -gt 1) {
                            $content = ($records | ConvertTo-Json -Depth 6)
                        } elseif ($records.Count -eq 1) {
                            $content = ($records[0] | ConvertTo-Json -Depth 6)
                        }
                    }
                } catch {
                    Write-Warning ("Failed to sanitize warm-run backup for {0}: {1}. Using raw content." -f $fileName, $_.Exception.Message)
                }
            }
            $warmRunSnapshot += [pscustomobject]@{
                Path    = $targetPath
                Content = $content
            }
        } else {
            Write-Warning "No warm-run backup found for $fileName; falling back to the current snapshot."
            $warmRunSnapshot += $entry
        }
    }

    if (-not $warmRunSnapshot) {
        throw "Failed to build warm-run snapshot from $DirectoryPath."
    }

    return ,$warmRunSnapshot
}

function Restore-IngestionHistory {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable]$Snapshot
    )

    foreach ($entry in $Snapshot) {
        [System.IO.File]::WriteAllText($entry.Path, $entry.Content)
    }
}

function Get-SitesFromSnapshot {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable]$Snapshot
    )

    $sites = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $Snapshot) {
        if (-not $entry) { continue }
        $content = $entry.Content
        if ([string]::IsNullOrWhiteSpace($content)) { continue }
        $records = $null
        try {
            $records = $content | ConvertFrom-Json -ErrorAction Stop
        } catch {
            continue
        }
        foreach ($record in @($records)) {
            if ($null -eq $record) { continue }
            if ($record.PSObject.Properties.Name -contains 'Site') {
                $siteValue = '' + $record.Site
                if (-not [string]::IsNullOrWhiteSpace($siteValue)) {
                    [void]$sites.Add($siteValue.Trim())
                }
            }
        }
    }
    return @($sites)
}

function Get-MetricsBaseline {
    param(
        [string]$DirectoryPath
    )

    $baseline = @{}
    if (-not (Test-Path -LiteralPath $DirectoryPath)) {
        return $baseline
    }

    foreach ($file in Get-ChildItem -Path $DirectoryPath -Filter '*.json' -File) {
        $lines = [System.IO.File]::ReadAllLines($file.FullName)
        $baseline[$file.FullName] = [pscustomobject]@{
            LineCount   = $lines.Length
            LengthBytes = $file.Length
        }
    }

    return $baseline
}

function Get-AppendedTelemetry {
    param(
        [Parameter(Mandatory)]
        [string]$DirectoryPath,
        [Parameter(Mandatory)]
        [hashtable]$Baseline
    )

    $events = @()

    foreach ($file in Get-ChildItem -Path $DirectoryPath -Filter '*.json' -File | Sort-Object FullName) {
        $lines = [System.IO.File]::ReadAllLines($file.FullName)
        $previousCount = 0
        $previousLength = 0
        if ($Baseline.ContainsKey($file.FullName)) {
            $entry = $Baseline[$file.FullName]
            if ($entry.PSObject.Properties.Name -contains 'LineCount') {
                $previousCount = [int]$entry.LineCount
            }
            if ($entry.PSObject.Properties.Name -contains 'LengthBytes') {
                $previousLength = [long]$entry.LengthBytes
            }
        }
        if ($lines.Length -le $previousCount) {
            $Baseline[$file.FullName] = [pscustomobject]@{
                LineCount   = $lines.Length
                LengthBytes = $file.Length
            }
            continue
        }

        for ($index = $previousCount; $index -lt $lines.Length; $index++) {
            $line = $lines[$index]
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            try {
                $parsed = $line | ConvertFrom-Json -ErrorAction Stop
                $parsed | Add-Member -NotePropertyName '__SourceFile' -NotePropertyValue $file.FullName
                $parsed | Add-Member -NotePropertyName '__LineIndex' -NotePropertyValue $index
                $events += $parsed
            } catch {
                Write-Warning "Failed to parse telemetry line $($file.Name):$index. $($_.Exception.Message)"
            }
        }

        $Baseline[$file.FullName] = [pscustomobject]@{
            LineCount   = $lines.Length
            LengthBytes = $file.Length
        }
    }

    return $events
}

function Wait-TelemetryFlush {
    param(
        [Parameter(Mandatory)][string]$DirectoryPath,
        [Parameter(Mandatory)][hashtable]$Baseline,
        [int]$TimeoutMilliseconds = 5000,
        [int]$PollMilliseconds = 100
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        do {
            foreach ($file in Get-ChildItem -Path $DirectoryPath -Filter '*.json' -File) {
                $previousLength = 0
                if ($Baseline.ContainsKey($file.FullName)) {
                    $entry = $Baseline[$file.FullName]
                    if ($entry.PSObject.Properties.Name -contains 'LengthBytes') {
                        try { $previousLength = [long]$entry.LengthBytes } catch { $previousLength = 0 }
                    }
                }
                if ($file.Length -gt $previousLength) {
                    return
                }
            }
            Start-Sleep -Milliseconds $PollMilliseconds
        } while ($stopwatch.ElapsedMilliseconds -lt $TimeoutMilliseconds)
    } finally {
        $stopwatch.Stop()
    }
}

function Get-TelemetrySince {
    param(
        [Parameter(Mandatory)][datetime]$Since,
        [Parameter(Mandatory)][string]$DirectoryPath,
        [string[]]$EventNames,
        [switch]$IgnoreEventTimestamp
    )

    $events = @()
    foreach ($file in Get-ChildItem -Path $DirectoryPath -Filter '*.json' -File | Where-Object { $_.LastWriteTime -ge $Since }) {
        foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $parsed = $line | ConvertFrom-Json -ErrorAction Stop
            } catch {
                continue
            }
            if (-not $parsed) { continue }
            $timestamp = $parsed.Timestamp
            if (-not $IgnoreEventTimestamp.IsPresent) {
                if ($timestamp -isnot [datetime]) {
                    if (-not [string]::IsNullOrWhiteSpace($timestamp)) {
                        try { $timestamp = [datetime]::Parse($timestamp) } catch { continue }
                    } else {
                        continue
                    }
                }
                if ($timestamp -lt $Since) {
                    continue
                }
            }
            if ($EventNames -and $EventNames.Count -gt 0 -and -not ($EventNames -contains ('' + $parsed.EventName))) {
                continue
            }
            $parsed | Add-Member -NotePropertyName '__SourceFile' -NotePropertyValue $file.FullName -Force
            $events += $parsed
        }
    }
    return $events
}

function Get-TelemetryIdentityKey {
    param(
        [Parameter(Mandatory)]
        [psobject]$Event
    )

    $eventName = ''
    if ($Event.PSObject.Properties.Name -contains 'EventName') {
        $eventName = ('' + $Event.EventName).Trim()
    }

    $site = ''
    if ($Event.PSObject.Properties.Name -contains 'Site') {
        $site = ('' + $Event.Site).Trim()
    }

    $timestampKey = ''
    if ($Event.PSObject.Properties.Name -contains 'Timestamp') {
        $timestampValue = $Event.Timestamp
        if ($timestampValue -is [datetime]) {
            $timestampKey = $timestampValue.ToString('o')
        } elseif (-not [string]::IsNullOrWhiteSpace($timestampValue)) {
            $timestampKey = ('' + $timestampValue).Trim()
        }
    }

    $sourceFile = ''
    if ($Event.PSObject.Properties.Name -contains '__SourceFile') {
        $sourceFile = ('' + $Event.__SourceFile).Trim()
    }

    $lineIndex = ''
    if ($Event.PSObject.Properties.Name -contains '__LineIndex') {
        $lineIndex = ('' + $Event.__LineIndex).Trim()
    }

    return [string]::Format('{0}|{1}|{2}|{3}|{4}', $eventName, $site, $timestampKey, $sourceFile, $lineIndex)
}

function Collect-TelemetryForPass {
    param(
        [Parameter(Mandatory)][string]$DirectoryPath,
        [Parameter(Mandatory)][hashtable]$Baseline,
        [datetime]$PassStartTime,
        [string[]]$RequiredEventNames,
        [int]$MaxAttempts = 120,
        [int]$PollMilliseconds = 500,
        [int]$FallbackLookbackSeconds = 2
    )

    $allEvents = @()
    $eventBuckets = @{}
    $identitySet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $requiredNames = @()
    if ($RequiredEventNames) {
        foreach ($name in $RequiredEventNames) {
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            if (-not $eventBuckets.ContainsKey($name)) {
                $eventBuckets[$name] = @()
            }
            $requiredNames += $name
        }
    }

    $addEvent = {
        param($evt)
        if (-not $evt) { return }

        $key = Get-TelemetryIdentityKey -Event $evt
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            if ($identitySet.Contains($key)) {
                return
            }
            [void]$identitySet.Add($key)
        }

        $allEvents += $evt

        if ($requiredNames -and $evt.PSObject.Properties.Name -contains 'EventName') {
            $evtName = ('' + $evt.EventName).Trim()
            if (-not [string]::IsNullOrWhiteSpace($evtName) -and $eventBuckets.ContainsKey($evtName)) {
                $eventBuckets[$evtName] += $evt
            }
        }
    }

    $maxAttempts = if ($MaxAttempts -gt 0) { $MaxAttempts } else { 1 }
    $pollTimeout = if ($PollMilliseconds -gt 0) { $PollMilliseconds } else { 250 }
    $pollInner = [math]::Max([int]($pollTimeout / 5), 25)
    $attempt = 0
    do {
        $attempt++
        $newEvents = Get-AppendedTelemetry -DirectoryPath $DirectoryPath -Baseline $Baseline
        foreach ($evt in @($newEvents)) {
            & $addEvent $evt
        }

        $complete = $true
        foreach ($name in $requiredNames) {
            $bucket = @()
            if ($eventBuckets.ContainsKey($name)) {
                $bucket = $eventBuckets[$name]
            }
            if (-not $bucket -or ($bucket | Measure-Object).Count -eq 0) {
                $complete = $false
                break
            }
        }

        if ($complete -or $attempt -ge $maxAttempts) {
            break
        }

        Wait-TelemetryFlush -DirectoryPath $DirectoryPath -Baseline $Baseline -TimeoutMilliseconds $pollTimeout -PollMilliseconds $pollInner
    } while ($true)

    $missingNames = @()
    foreach ($name in $requiredNames) {
        $bucket = @()
        if ($eventBuckets.ContainsKey($name)) {
            $bucket = $eventBuckets[$name]
        }
        if (-not $bucket -or ($bucket | Measure-Object).Count -eq 0) {
            $missingNames += $name
        }
    }

    if ($missingNames -and $PassStartTime) {
        $fallbackSince = $PassStartTime
        if ($FallbackLookbackSeconds -gt 0) {
            $fallbackSince = $PassStartTime.AddSeconds(-1 * [math]::Abs($FallbackLookbackSeconds))
        }

        $fallbackEvents = Get-TelemetrySince -Since $fallbackSince -DirectoryPath $DirectoryPath -EventNames $requiredNames -IgnoreEventTimestamp
        foreach ($evt in @($fallbackEvents)) {
            if (-not $evt) { continue }

            $baselineLineCount = $null
            $sourceFile = ''
            if ($evt.PSObject.Properties.Name -contains '__SourceFile') {
                $sourceFile = ('' + $evt.__SourceFile).Trim()
            }
            if (-not [string]::IsNullOrWhiteSpace($sourceFile) -and $Baseline.ContainsKey($sourceFile)) {
                $baselineEntry = $Baseline[$sourceFile]
                if ($baselineEntry -and $baselineEntry.PSObject.Properties.Name -contains 'LineCount') {
                    try {
                        $baselineLineCount = [int]$baselineEntry.LineCount
                    } catch {
                        $baselineLineCount = $null
                    }
                }
            }

            $lineIndex = $null
            if ($evt.PSObject.Properties.Name -contains '__LineIndex') {
                try {
                    $lineIndex = [int]$evt.__LineIndex
                } catch {
                    $lineIndex = $null
                }
            }

            if ($baselineLineCount -ne $null -and $lineIndex -ne $null -and $lineIndex -lt $baselineLineCount) {
                continue
            }

            & $addEvent $evt
        }

        $missingNames = @()
        foreach ($name in $requiredNames) {
            $bucket = @()
            if ($eventBuckets.ContainsKey($name)) {
                $bucket = $eventBuckets[$name]
            }
            if (-not $bucket -or ($bucket | Measure-Object).Count -eq 0) {
                $missingNames += $name
            }
        }
    }

    return [pscustomobject]@{
        Events            = $allEvents
        Buckets           = $eventBuckets
        MissingEventNames = $missingNames
    }
}

function Get-PercentileValue {
    param(
        [Parameter(Mandatory)]
        [double[]]$Values,
        [Parameter(Mandatory)]
        [double]$Percentile
    )

    if (-not $Values -or $Values.Length -eq 0) {
        return $null
    }

    $ordered = $Values | Sort-Object
    $maxIndex = $ordered.Length - 1
    if ($maxIndex -lt 0) {
        return $null
    }

    $clampedPercentile = if ($Percentile -lt 0) {
        0
    } elseif ($Percentile -gt 100) {
        100
    } else {
        $Percentile
    }

    if ($clampedPercentile -eq 100) {
        return [double]$ordered[$maxIndex]
    }

    $position = ($clampedPercentile / 100) * $maxIndex
    $lowerIndex = [math]::Floor($position)
    $upperIndex = [math]::Ceiling($position)
    if ($lowerIndex -eq $upperIndex) {
        return [double]$ordered[$lowerIndex]
    }

    $fraction = $position - $lowerIndex
    $lowerValue = [double]$ordered[$lowerIndex]
    $upperValue = [double]$ordered[$upperIndex]
    return $lowerValue + (($upperValue - $lowerValue) * $fraction)
}

function Measure-InterfaceCallDurationMetrics {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable]$Events
    )

    $durations = New-Object 'System.Collections.Generic.List[double]'
    $providerCounts = @{}
    $capturedEvents = @()

    foreach ($event in @($Events)) {
        if (-not $event) {
            continue
        }

        $capturedEvents += $event

        $provider = ''
        if ($event.PSObject.Properties.Name -contains 'SiteCacheProvider') {
            $provider = ('' + $event.SiteCacheProvider).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($provider)) {
            $provider = 'Unknown'
        }
        if ($providerCounts.ContainsKey($provider)) {
            $providerCounts[$provider]++
        } else {
            $providerCounts[$provider] = 1
        }

        if ($event.PSObject.Properties.Name -contains 'InterfaceCallDurationMs') {
            $durationValue = $event.InterfaceCallDurationMs
            if ($null -ne $durationValue) {
                try {
                    [void]$durations.Add([double]$durationValue)
                } catch {
                    # Ignore values that do not convert to double
                }
            }
        }
    }

    $count = $durations.Count
    $averageRaw = $null
    $p95Raw = $null
    $maxRaw = $null

    if ($count -gt 0) {
        $averageRaw = ($durations | Measure-Object -Average).Average
        $maxRaw = ($durations | Measure-Object -Maximum).Maximum
        $p95Raw = Get-PercentileValue -Values $durations.ToArray() -Percentile 95
    }

    $averageRounded = $null
    if ($averageRaw -ne $null) {
        $averageRounded = [math]::Round([double]$averageRaw, 3)
    }

    $p95Rounded = $null
    if ($p95Raw -ne $null) {
        $p95Rounded = [math]::Round([double]$p95Raw, 3)
    }

    $maxRounded = $null
    if ($maxRaw -ne $null) {
        $maxRounded = [math]::Round([double]$maxRaw, 3)
    }

    return [pscustomobject]@{
        Events         = $capturedEvents
        Durations      = $durations.ToArray()
        Count          = $count
        Average        = $averageRounded
        AverageRaw     = if ($averageRaw -ne $null) { [double]$averageRaw } else { $null }
        P95            = $p95Rounded
        P95Raw         = if ($p95Raw -ne $null) { [double]$p95Raw } else { $null }
        Max            = $maxRounded
        MaxRaw         = if ($maxRaw -ne $null) { [double]$maxRaw } else { $null }
        ProviderCounts = $providerCounts
    }
}

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

        [pscustomobject]@{
            PassLabel                     = $PassLabel
            Site                          = $metric.Site
            Timestamp                     = $timestamp
            CacheStatus                   = $metric.CacheStatus
            Provider                      = $metric.Provider
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

$results = @()
$postColdSnapshot = $null
$warmPassSnapshot = $null

function Set-IngestionHistoryForPass {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Empty','Snapshot','ColdOutput','WarmBackup')]
        [string]$SeedMode,
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable]$Snapshot,
        [string]$PassLabel = ''
    )

    switch ($SeedMode) {
        'Empty' {
            if ($PassLabel) {
                Write-Host "Seeding ingestion history as empty arrays for pass '$PassLabel'..." -ForegroundColor Yellow
            } else {
                Write-Host 'Seeding ingestion history as empty arrays...' -ForegroundColor Yellow
            }
            foreach ($entry in $Snapshot) {
                [System.IO.File]::WriteAllText($entry.Path, '[]')
            }
        }
        'Snapshot' {
            if ($PassLabel) {
                Write-Host "Restoring ingestion history snapshot for pass '$PassLabel'..." -ForegroundColor Yellow
            } else {
                Write-Host 'Restoring ingestion history snapshot...' -ForegroundColor Yellow
            }
            Restore-IngestionHistory -Snapshot $Snapshot
        }
        'ColdOutput' {
            if ($PassLabel) {
                Write-Host "Restoring ingestion history captured after the cold pass for pass '$PassLabel'..." -ForegroundColor Yellow
            } else {
                Write-Host 'Restoring ingestion history captured after the cold pass...' -ForegroundColor Yellow
            }
            Restore-IngestionHistory -Snapshot $Snapshot
        }
        'WarmBackup' {
            if ($PassLabel) {
                Write-Host "Restoring warm-run ingestion history backup for pass '$PassLabel'..." -ForegroundColor Yellow
            } else {
                Write-Host 'Restoring warm-run ingestion history backup...' -ForegroundColor Yellow
            }
            Restore-IngestionHistory -Snapshot $Snapshot
        }
        default {
            throw "Unsupported ingestion history seed mode '$SeedMode'."
        }
    }
}

$ingestionHistorySnapshot = Get-IngestionHistorySnapshot -DirectoryPath $ingestionHistoryDir
$metricsBaseline = Get-MetricsBaseline -DirectoryPath $metricsDirectory
$sharedCacheEntries = @()

$pipelineArguments = @{
    PreserveModuleSession = $true
}
if (-not $IncludeTests) {
    $pipelineArguments['SkipTests'] = $true
}
if ($VerboseParsing) {
    $pipelineArguments['VerboseParsing'] = $true
}
if ($ResetExtractedLogs) {
    $pipelineArguments['ResetExtractedLogs'] = $true
}

# Keep the parser runspace configuration identical across cold and warm passes so the preserved pool
# (and shared cache) stay alive between runs.
$pipelineArguments['ThreadCeilingOverride']     = 1
$pipelineArguments['MaxWorkersPerSiteOverride'] = 1
$pipelineArguments['MaxActiveSitesOverride']    = 1
$pipelineArguments['JobsPerThreadOverride']     = 1
$pipelineArguments['MinRunspacesOverride']      = 1

function Invoke-PipelinePass {
    param(
        [string]$Label
    )

    $passStartTime = Get-Date
    Write-Host "Running pipeline pass '$Label'..." -ForegroundColor Cyan
    & $pipelineScript @pipelineArguments | Out-Null
    Write-Host "Pipeline pass '$Label' completed." -ForegroundColor Green

    Wait-TelemetryFlush -DirectoryPath $metricsDirectory -Baseline $metricsBaseline

    $collection = Collect-TelemetryForPass -DirectoryPath $metricsDirectory -Baseline $metricsBaseline -PassStartTime $passStartTime -RequiredEventNames @('InterfaceSiteCacheMetrics','DatabaseWriteBreakdown')
    $telemetry = @()
    if ($collection -and $collection.Events) {
        $telemetry = @($collection.Events)
    }

    $cacheMetrics = @()
    if ($collection -and $collection.Buckets.ContainsKey('InterfaceSiteCacheMetrics')) {
        $cacheMetrics = @($collection.Buckets['InterfaceSiteCacheMetrics'])
    }

    $passResults = @()
    if (-not $cacheMetrics) {
        Write-Warning "No InterfaceSiteCacheMetrics events were captured for pass '$Label'."
    } else {
        $passResults += Convert-MetricsToSummary -PassLabel $Label -Metrics $cacheMetrics
    }

    $breakdownEvents = @()
    if ($collection -and $collection.Buckets.ContainsKey('DatabaseWriteBreakdown')) {
        $breakdownEvents = @($collection.Buckets['DatabaseWriteBreakdown'])
    }
    if ($collection -and $collection.MissingEventNames -and $collection.MissingEventNames.Count -gt 0) {
        Write-Warning ("Telemetry still missing after polling for pass '{0}': {1}" -f $Label, ($collection.MissingEventNames -join ', '))
    }

    if ($breakdownEvents -and ($breakdownEvents | Measure-Object).Count -gt 0) {
        $script:PassInterfaceAnalysis[$Label] = Measure-InterfaceCallDurationMetrics -Events $breakdownEvents
    } else {
        $script:PassInterfaceAnalysis[$Label] = $null
        Write-Warning "No DatabaseWriteBreakdown events were captured for pass '$Label'."
    }

    return $passResults
}

$warmRefreshResults = @()
$script:WarmRunSites = @()

function Invoke-SiteCacheRefresh {
    param(
        [Parameter(Mandatory)][string[]]$Sites,
        [Parameter(Mandatory)][string]$Label
    )

    if (-not $Sites -or $Sites.Count -eq 0) {
        return @()
    }

    $moduleLoaded = Get-Module -Name 'DeviceRepositoryModule'
    if (-not $moduleLoaded) {
        $modulePath = Join-Path -Path $repositoryRoot -ChildPath 'Modules\DeviceRepositoryModule.psm1'
        if (Test-Path -LiteralPath $modulePath) {
            Import-Module -Name $modulePath -ErrorAction SilentlyContinue | Out-Null
        }
    }

    $refreshCount = 0
    foreach ($site in $Sites) {
        if ([string]::IsNullOrWhiteSpace($site)) { continue }
        try {
            DeviceRepositoryModule\Get-InterfaceSiteCache -Site $site -Refresh | Out-Null
            $refreshCount++
        } catch {
            Write-Warning "Failed to refresh site cache for '$site': $($_.Exception.Message)"
        }
    }
    if ($refreshCount -le 0) { return @() }

    $telemetry = Get-AppendedTelemetry -DirectoryPath $metricsDirectory -Baseline $metricsBaseline
    $cacheMetrics = $telemetry | Where-Object {
        $_.EventName -eq 'InterfaceSiteCacheMetrics' -and
        $_.Site -and ($Sites -contains ('' + $_.Site))
    }
    if (-not $cacheMetrics) {
        Write-Warning 'No InterfaceSiteCacheMetrics events were captured during cache refresh.'
        return @()
    }

    return Convert-MetricsToSummary -PassLabel $Label -Metrics $cacheMetrics
}

function Invoke-SiteCacheProbe {
    param(
        [Parameter(Mandatory)][string[]]$Sites,
        [Parameter(Mandatory)][string]$Label
    )

    if (-not $Sites -or $Sites.Count -eq 0) {
        return @()
    }

    $moduleLoaded = Get-Module -Name 'DeviceRepositoryModule'
    if (-not $moduleLoaded) {
        $modulePath = Join-Path -Path $repositoryRoot -ChildPath 'Modules\DeviceRepositoryModule.psm1'
        if (Test-Path -LiteralPath $modulePath) {
            Import-Module -Name $modulePath -ErrorAction SilentlyContinue | Out-Null
        }
    }

    $probedSites = New-Object 'System.Collections.Generic.List[string]'
    foreach ($site in $Sites) {
        if ([string]::IsNullOrWhiteSpace($site)) { continue }
        try {
            DeviceRepositoryModule\Get-InterfaceSiteCache -Site $site | Out-Null
            $probedSites.Add($site) | Out-Null
        } catch {
            Write-Warning "Failed to probe site cache for '$site': $($_.Exception.Message)"
        }
    }

    if ($probedSites.Count -le 0) {
        Write-Warning 'Site cache probe skipped because no sites were successfully probed.'
        return @()
    }

    $telemetry = Get-AppendedTelemetry -DirectoryPath $metricsDirectory -Baseline $metricsBaseline
    $cacheMetrics = $telemetry | Where-Object {
        $_.EventName -eq 'InterfaceSiteCacheMetrics' -and
        $_.Site -and ($probedSites -contains ('' + $_.Site))
    }
    if (-not $cacheMetrics) {
        Write-Warning 'No InterfaceSiteCacheMetrics events were captured during the cache probe.'
        return @()
    }

    return Convert-MetricsToSummary -PassLabel $Label -Metrics $cacheMetrics
}

function Get-SiteCacheState {
    param(
        [Parameter(Mandatory)][string[]]$Sites,
        [Parameter(Mandatory)][string]$Label
    )

    if (-not $Sites -or $Sites.Count -eq 0) {
        return @()
    }

    $module = Get-Module -Name 'DeviceRepositoryModule'
    if (-not $module) {
        $modulePath = Join-Path -Path $repositoryRoot -ChildPath 'Modules\DeviceRepositoryModule.psm1'
        if (Test-Path -LiteralPath $modulePath) {
            $module = Import-Module -Name $modulePath -PassThru -ErrorAction SilentlyContinue
        }
    }
    if (-not $module) {
        Write-Warning 'Unable to inspect site cache state because DeviceRepositoryModule is not loaded.'
        return @()
    }

    $state = $module.Invoke(
        {
            param($siteList)

            $summaries = @()
            foreach ($site in $siteList) {
                if ([string]::IsNullOrWhiteSpace($site)) { continue }

                $entry = $null
                if ($script:SiteInterfaceSignatureCache -and $script:SiteInterfaceSignatureCache.ContainsKey($site)) {
                    $entry = $script:SiteInterfaceSignatureCache[$site]
                }

                if ($entry) {
                    $hostCount = 0
                    if ($entry.PSObject.Properties.Name -contains 'HostCount') {
                        try { $hostCount = [int]$entry.HostCount } catch { $hostCount = 0 }
                    }

                    $totalRows = 0
                    if ($entry.PSObject.Properties.Name -contains 'TotalRows') {
                        try { $totalRows = [int]$entry.TotalRows } catch { $totalRows = 0 }
                    }

                    $hostMap = $null
                    if ($entry.PSObject.Properties.Name -contains 'HostMap') {
                        $hostMap = $entry.HostMap
                    }

                    if ($hostCount -le 0 -and $hostMap -is [System.Collections.IDictionary]) {
                        try { $hostCount = [int]$hostMap.Count } catch { $hostCount = 0 }
                    }

                    if ($totalRows -le 0 -and $hostMap -is [System.Collections.IDictionary]) {
                        foreach ($hostEntry in @($hostMap.GetEnumerator())) {
                            $portMap = $hostEntry.Value
                            if ($portMap -is [System.Collections.ICollection]) {
                                $totalRows += $portMap.Count
                            } elseif ($portMap -is [System.Collections.IDictionary]) {
                                $totalRows += $portMap.Count
                            }
                        }
                    }

                    $cacheStatus = ''
                    if ($entry.PSObject.Properties.Name -contains 'CacheStatus') {
                        $cacheStatus = '' + $entry.CacheStatus
                    }

                    $cachedAt = $null
                    if ($entry.PSObject.Properties.Name -contains 'CachedAt') {
                        $cachedAt = $entry.CachedAt
                    }

                    $summaries += [pscustomobject]@{
                        Site        = $site
                        State       = 'Present'
                        HostCount   = $hostCount
                        TotalRows   = $totalRows
                        CacheStatus = $cacheStatus
                        CachedAt    = $cachedAt
                    }
                } else {
                    $summaries += [pscustomobject]@{
                        Site        = $site
                        State       = 'Missing'
                        HostCount   = 0
                        TotalRows   = 0
                        CacheStatus = ''
                        CachedAt    = $null
                    }
                }
            }

            return ,$summaries
        },
        $Sites
    )

    if (-not $state) {
        return @()
    }

    $now = Get-Date
    return $state | ForEach-Object {
        [pscustomobject]@{
            PassLabel                   = $Label
            Site                        = $_.Site
            Timestamp                   = $now
            CacheStatus                 = if ([string]::IsNullOrWhiteSpace($_.CacheStatus)) { $_.State } else { $_.CacheStatus }
            Provider                    = 'CacheState'
            HydrationDurationMs         = $null
            SnapshotDurationMs          = $null
            HostMapDurationMs           = $null
            HostCount                   = $_.HostCount
            TotalRows                   = $_.TotalRows
            HostMapSignatureMatchCount  = $null
            HostMapSignatureRewriteCount= $null
            HostMapCandidateMissingCount= $null
            HostMapCandidateFromPrevious= $null
            PreviousHostCount           = $null
            PreviousSnapshotStatus      = $_.State
            PreviousSnapshotHostMapType = $null
            CacheStateDetails           = $_
        }
    }
}

function Write-SharedCacheSnapshot {
    param(
        [Parameter(Mandatory)][string]$Label
    )

    $module = Get-Module -Name 'DeviceRepositoryModule'
    if (-not $module) {
        $modulePath = Join-Path -Path $repositoryRoot -ChildPath 'Modules\DeviceRepositoryModule.psm1'
        if (Test-Path -LiteralPath $modulePath) {
            $module = Import-Module -Name $modulePath -PassThru -ErrorAction SilentlyContinue
        }
    }
    if (-not $module) {
        Write-Warning ("Shared cache snapshot '{0}' skipped: DeviceRepositoryModule not loaded." -f $Label)
        return
    }

    $snapshot = $module.Invoke(
        {
            param($labelArg)
            $store = Get-SharedSiteInterfaceCacheStore
            $entryCount = 0
            $sites = @()
            if ($store -is [System.Collections.IDictionary]) {
                try { $entryCount = [int]$store.Count } catch { $entryCount = 0 }
                try { $sites = @($store.Keys) } catch { $sites = @() }
            }
            [pscustomobject]@{
                Label      = $labelArg
                EntryCount = $entryCount
                Sites      = $sites
            }
        },
        $Label
    )

    if ($snapshot) {
        Write-Host ("Shared cache '{0}' entry count: {1}" -f $snapshot.Label, $snapshot.EntryCount) -ForegroundColor DarkCyan
        if ($snapshot.Sites -and $snapshot.Sites.Count -gt 0) {
            Write-Host ("  -> Sites: {0}" -f ([string]::Join(', ', $snapshot.Sites))) -ForegroundColor DarkCyan
        }
    }
}

function Get-SharedCacheEntriesSnapshot {
    $module = Get-Module -Name 'DeviceRepositoryModule'
    if (-not $module) {
        $modulePath = Join-Path -Path $repositoryRoot -ChildPath 'Modules\DeviceRepositoryModule.psm1'
        if (Test-Path -LiteralPath $modulePath) {
            $module = Import-Module -Name $modulePath -PassThru -ErrorAction SilentlyContinue
        }
    }
    if (-not $module) {
        Write-Warning 'Unable to capture shared cache entries because DeviceRepositoryModule is not loaded.'
        return @()
    }

    $entries = $module.Invoke(
        {
            $store = Get-SharedSiteInterfaceCacheStore
            if ($store -isnot [System.Collections.Concurrent.ConcurrentDictionary[string, object]] -or ($store.Count -eq 0)) {
                $storeKey = $script:SharedSiteInterfaceCacheKey
                $domainStore = $null
                try { $domainStore = [System.AppDomain]::CurrentDomain.GetData($storeKey) } catch { $domainStore = $null }
                if ($domainStore -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
                    $scriptCount = 0
                    $domainCount = 0
                    try { $scriptCount = [int]$store.Count } catch { $scriptCount = 0 }
                    try { $domainCount = [int]$domainStore.Count } catch { $domainCount = 0 }
                    Write-Verbose ("Shared cache adoption candidates - script: {0}, domain: {1}" -f $scriptCount, $domainCount)
                    if ($domainCount -gt $scriptCount) {
                        $store = $domainStore
                        $script:SharedSiteInterfaceCache = $domainStore
                        try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetStore($domainStore) } catch { }
                    }
                }
            }
            $result = @()
            if ($store -is [System.Collections.IDictionary]) {
                foreach ($key in @($store.Keys)) {
                    if ([string]::IsNullOrWhiteSpace($key)) { continue }
                    $entry = Get-SharedSiteInterfaceCacheEntry -SiteKey $key
                    if ($entry) {
                        $result += [pscustomobject]@{
                            Site  = $key
                            Entry = $entry
                        }
                    }
                }
            }
            return ,$result
        }
    )

    if (-not $entries) { return @() }
    return @($entries)
}

function Restore-SharedCacheEntries {
    param(
        [System.Collections.IEnumerable]$Entries
    )

    if (-not $Entries) { return 0 }

    $module = Get-Module -Name 'DeviceRepositoryModule'
    if (-not $module) {
        $modulePath = Join-Path -Path $repositoryRoot -ChildPath 'Modules\DeviceRepositoryModule.psm1'
        if (Test-Path -LiteralPath $modulePath) {
            $module = Import-Module -Name $modulePath -PassThru -ErrorAction SilentlyContinue
        }
    }
    if (-not $module) {
        Write-Warning 'Unable to restore shared cache entries because DeviceRepositoryModule is not loaded.'
        return 0
    }

    $restoredCount = $module.Invoke(
        {
            param($payload)

            $entryList = @()
            if ($payload -and $payload.ContainsKey('EntryList')) {
                $entryList = @($payload.EntryList)
            }

            if (-not $entryList) { return 0 }

            $restored = 0
            foreach ($item in @($entryList)) {
                if (-not $item) { continue }
                $siteKey = ''
                if ($item.PSObject.Properties.Name -contains 'Site') {
                    $siteKey = ('' + $item.Site).Trim()
                }
                if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }
                $entryValue = $null
                if ($item.PSObject.Properties.Name -contains 'Entry') {
                    $entryValue = $item.Entry
                }
                if (-not $entryValue) { continue }
                if (-not $script:SiteInterfaceSignatureCache) {
                    $script:SiteInterfaceSignatureCache = @{}
                }
                $script:SiteInterfaceSignatureCache[$siteKey] = $entryValue
                Set-SharedSiteInterfaceCacheEntry -SiteKey $siteKey -Entry $entryValue
                $restored++
            }

            foreach ($item in @($entryList)) {
                if (-not $item) { continue }
                $siteKey = ''
                if ($item.PSObject.Properties.Name -contains 'Site') {
                    $siteKey = ('' + $item.Site).Trim()
                }
                if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }
                try { Get-InterfaceSiteCache -Site $siteKey | Out-Null } catch { }
            }

            return $restored
        },
        @{ EntryList = @($Entries) }
    )

    if ($restoredCount -is [System.Array]) {
        if ($restoredCount.Length -gt 0) {
            return [int]$restoredCount[-1]
        }
        return 0
    }

    return [int]$restoredCount
}

try {
    Set-IngestionHistoryForPass -SeedMode $ColdHistorySeed -Snapshot $ingestionHistorySnapshot -PassLabel 'ColdPass'
    $results += Invoke-PipelinePass -Label 'ColdPass'
    Write-SharedCacheSnapshot -Label 'PostColdPass'
    $sharedCacheEntries = Get-SharedCacheEntriesSnapshot
    $capturedAfterCold = ($sharedCacheEntries | Measure-Object).Count
    if ($capturedAfterCold -gt 0) {
        Write-Host ("Captured {0} shared cache entr{1} after cold pass." -f $capturedAfterCold, $(if ($capturedAfterCold -eq 1) { 'y' } else { 'ies' })) -ForegroundColor DarkCyan
    } else {
        Write-Warning 'Shared cache snapshot after cold pass contained no entries.'
    }
    $results += [pscustomobject]@{
        PassLabel   = 'SharedCacheSnapshot:PostColdPass'
        Timestamp   = Get-Date
        EntryCount  = $capturedAfterCold
        SourceStage = 'ColdPass'
    }

    try {
        Write-Host 'Capturing ingestion history produced by cold pass for potential warm-run reuse...' -ForegroundColor Yellow
        $postColdSnapshot = Get-IngestionHistorySnapshot -DirectoryPath $ingestionHistoryDir
    } catch {
        Write-Warning "Failed to capture post-cold ingestion history snapshot. $($_.Exception.Message)"
    }

    if ($RefreshSiteCaches.IsPresent) {
        try {
            $sitesForRefresh = @()
            if ($postColdSnapshot) {
                $sitesForRefresh = Get-SitesFromSnapshot -Snapshot $postColdSnapshot
            }
            if (-not $sitesForRefresh -or $sitesForRefresh.Count -eq 0) {
                $sitesForRefresh = Get-SitesFromSnapshot -Snapshot $ingestionHistorySnapshot
            }
            $script:WarmRunSites = $sitesForRefresh
            if ($sitesForRefresh -and $sitesForRefresh.Count -gt 0) {
                Write-Host ("Refreshing site caches for warm-run metrics ({0})..." -f ([string]::Join(', ', $sitesForRefresh))) -ForegroundColor Cyan
                $warmRefreshResults = Invoke-SiteCacheRefresh -Sites $sitesForRefresh -Label 'CacheRefresh'
                if ($warmRefreshResults -and $warmRefreshResults.Count -gt 0) {
                    $results += $warmRefreshResults
                }
                Write-SharedCacheSnapshot -Label 'PostRefresh'
                Write-Host 'Recording site cache state after refresh...' -ForegroundColor Cyan
                $cacheStateAfterRefresh = Get-SiteCacheState -Sites $sitesForRefresh -Label 'CacheState:PostRefresh'
                if ($cacheStateAfterRefresh) {
                    $count = ($cacheStateAfterRefresh | Measure-Object).Count
                    Write-Host ("Cache state entries after refresh: {0}" -f $count) -ForegroundColor DarkCyan
                    if ($count -gt 0) {
                        Write-Host ("  -> {0}" -f (($cacheStateAfterRefresh | ForEach-Object { '{0}:{1}' -f $_.Site, $_.CacheStatus }) -join ', ')) -ForegroundColor DarkCyan
                    }
                    $results += @($cacheStateAfterRefresh)
                }
                Write-Host 'Probing site caches after refresh to verify cache entries persisted...' -ForegroundColor Cyan
                $probeResults = Invoke-SiteCacheProbe -Sites $sitesForRefresh -Label 'CacheProbe'
                if ($probeResults -and $probeResults.Count -gt 0) {
                    $results += $probeResults
                }
                Write-Host 'Warming preserved parser runspaces with refreshed site caches...' -ForegroundColor Cyan
                try {
                    ParserRunspaceModule\Invoke-InterfaceSiteCacheWarmup -Sites $sitesForRefresh -Refresh
                } catch {
                    Write-Warning "Failed to warm parser runspace caches: $($_.Exception.Message)"
                }
            } else {
                Write-Warning 'No site codes were discovered in the ingestion history snapshot; skipping cache refresh.'
            }
        } catch {
            Write-Warning "Site cache refresh step failed: $($_.Exception.Message)"
        }
        $sharedCacheEntries = Get-SharedCacheEntriesSnapshot
        $capturedAfterRefresh = ($sharedCacheEntries | Measure-Object).Count
        if ($capturedAfterRefresh -gt 0) {
            Write-Host ("Captured {0} shared cache entr{1} after refresh." -f $capturedAfterRefresh, $(if ($capturedAfterRefresh -eq 1) { 'y' } else { 'ies' })) -ForegroundColor DarkCyan
        } else {
            Write-Warning 'Shared cache snapshot after refresh contained no entries.'
        }
        $results += [pscustomobject]@{
            PassLabel   = 'SharedCacheSnapshot:PostRefresh'
            Timestamp   = Get-Date
            EntryCount  = $capturedAfterRefresh
            SourceStage = 'PostRefresh'
        }
    }

    $warmSeedMode = $WarmHistorySeed
    switch ($WarmHistorySeed) {
        'Snapshot' {
            $warmPassSnapshot = $ingestionHistorySnapshot
        }
        'WarmBackup' {
            $fallbackSnapshot = $ingestionHistorySnapshot
            if ($postColdSnapshot) {
                $fallbackSnapshot = $postColdSnapshot
            }
            $warmPassSnapshot = Get-IngestionHistoryWarmRunSnapshot -DirectoryPath $ingestionHistoryDir -FallbackSnapshot $fallbackSnapshot
        }
        'ColdOutput' {
            if ($postColdSnapshot) {
                $warmPassSnapshot = $postColdSnapshot
            } else {
                Write-Warning 'Post-cold ingestion history snapshot was unavailable; falling back to the initial snapshot for the warm pass.'
                $warmPassSnapshot = $ingestionHistorySnapshot
                $warmSeedMode = 'Snapshot'
            }
        }
        'Empty' {
            if ($postColdSnapshot) {
                $warmPassSnapshot = $postColdSnapshot
            } else {
                $warmPassSnapshot = $ingestionHistorySnapshot
            }
        }
        default {
            throw "Unsupported warm history seed mode '$WarmHistorySeed'."
        }
    }

    Set-IngestionHistoryForPass -SeedMode $warmSeedMode -Snapshot $warmPassSnapshot -PassLabel 'WarmPass'
    $restoredCacheCount = Restore-SharedCacheEntries -Entries $sharedCacheEntries
    if ($restoredCacheCount -gt 0) {
        Write-Host ("Restored {0} site cache entr{1} from the shared snapshot before warm pass." -f $restoredCacheCount, $(if ($restoredCacheCount -eq 1) { 'y' } else { 'ies' })) -ForegroundColor DarkCyan
    } elseif ($sharedCacheEntries -and ($sharedCacheEntries | Measure-Object).Count -gt 0) {
        Write-Warning 'Cached site entries were captured after the cold pass but none were restored before the warm pass.'
    }
    $results += [pscustomobject]@{
        PassLabel    = 'SharedCacheRestore:PreWarmPass'
        Timestamp    = Get-Date
        RestoredCount= $restoredCacheCount
    }
    if ($script:WarmRunSites -and $script:WarmRunSites.Count -gt 0) {
        Write-Host 'Recording site cache state before warm pass...' -ForegroundColor Cyan
        $cacheStatePreWarm = Get-SiteCacheState -Sites $script:WarmRunSites -Label 'CacheState:PreWarmPass'
        if ($cacheStatePreWarm) {
            $count = ($cacheStatePreWarm | Measure-Object).Count
            Write-Host ("Cache state entries before warm pass: {0}" -f $count) -ForegroundColor DarkCyan
            if ($count -gt 0) {
                Write-Host ("  -> {0}" -f (($cacheStatePreWarm | ForEach-Object { '{0}:{1}' -f $_.Site, $_.CacheStatus }) -join ', ')) -ForegroundColor DarkCyan
            }
            $results += @($cacheStatePreWarm)
        }
        Write-SharedCacheSnapshot -Label 'PreWarmPass'
    }
    $results += Invoke-PipelinePass -Label 'WarmPass'
} finally {
    Write-Host 'Restoring ingestion history to original snapshot...' -ForegroundColor Yellow
    Restore-IngestionHistory -Snapshot $ingestionHistorySnapshot
    try { ParserRunspaceModule\Reset-DeviceParseRunspacePool } catch { }
}

$comparisonSummary = $null
$coldMetrics = $null
$warmMetrics = $null
if ($script:PassInterfaceAnalysis.ContainsKey('ColdPass')) {
    $coldMetrics = $script:PassInterfaceAnalysis['ColdPass']
}
if ($script:PassInterfaceAnalysis.ContainsKey('WarmPass')) {
    $warmMetrics = $script:PassInterfaceAnalysis['WarmPass']
}

if ($coldMetrics -and $warmMetrics) {
    $normalizedWarmProviderCounts = ConvertTo-NormalizedProviderCounts -ProviderCounts $warmMetrics.ProviderCounts
    $normalizedColdProviderCounts = ConvertTo-NormalizedProviderCounts -ProviderCounts $coldMetrics.ProviderCounts

    $warmCacheProviderHitCount = 0
    if ($normalizedWarmProviderCounts.ContainsKey('Cache')) {
        $warmCacheProviderHitCount = [int]$normalizedWarmProviderCounts['Cache']
    }

    $warmCacheProviderMissCount = 0
    foreach ($entry in $normalizedWarmProviderCounts.GetEnumerator()) {
        if ($entry.Key -ne 'Cache') {
            $warmCacheProviderMissCount += [int]$entry.Value
        }
    }

    $warmCacheHitRatioPercent = $null
    if ($warmMetrics.Count -gt 0) {
        $warmCacheHitRatioPercent = [math]::Round(($warmCacheProviderHitCount / $warmMetrics.Count) * 100, 2)
    }

    $warmSignatureRewriteTotal = 0
    $warmSignatureMatchMissCount = 0
    foreach ($event in @($warmMetrics.Events)) {
        if (-not $event) {
            continue
        }

        $matchCount = 0
        if ($event.PSObject.Properties.Name -contains 'SiteCacheHostMapSignatureMatchCount') {
            try {
                $matchCount = [int]$event.SiteCacheHostMapSignatureMatchCount
            } catch {
                $matchCount = 0
            }
        }
        if ($matchCount -le 0) {
            $warmSignatureMatchMissCount++
        }

        if ($event.PSObject.Properties.Name -contains 'SiteCacheHostMapSignatureRewriteCount') {
            try {
                $warmSignatureRewriteTotal += [int]$event.SiteCacheHostMapSignatureRewriteCount
            } catch {
                # Ignore conversion issues
            }
        }
    }

    $improvementMs = $null
    if ($coldMetrics.AverageRaw -ne $null -and $warmMetrics.AverageRaw -ne $null) {
        $improvementMs = [math]::Round($coldMetrics.AverageRaw - $warmMetrics.AverageRaw, 3)
    }

    $improvementPercent = $null
    if ($improvementMs -ne $null -and $coldMetrics.AverageRaw -gt 0) {
        $improvementPercent = [math]::Round(($improvementMs / $coldMetrics.AverageRaw) * 100, 2)
    }

    $comparisonSummary = [pscustomobject]@{
        PassLabel                      = 'WarmRunComparison'
        SummaryType                    = 'InterfaceCallDuration'
        ColdHostCount                  = $coldMetrics.Count
        ColdInterfaceCallAvgMs         = $coldMetrics.Average
        ColdInterfaceCallP95Ms         = $coldMetrics.P95
        ColdInterfaceCallMaxMs         = $coldMetrics.Max
        WarmHostCount                  = $warmMetrics.Count
        WarmInterfaceCallAvgMs         = $warmMetrics.Average
        WarmInterfaceCallP95Ms         = $warmMetrics.P95
        WarmInterfaceCallMaxMs         = $warmMetrics.Max
        ImprovementAverageMs           = $improvementMs
        ImprovementPercent             = $improvementPercent
        WarmCacheProviderHitCount      = $warmCacheProviderHitCount
        WarmCacheProviderMissCount     = $warmCacheProviderMissCount
        WarmCacheHitRatioPercent       = $warmCacheHitRatioPercent
        WarmSignatureMatchMissCount    = $warmSignatureMatchMissCount
        WarmSignatureRewriteTotal      = $warmSignatureRewriteTotal
        WarmProviderCounts             = $normalizedWarmProviderCounts
        WarmInterfaceMetrics           = $warmMetrics
        ColdInterfaceMetrics           = $coldMetrics
        ColdProviderCounts             = $normalizedColdProviderCounts
    }

    $results += $comparisonSummary
}

if ($AssertWarmCache.IsPresent) {
    $assertFailures = New-Object 'System.Collections.Generic.List[string]'
    if (-not $comparisonSummary) {
        $assertFailures.Add('InterfaceCallDuration comparison metrics were not captured for cold and warm passes.')
    } else {
        if ($comparisonSummary.WarmHostCount -le 0) {
            $assertFailures.Add('Warm pass produced no DatabaseWriteBreakdown events.')
        }
        if ($comparisonSummary.WarmCacheProviderMissCount -gt 0) {
            $assertFailures.Add(("Warm pass reported {0} host(s) without SiteCacheProvider=Cache." -f $comparisonSummary.WarmCacheProviderMissCount))
        }
        if ($comparisonSummary.WarmSignatureMatchMissCount -gt 0) {
            $assertFailures.Add(("Warm pass reported {0} host(s) without HostMapSignatureMatchCount>0." -f $comparisonSummary.WarmSignatureMatchMissCount))
        }
        if ($comparisonSummary.WarmSignatureRewriteTotal -gt 0) {
            $assertFailures.Add(("Warm pass rewrote {0} cached host entries." -f $comparisonSummary.WarmSignatureRewriteTotal))
        }
        if ($coldMetrics -and $warmMetrics) {
            if ($warmMetrics.AverageRaw -eq $null -or $coldMetrics.AverageRaw -eq $null) {
                $assertFailures.Add('InterfaceCallDuration averages were unavailable for comparison.')
            } elseif ($warmMetrics.AverageRaw -ge $coldMetrics.AverageRaw) {
                $assertFailures.Add(("Warm InterfaceCallDurationMs average {0:N3} ms is not lower than cold {1:N3} ms." -f $warmMetrics.AverageRaw, $coldMetrics.AverageRaw))
            }
        }
    }

    if ($assertFailures.Count -gt 0) {
        throw ("Warm-run validation failed: {0}" -f ($assertFailures -join '; '))
    }
}

if ($OutputPath) {
    $totalResultCount = ($results | Measure-Object).Count
    Write-Host ("Result count prior to export: {0}" -f $totalResultCount) -ForegroundColor Yellow
    $directory = Split-Path -Path $OutputPath -Parent
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $exportPayload = $results | Select-Object PassLabel,SummaryType,Site,Timestamp,CacheStatus,Provider,HydrationDurationMs,SnapshotDurationMs,HostMapDurationMs,HostCount,TotalRows,HostMapSignatureMatchCount,HostMapSignatureRewriteCount,HostMapCandidateMissingCount,HostMapCandidateFromPrevious,PreviousHostCount,PreviousSnapshotStatus,PreviousSnapshotHostMapType,EntryCount,RestoredCount,SourceStage,ColdHostCount,WarmHostCount,ColdInterfaceCallAvgMs,ColdInterfaceCallP95Ms,ColdInterfaceCallMaxMs,WarmInterfaceCallAvgMs,WarmInterfaceCallP95Ms,WarmInterfaceCallMaxMs,ImprovementAverageMs,ImprovementPercent,WarmCacheProviderHitCount,WarmCacheProviderMissCount,WarmCacheHitRatioPercent,WarmSignatureMatchMissCount,WarmSignatureRewriteTotal,WarmProviderCounts,ColdProviderCounts
    $json = $exportPayload | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($OutputPath, $json)
    Write-Host "Warm-run telemetry summary exported to $OutputPath" -ForegroundColor Green
}

$results
