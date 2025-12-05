[CmdletBinding()]
param(
    [switch]$IncludeTests,
    [switch]$VerboseParsing,
    [switch]$ResetExtractedLogs,
    [switch]$SkipSchedulerFairnessGuard,
    [string]$OutputPath,
    [int]$PortBatchMaxConsecutiveOverride,
    [switch]$SkipWarmValidation,
    [ValidateSet('Empty','Snapshot')]
    [string]$ColdHistorySeed = 'Snapshot',
    [ValidateSet('Empty','Snapshot','ColdOutput','WarmBackup')]
    [string]$WarmHistorySeed = 'WarmBackup',
    [switch]$RefreshSiteCaches,
    [switch]$AssertWarmCache,
    [switch]$PreserveSkipSiteCacheSetting,
    [switch]$SkipPortDiversityGuard,
    [int]$ThreadCeilingOverride = 1,
    [int]$MaxWorkersPerSiteOverride = 1,
    [int]$MaxActiveSitesOverride = 1,
    [int]$JobsPerThreadOverride = 1,
    [int]$MinRunspacesOverride = 1,
    [string]$SiteExistingRowCacheSnapshotPath,
    [switch]$PreserveSharedCacheSnapshot,
    [switch]$GenerateDiffHotspotReport,
    [int]$DiffHotspotTop = 20,
    [string]$DiffHotspotOutputPath,
    [string[]]$HostFilter,
    [string]$HostFilterPath,
    [switch]$RestrictWarmComparisonToColdHosts,
    [switch]$AllowPartialHostFilterCoverage,
    [switch]$DisableSharedCacheSnapshot,
    [switch]$DisablePreservedRunspacePool
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skipSiteCacheGuardModule = Join-Path -Path $PSScriptRoot -ChildPath 'SkipSiteCacheUpdateGuard.psm1'
if (-not (Test-Path -LiteralPath $skipSiteCacheGuardModule)) {
    throw "Skip-site-cache guard module not found at $skipSiteCacheGuardModule."
}
Import-Module -Name $skipSiteCacheGuardModule -Force -ErrorAction Stop

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

$settingsPath = Join-Path -Path $repositoryRoot -ChildPath 'Data\StateTraceSettings.json'
$skipSiteCacheGuard = $null
$sharedCacheSnapshotEnvOriginal = $null
$sharedCacheSnapshotEnvApplied = $false

$script:PassInterfaceAnalysis = @{}
$script:PassSummaries = @{}
$script:PassHostnames = @{}
$script:ColdPassHostnames = $null

if (-not $SiteExistingRowCacheSnapshotPath) {
    $SiteExistingRowCacheSnapshotPath = Join-Path -Path (Join-Path $repositoryRoot 'Logs') -ChildPath ("SiteExistingRowCacheSnapshot-{0:yyyyMMdd-HHmmss}.clixml" -f (Get-Date))
}

$shouldGenerateDiffHotspots = $GenerateDiffHotspotReport.IsPresent -or -not [string]::IsNullOrWhiteSpace($DiffHotspotOutputPath)

$originalSiteExistingRowCacheSnapshotEnv = $null
try { $originalSiteExistingRowCacheSnapshotEnv = $env:STATETRACE_SITE_EXISTING_ROW_CACHE_SNAPSHOT } catch { $originalSiteExistingRowCacheSnapshotEnv = $null }

function Get-ParserPersistenceModule {
    $module = Get-Module -Name 'ParserPersistenceModule' -ErrorAction SilentlyContinue
    if ($module) { return $module }
    $modulePath = Join-Path -Path $repositoryRoot -ChildPath 'Modules\ParserPersistenceModule.psm1'
    if (Test-Path -LiteralPath $modulePath) {
        try {
            return Import-Module -Name $modulePath -PassThru -Force -ErrorAction Stop
        } catch {
            Write-Warning ("Unable to import ParserPersistenceModule: {0}" -f $_.Exception.Message)
        }
    }
    return $null
}

function Save-SiteExistingRowCacheSnapshot {
    param([string]$SnapshotPath)

    if ([string]::IsNullOrWhiteSpace($SnapshotPath)) { return }
    $module = Get-ParserPersistenceModule
    if (-not $module) { return }

    try {
        $snapshot = ParserPersistenceModule\Get-SiteExistingRowCacheSnapshot
        if (-not $snapshot -or ($snapshot | Measure-Object).Count -le 0) {
            Write-Verbose 'Site existing row cache snapshot skipped (no entries).' -Verbose:$VerboseParsing
            return
        }
        $directory = Split-Path -Path $SnapshotPath -Parent
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $snapshot | Export-Clixml -Path $SnapshotPath
        Write-Host ("Site existing row cache snapshot exported to '{0}'." -f $SnapshotPath) -ForegroundColor DarkCyan
    } catch {
        Write-Warning ("Failed to export site existing row cache snapshot: {0}" -f $_.Exception.Message)
    }
}

function Restore-SiteExistingRowCacheSnapshot {
    param([string]$SnapshotPath)

    if ([string]::IsNullOrWhiteSpace($SnapshotPath) -or -not (Test-Path -LiteralPath $SnapshotPath)) { return }
    $module = Get-ParserPersistenceModule
    if (-not $module) { return }

    try {
        $snapshot = Import-Clixml -Path $SnapshotPath
        if (-not $snapshot -or ($snapshot | Measure-Object).Count -le 0) {
            Write-Warning ("Site existing row cache snapshot '{0}' did not contain any entries." -f $SnapshotPath)
            return
        }
        ParserPersistenceModule\Set-SiteExistingRowCacheSnapshot -Snapshot $snapshot
        Write-Host ("Restored site existing row cache snapshot from '{0}' ({1} entr{2})." -f $SnapshotPath, ($snapshot | Measure-Object).Count, $(if (($snapshot | Measure-Object).Count -eq 1) { 'y' } else { 'ies' })) -ForegroundColor DarkCyan
    } catch {
        Write-Warning ("Failed to restore site existing row cache snapshot '{0}': {1}" -f $SnapshotPath, $_.Exception.Message)
    }
}

$script:PassInterfaceAnalysis = @{}
$script:PassSummaries = @{}

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

function Get-HostnameTokens {
    param(
        [Parameter(Mandatory)]
        [object]$Value
    )

    $tokens = @()
    if ($null -eq $Value) {
        return $tokens
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        foreach ($item in $Value) {
            $tokens += Get-HostnameTokens -Value $item
        }
        return $tokens
    }

    $text = '' + $Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $tokens
    }

    foreach ($part in ($text -split ',')) {
        $candidate = $part.Trim()
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $tokens += $candidate
        }
    }

    return $tokens
}

function Get-HostnameFilterSet {
    param(
        [string[]]$Hostnames,
        [string]$Path
    )

    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($name in @($Hostnames)) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        foreach ($token in (Get-HostnameTokens -Value $name)) {
            if ([string]::IsNullOrWhiteSpace($token)) { continue }
            $trimmed = $token.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                [void]$set.Add($trimmed)
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Warning ("Hostname filter file '{0}' was not found; proceeding without file-based entries." -f $Path)
        } else {
            try {
                $rawLines = Get-Content -LiteralPath $Path -ErrorAction Stop
                foreach ($line in @($rawLines)) {
                    foreach ($token in (Get-HostnameTokens -Value $line)) {
                        [void]$set.Add($token)
                    }
                }
            } catch {
                Write-Warning ("Failed to read hostname filter file '{0}': {1}" -f $Path, $_.Exception.Message)
            }
        }
    }

    if ($set.Count -le 0) {
        return $null
    }

    return ,$set
}

function Get-HostnamesFromEvents {
    param(
        [System.Collections.IEnumerable]$Events
    )

    $hostnames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($event in @($Events)) {
        if (-not $event) { continue }
        $value = $null
        if ($event.PSObject.Properties.Name -contains 'Hostname') {
            $value = $event.Hostname
        } elseif ($event.PSObject.Properties.Name -contains 'Hostnames') {
            $value = $event.Hostnames
        }
        foreach ($token in (Get-HostnameTokens -Value $value)) {
            if (-not [string]::IsNullOrWhiteSpace($token)) {
                [void]$hostnames.Add($token.Trim())
            }
        }
    }
    return $hostnames
}

function Filter-EventsByHostname {
    param(
        [object[]]$Events,
        [System.Collections.Generic.HashSet[string]]$AllowedHostnames
    )

    if (-not $Events) {
        return @()
    }
    if (-not $AllowedHostnames -or $AllowedHostnames.Count -le 0) {
        return @($Events)
    }

    $filtered = New-Object 'System.Collections.Generic.List[psobject]'
    foreach ($event in @($Events)) {
        if (-not $event) { continue }
        $hosts = @()
        if ($event.PSObject.Properties.Name -contains 'Hostname') {
            $hosts = Get-HostnameTokens -Value $event.Hostname
        } elseif ($event.PSObject.Properties.Name -contains 'Hostnames') {
            $hosts = Get-HostnameTokens -Value $event.Hostnames
        } elseif ($event.PSObject.Properties.Name -contains 'HostName') {
            $hosts = Get-HostnameTokens -Value $event.HostName
        } elseif ($event.PSObject.Properties.Name -contains 'Host') {
            $hosts = Get-HostnameTokens -Value $event.Host
        }
        if (-not $hosts -or ($hosts | Measure-Object).Count -le 0) {
            # Preserve host-less events so pass-level summaries retain cold coverage even when host filter is active.
            $filtered.Add($event) | Out-Null
            continue
        }
        $matchingHosts = @()
        foreach ($hostNameCandidate in $hosts) {
            if ([string]::IsNullOrWhiteSpace($hostNameCandidate)) { continue }
            $trimmed = $hostNameCandidate.Trim()
            if ($AllowedHostnames.Contains($trimmed)) {
                $matchingHosts += $trimmed
            }
        }
        if (-not $matchingHosts -or ($matchingHosts | Measure-Object).Count -le 0) {
            continue
        }

        foreach ($match in $matchingHosts) {
            $clone = $event.PSObject.Copy()
            if ($clone.PSObject.Properties.Match('Hostname').Count -gt 0) {
                $clone.Hostname = $match
            } else {
                Add-Member -InputObject $clone -NotePropertyName 'Hostname' -NotePropertyValue $match -Force
            }
            if ($clone.PSObject.Properties.Match('Hostnames').Count -gt 0) {
                $clone.Hostnames = $match
            }
            $filtered.Add($clone) | Out-Null
        }
    }

    return $filtered
}

function Add-PassLabelToEvents {
    param(
        [System.Collections.IEnumerable]$Events,
        [string]$PassLabel
    )

    if (-not $Events) { return @() }
    # Normalize to an enumerable collection we can iterate even if a single PSCustomObject is passed.
    if (-not ($Events -is [System.Collections.IEnumerable]) -or ($Events -is [string])) {
        $Events = @($Events)
    }
    $labeled = New-Object 'System.Collections.Generic.List[psobject]'
    foreach ($evt in @($Events)) {
        if (-not $evt) { continue }
        if (-not ($evt -is [psobject])) {
            try {
                $evt = [pscustomobject]@{ Value = $evt }
            } catch {
                continue
            }
        }

        $passLabelProp = $evt.PSObject.Properties.Match('PassLabel')
        $passLabelValue = $null
        if ($passLabelProp -and $passLabelProp.Count -gt 0) {
            try { $passLabelValue = $passLabelProp[0].Value } catch { $passLabelValue = $null }
        }

        if ([string]::IsNullOrWhiteSpace($passLabelValue)) {
            $target = $evt
            if (-not $passLabelProp -or $passLabelProp.Count -le 0) {
                try { $target = $evt.PSObject.Copy() } catch { $target = $evt }
            }
            $added = $false
            try { Add-Member -InputObject $target -NotePropertyName 'PassLabel' -NotePropertyValue $PassLabel -Force -ErrorAction Stop; $added = $true } catch { }
            if ($added) {
                $evt = $target
            } elseif (-not ($evt -is [pscustomobject])) {
                try {
                    $copyTable = @{}
                    foreach ($prop in $evt.PSObject.Properties) {
                        $copyTable[$prop.Name] = $prop.Value
                    }
                    $copyTable['PassLabel'] = $PassLabel
                    $evt = [pscustomobject]$copyTable
                } catch { }
            }
        }
        $labeled.Add($evt) | Out-Null
    }
    return $labeled
}

