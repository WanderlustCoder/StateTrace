param(
    [ValidateSet('Quick','Full','Diag')]
    [string]$Profile,
    [switch]$SkipTests,
    [switch]$SkipParsing,
    [string]$DatabasePath,
    [int]$ThreadCeilingOverride,
    [int]$MaxWorkersPerSiteOverride,
    [int]$MaxActiveSitesOverride,
    [int]$MaxConsecutiveSiteLaunchesOverride,
    [int]$JobsPerThreadOverride,
    [int]$MinRunspacesOverride,
    [switch]$VerboseParsing,
    [switch]$ResetExtractedLogs,
    [switch]$DisableSkipSiteCacheUpdate,
    [switch]$SkipPortDiversityGuard,
    [int]$PortBatchMaxConsecutiveOverride,
    [switch]$SkipWarmValidation,
    [switch]$PreserveModuleSession,
    [switch]$RunWarmRunRegression,
    [string]$WarmRunRegressionOutputPath,
    [string]$SharedCacheSnapshotPath,
    [string]$SharedCacheSnapshotExportPath,
    [switch]$DisableSharedCacheSnapshot,
    [string]$SharedCacheSnapshotDirectory,
    [switch]$ShowSharedCacheSummary,
    [switch]$RunSharedCacheDiagnostics,
    [int]$SharedCacheDiagnosticsTopHosts = 10,
    [switch]$VerifyTelemetryCompleteness,
    [switch]$FailOnTelemetryMissing,
    [switch]$SynthesizeSchedulerTelemetryOnMissing,
    [switch]$FailOnSchedulerFairness = $true,
    [switch]$RequireTelemetryIntegrity,
    [switch]$DisablePreserveRunspace,
    [switch]$QuickMode
)

$sharedCacheSnapshotEnvOriginal = $null
$sharedCacheSnapshotEnvApplied = $false

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$profileBoundParameters = $PSBoundParameters
function Set-ProfileSwitch {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Value
    )
    if (-not $profileBoundParameters.ContainsKey($Name)) {
        Set-Variable -Scope Script -Name $Name -Value $Value
    }
}

if ($Profile) {
    switch ($Profile) {
        'Quick' {
            Set-ProfileSwitch -Name 'SkipTests' -Value $true
            Set-ProfileSwitch -Name 'QuickMode' -Value $true
            Set-ProfileSwitch -Name 'ResetExtractedLogs' -Value $true
            Set-ProfileSwitch -Name 'SkipWarmValidation' -Value $true
        }
        'Full' {
            Set-ProfileSwitch -Name 'QuickMode' -Value $false
            Set-ProfileSwitch -Name 'ResetExtractedLogs' -Value $true
            Set-ProfileSwitch -Name 'VerifyTelemetryCompleteness' -Value $true
            Set-ProfileSwitch -Name 'FailOnTelemetryMissing' -Value $true
        }
        'Diag' {
            Set-ProfileSwitch -Name 'QuickMode' -Value $false
            Set-ProfileSwitch -Name 'ResetExtractedLogs' -Value $true
            Set-ProfileSwitch -Name 'VerboseParsing' -Value $true
            Set-ProfileSwitch -Name 'RunSharedCacheDiagnostics' -Value $true
            Set-ProfileSwitch -Name 'ShowSharedCacheSummary' -Value $true
            Set-ProfileSwitch -Name 'VerifyTelemetryCompleteness' -Value $true
            Set-ProfileSwitch -Name 'FailOnTelemetryMissing' -Value $false
            Set-ProfileSwitch -Name 'SynthesizeSchedulerTelemetryOnMissing' -Value $true
        }
    }
}

