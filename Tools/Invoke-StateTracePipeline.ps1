param(
    [switch]$SkipTests,
    [switch]$SkipParsing,
    [string]$DatabasePath,
    [int]$ThreadCeilingOverride,
    [int]$MaxWorkersPerSiteOverride,
    [int]$MaxActiveSitesOverride,
    [int]$JobsPerThreadOverride,
    [int]$MinRunspacesOverride,
    [switch]$VerboseParsing,
    [switch]$ResetExtractedLogs,
    [switch]$PreserveModuleSession,
    [switch]$RunWarmRunRegression,
    [string]$WarmRunRegressionOutputPath,
    [string]$SharedCacheSnapshotPath,
    [string]$SharedCacheSnapshotExportPath,
    [switch]$DisableSharedCacheSnapshot,
    [string]$SharedCacheSnapshotDirectory,
    [switch]$ShowSharedCacheSummary,
    [switch]$RunSharedCacheDiagnostics,
    [int]$SharedCacheDiagnosticsTopHosts = 10
)

$sharedCacheSnapshotEnvOriginal = $null
$sharedCacheSnapshotEnvApplied = $false

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$modulesPath = Join-Path -Path $repositoryRoot -ChildPath 'Modules'
$testsPath = Join-Path -Path $modulesPath -ChildPath 'Tests'
$parserWorkerModule = Join-Path -Path $modulesPath -ChildPath 'ParserWorker.psm1'
$ingestionMetricsDirectory = Join-Path -Path $repositoryRoot -ChildPath 'Logs\IngestionMetrics'

$pathSeparator = [System.IO.Path]::PathSeparator
$resolvedModulesPath = [System.IO.Path]::GetFullPath($modulesPath)
$modulePathEntries = @()
if ($env:PSModulePath) {
    $modulePathEntries = $env:PSModulePath -split [System.IO.Path]::PathSeparator
}
$alreadyPresent = $false
foreach ($entry in $modulePathEntries) {
    if (-not [string]::IsNullOrWhiteSpace($entry)) {
        $normalizedEntry = [System.IO.Path]::GetFullPath($entry)
        if ([System.StringComparer]::OrdinalIgnoreCase.Equals($normalizedEntry.TrimEnd('\'), $resolvedModulesPath.TrimEnd('\'))) {
            $alreadyPresent = $true
            break
        }
    }
}
if (-not $alreadyPresent) {
    if ([string]::IsNullOrWhiteSpace($env:PSModulePath)) {
        $env:PSModulePath = $resolvedModulesPath
    } else {
        $env:PSModulePath = $resolvedModulesPath + $pathSeparator + $env:PSModulePath
    }
}

function Invoke-WarmRunRegressionInternal {
    $warmRunRegressionScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Invoke-WarmRunRegression.ps1'
    if (-not (Test-Path -LiteralPath $warmRunRegressionScript)) {
        throw "Warm-run regression script not found at $warmRunRegressionScript"
    }

    $pwshCommand = Get-Command -Name 'pwsh' -ErrorAction Stop
    $pwshExecutable = $pwshCommand.Source
    $argumentList = @('-NoLogo','-NoProfile','-File',$warmRunRegressionScript)
    if ($VerboseParsing) {
        $argumentList += '-VerboseParsing'
    }
    if ($ResetExtractedLogs) {
        $argumentList += '-ResetExtractedLogs'
    }
    if (-not [string]::IsNullOrWhiteSpace($WarmRunRegressionOutputPath)) {
        $resolvedOutput = $WarmRunRegressionOutputPath
        try {
            $resolvedOutput = (Resolve-Path -LiteralPath $WarmRunRegressionOutputPath -ErrorAction Stop).Path
        } catch {
            $resolvedOutput = [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location) -ChildPath $WarmRunRegressionOutputPath))
        }
        $argumentList += @('-OutputPath', $resolvedOutput)
    }

    Write-Host 'Running preserved-session warm-run regression...' -ForegroundColor Cyan
    & $pwshExecutable @argumentList
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Warm-run regression failed with exit code $exitCode."
    }
    Write-Host 'Warm-run regression completed successfully.' -ForegroundColor Green
}