$script:ComparisonHostFilter = Get-HostnameFilterSet -Hostnames $HostFilter -Path $HostFilterPath
if ($script:ComparisonHostFilter -and $script:ComparisonHostFilter.Count -gt 0) {
    $preview = @($script:ComparisonHostFilter | Select-Object -First 10)
    Write-Host ("Hostname filter active with {0} entr{1}: {2}" -f $script:ComparisonHostFilter.Count, $(if ($script:ComparisonHostFilter.Count -eq 1) { 'y' } else { 'ies' }), [string]::Join(', ', $preview)) -ForegroundColor DarkCyan
}
if ($RestrictWarmComparisonToColdHosts.IsPresent) {
    Write-Host 'Warm comparison metrics will be limited to hostnames captured during the cold pass (intersected with any explicit filters).' -ForegroundColor DarkYellow
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
        [hashtable]$Baseline,
        [string[]]$ExcludePaths
    )

    $events = @()

    $excludeSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($path in @($ExcludePaths)) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            [void]$excludeSet.Add((Resolve-Path -LiteralPath $path).Path)
        } catch {
            Write-Verbose ("Failed to resolve exclude path '{0}': {1}" -f $path, $_.Exception.Message) -Verbose:$VerboseParsing
        }
    }

    foreach ($file in Get-ChildItem -Path $DirectoryPath -Filter '*.json' -File | Sort-Object FullName) {
        if ($file.BaseName -like 'QueueDelaySummary*') {
            continue
        }
        $resolved = $null
        try { $resolved = (Resolve-Path -LiteralPath $file.FullName).Path } catch { $resolved = $file.FullName }
        if ($excludeSet.Count -gt 0 -and $excludeSet.Contains($resolved)) {
            continue
        }

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
        $newEvents = Get-AppendedTelemetry -DirectoryPath $DirectoryPath -Baseline $Baseline -ExcludePaths @($OutputPath)
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

    $valueArray = @()
    if ($null -ne $Values) {
        $valueArray = @($Values)
    }

    if (-not $valueArray -or $valueArray.Count -eq 0) {
        return $null
    }

    $ordered = @($valueArray | Sort-Object)
    $maxIndex = $ordered.Count - 1
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
    if ($providerCounts.ContainsKey('Cache')) {
        $hitCount = [int]$providerCounts['Cache']
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

$perHostDatabaseProperties = @(
    'InterfaceCallDurationMs',
    'DatabaseWriteLatencyMs'
)

$perHostInterfaceProperties = @(
    'DiffComparisonDurationMs',
    'DiffDurationMs',
    'LoadExistingDurationMs',
    'LoadExistingRowSetCount',
    'LoadSignatureDurationMs',
    'LoadCacheHit',
    'LoadCacheMiss',
    'LoadCacheRefreshed',
    'CachedRowCount',
    'CachePrimedRowCount',
    'RowsStaged',
    'InsertCandidates',
    'UpdateCandidates',
    'DeleteCandidates',
    'DiffRowsCompared',
    'DiffRowsChanged',
    'DiffRowsInserted',
    'DiffRowsUnchanged',
    'DiffSeenPorts',
    'DiffDuplicatePorts',
    'UiCloneDurationMs',
    'DeleteDurationMs',
    'FallbackDurationMs',
    'FallbackUsed',
    'FactsConsidered',
    'ExistingCount'
)

function Merge-PerHostTelemetry {
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

    $buildMap = {
        param($events)

        $eventMap = @{}
        foreach ($eventRecord in @($events)) {
            if (-not $eventRecord -or -not $eventRecord.PSObject) { continue }

            $siteKey = ''
            if ($eventRecord.PSObject.Properties.Name -contains 'Site') {
                $siteKey = ('' + $eventRecord.Site).Trim()
            }
            if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }

            $hostKey = Get-HostKeyFromTelemetryEvent -Event $eventRecord
            if ([string]::IsNullOrWhiteSpace($hostKey)) { continue }

            $mapKey = '{0}|{1}' -f $siteKey, $hostKey
            if (-not $eventMap.ContainsKey($mapKey)) {
                $eventMap[$mapKey] = $eventRecord
            }
        }

        return $eventMap
    }

    $databaseEventMap = @{}
    if ($DatabaseEvents) {
        $databaseEventMap = & $buildMap $DatabaseEvents
    }

    $interfaceEventMap = @{}
    if ($InterfaceSyncEvents) {
        $interfaceEventMap = & $buildMap $InterfaceSyncEvents
    }

    foreach ($summary in $results) {
        if (-not $summary) { continue }

        $siteKey = ''
        if ($summary.PSObject.Properties.Name -contains 'Site') {
            $siteKey = ('' + $summary.Site).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }

        $hostKey = Get-HostKeyFromMetricsSummary -Summary $summary
        if ([string]::IsNullOrWhiteSpace($hostKey)) { continue }

        $mapKey = '{0}|{1}' -f $siteKey, $hostKey

        if ($databaseEventMap.ContainsKey($mapKey)) {
            $databaseEvent = $databaseEventMap[$mapKey]
            foreach ($propertyName in $perHostDatabaseProperties) {
                if ($databaseEvent.PSObject.Properties.Name -contains $propertyName) {
                    $summary | Add-Member -MemberType NoteProperty -Name $propertyName -Value $databaseEvent.$propertyName -Force
                }
            }
        }

        if ($interfaceEventMap.ContainsKey($mapKey)) {
            $interfaceEvent = $interfaceEventMap[$mapKey]
            foreach ($propertyName in $perHostInterfaceProperties) {
                if ($interfaceEvent.PSObject.Properties.Name -contains $propertyName) {
                    $summary | Add-Member -MemberType NoteProperty -Name $propertyName -Value $interfaceEvent.$propertyName -Force
                }
            }
        }
    }

    return $results
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
$sharedCacheSnapshotPath = $null

$pipelineArguments = @{
    PreserveModuleSession       = $true
    # Keep shared cache snapshots enabled so SnapshotImported telemetry is recorded; guard module handles SkipSiteCacheUpdate.
    DisableSharedCacheSnapshot  = $DisableSharedCacheSnapshot.IsPresent
}
if ($SkipSchedulerFairnessGuard) {
    $pipelineArguments['FailOnSchedulerFairness'] = $false
    Write-Warning 'Skipping parser scheduler fairness guard for warm-run telemetry run.'
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
if ($SkipPortDiversityGuard) {
    $pipelineArguments['SkipPortDiversityGuard'] = $true
}
if ($PSBoundParameters.ContainsKey('PortBatchMaxConsecutiveOverride')) {
    $pipelineArguments['PortBatchMaxConsecutiveOverride'] = $PortBatchMaxConsecutiveOverride
}
if ($DisablePreservedRunspacePool) {
    $pipelineArguments['DisablePreserveRunspace'] = $true
}

# Keep the parser runspace configuration identical across cold and warm passes so the preserved pool
# (and shared cache) stay alive between runs.
$pipelineArguments['ThreadCeilingOverride']     = $ThreadCeilingOverride
$pipelineArguments['MaxWorkersPerSiteOverride'] = $MaxWorkersPerSiteOverride
$pipelineArguments['MaxActiveSitesOverride']    = $MaxActiveSitesOverride
$pipelineArguments['JobsPerThreadOverride']     = $JobsPerThreadOverride
$pipelineArguments['MinRunspacesOverride']      = $MinRunspacesOverride

function Invoke-PipelinePass {
    param(
        [string]$Label
    )

    $passStartTime = Get-Date
    Write-Host "Running pipeline pass '$Label'..." -ForegroundColor Cyan
    & $pipelineScript @pipelineArguments | Out-Null
    Write-Host "Pipeline pass '$Label' completed." -ForegroundColor Green

    Wait-TelemetryFlush -DirectoryPath $metricsDirectory -Baseline $metricsBaseline

    $collection = Collect-TelemetryForPass -DirectoryPath $metricsDirectory -Baseline $metricsBaseline -PassStartTime $passStartTime -RequiredEventNames @('InterfaceSiteCacheMetrics','DatabaseWriteBreakdown','InterfaceSyncTiming')
    $telemetry = @()
    if ($collection -and $collection.Events) {
        $collection.Events = Add-PassLabelToEvents -Events $collection.Events -PassLabel $Label
        $telemetry = @($collection.Events)
    }

    $cacheMetrics = @()
    if ($collection -and $collection.Buckets.ContainsKey('InterfaceSiteCacheMetrics')) {
        $cacheMetrics = Add-PassLabelToEvents -Events @($collection.Buckets['InterfaceSiteCacheMetrics']) -PassLabel $Label
        $collection.Buckets['InterfaceSiteCacheMetrics'] = $cacheMetrics
    }

    $passResults = @()
    if (-not $cacheMetrics) {
        Write-Warning "No InterfaceSiteCacheMetrics events were captured for pass '$Label'."
    } else {
        $passResults += Convert-MetricsToSummary -PassLabel $Label -Metrics $cacheMetrics
    }

    $breakdownEvents = @()
    if ($collection -and $collection.Buckets.ContainsKey('DatabaseWriteBreakdown')) {
        $breakdownEvents = Add-PassLabelToEvents -Events @($collection.Buckets['DatabaseWriteBreakdown']) -PassLabel $Label
        $collection.Buckets['DatabaseWriteBreakdown'] = $breakdownEvents
    }
    if ($collection -and $collection.MissingEventNames -and $collection.MissingEventNames.Count -gt 0) {
        Write-Warning ("Telemetry still missing after polling for pass '{0}': {1}" -f $Label, ($collection.MissingEventNames -join ', '))
    }

    $passHostFilter = $script:ComparisonHostFilter
    if ($RestrictWarmComparisonToColdHosts.IsPresent -and $Label -eq 'WarmPass') {
        if ($script:ColdPassHostnames -and $script:ColdPassHostnames.Count -gt 0) {
            $passHostFilter = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($hostNameCandidate in @($script:ColdPassHostnames)) {
                if ([string]::IsNullOrWhiteSpace($hostNameCandidate)) { continue }
                if (-not $script:ComparisonHostFilter -or $script:ComparisonHostFilter.Count -le 0 -or $script:ComparisonHostFilter.Contains($hostNameCandidate)) {
                    [void]$passHostFilter.Add($hostNameCandidate.Trim())
                }
            }
        } elseif ($script:ComparisonHostFilter -and $script:ComparisonHostFilter.Count -gt 0) {
            Write-Warning 'Warm comparison host restriction requested but no cold-pass hostnames were captured; using explicit hostname filter only.'
        } else {
            Write-Warning 'Warm comparison host restriction requested but no cold-pass hostnames were captured; no hostname filter will be applied.'
        }
    }

    if ($VerboseParsing.IsPresent) {
        if ($passHostFilter -and $passHostFilter.Count -gt 0) {
            $preview = @($passHostFilter | Select-Object -First 10)
            Write-Host ("Pass '{0}' applying hostname filter ({1}): {2}" -f $Label, $passHostFilter.Count, [string]::Join(', ', $preview)) -ForegroundColor DarkCyan
        } else {
            Write-Host ("Pass '{0}' running without a hostname filter." -f $Label) -ForegroundColor DarkYellow
        }
    }

    if ($passHostFilter -and $passHostFilter.Count -gt 0 -and $cacheMetrics) {
        $originalCacheCount = ($cacheMetrics | Measure-Object).Count
        $cacheMetrics = Filter-EventsByHostname -Events @($cacheMetrics) -AllowedHostnames $passHostFilter
        $filteredCacheCount = ($cacheMetrics | Measure-Object).Count
        if ($filteredCacheCount -le 0 -and $originalCacheCount -gt 0) {
            Write-Warning ("Hostname filter removed all InterfaceSiteCacheMetrics events for pass '{0}' ({1} -> 0)." -f $Label, $originalCacheCount)
        } elseif ($originalCacheCount -ne $filteredCacheCount) {
            Write-Host ("Filtered InterfaceSiteCacheMetrics events for pass '{0}': {1} -> {2}." -f $Label, $originalCacheCount, $filteredCacheCount) -ForegroundColor DarkCyan
        }
    }

    $originalBreakdownCount = (@($breakdownEvents) | Measure-Object).Count
    $breakdownEvents = Filter-EventsByHostname -Events @($breakdownEvents) -AllowedHostnames $passHostFilter
    $filteredBreakdownCount = ($breakdownEvents | Measure-Object).Count
    if ($passHostFilter -and $passHostFilter.Count -gt 0 -and $originalBreakdownCount -ne $filteredBreakdownCount) {
        Write-Host ("Filtered DatabaseWriteBreakdown events for pass '{0}': {1} -> {2}." -f $Label, $originalBreakdownCount, $filteredBreakdownCount) -ForegroundColor DarkCyan
    }

    $passHostnames = Get-HostnamesFromEvents -Events $breakdownEvents
    $script:PassHostnames[$Label] = $passHostnames
    if ($Label -eq 'ColdPass') {
        $script:ColdPassHostnames = $passHostnames
    }

    if ($passHostFilter -and $passHostFilter.Count -gt 0 -and $Label -eq 'ColdPass') {
        $breakdownCount = ($breakdownEvents | Measure-Object).Count
        if ($breakdownCount -eq 0) {
            throw "No DatabaseWriteBreakdown events remained for cold pass after applying the hostname filter; cannot produce a valid warm-run comparison."
        }

        $missingHosts = @()
        foreach ($expected in $passHostFilter) {
            if ([string]::IsNullOrWhiteSpace($expected)) { continue }
            if (-not $passHostnames.Contains($expected)) {
                $missingHosts += $expected
            }
        }

        if ($missingHosts -and $missingHosts.Count -gt 0) {
            $message = ("Hostname filter required cold coverage for: {0}. Only saw: {1}" -f ([string]::Join(', ', $missingHosts)), ([string]::Join(', ', $passHostnames)))
            if ($AllowPartialHostFilterCoverage.IsPresent) {
                Write-Warning $message
            } else {
                throw $message
            }
        }
    }

    if ($breakdownEvents -and ($breakdownEvents | Measure-Object).Count -gt 0) {
        $script:PassInterfaceAnalysis[$Label] = Measure-InterfaceCallDurationMetrics -Events $breakdownEvents
    } else {
        $script:PassInterfaceAnalysis[$Label] = $null
        Write-Warning "No DatabaseWriteBreakdown events were captured for pass '$Label'."
    }

    $syncEvents = @()
    if ($collection -and $collection.Buckets.ContainsKey('InterfaceSyncTiming')) {
        $syncEvents = Add-PassLabelToEvents -Events @($collection.Buckets['InterfaceSyncTiming']) -PassLabel $Label
        $collection.Buckets['InterfaceSyncTiming'] = $syncEvents
    }
    if ($passHostFilter -and $passHostFilter.Count -gt 0 -and $syncEvents) {
        $originalSyncCount = ($syncEvents | Measure-Object).Count
        $syncEvents = Filter-EventsByHostname -Events @($syncEvents) -AllowedHostnames $passHostFilter
        $filteredSyncCount = ($syncEvents | Measure-Object).Count
        if ($originalSyncCount -ne $filteredSyncCount) {
            Write-Host ("Filtered InterfaceSyncTiming events for pass '{0}': {1} -> {2}." -f $Label, $originalSyncCount, $filteredSyncCount) -ForegroundColor DarkCyan
        }
    }

    $passResults = Resolve-SiteCacheProviderReasons -Summaries $passResults -DatabaseEvents $breakdownEvents -InterfaceSyncEvents $syncEvents
    $passResults = Merge-PerHostTelemetry -Summaries $passResults -DatabaseEvents $breakdownEvents -InterfaceSyncEvents $syncEvents
    $script:PassSummaries[$Label] = @($passResults)

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

    $telemetry = Get-AppendedTelemetry -DirectoryPath $metricsDirectory -Baseline $metricsBaseline -ExcludePaths @($OutputPath)
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

    $telemetry = Get-AppendedTelemetry -DirectoryPath $metricsDirectory -Baseline $metricsBaseline -ExcludePaths @($OutputPath)
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

    $stateSummaries = @()
    foreach ($site in $Sites) {
        $siteKey = '' + $site
        if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }
        $siteKey = $siteKey.Trim()

        $perSiteSummary = $module.Invoke(
            {
                param($siteArg)

                $entry = $null
                if ($script:SiteInterfaceSignatureCache -and $script:SiteInterfaceSignatureCache.ContainsKey($siteArg)) {
                    $entry = $script:SiteInterfaceSignatureCache[$siteArg]
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

                    return [pscustomobject]@{
                        Site        = $siteArg
                        State       = 'Present'
                        HostCount   = $hostCount
                        TotalRows   = $totalRows
                        CacheStatus = $cacheStatus
                        CachedAt    = $cachedAt
                    }
                }

                return [pscustomobject]@{
                    Site        = $siteArg
                    State       = 'Missing'
                    HostCount   = 0
                    TotalRows   = 0
                    CacheStatus = ''
                    CachedAt    = $null
                }
            },
            $siteKey
        )

        Write-Host ("Inspecting site cache entry '{0}': {1}" -f $siteKey, $(if ($perSiteSummary -and $perSiteSummary.State -eq 'Present') { 'present' } else { 'missing' })) -ForegroundColor DarkGray

        if ($perSiteSummary) {
            $stateSummaries += $perSiteSummary
        }
    }

    if (-not $stateSummaries) {
        return @()
    }

    $now = Get-Date
    return $stateSummaries | ForEach-Object {
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

function ConvertTo-SharedCacheEntryArray {
    param([object]$Entries)

    if (-not $Entries) { return @() }

    $current = $Entries
    while ($current -is [System.Collections.IList] -and $current.Count -eq 1 -and ($current[0] -is [System.Collections.IList])) {
        $current = $current[0]
    }

    if ($current -is [System.Collections.IList]) {
        return @($current)
    }

    return ,$current
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

function Get-SharedCacheSummary {
    param(
        [Parameter(Mandatory)][string]$Label,
        [switch]$SuppressWarnings
    )

    $module = Get-Module -Name 'DeviceRepositoryModule'
    if (-not $module) {
        $modulePath = Join-Path -Path $repositoryRoot -ChildPath 'Modules\DeviceRepositoryModule.psm1'
        if (Test-Path -LiteralPath $modulePath) {
            $module = Import-Module -Name $modulePath -PassThru -ErrorAction SilentlyContinue
        }
    }
    if (-not $module) {
        if (-not $SuppressWarnings.IsPresent) {
            Write-Warning ("Shared cache summary '{0}' skipped: DeviceRepositoryModule not loaded." -f $Label)
        }
        return $null
    }

    $summary = $module.Invoke(
        {
            param($labelArg)

            $scriptCount = 0
            $scriptSites = @()
            if ($script:SiteInterfaceSignatureCache -is [System.Collections.IDictionary]) {
                try { $scriptCount = [int]$script:SiteInterfaceSignatureCache.Count } catch { $scriptCount = 0 }
                try { $scriptSites = @($script:SiteInterfaceSignatureCache.Keys) } catch { $scriptSites = @() }
            }

            $domainCount = 0
            $domainSites = @()
            $store = Get-SharedSiteInterfaceCacheStore
            if ($store -is [System.Collections.IDictionary]) {
                try { $domainCount = [int]$store.Count } catch { $domainCount = 0 }
                try { $domainSites = @($store.Keys) } catch { $domainSites = @() }
            }

            [pscustomobject]@{
                PassLabel        = $labelArg
                Timestamp        = Get-Date
                ScriptCacheCount = $scriptCount
                ScriptCacheSites = $scriptSites
                DomainCacheCount = $domainCount
                DomainCacheSites = $domainSites
            }
        },
        $Label
    )

    if (-not $summary) { return $null }

    Write-Host ("Shared cache summary '{0}': script={1}, domain={2}" -f $summary.PassLabel, $summary.ScriptCacheCount, $summary.DomainCacheCount) -ForegroundColor DarkCyan
    if ($summary.ScriptCacheSites -and $summary.ScriptCacheSites.Count -gt 0) {
        Write-Host ("  -> Script sites: {0}" -f ([string]::Join(', ', $summary.ScriptCacheSites))) -ForegroundColor DarkCyan
    }
    if ($summary.DomainCacheSites -and $summary.DomainCacheSites.Count -gt 0) {
        Write-Host ("  -> Domain sites: {0}" -f ([string]::Join(', ', $summary.DomainCacheSites))) -ForegroundColor DarkCyan
    }
    return $summary
}

function Get-SharedCacheEntriesSnapshot {
    param(
        [string[]]$FallbackSites = @()
    )

    $verboseFlag = $false
    try { $verboseFlag = [bool]$VerboseParsing.IsPresent } catch { $verboseFlag = $false }

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

    $entries = @()
    try {
        $entries = $module.Invoke(
            {
                param($sitesFallback, [bool]$verboseFlag)

                $normalizedFallbackSites = @()
                foreach ($siteCandidate in @($sitesFallback)) {
                    if ([string]::IsNullOrWhiteSpace($siteCandidate)) { continue }
                    $normalizedFallbackSites += ('' + $siteCandidate).Trim()
                }

                $result = New-Object 'System.Collections.Generic.List[psobject]'
                $seenSites = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

                $appendEntry = {
                    param([string]$siteKey, [psobject]$entryValue)

                    if ([string]::IsNullOrWhiteSpace($siteKey) -or -not $entryValue) { return }
                    $normalizedSite = $siteKey.Trim()
                    if ([string]::IsNullOrWhiteSpace($normalizedSite)) { return }
                    if ($seenSites.Contains($normalizedSite)) { return }

                    $result.Add([pscustomobject]@{ Site = $normalizedSite; Entry = $entryValue }) | Out-Null
                    $seenSites.Add($normalizedSite) | Out-Null
                }

                $snapshotEntries = @()
                try { $snapshotEntries = @(Get-SharedSiteInterfaceCacheSnapshotEntries) } catch { $snapshotEntries = @() }
                foreach ($snapshotEntry in $snapshotEntries) {
                    if (-not $snapshotEntry) { continue }
                    $snapshotSite = $null
                    if ($snapshotEntry.PSObject.Properties.Name -contains 'Site') {
                        $snapshotSite = ('' + $snapshotEntry.Site).Trim()
                    } elseif ($snapshotEntry.PSObject.Properties.Name -contains 'SiteKey') {
                        $snapshotSite = ('' + $snapshotEntry.SiteKey).Trim()
                    }
                    if ([string]::IsNullOrWhiteSpace($snapshotSite)) { continue }
                    $snapshotValue = $snapshotEntry
                    if ($snapshotEntry.PSObject.Properties.Name -contains 'Entry') {
                        $snapshotValue = $snapshotEntry.Entry
                    }
                    if (-not $snapshotValue) { continue }
                    & $appendEntry $snapshotSite $snapshotValue
                }

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
                        Write-Verbose ("Shared cache adoption candidates - script: {0}, domain: {1}" -f $scriptCount, $domainCount) -Verbose:$verboseFlag
                        if ($domainCount -gt $scriptCount) {
                            $store = $domainStore
                            $script:SiteInterfaceSignatureCache = $domainStore
                            try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetStore($domainStore) } catch { }
                        }
                    }
                }

                if ($verboseFlag) {
                    $storeSummary = @()
                    if ($store -is [System.Collections.IDictionary]) {
                        foreach ($key in @($store.Keys)) {
                            $hostCount = 0
                            $rowSum = 0
                            try {
                                $entry = Get-SharedSiteInterfaceCacheEntry -SiteKey $key
                                if ($entry -and $entry.HostMap -is [System.Collections.IDictionary]) {
                                    $hostCount = ($entry.HostMap.Keys | Measure-Object).Count
                                    foreach ($map in $entry.HostMap.Values) {
                                        if ($map -is [System.Collections.IDictionary]) {
                                            $rowSum += $map.Count
                                        }
                                    }
                                }
                            } catch { }
                            $storeSummary += [pscustomobject]@{ Site = $key; HostCount = $hostCount; TotalRows = $rowSum }
                        }
                    }
                    if ($storeSummary -and $storeSummary.Count -gt 0) {
                        $storeSummaryText = ($storeSummary | Sort-Object Site | ForEach-Object { "{0}:hosts={1},rows={2}" -f $_.Site, $_.HostCount, $_.TotalRows }) -join '; '
                        Write-Host ("Shared cache store snapshot (pre-export): {0}" -f $storeSummaryText) -ForegroundColor DarkCyan
                    } else {
                        Write-Host 'Shared cache store snapshot (pre-export): empty or unavailable.' -ForegroundColor DarkYellow
                    }
                }

                if ($store -is [System.Collections.IDictionary] -and $store.Count -gt 0) {
                    foreach ($key in @($store.Keys)) {
                        $entry = Get-SharedSiteInterfaceCacheEntry -SiteKey $key
                        if ($entry) {
                            & $appendEntry $key $entry
                        }
                    }
                }

                if ($result.Count -eq 0 -and $script:SiteInterfaceSignatureCache -is [System.Collections.IDictionary]) {
                    foreach ($cacheKey in @($script:SiteInterfaceSignatureCache.Keys)) {
                        $entryCandidate = $script:SiteInterfaceSignatureCache[$cacheKey]
                        if (-not $entryCandidate) { continue }
                        $normalized = $null
                        try { $normalized = Normalize-InterfaceSiteCacheEntry -Entry $entryCandidate } catch { $normalized = $null }
                        if ($normalized) {
                            & $appendEntry $cacheKey $normalized
                        }
                    }
                }

                if ($result.Count -eq 0 -and $normalizedFallbackSites.Count -gt 0) {
                    foreach ($fallbackSite in $normalizedFallbackSites) {
                        if ([string]::IsNullOrWhiteSpace($fallbackSite)) { continue }
                        $normalizedSiteKey = $fallbackSite.Trim()
                        if ([string]::IsNullOrWhiteSpace($normalizedSiteKey)) { continue }

                        $fetchedEntry = $null
                        try { $fetchedEntry = Get-InterfaceSiteCache -Site $normalizedSiteKey -Refresh } catch { $fetchedEntry = $null }
                        if (-not $fetchedEntry -and $normalizedSiteKey.Length -gt 0) {
                            $alphaPrefix = ($normalizedSiteKey -replace '[^A-Za-z]').Trim()
                            if (-not [string]::IsNullOrWhiteSpace($alphaPrefix) -and $alphaPrefix -ne $normalizedSiteKey) {
                                try { $fetchedEntry = Get-InterfaceSiteCache -Site $alphaPrefix -Refresh } catch { $fetchedEntry = $null }
                            }
                        }
                        if (-not $fetchedEntry) { continue }

                        $normalizedFetched = $null
                        try { $normalizedFetched = Normalize-InterfaceSiteCacheEntry -Entry $fetchedEntry } catch { $normalizedFetched = $null }
                        if ($normalizedFetched) {
                            & $appendEntry $normalizedSiteKey $normalizedFetched
                        }
                    }
                }

                if ($verboseFlag -and $result.Count -gt 0) {
                    Write-Host ("Shared cache snapshot candidates: {0}" -f $result.Count) -ForegroundColor DarkCyan
                    foreach ($entry in @($result)) {
                        if (-not $entry -or -not $entry.Entry) { continue }
                        $hostCount = 0
                        $totalRows = 0
                        if ($entry.Entry.PSObject.Properties.Name -contains 'HostCount') {
                            try { $hostCount = [int]$entry.Entry.HostCount } catch { $hostCount = 0 }
                        }
                        if ($entry.Entry.PSObject.Properties.Name -contains 'TotalRows') {
                            try { $totalRows = [int]$entry.Entry.TotalRows } catch { $totalRows = 0 }
                        }
                        if ($hostCount -le 0 -and $entry.Entry.HostMap -is [System.Collections.IDictionary]) {
                            try { $hostCount = ($entry.Entry.HostMap.Keys | Measure-Object).Count } catch { $hostCount = 0 }
                            foreach ($map in $entry.Entry.HostMap.Values) {
                                if ($map -is [System.Collections.IDictionary]) {
                                    try { $totalRows += $map.Count } catch { }
                                }
                            }
                        }
                        $cacheStatus = ''
                        if ($entry.Entry.PSObject.Properties.Name -contains 'CacheStatus') {
                            try { $cacheStatus = '' + $entry.Entry.CacheStatus } catch { $cacheStatus = '' }
                        }
                        if ([string]::IsNullOrWhiteSpace($cacheStatus)) {
                            $cacheStatus = 'Unknown'
                        }
                        Write-Host ("  -> {0}: HostCount={1}, TotalRows={2}, CacheStatus={3}" -f $entry.Site, $hostCount, $totalRows, $cacheStatus) -ForegroundColor DarkCyan
                    }
                }

                return ,$result.ToArray()
            },
            @($FallbackSites, $verboseFlag)
        )
    } catch {
        $err = $_
        $siteList = '(none)'
        try {
            if ($FallbackSites) { $siteList = [string]::Join(', ', @($FallbackSites)) }
        } catch { }
        $errDetails = $null
        try { $errDetails = $err.ToString() } catch { $errDetails = $err.Exception.Message }
        Write-Warning ("Failed to capture shared cache entries snapshot (sites: {0}): {1}" -f $siteList, $errDetails)
        $entries = @()
    }

    if (-not $entries) { return @() }
    return @($entries)
}
function Write-SharedCacheSnapshotFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [System.Collections.IEnumerable]$Entries
    )

    $entryArray = ConvertTo-SharedCacheEntryArray -Entries $Entries
    $sanitizedEntries = New-Object 'System.Collections.Generic.List[psobject]'

    foreach ($entry in $entryArray) {
        if (-not $entry) { continue }

        $siteValue = ''
        if ($entry.PSObject.Properties.Name -contains 'Site') {
            $siteValue = ('' + $entry.Site).Trim()
        } elseif ($entry.PSObject.Properties.Name -contains 'SiteKey') {
            $siteValue = ('' + $entry.SiteKey).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($siteValue)) { continue }

        $entryValue = $null
        if ($entry.PSObject.Properties.Name -contains 'Entry') {
            $entryValue = $entry.Entry
        }
        if (-not $entryValue -or ($entryValue.PSObject.Properties.Name -contains 'HostCount' -and [int]$entryValue.HostCount -le 0)) {
            # Try to rehydrate missing/empty entries directly from the cache store.
            $rehydrated = $null
            try { $rehydrated = DeviceRepositoryModule\Get-InterfaceSiteCache -Site $siteValue -Refresh } catch { $rehydrated = $null }
            if (-not $rehydrated -and $siteValue) {
                $alphaPrefix = ($siteValue -replace '[^A-Za-z]').Trim()
                if ($alphaPrefix -and $alphaPrefix -ne $siteValue) {
                    try { $rehydrated = DeviceRepositoryModule\Get-InterfaceSiteCache -Site $alphaPrefix -Refresh } catch { $rehydrated = $null }
                    if ($rehydrated) {
                        $siteValue = $alphaPrefix
                    }
                }
            }
            if ($rehydrated) {
                try { $entryValue = Normalize-InterfaceSiteCacheEntry -Entry $rehydrated } catch { $entryValue = $rehydrated }
            }
        }

        if (-not $entryValue) {
            Write-Warning ("Shared cache snapshot entry for site '{0}' is missing cache data and will be skipped." -f $siteValue)
            continue
        }

        $sanitizedEntries.Add([pscustomobject]@{
                Site  = $siteValue
                Entry = $entryValue
            }) | Out-Null
    }

    $directory = $null
    try { $directory = Split-Path -Parent $Path } catch { $directory = $null }
    try {
        if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        if ($sanitizedEntries.Count -eq 0) {
            Write-Warning 'Shared cache snapshot contained no valid site entries; exporting empty snapshot.'
        }
        $exportEntries = if ($sanitizedEntries.Count -gt 0) { $sanitizedEntries.ToArray() } else { @() }
        Export-Clixml -InputObject $exportEntries -Path $Path -Depth 20
    } catch {
        Write-Warning ("Failed to write shared cache snapshot to '{0}': {1}" -f $Path, $_.Exception.Message)
    }
}

