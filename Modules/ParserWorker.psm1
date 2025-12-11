if (-not (Get-Variable -Name StateTraceDebug -Scope Global -ErrorAction SilentlyContinue)) {
    Set-Variable -Scope Global -Name StateTraceDebug -Value $false -Option None
}
try {
    TelemetryModule\Initialize-StateTraceDebug
} catch { }



function New-Directories {

    param ([string[]]$Paths)

    foreach ($path in $Paths) {

        if (-not (Test-Path $path)) {

            New-Item -ItemType Directory -Path $path | Out-Null

        }

    }

}


function Get-DeviceLogSetStatistics {

    param([string[]]$DeviceFiles)

    $deviceCount = if ($DeviceFiles) { $DeviceFiles.Count } else { 0 }
    $siteCount = 0
    if ($deviceCount -gt 0) {
        $siteSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($pathValue in $DeviceFiles) {
            if ([string]::IsNullOrWhiteSpace($pathValue)) { continue }
            $name = [System.IO.Path]::GetFileNameWithoutExtension($pathValue)
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $siteToken = $name
            $dashIndex = $name.IndexOf('-')
            if ($dashIndex -gt 0) { $siteToken = $name.Substring(0, $dashIndex) }
            if (-not [string]::IsNullOrWhiteSpace($siteToken)) {
                [void]$siteSet.Add($siteToken)
            }
        }
        $siteCount = $siteSet.Count
    }

    return [PSCustomObject]@{
        DeviceCount = [int][Math]::Max(0, $deviceCount)
        SiteCount   = [int][Math]::Max(0, $siteCount)
    }
}

function Initialize-SiteExistingRowCacheSnapshot {
    [CmdletBinding()]
    param(
        [string]$SnapshotPath,
        [switch]$PrimeDeviceRepository
    )

    $resolvedPath = $SnapshotPath
    if (-not $resolvedPath) {
        try {
            if ($env:STATETRACE_SITE_EXISTING_ROW_CACHE_SNAPSHOT) {
                $resolvedPath = '' + $env:STATETRACE_SITE_EXISTING_ROW_CACHE_SNAPSHOT
            }
        } catch {
            $resolvedPath = $null
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedPath) -or -not (Test-Path -LiteralPath $resolvedPath)) {
        return $null
    }

    $snapshot = $null
    try {
        $snapshot = Import-Clixml -Path $resolvedPath
    } catch {
        Write-Warning ("Failed to import site existing row cache snapshot '{0}': {1}" -f $resolvedPath, $_.Exception.Message)
        return $null
    }
    if (-not $snapshot) { return $null }

    $entryCount = ($snapshot | Measure-Object).Count
    if ($entryCount -le 0) { return $null }

    try {
        ParserPersistenceModule\Set-SiteExistingRowCacheSnapshot -Snapshot $snapshot | Out-Null
    } catch {
        Write-Warning ("Failed to hydrate parser persistence cache from '{0}': {1}" -f $resolvedPath, $_.Exception.Message)
        return $null
    }

    $siteSummaries = [System.Collections.Generic.List[psobject]]::new()
    $siteGroups = @($snapshot | Group-Object -Property Site)
    foreach ($group in $siteGroups) {
        $siteName = '' + $group.Name
        if ([string]::IsNullOrWhiteSpace($siteName)) { $siteName = 'Unknown' }
        $siteSummaries.Add([pscustomobject]@{
                Site      = $siteName
                HostCount = [int]$group.Count
            }) | Out-Null

        if ($PrimeDeviceRepository) {
            foreach ($hostEntry in $group.Group) {
                $hostname = '' + $hostEntry.Hostname
                if ([string]::IsNullOrWhiteSpace($hostname)) { continue }
                $rowsByPort = $hostEntry.Rows
                if (-not $rowsByPort) { continue }
                try {
                    DeviceRepositoryModule\Set-InterfaceSiteCacheHost -Site $siteName -Hostname $hostname -RowsByPort $rowsByPort | Out-Null
                } catch {
                    Write-Verbose ("Failed to prime site cache for {0}/{1}: {2}" -f $siteName, $hostname, $_.Exception.Message)
                }
            }
        }
    }

    return [pscustomobject]@{
        SnapshotPath = $resolvedPath
        EntryCount   = [int]$entryCount
        SiteSummaries = $siteSummaries.ToArray()
    }
}