function Resolve-RelativePath {
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $null }
    try {
        return (Resolve-Path -LiteralPath $PathValue -ErrorAction Stop).Path
    } catch {
        if ([System.IO.Path]::IsPathRooted($PathValue)) {
            return [System.IO.Path]::GetFullPath($PathValue)
        }
        $basePath = (Get-Location).ProviderPath
        return [System.IO.Path]::GetFullPath($PathValue, $basePath)
    }
}

function Restore-SharedCacheEntries {
    param(
        [System.Collections.IEnumerable]$Entries
    )

    if (-not $Entries) { return 0 }
    $entryArray = @($Entries)
    if (-not $entryArray -or $entryArray.Count -eq 0) { return 0 }

    $sitesToWarm = New-Object 'System.Collections.Generic.List[string]'
    $siteEntryTable = @{}
    foreach ($entry in $entryArray) {
        if (-not $entry) { continue }
        $siteName = ''
        if ($entry.PSObject.Properties.Name -contains 'Site') {
            $siteName = ('' + $entry.Site).Trim()
        } elseif ($entry.PSObject.Properties.Name -contains 'SiteKey') {
            $siteName = ('' + $entry.SiteKey).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($siteName)) { continue }
        if (-not ($sitesToWarm.Contains($siteName))) {
            $null = $sitesToWarm.Add($siteName)
        }
        if ($entry.PSObject.Properties.Name -contains 'Entry') {
            $entryValue = $entry.Entry
            if ($entryValue) {
                $siteEntryTable[$siteName] = $entryValue
            }
        }
    }

    if ($sitesToWarm.Count -eq 0) { return 0 }

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
                } elseif ($item.PSObject.Properties.Name -contains 'SiteKey') {
                    $siteKey = ('' + $item.SiteKey).Trim()
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
                } elseif ($item.PSObject.Properties.Name -contains 'SiteKey') {
                    $siteKey = ('' + $item.SiteKey).Trim()
                }
                if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }
                try { Get-InterfaceSiteCache -Site $siteKey | Out-Null } catch { }
            }

            return $restored
        },
        @{ EntryList = $entryArray }
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

function Restore-SharedCacheEntriesFromFile {
    param([string]$SnapshotPath)

    if ([string]::IsNullOrWhiteSpace($SnapshotPath)) { return 0 }
    if (-not (Test-Path -LiteralPath $SnapshotPath)) {
        Write-Warning ("Shared cache snapshot '{0}' was not found." -f $SnapshotPath)
        return 0
    }

    $entries = $null
    try {
        $entries = Import-Clixml -Path $SnapshotPath
    } catch {
        Write-Warning ("Failed to import shared cache snapshot '{0}': {1}" -f $SnapshotPath, $_.Exception.Message)
        return 0
    }

    return Restore-SharedCacheEntries -Entries @($entries)
}

function Get-SharedCacheEntriesForExport {
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

    $entries = $module.Invoke({ Get-SharedSiteInterfaceCacheSnapshotEntries })
    $entryCount = ($entries | Measure-Object).Count
    Write-Verbose ("Shared cache snapshot entries available: {0}" -f $entryCount)
    if (-not $entries -or $entryCount -eq 0) {
        $entries = $module.Invoke(
            {
                $result = New-Object 'System.Collections.Generic.List[psobject]'
                $store = Get-SharedSiteInterfaceCacheStore
                if ($store -is [System.Collections.IDictionary]) {
                    foreach ($siteKey in @($store.Keys)) {
                        if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }
                        $entry = $null
                        try { $entry = Get-SharedSiteInterfaceCacheEntry -SiteKey $siteKey } catch { $entry = $null }
                        if ($entry) {
                            $result.Add([pscustomobject]@{
                                    Site  = $siteKey
                                    Entry = $entry
                                }) | Out-Null
                        }
                    }
                }
                return ,$result.ToArray()
            }
        )
    }

    Write-Verbose ("Shared cache entries selected for export: {0}" -f (($entries | Measure-Object).Count))

    if (-not $entries) { return @() }
    return @($entries)
}

function Write-SharedCacheSnapshotFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [System.Collections.IEnumerable]$Entries
    )

    $entryArray = @($Entries)
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
        if (-not $entryValue) { continue }

        $sanitizedEntries.Add([pscustomobject]@{
                Site  = $siteValue
                Entry = $entryValue
            }) | Out-Null
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