function Restore-SharedCacheEntries {
    param(
        [System.Collections.IEnumerable]$Entries
    )

    if (-not $Entries) { return 0 }

    $entryArray = ConvertTo-SharedCacheEntryArray -Entries $Entries
    if (-not $entryArray -or $entryArray.Count -eq 0) { return 0 }

    $validEntries = New-Object 'System.Collections.Generic.List[psobject]'
    foreach ($entry in $entryArray) {
        if (-not $entry) { continue }

        $siteName = ''
        if ($entry.PSObject.Properties.Name -contains 'Site') {
            $siteName = ('' + $entry.Site).Trim()
        } elseif ($entry.PSObject.Properties.Name -contains 'SiteKey') {
            $siteName = ('' + $entry.SiteKey).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($siteName)) { continue }

        $entryValue = $null
        if ($entry.PSObject.Properties.Name -contains 'Entry') {
            $entryValue = $entry.Entry
        }
        if (-not $entryValue) {
            Write-Warning ("Shared cache snapshot entry for site '{0}' is missing cache data and will be ignored during restore." -f $siteName)
            continue
        }

        $validEntries.Add([pscustomobject]@{
                Site  = $siteName
                Entry = $entryValue
            }) | Out-Null
    }

    $sanitizedEntries = $validEntries.ToArray()
    if (-not $sanitizedEntries -or $sanitizedEntries.Count -eq 0) {
        Write-Warning 'No valid shared cache entries were available to restore.'
        return 0
    }

    $sitesToWarm = New-Object 'System.Collections.Generic.List[string]'
    $siteEntryTable = @{}
    foreach ($entry in $validEntries) {
        $siteName = ('' + $entry.Site).Trim()
        if ([string]::IsNullOrWhiteSpace($siteName)) { continue }
        if (-not ($sitesToWarm.Contains($siteName))) {
            $null = $sitesToWarm.Add($siteName)
        }
        $entryValue = $entry.Entry
        if ($entryValue) {
            $siteEntryTable[$siteName] = $entryValue
        }
    }

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
                $normalizedEntry = Normalize-InterfaceSiteCacheEntry -Entry $entryValue
                if (-not $script:SiteInterfaceSignatureCache) {
                    $script:SiteInterfaceSignatureCache = @{}
                }
                $script:SiteInterfaceSignatureCache[$siteKey] = $normalizedEntry
                Set-SharedSiteInterfaceCacheEntry -SiteKey $siteKey -Entry $normalizedEntry
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
        @{ EntryList = $sanitizedEntries }
    )

    if ($sitesToWarm.Count -gt 0 -and $siteEntryTable.Count -gt 0) {
        foreach ($siteKey in @($siteEntryTable.Keys)) {
            $entryForSite = $siteEntryTable[$siteKey]
            if (-not $entryForSite) { continue }
            $normalizedEntry = $module.Invoke({ param($entry) Normalize-InterfaceSiteCacheEntry -Entry $entry }, $entryForSite)
            if ($normalizedEntry) {
                $siteEntryTable[$siteKey] = $normalizedEntry
            }
        }
    }

    if ($sitesToWarm.Count -gt 0) {
        try {
            $parserModule = Get-Module -Name 'ParserRunspaceModule'
            if (-not $parserModule) {
                $parserModulePath = Join-Path -Path $repositoryRoot -ChildPath 'Modules\ParserRunspaceModule.psm1'
                if (Test-Path -LiteralPath $parserModulePath) {
                    $parserModule = Import-Module -Name $parserModulePath -PassThru -ErrorAction SilentlyContinue
                }
            }
            if ($parserModule) {
                try {
                    ParserRunspaceModule\Invoke-InterfaceSiteCacheWarmup -Sites $sitesToWarm.ToArray() -SiteEntries $siteEntryTable | Out-Null
                } catch {
                    Write-Warning ("Failed to warm preserved runspace caches for restored sites ({0}): {1}" -f ([string]::Join(', ', $sitesToWarm.ToArray())), $_.Exception.Message)
                }
            } else {
                Write-Warning 'Unable to warm preserved runspace caches because ParserRunspaceModule is not loaded.'
            }
        } catch {
            Write-Warning ("Exception while attempting to warm preserved runspace caches: {0}" -f $_.Exception.Message)
        }
    }

    if ($restoredCount -is [System.Array]) {
        if ($restoredCount.Length -gt 0) {
            return [int]$restoredCount[-1]
        }
        return 0
    }

    return [int]$restoredCount
}

