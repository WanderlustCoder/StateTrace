[CmdletBinding()]
param(
    [switch]$IncludeTests,
    [switch]$VerboseParsing,
    [switch]$UseBalancedHostOrder,
    [switch]$ResetExtractedLogs,
    [switch]$SkipSchedulerFairnessGuard,
    [string]$OutputPath,
    [int]$PortBatchMaxConsecutiveOverride,
    [switch]$SkipWarmValidation,
    [ValidateSet('Empty','Snapshot')]
    [string]$ColdHistorySeed = 'Snapshot',
    [ValidateSet('Empty','Snapshot','ColdOutput','WarmBackup')]
    [string]$WarmHistorySeed = 'Empty',
    [switch]$RefreshSiteCaches,
    [switch]$AssertWarmCache,
    [switch]$PreserveSkipSiteCacheSetting,
    [switch]$SkipPortDiversityGuard,
    [switch]$ForcePortBatchReadySynthesis,
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
    [switch]$GenerateSharedCacheDiagnostics,
    [int]$SharedCacheDiagnosticsTopHosts = 10,
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

$statisticsModulePath = Join-Path -Path $repositoryRoot -ChildPath 'Modules\StatisticsModule.psm1'
if (-not (Test-Path -LiteralPath $statisticsModulePath)) {
    throw "StatisticsModule not found at $statisticsModulePath"
}
Import-Module -Name $statisticsModulePath -Force -ErrorAction Stop

$warmRunTelemetryModulePath = Join-Path -Path $repositoryRoot -ChildPath 'Modules\WarmRun.Telemetry.psm1'
if (-not (Test-Path -LiteralPath $warmRunTelemetryModulePath)) {
    throw "WarmRun.Telemetry module not found at $warmRunTelemetryModulePath"
}
Import-Module -Name $warmRunTelemetryModulePath -Force -ErrorAction Stop

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
$sharedCacheDisableEnvOriginal = $null
$sharedCacheDisableEnvApplied = $false

$script:PassInterfaceAnalysis = @{}
$script:PassSummaries = @{}
$script:PassHostnames = @{}
$script:PassWindows = @{}
$script:ColdPassHostnames = $null

if (-not $SiteExistingRowCacheSnapshotPath) {
    $SiteExistingRowCacheSnapshotPath = Join-Path -Path (Join-Path $repositoryRoot 'Logs') -ChildPath ("SiteExistingRowCacheSnapshot-{0:yyyyMMdd-HHmmss}.clixml" -f (Get-Date))
}

$shouldGenerateDiffHotspots = $GenerateDiffHotspotReport.IsPresent -or -not [string]::IsNullOrWhiteSpace($DiffHotspotOutputPath)
$shouldGenerateSharedCacheDiagnostics = $GenerateSharedCacheDiagnostics.IsPresent

if ($shouldGenerateSharedCacheDiagnostics -and -not $PSBoundParameters.ContainsKey('ColdHistorySeed') -and $ColdHistorySeed -eq 'Snapshot') {
    Write-Host 'Shared cache diagnostics requested; forcing ColdHistorySeed=Empty to ensure cold-pass parse telemetry.' -ForegroundColor DarkYellow
    $ColdHistorySeed = 'Empty'
}

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

function Get-DeviceRepositoryModule {
    $module = Get-Module -Name 'DeviceRepositoryModule' -ErrorAction SilentlyContinue
    if ($module) { return $module }

    $modulePath = Join-Path -Path $repositoryRoot -ChildPath 'Modules\DeviceRepositoryModule.psm1'
    if (Test-Path -LiteralPath $modulePath) {
        try {
            return Import-Module -Name $modulePath -PassThru -ErrorAction SilentlyContinue
        } catch {
            Write-Verbose ("Unable to import DeviceRepositoryModule: {0}" -f $_.Exception.Message) -Verbose:$VerboseParsing
        }
    }

    return $null
}

function Get-DeviceRepositoryCacheCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    $cmd = $null
    $qualifiedName = 'DeviceRepository.Cache\{0}' -f $Name
    try { $cmd = Get-Command -Name $qualifiedName -ErrorAction SilentlyContinue } catch { $cmd = $null }
    if (-not $cmd) {
        try { $cmd = Get-Command -Name $Name -Module 'DeviceRepository.Cache' -ErrorAction SilentlyContinue } catch { $cmd = $null }
    }
    return $cmd
}

function Get-TelemetryModuleCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    $cmd = $null
    $qualifiedName = 'TelemetryModule\{0}' -f $Name
    try { $cmd = Get-Command -Name $qualifiedName -ErrorAction SilentlyContinue } catch { $cmd = $null }
    if (-not $cmd) {
        try { $cmd = Get-Command -Name $Name -Module 'TelemetryModule' -ErrorAction SilentlyContinue } catch { $cmd = $null }
    }
    return $cmd
}

function Get-NonNullItemCount {
    param([object]$Items)

    if ($null -eq $Items) { return 0 }
    if ($Items -is [string]) { return 1 }

    if ($Items -is [System.Collections.IEnumerable]) {
        $count = 0
        foreach ($item in $Items) {
            if ($null -ne $item) {
                $count++
            }
        }
        return $count
    }

    return 1
}

function Get-FileLineCount {
    param([Parameter(Mandatory)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return 0
    }

    $count = 0
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        $count++
    }
    return $count
}

function Get-FirstItems {
    param(
        [System.Collections.IEnumerable]$Items,
        [int]$Count = 10
    )

    if (-not $Items -or $Count -le 0) { return @() }

    $preview = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Items) {
        if ($preview.Count -ge $Count) { break }
        [void]$preview.Add($item)
    }

    return $preview.ToArray()
}

function Initialize-Directory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }

    if (-not (Test-Path -LiteralPath $Path)) {
        $null = New-Item -ItemType Directory -Path $Path -Force
    }

    return $Path
}

function Initialize-DirectoryForPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }

    $directory = $null
    try { $directory = Split-Path -Path $Path -Parent } catch { $directory = $null }
    if ([string]::IsNullOrWhiteSpace($directory)) { return $null }

    $null = Initialize-Directory -Path $directory
    return $directory
}

function Get-TrimmedSiteKey {
    param([object]$InputObject)

    if ($null -eq $InputObject) { return '' }

    $siteProperty = $InputObject.PSObject.Properties['Site']
    if ($siteProperty) {
        return ('' + $siteProperty.Value).Trim()
    }

    $siteKeyProperty = $InputObject.PSObject.Properties['SiteKey']
    if ($siteKeyProperty) {
        return ('' + $siteKeyProperty.Value).Trim()
    }

    return ''
}

function Format-SiteCacheStatusText {
    param([System.Collections.IEnumerable]$CacheStates)

    if (-not $CacheStates) { return '' }

    $items = [System.Collections.Generic.List[string]]::new()
    foreach ($state in $CacheStates) {
        if (-not $state) { continue }
        $site = Get-TrimmedSiteKey -InputObject $state
        if ([string]::IsNullOrWhiteSpace($site)) { continue }
        $cacheStatus = ''
        $cacheStatusProp = $state.PSObject.Properties['CacheStatus']
        if ($cacheStatusProp) { $cacheStatus = ('' + $cacheStatusProp.Value).Trim() }
        if ([string]::IsNullOrWhiteSpace($cacheStatus)) { continue }
        [void]$items.Add(('{0}:{1}' -f $site, $cacheStatus))
    }

    $result = $items.ToArray()
    if ($result.Length -gt 1) {
        [array]::Sort($result, [System.StringComparer]::OrdinalIgnoreCase)
    }
    return [string]::Join(', ', $result)
}

function Format-SharedCacheSummaryText {
    param([System.Collections.IEnumerable]$Entries)

    if (-not $Entries) { return '' }

    $items = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $Entries) {
        if (-not $entry) { continue }

        $site = Get-TrimmedSiteKey -InputObject $entry
        $siteProp = $entry.PSObject.Properties['Site']
        if ([string]::IsNullOrWhiteSpace($site) -and $siteProp) {
            $site = ('' + $siteProp.Value).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($site)) { continue }

        $hostCount = 0
        $totalRows = 0

        $hostCountProp = $entry.PSObject.Properties['HostCount']
        if ($hostCountProp) {
            try { $hostCount = [int]$hostCountProp.Value } catch { $hostCount = 0 }
        }
        $totalRowsProp = $entry.PSObject.Properties['TotalRows']
        if ($totalRowsProp) {
            try { $totalRows = [int]$totalRowsProp.Value } catch { $totalRows = 0 }
        }

        $entryValue = $entry
        $entryValueProp = $entry.PSObject.Properties['Entry']
        if ($entryValueProp -and $entryValueProp.Value) {
            $entryValue = $entryValueProp.Value
        }

        $hostMap = $null
        $hostMapProp = $entryValue.PSObject.Properties['HostMap']
        if ($hostMapProp) { $hostMap = $hostMapProp.Value }
        if (-not $hostMap -and $entryValue -is [System.Collections.IDictionary]) {
            $hostMap = $entryValue
        }

        if ($hostCount -le 0 -and $hostMap -is [System.Collections.IDictionary]) {
            try { $hostCount = [int]$hostMap.Count } catch { $hostCount = 0 }
        } elseif ($hostCount -le 0) {
            $entryHostCountProp = $entryValue.PSObject.Properties['HostCount']
            if ($entryHostCountProp) {
                try { $hostCount = [int]$entryHostCountProp.Value } catch { $hostCount = 0 }
            }
        }

        if ($totalRows -le 0 -and $hostMap -is [System.Collections.IDictionary]) {
            foreach ($map in $hostMap.Values) {
                if ($map -is [System.Collections.IDictionary]) {
                    $totalRows += $map.Count
                } elseif ($map -is [System.Collections.ICollection]) {
                    $totalRows += $map.Count
                }
            }
        } elseif ($totalRows -le 0) {
            $entryTotalRowsProp = $entryValue.PSObject.Properties['TotalRows']
            if ($entryTotalRowsProp) {
                try { $totalRows = [int]$entryTotalRowsProp.Value } catch { $totalRows = 0 }
            }
        }

        [void]$items.Add(('{0}:hosts={1},rows={2}' -f $site, $hostCount, $totalRows))
    }

    $result = $items.ToArray()
    if ($result.Length -gt 1) {
        [array]::Sort($result, [System.StringComparer]::OrdinalIgnoreCase)
    }
    return [string]::Join('; ', $result)
}

function Resolve-CacheProviderMetrics {
    param(
        [Parameter(Mandatory)][hashtable]$ProviderCounts,
        [int]$CountSource = 0
    )

    $hitCount = 0
    foreach ($cacheKey in @('Cache','SharedCache')) {
        if ($ProviderCounts.ContainsKey($cacheKey)) {
            $hitCount += [int]$ProviderCounts[$cacheKey]
        }
    }

    $missCount = 0
    foreach ($entry in $ProviderCounts.GetEnumerator()) {
        if ($entry.Key -ne 'Cache' -and $entry.Key -ne 'SharedCache') {
            $missCount += [int]$entry.Value
        }
    }

    $hitRatioPercent = $null
    $samples = $hitCount + $missCount
    if ($samples -gt 0) {
        $hitRatioPercent = [math]::Round(($hitCount / $samples) * 100, 2)
    } elseif ($CountSource -gt 0) {
        $hitRatioPercent = [math]::Round(($hitCount / $CountSource) * 100, 2)
    }

    return [pscustomobject]@{
        HitCount        = $hitCount
        MissCount       = $missCount
        HitRatioPercent = $hitRatioPercent
    }
}

function Save-SiteExistingRowCacheSnapshot {
    param([string]$SnapshotPath)

    if ([string]::IsNullOrWhiteSpace($SnapshotPath)) { return }
    $module = Get-ParserPersistenceModule
    if (-not $module) { return }

    try {
        $snapshot = ParserPersistenceModule\Get-SiteExistingRowCacheSnapshot
        $entryCount = Get-NonNullItemCount -Items $snapshot
        if ($entryCount -le 0) {
            Write-Verbose 'Site existing row cache snapshot skipped (no entries).' -Verbose:$VerboseParsing
            return
        }
        $null = Initialize-DirectoryForPath -Path $SnapshotPath
        Export-Clixml -InputObject $snapshot -Path $SnapshotPath
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
        $entryCount = Get-NonNullItemCount -Items $snapshot
        if ($entryCount -le 0) {
            Write-Warning ("Site existing row cache snapshot '{0}' did not contain any entries." -f $SnapshotPath)
            return
        }
        ParserPersistenceModule\Set-SiteExistingRowCacheSnapshot -Snapshot $snapshot
        Write-Host ("Restored site existing row cache snapshot from '{0}' ({1} entr{2})." -f $SnapshotPath, $entryCount, $(if ($entryCount -eq 1) { 'y' } else { 'ies' })) -ForegroundColor DarkCyan
    } catch {
        Write-Warning ("Failed to restore site existing row cache snapshot '{0}': {1}" -f $SnapshotPath, $_.Exception.Message)
    }
}

function Get-IngestionHistorySnapshot {
    param(
        [string]$DirectoryPath
    )

    $snapshot = [System.Collections.Generic.List[psobject]]::new()
    foreach ($file in Get-ChildItem -Path $DirectoryPath -Filter '*.json' -File) {
        $content = [System.IO.File]::ReadAllText($file.FullName)
        [void]$snapshot.Add([pscustomobject]@{
            Path    = $file.FullName
            Content = $content
        })
    }
    if ($snapshot.Count -eq 0) {
        throw "No ingestion history JSON files found under $DirectoryPath."
    }
    return $snapshot.ToArray()
}

function Get-IngestionHistoryWarmRunSnapshot {
    param(
        [Parameter(Mandatory)]
        [string]$DirectoryPath,
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable]$FallbackSnapshot
    )

    $warmRunSnapshot = [System.Collections.Generic.List[psobject]]::new()
    foreach ($entry in $FallbackSnapshot) {
        $targetPath = $entry.Path
        $fileName = [System.IO.Path]::GetFileName($targetPath)
        $pattern = "${fileName}.warmrun.*.bak"
        $backup = $null
        foreach ($candidate in Get-ChildItem -Path $DirectoryPath -Filter $pattern -File) {
            if (-not $backup -or $candidate.LastWriteTime -gt $backup.LastWriteTime) {
                $backup = $candidate
            }
        }
        if ($backup) {
            # LANDMARK: Warm-run history backup selection - record chosen backup path
            Write-Host ("Warm-run backup selected for {0}: {1}" -f $fileName, $backup.FullName) -ForegroundColor DarkCyan
            $content = [System.IO.File]::ReadAllText($backup.FullName)
            if (-not [string]::IsNullOrWhiteSpace($content)) {
                try {
                    $parsed = ConvertFrom-Json -InputObject $content -ErrorAction Stop
                    if ($parsed) {
                        $records = @($parsed)
                        if ($records.Count -gt 1) {
                            $content = ConvertTo-Json -InputObject $records -Depth 6
                        } elseif ($records.Count -eq 1) {
                            $content = ConvertTo-Json -InputObject $records[0] -Depth 6
                        }
                    }
                } catch {
                    Write-Warning ("Failed to sanitize warm-run backup for {0}: {1}. Using raw content." -f $fileName, $_.Exception.Message)
                }
            }
            [void]$warmRunSnapshot.Add([pscustomobject]@{
                Path         = $targetPath
                Content      = $content
                BackupPath   = $backup.FullName
                BackupStatus = 'Selected'
            })
        } else {
            Write-Warning "No warm-run backup found for $fileName; falling back to the current snapshot."
            [void]$warmRunSnapshot.Add([pscustomobject]@{
                Path         = $entry.Path
                Content      = $entry.Content
                BackupPath   = $null
                BackupStatus = 'FallbackSnapshot'
            })
        }
    }

    if ($warmRunSnapshot.Count -eq 0) {
        throw "Failed to build warm-run snapshot from $DirectoryPath."
    }

    return $warmRunSnapshot.ToArray()
}