function Get-SharedCacheSnapshotSummary {
    param([Parameter(Mandatory)][string]$SnapshotPath)

    if (-not (Test-Path -LiteralPath $SnapshotPath)) {
        return @()
    }

    $entries = Import-Clixml -Path $SnapshotPath
    if (-not $entries) { return @() }
    if (-not ($entries -is [System.Collections.IEnumerable])) {
        $entries = @($entries)
    }

    $summaries = New-Object 'System.Collections.Generic.List[psobject]'
    foreach ($entry in $entries) {
        if (-not $entry) { continue }
        $siteValue = ''
        if ($entry.PSObject.Properties.Name -contains 'Site') {
            $siteValue = ('' + $entry.Site).Trim()
        } elseif ($entry.PSObject.Properties.Name -contains 'SiteKey') {
            $siteValue = ('' + $entry.SiteKey).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($siteValue)) { continue }

        $snapshotEntry = $entry
        if ($entry.PSObject.Properties.Name -contains 'Entry') {
            $snapshotEntry = $entry.Entry
        }
        if (-not $snapshotEntry) { continue }

        $hostCount = 0
        $rowCount = 0
        $cachedAt = $null
        if ($snapshotEntry.PSObject.Properties.Name -contains 'HostCount') {
            try { $hostCount = [int]$snapshotEntry.HostCount } catch { $hostCount = 0 }
        }
        if ($snapshotEntry.PSObject.Properties.Name -contains 'TotalRows') {
            try { $rowCount = [int]$snapshotEntry.TotalRows } catch { $rowCount = 0 }
        }
        if ($snapshotEntry.PSObject.Properties.Name -contains 'CachedAt') {
            $cachedAt = $snapshotEntry.CachedAt
        }

        $summaries.Add([pscustomobject]@{
                Site      = $siteValue
                Hosts     = $hostCount
                TotalRows = $rowCount
                CachedAt  = $cachedAt
            }) | Out-Null
    }

    return $summaries.ToArray()
}