$skipWarmRunTelemetryMain = $false
try {
    $existingSkip = Get-Variable -Name 'WarmRunTelemetrySkipMain' -Scope Global -ErrorAction SilentlyContinue
    if ($existingSkip) {
        try { $skipWarmRunTelemetryMain = [bool]$existingSkip.Value } catch { $skipWarmRunTelemetryMain = $true }
    }
} catch {
    $skipWarmRunTelemetryMain = $false
}
if (-not $skipWarmRunTelemetryMain) {
    if ([string]::Equals($env:STATETRACE_SKIP_WARM_RUN_TELEMETRY_MAIN, '1', [System.StringComparison]::OrdinalIgnoreCase)) {
        $skipWarmRunTelemetryMain = $true
    }
}
if ($skipWarmRunTelemetryMain) {
    return
}

try {
    if (-not $PreserveSkipSiteCacheSetting.IsPresent) {
        $skipSiteCacheGuard = Disable-SkipSiteCacheUpdateSetting -SettingsPath $settingsPath -Label 'WarmRunTelemetry'
    }
    if (-not $sharedCacheSnapshotPath) {
        $snapshotFileName = "SharedCacheSnapshot-{0:yyyyMMdd-HHmmss}.clixml" -f (Get-Date)
        $sharedCacheSnapshotPath = Join-Path -Path (Join-Path $repositoryRoot 'Logs') -ChildPath $snapshotFileName
    }
    if (-not $sharedCacheSnapshotEnvApplied -and $sharedCacheSnapshotPath) {
        try { $sharedCacheSnapshotEnvOriginal = $env:STATETRACE_SHARED_CACHE_SNAPSHOT } catch { $sharedCacheSnapshotEnvOriginal = $null }
        try {
            $env:STATETRACE_SHARED_CACHE_SNAPSHOT = $sharedCacheSnapshotPath
            $sharedCacheSnapshotEnvApplied = $true
        } catch {
            $sharedCacheSnapshotEnvApplied = $false
        }
    }

    $pipelineArguments['SharedCacheSnapshotExportPath'] = $sharedCacheSnapshotPath
    Set-IngestionHistoryForPass -SeedMode $ColdHistorySeed -Snapshot $ingestionHistorySnapshot -PassLabel 'ColdPass'
    $results += Invoke-PipelinePass -Label 'ColdPass'

    if ($pipelineArguments.ContainsKey('SharedCacheSnapshotExportPath')) {
        $pipelineArguments.Remove('SharedCacheSnapshotExportPath')
    }
    Write-SharedCacheSnapshot -Label 'PostColdPass'
    $postColdSummary = Get-SharedCacheSummary -Label 'SharedCacheState:PostColdPass'
    if ($postColdSummary) {
        $results += $postColdSummary
    }
    if ($SiteExistingRowCacheSnapshotPath) {
        Save-SiteExistingRowCacheSnapshot -SnapshotPath $SiteExistingRowCacheSnapshotPath
        try { $env:STATETRACE_SITE_EXISTING_ROW_CACHE_SNAPSHOT = $SiteExistingRowCacheSnapshotPath } catch { }
    }
    $initialSiteCandidates = @()
    try { $initialSiteCandidates = Get-SitesFromSnapshot -Snapshot $ingestionHistorySnapshot } catch { $initialSiteCandidates = @() }
    if ($initialSiteCandidates -and $initialSiteCandidates.Count -gt 0) {
        $postColdProbe = Invoke-SiteCacheProbe -Sites $initialSiteCandidates -Label 'CacheProbe:PostColdPass'
        if ($postColdProbe -and $postColdProbe.Count -gt 0) {
            $results += $postColdProbe
        }
    }
    $usingExportedSnapshot = $false
    if ($sharedCacheSnapshotPath -and (Test-Path -LiteralPath $sharedCacheSnapshotPath)) {
        try {
            $sharedCacheEntries = ConvertTo-SharedCacheEntryArray -Entries (Import-Clixml -Path $sharedCacheSnapshotPath)
            if ($sharedCacheEntries -and ($sharedCacheEntries | Measure-Object).Count -gt 0) {
                $usingExportedSnapshot = $true
            } else {
                $sharedCacheEntries = @()
            }
        } catch {
            Write-Warning ("Failed to import shared cache snapshot exported by the cold pass: {0}" -f $_.Exception.Message)
            $sharedCacheEntries = @()
        }
    }
    if ($SiteExistingRowCacheSnapshotPath -and (Test-Path -LiteralPath $SiteExistingRowCacheSnapshotPath)) {
        Restore-SiteExistingRowCacheSnapshot -SnapshotPath $SiteExistingRowCacheSnapshotPath
    }
    if (-not $sharedCacheEntries -or ($sharedCacheEntries | Measure-Object).Count -eq 0) {
        $sharedCacheEntries = ConvertTo-SharedCacheEntryArray -Entries (Get-SharedCacheEntriesSnapshot -FallbackSites $initialSiteCandidates)
    }
    $capturedAfterCold = ($sharedCacheEntries | Measure-Object).Count

    try {
        Write-Host 'Capturing ingestion history produced by cold pass for potential warm-run reuse...' -ForegroundColor Yellow
        $postColdSnapshot = Get-IngestionHistorySnapshot -DirectoryPath $ingestionHistoryDir
    } catch {
        Write-Warning "Failed to capture post-cold ingestion history snapshot. $($_.Exception.Message)"
    }

    if ($capturedAfterCold -eq 0) {
        $postColdFallbackSites = @()
        if ($postColdSnapshot) {
            try { $postColdFallbackSites = Get-SitesFromSnapshot -Snapshot $postColdSnapshot } catch { $postColdFallbackSites = @() }
        }
        if (-not $postColdFallbackSites -or $postColdFallbackSites.Count -eq 0) {
            try { $postColdFallbackSites = Get-SitesFromSnapshot -Snapshot $ingestionHistorySnapshot } catch { $postColdFallbackSites = @() }
        }
        if ($postColdFallbackSites -and $postColdFallbackSites.Count -gt 0) {
            $sharedCacheEntries = ConvertTo-SharedCacheEntryArray -Entries (Get-SharedCacheEntriesSnapshot -FallbackSites $postColdFallbackSites)
            $capturedAfterCold = ($sharedCacheEntries | Measure-Object).Count
        }
    }

    if (-not $usingExportedSnapshot -and $sharedCacheSnapshotPath) {
        Write-SharedCacheSnapshotFile -Path $sharedCacheSnapshotPath -Entries @($sharedCacheEntries)
        Write-Host ("Shared cache snapshot saved to '{0}'." -f $sharedCacheSnapshotPath) -ForegroundColor DarkCyan
    }
    if ($capturedAfterCold -gt 0) {
        Write-Host ("Captured {0} shared cache entr{1} after cold pass." -f $capturedAfterCold, $(if ($capturedAfterCold -eq 1) { 'y' } else { 'ies' })) -ForegroundColor DarkCyan
    } else {
        Write-Warning 'Shared cache snapshot after cold pass contained no entries.'
    }
    try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::ClearSnapshot() } catch { }
    $results += [pscustomobject]@{
        PassLabel   = 'SharedCacheSnapshot:PostColdPass'
        Timestamp   = Get-Date
        EntryCount  = $capturedAfterCold
        SourceStage = 'ColdPass'
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
                $postRefreshSummary = Get-SharedCacheSummary -Label 'SharedCacheState:PostRefresh'
                if ($postRefreshSummary) {
                    $results += $postRefreshSummary
                }
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
                $refreshedEntries = ConvertTo-SharedCacheEntryArray -Entries (Get-SharedCacheEntriesSnapshot -FallbackSites $sitesForRefresh)
                $refreshEntryTable = @{}
                foreach ($entry in $refreshedEntries) {
                    if (-not $entry) { continue }
                    $siteKey = ''
                    if ($entry.PSObject.Properties.Name -contains 'Site') {
                        $siteKey = ('' + $entry.Site).Trim()
                    } elseif ($entry.PSObject.Properties.Name -contains 'SiteKey') {
                        $siteKey = ('' + $entry.SiteKey).Trim()
                    }
                    if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }
                    if ($entry.PSObject.Properties.Name -contains 'Entry') {
                        $entryValue = $entry.Entry
                        if ($entryValue) { $refreshEntryTable[$siteKey] = $entryValue }
                    }
                }
                try {
                    ParserRunspaceModule\Invoke-InterfaceSiteCacheWarmup -Sites $sitesForRefresh -Refresh -SiteEntries $refreshEntryTable
                } catch {
                    Write-Warning "Failed to warm parser runspace caches: $($_.Exception.Message)"
                }
                $sharedCacheEntries = $refreshedEntries
                if ($sharedCacheSnapshotPath) {
                    Write-SharedCacheSnapshotFile -Path $sharedCacheSnapshotPath -Entries @($sharedCacheEntries)
                    Write-Host ("Updated shared cache snapshot at '{0}' with refreshed entries." -f $sharedCacheSnapshotPath) -ForegroundColor DarkCyan
                }
            } else {
                Write-Warning 'No site codes were discovered in the ingestion history snapshot; skipping cache refresh.'
            }
        } catch {
            $err = $_
            $details = $err
            try { $details = $err.ToString() } catch { }
            Write-Warning ("Site cache refresh step failed: {0}`n{1}" -f $err.Exception.Message, $details)
        }
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

    $sharedCacheSites = @($sharedCacheEntries | ForEach-Object {
            if (-not $_) { return }
            if ($_.PSObject.Properties.Name -contains 'Site') {
                $value = ('' + $_.Site).Trim()
                if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
            } elseif ($_.PSObject.Properties.Name -contains 'SiteKey') {
                $value = ('' + $_.SiteKey).Trim()
                if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
            }
        } | Where-Object { $_ })
    if ($sharedCacheSites.Count -gt 0) {
        Write-Host ("Shared cache snapshot sites available for warm pass: {0}" -f ([string]::Join(', ', ($sharedCacheSites | Sort-Object)))) -ForegroundColor DarkCyan
    } else {
        Write-Warning 'Shared cache snapshot did not include any site keys.'
    }

    $warmRunSiteSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($existingSite in @($script:WarmRunSites)) {
        if ([string]::IsNullOrWhiteSpace($existingSite)) { continue }
        [void]$warmRunSiteSet.Add($existingSite.Trim())
    }
    foreach ($entry in @($sharedCacheEntries)) {
        if (-not $entry) { continue }
        $siteKey = ''
        if ($entry.PSObject.Properties.Name -contains 'Site') {
            $siteKey = '' + $entry.Site
        } elseif ($entry.PSObject.Properties.Name -contains 'SiteKey') {
            $siteKey = '' + $entry.SiteKey
        }
        if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }
        [void]$warmRunSiteSet.Add($siteKey.Trim())
    }
    if ($postColdSnapshot) {
        foreach ($site in Get-SitesFromSnapshot -Snapshot $postColdSnapshot) {
            if ([string]::IsNullOrWhiteSpace($site)) { continue }
            [void]$warmRunSiteSet.Add($site.Trim())
        }
    }
    if ($warmRunSiteSet.Count -eq 0 -and $ingestionHistorySnapshot) {
        foreach ($site in Get-SitesFromSnapshot -Snapshot $ingestionHistorySnapshot) {
            if ([string]::IsNullOrWhiteSpace($site)) { continue }
            [void]$warmRunSiteSet.Add($site.Trim())
        }
    }
    if ($warmRunSiteSet.Count -gt 0) {
        $script:WarmRunSites = @($warmRunSiteSet | ForEach-Object { $_ } | Sort-Object)
        Write-Host ("Monitoring warm pass cache state for {0} site(s): {1}" -f $script:WarmRunSites.Count, ([string]::Join(', ', $script:WarmRunSites))) -ForegroundColor DarkCyan
    } else {
        $script:WarmRunSites = @()
        Write-Warning 'No site codes were discovered for warm pass cache monitoring; warm cache assertions may fail.'
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
    $postRestoreSummary = Get-SharedCacheSummary -Label 'SharedCacheState:PostRestore'
    if ($postRestoreSummary) {
        $results += $postRestoreSummary
    }
    if ($script:WarmRunSites -and $script:WarmRunSites.Count -gt 0) {
        Write-Host ("Preparing cache state check for sites: {0}" -f ([string]::Join(', ', $script:WarmRunSites))) -ForegroundColor DarkCyan
        Write-Host 'Recording site cache state before warm pass...' -ForegroundColor Cyan
        $preWarmSummary = Get-SharedCacheSummary -Label 'SharedCacheState:PreWarmPass'
        if ($preWarmSummary) {
            $results += $preWarmSummary
        }
        $cacheStatePreWarm = Get-SiteCacheState -Sites $script:WarmRunSites -Label 'CacheState:PreWarmPass'
        if ($cacheStatePreWarm) {
            $count = ($cacheStatePreWarm | Measure-Object).Count
            Write-Host ("Cache state entries before warm pass: {0}" -f $count) -ForegroundColor DarkCyan
            if ($count -gt 0) {
                Write-Host ("  -> {0}" -f (($cacheStatePreWarm | ForEach-Object { '{0}:{1}' -f $_.Site, $_.CacheStatus }) -join ', ')) -ForegroundColor DarkCyan
            }
            $results += @($cacheStatePreWarm)
        }

        try {
            $preWarmEntries = Get-SharedCacheEntriesSnapshot -FallbackSites $script:WarmRunSites
            if ($preWarmEntries -and $preWarmEntries.Count -gt 0) {
                $hostSummary = ($preWarmEntries | Sort-Object Site | ForEach-Object {
                        $entryValue = if ($_.Entry) { $_.Entry } else { $_ }
                        $hostCount = 0
                        $rowCount = 0
                        if ($entryValue.HostMap -is [System.Collections.IDictionary]) {
                            $hostCount = $entryValue.HostMap.Count
                            foreach ($m in @($entryValue.HostMap.Values)) {
                                if ($m -is [System.Collections.IDictionary]) { $rowCount += $m.Count }
                            }
                        } elseif ($entryValue.PSObject.Properties.Name -contains 'HostCount') {
                            try { $hostCount = [int]$entryValue.HostCount } catch { }
                        }
                        if ($entryValue.PSObject.Properties.Name -contains 'TotalRows' -and $rowCount -eq 0) {
                            try { $rowCount = [int]$entryValue.TotalRows } catch { }
                        }
                        '{0}:hosts={1},rows={2}' -f $_.Site, $hostCount, $rowCount
                    }) -join '; '
                Write-Host ("Shared cache entries before warm pass: {0}" -f $hostSummary) -ForegroundColor DarkCyan
            } else {
                Write-Host 'Shared cache entries before warm pass: none captured.' -ForegroundColor DarkYellow
            }
        } catch {
            Write-Warning ("Failed to summarize shared cache entries before warm pass: {0}" -f $_.Exception.Message)
        }
    }

    try {
        $runspaceSharedCache = ParserRunspaceModule\Get-RunspaceSharedCacheSummary
        if ($runspaceSharedCache -and $runspaceSharedCache.Count -gt 0) {
            $runspaceSharedCache = $runspaceSharedCache | ForEach-Object {
                $_ | Add-Member -NotePropertyName 'PassLabel' -NotePropertyValue 'SharedCacheState:PreservedRunspace' -PassThru
            }
            $results += @($runspaceSharedCache)
            $runspaceSharedText = ($runspaceSharedCache | Sort-Object Site | ForEach-Object { '{0}:hosts={1},rows={2}' -f $_.Site, $_.HostCount, $_.TotalRows }) -join '; '
            Write-Host ("Preserved runspace shared cache store: {0}" -f $runspaceSharedText) -ForegroundColor DarkCyan
        } else {
            Write-Host 'Preserved runspace shared cache store: empty or unavailable.' -ForegroundColor DarkYellow
        }
    } catch {
        Write-Warning ("Failed to capture preserved runspace shared cache state: {0}" -f $_.Exception.Message)
    }
    Write-SharedCacheSnapshot -Label 'PreWarmPass'
    if ($sharedCacheSnapshotPath) {
        $pipelineArguments['SharedCacheSnapshotPath'] = $sharedCacheSnapshotPath
    }
    try {
        if ($sharedCacheEntries -and $sharedCacheEntries.Count -gt 0) {
            try {
                $store = $null
                try { $store = DeviceRepositoryModule\Get-SharedSiteInterfaceCacheStore } catch { $store = $null }
                if ($store -is [System.Collections.IDictionary]) {
                    foreach ($entry in @($sharedCacheEntries)) {
                        if (-not $entry) { continue }
                        $siteKey = ''
                        if ($entry.PSObject.Properties.Name -contains 'Site') { $siteKey = ('' + $entry.Site).Trim() }
                        elseif ($entry.PSObject.Properties.Name -contains 'SiteKey') { $siteKey = ('' + $entry.SiteKey).Trim() }
                        if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }
                        $payload = $entry
                        if ($entry.PSObject.Properties.Name -contains 'Entry') { $payload = $entry.Entry }
                        if (-not $payload) { continue }
                        try { DeviceRepositoryModule\Set-SharedSiteInterfaceCacheEntry -SiteKey $siteKey -Entry $payload } catch { }
                    }
                    try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetStore($store) } catch { }
                }
            } catch { }

            ParserRunspaceModule\Set-RunspaceSharedCacheEntries -Entries $sharedCacheEntries
            Write-Host ("Seeded preserved runspace shared cache with {0} entr{1}." -f $sharedCacheEntries.Count, $(if ($sharedCacheEntries.Count -eq 1) { 'y' } else { 'ies' })) -ForegroundColor DarkCyan
            $postSeedSummary = ParserRunspaceModule\Get-RunspaceSharedCacheSummary
            if ($postSeedSummary -and $postSeedSummary.Count -gt 0) {
                $postSeedText = ($postSeedSummary | Sort-Object Site | ForEach-Object { '{0}:hosts={1},rows={2}' -f $_.Site, $_.HostCount, $_.TotalRows }) -join '; '
                Write-Host ("Preserved runspace shared cache after seeding: {0}" -f $postSeedText) -ForegroundColor DarkCyan
                $results += @($postSeedSummary | ForEach-Object { $_ | Add-Member -NotePropertyName 'PassLabel' -NotePropertyValue 'SharedCacheState:PreservedRunspacePostSeed' -PassThru })
            } else {
                Write-Host 'Preserved runspace shared cache after seeding: empty or unavailable.' -ForegroundColor DarkYellow
            }
        } else {
            Write-Host 'No shared cache entries available to seed into preserved runspace pool.' -ForegroundColor DarkYellow
        }
    } catch {
        Write-Warning ("Failed to seed preserved runspace shared cache: {0}" -f $_.Exception.Message)
    }
    $results += Invoke-PipelinePass -Label 'WarmPass'
} finally {
    Write-Host 'Restoring ingestion history to original snapshot...' -ForegroundColor Yellow
    Restore-IngestionHistory -Snapshot $ingestionHistorySnapshot
    try { ParserRunspaceModule\Reset-DeviceParseRunspacePool } catch { }
    if ($pipelineArguments.ContainsKey('SharedCacheSnapshotPath')) {
        $pipelineArguments.Remove('SharedCacheSnapshotPath')
    }
    if ($sharedCacheSnapshotEnvApplied) {
        try {
            if ($null -ne $sharedCacheSnapshotEnvOriginal) {
                $env:STATETRACE_SHARED_CACHE_SNAPSHOT = $sharedCacheSnapshotEnvOriginal
            } else {
                Remove-Item Env:STATETRACE_SHARED_CACHE_SNAPSHOT -ErrorAction SilentlyContinue
            }
        } catch { }
        $sharedCacheSnapshotEnvApplied = $false
    }
    if (-not $PreserveSharedCacheSnapshot.IsPresent -and $sharedCacheSnapshotPath -and (Test-Path -LiteralPath $sharedCacheSnapshotPath)) {
        try { Remove-Item -LiteralPath $sharedCacheSnapshotPath -Force } catch { }
    } elseif ($PreserveSharedCacheSnapshot.IsPresent -and $sharedCacheSnapshotPath) {
        Write-Host ("Preserved shared cache snapshot at '{0}' for inspection." -f $sharedCacheSnapshotPath) -ForegroundColor DarkCyan
    }
    if (-not $PreserveSkipSiteCacheSetting.IsPresent -and $skipSiteCacheGuard) {
        Restore-SkipSiteCacheUpdateSetting -Guard $skipSiteCacheGuard
    }
}