# LANDMARK: Warm-run history backups - persist .warmrun.*.bak files after cold pass
function Write-IngestionHistoryWarmRunBackups {
    param(
        [Parameter(Mandatory)]
        [string]$DirectoryPath,
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable]$Snapshot,
        [string]$Label = 'WarmRunBackup'
    )

    if (-not $Snapshot) { return 0 }
    if ([string]::IsNullOrWhiteSpace($DirectoryPath)) { return 0 }

    $null = Initialize-Directory -Path $DirectoryPath
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $written = 0

    foreach ($entry in $Snapshot) {
        if (-not $entry) { continue }
        $targetPath = $entry.Path
        if ([string]::IsNullOrWhiteSpace($targetPath)) { continue }
        $fileName = [System.IO.Path]::GetFileName($targetPath)
        if ([string]::IsNullOrWhiteSpace($fileName)) { continue }
        $backupPath = Join-Path -Path $DirectoryPath -ChildPath ("{0}.warmrun.{1}.bak" -f $fileName, $timestamp)
        $content = $entry.Content
        if ($null -eq $content) { $content = '' }
        try {
            [System.IO.File]::WriteAllText($backupPath, $content)
            $written++
        } catch {
            Write-Warning ("Failed to write warm-run backup for {0}: {1}" -f $fileName, $_.Exception.Message)
        }
    }

    if ($written -gt 0) {
        Write-Host ("Warm-run backup files written ({0}) [{1}]." -f $written, $Label) -ForegroundColor DarkCyan
    }

    return $written
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

    $sites = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $Snapshot) {
        if (-not $entry) { continue }
        $content = $entry.Content
        if ([string]::IsNullOrWhiteSpace($content)) { continue }
        $records = $null
        try {
            $records = ConvertFrom-Json -InputObject $content -ErrorAction Stop
        } catch {
            continue
        }
        foreach ($record in @($records)) {
            if ($null -eq $record) { continue }
            $siteValue = Get-TrimmedSiteKey -InputObject $record
            if (-not [string]::IsNullOrWhiteSpace($siteValue)) {
                [void]$sites.Add($siteValue)
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

    if ($null -eq $Value) {
        return [string[]]@()
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $tokens = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $Value) {
            $childTokens = Get-HostnameTokens -Value $item
            if ($childTokens.Count -gt 0) {
                [void]$tokens.AddRange($childTokens)
            }
        }
        return $tokens.ToArray()
    }

    $text = '' + $Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return [string[]]@()
    }

    $tokens = [System.Collections.Generic.List[string]]::new()
    foreach ($part in ($text -split ',')) {
        $candidate = $part.Trim()
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            [void]$tokens.Add($candidate)
        }
    }

    return $tokens.ToArray()
}

function Get-HostnameFilterSet {
    param(
        [string[]]$Hostnames,
        [string]$Path
    )

    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

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
                foreach ($line in [System.IO.File]::ReadLines($Path)) {
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

    $hostnames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($event in @($Events)) {
        if (-not $event) { continue }
        $value = $null
        $hostnameProp = $event.PSObject.Properties['Hostname']
        if ($hostnameProp) {
            $value = $hostnameProp.Value
        } else {
            $hostnamesProp = $event.PSObject.Properties['Hostnames']
            if ($hostnamesProp) {
                $value = $hostnamesProp.Value
            }
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

    $filtered = [System.Collections.Generic.List[psobject]]::new()
    foreach ($event in @($Events)) {
        if (-not $event) { continue }
        $hosts = @()
        $hostnameProp = $event.PSObject.Properties['Hostname']
        if ($hostnameProp) {
            $hosts = Get-HostnameTokens -Value $hostnameProp.Value
        } else {
            $hostnamesProp = $event.PSObject.Properties['Hostnames']
            if ($hostnamesProp) {
                $hosts = Get-HostnameTokens -Value $hostnamesProp.Value
            } else {
                $legacyHostnameProp = $event.PSObject.Properties['HostName']
                if ($legacyHostnameProp) {
                    $hosts = Get-HostnameTokens -Value $legacyHostnameProp.Value
                } else {
                    $hostProp = $event.PSObject.Properties['Host']
                    if ($hostProp) {
                        $hosts = Get-HostnameTokens -Value $hostProp.Value
                    }
                }
            }
        }
        if (-not $hosts -or $hosts.Count -le 0) {
            # Preserve host-less events so pass-level summaries retain cold coverage even when host filter is active.
            [void]$filtered.Add($event)
            continue
        }

        foreach ($hostNameCandidate in $hosts) {
            if ([string]::IsNullOrWhiteSpace($hostNameCandidate)) { continue }
            $trimmed = $hostNameCandidate.Trim()
            if (-not $AllowedHostnames.Contains($trimmed)) { continue }

            $clone = $event.PSObject.Copy()
            $cloneHostname = $clone.PSObject.Properties['Hostname']
            if ($cloneHostname) {
                $clone.Hostname = $trimmed
            } else {
                Add-Member -InputObject $clone -NotePropertyName 'Hostname' -NotePropertyValue $trimmed -Force
            }
            if ($clone.PSObject.Properties['Hostnames']) {
                $clone.Hostnames = $trimmed
            }
            [void]$filtered.Add($clone)
        }
    }

    return $filtered.ToArray()
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
    $labeled = [System.Collections.Generic.List[psobject]]::new()
    foreach ($evt in @($Events)) {
        if (-not $evt) { continue }
        if (-not ($evt -is [psobject])) {
            try {
                $evt = [pscustomobject]@{ Value = $evt }
            } catch {
                continue
            }
        }

        $passLabelValue = $null
        $passLabelProp = $evt.PSObject.Properties['PassLabel']
        if ($passLabelProp) {
            try { $passLabelValue = $passLabelProp.Value } catch { $passLabelValue = $null }
        }

        if ([string]::IsNullOrWhiteSpace($passLabelValue)) {
            $target = $evt
            if (-not $passLabelProp) {
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
        [void]$labeled.Add($evt)
    }
    return $labeled.ToArray()
}

$script:ComparisonHostFilter = Get-HostnameFilterSet -Hostnames $HostFilter -Path $HostFilterPath
if ($script:ComparisonHostFilter -and $script:ComparisonHostFilter.Count -gt 0) {
    $preview = Get-FirstItems -Items $script:ComparisonHostFilter -Count 10
    Write-Host ("Hostname filter active with {0} entr{1}: {2}" -f $script:ComparisonHostFilter.Count, $(if ($script:ComparisonHostFilter.Count -eq 1) { 'y' } else { 'ies' }), [string]::Join(', ', $preview)) -ForegroundColor DarkCyan
}
if ($RestrictWarmComparisonToColdHosts.IsPresent) {
    Write-Host 'Warm comparison metrics will be limited to hostnames captured during the cold pass (intersected with any explicit filters).' -ForegroundColor DarkYellow
}

function Get-TelemetryLogFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DirectoryPath
    )

    $telemetryLogPath = $null
    try {
        $telemetryPathCmd = Get-TelemetryModuleCommand -Name 'Get-TelemetryLogPath'
        if ($telemetryPathCmd) {
            $telemetryLogPath = & $telemetryPathCmd
        }
    } catch { }

    if (-not [string]::IsNullOrWhiteSpace($telemetryLogPath) -and (Test-Path -LiteralPath $telemetryLogPath)) {
        try { return ,(Get-Item -LiteralPath $telemetryLogPath -ErrorAction Stop) } catch { }
    }

    if (-not (Test-Path -LiteralPath $DirectoryPath)) {
        return @()
    }

    $candidates = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($file in Get-ChildItem -Path $DirectoryPath -Filter '*.json' -File) {
        if ($file.BaseName -match '^\d{4}-\d{2}-\d{2}$') {
            [void]$candidates.Add($file)
        }
    }

    if ($candidates.Count -gt 1) {
        $candidates.Sort({ param($left, $right) [string]::Compare($left.FullName, $right.FullName, [System.StringComparison]::OrdinalIgnoreCase) })
    }

    return $candidates.ToArray()
}

function Get-MetricsBaseline {
    param(
        [string]$DirectoryPath
    )

    $baseline = @{}
    foreach ($file in Get-TelemetryLogFiles -DirectoryPath $DirectoryPath) {
        $lineCount = Get-FileLineCount -Path $file.FullName
        $baseline[$file.FullName] = [pscustomobject]@{
            LineCount   = $lineCount
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

    $events = [System.Collections.Generic.List[psobject]]::new()

    $excludeSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($path in @($ExcludePaths)) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            [void]$excludeSet.Add((Resolve-Path -LiteralPath $path).Path)
        } catch {
            Write-Verbose ("Failed to resolve exclude path '{0}': {1}" -f $path, $_.Exception.Message) -Verbose:$VerboseParsing
        }
    }

    $shouldApplyExcludes = $excludeSet.Count -gt 0
    foreach ($file in Get-TelemetryLogFiles -DirectoryPath $DirectoryPath) {
        $filePath = $file.FullName
        if ($shouldApplyExcludes) {
            $resolved = $filePath
            try { $resolved = (Resolve-Path -LiteralPath $filePath).Path } catch { $resolved = $filePath }
            if ($excludeSet.Contains($resolved)) { continue }
        }

        $previousCount = 0
        $previousLength = 0
        if ($Baseline.ContainsKey($filePath)) {
            $entry = $Baseline[$filePath]
            $lineCountProp = $entry.PSObject.Properties['LineCount']
            if ($lineCountProp) {
                try { $previousCount = [int]$lineCountProp.Value } catch { $previousCount = 0 }
            }
            $lengthProp = $entry.PSObject.Properties['LengthBytes']
            if ($lengthProp) {
                try { $previousLength = [long]$lengthProp.Value } catch { $previousLength = 0 }
            }
        }

        $currentLength = 0
        try { $currentLength = [long]$file.Length } catch { $currentLength = 0 }
        if ($previousLength -gt 0) {
            if ($currentLength -lt $previousLength) {
                $previousCount = 0
                $previousLength = 0
            } elseif ($currentLength -eq $previousLength) {
                continue
            }
        }

        $lineIndex = 0
        foreach ($line in [System.IO.File]::ReadLines($filePath)) {
            $currentIndex = $lineIndex
            $lineIndex++
            if ($currentIndex -lt $previousCount) { continue }
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            try {
                $parsed = ConvertFrom-Json -InputObject $line -ErrorAction Stop
                Add-Member -InputObject $parsed -NotePropertyName '__SourceFile' -NotePropertyValue $filePath
                Add-Member -InputObject $parsed -NotePropertyName '__LineIndex' -NotePropertyValue $currentIndex
                [void]$events.Add($parsed)
            } catch {
                Write-Warning "Failed to parse telemetry line $($file.Name):$currentIndex. $($_.Exception.Message)"
            }
        }

        $Baseline[$filePath] = [pscustomobject]@{
            LineCount   = $lineIndex
            LengthBytes = $currentLength
        }
    }

    return $events.ToArray()
}

function Wait-TelemetryFlush {
    param(
        [Parameter(Mandatory)][string]$DirectoryPath,
        [Parameter(Mandatory)][hashtable]$Baseline,
        [int]$TimeoutMilliseconds = 5000,
        [int]$PollMilliseconds = 100
    )

    $timeoutMs = if ($TimeoutMilliseconds -gt 0) { $TimeoutMilliseconds } else { 5000 }
    $pollMs = if ($PollMilliseconds -gt 0) { $PollMilliseconds } else { 100 }
    if ($pollMs -gt $timeoutMs) { $pollMs = [Math]::Max(25, [int]($timeoutMs / 5)) }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        do {
            foreach ($file in Get-TelemetryLogFiles -DirectoryPath $DirectoryPath) {
                $previousLength = 0
                if ($Baseline.ContainsKey($file.FullName)) {
                    $entry = $Baseline[$file.FullName]
                    $lengthProp = $entry.PSObject.Properties['LengthBytes']
                    if ($lengthProp) {
                        try { $previousLength = [long]$lengthProp.Value } catch { $previousLength = 0 }
                    }
                }
                if ($file.Length -gt $previousLength) {
                    return
                }
            }
            Start-Sleep -Milliseconds $pollMs
        } while ($stopwatch.ElapsedMilliseconds -lt $timeoutMs)
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

    $events = [System.Collections.Generic.List[psobject]]::new()
    $eventNameSet = $null
    if ($EventNames -and $EventNames.Count -gt 0) {
        $eventNameSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($name in $EventNames) {
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            [void]$eventNameSet.Add(('' + $name).Trim())
        }
    }

    foreach ($file in Get-TelemetryLogFiles -DirectoryPath $DirectoryPath) {
        if ($file.LastWriteTime -lt $Since) { continue }
        $lineIndex = 0
        foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
            $currentIndex = $lineIndex
            $lineIndex++
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $parsed = ConvertFrom-Json -InputObject $line -ErrorAction Stop
            } catch {
                continue
            }
            if (-not $parsed) { continue }
            $timestampProp = $parsed.PSObject.Properties['Timestamp']
            if (-not $timestampProp) { continue }
            $timestamp = $timestampProp.Value
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
            if ($eventNameSet) {
                $parsedEventName = ''
                $eventNameProp = $parsed.PSObject.Properties['EventName']
                if ($eventNameProp) {
                    $parsedEventName = ('' + $eventNameProp.Value).Trim()
                }
                if ([string]::IsNullOrWhiteSpace($parsedEventName) -or -not $eventNameSet.Contains($parsedEventName)) { continue }
            }
            Add-Member -InputObject $parsed -NotePropertyName '__SourceFile' -NotePropertyValue $file.FullName -Force
            Add-Member -InputObject $parsed -NotePropertyName '__LineIndex' -NotePropertyValue $currentIndex -Force
            [void]$events.Add($parsed)
        }
    }
    return $events.ToArray()
}

function Get-TelemetryIdentityKey {
    param(
        [Parameter(Mandatory)]
        [psobject]$Event
    )

    $eventName = ''
    $eventNameProp = $Event.PSObject.Properties['EventName']
    if ($eventNameProp) { $eventName = ('' + $eventNameProp.Value).Trim() }

    $site = Get-TrimmedSiteKey -InputObject $Event

    $timestampKey = ''
    $timestampProp = $Event.PSObject.Properties['Timestamp']
    if ($timestampProp) {
        $timestampValue = $timestampProp.Value
        if ($timestampValue -is [datetime]) {
            $timestampKey = $timestampValue.ToString('o')
        } elseif (-not [string]::IsNullOrWhiteSpace($timestampValue)) {
            $timestampKey = ('' + $timestampValue).Trim()
        }
    }

    $sourceFile = ''
    $sourceFileProp = $Event.PSObject.Properties['__SourceFile']
    if ($sourceFileProp) { $sourceFile = ('' + $sourceFileProp.Value).Trim() }

    $lineIndex = ''
    $lineIndexProp = $Event.PSObject.Properties['__LineIndex']
    if ($lineIndexProp) { $lineIndex = ('' + $lineIndexProp.Value).Trim() }

    return [string]::Format('{0}|{1}|{2}|{3}|{4}', $eventName, $site, $timestampKey, $sourceFile, $lineIndex)
}

function Get-EventNameCount {
    param(
        [System.Collections.IEnumerable]$Events,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not $Events -or [string]::IsNullOrWhiteSpace($Name)) {
        return 0
    }

    $count = 0
    foreach ($evt in $Events) {
        if (-not $evt) { continue }
        $eventNameProp = $evt.PSObject.Properties['EventName']
        if (-not $eventNameProp) { continue }
        if ([string]::Equals(('' + $eventNameProp.Value).Trim(), $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            $count++
        }
    }

    return $count
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

    $allEvents = [System.Collections.Generic.List[psobject]]::new()
    $eventBuckets = @{}
    $identitySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $passLineBaseline = @{}
    foreach ($file in Get-TelemetryLogFiles -DirectoryPath $DirectoryPath) {
        $baselineCount = 0
        if ($Baseline.ContainsKey($file.FullName)) {
            $entry = $Baseline[$file.FullName]
            if ($entry) {
                $lineCountProp = $entry.PSObject.Properties['LineCount']
                if ($lineCountProp) {
                    try { $baselineCount = [int]$lineCountProp.Value } catch { $baselineCount = 0 }
                }
            }
        }
        $passLineBaseline[$file.FullName] = $baselineCount
    }
    $requiredNames = [System.Collections.Generic.List[string]]::new()
    if ($RequiredEventNames) {
        foreach ($name in $RequiredEventNames) {
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            if (-not $eventBuckets.ContainsKey($name)) {
                $eventBuckets[$name] = [System.Collections.Generic.List[psobject]]::new()
            }
            [void]$requiredNames.Add($name)
        }
    }

    $countLogPrefix = 'Collect-TelemetryForPass'
    $getCountOrThrow = {
        param(
            [Parameter(Mandatory)][string]$Label,
            $Value
        )

        if ($null -eq $Value) {
            Write-Warning ("{0}: '{1}' is null; Count property unavailable (treating as 0)." -f $countLogPrefix, $Label)
            return 0
        }

        $countProp = $Value.PSObject.Properties['Count']
        if (-not $countProp) {
            $typeName = $Value.GetType().FullName
            $propNames = $Value.PSObject.Properties.Name -join ', '
            $valuePreview = ''
            try { $valuePreview = ('' + $Value) } catch { $valuePreview = '<unprintable>' }
            Write-Warning ("{0}: '{1}' missing Count property. Type={2}; Properties={3}; Value={4}" -f $countLogPrefix, $Label, $typeName, $propNames, $valuePreview)
            throw ("{0}: '{1}' missing Count property (type {2})." -f $countLogPrefix, $Label, $typeName)
        }

        return $countProp.Value
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

        [void]$allEvents.Add($evt)

        if ((& $getCountOrThrow 'requiredNames' $requiredNames) -gt 0) {
            $evtNameProp = $evt.PSObject.Properties['EventName']
            if (-not $evtNameProp) { return }
            $evtName = ('' + $evtNameProp.Value).Trim()
            if (-not [string]::IsNullOrWhiteSpace($evtName) -and $eventBuckets.ContainsKey($evtName)) {
                [void]$eventBuckets[$evtName].Add($evt)
            }
        }
    }

    $getMissingEventNames = {
        $missing = [System.Collections.Generic.List[string]]::new()
        foreach ($name in $requiredNames) {
            $bucket = $null
            if ($eventBuckets.ContainsKey($name)) { $bucket = $eventBuckets[$name] }
            if (-not $bucket -or (& $getCountOrThrow ("eventBuckets[{0}]" -f $name) $bucket) -eq 0) {
                [void]$missing.Add($name)
            }
        }
        Write-Output -NoEnumerate $missing
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
            $bucket = $null
            if ($eventBuckets.ContainsKey($name)) { $bucket = $eventBuckets[$name] }
            if (-not $bucket -or (& $getCountOrThrow ("eventBuckets[{0}]" -f $name) $bucket) -eq 0) {
                $complete = $false
                break
            }
        }

        if ($complete -or $attempt -ge $maxAttempts) {
            break
        }

        Wait-TelemetryFlush -DirectoryPath $DirectoryPath -Baseline $Baseline -TimeoutMilliseconds $pollTimeout -PollMilliseconds $pollInner
    } while ($true)

    $missingNames = & $getMissingEventNames

    if ((& $getCountOrThrow 'missingNames' $missingNames) -gt 0 -and $PassStartTime) {
        $fallbackSince = $PassStartTime
        if ($FallbackLookbackSeconds -gt 0) {
            $fallbackSince = $PassStartTime.AddSeconds(-1 * [math]::Abs($FallbackLookbackSeconds))
        }

        $fallbackEvents = Get-TelemetrySince -Since $fallbackSince -DirectoryPath $DirectoryPath -EventNames $requiredNames.ToArray() -IgnoreEventTimestamp
        foreach ($evt in @($fallbackEvents)) {
            if (-not $evt) { continue }

            $baselineLineCount = $null
            $sourceFile = ''
            $sourceFileProp = $evt.PSObject.Properties['__SourceFile']
            if ($sourceFileProp) { $sourceFile = ('' + $sourceFileProp.Value).Trim() }
            if (-not [string]::IsNullOrWhiteSpace($sourceFile) -and $passLineBaseline.ContainsKey($sourceFile)) {
                $baselineLineCount = [int]$passLineBaseline[$sourceFile]
            }

            $lineIndex = $null
            $lineIndexProp = $evt.PSObject.Properties['__LineIndex']
            if ($lineIndexProp) {
                try { $lineIndex = [int]$lineIndexProp.Value } catch { $lineIndex = $null }
            }

            if ($baselineLineCount -ne $null -and $lineIndex -ne $null -and $lineIndex -lt $baselineLineCount) {
                continue
            }

            & $addEvent $evt
        }

        $missingNames = & $getMissingEventNames
    }

    $bucketArrays = @{}
    foreach ($key in @($eventBuckets.Keys)) {
        $value = $eventBuckets[$key]
        if ($value -and $value -is [System.Collections.Generic.List[psobject]]) {
            $bucketArrays[$key] = $value.ToArray()
        } else {
            $bucketArrays[$key] = @($value)
        }
    }

    return [pscustomobject]@{
        Events            = $allEvents.ToArray()
        Buckets           = $bucketArrays
        MissingEventNames = $missingNames.ToArray()
    }
}

# LANDMARK: Warm-pass metric status - classify duplicate-only telemetry
function Resolve-PassTelemetryMetricStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Label,
        [System.Collections.IEnumerable]$Events,
        [string[]]$MissingEventNames,
        [string]$HistorySeedMode
    )

    $parseDurationCount = Get-EventNameCount -Events $Events -Name 'ParseDuration'
    $skippedDuplicateCount = Get-EventNameCount -Events $Events -Name 'SkippedDuplicate'
    $duplicateOnly = ($parseDurationCount -le 0 -and $skippedDuplicateCount -gt 0)

    $optionalMissing = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($Label -eq 'WarmPass' -and $duplicateOnly -and -not [string]::IsNullOrWhiteSpace($HistorySeedMode) -and $HistorySeedMode -ne 'Empty') {
        foreach ($name in @('DatabaseWriteBreakdown','InterfaceSyncTiming')) {
            [void]$optionalMissing.Add($name)
        }
    }

    $statusEntries = [System.Collections.Generic.List[psobject]]::new()
    foreach ($metricName in @($MissingEventNames)) {
        if ([string]::IsNullOrWhiteSpace($metricName)) { continue }
        if ($optionalMissing.Contains($metricName)) {
            $statusEntries.Add([pscustomobject]@{
                PassLabel             = $Label
                SummaryType           = 'TelemetryMetricStatus'
                MetricName            = $metricName
                MetricStatus          = 'NotApplicable'
                MetricStatusReason    = 'SkippedDuplicateOnly'
                MetricStatusNotes     = ("HistorySeed={0}; ParseDurationCount={1}; SkippedDuplicateCount={2}" -f $HistorySeedMode, $parseDurationCount, $skippedDuplicateCount)
                ParseDurationCount    = $parseDurationCount
                SkippedDuplicateCount = $skippedDuplicateCount
                HistorySeedMode       = $HistorySeedMode
            })
        }
    }

    return [pscustomobject]@{
        OptionalMissing     = $optionalMissing
        Statuses            = $statusEntries.ToArray()
        ParseDurationCount  = $parseDurationCount
        SkippedDuplicateCount = $skippedDuplicateCount
        DuplicateOnly       = $duplicateOnly
    }
}