function Write-SharedCacheSnapshotSummaryFiles {
    param(
        [Parameter(Mandatory)][string]$SnapshotPath,
        [string]$TimestampSummaryPath,
        [string]$LatestSummaryPath
    )

    if (-not (Test-Path -LiteralPath $SnapshotPath)) { return }

    $summaryEntries = Get-SharedCacheSnapshotSummary -SnapshotPath $SnapshotPath
    if (-not $summaryEntries -or $summaryEntries.Count -eq 0) {
        Write-Verbose ("Shared cache snapshot '{0}' did not contain any entries to summarise." -f $SnapshotPath)
        return
    }

    $json = $summaryEntries | ConvertTo-Json -Depth 5

    if (-not [string]::IsNullOrWhiteSpace($TimestampSummaryPath)) {
        try {
            $timestampDirectory = Split-Path -Parent $TimestampSummaryPath
            if (-not [string]::IsNullOrWhiteSpace($timestampDirectory) -and -not (Test-Path -LiteralPath $timestampDirectory)) {
                New-Item -ItemType Directory -Path $timestampDirectory -Force | Out-Null
            }
            Set-Content -LiteralPath (Resolve-RelativePath -PathValue $TimestampSummaryPath) -Value $json -Encoding utf8
        } catch {
            Write-Warning ("Failed to write snapshot summary '{0}': {1}" -f $TimestampSummaryPath, $_.Exception.Message)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($LatestSummaryPath)) {
        try {
            $latestDirectory = Split-Path -Parent $LatestSummaryPath
            if (-not [string]::IsNullOrWhiteSpace($latestDirectory) -and -not (Test-Path -LiteralPath $latestDirectory)) {
                New-Item -ItemType Directory -Path $latestDirectory -Force | Out-Null
            }
            Set-Content -LiteralPath (Resolve-RelativePath -PathValue $LatestSummaryPath) -Value $json -Encoding utf8
        } catch {
            Write-Warning ("Failed to update latest snapshot summary '{0}': {1}" -f $LatestSummaryPath, $_.Exception.Message)
        }
    }
}

$defaultSnapshotDirectory = Join-Path -Path $repositoryRoot -ChildPath 'Logs\SharedCacheSnapshot'
$autoSnapshotEnabled = -not $DisableSharedCacheSnapshot.IsPresent
$autoSnapshotDirectory = $null
$autoSnapshotLatestPath = $null
$autoSnapshotTimestampPath = $null
$usingAutoSnapshotExport = $false
$snapshotSummaryPath = $null

$effectiveSharedCacheSnapshotPath = $SharedCacheSnapshotPath
$effectiveSharedCacheSnapshotExportPath = $SharedCacheSnapshotExportPath

if ($autoSnapshotEnabled) {
    $autoSnapshotDirectory = if ([string]::IsNullOrWhiteSpace($SharedCacheSnapshotDirectory)) {
        $defaultSnapshotDirectory
    } else {
        Resolve-RelativePath -PathValue $SharedCacheSnapshotDirectory
    }

    if (-not [string]::IsNullOrWhiteSpace($autoSnapshotDirectory)) {
        try {
            if (-not (Test-Path -LiteralPath $autoSnapshotDirectory)) {
                New-Item -ItemType Directory -Path $autoSnapshotDirectory -Force | Out-Null
            }
        } catch {
            Write-Warning ("Failed to ensure shared cache snapshot directory '{0}': {1}" -f $autoSnapshotDirectory, $_.Exception.Message)
        }

        $autoSnapshotLatestPath = Join-Path -Path $autoSnapshotDirectory -ChildPath 'SharedCacheSnapshot-latest.clixml'
        if (-not $PSBoundParameters.ContainsKey('SharedCacheSnapshotPath') -and (Test-Path -LiteralPath $autoSnapshotLatestPath)) {
            $effectiveSharedCacheSnapshotPath = $autoSnapshotLatestPath
        }
    }

    if (-not $PSBoundParameters.ContainsKey('SharedCacheSnapshotExportPath') -and -not [string]::IsNullOrWhiteSpace($autoSnapshotDirectory)) {
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $autoSnapshotTimestampPath = Join-Path -Path $autoSnapshotDirectory -ChildPath ("SharedCacheSnapshot-{0}.clixml" -f $timestamp)
        $effectiveSharedCacheSnapshotExportPath = $autoSnapshotTimestampPath
        $usingAutoSnapshotExport = $true
    }
}

if (-not [string]::IsNullOrWhiteSpace($effectiveSharedCacheSnapshotPath)) {
    $effectiveSharedCacheSnapshotPath = Resolve-RelativePath -PathValue $effectiveSharedCacheSnapshotPath
    if (-not $snapshotSummaryPath) {
        $snapshotSummaryPath = $effectiveSharedCacheSnapshotPath
    }
}
if (-not [string]::IsNullOrWhiteSpace($effectiveSharedCacheSnapshotExportPath)) {
    $effectiveSharedCacheSnapshotExportPath = Resolve-RelativePath -PathValue $effectiveSharedCacheSnapshotExportPath
    $snapshotSummaryPath = $effectiveSharedCacheSnapshotExportPath
}

if (-not $SkipTests) {
    if (-not (Test-Path -LiteralPath $testsPath)) {
        throw "Pester test directory not found at $testsPath"
    }

    if (-not (Get-Command -Name Invoke-Pester -ErrorAction SilentlyContinue)) {
        throw 'Invoke-Pester is not available in the current session.'
    }

    Write-Host 'Running Pester tests (Modules/Tests)...' -ForegroundColor Cyan
    $pesterResult = Invoke-Pester -Path $testsPath -PassThru
    if ($null -ne $pesterResult -and $pesterResult.FailedCount -gt 0) {
        throw "Pester reported $($pesterResult.FailedCount) failing tests."
    }
    Write-Host 'Pester tests completed successfully.' -ForegroundColor Green
}

if ($SkipParsing) {
    if ($VerboseParsing) {
        Write-Host 'Skipping ingestion run because -SkipParsing was supplied.' -ForegroundColor Yellow
    }
    if ($RunWarmRunRegression) {
        Invoke-WarmRunRegressionInternal
    }
    return
}

# Load modules from manifest so module-qualified calls resolve during ingestion
$manifestPath = Join-Path -Path $modulesPath -ChildPath 'ModulesManifest.psd1'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Module manifest not found at $manifestPath"
}