function Write-SharedCacheSnapshotFileInternal {
    param(
        [Parameter(Mandatory)][string]$Path,
        [System.Collections.IEnumerable]$Entries
    )

    $cacheFallbackWriter = Get-Command -Name 'DeviceRepository.Cache\Write-SharedCacheSnapshotFileFallback' -ErrorAction SilentlyContinue
    if (-not $cacheFallbackWriter) {
        $cacheFallbackWriter = Get-Command -Name 'Write-SharedCacheSnapshotFileFallback' -Module 'DeviceRepository.Cache' -ErrorAction SilentlyContinue
    }
    if ($cacheFallbackWriter) {
        try {
            & $cacheFallbackWriter -Path $Path -Entries $Entries
            return
        } catch {
            Write-Verbose ("Shared cache snapshot fallback via DeviceRepository.Cache failed: {0}" -f $_.Exception.Message)
        }
    }

    $entryArray = @()
    try { $entryArray = @(ConvertTo-SharedCacheEntryArray -Entries $Entries) } catch { $entryArray = @($Entries) }
    if (-not ($entryArray -is [System.Collections.IEnumerable])) { $entryArray = @($entryArray) }
    $sanitizedEntries = $null
    try {
        $repoModule = Get-Module -Name 'DeviceRepositoryModule'
        if (-not $repoModule) {
            $repoPath = Join-Path -Path $modulesPath -ChildPath 'DeviceRepositoryModule.psm1'
            if (Test-Path -LiteralPath $repoPath) {
                $repoModule = Import-Module -Name $repoPath -PassThru -ErrorAction SilentlyContinue
            }
        }
        if ($repoModule) {
            $sanitizedEntries = @($repoModule.Invoke({ param($entries) Resolve-SharedSiteInterfaceCacheSnapshotEntries -Entries $entries }, $entryArray))
        }
    } catch {
        $sanitizedEntries = $null
    }
    if (-not $sanitizedEntries) {
        $sanitizedEntries = [System.Collections.Generic.List[psobject]]::new()

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
            if (-not $entryValue) {
                continue
            }

            $sanitizedEntries.Add([pscustomobject]@{
                    Site  = $siteValue
                    Entry = $entryValue
                }) | Out-Null
        }
    }

    $directory = $null
    try { $directory = Split-Path -Parent $Path } catch { $directory = $null }
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        try { $directory = [System.IO.Path]::GetFullPath($directory) } catch { }
    }
    $targetPath = $Path
    try { $targetPath = [System.IO.Path]::GetFullPath($Path) } catch { $targetPath = $Path }
    try {
        if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $exportEntries = if ($sanitizedEntries.Count -gt 0) { $sanitizedEntries.ToArray() } else { @() }
        Export-Clixml -InputObject $exportEntries -Path $targetPath -Depth 20
    } catch {
        Write-Warning ("Failed to write shared cache snapshot to '{0}': {1}" -f $targetPath, $_.Exception.Message)
    }
}

function Get-AutoScaleConcurrencyProfile {

    [CmdletBinding()]

    param(

        [Parameter(Mandatory)][string[]]$DeviceFiles,

        [int]$CpuCount = 1,

        [int]$ThreadCeiling = 0,

        [int]$MaxWorkersPerSite = 0,

        [int]$MaxActiveSites = -1,

        [int]$JobsPerThread = 0,

        [int]$MinRunspaces = 1

    )



    $cpuCount = [Math]::Max(1, $CpuCount)

    $stats = Get-DeviceLogSetStatistics -DeviceFiles $DeviceFiles

    $deviceCount = $stats.DeviceCount

    $rawSiteCount = $stats.SiteCount

    $siteCount = if ($rawSiteCount -gt 0) { $rawSiteCount } else { 1 }



    $maxThreadBound = [Math]::Max(1, [Math]::Min($cpuCount * 2, [Math]::Max(1, $deviceCount)))

    $targetThreads = $ThreadCeiling

    if ($targetThreads -le 0) {

        $baseline = [Math]::Ceiling($cpuCount * 0.75)

        if ($deviceCount -gt 0) {

            $targetThreads = [Math]::Min($baseline, $deviceCount)

        } else {

            $targetThreads = $baseline

        }

    }

    $targetThreads = [Math]::Max(1, [Math]::Min($targetThreads, $maxThreadBound))



    $workersPerSite = $MaxWorkersPerSite

    if ($workersPerSite -le 0) {

        $workersPerSite = [Math]::Ceiling($targetThreads / [Math]::Max(1, $siteCount))

        if ($workersPerSite -lt 1) { $workersPerSite = 1 }

        if ($siteCount -le 1 -and $workersPerSite -gt 4) {

            $workersPerSite = 4

        } elseif ($siteCount -gt 1 -and $workersPerSite -gt 12) {

            $workersPerSite = 12

        }

    } else {

        $workersPerSite = [Math]::Max(1, $workersPerSite)

    }



    if ($MaxActiveSites -eq 0) {

        $activeSiteLimit = 0

    } elseif ($MaxActiveSites -gt 0) {

        $activeSiteLimit = [Math]::Min($siteCount, $MaxActiveSites)

    } else {

        $activeSiteLimit = [Math]::Ceiling($targetThreads / [Math]::Max(1, $workersPerSite))

        if ($activeSiteLimit -lt 1) { $activeSiteLimit = 1 }

        if ($activeSiteLimit -gt $siteCount) { $activeSiteLimit = $siteCount }

    }



    $jobsPerThreadValue = $JobsPerThread

    if ($jobsPerThreadValue -le 0) {

        if ($targetThreads -gt 0) {

            $jobsPerThreadValue = [Math]::Ceiling([Math]::Max(1, $deviceCount) / [Math]::Max(1, $targetThreads))

        }

        if ($jobsPerThreadValue -lt 1) { $jobsPerThreadValue = 1 }

        if ($jobsPerThreadValue -gt 4) { $jobsPerThreadValue = 4 }

    } else {

        $jobsPerThreadValue = [Math]::Max(1, $jobsPerThreadValue)

    }



    $minThreadBaseline = $MinRunspaces

    if ($minThreadBaseline -le 0 -or $minThreadBaseline -gt $targetThreads) {

        $minThreadBaseline = [Math]::Max(1, [Math]::Min($targetThreads, [Math]::Ceiling([Math]::Max(1.0, [double]$siteCount) / 2.0)))

    }



    return [PSCustomObject]@{

        ThreadCeiling     = [int][Math]::Max(1, $targetThreads)

        MaxWorkersPerSite = [int][Math]::Max(1, $workersPerSite)

        MaxActiveSites    = [int][Math]::Max(0, $activeSiteLimit)

        JobsPerThread     = [int][Math]::Max(1, $jobsPerThreadValue)

        MinRunspaces      = [int][Math]::Max(1, $minThreadBaseline)

        DeviceCount       = [int][Math]::Max(0, $deviceCount)

        SiteCount         = [int][Math]::Max(0, $rawSiteCount)

    }

}