# LANDMARK: Warm-pass telemetry warnings - filter expected missing metrics
function Get-TelemetryWarningMissingNames {
    [CmdletBinding()]
    param(
        [string[]]$MissingEventNames,
        [System.Collections.IEnumerable]$OptionalMissing
    )

    $warnMissing = @()
    if ($MissingEventNames) {
        $warnMissing = @($MissingEventNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    if ($OptionalMissing) {
        $optionalSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($name in @($OptionalMissing)) {
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            [void]$optionalSet.Add($name)
        }
        if ($optionalSet.Count -gt 0 -and $warnMissing.Count -gt 0) {
            $warnMissing = @($warnMissing | Where-Object { -not $optionalSet.Contains($_) })
        }
    }

    return ,@($warnMissing)
}

function Resolve-PassWindow {
    param(
        [string]$Label,
        [System.Collections.IEnumerable]$Events,
        [datetime]$FallbackStart,
        [datetime]$FallbackEnd
    )

    $start = $null
    $end = $null
    $timestampCount = 0
    foreach ($evt in @($Events)) {
        if (-not $evt) { continue }
        $timestampProp = $evt.PSObject.Properties['Timestamp']
        if (-not $timestampProp) { continue }
        $timestampValue = $timestampProp.Value
        $ts = $null
        try {
            if ($timestampValue -is [datetime]) {
                $ts = $timestampValue
            } elseif (-not [string]::IsNullOrWhiteSpace($timestampValue)) {
                $ts = [datetime]$timestampValue
            }
        } catch {
            $ts = $null
        }
        if (-not $ts) { continue }
        $timestampCount++
        if (-not $start -or $ts -lt $start) { $start = $ts }
        if (-not $end -or $ts -gt $end) { $end = $ts }
    }

    if (-not $start -and $FallbackStart) { $start = $FallbackStart }
    if (-not $end -and $FallbackEnd) { $end = $FallbackEnd }
    if ($start -and -not $end) { $end = $start }
    if ($end -and -not $start) { $start = $end }
    if ($start -and $end -and $start -gt $end) {
        $swap = $start
        $start = $end
        $end = $swap
    }

    $startUtc = $null
    $endUtc = $null
    if ($start) { $startUtc = $start.ToUniversalTime() }
    if ($end) { $endUtc = $end.ToUniversalTime() }

    return [pscustomobject]@{
        PassLabel      = $Label
        StartLocal     = $start
        EndLocal       = $end
        StartUtc       = $startUtc
        EndUtc         = $endUtc
        TimestampCount = $timestampCount
    }
}

function Get-LatestIngestionMetricsFile {
    param(
        [Parameter(Mandatory)]
        [string]$DirectoryPath
    )

    if (-not (Test-Path -LiteralPath $DirectoryPath)) {
        return $null
    }
    $entries = Get-ChildItem -LiteralPath $DirectoryPath -Filter '*.json' -File |
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}\.json$' } |
        Sort-Object LastWriteTime -Descending
    if (-not $entries) { return $null }
    return $entries[0].FullName
}

function Measure-InterfaceCallDurationMetrics {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable]$Events
    )

    $durations = [System.Collections.Generic.List[double]]::new()
    $providerCounts = @{}
    $capturedEvents = [System.Collections.Generic.List[psobject]]::new()

    foreach ($event in @($Events)) {
        if (-not $event) {
            continue
        }

        [void]$capturedEvents.Add($event)

        $provider = ''
        $providerProp = $event.PSObject.Properties['SiteCacheProvider']
        if ($providerProp) { $provider = ('' + $providerProp.Value).Trim() }
        if ([string]::IsNullOrWhiteSpace($provider)) {
            $provider = 'Unknown'
        }
        if ($provider -eq 'SharedCache') {
            $provider = 'Cache'
        }
        if ($providerCounts.ContainsKey($provider)) {
            $providerCounts[$provider]++
        } else {
            $providerCounts[$provider] = 1
        }

        $durationProp = $event.PSObject.Properties['InterfaceCallDurationMs']
        if ($durationProp) {
            $durationValue = $durationProp.Value
            if ($null -ne $durationValue) {
                try { [void]$durations.Add([double]$durationValue) } catch { }
            }
        }
    }

    $durationArray = $durations.ToArray()
    $count = $durationArray.Length
    $averageRaw = $null
    $p95Raw = $null
    $maxRaw = $null

    if ($count -gt 0) {
        $averageRaw = [System.Linq.Enumerable]::Average($durationArray)
        $maxRaw = [System.Linq.Enumerable]::Max($durationArray)
        $p95Raw = StatisticsModule\Get-PercentileValue -Values $durationArray -Percentile 95
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
        Events         = $capturedEvents.ToArray()
        Durations      = $durationArray
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

            $siteKey = Get-TrimmedSiteKey -InputObject $eventRecord
            if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }

            $hostKey = WarmRun.Telemetry\Get-HostKeyFromTelemetryEvent -Event $eventRecord
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

    $sitesWithHostEvents = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($mapKey in @($databaseEventMap.Keys + $interfaceEventMap.Keys)) {
        if ([string]::IsNullOrWhiteSpace($mapKey)) { continue }
        $parts = $mapKey -split '\|', 2
        if ($parts.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($parts[0])) {
            [void]$sitesWithHostEvents.Add($parts[0].Trim())
        }
    }

    $summaryHostKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $filteredSummaries = [System.Collections.Generic.List[psobject]]::new()
    foreach ($summary in $results) {
        if (-not $summary) { continue }

        $siteKey = Get-TrimmedSiteKey -InputObject $summary
        if ([string]::IsNullOrWhiteSpace($siteKey)) {
            [void]$filteredSummaries.Add($summary)
            continue
        }

        $hostKey = WarmRun.Telemetry\Get-HostKeyFromMetricsSummary -Summary $summary
        $hostTokens = @()
        if (-not [string]::IsNullOrWhiteSpace($hostKey)) {
            $hostTokens = @(Get-HostnameTokens -Value $hostKey)
        }
        if ($hostTokens.Count -gt 1 -and $sitesWithHostEvents.Contains($siteKey)) {
            continue
        }

        [void]$filteredSummaries.Add($summary)
        if ($hostTokens.Count -eq 1) {
            $mapKey = '{0}|{1}' -f $siteKey, $hostTokens[0]
            [void]$summaryHostKeys.Add($mapKey)
        }
    }

    $results = @($filteredSummaries)
    $buildSummary = {
        param($eventRecord)

        if (-not $eventRecord -or -not $eventRecord.PSObject) { return $null }

        $siteKey = Get-TrimmedSiteKey -InputObject $eventRecord
        if ([string]::IsNullOrWhiteSpace($siteKey)) { return $null }

        $hostKey = WarmRun.Telemetry\Get-HostKeyFromTelemetryEvent -Event $eventRecord
        if ([string]::IsNullOrWhiteSpace($hostKey)) { return $null }

        $timestamp = $eventRecord.Timestamp
        if ($timestamp -isnot [datetime] -and -not [string]::IsNullOrWhiteSpace($timestamp)) {
            try { $timestamp = [datetime]::Parse($timestamp) } catch { $timestamp = $null }
        }

        $provider = $null
        $providerProp = $eventRecord.PSObject.Properties['SiteCacheProvider']
        if ($providerProp) {
            $provider = $providerProp.Value
        } elseif ($eventRecord.PSObject.Properties['Provider']) {
            $provider = $eventRecord.Provider
        }

        $cacheStatus = $null
        $cacheStatusProp = $eventRecord.PSObject.Properties['SiteCacheFetchStatus']
        if ($cacheStatusProp) {
            $cacheStatus = $cacheStatusProp.Value
        } elseif ($eventRecord.PSObject.Properties['CacheStatus']) {
            $cacheStatus = $eventRecord.CacheStatus
        }

        $providerReason = $null
        if ($eventRecord.PSObject.Properties['SiteCacheProviderReason']) {
            $providerReason = $eventRecord.SiteCacheProviderReason
        }

        return [pscustomobject]@{
            PassLabel                     = $eventRecord.PassLabel
            Site                          = $siteKey
            Hostname                      = $hostKey
            Timestamp                     = $timestamp
            CacheStatus                   = $cacheStatus
            Provider                      = $provider
            SiteCacheProviderReason       = $providerReason
            HydrationDurationMs           = $null
            SnapshotDurationMs            = $null
            HostMapDurationMs             = $null
            HostCount                     = 1
            TotalRows                     = $null
            HostMapSignatureMatchCount    = $null
            HostMapSignatureRewriteCount  = $null
            HostMapCandidateMissingCount  = $null
            HostMapCandidateFromPrevious  = $null
            PreviousHostCount             = $null
            PreviousSnapshotStatus        = $null
            PreviousSnapshotHostMapType   = $null
            Metrics                       = $null
        }
    }

    $newSummaries = [System.Collections.Generic.List[psobject]]::new()
    foreach ($mapKey in @($databaseEventMap.Keys)) {
        if ($summaryHostKeys.Contains($mapKey)) { continue }
        $summary = & $buildSummary $databaseEventMap[$mapKey]
        if ($summary) {
            [void]$newSummaries.Add($summary)
            [void]$summaryHostKeys.Add($mapKey)
        }
    }
    foreach ($mapKey in @($interfaceEventMap.Keys)) {
        if ($summaryHostKeys.Contains($mapKey)) { continue }
        $summary = & $buildSummary $interfaceEventMap[$mapKey]
        if ($summary) {
            [void]$newSummaries.Add($summary)
            [void]$summaryHostKeys.Add($mapKey)
        }
    }

    if ($newSummaries.Count -gt 0) {
        $results = @($results + $newSummaries.ToArray())
    }

    foreach ($summary in $results) {
        if (-not $summary) { continue }

        $siteKey = Get-TrimmedSiteKey -InputObject $summary
        if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }

        $hostKey = WarmRun.Telemetry\Get-HostKeyFromMetricsSummary -Summary $summary
        if ([string]::IsNullOrWhiteSpace($hostKey)) { continue }

        $mapKey = '{0}|{1}' -f $siteKey, $hostKey

        if ($databaseEventMap.ContainsKey($mapKey)) {
            $databaseEvent = $databaseEventMap[$mapKey]
            foreach ($propertyName in $perHostDatabaseProperties) {
                $property = $databaseEvent.PSObject.Properties[$propertyName]
                if ($property) { Add-Member -InputObject $summary -MemberType NoteProperty -Name $propertyName -Value $property.Value -Force }
            }
        }

        if ($interfaceEventMap.ContainsKey($mapKey)) {
            $interfaceEvent = $interfaceEventMap[$mapKey]
            foreach ($propertyName in $perHostInterfaceProperties) {
                $property = $interfaceEvent.PSObject.Properties[$propertyName]
                if ($property) { Add-Member -InputObject $summary -MemberType NoteProperty -Name $propertyName -Value $property.Value -Force }
            }
        }
    }

    return $results
}