if (Get-Command -Name Import-PowerShellDataFile -ErrorAction SilentlyContinue) {
    $manifest = Import-PowerShellDataFile -Path $manifestPath
} else {
    $manifest = . $manifestPath
}

$modulesToImport = @()
if ($manifest -is [hashtable] -and $manifest.ContainsKey('ModulesToImport') -and $manifest['ModulesToImport']) {
    $modulesToImport = $manifest['ModulesToImport']
} elseif ($manifest -is [hashtable] -and $manifest.ContainsKey('Modules') -and $manifest['Modules']) {
    $modulesToImport = $manifest['Modules']
} else {
    throw 'No modules defined in ModulesManifest.psd1.'
}

foreach ($moduleEntry in $modulesToImport) {
    if ([string]::IsNullOrWhiteSpace($moduleEntry)) { continue }
    if ([System.StringComparer]::OrdinalIgnoreCase.Equals($moduleEntry.Trim(), 'ParserWorker.psm1')) { continue }
    $candidatePath = if ([System.IO.Path]::IsPathRooted($moduleEntry)) {
        $moduleEntry
    } else {
        Join-Path -Path $modulesPath -ChildPath $moduleEntry
    }
    if (-not (Test-Path -LiteralPath $candidatePath)) {
        throw "Module entry '$moduleEntry' not found at $candidatePath"
    }
    $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($candidatePath)
    $loadedModule = $null
    if (-not [string]::IsNullOrWhiteSpace($moduleName)) {
        $loadedModule = Get-Module -Name $moduleName -ErrorAction SilentlyContinue
    }
    if ($PreserveModuleSession -and $loadedModule) {
        continue
    }
    $importArgs = @{
        Name        = $candidatePath
        ErrorAction = 'Stop'
    }
    if (-not $PreserveModuleSession -or -not $loadedModule) {
        $importArgs['Force'] = $true
    }
    Import-Module @importArgs | Out-Null
}

if (-not (Test-Path -LiteralPath $parserWorkerModule)) {
    throw "ParserWorker module not found at $parserWorkerModule"
}

if ($ResetExtractedLogs) {
    $extractedRoot = Join-Path -Path $repositoryRoot -ChildPath 'Logs'
    $extractedPath = Join-Path -Path $extractedRoot -ChildPath 'Extracted'
    if (Test-Path -LiteralPath $extractedPath) {
        Write-Host "Resetting extracted log slices under ${extractedPath}..." -ForegroundColor Yellow
        try {
            Get-ChildItem -LiteralPath $extractedPath -Force -Recurse | Remove-Item -Force -Recurse
        } catch {
            Write-Warning "Failed to reset extracted logs in ${extractedPath}: $($_.Exception.Message)"
        }
    } elseif ($VerboseParsing) {
        Write-Host "No extracted log directory found at ${extractedPath}; skipping reset." -ForegroundColor Yellow
    }
}

$restoredSharedCacheCount = 0
if (-not [string]::IsNullOrWhiteSpace($effectiveSharedCacheSnapshotPath)) {
    if (-not $sharedCacheSnapshotEnvApplied) {
        try { $sharedCacheSnapshotEnvOriginal = $env:STATETRACE_SHARED_CACHE_SNAPSHOT } catch { $sharedCacheSnapshotEnvOriginal = $null }
        try {
            $env:STATETRACE_SHARED_CACHE_SNAPSHOT = $effectiveSharedCacheSnapshotPath
            $sharedCacheSnapshotEnvApplied = $true
        } catch {
            $sharedCacheSnapshotEnvApplied = $false
        }
    }
    $restoredSharedCacheCount = Restore-SharedCacheEntriesFromFile -SnapshotPath $effectiveSharedCacheSnapshotPath
    if ($restoredSharedCacheCount -gt 0) {
        Write-Host ("Restored {0} shared cache entr{1} from snapshot '{2}'." -f $restoredSharedCacheCount, $(if ($restoredSharedCacheCount -eq 1) { 'y' } else { 'ies' }), $effectiveSharedCacheSnapshotPath) -ForegroundColor DarkCyan
    } elseif ($VerboseParsing -and (Test-Path -LiteralPath $effectiveSharedCacheSnapshotPath)) {
        Write-Host ("Shared cache snapshot '{0}' did not contain any restorable entries." -f $effectiveSharedCacheSnapshotPath) -ForegroundColor DarkGray
    }
}