$comparisonSummary = $null
$coldMetrics = $null
$warmMetrics = $null
$coldSummaries = @()
$warmSummaries = @()
if ($script:PassInterfaceAnalysis.ContainsKey('ColdPass')) {
    $coldMetrics = $script:PassInterfaceAnalysis['ColdPass']
}
if ($script:PassInterfaceAnalysis.ContainsKey('WarmPass')) {
    $warmMetrics = $script:PassInterfaceAnalysis['WarmPass']
}
if ($script:PassSummaries.ContainsKey('ColdPass')) {
    $coldSummaries = @($script:PassSummaries['ColdPass'])
}
if ($script:PassSummaries.ContainsKey('WarmPass')) {
    $warmSummaries = @($script:PassSummaries['WarmPass'])
}

$warmPassHostnames = $null
if ($script:PassHostnames.ContainsKey('WarmPass')) {
    $warmPassHostnames = $script:PassHostnames['WarmPass']
}
$coldPassHostnames = $null
if ($script:PassHostnames.ContainsKey('ColdPass')) {
    $coldPassHostnames = $script:PassHostnames['ColdPass']
}

$hostFilterApplied = ($script:ComparisonHostFilter -and $script:ComparisonHostFilter.Count -gt 0) -or $RestrictWarmComparisonToColdHosts.IsPresent