$results = [System.Collections.Generic.List[psobject]]::new()
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
$sharedCacheSnapshotDirectory = Join-Path -Path (Join-Path $repositoryRoot 'Logs') -ChildPath 'SharedCacheSnapshot'
$sharedCacheSnapshotLatestPath = Join-Path -Path $sharedCacheSnapshotDirectory -ChildPath 'SharedCacheSnapshot-latest.clixml'
$sharedCacheSnapshotCleanupPath = $null
$coldSharedCacheSnapshotPath = $null
$coldSharedCacheSnapshotCleanupPath = $null

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
if ($UseBalancedHostOrder.IsPresent) {
    # LANDMARK: Host sweep balancing - keep warm-run parsing order deterministic
    $pipelineArguments['UseBalancedHostOrder'] = $true
}
if ($ResetExtractedLogs) {
    $pipelineArguments['ResetExtractedLogs'] = $true
}
if ($SkipPortDiversityGuard) {
    $pipelineArguments['SkipPortDiversityGuard'] = $true
}
if ($ForcePortBatchReadySynthesis.IsPresent) {
    # LANDMARK: PortBatchReady synthesis - keep warm-run diversity guard aligned with synthesized batches
    Write-Warning 'PortBatchReady synthesis is enabled for warm-run telemetry; events will be synthesized for guard evaluation.'
    $pipelineArguments['ForcePortBatchReadySynthesis'] = $true
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
        [string]$Label,
        [string]$HistorySeedMode
    )

    $passStartTime = Get-Date
    Write-Host "Running pipeline pass '$Label'..." -ForegroundColor Cyan
    $null = & $pipelineScript @pipelineArguments
    Write-Host "Pipeline pass '$Label' completed." -ForegroundColor Green

    Wait-TelemetryFlush -DirectoryPath $metricsDirectory -Baseline $metricsBaseline

    $passEndTime = Get-Date
    $collection = Collect-TelemetryForPass -DirectoryPath $metricsDirectory -Baseline $metricsBaseline -PassStartTime $passStartTime -RequiredEventNames @('InterfaceSiteCacheMetrics','DatabaseWriteBreakdown','InterfaceSyncTiming')

    # LANDMARK: Warm-pass telemetry warnings - suppress expected missing metrics
    $passEvents = @()
    if ($collection -and $collection.Events) {
        $passEvents = $collection.Events
    }
    $missingEventNames = @()
    if ($collection -and $collection.MissingEventNames) {
        $missingEventNames = $collection.MissingEventNames
    }
    $historySeedLabel = if ([string]::IsNullOrWhiteSpace($HistorySeedMode)) { '' } else { $HistorySeedMode }
    $passMetricStatus = Resolve-PassTelemetryMetricStatus -Label $Label -Events $passEvents -MissingEventNames $missingEventNames -HistorySeedMode $historySeedLabel
    if ($passMetricStatus -and $passMetricStatus.Statuses -and $passMetricStatus.Statuses.Count -gt 0) {
        $statusPreview = @()
        foreach ($entry in @($passMetricStatus.Statuses)) {
            if (-not $entry) { continue }
            $statusPreview += ("{0}={1}" -f $entry.MetricName, $entry.MetricStatus)
        }
        if ($statusPreview.Count -gt 0) {
            Write-Host ("Pass '{0}' telemetry status: {1}" -f $Label, ([string]::Join(', ', $statusPreview))) -ForegroundColor DarkCyan
        }
    }

    if ($collection -and $collection.Events) {
        $parseDurationCount = Get-EventNameCount -Events $collection.Events -Name 'ParseDuration'
        $skippedDuplicateCount = Get-EventNameCount -Events $collection.Events -Name 'SkippedDuplicate'
        if ($Label -eq 'ColdPass' -and $skippedDuplicateCount -gt 0 -and $parseDurationCount -eq 0) {
            Write-Warning "Cold pass emitted SkippedDuplicate events but no ParseDuration. Ingestion history likely marks these logs as already processed; rerun with -ColdHistorySeed Empty (or clear Data\\IngestionHistory) to force parse telemetry."
        }
    }

    $cacheMetrics = @()
    if ($collection -and $collection.Buckets.ContainsKey('InterfaceSiteCacheMetrics')) {
        $cacheMetrics = @(Add-PassLabelToEvents -Events @($collection.Buckets['InterfaceSiteCacheMetrics']) -PassLabel $Label)
    }

    $passResults = @()
    if (-not $cacheMetrics) {
        Write-Warning "No InterfaceSiteCacheMetrics events were captured for pass '$Label'."
    } else {
        $passResults = @(WarmRun.Telemetry\Convert-MetricsToSummary -PassLabel $Label -Metrics $cacheMetrics)
    }

    $breakdownEvents = @()
    if ($collection -and $collection.Buckets.ContainsKey('DatabaseWriteBreakdown')) {
        $breakdownEvents = @(Add-PassLabelToEvents -Events @($collection.Buckets['DatabaseWriteBreakdown']) -PassLabel $Label)
    }
    if ($collection -and $collection.MissingEventNames -and $collection.MissingEventNames.Count -gt 0) {
        $optionalMissing = $null
        if ($passMetricStatus) { $optionalMissing = $passMetricStatus.OptionalMissing }
        $warnMissing = Get-TelemetryWarningMissingNames -MissingEventNames $missingEventNames -OptionalMissing $optionalMissing
        if ($warnMissing -and $warnMissing.Count -gt 0) {
            Write-Warning ("Telemetry still missing after polling for pass '{0}': {1}" -f $Label, ($warnMissing -join ', '))
        }
    }

    $passWindow = Resolve-PassWindow -Label $Label -Events $collection.Events -FallbackStart $passStartTime -FallbackEnd $passEndTime
    if ($passWindow) {
        $script:PassWindows[$Label] = $passWindow
    }

    $passHostFilter = $script:ComparisonHostFilter
    if ($RestrictWarmComparisonToColdHosts.IsPresent -and $Label -eq 'WarmPass') {
        if ($script:ColdPassHostnames -and $script:ColdPassHostnames.Count -gt 0) {
            $passHostFilter = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
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
            $preview = Get-FirstItems -Items $passHostFilter -Count 10
            Write-Host ("Pass '{0}' applying hostname filter ({1}): {2}" -f $Label, $passHostFilter.Count, [string]::Join(', ', $preview)) -ForegroundColor DarkCyan
        } else {
            Write-Host ("Pass '{0}' running without a hostname filter." -f $Label) -ForegroundColor DarkYellow
        }
    }

    if ($passHostFilter -and $passHostFilter.Count -gt 0 -and $cacheMetrics) {
        $originalCacheCount = $cacheMetrics.Count
        $cacheMetrics = @(Filter-EventsByHostname -Events $cacheMetrics -AllowedHostnames $passHostFilter)
        $filteredCacheCount = $cacheMetrics.Count
        if ($filteredCacheCount -le 0 -and $originalCacheCount -gt 0) {
            Write-Warning ("Hostname filter removed all InterfaceSiteCacheMetrics events for pass '{0}' ({1} -> 0)." -f $Label, $originalCacheCount)
        } elseif ($originalCacheCount -ne $filteredCacheCount) {
            Write-Host ("Filtered InterfaceSiteCacheMetrics events for pass '{0}': {1} -> {2}." -f $Label, $originalCacheCount, $filteredCacheCount) -ForegroundColor DarkCyan
        }
    }

    $originalBreakdownCount = $breakdownEvents.Count
    $breakdownEvents = @(Filter-EventsByHostname -Events $breakdownEvents -AllowedHostnames $passHostFilter)
    $filteredBreakdownCount = $breakdownEvents.Count
    if ($passHostFilter -and $passHostFilter.Count -gt 0 -and $originalBreakdownCount -ne $filteredBreakdownCount) {
        Write-Host ("Filtered DatabaseWriteBreakdown events for pass '{0}': {1} -> {2}." -f $Label, $originalBreakdownCount, $filteredBreakdownCount) -ForegroundColor DarkCyan
    }

    $passHostnames = Get-HostnamesFromEvents -Events @($breakdownEvents)
    $script:PassHostnames[$Label] = $passHostnames
    if ($Label -eq 'ColdPass') {
        $script:ColdPassHostnames = $passHostnames
    }

    if ($passHostFilter -and $passHostFilter.Count -gt 0 -and $Label -eq 'ColdPass') {
        $breakdownCount = $breakdownEvents.Count
        if ($breakdownCount -eq 0) {
            throw "No DatabaseWriteBreakdown events remained for cold pass after applying the hostname filter; cannot produce a valid warm-run comparison."
        }

        $missingHosts = [System.Collections.Generic.List[string]]::new()
        foreach ($expected in $passHostFilter) {
            if ([string]::IsNullOrWhiteSpace($expected)) { continue }
            if (-not $passHostnames.Contains($expected)) {
                [void]$missingHosts.Add($expected)
            }
        }

        if ($missingHosts.Count -gt 0) {
            $message = ("Hostname filter required cold coverage for: {0}. Only saw: {1}" -f ([string]::Join(', ', $missingHosts.ToArray())), ([string]::Join(', ', $passHostnames)))
            if ($AllowPartialHostFilterCoverage.IsPresent) {
                Write-Warning $message
            } else {
                throw $message
            }
        }
    }

    $allowMissingBreakdown = $false
    if ($passMetricStatus -and $passMetricStatus.OptionalMissing -and $passMetricStatus.OptionalMissing.Contains('DatabaseWriteBreakdown')) {
        $allowMissingBreakdown = $true
    }

    if ($breakdownEvents -and $breakdownEvents.Count -gt 0) {
        $script:PassInterfaceAnalysis[$Label] = Measure-InterfaceCallDurationMetrics -Events @($breakdownEvents)
    } else {
        $script:PassInterfaceAnalysis[$Label] = $null
        if (-not $allowMissingBreakdown) {
            Write-Warning "No DatabaseWriteBreakdown events were captured for pass '$Label'."
        }
    }

    $syncEvents = @()
    if ($collection -and $collection.Buckets.ContainsKey('InterfaceSyncTiming')) {
        $syncEvents = @(Add-PassLabelToEvents -Events @($collection.Buckets['InterfaceSyncTiming']) -PassLabel $Label)
    }
    if ($passHostFilter -and $passHostFilter.Count -gt 0 -and $syncEvents) {
        $originalSyncCount = $syncEvents.Count
        $syncEvents = @(Filter-EventsByHostname -Events $syncEvents -AllowedHostnames $passHostFilter)
        $filteredSyncCount = $syncEvents.Count
        if ($originalSyncCount -ne $filteredSyncCount) {
            Write-Host ("Filtered InterfaceSyncTiming events for pass '{0}': {1} -> {2}." -f $Label, $originalSyncCount, $filteredSyncCount) -ForegroundColor DarkCyan
        }
    }

    $passResults = WarmRun.Telemetry\Resolve-SiteCacheProviderReasons -Summaries $passResults -DatabaseEvents $breakdownEvents -InterfaceSyncEvents $syncEvents
    $passResults = Merge-PerHostTelemetry -Summaries $passResults -DatabaseEvents $breakdownEvents -InterfaceSyncEvents $syncEvents

    if ($passMetricStatus -and $passMetricStatus.Statuses -and $passMetricStatus.Statuses.Count -gt 0) {
        $passResults = @($passResults + $passMetricStatus.Statuses)
    }
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

    $null = Get-DeviceRepositoryModule

    $refreshCount = 0
    foreach ($site in $Sites) {
        if ([string]::IsNullOrWhiteSpace($site)) { continue }
        try {
            $null = DeviceRepositoryModule\Get-InterfaceSiteCache -Site $site -Refresh
            $refreshCount++
        } catch {
            Write-Warning "Failed to refresh site cache for '$site': $($_.Exception.Message)"
        }
    }
    if ($refreshCount -le 0) { return @() }

    # LANDMARK: Telemetry buffer rename - resolve approved-verb command
    $flushCmd = Get-TelemetryModuleCommand -Name 'Save-StTelemetryBuffer'
    if ($flushCmd) {
        try { & $flushCmd | Out-Null } catch { }
    }
    $telemetry = Get-AppendedTelemetry -DirectoryPath $metricsDirectory -Baseline $metricsBaseline -ExcludePaths @($OutputPath)
    $siteSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($site in $Sites) {
        $siteValue = ('' + $site).Trim()
        if (-not [string]::IsNullOrWhiteSpace($siteValue)) {
            [void]$siteSet.Add($siteValue)
        }
    }

    $cacheMetrics = [System.Collections.Generic.List[psobject]]::new()
    foreach ($evt in @($telemetry)) {
        if (-not $evt) { continue }
        $eventNameProp = $evt.PSObject.Properties['EventName']
        if (-not $eventNameProp -or ('' + $eventNameProp.Value) -ne 'InterfaceSiteCacheMetrics') { continue }
        $siteProp = $evt.PSObject.Properties['Site']
        if (-not $siteProp) { continue }
        $siteValue = ('' + $siteProp.Value).Trim()
        if ([string]::IsNullOrWhiteSpace($siteValue)) { continue }
        if ($siteSet.Contains($siteValue)) {
            [void]$cacheMetrics.Add($evt)
        }
    }

    if ($cacheMetrics.Count -le 0) {
        Write-Warning 'No InterfaceSiteCacheMetrics events were captured during cache refresh.'
        return @()
    }

    return @(WarmRun.Telemetry\Convert-MetricsToSummary -PassLabel $Label -Metrics $cacheMetrics)
}