function Invoke-StateTraceParsing {

    [CmdletBinding()]

    param(

        [string]$DatabasePath,

        [int]$ThreadCeilingOverride,

        [int]$MaxWorkersPerSiteOverride,

        [int]$MaxActiveSitesOverride,

        [int]$MaxConsecutiveSiteLaunchesOverride,

        [int]$JobsPerThreadOverride,

        [int]$MinRunspacesOverride,

        [switch]$Synchronous,

        [switch]$PreserveRunspace,

        [switch]$DisableAutoScaleProfile,

        [string]$SharedCacheSnapshotExportPath,

        [string]$LogRoot

    )

    # Determine project root based on the module's location.  $PSScriptRoot is

    # Resolve the project root once using .NET methods.  Using Resolve-Path in a

    # pipeline can be expensive; GetFullPath computes the absolute path to the

    # parent directory without invoking the pipeline.

    try {

        $projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

    } catch {

        $projectRoot = (Split-Path -Parent $PSScriptRoot)

    }

    $logPath = if (-not [string]::IsNullOrWhiteSpace($LogRoot)) {
        [System.IO.Path]::GetFullPath($LogRoot)
    } else {
        Join-Path $projectRoot 'Logs'
    }

    $extractedPath = Join-Path $logPath 'Extracted'

    $modulesPath   = Join-Path $projectRoot 'Modules'

    $archiveRoot   = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'SwitchArchives'



    New-Directories @($logPath, $extractedPath, $archiveRoot)

    LogIngestionModule\Split-RawLogs -LogPath $logPath -ExtractedPath $extractedPath



    $allExtractedFiles = @(Get-ChildItem -Path $extractedPath -File)

    if ($allExtractedFiles.Count -gt 0) {
        $unknownSlices = @($allExtractedFiles | Where-Object { $_.BaseName -eq '_unknown' })
        if ($unknownSlices.Count -gt 0) {
            $unknownNames = $unknownSlices | Select-Object -ExpandProperty FullName
            Write-Verbose ("Skipping {0} unknown slice(s): {1}" -f $unknownSlices.Count, ($unknownNames -join ', '))
        }
    }

    $deviceFiles = @($allExtractedFiles | Where-Object { $_.BaseName -ne '_unknown' } | Select-Object -ExpandProperty FullName)

    $logSetStats = Get-DeviceLogSetStatistics -DeviceFiles $deviceFiles

    $rawSiteCountForTelemetry = $logSetStats.SiteCount

    $deviceCountForTelemetry = $logSetStats.DeviceCount

    if ($deviceFiles.Count -gt 0) {

        Write-Host "Extracted $($deviceFiles.Count) device log file(s) to process:" -ForegroundColor Yellow

        foreach ($dev in $deviceFiles) {

            Write-Host "  - $dev" -ForegroundColor Yellow

        }

    } else {

        Write-Warning "No device logs were extracted; the parser will not run."

    }



    $parserSettings = $null

    $maxWorkersPerSite = 1

    $maxActiveSites = 1

    $threadCeiling = [Math]::Min(8, [Environment]::ProcessorCount)

    $minRunspaces = 1

    $jobsPerThread = 2

    $enableAdaptiveThreads = $true

    $maxConsecutiveSiteLaunches = 8
    $hasMaxConsecutiveSiteSetting = $false

    $interfaceBulkChunkSize = $null
    $interfaceBulkChunkSizeHint = $null
    $resolvedInterfaceBulkChunkSize = $null
    $skipSiteCacheUpdate = $false

    try {
        $settingsPath = Join-Path $projectRoot 'Data\StateTraceSettings.json'
        if (-not (Test-Path -LiteralPath $settingsPath)) {
            $altSettingsPath = Join-Path $projectRoot '..\Data\StateTraceSettings.json'
            if (Test-Path -LiteralPath $altSettingsPath) {
                $settingsPath = $altSettingsPath
            }
        }

        if (Test-Path -LiteralPath $settingsPath) {

            $raw = Get-Content -LiteralPath $settingsPath -Raw

            if (-not [string]::IsNullOrWhiteSpace($raw)) {

                try { $settings = $raw | ConvertFrom-Json } catch { $settings = $null }

                if ($settings) {

                    if ($settings.PSObject.Properties.Name -contains 'ParserSettings') {

                        $parserSettings = $settings.ParserSettings

                    } elseif ($settings.PSObject.Properties.Name -contains 'Parser') {

                        $parserSettings = $settings.Parser

                    }

                }

            }

        }

    } catch { }



    $autoScaleConcurrency = $false

    $hasThreadCeilingSetting = $false

    $hasMaxWorkersSetting = $false

    $hasMaxActiveSitesSetting = $false

    $hasJobsPerThreadSetting = $false

    $hasMinRunspacesSetting = $false



    if ($parserSettings) {

        if ($parserSettings.PSObject.Properties.Name -contains 'MaxWorkersPerSite') {

            try {

                $val = [int]$parserSettings.MaxWorkersPerSite

                if ($val -gt 0) { $maxWorkersPerSite = $val }

                elseif ($val -eq 0) { $maxWorkersPerSite = 0 }

                $hasMaxWorkersSetting = $true

            } catch { }

        }

        if ($parserSettings.PSObject.Properties.Name -contains 'MaxActiveSites') {

            try {

                $val = [int]$parserSettings.MaxActiveSites

                if ($val -gt 0) { $maxActiveSites = $val }

                elseif ($val -eq 0) { $maxActiveSites = 0 }

                $hasMaxActiveSitesSetting = $true

            } catch { }

        }

        if ($parserSettings.PSObject.Properties.Name -contains 'MaxConsecutiveSiteLaunches') {

            try {

                $limit = [int]$parserSettings.MaxConsecutiveSiteLaunches

                if ($limit -gt 0) {
                    $maxConsecutiveSiteLaunches = $limit
                } elseif ($limit -eq 0) {
                    $maxConsecutiveSiteLaunches = 0
                }
                $hasMaxConsecutiveSiteSetting = $true

            } catch { }

        }

        if ($parserSettings.PSObject.Properties.Name -contains 'MaxRunspaceCeiling') {

            try {

                $val = [int]$parserSettings.MaxRunspaceCeiling

                if ($val -gt 0) { $threadCeiling = $val }

                $hasThreadCeilingSetting = $true

            } catch { }

        }

        if ($parserSettings.PSObject.Properties.Name -contains 'MinRunspaceCount') {

            try {

                $val = [int]$parserSettings.MinRunspaceCount

                if ($val -gt 0) { $minRunspaces = $val }

                $hasMinRunspacesSetting = $true

            } catch { }

        }

        if ($parserSettings.PSObject.Properties.Name -contains 'JobsPerThread') {

            try {

                $val = [int]$parserSettings.JobsPerThread

                if ($val -gt 0) { $jobsPerThread = $val }

                $hasJobsPerThreadSetting = $true

            } catch { }

        }

        if ($parserSettings.PSObject.Properties.Name -contains 'EnableAdaptiveThreads') {

            try {

                $flag = [bool]$parserSettings.EnableAdaptiveThreads

                $enableAdaptiveThreads = $flag

            } catch { }

        }

        if ($parserSettings.PSObject.Properties.Name -contains 'InterfaceBulkChunkSize') {

            try {

                $candidateChunk = $parserSettings.InterfaceBulkChunkSize

                $interfaceBulkChunkSizeHint = $candidateChunk

                if ($null -ne $candidateChunk -and -not ([string]::IsNullOrWhiteSpace([string]$candidateChunk))) {

                    $interfaceBulkChunkSize = [int]$candidateChunk

                } else {

                    $interfaceBulkChunkSize = $null

                }

            } catch { $interfaceBulkChunkSize = $null }

        }

        if ($parserSettings.PSObject.Properties.Name -contains 'AutoScaleConcurrency') {

            try {

                $autoScaleConcurrency = [bool]$parserSettings.AutoScaleConcurrency

            } catch { $autoScaleConcurrency = $false }

        }

        if ($parserSettings.PSObject.Properties.Name -contains 'SkipSiteCacheUpdate') {
            try {
                $skipSiteCacheUpdate = [bool]$parserSettings.SkipSiteCacheUpdate
            } catch { $skipSiteCacheUpdate = $false }
        }

    }
    $autoScaleConcurrencyRequested = $autoScaleConcurrency
    if ($DisableAutoScaleProfile) {
        $autoScaleConcurrency = $false
    }
    if ($PSBoundParameters.ContainsKey('ThreadCeilingOverride')) {

        $threadCeiling = [int]$ThreadCeilingOverride

        $hasThreadCeilingSetting = $true

    }

    if ($PSBoundParameters.ContainsKey('MaxWorkersPerSiteOverride')) {

        $maxWorkersPerSite = [int]$MaxWorkersPerSiteOverride

        $hasMaxWorkersSetting = $true

    }

    if ($PSBoundParameters.ContainsKey('MaxActiveSitesOverride')) {

        $maxActiveSites = [int]$MaxActiveSitesOverride

        $hasMaxActiveSitesSetting = $true

    }

    if ($PSBoundParameters.ContainsKey('MaxConsecutiveSiteLaunchesOverride')) {

        $maxConsecutiveSiteLaunches = [int]$MaxConsecutiveSiteLaunchesOverride

        $hasMaxConsecutiveSiteSetting = $true

    }

    if ($PSBoundParameters.ContainsKey('JobsPerThreadOverride')) {

        $jobsPerThread = [int]$JobsPerThreadOverride

        $hasJobsPerThreadSetting = $true

    }

    if ($PSBoundParameters.ContainsKey('MinRunspacesOverride')) {

        $minRunspaces = [int]$MinRunspacesOverride

        $hasMinRunspacesSetting = $true

    }

    $hasManualOverrides = $false

    if ($PSBoundParameters.ContainsKey('ThreadCeilingOverride') -or
        $PSBoundParameters.ContainsKey('MaxWorkersPerSiteOverride') -or
        $PSBoundParameters.ContainsKey('MaxActiveSitesOverride') -or
        $PSBoundParameters.ContainsKey('MaxConsecutiveSiteLaunchesOverride') -or
        $PSBoundParameters.ContainsKey('JobsPerThreadOverride') -or
        $PSBoundParameters.ContainsKey('MinRunspacesOverride')) {

        $hasManualOverrides = $true

    }

    $noConcurrencyHints = (-not $hasThreadCeilingSetting -and -not $hasMaxWorkersSetting -and -not $hasMaxActiveSitesSetting -and -not $hasJobsPerThreadSetting -and -not $hasMinRunspacesSetting -and -not $hasManualOverrides)



    $autoScaleThreadHint = if ($hasThreadCeilingSetting) { $threadCeiling } else { 0 }

    $autoScaleWorkerHint = if ($hasMaxWorkersSetting) { $maxWorkersPerSite } else { 0 }

    $autoScaleSiteHint   = if ($hasMaxActiveSitesSetting) { $maxActiveSites } else { -1 }

    $autoScaleJobsHint   = if ($hasJobsPerThreadSetting) { $jobsPerThread } else { 0 }

    $autoScaleMinHint    = if ($hasMinRunspacesSetting) { $minRunspaces } else { 0 }



    $resolvedProfile = $null

    $useAutoScaleProfile = $false

    $shouldApplyAutoScaleProfile = (-not $DisableAutoScaleProfile) -and ($autoScaleConcurrency -or $noConcurrencyHints)

    if ($shouldApplyAutoScaleProfile) {

        $useAutoScaleProfile = $true

        $profile = Get-AutoScaleConcurrencyProfile -DeviceFiles $deviceFiles -CpuCount ([Environment]::ProcessorCount) -ThreadCeiling $autoScaleThreadHint -MaxWorkersPerSite $autoScaleWorkerHint -MaxActiveSites $autoScaleSiteHint -JobsPerThread $autoScaleJobsHint -MinRunspaces $autoScaleMinHint
        if ($profile) {

            $resolvedProfile = $profile

            $threadCeiling = $profile.ThreadCeiling

            $maxWorkersPerSite = $profile.MaxWorkersPerSite

            $maxActiveSites = $profile.MaxActiveSites

            $jobsPerThread = $profile.JobsPerThread

            if ($profile.MinRunspaces -gt 0) { $minRunspaces = $profile.MinRunspaces }

        }

    }



    $threadCeiling = [Math]::Max($minRunspaces, $threadCeiling)

    $jobsPerThread = [Math]::Max(1, $jobsPerThread)

    $cpuLimit = [Math]::Max($minRunspaces, [Environment]::ProcessorCount * 2)

    $threadCeiling = [Math]::Min($threadCeiling, $cpuLimit)

    if ($maxActiveSites -gt 0) {

        $threadCeiling = [Math]::Min($threadCeiling, [Math]::Max($minRunspaces, $maxActiveSites * [Math]::Max(1, $maxWorkersPerSite)))

    } elseif ($maxWorkersPerSite -gt 0) {

        $threadCeiling = [Math]::Min($threadCeiling, [Math]::Max($minRunspaces, $maxWorkersPerSite))

    }

    if ($threadCeiling -lt $minRunspaces) { $threadCeiling = $minRunspaces }



    try {

        if ($null -ne $interfaceBulkChunkSize) {

            $resolvedInterfaceBulkChunkSize = ParserPersistenceModule\Set-InterfaceBulkChunkSize -ChunkSize $interfaceBulkChunkSize

        } else {

            $resolvedInterfaceBulkChunkSize = ParserPersistenceModule\Set-InterfaceBulkChunkSize -Reset

        }

    } catch {

        $resolvedInterfaceBulkChunkSize = $null

        Write-Verbose ("Failed to apply InterfaceBulkChunkSize setting: {0}" -f $_.Exception.Message)

    }

    try {
        ParserPersistenceModule\Set-ParserSkipSiteCacheUpdate -Skip:$skipSiteCacheUpdate | Out-Null
    } catch {
        Write-Verbose ("Failed to apply SkipSiteCacheUpdate setting: {0}" -f $_.Exception.Message)
    }
    try {
        if ($skipSiteCacheUpdate) {
            $env:STATETRACE_SKIP_SITECACHE_UPDATE = '1'
        } else {
            $env:STATETRACE_SKIP_SITECACHE_UPDATE = '0'
        }
    } catch {
        Write-Verbose ("Failed to persist SkipSiteCacheUpdate environment flag: {0}" -f $_.Exception.Message)
    }
    $siteExistingCacheHydration = $null
    if ($skipSiteCacheUpdate) {
        try {
            $siteExistingCacheHydration = Initialize-SiteExistingRowCacheSnapshot -PrimeDeviceRepository
        } catch {
            Write-Verbose ("Site existing row cache hydration skipped: {0}" -f $_.Exception.Message)
        }
        if ($siteExistingCacheHydration) {
            $hydratedSiteCount = if ($siteExistingCacheHydration.SiteSummaries) { $siteExistingCacheHydration.SiteSummaries.Length } else { 0 }
            $entryLabel = if ($siteExistingCacheHydration.EntryCount -eq 1) { 'entry' } else { 'entries' }
            $siteLabel = if ($hydratedSiteCount -eq 1) { 'site' } else { 'sites' }
            Write-Host ("Primed site existing row cache from '{0}' ({1} {2} across {3} {4})." -f $siteExistingCacheHydration.SnapshotPath, $siteExistingCacheHydration.EntryCount, $entryLabel, $hydratedSiteCount, $siteLabel) -ForegroundColor DarkCyan
        } elseif ($env:STATETRACE_SITE_EXISTING_ROW_CACHE_SNAPSHOT) {
            $snapshotNote = '' + $env:STATETRACE_SITE_EXISTING_ROW_CACHE_SNAPSHOT
            Write-Verbose ("Site existing row cache snapshot '{0}' was unavailable or empty; skipping hydration." -f $snapshotNote)
        }
    }

    $resolvedConsecutiveLimit = if ($maxConsecutiveSiteLaunches -gt 0) { [Math]::Max(1, [int]$maxConsecutiveSiteLaunches) } else { 0 }

    $telemetryPayload = @{

        AutoScaleEnabled = [bool]$autoScaleConcurrency
        AutoScaleRequested = [bool]$autoScaleConcurrencyRequested
        AutoScaleProfileRequested = [bool]$useAutoScaleProfile
        AutoScaleProfileDisabled  = [bool]$DisableAutoScaleProfile.IsPresent
        AutoScaleProfileResolved  = [bool]($resolvedProfile -ne $null)

        DeviceCount      = [int]$deviceCountForTelemetry

        SiteCount        = [int]$rawSiteCountForTelemetry

        ThreadCeiling    = [int]$threadCeiling

        MaxWorkersPerSite = [int]$maxWorkersPerSite

        MaxActiveSites   = [int]$maxActiveSites

        MaxConsecutiveSiteLaunches = [int][Math]::Max(0, $resolvedConsecutiveLimit)

        JobsPerThread    = [int]$jobsPerThread

        MinRunspaces     = [int]$minRunspaces

        AdaptiveThreads  = [bool]$enableAdaptiveThreads

        ManualOverrides  = [bool]$hasManualOverrides

        HintThreadCeiling     = [int]$autoScaleThreadHint

        HintMaxWorkersPerSite = [int]$autoScaleWorkerHint

        HintMaxActiveSites    = [int]$autoScaleSiteHint

        HintJobsPerThread     = [int]$autoScaleJobsHint

        HintMinRunspaces      = [int]$autoScaleMinHint

    }

    if ($null -ne $interfaceBulkChunkSizeHint) {

        $telemetryPayload.HintInterfaceBulkChunkSize = [string]$interfaceBulkChunkSizeHint

    }

    if ($resolvedInterfaceBulkChunkSize -ne $null) {

        $telemetryPayload.InterfaceBulkChunkSize = [int]$resolvedInterfaceBulkChunkSize

    }

    if ($PSBoundParameters.ContainsKey('ThreadCeilingOverride')) {

        $telemetryPayload.OverrideThreadCeiling = [int]$ThreadCeilingOverride

    }

    if ($PSBoundParameters.ContainsKey('MaxWorkersPerSiteOverride')) {

        $telemetryPayload.OverrideMaxWorkersPerSite = [int]$MaxWorkersPerSiteOverride

    }

    if ($PSBoundParameters.ContainsKey('MaxActiveSitesOverride')) {

        $telemetryPayload.OverrideMaxActiveSites = [int]$MaxActiveSitesOverride

    }

    if ($PSBoundParameters.ContainsKey('MaxConsecutiveSiteLaunchesOverride')) {

        $telemetryPayload.OverrideMaxConsecutiveSiteLaunches = [int]$MaxConsecutiveSiteLaunchesOverride

    }

    if ($PSBoundParameters.ContainsKey('JobsPerThreadOverride')) {

        $telemetryPayload.OverrideJobsPerThread = [int]$JobsPerThreadOverride

    }

    if ($PSBoundParameters.ContainsKey('MinRunspacesOverride')) {

        $telemetryPayload.OverrideMinRunspaces = [int]$MinRunspacesOverride

    }



    if ($resolvedProfile) {

        $telemetryPayload.DecisionSource = 'AutoScale'

        $telemetryPayload.ResolvedThreadCeiling = [int]$resolvedProfile.ThreadCeiling

        $telemetryPayload.ResolvedMaxWorkersPerSite = [int]$resolvedProfile.MaxWorkersPerSite

        $telemetryPayload.ResolvedMaxActiveSites = [int]$resolvedProfile.MaxActiveSites

        $telemetryPayload.ResolvedJobsPerThread = [int]$resolvedProfile.JobsPerThread

        $telemetryPayload.ResolvedMinRunspaces = [int]$resolvedProfile.MinRunspaces

        if ($resolvedProfile.PSObject.Properties.Name -contains 'DeviceCount') {

            $telemetryPayload.ProfileDeviceCount = [int]$resolvedProfile.DeviceCount

        }

        if ($resolvedProfile.PSObject.Properties.Name -contains 'SiteCount') {

            $telemetryPayload.ProfileSiteCount = [int]$resolvedProfile.SiteCount

        }

    } else {

        $telemetryPayload.DecisionSource = 'Settings'

    }

    $telemetryPayload.ResolvedMaxConsecutiveSiteLaunches = [int][Math]::Max(0, $resolvedConsecutiveLimit)

    try {

        TelemetryModule\Write-StTelemetryEvent -Name 'ConcurrencyProfileResolved' -Payload $telemetryPayload

    } catch { }



    $dbPath = $null

    if ($PSBoundParameters.ContainsKey('DatabasePath') -and $DatabasePath) {

        $dbPath = $DatabasePath

    }



    $jobsParams = @{

        DeviceFiles = $deviceFiles

        MaxThreads  = [Math]::Max($minRunspaces, $threadCeiling)

        MinThreads  = $minRunspaces

        JobsPerThread = $jobsPerThread

        DatabasePath = $dbPath

        ModulesPath = $modulesPath

        ArchiveRoot = $archiveRoot

        MaxWorkersPerSite = $maxWorkersPerSite

        MaxActiveSites    = $maxActiveSites

        MaxConsecutiveSiteLaunches = $resolvedConsecutiveLimit

    }

    if ($enableAdaptiveThreads) { $jobsParams.AdaptiveThreads = $true }
    if ($useAutoScaleProfile) { $jobsParams.UseAutoScaleProfile = $true }

    if ($Synchronous) { $jobsParams.Synchronous = $true }

    if ($PreserveRunspace) { $jobsParams.PreserveRunspacePool = $true }

    function Get-SharedCacheSnapshotEntriesForExport {
        param($DeviceRepoModule)

        $entries = @()
        if ($DeviceRepoModule) {
            try { $entries = @($DeviceRepoModule.Invoke({ Get-SharedSiteInterfaceCacheSnapshotEntries })) } catch { $entries = @() }
            if ($entries -and $entries.Count -gt 0) { return ,$entries }
        }

        $cacheSnapshotCmd = Get-Command -Name 'DeviceRepository.Cache\Get-SharedSiteInterfaceCacheSnapshotEntries' -ErrorAction SilentlyContinue
        if (-not $cacheSnapshotCmd) {
            $cacheSnapshotCmd = Get-Command -Name 'Get-SharedSiteInterfaceCacheSnapshotEntries' -Module 'DeviceRepository.Cache' -ErrorAction SilentlyContinue
        }
        if ($cacheSnapshotCmd) {
            try { $entries = @(& $cacheSnapshotCmd) } catch { $entries = @() }
        }

        if ($entries -and $entries.Count -gt 0) {
            $cacheHelper = Get-Command -Name 'DeviceRepository.Cache\ConvertTo-SharedCacheEntryArray' -ErrorAction SilentlyContinue
            if (-not $cacheHelper) {
                $cacheHelper = Get-Command -Name 'ConvertTo-SharedCacheEntryArray' -Module 'DeviceRepository.Cache' -ErrorAction SilentlyContinue
            }
            if ($cacheHelper) {
                try { $entries = @(& $cacheHelper -Entries $entries) } catch { }
            }
        }

        return ,$entries
    }


    if ($deviceFiles.Count -gt 0) {

        $mode = if ($Synchronous) { "synchronously" } else { "in parallel" }

        Write-Host "Processing $($deviceFiles.Count) logs $mode..." -ForegroundColor Yellow

        ParserRunspaceModule\Invoke-DeviceParsingJobs @jobsParams

    }



    LogIngestionModule\Clear-ExtractedLogs -ExtractedPath $extractedPath

    if (-not [string]::IsNullOrWhiteSpace($SharedCacheSnapshotExportPath)) {
        try {
            $exported = $false
            $deviceRepoModule = Get-Module -Name 'DeviceRepositoryModule'
            if (-not $deviceRepoModule) {
                try {
                    $deviceRepoPath = Join-Path $modulesPath 'DeviceRepositoryModule.psm1'
                    if (Test-Path -LiteralPath $deviceRepoPath) {
                        $deviceRepoModule = Import-Module -Name $deviceRepoPath -ErrorAction SilentlyContinue -PassThru
                    }
                } catch { $deviceRepoModule = $null }
            }

            $snapshotEntries = Get-SharedCacheSnapshotEntriesForExport -DeviceRepoModule $deviceRepoModule
            $snapshotEntryCount = ($snapshotEntries | Measure-Object).Count
            Write-Verbose ("Shared cache snapshot entries captured: {0}" -f $snapshotEntryCount)

            $cacheModule = Get-Module -Name 'DeviceRepository.Cache' -ErrorAction SilentlyContinue
            if (-not $cacheModule) {
                try {
                    $cacheModulePath = Join-Path $modulesPath 'DeviceRepository.Cache.psm1'
                    if (Test-Path -LiteralPath $cacheModulePath) {
                        $cacheModule = Import-Module -Name $cacheModulePath -ErrorAction SilentlyContinue -PassThru
                    }
                } catch { }
            }
            $cacheExportCmd = Get-Command -Name 'DeviceRepository.Cache\Export-SharedCacheSnapshot' -ErrorAction SilentlyContinue
            if (-not $cacheExportCmd) {
                $cacheExportCmd = Get-Command -Name 'Export-SharedCacheSnapshot' -Module 'DeviceRepository.Cache' -ErrorAction SilentlyContinue
            }
            if ($cacheExportCmd -and $snapshotEntryCount -gt 0) {
                try {
                    $siteFilter = [System.Collections.Generic.List[string]]::new()
                    try {
                        $filterSites = @($deviceRepoModule.Invoke({ param($entries) Get-SharedCacheSiteFilterFromEntries -Entries $entries }, $snapshotEntries))
                        if ($filterSites -and $filterSites.Count -gt 0) {
                            foreach ($site in $filterSites) { if (-not [string]::IsNullOrWhiteSpace($site)) { $siteFilter.Add($site) | Out-Null } }
                        }
                    } catch {
                        foreach ($entry in $snapshotEntries) {
                            if (-not $entry) { continue }
                            $siteValue = ''
                            if ($entry.PSObject.Properties.Name -contains 'Site') {
                                $siteValue = ('' + $entry.Site).Trim()
                            } elseif ($entry.PSObject.Properties.Name -contains 'SiteKey') {
                                $siteValue = ('' + $entry.SiteKey).Trim()
                            }
                            if (-not [string]::IsNullOrWhiteSpace($siteValue)) {
                                $siteFilter.Add($siteValue) | Out-Null
                            }
                        }
                    }

                    $exportArgs = @{ OutputPath = $SharedCacheSnapshotExportPath }
                    if ($siteFilter.Count -gt 0) { $exportArgs['SiteFilter'] = $siteFilter.ToArray() }

                    & $cacheExportCmd @exportArgs | Out-Null
                    $exported = $true
                    Write-Verbose ("Shared cache snapshot exported via DeviceRepository.Cache to '{0}'." -f $SharedCacheSnapshotExportPath)
                    if (Test-Path -LiteralPath $SharedCacheSnapshotExportPath) {
                        $exportCheck = $null
                        try { $exportCheck = Import-Clixml -Path $SharedCacheSnapshotExportPath } catch { $exportCheck = $null }
                        $exportedCount = 0
                        if ($exportCheck) {
                            try { $exportedCount = ($exportCheck | Measure-Object).Count } catch { $exportedCount = 0 }
                        }
                        if ($exportedCount -le 0) {
                            Write-Verbose ("Shared cache snapshot at '{0}' contained no entries after export; falling back to local writer." -f $SharedCacheSnapshotExportPath)
                            $exported = $false
                        }
                    }
                } catch {
                    Write-Verbose ("Shared cache snapshot export via DeviceRepository.Cache failed: {0}" -f $_.Exception.Message)
                }
            }

            if (-not $exported) {
                if ($snapshotEntryCount -le 0) {
                    $snapshotEntries = Get-SharedCacheSnapshotEntriesForExport -DeviceRepoModule $deviceRepoModule
                    $snapshotEntryCount = ($snapshotEntries | Measure-Object).Count
                    Write-Verbose ("Shared cache snapshot entries captured: {0}" -f $snapshotEntryCount)
                }

                if ($snapshotEntryCount -gt 0) {
                    $fallbackWriter = Get-Command -Name 'DeviceRepository.Cache\Write-SharedCacheSnapshotFileFallback' -ErrorAction SilentlyContinue
                    if (-not $fallbackWriter) {
                        $fallbackWriter = Get-Command -Name 'Write-SharedCacheSnapshotFileFallback' -Module 'DeviceRepository.Cache' -ErrorAction SilentlyContinue
                    }
                    if ($fallbackWriter) {
                        try {
                            & $fallbackWriter -Path $SharedCacheSnapshotExportPath -Entries $snapshotEntries
                        } catch {
                            Write-Verbose ("Fallback shared cache snapshot export via DeviceRepository.Cache failed: {0}" -f $_.Exception.Message)
                            Write-SharedCacheSnapshotFileInternal -Path $SharedCacheSnapshotExportPath -Entries $snapshotEntries
                        }
                    } else {
                        Write-SharedCacheSnapshotFileInternal -Path $SharedCacheSnapshotExportPath -Entries $snapshotEntries
                    }
                } else {
                    Write-Verbose ("Shared cache snapshot export skipped (no entries).")
                }
            }
        } catch {
            Write-Warning ("Failed to export shared cache snapshot to '{0}': {1}" -f $SharedCacheSnapshotExportPath, $_.Exception.Message)
        }
        try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::ClearSnapshot() } catch { }
    }

    Write-Host "Processing complete." -ForegroundColor Yellow

}

Export-ModuleMember -Function Invoke-StateTraceParsing