Write-Host 'Starting ingestion run via Invoke-StateTraceParsing -Synchronous...' -ForegroundColor Cyan
$parserWorkerName = [System.IO.Path]::GetFileNameWithoutExtension($parserWorkerModule)
$existingParserWorker = $null
if (-not [string]::IsNullOrWhiteSpace($parserWorkerName)) {
    $existingParserWorker = Get-Module -Name $parserWorkerName -ErrorAction SilentlyContinue
}
$module = $null
if ($PreserveModuleSession -and $existingParserWorker) {
    $module = $existingParserWorker
} else {
    $parserImportArgs = @{
        Name        = $parserWorkerModule
        ErrorAction = 'Stop'
        PassThru    = $true
    }
    if (-not $PreserveModuleSession -or -not $existingParserWorker) {
        $parserImportArgs['Force'] = $true
    }
    $module = Import-Module @parserImportArgs
}

$invokeParams = @{ Synchronous = $true }
if ($PSBoundParameters.ContainsKey('DatabasePath')) {
    $invokeParams['DatabasePath'] = $DatabasePath
}
if ($PSBoundParameters.ContainsKey('ThreadCeilingOverride')) {
    $invokeParams['ThreadCeilingOverride'] = $ThreadCeilingOverride
}
if ($PSBoundParameters.ContainsKey('MaxWorkersPerSiteOverride')) {
    $invokeParams['MaxWorkersPerSiteOverride'] = $MaxWorkersPerSiteOverride
}
if ($PSBoundParameters.ContainsKey('MaxActiveSitesOverride')) {
    $invokeParams['MaxActiveSitesOverride'] = $MaxActiveSitesOverride
}
if ($PSBoundParameters.ContainsKey('JobsPerThreadOverride')) {
    $invokeParams['JobsPerThreadOverride'] = $JobsPerThreadOverride
}
if ($PSBoundParameters.ContainsKey('MinRunspacesOverride')) {
    $invokeParams['MinRunspacesOverride'] = $MinRunspacesOverride
}
if ($PreserveModuleSession) {
    $invokeParams['PreserveRunspace'] = $true
}
if (-not [string]::IsNullOrWhiteSpace($effectiveSharedCacheSnapshotExportPath)) {
    $invokeParams['SharedCacheSnapshotExportPath'] = $effectiveSharedCacheSnapshotExportPath
}