function Invoke-SiteCacheProbe {
    param(
        [Parameter(Mandatory)][string[]]$Sites,
        [Parameter(Mandatory)][string]$Label
    )

    if (-not $Sites -or $Sites.Count -eq 0) {
        return @()
    }

    $null = Get-DeviceRepositoryModule

    $probedSites = [System.Collections.Generic.List[string]]::new()
    $probedSiteSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($site in $Sites) {
        $siteValue = ('' + $site).Trim()
        if ([string]::IsNullOrWhiteSpace($siteValue)) { continue }
        try {
            $null = DeviceRepositoryModule\Get-InterfaceSiteCache -Site $siteValue
            if ($probedSiteSet.Add($siteValue)) {
                [void]$probedSites.Add($siteValue)
            }
        } catch {
            Write-Warning "Failed to probe site cache for '$siteValue': $($_.Exception.Message)"
        }
    }

    if ($probedSites.Count -le 0) {
        Write-Warning 'Site cache probe skipped because no sites were successfully probed.'
        return @()
    }

    # LANDMARK: Telemetry buffer rename - resolve approved-verb command
    $flushCmd = Get-TelemetryModuleCommand -Name 'Save-StTelemetryBuffer'
    if ($flushCmd) {
        try { & $flushCmd | Out-Null } catch { }
    }
    $telemetry = Get-AppendedTelemetry -DirectoryPath $metricsDirectory -Baseline $metricsBaseline -ExcludePaths @($OutputPath)
    $cacheMetrics = [System.Collections.Generic.List[psobject]]::new()
    foreach ($evt in @($telemetry)) {
        if (-not $evt) { continue }
        $eventNameProp = $evt.PSObject.Properties['EventName']
        if (-not $eventNameProp -or ('' + $eventNameProp.Value) -ne 'InterfaceSiteCacheMetrics') { continue }
        $siteProp = $evt.PSObject.Properties['Site']
        if (-not $siteProp) { continue }
        $siteValue = ('' + $siteProp.Value).Trim()
        if ([string]::IsNullOrWhiteSpace($siteValue)) { continue }
        if ($probedSiteSet.Contains($siteValue)) {
            [void]$cacheMetrics.Add($evt)
        }
    }

    if ($cacheMetrics.Count -le 0) {
        Write-Warning 'No InterfaceSiteCacheMetrics events were captured during the cache probe.'
        return @()
    }

    return @(WarmRun.Telemetry\Convert-MetricsToSummary -PassLabel $Label -Metrics $cacheMetrics)
}

function Get-SiteCacheState {
    param(
        [Parameter(Mandatory)][string[]]$Sites,
        [Parameter(Mandatory)][string]$Label
    )

    if (-not $Sites -or $Sites.Count -eq 0) {
        return @()
    }

    $module = Get-DeviceRepositoryModule
    if (-not $module) {
        Write-Warning 'Unable to inspect site cache state because DeviceRepositoryModule is not loaded.'
        return @()
    }

    $stateSummaries = [System.Collections.Generic.List[psobject]]::new()
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
                    $hostCountProp = $entry.PSObject.Properties['HostCount']
                    if ($hostCountProp) {
                        try { $hostCount = [int]$hostCountProp.Value } catch { $hostCount = 0 }
                    }

                    $totalRows = 0
                    $totalRowsProp = $entry.PSObject.Properties['TotalRows']
                    if ($totalRowsProp) {
                        try { $totalRows = [int]$totalRowsProp.Value } catch { $totalRows = 0 }
                    }

                    $hostMap = $null
                    $hostMapProp = $entry.PSObject.Properties['HostMap']
                    if ($hostMapProp) { $hostMap = $hostMapProp.Value }

                    if ($hostCount -le 0 -and $hostMap -is [System.Collections.IDictionary]) {
                        try { $hostCount = [int]$hostMap.Count } catch { $hostCount = 0 }
                    }

                    if ($totalRows -le 0 -and $hostMap -is [System.Collections.IDictionary]) {
                        foreach ($portMap in $hostMap.Values) {
                            if ($portMap -is [System.Collections.ICollection]) {
                                $totalRows += $portMap.Count
                            }
                        }
                    }

                    $cacheStatus = ''
                    $cacheStatusProp = $entry.PSObject.Properties['CacheStatus']
                    if ($cacheStatusProp) { $cacheStatus = '' + $cacheStatusProp.Value }

                    $cachedAt = $null
                    $cachedAtProp = $entry.PSObject.Properties['CachedAt']
                    if ($cachedAtProp) { $cachedAt = $cachedAtProp.Value }

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
            [void]$stateSummaries.Add($perSiteSummary)
        }
    }

    if ($stateSummaries.Count -le 0) {
        return @()
    }

    $now = Get-Date
    $cacheStateRows = [System.Collections.Generic.List[psobject]]::new()
    foreach ($state in $stateSummaries) {
        [void]$cacheStateRows.Add([pscustomobject]@{
            PassLabel                    = $Label
            Site                         = $state.Site
            Timestamp                    = $now
            CacheStatus                  = if ([string]::IsNullOrWhiteSpace($state.CacheStatus)) { $state.State } else { $state.CacheStatus }
            Provider                     = 'CacheState'
            HydrationDurationMs          = $null
            SnapshotDurationMs           = $null
            HostMapDurationMs            = $null
            HostCount                    = $state.HostCount
            TotalRows                    = $state.TotalRows
            HostMapSignatureMatchCount   = $null
            HostMapSignatureRewriteCount = $null
            HostMapCandidateMissingCount = $null
            HostMapCandidateFromPrevious = $null
            PreviousHostCount            = $null
            PreviousSnapshotStatus       = $state.State
            PreviousSnapshotHostMapType  = $null
            CacheStateDetails            = $state
        })
    }

    return $cacheStateRows.ToArray()
}

function ConvertTo-SharedCacheEntryArray {
    param([object]$Entries)

    $module = Get-DeviceRepositoryModule
    if ($module) {
        try {
            return @(DeviceRepositoryModule\ConvertTo-SharedCacheEntryArray -Entries $Entries)
        } catch [System.Management.Automation.CommandNotFoundException] {
        } catch { }
    }

    # Minimal fallback to keep shape stable when module helper is unavailable.
    if (-not $Entries) { return @() }
    if ($Entries -is [System.Collections.IList]) { return @($Entries) }
    return ,$Entries
}