$skipSiteCacheGuardModule = Join-Path -Path $PSScriptRoot -ChildPath 'SkipSiteCacheUpdateGuard.psm1'
if (-not (Test-Path -LiteralPath $skipSiteCacheGuardModule)) {
    throw "Skip-site-cache guard module not found at $skipSiteCacheGuardModule."
}
Import-Module -Name $skipSiteCacheGuardModule -Force -ErrorAction Stop

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$modulesPath = Join-Path -Path $repositoryRoot -ChildPath 'Modules'
$testsPath = Join-Path -Path $modulesPath -ChildPath 'Tests'
$parserWorkerModule = Join-Path -Path $modulesPath -ChildPath 'ParserWorker.psm1'
$ingestionMetricsDirectory = Join-Path -Path $repositoryRoot -ChildPath 'Logs\IngestionMetrics'
$reportsDirectory = Join-Path -Path $repositoryRoot -ChildPath 'Logs\Reports'
$settingsPath = Join-Path -Path $repositoryRoot -ChildPath 'Data\StateTraceSettings.json'
$skipSiteCacheGuard = $null

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
    if ($SkipPortDiversityGuard) {
        $argumentList += '-SkipPortDiversityGuard'
    }
    if ($PSBoundParameters.ContainsKey('PortBatchMaxConsecutiveOverride')) {
        $argumentList += @('-PortBatchMaxConsecutiveOverride', $PortBatchMaxConsecutiveOverride)
    }
    if ($SkipWarmValidation) {
        $argumentList += '-SkipWarmValidation'
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

    $sitesToWarm = [System.Collections.Generic.List[string]]::new()
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
        $entryValue = $null
        if ($entry.PSObject.Properties.Name -contains 'Entry') {
            $entryValue = $entry.Entry
        } elseif ($entry.PSObject.Properties.Name -contains 'HostMap' -and $entry.HostMap) {
            $entryValue = $entry
        }
        if ($entryValue) {
            $siteEntryTable[$siteName] = $entryValue
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
                if (-not $entryValue -and $item.PSObject.Properties.Name -contains 'HostMap' -and $item.HostMap) {
                    $entryValue = $item
                }
                if (-not $entryValue) { continue }
                $normalizedEntry = Normalize-InterfaceSiteCacheEntry -Entry $entryValue
                if (-not $script:SiteInterfaceSignatureCache) {
                    $script:SiteInterfaceSignatureCache = @{}
                }
                $script:SiteInterfaceSignatureCache[$siteKey] = $normalizedEntry
                # Ensure shared store is available in this session for restored entries.
                try {
                    $store = DeviceRepositoryModule\Get-SharedSiteInterfaceCacheStore
                    if ($store -is [System.Collections.IDictionary]) {
                        try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetStore($store) } catch { }
                        try { [System.AppDomain]::CurrentDomain.SetData('StateTrace.Repository.SharedSiteInterfaceCache', $store) } catch { }
                    }
                } catch { }
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

    $deviceRepoModule = Get-Module -Name 'DeviceRepositoryModule'
    if (-not $deviceRepoModule) {
        $repoPath = Join-Path -Path $repositoryRoot -ChildPath 'Modules\DeviceRepositoryModule.psm1'
        if (Test-Path -LiteralPath $repoPath) {
            try { $deviceRepoModule = Import-Module -Name $repoPath -PassThru -ErrorAction SilentlyContinue } catch { $deviceRepoModule = $null }
        }
    }
    if ($deviceRepoModule) {
        try { $entries = @($deviceRepoModule.Invoke({ param($e) Resolve-SharedSiteInterfaceCacheSnapshotEntries -Entries $e }, @($entries))) } catch { }
    }

    $summaries = [System.Collections.Generic.List[psobject]]::new()
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
        $stats = $null
        if ($deviceRepoModule) {
            try { $stats = $deviceRepoModule.Invoke({ param($value) Get-SharedSiteInterfaceCacheEntryStatistics -Entry $value }, $snapshotEntry) } catch { $stats = $null }
        }
        if ($stats) {
            try { $hostCount = [int]$stats.HostCount } catch { $hostCount = 0 }
            try { $rowCount = [int]$stats.TotalRows } catch { $rowCount = 0 }
        }
        $cachedAt = $null
        if ($hostCount -le 0 -and $snapshotEntry.PSObject.Properties.Name -contains 'HostCount') {
            try { $hostCount = [int]$snapshotEntry.HostCount } catch { $hostCount = 0 }
        }
        if ($rowCount -le 0 -and $snapshotEntry.PSObject.Properties.Name -contains 'TotalRows') {
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

try {
    if ($DisableSkipSiteCacheUpdate.IsPresent) {
        $skipSiteCacheGuard = Disable-SkipSiteCacheUpdateSetting -SettingsPath $settingsPath -Label 'StateTracePipeline'
    }

if (-not $SkipTests) {
    if (-not (Test-Path -LiteralPath $testsPath)) {
        throw "Pester test directory not found at $testsPath"
    }

    if (-not (Get-Command -Name Invoke-Pester -ErrorAction SilentlyContinue)) {
        throw 'Invoke-Pester is not available in the current session.'
    }

    $ranInCurrentSession = $false
    $currentApartment = $null
    try { $currentApartment = [System.Threading.Thread]::CurrentThread.GetApartmentState() } catch { }
    if ($currentApartment -ne [System.Threading.ApartmentState]::STA) {
        try { [void][System.Threading.Thread]::CurrentThread.TrySetApartmentState([System.Threading.ApartmentState]::STA) } catch { }
        try { $currentApartment = [System.Threading.Thread]::CurrentThread.GetApartmentState() } catch { }
    }

    if ($currentApartment -eq [System.Threading.ApartmentState]::STA) {
        Write-Host 'Running Pester tests (Modules/Tests)...' -ForegroundColor Cyan
        $pesterResult = Invoke-Pester -Path $testsPath -PassThru
        $ranInCurrentSession = $true
    } else {
        Write-Host 'Running Pester tests (Modules/Tests) in STA helper process...' -ForegroundColor Cyan
        $pesterCmd = "& { Import-Module Pester -ErrorAction Stop; `$result = Invoke-Pester -Path '$testsPath' -PassThru; if(`$null -ne `$result -and `$result.FailedCount -gt 0){ exit 3 } }"
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Sta -Command `"$pesterCmd`""
        $psi.RedirectStandardOutput = $false
        $psi.RedirectStandardError = $false
        $psi.UseShellExecute = $false
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.WaitForExit()
        $pesterResult = $null
        if ($proc.ExitCode -ne 0) {
            throw "Pester reported failures in STA helper (exit code $($proc.ExitCode))."
        }
    }

    if ($null -ne $pesterResult -and $pesterResult.FailedCount -gt 0) {
        throw "Pester reported $($pesterResult.FailedCount) failing tests."
    }
    if ($ranInCurrentSession) {
        Write-Host 'Pester tests completed successfully.' -ForegroundColor Green
    } else {
        Write-Host 'Pester tests completed successfully in STA helper.' -ForegroundColor Green
    }
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
$moduleLoaderPath = Join-Path -Path $modulesPath -ChildPath 'ModuleLoaderModule.psm1'
if (-not (Test-Path -LiteralPath $moduleLoaderPath)) {
    throw "Module loader not found at $moduleLoaderPath"
}
Import-Module -Name $moduleLoaderPath -Force -ErrorAction Stop | Out-Null
$manifestImportParams = @{
    RepositoryRoot = $repositoryRoot
    Exclude        = @('ParserWorker.psm1')
}
if ($PreserveModuleSession) {
    $manifestImportParams['PreserveIfLoaded'] = $true
} else {
    $manifestImportParams['Force'] = $true
}
ModuleLoaderModule\Import-StateTraceModulesFromManifest @manifestImportParams | Out-Null

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

if ($DisablePreserveRunspace) {
    Write-Host 'Starting ingestion run via Invoke-StateTraceParsing (single-session)...' -ForegroundColor Cyan
} else {
    Write-Host 'Starting ingestion run via Invoke-StateTraceParsing (preserved runspace pool)...' -ForegroundColor Cyan
}
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
if (-not $DisablePreserveRunspace) {
    $invokeParams['PreserveRunspace'] = $true
}
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
if ($PSBoundParameters.ContainsKey('MaxConsecutiveSiteLaunchesOverride')) {
    $invokeParams['MaxConsecutiveSiteLaunchesOverride'] = $MaxConsecutiveSiteLaunchesOverride
}
if ($PSBoundParameters.ContainsKey('JobsPerThreadOverride')) {
    $invokeParams['JobsPerThreadOverride'] = $JobsPerThreadOverride
}
if ($PSBoundParameters.ContainsKey('MinRunspacesOverride')) {
    $invokeParams['MinRunspacesOverride'] = $MinRunspacesOverride
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

$latestIngestionMetricsEntry = $null
    try {
        $telemetryLogPath = $null
        try {
            $telemetryPathCmd = Get-TelemetryModuleCommand -Name 'Get-TelemetryLogPath'
            if ($telemetryPathCmd) {
                $telemetryLogPath = & $telemetryPathCmd
            }
        } catch { }

    if (-not [string]::IsNullOrWhiteSpace($telemetryLogPath) -and (Test-Path -LiteralPath $telemetryLogPath)) {
        $latestIngestionMetricsEntry = Get-Item -LiteralPath $telemetryLogPath -ErrorAction Stop
    } elseif (Test-Path -LiteralPath $ingestionMetricsDirectory) {
        $latestIngestionMetricsEntry = Get-ChildItem -LiteralPath $ingestionMetricsDirectory -Filter '*.json' -File |
            Where-Object {
                $baseName = $_.BaseName
                (-not [string]::IsNullOrWhiteSpace($baseName)) -and ($baseName -match '^\d{4}-\d{2}-\d{2}$')
            } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    }
} catch {
    Write-Warning ("Failed to enumerate ingestion metrics files: {0}" -f $_.Exception.Message)
}

$metricsBaseName = $null
$metricsReportSuffix = (Get-Date).ToString('yyyyMMdd-HHmmss')
if ($latestIngestionMetricsEntry) {
    $metricsBaseName = [System.IO.Path]::GetFileNameWithoutExtension($latestIngestionMetricsEntry.Name)
    if (-not [string]::IsNullOrWhiteSpace($metricsBaseName)) {
        $metricsReportSuffix = $metricsBaseName
    }
}

$reportsDirectory = Join-Path -Path $repositoryRoot -ChildPath 'Logs\Reports'
if (-not (Test-Path -LiteralPath $reportsDirectory)) {
    New-Item -Path $reportsDirectory -ItemType Directory -Force | Out-Null
}

$schedulerReportPath = $null
$queueSummaryPath = $null
$portBatchReportPath = $null
$interfaceSyncReportPath = $null
$portDiversityReportPath = $null
if (-not $QuickMode) {
    try {
        $queueSummaryScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Generate-QueueDelaySummary.ps1'
        if (-not (Test-Path -LiteralPath $queueSummaryScript)) {
            Write-Verbose ("Queue delay summary script not found at '{0}', skipping generation." -f $queueSummaryScript)
        } elseif (-not $latestIngestionMetricsEntry) {
            Write-Warning 'Queue delay summary skipped: no ingestion metrics files were found.'
        } else {
            $queueSummaryPath = Join-Path -Path $ingestionMetricsDirectory -ChildPath ("QueueDelaySummary-{0}.json" -f $metricsReportSuffix)
            Write-Host ("Generating queue delay summary '{0}'..." -f $queueSummaryPath) -ForegroundColor Cyan
            & $queueSummaryScript -MetricsPath $latestIngestionMetricsEntry.FullName -OutputPath $queueSummaryPath | Out-Null
        }
    } catch {
        Write-Warning ("Queue delay summary generation failed: {0}" -f $_.Exception.Message)
        $queueSummaryPath = $null
    }

    try {
        $portAnalyzerScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Analyze-PortBatchReadyTelemetry.ps1'
        if (-not (Test-Path -LiteralPath $portAnalyzerScript)) {
            Write-Verbose ("Port batch analyzer '{0}' not found; skipping incremental loading summary." -f $portAnalyzerScript)
        } elseif (-not $latestIngestionMetricsEntry) {
            Write-Warning 'Port batch analyzer skipped: no ingestion metrics files were found.'
        } else {
            $portBatchReportPath = Join-Path -Path $reportsDirectory -ChildPath ("PortBatchReady-{0}.json" -f $metricsReportSuffix)
            Write-Host ("Summarising incremental loading telemetry into '{0}'..." -f $portBatchReportPath) -ForegroundColor Cyan
            & $portAnalyzerScript -Path $latestIngestionMetricsEntry.FullName -IncludeHostBreakdown -OutputPath $portBatchReportPath | Out-Null
        }
    } catch {
        Write-Warning ("Port batch analyzer failed: {0}" -f $_.Exception.Message)
        $portBatchReportPath = $null
    }

    try {
        $interfaceAnalyzerScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Analyze-InterfaceSyncTiming.ps1'
        if (-not (Test-Path -LiteralPath $interfaceAnalyzerScript)) {
            Write-Verbose ("InterfaceSync analyzer '{0}' not found; skipping InterfaceSyncTiming summary." -f $interfaceAnalyzerScript)
        } elseif (-not $latestIngestionMetricsEntry) {
            Write-Warning 'InterfaceSync analyzer skipped: no ingestion metrics files were found.'
        } else {
            $interfaceSyncReportPath = Join-Path -Path $reportsDirectory -ChildPath ("InterfaceSyncTiming-{0}.json" -f $metricsReportSuffix)
            Write-Host ("Summarising InterfaceSync telemetry into '{0}'..." -f $interfaceSyncReportPath) -ForegroundColor Cyan
            & $interfaceAnalyzerScript -Path $latestIngestionMetricsEntry.FullName -OutputPath $interfaceSyncReportPath | Out-Null
        }
    } catch {
        Write-Warning ("InterfaceSync analyzer failed: {0}" -f $_.Exception.Message)
        $interfaceSyncReportPath = $null
    }

    try {
        if ($SkipPortDiversityGuard.IsPresent) {
            Write-Warning 'Port batch diversity guard skipped by request.'
        } else {
            $diversityScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Test-PortBatchSiteDiversity.ps1'
            if (-not (Test-Path -LiteralPath $diversityScript)) {
                Write-Verbose ("Port batch diversity script '{0}' not found; skipping site streak guard." -f $diversityScript)
            } elseif (-not $latestIngestionMetricsEntry) {
                Write-Warning 'Port batch diversity guard skipped: no ingestion metrics files were found.'
            } else {
                $maxConsecutive = 8
                 if ($PSBoundParameters.ContainsKey('PortBatchMaxConsecutiveOverride')) {
                     $maxConsecutive = $PortBatchMaxConsecutiveOverride
                 }
                 $portDiversityReportPath = Join-Path -Path $reportsDirectory -ChildPath ("PortBatchSiteDiversity-{0}.json" -f $metricsReportSuffix)
                 Write-Host ("Validating port batch site diversity into '{0}'..." -f $portDiversityReportPath) -ForegroundColor Cyan
                 try {
                    $diversityArgs = @{
                        MetricsPath          = $latestIngestionMetricsEntry.FullName
                        MaxAllowedConsecutive= $maxConsecutive
                        OutputPath           = $portDiversityReportPath
                    }
                    if ($Profile -eq 'Diag' -and -not $FailOnTelemetryMissing) {
                        $diversityArgs['AllowEmpty'] = $true
                    }
                    & $diversityScript @diversityArgs | Out-Null
                 } catch {
                     throw ("Port batch diversity guard failed: {0}" -f $_.Exception.Message)
                 }
             }
         }
    } catch {
        throw
    }
} else {
    Write-Host 'Quick mode: skipping telemetry summaries and diversity guard.' -ForegroundColor Yellow
}

if ($RunSharedCacheDiagnostics) {
    try {
        if (-not $latestIngestionMetricsEntry) {
            Write-Warning 'Shared cache diagnostics skipped: no ingestion metrics files were found.'
        } else {
            $latestLogPath = $latestIngestionMetricsEntry.FullName
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

try {
    $schedulerAnalyzer = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Analyze-ParserSchedulerLaunch.ps1'
    if (Test-Path -LiteralPath $schedulerAnalyzer) {
        if (-not $latestIngestionMetricsEntry) {
            Write-Warning 'Parser scheduler launch analyzer skipped: no ingestion metrics files were found.'
        } else {
            $schedulerReportPath = Join-Path -Path $reportsDirectory -ChildPath ("ParserSchedulerLaunch-{0}.json" -f $metricsReportSuffix)
            Write-Host ("Summarising parser scheduler telemetry into '{0}'..." -f $schedulerReportPath) -ForegroundColor Cyan
            & $schedulerAnalyzer -Path $latestIngestionMetricsEntry.FullName -MaxAllowedStreak 8 -OutputPath $schedulerReportPath | Out-Null
        }
    } else {
        Write-Verbose ("Parser scheduler analyzer not found at '{0}', skipping rotation summary." -f $schedulerAnalyzer)
    }
} catch {
    Write-Warning ("Parser scheduler analyzer failed: {0}" -f $_.Exception.Message)
}

if ($FailOnSchedulerFairness -and $schedulerReportPath -and (Test-Path -LiteralPath $schedulerReportPath)) {
    $fairnessScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Test-ParserSchedulerFairness.ps1'
    if (Test-Path -LiteralPath $fairnessScript) {
        try {
            & $fairnessScript -ReportPath $schedulerReportPath -ThrowOnViolation | Out-Null
        } catch {
            throw ("Parser scheduler fairness guard failed: {0}" -f $_.Exception.Message)
        }
    } else {
        Write-Warning ("Scheduler fairness test script '{0}' was not found; skipping guard." -f $fairnessScript)
    }
}

if (-not $QuickMode) {
try {
    if ($schedulerReportPath -and $portDiversityReportPath) {
        $comparisonScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Compare-SchedulerAndPortDiversity.ps1'
        if (Test-Path -LiteralPath $comparisonScript) {
            $schedulerVsPortReportPath = Join-Path -Path $reportsDirectory -ChildPath ("SchedulerVsPortDiversity-{0}.json" -f $metricsReportSuffix)
            $performanceReportsDirectory = Join-Path -Path $repositoryRoot -ChildPath 'docs\performance'
            if (-not (Test-Path -LiteralPath $performanceReportsDirectory)) {
                New-Item -ItemType Directory -Path $performanceReportsDirectory -Force | Out-Null
            }
            $schedulerVsPortMarkdownPath = Join-Path -Path $performanceReportsDirectory -ChildPath ("SchedulerVsPortDiversity-{0}.md" -f $metricsReportSuffix)
            Write-Host ("Comparing scheduler vs. port diversity into '{0}' and '{1}'..." -f $schedulerVsPortReportPath, $schedulerVsPortMarkdownPath) -ForegroundColor Cyan
            try {
                & $comparisonScript -SchedulerReportPath $schedulerReportPath -PortDiversityReportPath $portDiversityReportPath -OutputPath $schedulerVsPortReportPath -MarkdownPath $schedulerVsPortMarkdownPath | Out-Null
            } catch {
                Write-Warning ("Scheduler vs. port diversity comparison failed: {0}" -f $_.Exception.Message)
            }
        } else {
            Write-Verbose ("Scheduler vs. port diversity script '{0}' not found; skipping comparison." -f $comparisonScript)
        }
    }
} catch {
    Write-Warning ("Scheduler vs. port diversity comparison encountered an error: {0}" -f $_.Exception.Message)
}

try {
    if ($portBatchReportPath -and (Test-Path -LiteralPath $portBatchReportPath)) {
        $portHistoryScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Update-PortBatchHistory.ps1'
        if (Test-Path -LiteralPath $portHistoryScript) {
            powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command @"
& '$portHistoryScript' -ReportPaths '$portBatchReportPath'
"@ | Out-Null
        } else {
            Write-Verbose ("Port batch history updater not found at '{0}', skipping history append." -f $portHistoryScript)
        }
    }
} catch {
    Write-Warning ("Port batch history update failed: {0}" -f $_.Exception.Message)
}

try {
    if ($interfaceSyncReportPath -and (Test-Path -LiteralPath $interfaceSyncReportPath)) {
        $interfaceHistoryScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Update-InterfaceSyncHistory.ps1'
        if (Test-Path -LiteralPath $interfaceHistoryScript) {
            powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command @"
& '$interfaceHistoryScript' -ReportPaths '$interfaceSyncReportPath'
"@ | Out-Null
        } else {
            Write-Verbose ("InterfaceSync history updater not found at '{0}', skipping history append." -f $interfaceHistoryScript)
        }
    }
} catch {
    Write-Warning ("InterfaceSync history update failed: {0}" -f $_.Exception.Message)
}

try {
    if ($queueSummaryPath -and (Test-Path -LiteralPath $queueSummaryPath)) {
        $historyScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Update-QueueDelayHistory.ps1'
        if (Test-Path -LiteralPath $historyScript) {
            & $historyScript -QueueSummaryPaths $queueSummaryPath | Out-Null
        } else {
            Write-Verbose ("Queue delay history updater not found at '{0}', skipping history append." -f $historyScript)
        }
    }
} catch {
    Write-Warning ("Queue delay history update failed: {0}" -f $_.Exception.Message)
}

try {
    if ($schedulerReportPath -and (Test-Path -LiteralPath $schedulerReportPath)) {
        $schedulerHistoryScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Update-ParserSchedulerHistory.ps1'
        if (Test-Path -LiteralPath $schedulerHistoryScript) {
            & $schedulerHistoryScript -SchedulerReportPaths $schedulerReportPath | Out-Null
        } else {
            Write-Verbose ("Parser scheduler history updater not found at '{0}', skipping history append." -f $schedulerHistoryScript)
        }
    }
    } catch {
        Write-Warning ("Parser scheduler history update failed: {0}" -f $_.Exception.Message)
    }

}

if ($VerifyTelemetryCompleteness -and -not $QuickMode) {
    $telemetryResult = $null
    $telemetryMissingSignals = @()
    $telemetryPass = $true
    if (-not $latestIngestionMetricsEntry) {
        Write-Warning 'Telemetry completeness check skipped: no ingestion metrics files were found.'
        $telemetryPass = $false
    } else {
        $telemetryScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Test-IncrementalTelemetryCompleteness.ps1'
        if (-not (Test-Path -LiteralPath $telemetryScript)) {
            Write-Warning ("Telemetry completeness script '{0}' not found; skipping verification." -f $telemetryScript)
            $telemetryPass = $false
        } else {
            $scriptArgs = @{
                MetricsPath            = $latestIngestionMetricsEntry.FullName
                RequirePortBatchReady  = $true
                RequireInterfaceSync   = $true
                RequireSchedulerLaunch = $true
            }
            if ($FailOnTelemetryMissing) { $scriptArgs['ThrowOnMissing'] = $true }
            Write-Host ("Verifying incremental telemetry completeness via '{0}'..." -f $telemetryScript) -ForegroundColor Cyan
            try {
                $telemetryResult = & $telemetryScript @scriptArgs
                $telemetryMissingSignals = @($telemetryResult.MissingSignals)
                $telemetryPass = [bool]$telemetryResult.Pass
            } catch {
                $telemetryPass = $false
                if ($FailOnTelemetryMissing -and -not $SynthesizeSchedulerTelemetryOnMissing) {
                    throw
                } else {
                    Write-Warning ("Telemetry completeness check failed: {0}" -f $_.Exception.Message)
                }
            }
        }

        if (-not $telemetryPass -and $SynthesizeSchedulerTelemetryOnMissing -and ($telemetryMissingSignals -contains 'ParserSchedulerLaunch')) {
            $synthScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Synthesize-ParserSchedulerTelemetry.ps1'
            if (Test-Path -LiteralPath $synthScript) {
                Write-Warning 'ParserSchedulerLaunch events missing; synthesizing scheduler telemetry from ParseDuration order...'
                & $synthScript -MetricsPath $latestIngestionMetricsEntry.FullName -InPlace | Out-Null
                try {
                    Write-Host 'Re-running telemetry completeness check after synthesis...' -ForegroundColor Cyan
                    $telemetryResult = & $telemetryScript @scriptArgs
                    $telemetryMissingSignals = @($telemetryResult.MissingSignals)
                    $telemetryPass = [bool]$telemetryResult.Pass
                } catch {
                    $telemetryPass = $false
                    if ($FailOnTelemetryMissing) {
                        throw
                    } else {
                        Write-Warning ("Telemetry completeness check failed after synthesis: {0}" -f $_.Exception.Message)
                    }
                }
            } else {
                Write-Warning ("Scheduler synthesis script '{0}' not found; unable to patch telemetry." -f $synthScript)
            }
        }

        if (-not $telemetryPass -and $FailOnTelemetryMissing) {
            $missingSummary = if ($telemetryMissingSignals) { ($telemetryMissingSignals -join ', ') } else { 'Unknown' }
            throw ("Telemetry completeness check failed (missing: {0})." -f $missingSummary)
        } elseif (-not $telemetryPass) {
            $missingSummary = if ($telemetryMissingSignals) { ($telemetryMissingSignals -join ', ') } else { 'Unknown' }
            Write-Warning ("Telemetry completeness check failed (missing: {0})." -f $missingSummary)
        }
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
# Telemetry integrity lint (after pipeline run)
if ($RequireTelemetryIntegrity) {
    $integrityScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Test-TelemetryIntegrity.ps1'
    if (-not (Test-Path -LiteralPath $integrityScript)) {
        throw "Telemetry integrity script not found at $integrityScript"
    }
    if (-not (Test-Path -LiteralPath $reportsDirectory)) {
        New-Item -ItemType Directory -Path $reportsDirectory -Force | Out-Null
    }
    $latestIngestionMetricsEntry = Get-ChildItem -Path $ingestionMetricsDirectory -Filter '*.json' -File -ErrorAction Stop |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latestIngestionMetricsEntry) {
        throw "No ingestion metrics found under $ingestionMetricsDirectory for integrity check."
    }
    $integrityReportPath = Join-Path -Path $reportsDirectory -ChildPath ("TelemetryIntegrity-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Write-Host ("Running telemetry integrity check on {0}..." -f $latestIngestionMetricsEntry.FullName) -ForegroundColor Cyan
    & pwsh -File $integrityScript -Path $latestIngestionMetricsEntry.FullName -RequireQueueSummary -RequireInterfaceSync *> $integrityReportPath
    $integrityExit = $LASTEXITCODE
    if ($integrityExit -ne 0) {
        $integrityPreview = Get-Content -LiteralPath $integrityReportPath | Select-Object -First 20
        $previewText = ($integrityPreview -join [Environment]::NewLine)
        throw ("Telemetry integrity failed (exit {0}). See report at {1}.{2}{3}" -f $integrityExit, $integrityReportPath, [Environment]::NewLine, $previewText)
    }
    Write-Host ("Telemetry integrity passed. Report: {0}" -f $integrityReportPath) -ForegroundColor Green
}
} finally {
    if ($skipSiteCacheGuard) {
        Restore-SkipSiteCacheUpdateSetting -Guard $skipSiteCacheGuard
    }
}