if (($coldMetrics -or $coldSummaries) -and ($warmMetrics -or $warmSummaries)) {
    $normalizedWarmProviderCounts = @{}
    $normalizedColdProviderCounts = @{}
    $warmCountSource = 0
    $coldCountSource = 0

    if ($warmMetrics) {
        $normalizedWarmProviderCounts = ConvertTo-NormalizedProviderCounts -ProviderCounts $warmMetrics.ProviderCounts
        if ($warmPassHostnames -and $warmPassHostnames.Count -gt 0) {
            $warmCountSource = $warmPassHostnames.Count
        } else {
            $warmCountSource = $warmMetrics.Count
        }
    } elseif ($warmPassHostnames -and $warmPassHostnames.Count -gt 0) {
        $warmCountSource = $warmPassHostnames.Count
    }
    if ($coldMetrics) {
        $normalizedColdProviderCounts = ConvertTo-NormalizedProviderCounts -ProviderCounts $coldMetrics.ProviderCounts
        if ($coldPassHostnames -and $coldPassHostnames.Count -gt 0) {
            $coldCountSource = $coldPassHostnames.Count
        } else {
            $coldCountSource = $coldMetrics.Count
        }
    } elseif ($coldPassHostnames -and $coldPassHostnames.Count -gt 0) {
        $coldCountSource = $coldPassHostnames.Count
    }
    if ($coldCountSource -le 0 -and $hostFilterApplied -and $script:ComparisonHostFilter -and $script:ComparisonHostFilter.Count -gt 0) {
        $coldCountSource = $script:ComparisonHostFilter.Count
    }
    if ($warmCountSource -le 0 -and $hostFilterApplied -and $script:ComparisonHostFilter -and $script:ComparisonHostFilter.Count -gt 0) {
        $warmCountSource = $script:ComparisonHostFilter.Count
    }

    $warmCacheProviderHitCountRaw = 0
    if ($normalizedWarmProviderCounts.ContainsKey('Cache')) {
        $warmCacheProviderHitCountRaw = [int]$normalizedWarmProviderCounts['Cache']
    }

    $warmCacheProviderMissCountRaw = 0
    foreach ($entry in $normalizedWarmProviderCounts.GetEnumerator()) {
        if ($entry.Key -ne 'Cache') {
            $warmCacheProviderMissCountRaw += [int]$entry.Value
        }
    }

    $warmCacheHitRatioPercentRaw = $null
    $warmProviderSamples = $warmCacheProviderHitCountRaw + $warmCacheProviderMissCountRaw
    if ($warmProviderSamples -gt 0) {
        $warmCacheHitRatioPercentRaw = [math]::Round(($warmCacheProviderHitCountRaw / $warmProviderSamples) * 100, 2)
    } elseif ($warmCountSource -gt 0) {
        $warmCacheHitRatioPercentRaw = [math]::Round(($warmCacheProviderHitCountRaw / $warmCountSource) * 100, 2)
    }

    $warmProviderCounts = $normalizedWarmProviderCounts
    $warmCacheProviderHitCount = $warmCacheProviderHitCountRaw
    $warmCacheProviderMissCount = $warmCacheProviderMissCountRaw
    $warmCacheHitRatioPercent = $warmCacheHitRatioPercentRaw

    $warmSummaryMetrics = Measure-ProviderMetricsFromSummaries -Summaries $warmSummaries
    if (-not $hostFilterApplied -and $warmSummaryMetrics) {
        $warmProviderCounts = $warmSummaryMetrics.ProviderCounts
        $warmCacheProviderHitCount = [int]$warmSummaryMetrics.HitCount
        $warmCacheProviderMissCount = [int]$warmSummaryMetrics.MissCount
        $warmCacheHitRatioPercent = $warmSummaryMetrics.HitRatio
        if ($warmSummaryMetrics.TotalWeight -gt 0) {
            $warmCountSource = $warmSummaryMetrics.TotalWeight
        } elseif ($warmPassHostnames -and $warmPassHostnames.Count -gt 0) {
            $warmCountSource = $warmPassHostnames.Count
        }
        # Prefer summary-derived provider counts for normalized/raw reporting when breakdown events are sparse.
        $normalizedWarmProviderCounts = $warmProviderCounts
        $warmCacheProviderHitCountRaw = 0
        if ($normalizedWarmProviderCounts.ContainsKey('Cache')) {
            $warmCacheProviderHitCountRaw = [int]$normalizedWarmProviderCounts['Cache']
        }

        $warmCacheProviderMissCountRaw = 0
        foreach ($entry in $normalizedWarmProviderCounts.GetEnumerator()) {
            if ($entry.Key -ne 'Cache') {
                $warmCacheProviderMissCountRaw += [int]$entry.Value
            }
        }
        $warmCacheHitRatioPercentRaw = $null
        $warmProviderSamples = $warmCacheProviderHitCountRaw + $warmCacheProviderMissCountRaw
        if ($warmProviderSamples -gt 0) {
            $warmCacheHitRatioPercentRaw = [math]::Round(($warmCacheProviderHitCountRaw / $warmProviderSamples) * 100, 2)
        } elseif ($warmCountSource -gt 0) {
            $warmCacheHitRatioPercentRaw = [math]::Round(($warmCacheProviderHitCountRaw / $warmCountSource) * 100, 2)
        }
    }

    $coldProviderCounts = $normalizedColdProviderCounts
    $coldSummaryMetrics = Measure-ProviderMetricsFromSummaries -Summaries $coldSummaries
    if (-not $hostFilterApplied -and $coldSummaryMetrics) {
        $coldProviderCounts = $coldSummaryMetrics.ProviderCounts
        if ($coldSummaryMetrics.TotalWeight -gt 0) {
            $coldCountSource = $coldSummaryMetrics.TotalWeight
        } elseif ($coldPassHostnames -and $coldPassHostnames.Count -gt 0) {
            $coldCountSource = $coldPassHostnames.Count
        }
        # Prefer summary-derived provider counts when breakdown events are sparse.
        $normalizedColdProviderCounts = $coldProviderCounts
    }

    $warmSignatureRewriteTotal = 0
    $warmSignatureMatchMissCount = 0
    if ($warmMetrics -and $warmMetrics.Events) {
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
    } elseif ($warmSummaries) {
        foreach ($summary in @($warmSummaries)) {
            if (-not $summary) { continue }
            $matchCount = 0
            if ($summary.PSObject.Properties.Name -contains 'HostMapSignatureMatchCount') {
                try { $matchCount = [int]$summary.HostMapSignatureMatchCount } catch { $matchCount = 0 }
            }
            if ($matchCount -le 0) {
                $warmSignatureMatchMissCount++
            }

            if ($summary.PSObject.Properties.Name -contains 'HostMapSignatureRewriteCount') {
                try { $warmSignatureRewriteTotal += [int]$summary.HostMapSignatureRewriteCount } catch { }
            }
        }
    }

    $improvementMs = $null
    if ($coldMetrics -and $warmMetrics -and $coldMetrics.AverageRaw -ne $null -and $warmMetrics.AverageRaw -ne $null) {
        $improvementMs = [math]::Round($coldMetrics.AverageRaw - $warmMetrics.AverageRaw, 3)
    }

    $improvementPercent = $null
    if ($improvementMs -ne $null -and $coldMetrics -and $coldMetrics.AverageRaw -gt 0) {
        $improvementPercent = [math]::Round(($improvementMs / $coldMetrics.AverageRaw) * 100, 2)
    }

    $comparisonSummary = [pscustomobject]@{
        PassLabel                      = 'WarmRunComparison'
        SummaryType                    = 'InterfaceCallDuration'
        ColdHostCount                  = $coldCountSource
        ColdInterfaceCallAvgMs         = if ($coldMetrics) { $coldMetrics.Average } else { $null }
        ColdInterfaceCallP95Ms         = if ($coldMetrics) { $coldMetrics.P95 } else { $null }
        ColdInterfaceCallMaxMs         = if ($coldMetrics) { $coldMetrics.Max } else { $null }
        WarmHostCount                  = $warmCountSource
        WarmInterfaceCallAvgMs         = if ($warmMetrics) { $warmMetrics.Average } else { $null }
        WarmInterfaceCallP95Ms         = if ($warmMetrics) { $warmMetrics.P95 } else { $null }
        WarmInterfaceCallMaxMs         = if ($warmMetrics) { $warmMetrics.Max } else { $null }
        ImprovementAverageMs           = $improvementMs
        ImprovementPercent             = $improvementPercent
        WarmCacheProviderHitCount      = $warmCacheProviderHitCount
        WarmCacheProviderHitCountRaw   = $warmCacheProviderHitCountRaw
        WarmCacheProviderMissCount     = $warmCacheProviderMissCount
        WarmCacheProviderMissCountRaw  = $warmCacheProviderMissCountRaw
        WarmCacheHitRatioPercent       = $warmCacheHitRatioPercent
        WarmCacheHitRatioPercentRaw    = $warmCacheHitRatioPercentRaw
        WarmSignatureMatchMissCount    = $warmSignatureMatchMissCount
        WarmSignatureRewriteTotal      = $warmSignatureRewriteTotal
        WarmProviderCounts             = $warmProviderCounts
        WarmProviderCountsRaw          = $normalizedWarmProviderCounts
        WarmInterfaceMetrics           = $warmMetrics
        ColdInterfaceMetrics           = $coldMetrics
        ColdProviderCounts             = $coldProviderCounts
        ColdProviderCountsRaw          = $normalizedColdProviderCounts
    }

    $results += $comparisonSummary
}