function Write-SharedCacheSnapshot {
    param(
        [Parameter(Mandatory)][string]$Label
    )

    $module = Get-DeviceRepositoryModule
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

    $module = Get-DeviceRepositoryModule
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

    $module = Get-DeviceRepositoryModule
    if (-not $module) {
        Write-Warning 'Unable to capture shared cache entries because DeviceRepositoryModule is not loaded.'
        return @()
    }

    $entries = @()
    try {
        $entries = $module.Invoke(
            {
                param($sitesFallback, [bool]$verboseFlag)

                $normalizedFallbackSites = [System.Collections.Generic.List[string]]::new()
                foreach ($siteCandidate in @($sitesFallback)) {
                    if ([string]::IsNullOrWhiteSpace($siteCandidate)) { continue }
                    [void]$normalizedFallbackSites.Add(('' + $siteCandidate).Trim())
                }

                $result = [System.Collections.Generic.List[psobject]]::new()
                $seenSites = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

                $appendEntry = {
                    param([string]$siteKey, [psobject]$entryValue)

                    if ([string]::IsNullOrWhiteSpace($siteKey) -or -not $entryValue) { return }
                    $normalizedSite = $siteKey.Trim()
                    if ([string]::IsNullOrWhiteSpace($normalizedSite)) { return }
                    if ($seenSites.Contains($normalizedSite)) { return }

                    [void]$result.Add([pscustomobject]@{ Site = $normalizedSite; Entry = $entryValue })
                    [void]$seenSites.Add($normalizedSite)
                }

                $snapshotEntries = @()
                $cacheSnapshotCmd = $null
                try { $cacheSnapshotCmd = script:Get-DeviceRepositoryCacheCommand -Name 'Get-SharedSiteInterfaceCacheSnapshotEntries' } catch { $cacheSnapshotCmd = $null }
                if ($cacheSnapshotCmd) {
                    try { $snapshotEntries = @(& $cacheSnapshotCmd) } catch { $snapshotEntries = @() }
                }
                if (-not $snapshotEntries -or $snapshotEntries.Count -eq 0) {
                    try { $snapshotEntries = @(Get-SharedSiteInterfaceCacheSnapshotEntries) } catch { $snapshotEntries = @() }
                }
                foreach ($snapshotEntry in $snapshotEntries) {
                    if (-not $snapshotEntry) { continue }
                    $snapshotSite = $null
                    $snapshotSiteProp = $snapshotEntry.PSObject.Properties['Site']
                    if ($snapshotSiteProp) {
                        $snapshotSite = ('' + $snapshotSiteProp.Value).Trim()
                    } else {
                        $snapshotSiteKeyProp = $snapshotEntry.PSObject.Properties['SiteKey']
                        if ($snapshotSiteKeyProp) {
                            $snapshotSite = ('' + $snapshotSiteKeyProp.Value).Trim()
                        }
                    }
                    if ([string]::IsNullOrWhiteSpace($snapshotSite)) { continue }
                    $snapshotValue = $snapshotEntry
                    $snapshotValueProp = $snapshotEntry.PSObject.Properties['Entry']
                    if ($snapshotValueProp) { $snapshotValue = $snapshotValueProp.Value }
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
                    $storeSummary = [System.Collections.Generic.List[psobject]]::new()
                    if ($store -is [System.Collections.IDictionary]) {
                        foreach ($key in @($store.Keys)) {
                            $hostCount = 0
                            $rowSum = 0
                            try {
                                $entry = Get-SharedSiteInterfaceCacheEntry -SiteKey $key
                                if ($entry -and $entry.HostMap -is [System.Collections.IDictionary]) {
                                    try { $hostCount = [int]$entry.HostMap.Count } catch { $hostCount = 0 }
                                    foreach ($map in $entry.HostMap.Values) {
                                        if ($map -is [System.Collections.IDictionary]) {
                                            $rowSum += $map.Count
                                        }
                                    }
                                }
                            } catch { }
                            [void]$storeSummary.Add([pscustomobject]@{ Site = $key; HostCount = $hostCount; TotalRows = $rowSum })
                        }
                    }
                    if ($storeSummary.Count -gt 0) {
                        $summaryItems = [System.Collections.Generic.List[string]]::new()
                        foreach ($summaryEntry in $storeSummary) {
                            if (-not $summaryEntry) { continue }
                            $siteValue = ''
                            $siteProp = $summaryEntry.PSObject.Properties['Site']
                            if ($siteProp) { $siteValue = ('' + $siteProp.Value).Trim() }
                            if ([string]::IsNullOrWhiteSpace($siteValue)) { continue }
                            $hostValue = 0
                            $rowsValue = 0
                            $hostProp = $summaryEntry.PSObject.Properties['HostCount']
                            if ($hostProp) { try { $hostValue = [int]$hostProp.Value } catch { $hostValue = 0 } }
                            $rowsProp = $summaryEntry.PSObject.Properties['TotalRows']
                            if ($rowsProp) { try { $rowsValue = [int]$rowsProp.Value } catch { $rowsValue = 0 } }
                            [void]$summaryItems.Add(('{0}:hosts={1},rows={2}' -f $siteValue, $hostValue, $rowsValue))
                        }
                        $summaryText = ''
                        if ($summaryItems.Count -gt 1) {
                            $sortedItems = $summaryItems.ToArray()
                            [array]::Sort($sortedItems, [System.StringComparer]::OrdinalIgnoreCase)
                            $summaryText = [string]::Join('; ', $sortedItems)
                        } elseif ($summaryItems.Count -eq 1) {
                            $summaryText = $summaryItems[0]
                        }
                        if (-not [string]::IsNullOrWhiteSpace($summaryText)) {
                            Write-Host ("Shared cache store snapshot (pre-export): {0}" -f $summaryText) -ForegroundColor DarkCyan
                        } else {
                            Write-Host 'Shared cache store snapshot (pre-export): empty or unavailable.' -ForegroundColor DarkYellow
                        }
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
                        if (-not $entry) { continue }
                        $entryValueProp = $entry.PSObject.Properties['Entry']
                        if (-not $entryValueProp -or -not $entryValueProp.Value) { continue }
                        $entryValue = $entryValueProp.Value
                        $hostCount = 0
                        $totalRows = 0
                        $hostCountProp = $entryValue.PSObject.Properties['HostCount']
                        if ($hostCountProp) {
                            try { $hostCount = [int]$hostCountProp.Value } catch { $hostCount = 0 }
                        }
                        $totalRowsProp = $entryValue.PSObject.Properties['TotalRows']
                        if ($totalRowsProp) {
                            try { $totalRows = [int]$totalRowsProp.Value } catch { $totalRows = 0 }
                        }
                        $hostMap = $null
                        $hostMapProp = $entryValue.PSObject.Properties['HostMap']
                        if ($hostMapProp) { $hostMap = $hostMapProp.Value }
                        if ($hostCount -le 0 -and $hostMap -is [System.Collections.IDictionary]) {
                            try { $hostCount = [int]$hostMap.Count } catch { $hostCount = 0 }
                            foreach ($map in $hostMap.Values) {
                                if ($map -is [System.Collections.IDictionary]) {
                                    try { $totalRows += $map.Count } catch { }
                                }
                            }
                        }
                        $cacheStatus = ''
                        $cacheStatusProp = $entryValue.PSObject.Properties['CacheStatus']
                        if ($cacheStatusProp) {
                            try { $cacheStatus = '' + $cacheStatusProp.Value } catch { $cacheStatus = '' }
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

    # Prefer the cache module export (keeps format aligned) when the module is available.
    $siteFilter = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $entryArray) {
        if (-not $entry) { continue }
        $siteValue = Get-TrimmedSiteKey -InputObject $entry
        if (-not [string]::IsNullOrWhiteSpace($siteValue)) { [void]$siteFilter.Add($siteValue) }
    }

    $cacheModule = Get-Module -Name 'DeviceRepository.Cache' -ErrorAction SilentlyContinue
    if (-not $cacheModule) {
        try {
            $cachePath = Join-Path -Path $repositoryRoot -ChildPath 'Modules\DeviceRepository.Cache.psm1'
            if (Test-Path -LiteralPath $cachePath) {
                $cacheModule = Import-Module -Name $cachePath -PassThru -ErrorAction SilentlyContinue
            }
        } catch { }
    }
    if ($cacheModule) {
        $cacheExport = Get-DeviceRepositoryCacheCommand -Name 'Export-SharedCacheSnapshot'
        if ($cacheExport) {
            try {
                $args = @{ OutputPath = $Path }
                if ($siteFilter.Count -gt 0) { $args['SiteFilter'] = $siteFilter.ToArray() }
                $null = & $cacheExport @args
                return
            } catch {
                Write-Verbose ("Shared cache snapshot export via DeviceRepository.Cache failed: {0}" -f $_.Exception.Message)
            }
        }
        $fallbackWriter = Get-DeviceRepositoryCacheCommand -Name 'Write-SharedCacheSnapshotFileFallback'
        if ($fallbackWriter) {
            try {
                & $fallbackWriter -Path $Path -Entries $entryArray
                return
            } catch {
                Write-Verbose ("Shared cache snapshot fallback export via DeviceRepository.Cache failed: {0}" -f $_.Exception.Message)
            }
        }
    }

    $sanitizedEntries = $null
    try { $sanitizedEntries = @(DeviceRepositoryModule\Resolve-SharedSiteInterfaceCacheSnapshotEntries -Entries $entryArray -RehydrateMissingEntries) } catch { $sanitizedEntries = $null }
    if (-not $sanitizedEntries) {
        $sanitizedEntries = [System.Collections.Generic.List[psobject]]::new()

        foreach ($entry in $entryArray) {
            if (-not $entry) { continue }

            $siteValue = Get-TrimmedSiteKey -InputObject $entry
            if ([string]::IsNullOrWhiteSpace($siteValue)) { continue }

            $entryValue = $null
            $entryValueProp = $entry.PSObject.Properties['Entry']
            if ($entryValueProp) {
                $entryValue = $entryValueProp.Value
            }

            $shouldRefresh = $false
            if (-not $entryValue) {
                $shouldRefresh = $true
            } else {
                $hostCountProp = $entryValue.PSObject.Properties['HostCount']
                if ($hostCountProp) {
                    try {
                        if ([int]$hostCountProp.Value -le 0) { $shouldRefresh = $true }
                    } catch { }
                }
            }
            if ($shouldRefresh) {
                try { $entryValue = DeviceRepositoryModule\Get-InterfaceSiteCache -Site $siteValue -Refresh } catch { $entryValue = $entryValue }
            }
            if (-not $entryValue) {
                Write-Warning ("Shared cache snapshot entry for site '{0}' is missing cache data and will be skipped." -f $siteValue)
                continue
            }

            [void]$sanitizedEntries.Add([pscustomobject]@{
                Site  = $siteValue
                Entry = $entryValue
            })
        }
    }

    try {
        $null = Initialize-DirectoryForPath -Path $Path
        if ($sanitizedEntries.Count -eq 0) {
            Write-Warning 'Shared cache snapshot contained no valid site entries; exporting empty snapshot.'
        }
        Export-Clixml -InputObject $sanitizedEntries.ToArray() -Path $Path -Depth 20
    } catch {
        Write-Warning ("Failed to write shared cache snapshot to '{0}': {1}" -f $Path, $_.Exception.Message)
    }
}

function New-EmptySharedCacheSnapshotFile {
    param([Parameter(Mandatory)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $null = Initialize-DirectoryForPath -Path $Path
    try {
        @() | Export-Clixml -Path $Path
        return $Path
    } catch {
        Write-Warning ("Failed to write empty shared cache snapshot '{0}': {1}" -f $Path, $_.Exception.Message)
        return $null
    }
}

function Sync-SharedCacheSnapshotPointer {
    param(
        [Parameter(Mandatory)][string]$SnapshotPath,
        [string]$LatestPath
    )

    if ([string]::IsNullOrWhiteSpace($SnapshotPath)) { return $false }
    if (-not (Test-Path -LiteralPath $SnapshotPath)) { return $false }

    if (-not [string]::IsNullOrWhiteSpace($LatestPath) -and
        -not [System.StringComparer]::OrdinalIgnoreCase.Equals($SnapshotPath, $LatestPath)) {
        try {
            $null = Initialize-DirectoryForPath -Path $LatestPath
            Copy-Item -LiteralPath $SnapshotPath -Destination $LatestPath -Force
        } catch {
            Write-Warning ("Failed to update shared cache snapshot pointer '{0}': {1}" -f $LatestPath, $_.Exception.Message)
        }
    }

    return $true
}

function Restore-SharedCacheEntries {
    param(
        # LANDMARK: Shared cache restore - accept single-entry snapshot payloads
        [object]$Entries
    )

    if (-not $Entries) { return 0 }

    $entryArray = ConvertTo-SharedCacheEntryArray -Entries $Entries
    if (-not $entryArray -or $entryArray.Count -eq 0) { return 0 }

    $validEntries = [System.Collections.Generic.List[psobject]]::new()
    foreach ($entry in $entryArray) {
        if (-not $entry) { continue }

        $siteName = Get-TrimmedSiteKey -InputObject $entry
        if ([string]::IsNullOrWhiteSpace($siteName)) { continue }

        $entryValue = $null
        $entryValueProp = $entry.PSObject.Properties['Entry']
        if ($entryValueProp) {
            $entryValue = $entryValueProp.Value
        } else {
            $hostMapProp = $entry.PSObject.Properties['HostMap']
            if ($hostMapProp -and $hostMapProp.Value) {
                $entryValue = $entry
            }
        }
        if (-not $entryValue) {
            Write-Warning ("Shared cache snapshot entry for site '{0}' is missing cache data and will be ignored during restore." -f $siteName)
            continue
        }

        [void]$validEntries.Add([pscustomobject]@{
            Site  = $siteName
            Entry = $entryValue
        })
    }

    if ($validEntries.Count -eq 0) {
        Write-Warning 'No valid shared cache entries were available to restore.'
        return 0
    }

    $sitesToWarm = [System.Collections.Generic.List[string]]::new()
    $siteSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $siteEntryTable = @{}
    foreach ($entry in $validEntries) {
        $siteName = ('' + $entry.Site).Trim()
        if ([string]::IsNullOrWhiteSpace($siteName)) { continue }
        if ($siteSet.Add($siteName)) {
            [void]$sitesToWarm.Add($siteName)
        }
        $entryValue = $entry.Entry
        if ($entryValue) {
            $siteEntryTable[$siteName] = $entryValue
        }
    }

    $module = Get-DeviceRepositoryModule
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
                $siteProp = $item.PSObject.Properties['Site']
                if ($siteProp) { $siteKey = ('' + $siteProp.Value).Trim() }
                if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }
                $entryValue = $null
                $entryProp = $item.PSObject.Properties['Entry']
                if ($entryProp) { $entryValue = $entryProp.Value }
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
                $siteProp = $item.PSObject.Properties['Site']
                if ($siteProp) { $siteKey = ('' + $siteProp.Value).Trim() }
                if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }
                try { $null = Get-InterfaceSiteCache -Site $siteKey } catch {
                    Write-Warning ("Failed to hydrate interface site cache for '{0}': {1}" -f $siteKey, $_.Exception.Message)
                }
            }

            return $restored
        },
        @{ EntryList = $validEntries.ToArray() }
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
                    $null = ParserRunspaceModule\Invoke-InterfaceSiteCacheWarmup -Sites $sitesToWarm.ToArray() -SiteEntries $siteEntryTable
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

if ($IncludeTests) {
    Write-Host 'Running Pester tests (Modules/Tests)...' -ForegroundColor Yellow
    $pesterDisableEnvOriginal = $null
    $pesterDisableEnvHadValue = $false
    try {
        $pesterDisableEnvOriginal = $env:STATETRACE_DISABLE_SHARED_CACHE
        if ($null -ne $pesterDisableEnvOriginal) {
            $pesterDisableEnvHadValue = $true
        }
    } catch {
        $pesterDisableEnvOriginal = $null
        $pesterDisableEnvHadValue = $false
    }

    try { Remove-Item Env:STATETRACE_DISABLE_SHARED_CACHE -ErrorAction SilentlyContinue } catch { }
    $pesterResult = Invoke-Pester Modules/Tests -PassThru
    try {
        if ($pesterDisableEnvHadValue) {
            $env:STATETRACE_DISABLE_SHARED_CACHE = $pesterDisableEnvOriginal
        } else {
            Remove-Item Env:STATETRACE_DISABLE_SHARED_CACHE -ErrorAction SilentlyContinue
        }
    } catch { }

    if ($pesterResult.FailedCount -gt 0) {
        throw "Pester reported $($pesterResult.FailedCount) failing tests."
    }
    $pipelineArguments['SkipTests'] = $true
}

try {
    if (-not $PreserveSkipSiteCacheSetting.IsPresent) {
        $skipSiteCacheGuard = Disable-SkipSiteCacheUpdateSetting -SettingsPath $settingsPath -Label 'WarmRunTelemetry'
    }
    if (-not $sharedCacheSnapshotPath) {
        $snapshotFileName = "SharedCacheSnapshot-{0:yyyyMMdd-HHmmss}.clixml" -f (Get-Date)
        $sharedCacheSnapshotPath = Join-Path -Path $sharedCacheSnapshotDirectory -ChildPath $snapshotFileName
        $sharedCacheSnapshotCleanupPath = $sharedCacheSnapshotPath
        $null = Initialize-DirectoryForPath -Path $sharedCacheSnapshotPath
    }
    $pipelineArguments['SharedCacheSnapshotExportPath'] = $sharedCacheSnapshotPath
    $coldSharedCacheSnapshotPath = $null
    if (-not $DisableSharedCacheSnapshot.IsPresent) {
        $coldSnapshotName = "SharedCacheSnapshot-ColdEmpty-{0:yyyyMMdd-HHmmss}.clixml" -f (Get-Date)
        $coldSharedCacheSnapshotPath = Join-Path -Path $sharedCacheSnapshotDirectory -ChildPath $coldSnapshotName
        $coldSharedCacheSnapshotPath = New-EmptySharedCacheSnapshotFile -Path $coldSharedCacheSnapshotPath
        if ($coldSharedCacheSnapshotPath) {
            $coldSharedCacheSnapshotCleanupPath = $coldSharedCacheSnapshotPath
            $pipelineArguments['SharedCacheSnapshotPath'] = $coldSharedCacheSnapshotPath
            Write-Host ("Cold pass shared cache snapshot placeholder created at '{0}'." -f $coldSharedCacheSnapshotPath) -ForegroundColor DarkCyan
        }
    }
    $sharedCacheSnapshotEnvTarget = $sharedCacheSnapshotPath
    if ($coldSharedCacheSnapshotPath) {
        $sharedCacheSnapshotEnvTarget = $coldSharedCacheSnapshotPath
    }
    if (-not $sharedCacheSnapshotEnvApplied -and $sharedCacheSnapshotEnvTarget) {
        try { $sharedCacheSnapshotEnvOriginal = $env:STATETRACE_SHARED_CACHE_SNAPSHOT } catch { $sharedCacheSnapshotEnvOriginal = $null }
        try {
            $env:STATETRACE_SHARED_CACHE_SNAPSHOT = $sharedCacheSnapshotEnvTarget
            $sharedCacheSnapshotEnvApplied = $true
        } catch {
            $sharedCacheSnapshotEnvApplied = $false
        }
    }
    if (-not $sharedCacheDisableEnvApplied) {
        try { $sharedCacheDisableEnvOriginal = $env:STATETRACE_DISABLE_SHARED_CACHE } catch { $sharedCacheDisableEnvOriginal = $null }
        try {
            $env:STATETRACE_DISABLE_SHARED_CACHE = '1'
            $sharedCacheDisableEnvApplied = $true
        } catch {
            $sharedCacheDisableEnvApplied = $false
        }
    }
    if ($sharedCacheDisableEnvApplied) {
        $cacheClearCommand = Get-DeviceRepositoryCacheCommand -Name 'Clear-SharedSiteInterfaceCache'
        if (-not $cacheClearCommand) {
            try {
                $cacheModulePath = Join-Path -Path $repositoryRoot -ChildPath 'Modules\DeviceRepository.Cache.psm1'
                if (Test-Path -LiteralPath $cacheModulePath) {
                    Import-Module -Name $cacheModulePath -Force -ErrorAction SilentlyContinue | Out-Null
                }
            } catch { }
            $cacheClearCommand = Get-DeviceRepositoryCacheCommand -Name 'Clear-SharedSiteInterfaceCache'
        }
        if ($cacheClearCommand) {
            try { & $cacheClearCommand -Reason 'WarmRunTelemetryColdPass' } catch { }
        }
    }
    Set-IngestionHistoryForPass -SeedMode $ColdHistorySeed -Snapshot $ingestionHistorySnapshot -PassLabel 'ColdPass'
    $results.AddRange([psobject[]]@(Invoke-PipelinePass -Label 'ColdPass' -HistorySeedMode $ColdHistorySeed))

    if ($pipelineArguments.ContainsKey('SharedCacheSnapshotPath')) {
        $pipelineArguments.Remove('SharedCacheSnapshotPath')
    }
    if ($pipelineArguments.ContainsKey('SharedCacheSnapshotExportPath')) {
        $pipelineArguments.Remove('SharedCacheSnapshotExportPath')
    }
    if ($sharedCacheDisableEnvApplied) {
        try {
            if ($null -ne $sharedCacheDisableEnvOriginal) {
                $env:STATETRACE_DISABLE_SHARED_CACHE = $sharedCacheDisableEnvOriginal
            } else {
                Remove-Item Env:STATETRACE_DISABLE_SHARED_CACHE -ErrorAction SilentlyContinue
            }
        } catch { }
        $sharedCacheDisableEnvApplied = $false
    }
    Write-SharedCacheSnapshot -Label 'PostColdPass'
    $postColdSummary = Get-SharedCacheSummary -Label 'SharedCacheState:PostColdPass'
    if ($postColdSummary) {
        $results.AddRange([psobject[]]@($postColdSummary))
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
            $results.AddRange([psobject[]]@($postColdProbe))
        }
    }
    $usingExportedSnapshot = $false
    $capturedAfterCold = 0
    if ($sharedCacheSnapshotPath -and (Test-Path -LiteralPath $sharedCacheSnapshotPath)) {
        try {
            $sharedCacheEntries = ConvertTo-SharedCacheEntryArray -Entries (Import-Clixml -Path $sharedCacheSnapshotPath)
            $capturedAfterCold = Get-NonNullItemCount -Items $sharedCacheEntries
            if ($capturedAfterCold -gt 0) {
                $usingExportedSnapshot = $true
            } else {
                $sharedCacheEntries = @()
                $capturedAfterCold = 0
            }
        } catch {
            Write-Warning ("Failed to import shared cache snapshot exported by the cold pass: {0}" -f $_.Exception.Message)
            $sharedCacheEntries = @()
            $capturedAfterCold = 0
        }
    }
    if ($SiteExistingRowCacheSnapshotPath -and (Test-Path -LiteralPath $SiteExistingRowCacheSnapshotPath)) {
        Restore-SiteExistingRowCacheSnapshot -SnapshotPath $SiteExistingRowCacheSnapshotPath
    }
    if ($capturedAfterCold -le 0) {
        $sharedCacheEntries = ConvertTo-SharedCacheEntryArray -Entries (Get-SharedCacheEntriesSnapshot -FallbackSites $initialSiteCandidates)
        $capturedAfterCold = Get-NonNullItemCount -Items $sharedCacheEntries
    }

    try {
        Write-Host 'Capturing ingestion history produced by cold pass for potential warm-run reuse...' -ForegroundColor Yellow
        $postColdSnapshot = Get-IngestionHistorySnapshot -DirectoryPath $ingestionHistoryDir
    } catch {
        Write-Warning "Failed to capture post-cold ingestion history snapshot. $($_.Exception.Message)"
    }

    $backupSnapshot = $postColdSnapshot
    if (-not $backupSnapshot) { $backupSnapshot = $ingestionHistorySnapshot }
    if ($backupSnapshot) {
        # LANDMARK: Warm-run backup seed - snapshot ingestion history after cold pass
        $null = Write-IngestionHistoryWarmRunBackups -DirectoryPath $ingestionHistoryDir -Snapshot $backupSnapshot -Label 'PostColdPass'
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
            $capturedAfterCold = Get-NonNullItemCount -Items $sharedCacheEntries
        }
    }

    if ($sharedCacheSnapshotPath) {
        if (-not $usingExportedSnapshot) {
            Write-SharedCacheSnapshotFile -Path $sharedCacheSnapshotPath -Entries @($sharedCacheEntries)
            Write-Host ("Shared cache snapshot saved to '{0}'." -f $sharedCacheSnapshotPath) -ForegroundColor DarkCyan
        }
        # LANDMARK: Shared cache snapshot pointer - update latest after cold export
        $snapshotReady = Sync-SharedCacheSnapshotPointer -SnapshotPath $sharedCacheSnapshotPath -LatestPath $sharedCacheSnapshotLatestPath
        if (-not $snapshotReady) {
            if ($sharedCacheSnapshotLatestPath -and (Test-Path -LiteralPath $sharedCacheSnapshotLatestPath)) {
                Write-Warning ("Shared cache snapshot '{0}' was not created; falling back to '{1}'." -f $sharedCacheSnapshotPath, $sharedCacheSnapshotLatestPath)
                $sharedCacheSnapshotPath = $sharedCacheSnapshotLatestPath
                if ($sharedCacheSnapshotEnvApplied) {
                    try { $env:STATETRACE_SHARED_CACHE_SNAPSHOT = $sharedCacheSnapshotPath } catch { }
                }
            } else {
                Write-Warning ("Shared cache snapshot '{0}' was not created and no fallback snapshot was found." -f $sharedCacheSnapshotPath)
            }
        }
    }
    if ($capturedAfterCold -gt 0) {
        Write-Host ("Captured {0} shared cache entr{1} after cold pass." -f $capturedAfterCold, $(if ($capturedAfterCold -eq 1) { 'y' } else { 'ies' })) -ForegroundColor DarkCyan
    } else {
        Write-Warning 'Shared cache snapshot after cold pass contained no entries.'
    }
    try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::ClearSnapshot() } catch { }
    [void]$results.Add([pscustomobject]@{
        PassLabel   = 'SharedCacheSnapshot:PostColdPass'
        Timestamp   = Get-Date
        EntryCount  = $capturedAfterCold
        SourceStage = 'ColdPass'
    })

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
                    $results.AddRange([psobject[]]@($warmRefreshResults))
                }
                Write-SharedCacheSnapshot -Label 'PostRefresh'
                $postRefreshSummary = Get-SharedCacheSummary -Label 'SharedCacheState:PostRefresh'
                if ($postRefreshSummary) {
                    $results.AddRange([psobject[]]@($postRefreshSummary))
                }
                Write-Host 'Recording site cache state after refresh...' -ForegroundColor Cyan
                $cacheStateAfterRefresh = Get-SiteCacheState -Sites $sitesForRefresh -Label 'CacheState:PostRefresh'
                if ($cacheStateAfterRefresh) {
                    $count = $cacheStateAfterRefresh.Count
                    Write-Host ("Cache state entries after refresh: {0}" -f $count) -ForegroundColor DarkCyan
                    if ($count -gt 0) {
                        Write-Host ("  -> {0}" -f (Format-SiteCacheStatusText -CacheStates $cacheStateAfterRefresh)) -ForegroundColor DarkCyan
                    }
                    $results.AddRange([psobject[]]@($cacheStateAfterRefresh))
                }
                Write-Host 'Probing site caches after refresh to verify cache entries persisted...' -ForegroundColor Cyan
                $probeResults = Invoke-SiteCacheProbe -Sites $sitesForRefresh -Label 'CacheProbe'
                if ($probeResults -and $probeResults.Count -gt 0) {
                    $results.AddRange([psobject[]]@($probeResults))
                }
                Write-Host 'Warming preserved parser runspaces with refreshed site caches...' -ForegroundColor Cyan
                $refreshedEntries = ConvertTo-SharedCacheEntryArray -Entries (Get-SharedCacheEntriesSnapshot -FallbackSites $sitesForRefresh)
                $refreshedEntryCount = Get-NonNullItemCount -Items $refreshedEntries
                $refreshEntryTable = @{}
                foreach ($entry in $refreshedEntries) {
                    if (-not $entry) { continue }
                    $siteKey = Get-TrimmedSiteKey -InputObject $entry
                    if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }
                    $entryValueProp = $entry.PSObject.Properties['Entry']
                    if ($entryValueProp -and $entryValueProp.Value) {
                        $refreshEntryTable[$siteKey] = $entryValueProp.Value
                    }
                }
                try {
                    ParserRunspaceModule\Invoke-InterfaceSiteCacheWarmup -Sites $sitesForRefresh -Refresh -SiteEntries $refreshEntryTable
                } catch {
                    Write-Warning "Failed to warm parser runspace caches: $($_.Exception.Message)"
                }
                if ($refreshedEntryCount -gt 0) {
                    $sharedCacheEntries = $refreshedEntries
                    if ($sharedCacheSnapshotPath) {
                        Write-SharedCacheSnapshotFile -Path $sharedCacheSnapshotPath -Entries @($sharedCacheEntries)
                        Write-Host ("Updated shared cache snapshot at '{0}' with refreshed entries." -f $sharedCacheSnapshotPath) -ForegroundColor DarkCyan     
                        $null = Sync-SharedCacheSnapshotPointer -SnapshotPath $sharedCacheSnapshotPath -LatestPath $sharedCacheSnapshotLatestPath
                    }
                } else {
                    Write-Warning 'Shared cache snapshot after refresh contained no entries; retaining pre-refresh entries.'
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
        $capturedAfterRefresh = Get-NonNullItemCount -Items $sharedCacheEntries
        if ($capturedAfterRefresh -gt 0) {
            Write-Host ("Captured {0} shared cache entr{1} after refresh." -f $capturedAfterRefresh, $(if ($capturedAfterRefresh -eq 1) { 'y' } else { 'ies' })) -ForegroundColor DarkCyan
        } else {
            Write-Warning 'Shared cache snapshot after refresh contained no entries.'
        }
        [void]$results.Add([pscustomobject]@{
            PassLabel   = 'SharedCacheSnapshot:PostRefresh'
            Timestamp   = Get-Date
            EntryCount  = $capturedAfterRefresh
            SourceStage = 'PostRefresh'
        })
    }

    $sharedCacheSiteSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($sharedCacheEntries)) {
        if (-not $entry) { continue }

        $siteValue = Get-TrimmedSiteKey -InputObject $entry
        if (-not [string]::IsNullOrWhiteSpace($siteValue)) {
            [void]$sharedCacheSiteSet.Add($siteValue)
        }
    }

    $sharedCacheSites = @($sharedCacheSiteSet)
    if ($sharedCacheSites.Count -gt 1) {
        [array]::Sort($sharedCacheSites, [System.StringComparer]::OrdinalIgnoreCase)
    }

    if ($sharedCacheSites.Count -gt 0) {
        Write-Host ("Shared cache snapshot sites available for warm pass: {0}" -f ([string]::Join(', ', $sharedCacheSites))) -ForegroundColor DarkCyan
    } else {
        Write-Warning 'Shared cache snapshot did not include any site keys.'
    }

    $warmRunSiteSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($existingSite in @($script:WarmRunSites)) {
        if ([string]::IsNullOrWhiteSpace($existingSite)) { continue }
        [void]$warmRunSiteSet.Add($existingSite.Trim())
    }
    foreach ($entry in @($sharedCacheEntries)) {
        if (-not $entry) { continue }
        $siteKey = Get-TrimmedSiteKey -InputObject $entry
        if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }
        [void]$warmRunSiteSet.Add($siteKey)
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
        $warmRunSites = @($warmRunSiteSet)
        if ($warmRunSites.Count -gt 1) {
            [array]::Sort($warmRunSites, [System.StringComparer]::OrdinalIgnoreCase)
        }
        $script:WarmRunSites = $warmRunSites
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
    } elseif ((Get-NonNullItemCount -Items $sharedCacheEntries) -gt 0) {
        Write-Warning 'Cached site entries were captured after the cold pass but none were restored before the warm pass.'
    }
    [void]$results.Add([pscustomobject]@{
        PassLabel    = 'SharedCacheRestore:PreWarmPass'
        Timestamp    = Get-Date
        RestoredCount= $restoredCacheCount
    })
    $postRestoreSummary = Get-SharedCacheSummary -Label 'SharedCacheState:PostRestore'
    if ($postRestoreSummary) {
        $results.AddRange([psobject[]]@($postRestoreSummary))
    }
    if ($script:WarmRunSites -and $script:WarmRunSites.Count -gt 0) {
        Write-Host ("Preparing cache state check for sites: {0}" -f ([string]::Join(', ', $script:WarmRunSites))) -ForegroundColor DarkCyan
        Write-Host 'Recording site cache state before warm pass...' -ForegroundColor Cyan
        $preWarmSummary = Get-SharedCacheSummary -Label 'SharedCacheState:PreWarmPass'
        if ($preWarmSummary) {
            $results.AddRange([psobject[]]@($preWarmSummary))
        }
        $cacheStatePreWarm = Get-SiteCacheState -Sites $script:WarmRunSites -Label 'CacheState:PreWarmPass'
        if ($cacheStatePreWarm) {
            $count = $cacheStatePreWarm.Count
            Write-Host ("Cache state entries before warm pass: {0}" -f $count) -ForegroundColor DarkCyan
            if ($count -gt 0) {
                Write-Host ("  -> {0}" -f (Format-SiteCacheStatusText -CacheStates $cacheStatePreWarm)) -ForegroundColor DarkCyan
            }
            $results.AddRange([psobject[]]@($cacheStatePreWarm))
        }

        try {
            $preWarmEntries = Get-SharedCacheEntriesSnapshot -FallbackSites $script:WarmRunSites
            if ($preWarmEntries -and $preWarmEntries.Count -gt 0) {
                $hostSummary = Format-SharedCacheSummaryText -Entries $preWarmEntries
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
            $runspaceSharedCache = Add-PassLabelToEvents -Events @($runspaceSharedCache) -PassLabel 'SharedCacheState:PreservedRunspace'
            $results.AddRange([psobject[]]@($runspaceSharedCache))
            $runspaceSharedText = Format-SharedCacheSummaryText -Entries $runspaceSharedCache
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
                        $siteKey = Get-TrimmedSiteKey -InputObject $entry
                        if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }
                        $payload = $entry
                        $payloadProp = $entry.PSObject.Properties['Entry']
                        if ($payloadProp) { $payload = $payloadProp.Value }
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
                $postSeedText = Format-SharedCacheSummaryText -Entries $postSeedSummary
                Write-Host ("Preserved runspace shared cache after seeding: {0}" -f $postSeedText) -ForegroundColor DarkCyan
                $results.AddRange([psobject[]]@(Add-PassLabelToEvents -Events @($postSeedSummary) -PassLabel 'SharedCacheState:PreservedRunspacePostSeed'))
            } else {
                Write-Host 'Preserved runspace shared cache after seeding: empty or unavailable.' -ForegroundColor DarkYellow
            }
        } else {
            Write-Host 'No shared cache entries available to seed into preserved runspace pool.' -ForegroundColor DarkYellow
        }
    } catch {
        Write-Warning ("Failed to seed preserved runspace shared cache: {0}" -f $_.Exception.Message)
    }
    # Advance the telemetry baseline so WarmPass collection excludes pre-warm cache work.
    $metricsBaseline = Get-MetricsBaseline -DirectoryPath $metricsDirectory
    Write-Host ("[Diag] WarmPass starting at {0:o}" -f (Get-Date)) -ForegroundColor Magenta
    $results.AddRange([psobject[]]@(Invoke-PipelinePass -Label 'WarmPass' -HistorySeedMode $warmSeedMode))
    Write-Host ("[Diag] WarmPass completed at {0:o}" -f (Get-Date)) -ForegroundColor Magenta
} finally {
    $restoreStart = Get-Date
    Write-Host ("[Diag] Restoring ingestion history to original snapshot... ({0:o})" -f $restoreStart) -ForegroundColor Yellow
    Restore-IngestionHistory -Snapshot $ingestionHistorySnapshot
    Write-Host ("[Diag] Ingestion history restore completed in {0:N0} ms" -f ((Get-Date) - $restoreStart).TotalMilliseconds) -ForegroundColor Magenta
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
    if ($sharedCacheDisableEnvApplied) {
        try {
            if ($null -ne $sharedCacheDisableEnvOriginal) {
                $env:STATETRACE_DISABLE_SHARED_CACHE = $sharedCacheDisableEnvOriginal
            } else {
                Remove-Item Env:STATETRACE_DISABLE_SHARED_CACHE -ErrorAction SilentlyContinue
            }
        } catch { }
        $sharedCacheDisableEnvApplied = $false
    }
    $cleanupPath = $sharedCacheSnapshotCleanupPath
    if (-not $cleanupPath -and $sharedCacheSnapshotPath -and
        -not [System.StringComparer]::OrdinalIgnoreCase.Equals($sharedCacheSnapshotPath, $sharedCacheSnapshotLatestPath)) {
        $cleanupPath = $sharedCacheSnapshotPath
    }
    if (-not $PreserveSharedCacheSnapshot.IsPresent -and $cleanupPath -and (Test-Path -LiteralPath $cleanupPath)) {
        try { Remove-Item -LiteralPath $cleanupPath -Force } catch { }
    } elseif ($PreserveSharedCacheSnapshot.IsPresent -and $sharedCacheSnapshotPath) {
        Write-Host ("Preserved shared cache snapshot at '{0}' for inspection." -f $sharedCacheSnapshotPath) -ForegroundColor DarkCyan
    }
    if ($coldSharedCacheSnapshotCleanupPath -and (Test-Path -LiteralPath $coldSharedCacheSnapshotCleanupPath)) {
        try { Remove-Item -LiteralPath $coldSharedCacheSnapshotCleanupPath -Force } catch { }
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
        $normalizedWarmProviderCounts = WarmRun.Telemetry\ConvertTo-NormalizedProviderCounts -ProviderCounts $warmMetrics.ProviderCounts
        if ($warmPassHostnames -and $warmPassHostnames.Count -gt 0) {
            $warmCountSource = $warmPassHostnames.Count
        } else {
            $warmCountSource = $warmMetrics.Count
        }
    } elseif ($warmPassHostnames -and $warmPassHostnames.Count -gt 0) {
        $warmCountSource = $warmPassHostnames.Count
    }
    if ($coldMetrics) {
        $normalizedColdProviderCounts = WarmRun.Telemetry\ConvertTo-NormalizedProviderCounts -ProviderCounts $coldMetrics.ProviderCounts
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

    $warmProviderRawMetrics = Resolve-CacheProviderMetrics -ProviderCounts $normalizedWarmProviderCounts -CountSource $warmCountSource
    $warmCacheProviderHitCountRaw = [int]$warmProviderRawMetrics.HitCount
    $warmCacheProviderMissCountRaw = [int]$warmProviderRawMetrics.MissCount
    $warmCacheHitRatioPercentRaw = $warmProviderRawMetrics.HitRatioPercent

    $warmProviderCounts = $normalizedWarmProviderCounts
    $warmCacheProviderHitCount = $warmCacheProviderHitCountRaw
    $warmCacheProviderMissCount = $warmCacheProviderMissCountRaw
    $warmCacheHitRatioPercent = $warmCacheHitRatioPercentRaw

    $warmSummaryMetrics = WarmRun.Telemetry\Measure-ProviderMetricsFromSummaries -Summaries $warmSummaries
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
        $warmProviderRawMetrics = Resolve-CacheProviderMetrics -ProviderCounts $normalizedWarmProviderCounts -CountSource $warmCountSource
        $warmCacheProviderHitCountRaw = [int]$warmProviderRawMetrics.HitCount
        $warmCacheProviderMissCountRaw = [int]$warmProviderRawMetrics.MissCount
        $warmCacheHitRatioPercentRaw = $warmProviderRawMetrics.HitRatioPercent
    }

    $coldProviderCounts = $normalizedColdProviderCounts
    $coldSummaryMetrics = WarmRun.Telemetry\Measure-ProviderMetricsFromSummaries -Summaries $coldSummaries
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
            $matchCountProp = $event.PSObject.Properties['SiteCacheHostMapSignatureMatchCount']
            if ($matchCountProp) {
                try { $matchCount = [int]$matchCountProp.Value } catch { $matchCount = 0 }
            }
            if ($matchCount -le 0) {
                $warmSignatureMatchMissCount++
            }

            $rewriteCountProp = $event.PSObject.Properties['SiteCacheHostMapSignatureRewriteCount']
            if ($rewriteCountProp) {
                try { $warmSignatureRewriteTotal += [int]$rewriteCountProp.Value } catch { }
            }
        }
    } elseif ($warmSummaries) {
        foreach ($summary in @($warmSummaries)) {
            if (-not $summary) { continue }
            $matchCount = 0
            $matchCountProp = $summary.PSObject.Properties['HostMapSignatureMatchCount']
            if ($matchCountProp) { try { $matchCount = [int]$matchCountProp.Value } catch { $matchCount = 0 } }
            if ($matchCount -le 0) {
                $warmSignatureMatchMissCount++
            }

            $rewriteProp = $summary.PSObject.Properties['HostMapSignatureRewriteCount']
            if ($rewriteProp) {
                try { $warmSignatureRewriteTotal += [int]$rewriteProp.Value } catch { }
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

    if ($comparisonSummary -and $warmMetrics -and $warmMetrics.Events) {
        $providerCounts = @{}
        $hitCount = 0
        $missCount = 0
        foreach ($event in @($warmMetrics.Events)) {
            if (-not $event) { continue }
            $provider = ''
            $providerProp = $event.PSObject.Properties['SiteCacheProvider']
            if ($providerProp) { $provider = ('' + $providerProp.Value).Trim() }
            if ([string]::IsNullOrWhiteSpace($provider)) {
                $provider = 'Unknown'
            }
            if ($providerCounts.ContainsKey($provider)) {
                $providerCounts[$provider]++
            } else {
                $providerCounts[$provider] = 1
            }
            if ($provider -eq 'Cache' -or $provider -eq 'SharedCache') {
                $hitCount++
            } else {
                $missCount++
            }
        }
        $totalProviders = $hitCount + $missCount
        $hitRatio = $null
        if ($totalProviders -gt 0) {
            $hitRatio = [math]::Round(($hitCount / $totalProviders) * 100, 2)
        } elseif ($comparisonSummary.WarmHostCount) {
            $hitRatio = [math]::Round(($hitCount / [int]$comparisonSummary.WarmHostCount) * 100, 2)
        }
        $comparisonSummary.WarmProviderCounts = $providerCounts
        $comparisonSummary.WarmProviderCountsRaw = $providerCounts
        $comparisonSummary.WarmCacheProviderHitCount = $hitCount
        $comparisonSummary.WarmCacheProviderHitCountRaw = $hitCount
        $comparisonSummary.WarmCacheProviderMissCount = $missCount
        $comparisonSummary.WarmCacheProviderMissCountRaw = $missCount
        $comparisonSummary.WarmCacheHitRatioPercent = $hitRatio
        $comparisonSummary.WarmCacheHitRatioPercentRaw = $hitRatio
    } elseif ($comparisonSummary -and $comparisonSummary.WarmProviderCountsRaw) {
        $normalizedWarmCounts = WarmRun.Telemetry\ConvertTo-NormalizedProviderCounts -ProviderCounts $comparisonSummary.WarmProviderCountsRaw
        $warmCountSource = if ($comparisonSummary.WarmHostCount) { [int]$comparisonSummary.WarmHostCount } else { 0 }
        $warmProviderMetrics = Resolve-CacheProviderMetrics -ProviderCounts $normalizedWarmCounts -CountSource $warmCountSource
        $comparisonSummary.WarmCacheProviderHitCount = [int]$warmProviderMetrics.HitCount
        $comparisonSummary.WarmCacheProviderHitCountRaw = [int]$warmProviderMetrics.HitCount
        $comparisonSummary.WarmCacheProviderMissCount = [int]$warmProviderMetrics.MissCount
        $comparisonSummary.WarmCacheProviderMissCountRaw = [int]$warmProviderMetrics.MissCount
        $comparisonSummary.WarmCacheHitRatioPercent = $warmProviderMetrics.HitRatioPercent
        $comparisonSummary.WarmCacheHitRatioPercentRaw = $warmProviderMetrics.HitRatioPercent
    }

    [void]$results.Add($comparisonSummary)
}

if ($AssertWarmCache.IsPresent -and -not $SkipWarmValidation.IsPresent) {
    $assertFailures = [System.Collections.Generic.List[string]]::new()
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
    $filteredResults = [System.Collections.Generic.List[psobject]]::new()
    foreach ($result in $results) {
        $summaryTypeProp = $result.PSObject.Properties['SummaryType']
        if ($summaryTypeProp -and $summaryTypeProp.Value) {
            [void]$filteredResults.Add($result)
            continue
        }

        $passLabel = $result.PassLabel
        $allowedHosts = Get-PassHostnameFilter -Label $passLabel
        if (-not $allowedHosts -or $allowedHosts.Count -le 0) {
            [void]$filteredResults.Add($result)
            continue
        }

        $hostnameValue = $null
        $hostnameProp = $result.PSObject.Properties['Hostname']
        if ($hostnameProp) { $hostnameValue = $hostnameProp.Value }

        if ([string]::IsNullOrWhiteSpace($hostnameValue)) {
            # Retain hostless rows so cold metrics are not dropped entirely when filtered logs omit hostnames.
            [void]$filteredResults.Add($result)
            continue
        }

        if ($allowedHosts.Contains(('' + $hostnameValue).Trim())) {
            [void]$filteredResults.Add($result)
        }
    }
    $results = $filteredResults.ToArray()
}

function Update-ComparisonSummaryFromResults {
    param(
        [System.Collections.IEnumerable]$Items
    )

    $itemsArray = @($Items)
    if (-not $itemsArray) { return $Items }

    $comparison = $null
    $warmEventsList = [System.Collections.Generic.List[psobject]]::new()
    $coldEventsList = [System.Collections.Generic.List[psobject]]::new()
    foreach ($item in $itemsArray) {
        if (-not $item -or -not $item.PSObject) { continue }

        $summaryTypeProp = $item.PSObject.Properties['SummaryType']
        $summaryTypeValue = $null
        if ($summaryTypeProp) { $summaryTypeValue = $summaryTypeProp.Value }
        if (-not [string]::IsNullOrWhiteSpace('' + $summaryTypeValue)) {
            if (-not $comparison -and ('' + $summaryTypeValue) -eq 'InterfaceCallDuration') {
                $comparison = $item
            }
            continue
        }

        $passLabelProp = $item.PSObject.Properties['PassLabel']
        if (-not $passLabelProp) { continue }
        $passLabel = '' + $passLabelProp.Value
        if ($passLabel -eq 'WarmPass') {
            [void]$warmEventsList.Add($item)
        } elseif ($passLabel -eq 'ColdPass') {
            [void]$coldEventsList.Add($item)
        }
    }
    if (-not $comparison) { return $Items }

    $originalColdHostCount = $comparison.ColdHostCount
    $originalWarmHostCount = $comparison.WarmHostCount

    $warmEvents = $warmEventsList.ToArray()
    $coldEvents = $coldEventsList.ToArray()

    function Get-ProviderSnapshot {
        param([System.Collections.IEnumerable]$Events)
        $providerCounts = @{}
        $hostSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $durations = [System.Collections.Generic.List[double]]::new()
        $signatureMisses = 0

        foreach ($evt in @($Events)) {
            if (-not $evt) { continue }
            $provider = ''
            $providerProp = $evt.PSObject.Properties['Provider']
            if ($providerProp) { $provider = '' + $providerProp.Value }
            if ([string]::IsNullOrWhiteSpace($provider)) {
                $siteCacheProviderProp = $evt.PSObject.Properties['SiteCacheProvider']
                if ($siteCacheProviderProp) { $provider = '' + $siteCacheProviderProp.Value }
            }
            $provider = $provider.Trim()
            if ([string]::IsNullOrWhiteSpace($provider)) {
                $provider = 'Unknown'
            }
            if ($providerCounts.ContainsKey($provider)) {
                $providerCounts[$provider]++
            } else {
                $providerCounts[$provider] = 1
            }

            $hostnameProp = $evt.PSObject.Properties['Hostname']
            if ($hostnameProp) {
                $hostnameValue = ('' + $hostnameProp.Value).Trim()
                if (-not [string]::IsNullOrWhiteSpace($hostnameValue)) {
                    [void]$hostSet.Add($hostnameValue)
                }
            }

            $durationProp = $evt.PSObject.Properties['InterfaceCallDurationMs']
            if ($durationProp -and $durationProp.Value -ne $null) {
                try { [void]$durations.Add([double]$durationProp.Value) } catch { }
            }

            $matchCountProp = $evt.PSObject.Properties['SiteCacheHostMapSignatureMatchCount']
            if ($matchCountProp) {
                try {
                    if ([int]$matchCountProp.Value -le 0) { $signatureMisses++ }
                } catch {
                    $signatureMisses++
                }
            }
        }

        return [pscustomobject]@{
            Providers       = $providerCounts
            HostCount       = $hostSet.Count
            Durations       = $durations.ToArray()
            SignatureMisses = $signatureMisses
        }
    }

    function Test-CacheRefreshSummary {
        param($Event)

        if (-not $Event -or -not $Event.PSObject) { return $false }

        $provider = ''
        $providerProp = $Event.PSObject.Properties['Provider']
        if ($providerProp) { $provider = ('' + $providerProp.Value).Trim() }
        if ($provider -ne 'AccessRetry') { return $false }

        $cacheStatus = ''
        $cacheStatusProp = $Event.PSObject.Properties['CacheStatus']
        if ($cacheStatusProp) { $cacheStatus = ('' + $cacheStatusProp.Value).Trim() }

        $reason = ''
        $reasonProp = $Event.PSObject.Properties['SiteCacheProviderReason']
        if ($reasonProp) { $reason = ('' + $reasonProp.Value).Trim() }

        return ($cacheStatus -eq 'Refreshed' -and $reason -eq 'AccessRefresh')
    }

    $warmEventsForProviders = $warmEvents
    if ($warmEvents -and $warmEvents.Count -gt 0) {
        $filteredWarmEvents = [System.Collections.Generic.List[psobject]]::new()
        foreach ($evt in @($warmEvents)) {
            if (-not (Test-CacheRefreshSummary -Event $evt)) {
                [void]$filteredWarmEvents.Add($evt)
            }
        }
        if ($filteredWarmEvents.Count -gt 0) {
            $warmEventsForProviders = $filteredWarmEvents.ToArray()
        }
    }

    $warmSnapshot = Get-ProviderSnapshot -Events @($warmEventsForProviders)
    $coldSnapshot = Get-ProviderSnapshot -Events @($coldEvents)

    if ($warmSnapshot) {
        $comparison.WarmProviderCounts = $warmSnapshot.Providers
        $comparison.WarmProviderCountsRaw = $warmSnapshot.Providers
        $hitCount = 0
        foreach ($cacheKey in @('Cache','SharedCache')) {
            if ($warmSnapshot.Providers.ContainsKey($cacheKey)) {
                $hitCount += [int]$warmSnapshot.Providers[$cacheKey]
            }
        }
        $missCount = 0
        foreach ($entry in $warmSnapshot.Providers.GetEnumerator()) {
            if ($entry.Key -ne 'Cache' -and $entry.Key -ne 'SharedCache') {
                $missCount += [int]$entry.Value
            }
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
            $warmAverage = [System.Linq.Enumerable]::Average($warmSnapshot.Durations)
            $warmMax = [System.Linq.Enumerable]::Max($warmSnapshot.Durations)
            $comparison.WarmInterfaceCallAvgMs = [math]::Round($warmAverage, 3)
            $comparison.WarmInterfaceCallMaxMs = [math]::Round($warmMax, 3)
            $comparison.WarmInterfaceCallP95Ms = [math]::Round((StatisticsModule\Get-PercentileValue -Values $warmSnapshot.Durations -Percentile 95), 3)
        }
    }

    if ($coldSnapshot) {
        $comparison.ColdProviderCounts = $coldSnapshot.Providers
        $comparison.ColdProviderCountsRaw = $coldSnapshot.Providers
        $comparison.ColdHostCount = $coldSnapshot.HostCount

        if ($coldSnapshot.Durations.Length -gt 0) {
            $coldAverage = [System.Linq.Enumerable]::Average($coldSnapshot.Durations)
            $coldMax = [System.Linq.Enumerable]::Max($coldSnapshot.Durations)
            $comparison.ColdInterfaceCallAvgMs = [math]::Round($coldAverage, 3)
            $comparison.ColdInterfaceCallMaxMs = [math]::Round($coldMax, 3)
            $comparison.ColdInterfaceCallP95Ms = [math]::Round((StatisticsModule\Get-PercentileValue -Values $coldSnapshot.Durations -Percentile 95), 3)
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
    $totalResultCount = $results.Count
    Write-Host ("Result count prior to export: {0}" -f $totalResultCount) -ForegroundColor Yellow
    $null = Initialize-DirectoryForPath -Path $OutputPath
    $exportPayload = [System.Collections.Generic.List[psobject]]::new()
    foreach ($result in @($results)) {
        if (-not $result) { continue }

        [void]$exportPayload.Add((Select-Object -InputObject $result -Property `
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
            ExistingCount,
            MetricName,
            MetricStatus,
            MetricStatusReason,
            MetricStatusNotes,
            ParseDurationCount,
            SkippedDuplicateCount,
            HistorySeedMode
        ))
    }

    $json = ConvertTo-Json -InputObject $exportPayload.ToArray() -Depth 6
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
            $null = Initialize-Directory -Path $diffDirEnsure

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

if ($shouldGenerateSharedCacheDiagnostics) {
    $sharedStoreScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Analyze-SharedCacheStoreState.ps1'
    $providerReasonScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Analyze-SiteCacheProviderReasons.ps1'
    if (-not (Test-Path -LiteralPath $sharedStoreScript)) {
        throw "Shared cache store analyzer script not found at '$sharedStoreScript'."
    }
    if (-not (Test-Path -LiteralPath $providerReasonScript)) {
        throw "Shared cache provider analyzer script not found at '$providerReasonScript'."
    }

    $metricsPath = Get-LatestIngestionMetricsFile -DirectoryPath $metricsDirectory
    if (-not $metricsPath) {
        Write-Warning ("Shared cache diagnostics requested but no ingestion metrics file was found under '{0}'." -f $metricsDirectory)
    } else {
        foreach ($passLabel in @('ColdPass','WarmPass')) {
            $window = $null
            if ($script:PassWindows.ContainsKey($passLabel)) {
                $window = $script:PassWindows[$passLabel]
            }
            if (-not $window -or -not $window.StartUtc -or -not $window.EndUtc) {
                Write-Warning ("Shared cache diagnostics skipped for {0} because pass window timestamps are unavailable." -f $passLabel)
                continue
            }

            Write-Host ("Running shared cache diagnostics for {0} window {1} -> {2} (UTC)..." -f $passLabel, $window.StartUtc.ToString('o'), $window.EndUtc.ToString('o')) -ForegroundColor Cyan
            try {
                & $sharedStoreScript -Path $metricsPath -IncludeSiteBreakdown -StartTimeUtc $window.StartUtc -EndTimeUtc $window.EndUtc
            } catch {
                throw ("Shared cache store diagnostics failed for {0}: {1}" -f $passLabel, $_.Exception.Message)
            }
            try {
                & $providerReasonScript -Path $metricsPath -IncludeHostBreakdown -TopHosts $SharedCacheDiagnosticsTopHosts -StartTimeUtc $window.StartUtc -EndTimeUtc $window.EndUtc
            } catch {
                throw ("Shared cache provider diagnostics failed for {0}: {1}" -f $passLabel, $_.Exception.Message)
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