try {
    if ($VerboseParsing) {
        Invoke-StateTraceParsing @invokeParams -Verbose
    } else {
        Invoke-StateTraceParsing @invokeParams
    }
} finally {
    if ($module -and -not $PreserveModuleSession) {
        Remove-Module -ModuleInfo $module -Force -ErrorAction SilentlyContinue
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
}

Write-Host 'Ingestion run completed.' -ForegroundColor Green

if ($RunWarmRunRegression) {
    Invoke-WarmRunRegressionInternal
}

if ($RunSharedCacheDiagnostics) {
    try {
        $latestLogEntry = $null
        if (Test-Path -LiteralPath $ingestionMetricsDirectory) {
            $latestLogEntry = Get-ChildItem -LiteralPath $ingestionMetricsDirectory -Filter '*.json' -File |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
        }

        if (-not $latestLogEntry) {
            Write-Warning 'Shared cache diagnostics skipped: no ingestion metrics files were found.'
        } else {
            $latestLogPath = $latestLogEntry.FullName
            Write-Host ("Running shared cache diagnostics against '{0}'..." -f $latestLogPath) -ForegroundColor Cyan

            $storeAnalyzer = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Analyze-SharedCacheStoreState.ps1'
            if (Test-Path -LiteralPath $storeAnalyzer) {
                try {
                    & $storeAnalyzer -Path $latestLogPath -IncludeSiteBreakdown
                } catch {
                    Write-Warning ("Shared cache store analyzer failed: {0}" -f $_.Exception.Message)
                }
            } else {
                Write-Warning ("Shared cache store analyzer '{0}' was not found." -f $storeAnalyzer)
            }

            $providerAnalyzer = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Analyze-SiteCacheProviderReasons.ps1'
            if (Test-Path -LiteralPath $providerAnalyzer) {
                try {
                    & $providerAnalyzer -Path $latestLogPath -IncludeHostBreakdown -TopHosts $SharedCacheDiagnosticsTopHosts
                } catch {
                    Write-Warning ("Provider reason analyzer failed: {0}" -f $_.Exception.Message)
                }
            } else {
                Write-Warning ("Provider reason analyzer '{0}' was not found." -f $providerAnalyzer)
            }
        }
    } catch {
        Write-Warning ("Shared cache diagnostics encountered an unexpected error: {0}" -f $_.Exception.Message)
    }
}

$timestampSummaryPath = $null
if (-not [string]::IsNullOrWhiteSpace($effectiveSharedCacheSnapshotExportPath) -and (Test-Path -LiteralPath $effectiveSharedCacheSnapshotExportPath)) {
    $exportDir = Split-Path -Parent $effectiveSharedCacheSnapshotExportPath
    $exportName = [System.IO.Path]::GetFileNameWithoutExtension($effectiveSharedCacheSnapshotExportPath)
    if (-not [string]::IsNullOrWhiteSpace($exportDir) -and -not [string]::IsNullOrWhiteSpace($exportName)) {
        $timestampSummaryPath = Join-Path -Path $exportDir -ChildPath ($exportName + '-summary.json')
    }
}

$latestSummaryPath = $null
if (-not [string]::IsNullOrWhiteSpace($snapshotSummaryPath)) {
    $summaryDir = Split-Path -Parent $snapshotSummaryPath
    if (-not [string]::IsNullOrWhiteSpace($summaryDir)) {
        $latestSummaryPath = Join-Path -Path $summaryDir -ChildPath 'SharedCacheSnapshot-latest-summary.json'
    }
}

if (-not [string]::IsNullOrWhiteSpace($snapshotSummaryPath) -and (Test-Path -LiteralPath $snapshotSummaryPath)) {
    Write-SharedCacheSnapshotSummaryFiles -SnapshotPath $snapshotSummaryPath -TimestampSummaryPath $timestampSummaryPath -LatestSummaryPath $latestSummaryPath
}

if ($usingAutoSnapshotExport -and -not [string]::IsNullOrWhiteSpace($autoSnapshotLatestPath)) {
    if ($autoSnapshotTimestampPath -and (Test-Path -LiteralPath $autoSnapshotTimestampPath)) {
        try {
            Copy-Item -LiteralPath $autoSnapshotTimestampPath -Destination $autoSnapshotLatestPath -Force
            if ($VerboseParsing) {
                Write-Host ("Latest shared cache snapshot updated at '{0}'." -f $autoSnapshotLatestPath) -ForegroundColor DarkGray
            }
            $snapshotSummaryPath = $autoSnapshotLatestPath
        } catch {
            Write-Warning ("Failed to update shared cache snapshot pointer '{0}': {1}" -f $autoSnapshotLatestPath, $_.Exception.Message)
        }
    } elseif ($VerboseParsing) {
        Write-Host ("Shared cache snapshot export at '{0}' was not created; latest pointer was not updated." -f $autoSnapshotTimestampPath) -ForegroundColor DarkGray
    }
}

if ($ShowSharedCacheSummary.IsPresent) {
    if ($DisableSharedCacheSnapshot.IsPresent) {
        Write-Warning 'Shared cache snapshot summary was requested, but automatic snapshots are disabled for this run.'
    } elseif (-not $snapshotSummaryPath -or -not (Test-Path -LiteralPath $snapshotSummaryPath)) {
        Write-Warning 'Unable to locate a shared cache snapshot to summarize. Run the pipeline once with snapshots enabled.'
    } else {
        $summaryData = @()
        try {
            $summaryData = Get-SharedCacheSnapshotSummary -SnapshotPath $snapshotSummaryPath
        } catch {
            Write-Warning ("Failed to gather shared cache snapshot summary: {0}" -f $_.Exception.Message)
        }

        Write-Host 'Shared cache snapshot summary:' -ForegroundColor Cyan
        if ($summaryData -and $summaryData.Count -gt 0) {
            $summaryData |
                Sort-Object Site |
                Format-Table Site, Hosts, TotalRows, CachedAt -AutoSize
        } else {
            Write-Host '  (No entries reported)' -ForegroundColor DarkGray
        }
    }
}