if ($AssertWarmCache.IsPresent -and -not $SkipWarmValidation.IsPresent) {
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

# Final hostname guard for exported results to keep payloads aligned with the active filters.
function Get-PassHostnameFilter {
    param([string]$Label)

    $filter = $script:ComparisonHostFilter
    if ($RestrictWarmComparisonToColdHosts.IsPresent -and $Label -eq 'WarmPass' -and $script:ColdPassHostnames -and $script:ColdPassHostnames.Count -gt 0) {
        $filter = $script:ColdPassHostnames
    }
    return $filter
}

if ($script:ComparisonHostFilter -and $script:ComparisonHostFilter.Count -gt 0) {
    $filteredResults = New-Object 'System.Collections.Generic.List[psobject]'
    foreach ($result in @($results)) {
        if ($result.PSObject.Properties.Name -contains 'SummaryType' -and $result.SummaryType) {
            $filteredResults.Add($result) | Out-Null
            continue
        }

        $passLabel = $result.PassLabel
        $allowedHosts = Get-PassHostnameFilter -Label $passLabel
        if (-not $allowedHosts -or $allowedHosts.Count -le 0) {
            $filteredResults.Add($result) | Out-Null
            continue
        }

        $hostnameValue = $null
        if ($result.PSObject.Properties.Name -contains 'Hostname') {
            $hostnameValue = $result.Hostname
        }

        if ([string]::IsNullOrWhiteSpace($hostnameValue)) {
            # Retain hostless rows so cold metrics are not dropped entirely when filtered logs omit hostnames.
            $filteredResults.Add($result) | Out-Null
            continue
        }

        if ($allowedHosts.Contains(('' + $hostnameValue).Trim())) {
            $filteredResults.Add($result) | Out-Null
        }
    }
    $results = @($filteredResults)
}

function Update-ComparisonSummaryFromResults {
    param(
        [System.Collections.IEnumerable]$Items
    )

    $itemsArray = @($Items)
    if (-not $itemsArray) { return $Items }

    $comparison = $itemsArray | Where-Object { $_.PSObject -and $_.PSObject.Properties.Name -contains 'SummaryType' -and $_.SummaryType -eq 'InterfaceCallDuration' } | Select-Object -First 1
    if (-not $comparison) { return $Items }

    $originalColdHostCount = $comparison.ColdHostCount
    $originalWarmHostCount = $comparison.WarmHostCount

    $warmEvents = @($itemsArray | Where-Object { $_.PSObject -and $_.PSObject.Properties.Name -contains 'PassLabel' -and $_.PassLabel -eq 'WarmPass' -and -not ($_.PSObject.Properties.Name -contains 'SummaryType' -and $_.SummaryType) })
    $coldEvents = @($itemsArray | Where-Object { $_.PSObject -and $_.PSObject.Properties.Name -contains 'PassLabel' -and $_.PassLabel -eq 'ColdPass' -and -not ($_.PSObject.Properties.Name -contains 'SummaryType' -and $_.SummaryType) })

    function Get-ProviderSnapshot {
        param([System.Collections.IEnumerable]$Events)
        $providerCounts = @{}
        $hostSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $durations = New-Object 'System.Collections.Generic.List[double]'
        $signatureMisses = 0

        foreach ($evt in @($Events)) {
            if (-not $evt) { continue }
            $provider = '' + ($evt.Provider)
            if ([string]::IsNullOrWhiteSpace($provider) -and $evt.PSObject.Properties.Name -contains 'SiteCacheProvider') {
                $provider = '' + $evt.SiteCacheProvider
            }
            if ([string]::IsNullOrWhiteSpace($provider)) {
                $provider = 'Unknown'
            }
            if ($providerCounts.ContainsKey($provider)) {
                $providerCounts[$provider]++
            } else {
                $providerCounts[$provider] = 1
            }

            if ($evt.PSObject.Properties.Name -contains 'Hostname' -and -not [string]::IsNullOrWhiteSpace($evt.Hostname)) {
                [void]$hostSet.Add(($evt.Hostname).Trim())
            }

            if ($evt.PSObject.Properties.Name -contains 'InterfaceCallDurationMs') {
                $val = $evt.InterfaceCallDurationMs
                if ($null -ne $val) {
                    try { [void]$durations.Add([double]$val) } catch { }
                }
            }

            if ($evt.PSObject.Properties.Name -contains 'SiteCacheHostMapSignatureMatchCount') {
                try {
                    $matchCount = [int]$evt.SiteCacheHostMapSignatureMatchCount
                    if ($matchCount -le 0) { $signatureMisses++ }
                } catch { $signatureMisses++ }
            }
        }

        return [pscustomobject]@{
            Providers       = $providerCounts
            HostCount       = $hostSet.Count
            Durations       = $durations.ToArray()
            SignatureMisses = $signatureMisses
        }
    }

    $warmSnapshot = Get-ProviderSnapshot -Events $warmEvents
    $coldSnapshot = Get-ProviderSnapshot -Events $coldEvents

    if ($warmSnapshot) {
        $comparison.WarmProviderCounts = $warmSnapshot.Providers
        $comparison.WarmProviderCountsRaw = $warmSnapshot.Providers
        $hitCount = 0
        if ($warmSnapshot.Providers.ContainsKey('Cache')) { $hitCount = [int]$warmSnapshot.Providers['Cache'] }
        $missCount = 0
        foreach ($entry in $warmSnapshot.Providers.GetEnumerator()) {
            if ($entry.Key -ne 'Cache') { $missCount += [int]$entry.Value }
        }
        $totalProviders = $hitCount + $missCount
        $hitRatio = $null
        if ($totalProviders -gt 0) { $hitRatio = [math]::Round(($hitCount / $totalProviders) * 100, 2) }

        $comparison.WarmCacheProviderHitCount = $hitCount
        $comparison.WarmCacheProviderHitCountRaw = $hitCount
        $comparison.WarmCacheProviderMissCount = $missCount
        $comparison.WarmCacheProviderMissCountRaw = $missCount
        $comparison.WarmCacheHitRatioPercent = $hitRatio
        $comparison.WarmCacheHitRatioPercentRaw = $hitRatio
        $comparison.WarmHostCount = $warmSnapshot.HostCount
        $comparison.WarmSignatureMatchMissCount = $warmSnapshot.SignatureMisses

        if ($warmSnapshot.Durations.Length -gt 0) {
            $comparison.WarmInterfaceCallAvgMs = [math]::Round(($warmSnapshot.Durations | Measure-Object -Average).Average, 3)
            $comparison.WarmInterfaceCallMaxMs = [math]::Round(($warmSnapshot.Durations | Measure-Object -Maximum).Maximum, 3)
            $comparison.WarmInterfaceCallP95Ms = [math]::Round((Get-PercentileValue -Values $warmSnapshot.Durations -Percentile 95), 3)
        }
    }

    if ($coldSnapshot) {
        $comparison.ColdProviderCounts = $coldSnapshot.Providers
        $comparison.ColdProviderCountsRaw = $coldSnapshot.Providers
        $comparison.ColdHostCount = $coldSnapshot.HostCount

        if ($coldSnapshot.Durations.Length -gt 0) {
            $comparison.ColdInterfaceCallAvgMs = [math]::Round(($coldSnapshot.Durations | Measure-Object -Average).Average, 3)
            $comparison.ColdInterfaceCallMaxMs = [math]::Round(($coldSnapshot.Durations | Measure-Object -Maximum).Maximum, 3)
            $comparison.ColdInterfaceCallP95Ms = [math]::Round((Get-PercentileValue -Values $coldSnapshot.Durations -Percentile 95), 3)
        }
    }

    if ($comparison.WarmHostCount -le 0 -and $originalWarmHostCount -gt 0) {
        $comparison.WarmHostCount = $originalWarmHostCount
    }
    if ($comparison.ColdHostCount -le 0 -and $originalColdHostCount -gt 0) {
        $comparison.ColdHostCount = $originalColdHostCount
    }

    if ($comparison.ColdInterfaceCallAvgMs -ne $null -and $comparison.WarmInterfaceCallAvgMs -ne $null) {
        $comparison.ImprovementAverageMs = [math]::Round($comparison.ColdInterfaceCallAvgMs - $comparison.WarmInterfaceCallAvgMs, 3)
        if ($comparison.ColdInterfaceCallAvgMs -gt 0) {
            $comparison.ImprovementPercent = [math]::Round(($comparison.ImprovementAverageMs / $comparison.ColdInterfaceCallAvgMs) * 100, 2)
        }
    }

    return $itemsArray
}

$results = Update-ComparisonSummaryFromResults -Items $results

if ($OutputPath) {
    $totalResultCount = ($results | Measure-Object).Count
    Write-Host ("Result count prior to export: {0}" -f $totalResultCount) -ForegroundColor Yellow
    $directory = Split-Path -Path $OutputPath -Parent
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $exportPayload = $results | Select-Object `
        PassLabel,
        SummaryType,
        Site,
        Hostname,
        Timestamp,
        CacheStatus,
        Provider,
        SiteCacheProviderReason,
        HydrationDurationMs,
        SnapshotDurationMs,
        HostMapDurationMs,
        HostCount,
        TotalRows,
        HostMapSignatureMatchCount,
        HostMapSignatureRewriteCount,
        HostMapCandidateMissingCount,
        HostMapCandidateFromPrevious,
        PreviousHostCount,
        PreviousSnapshotStatus,
        PreviousSnapshotHostMapType,
        EntryCount,
        RestoredCount,
        SourceStage,
        ColdHostCount,
        WarmHostCount,
        ColdInterfaceCallAvgMs,
        ColdInterfaceCallP95Ms,
        ColdInterfaceCallMaxMs,
        WarmInterfaceCallAvgMs,
        WarmInterfaceCallP95Ms,
        WarmInterfaceCallMaxMs,
        ImprovementAverageMs,
        ImprovementPercent,
        WarmCacheProviderHitCount,
        WarmCacheProviderHitCountRaw,
        WarmCacheProviderMissCount,
        WarmCacheProviderMissCountRaw,
        WarmCacheHitRatioPercent,
        WarmCacheHitRatioPercentRaw,
        WarmSignatureMatchMissCount,
        WarmSignatureRewriteTotal,
        WarmProviderCounts,
        WarmProviderCountsRaw,
        ColdProviderCounts,
        ColdProviderCountsRaw,
        ScriptCacheCount,
        ScriptCacheSites,
        DomainCacheCount,
        DomainCacheSites,
        InterfaceCallDurationMs,
        DatabaseWriteLatencyMs,
        DiffComparisonDurationMs,
        DiffDurationMs,
        LoadExistingDurationMs,
        LoadExistingRowSetCount,
        LoadSignatureDurationMs,
        LoadCacheHit,
        LoadCacheMiss,
        LoadCacheRefreshed,
        CachedRowCount,
        CachePrimedRowCount,
        RowsStaged,
        InsertCandidates,
        UpdateCandidates,
        DeleteCandidates,
        DiffRowsCompared,
        DiffRowsChanged,
        DiffRowsInserted,
        DiffRowsUnchanged,
        DiffSeenPorts,
        DiffDuplicatePorts,
        UiCloneDurationMs,
        DeleteDurationMs,
        FallbackDurationMs,
        FallbackUsed,
        FactsConsidered,
        ExistingCount
    $json = $exportPayload | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($OutputPath, $json)
    Write-Host "Warm-run telemetry summary exported to $OutputPath" -ForegroundColor Green

    if ($shouldGenerateDiffHotspots) {
        if (-not (Test-Path -LiteralPath $OutputPath)) {
            Write-Warning 'Unable to generate diff hotspot report because the warm-run telemetry file does not exist.'
        } else {
            $analyzerScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Analyze-WarmRunDiffHotspots.ps1'
            if (-not (Test-Path -LiteralPath $analyzerScript)) {
                throw "Diff hotspot analyzer script not found at '$analyzerScript'."
            }

            $targetDiffPath = $DiffHotspotOutputPath
            if ([string]::IsNullOrWhiteSpace($targetDiffPath)) {
                $diffDir = Split-Path -Path $OutputPath -Parent
                if ([string]::IsNullOrWhiteSpace($diffDir)) {
                    $diffDir = Join-Path -Path $repositoryRoot -ChildPath 'Logs\IngestionMetrics'
                }
                $leafName = Split-Path -Path $OutputPath -Leaf
                $match = [System.Text.RegularExpressions.Regex]::Match($leafName, 'WarmRunTelemetry-(?<ts>\d{8}-\d{6})\.json', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                $timestamp = if ($match.Success) { $match.Groups['ts'].Value } else { (Get-Date -Format 'yyyyMMdd-HHmmss') }
                $targetDiffPath = Join-Path -Path $diffDir -ChildPath ("DiffHotspots-{0}.csv" -f $timestamp)
            } else {
                try {
                    $targetDiffPath = (Resolve-Path -LiteralPath $targetDiffPath -ErrorAction Stop).Path
                } catch {
                    $targetDiffPath = $DiffHotspotOutputPath
                }
            }

            $diffDirEnsure = Split-Path -Path $targetDiffPath -Parent
            if ($diffDirEnsure -and -not (Test-Path -LiteralPath $diffDirEnsure)) {
                New-Item -ItemType Directory -Path $diffDirEnsure -Force | Out-Null
            }

            try {
                & $analyzerScript -TelemetryPath $OutputPath -Top $DiffHotspotTop -OutputPath $targetDiffPath
                if ($LASTEXITCODE -ne 0) {
                    throw "Analyze-WarmRunDiffHotspots exited with code $LASTEXITCODE."
                }
                Write-Host ("Diff hotspot report exported to {0}" -f $targetDiffPath) -ForegroundColor Green
            } catch {
                throw ("Failed to generate diff hotspot report: {0}" -f $_.Exception.Message)
            }
        }
    }
}

try {
    if ($null -ne $originalSiteExistingRowCacheSnapshotEnv) {
        $env:STATETRACE_SITE_EXISTING_ROW_CACHE_SNAPSHOT = $originalSiteExistingRowCacheSnapshotEnv
    } else {
        Remove-Item Env:STATETRACE_SITE_EXISTING_ROW_CACHE_SNAPSHOT -ErrorAction SilentlyContinue
    }
} catch { }

$results


