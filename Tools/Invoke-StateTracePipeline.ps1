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
    [switch]$ForcePortBatchReadySynthesis,
    [switch]$UseBalancedHostOrder,
    [switch]$RawPortDiversityAutoConcurrency,
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
    [switch]$RunQueueDelayHarness,
    [string[]]$QueueDelayHarnessHosts,
    [string[]]$QueueDelayHarnessSiteFilter = @(),
    [int]$QueueDelayHarnessMaxHosts = 12,
    [double]$QueueDelayHarnessWarningMs = 120,
    [double]$QueueDelayHarnessCriticalMs = 200,
    [switch]$VerifyTelemetryCompleteness,
    [switch]$FailOnTelemetryMissing,
    [switch]$SynthesizeSchedulerTelemetryOnMissing,
    [switch]$FailOnSchedulerFairness = $true,
    [switch]$RequireTelemetryIntegrity,
    [switch]$SkipTelemetryIntegrityPreflight,
    [switch]$DisablePreserveRunspace,
    [switch]$QuickMode
)

$sharedCacheSnapshotEnvOriginal = $null
$sharedCacheSnapshotEnvApplied = $false

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$forcePortBatchSynthesis = $ForcePortBatchReadySynthesis.IsPresent
if ($forcePortBatchSynthesis) {
    # LANDMARK: PortBatchReady synthesis - warn when enabled
    Write-Warning 'PortBatchReady synthesis is enabled; telemetry will be modified in-place and a .bak copy will be created.'
}

$rawPortDiversityAutoConcurrency = $RawPortDiversityAutoConcurrency.IsPresent
if ($rawPortDiversityAutoConcurrency -and $ForcePortBatchReadySynthesis.IsPresent) {
    throw 'RawPortDiversityAutoConcurrency cannot be combined with ForcePortBatchReadySynthesis. Run raw mode without synthesis.'
}

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
            Set-ProfileSwitch -Name 'RunQueueDelayHarness' -Value $true
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
            Set-ProfileSwitch -Name 'RunQueueDelayHarness' -Value $true
        }
    }
}

$skipSiteCacheGuardModule = Join-Path -Path $PSScriptRoot -ChildPath 'SkipSiteCacheUpdateGuard.psm1'
if (-not (Test-Path -LiteralPath $skipSiteCacheGuardModule)) {
    throw "Skip-site-cache guard module not found at $skipSiteCacheGuardModule."
}
Import-Module -Name $skipSiteCacheGuardModule -Force -ErrorAction Stop
$concurrencyOverrideGuardModule = Join-Path -Path $PSScriptRoot -ChildPath 'ConcurrencyOverrideGuard.psm1'
if (-not (Test-Path -LiteralPath $concurrencyOverrideGuardModule)) {
    throw "Concurrency override guard module not found at $concurrencyOverrideGuardModule."
}
Import-Module -Name $concurrencyOverrideGuardModule -Force -ErrorAction Stop

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$modulesPath = Join-Path -Path $repositoryRoot -ChildPath 'Modules'
$testsPath = Join-Path -Path $modulesPath -ChildPath 'Tests'
$parserWorkerModule = Join-Path -Path $modulesPath -ChildPath 'ParserWorker.psm1'
$ingestionMetricsDirectory = Join-Path -Path $repositoryRoot -ChildPath 'Logs\IngestionMetrics'
$reportsDirectory = Join-Path -Path $repositoryRoot -ChildPath 'Logs\Reports'
$settingsPath = Join-Path -Path $repositoryRoot -ChildPath 'Data\StateTraceSettings.json'
$rawPortDiversitySnapshot = $null
$rawPortDiversityReset = $null
$rawPortDiversityHistorySnapshot = $null
$skipSiteCacheGuard = $null

if ($rawPortDiversityAutoConcurrency) {
    # LANDMARK: Raw diversity auto concurrency - disable serialized overrides for this pass
    try {
        $rawPortDiversitySnapshot = Get-ConcurrencyOverrideSnapshot -SettingsPath $settingsPath
    } catch {
        Write-Warning ("Failed to snapshot concurrency overrides: {0}" -f $_.Exception.Message)
    }
    try {
        $rawPortDiversityReset = Reset-ConcurrencyOverrideSettings -SettingsPath $settingsPath -Label 'RawPortDiversityAutoConcurrency'
    } catch {
        Write-Warning ("Failed to reset concurrency overrides for raw diversity: {0}" -f $_.Exception.Message)
    }
    Write-Host 'Raw port diversity auto concurrency enabled; manual overrides suppressed for this run.' -ForegroundColor DarkCyan
    $manualOverrideParamsPresent = ($PSBoundParameters.ContainsKey('ThreadCeilingOverride') -or
        $PSBoundParameters.ContainsKey('MaxWorkersPerSiteOverride') -or
        $PSBoundParameters.ContainsKey('MaxActiveSitesOverride') -or
        $PSBoundParameters.ContainsKey('MaxConsecutiveSiteLaunchesOverride') -or
        $PSBoundParameters.ContainsKey('JobsPerThreadOverride') -or
        $PSBoundParameters.ContainsKey('MinRunspacesOverride'))
    if ($manualOverrideParamsPresent) {
        Write-Warning 'Raw diversity auto concurrency ignores manual override parameters for this run.'
    }

    # LANDMARK: Raw diversity auto concurrency - temporary ingestion history reset
    $historyPath = Join-Path -Path $repositoryRoot -ChildPath 'Data\IngestionHistory'
    $rawPortDiversityHistorySnapshot = [pscustomobject]@{
        Path       = $historyPath
        BackupPath = $null
        Existed    = $false
    }
    try {
        if (Test-Path -LiteralPath $historyPath) {
            $rawPortDiversityHistorySnapshot.Existed = $true
            $backupPath = Join-Path -Path $repositoryRoot -ChildPath ("Data\IngestionHistory.backup-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
            Move-Item -LiteralPath $historyPath -Destination $backupPath -Force
            $rawPortDiversityHistorySnapshot.BackupPath = $backupPath
        }
        New-Item -ItemType Directory -Path $historyPath -Force | Out-Null
        Write-Host ("Raw port diversity auto concurrency reset ingestion history at '{0}'." -f $historyPath) -ForegroundColor DarkCyan
    } catch {
        Write-Warning ("Failed to reset ingestion history for raw diversity: {0}" -f $_.Exception.Message)
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
    if ($SkipPortDiversityGuard) {
        $argumentList += '-SkipPortDiversityGuard'
    }
    if ($ForcePortBatchReadySynthesis) {
        # LANDMARK: PortBatchReady synthesis - propagate forced synthesis to warm-run regression
        $argumentList += '-ForcePortBatchReadySynthesis'
    }
    if ($UseBalancedHostOrder.IsPresent) {
        # LANDMARK: Host sweep balancing - propagate to warm-run regression
        $argumentList += '-UseBalancedHostOrder'
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
            if ([System.IO.Path]::IsPathRooted($WarmRunRegressionOutputPath)) {
                $resolvedOutput = [System.IO.Path]::GetFullPath($WarmRunRegressionOutputPath)
            } else {
                $basePath = (Get-Location).ProviderPath
                $resolvedOutput = [System.IO.Path]::GetFullPath((Join-Path -Path $basePath -ChildPath $WarmRunRegressionOutputPath))
            }
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
        return [System.IO.Path]::GetFullPath((Join-Path -Path $basePath -ChildPath $PathValue))
    }
}

function Get-SitePrefix {
    param([string]$Hostname)

    if ([string]::IsNullOrWhiteSpace($Hostname)) { return '(unknown)' }
    $parts = $Hostname.Split('-', 2, [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Count -gt 0) { return $parts[0] }
    return $Hostname
}

function Resolve-QueueDelayHarnessHosts {
    param(
        [string[]]$ExplicitHosts,
        [string[]]$SiteFilter,
        [int]$MaxHosts,
        [string]$RepositoryRoot,
        [string]$ModulesPath
    )

    $normalizedSites = @()
    if ($SiteFilter) {
        foreach ($site in $SiteFilter) {
            if ([string]::IsNullOrWhiteSpace($site)) { continue }
            foreach ($token in ($site -split ',')) {
                $trimmed = $token.Trim()
                if ($trimmed) { $normalizedSites += $trimmed }
            }
        }
    }
    $SiteFilter = $normalizedSites

    $hosts = @()
    if ($ExplicitHosts -and $ExplicitHosts.Count -gt 0) {
        $hosts = @($ExplicitHosts)
    } else {
        $catalogPath = Join-Path -Path $ModulesPath -ChildPath 'DeviceCatalogModule.psm1'
        if (Test-Path -LiteralPath $catalogPath) {
            if (-not (Get-Module -Name DeviceCatalogModule -ErrorAction SilentlyContinue)) {
                Import-Module $catalogPath -ErrorAction Stop
            }
            try {
                if ($SiteFilter -and $SiteFilter.Count -gt 0) {
                    $catalog = DeviceCatalogModule\Get-DeviceSummaries -SiteFilter $SiteFilter
                } else {
                    $catalog = DeviceCatalogModule\Get-DeviceSummaries
                }
            } catch { $catalog = $null }
            if ($catalog -and $catalog.Hostnames) {
                $hosts = @($catalog.Hostnames)
            }
        }

        if (-not $hosts -or $hosts.Count -eq 0) {
            $routingPaths = @(
                (Join-Path $RepositoryRoot 'Data\RoutingHosts_Balanced.txt'),
                (Join-Path $RepositoryRoot 'Data\RoutingHosts.txt')
            )
            foreach ($path in $routingPaths) {
                if (-not (Test-Path -LiteralPath $path)) { continue }
                $hosts = Get-Content -LiteralPath $path
                if ($hosts -and $hosts.Count -gt 0) { break }
            }
        }
    }

    $hosts = @($hosts | ForEach-Object { ('' + $_).Trim() } | Where-Object { $_ } | Select-Object -Unique)
    if ($SiteFilter -and $SiteFilter.Count -gt 0 -and $hosts.Count -gt 0) {
        $filterSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($site in $SiteFilter) {
            if (-not [string]::IsNullOrWhiteSpace($site)) { $filterSet.Add($site) | Out-Null }
        }
        if ($filterSet.Count -gt 0) {
            $hosts = @($hosts | Where-Object { $filterSet.Contains((Get-SitePrefix $_)) })
        }
    }
    if ($MaxHosts -gt 0 -and $hosts.Count -gt $MaxHosts) {
        $hosts = @($hosts | Select-Object -First $MaxHosts)
    }
    return @($hosts)
}

# LANDMARK: Telemetry event counts - detect missing queue/stream metrics
function Get-TelemetryEventCount {
    param(
        [string]$MetricsPath,
        [string]$EventName
    )

    if ([string]::IsNullOrWhiteSpace($MetricsPath) -or -not (Test-Path -LiteralPath $MetricsPath)) {
        return 0
    }
    if ([string]::IsNullOrWhiteSpace($EventName)) { return 0 }

    $count = 0
    try {
        foreach ($line in [System.IO.File]::ReadLines($MetricsPath)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line.IndexOf($EventName, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            try {
                $obj = $line | ConvertFrom-Json -ErrorAction Stop
                if ($obj -and $obj.EventName -eq $EventName) {
                    $count++
                }
            } catch { }
        }
    } catch { }

    return $count
}

# LANDMARK: Telemetry event timestamps - capture latest PortBatchReady time
function Get-TelemetryEventLatestTimestamp {
    param(
        [string]$MetricsPath,
        [string]$EventName,
        [datetime]$SinceTimestamp,
        [datetime]$UntilTimestamp
    )

    if ([string]::IsNullOrWhiteSpace($MetricsPath) -or -not (Test-Path -LiteralPath $MetricsPath)) {
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($EventName)) { return $null }

    $latest = $null
    $sinceUtc = $null
    if ($PSBoundParameters.ContainsKey('SinceTimestamp')) {
        $sinceUtc = $SinceTimestamp.ToUniversalTime()
    }
    $untilUtc = $null
    if ($PSBoundParameters.ContainsKey('UntilTimestamp')) {
        $untilUtc = $UntilTimestamp.ToUniversalTime()
    }
    try {
        foreach ($line in [System.IO.File]::ReadLines($MetricsPath)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line.IndexOf($EventName, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            try {
                $obj = $line | ConvertFrom-Json -ErrorAction Stop
                if ($obj -and $obj.EventName -eq $EventName -and $obj.Timestamp) {
                    $stamp = ([datetime]$obj.Timestamp).ToUniversalTime()
                    if ($sinceUtc -and $stamp -lt $sinceUtc) { continue }
                    if ($untilUtc -and $stamp -gt $untilUtc) { continue }
                    if (-not $latest -or $stamp -gt $latest) {
                        $latest = $stamp
                    }
                }
            } catch { }
        }
    } catch { }

    return $latest
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
                try { Get-InterfaceSiteCache -Site $siteKey | Out-Null } catch {
                    Write-Warning ("Failed to warm interface site cache for '{0}': {1}" -f $siteKey, $_.Exception.Message)
                }
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

function Get-ConcurrencyOverrideParameters {
    [CmdletBinding()]
    param([hashtable]$BoundParameters)

    $overrides = [ordered]@{}
    if (-not $BoundParameters) { return $overrides }

    if ($BoundParameters.ContainsKey('ThreadCeilingOverride')) {
        $overrides['ThreadCeilingOverride'] = [int]$BoundParameters.ThreadCeilingOverride
    }
    if ($BoundParameters.ContainsKey('MaxWorkersPerSiteOverride')) {
        $overrides['MaxWorkersPerSiteOverride'] = [int]$BoundParameters.MaxWorkersPerSiteOverride
    }
    if ($BoundParameters.ContainsKey('MaxActiveSitesOverride')) {
        $overrides['MaxActiveSitesOverride'] = [int]$BoundParameters.MaxActiveSitesOverride
    }
    if ($BoundParameters.ContainsKey('MaxConsecutiveSiteLaunchesOverride')) {
        $overrides['MaxConsecutiveSiteLaunchesOverride'] = [int]$BoundParameters.MaxConsecutiveSiteLaunchesOverride
    }
    if ($BoundParameters.ContainsKey('JobsPerThreadOverride')) {
        $overrides['JobsPerThreadOverride'] = [int]$BoundParameters.JobsPerThreadOverride
    }
    if ($BoundParameters.ContainsKey('MinRunspacesOverride')) {
        $overrides['MinRunspacesOverride'] = [int]$BoundParameters.MinRunspacesOverride
    }

    return $overrides
}

function Get-ConcurrencyProfileSummaryFromMetrics {
    [CmdletBinding()]
    param([string]$MetricsPath)

    if ([string]::IsNullOrWhiteSpace($MetricsPath) -or -not (Test-Path -LiteralPath $MetricsPath)) {
        return $null
    }

    $lastEvent = $null
    try {
        foreach ($line in [System.IO.File]::ReadLines($MetricsPath)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line.IndexOf('ConcurrencyProfileResolved', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            try {
                $event = $line | ConvertFrom-Json -ErrorAction Stop
                if ($event -and $event.EventName -eq 'ConcurrencyProfileResolved') {
                    $lastEvent = $event
                }
            } catch { }
        }
    } catch { }

    if (-not $lastEvent) { return $null }

    $summaryFields = @(
        'ManualOverrides',
        'DecisionSource',
        'ThreadCeiling',
        'MaxWorkersPerSite',
        'MaxActiveSites',
        'JobsPerThread',
        'MinRunspaces',
        'ResolvedThreadCeiling',
        'ResolvedMaxWorkersPerSite',
        'ResolvedMaxActiveSites',
        'ResolvedJobsPerThread',
        'ResolvedMinRunspaces',
        'ResolvedMaxConsecutiveSiteLaunches',
        'OverrideThreadCeiling',
        'OverrideMaxWorkersPerSite',
        'OverrideMaxActiveSites',
        'OverrideJobsPerThread',
        'OverrideMinRunspaces'
    )
    $summary = [ordered]@{}
    foreach ($field in $summaryFields) {
        if ($lastEvent.PSObject.Properties.Name -contains $field) {
            $summary[$field] = $lastEvent.$field
        }
    }
    if ($summary.Count -eq 0) { return $null }
    return [pscustomobject]$summary
}

function Write-ConcurrencyOverrideTelemetry {
    [CmdletBinding()]
    param(
        [hashtable]$ParameterOverrides,
        [psobject]$ResetResult,
        [string]$Label
    )

    $hasParameterOverrides = $ParameterOverrides -and $ParameterOverrides.Count -gt 0
    $hasSettingsOverrides = $ResetResult -and $ResetResult.Overrides -and $ResetResult.Overrides.Count -gt 0
    $resetApplied = $ResetResult -and $ResetResult.Changed

    if (-not ($hasParameterOverrides -or $hasSettingsOverrides -or $resetApplied)) {
        return
    }

    $payload = [ordered]@{}
    if ($hasParameterOverrides) {
        foreach ($entry in $ParameterOverrides.GetEnumerator()) {
            $payload[$entry.Key] = $entry.Value
        }
    }

    if ($hasSettingsOverrides) {
        foreach ($entry in $ResetResult.Overrides.GetEnumerator()) {
            $payload['Settings{0}' -f $entry.Key] = $entry.Value
        }
        $payload['SettingsResetApplied'] = [bool]$resetApplied
    } elseif ($resetApplied) {
        $payload['SettingsResetApplied'] = [bool]$resetApplied
    }

    if (-not [string]::IsNullOrWhiteSpace($Label)) {
        $payload['Source'] = $Label
    }

    $telemetryCmd = Get-TelemetryModuleCommand -Name 'Write-StTelemetryEvent'
    if (-not $telemetryCmd) { return }

    try {
        & $telemetryCmd -Name 'ConcurrencyOverrideSummary' -Payload $payload
    } catch { }

    # LANDMARK: Telemetry buffer rename - resolve approved-verb command
    $flushCmd = Get-TelemetryModuleCommand -Name 'Save-StTelemetryBuffer'
    if ($flushCmd) {
        try { & $flushCmd | Out-Null } catch { }
    }
}

$parameterOverrides = if ($rawPortDiversityAutoConcurrency) {
    [ordered]@{}
} else {
    Get-ConcurrencyOverrideParameters -BoundParameters $PSBoundParameters
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

    # LANDMARK: Shared cache summary - ensure collection semantics for single entries
    $summaryEntries = @(Get-SharedCacheSnapshotSummary -SnapshotPath $SnapshotPath)
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
    try { $currentApartment = [System.Threading.Thread]::CurrentThread.GetApartmentState() } catch {
        Write-Warning ("Failed to read current apartment state: {0}" -f $_.Exception.Message)
    }
    if ($currentApartment -ne [System.Threading.ApartmentState]::STA) {
        try { [void][System.Threading.Thread]::CurrentThread.TrySetApartmentState([System.Threading.ApartmentState]::STA) } catch {
            Write-Warning ("Failed to set apartment state to STA: {0}" -f $_.Exception.Message)
        }
        try { $currentApartment = [System.Threading.Thread]::CurrentThread.GetApartmentState() } catch {
            Write-Warning ("Failed to re-read apartment state after update: {0}" -f $_.Exception.Message)
        }
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
$ingestionStartUtc = (Get-Date).ToUniversalTime().AddSeconds(-2)
$ingestionEndUtc = $null
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
if (-not $rawPortDiversityAutoConcurrency -and $PSBoundParameters.ContainsKey('ThreadCeilingOverride')) {
    $invokeParams['ThreadCeilingOverride'] = $ThreadCeilingOverride
}
if (-not $rawPortDiversityAutoConcurrency -and $PSBoundParameters.ContainsKey('MaxWorkersPerSiteOverride')) {
    $invokeParams['MaxWorkersPerSiteOverride'] = $MaxWorkersPerSiteOverride
}
if (-not $rawPortDiversityAutoConcurrency -and $PSBoundParameters.ContainsKey('MaxActiveSitesOverride')) {
    $invokeParams['MaxActiveSitesOverride'] = $MaxActiveSitesOverride
}
if (-not $rawPortDiversityAutoConcurrency -and $PSBoundParameters.ContainsKey('MaxConsecutiveSiteLaunchesOverride')) {
    $invokeParams['MaxConsecutiveSiteLaunchesOverride'] = $MaxConsecutiveSiteLaunchesOverride
}
if (-not $rawPortDiversityAutoConcurrency -and $PSBoundParameters.ContainsKey('JobsPerThreadOverride')) {
    $invokeParams['JobsPerThreadOverride'] = $JobsPerThreadOverride
}
if (-not $rawPortDiversityAutoConcurrency -and $PSBoundParameters.ContainsKey('MinRunspacesOverride')) {
    $invokeParams['MinRunspacesOverride'] = $MinRunspacesOverride
}
if ($UseBalancedHostOrder.IsPresent) {
    # LANDMARK: Host sweep balancing - deterministic interleaving to reduce site streaks
    $invokeParams['UseBalancedHostOrder'] = $true
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
# LANDMARK: Port diversity window - capture latest PortBatchReady timestamp from initial run
$ingestionEndUtc = $null
$ingestionEndFallbackUsed = $false
$ingestionMetricsPath = $null
try {
    $flushCmd = Get-TelemetryModuleCommand -Name 'Save-StTelemetryBuffer'
    if ($flushCmd) {
        & $flushCmd | Out-Null
    }
} catch { }
try {
    $telemetryPathCmd = Get-TelemetryModuleCommand -Name 'Get-TelemetryLogPath'
    if ($telemetryPathCmd) {
        $ingestionMetricsPath = & $telemetryPathCmd
    }
} catch { }
if (-not [string]::IsNullOrWhiteSpace($ingestionMetricsPath) -and (Test-Path -LiteralPath $ingestionMetricsPath)) {
    for ($attempt = 0; $attempt -lt 5 -and -not $ingestionEndUtc; $attempt++) {
        try {
            $flushCmd = Get-TelemetryModuleCommand -Name 'Save-StTelemetryBuffer'
            if ($flushCmd) {
                & $flushCmd | Out-Null
            }
        } catch { }
        $ingestionEndUtc = Get-TelemetryEventLatestTimestamp -MetricsPath $ingestionMetricsPath -EventName 'PortBatchReady' -SinceTimestamp $ingestionStartUtc
        if (-not $ingestionEndUtc) {
            Start-Sleep -Milliseconds 200
        }
    }
}
if (-not $ingestionEndUtc -and (Test-Path -LiteralPath $ingestionMetricsDirectory)) {
    $fallbackMetrics = Get-ChildItem -LiteralPath $ingestionMetricsDirectory -Filter '*.json' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($fallbackMetrics) {
        $ingestionEndUtc = Get-TelemetryEventLatestTimestamp -MetricsPath $fallbackMetrics.FullName -EventName 'PortBatchReady' -SinceTimestamp $ingestionStartUtc
    }
}
if ($ingestionEndUtc -and $ingestionEndUtc -lt $ingestionStartUtc) {
    Write-Warning 'PortBatchReady timestamps were not detected after the ingestion start; widening window to current time.'
    $ingestionEndUtc = $null
}
if (-not $ingestionEndUtc) {
    Write-Warning 'Unable to locate latest PortBatchReady timestamp; falling back to current time.'
    $ingestionEndUtc = (Get-Date).ToUniversalTime()
    $ingestionEndFallbackUsed = $true
}

if ($RunWarmRunRegression -and -not $rawPortDiversityAutoConcurrency) {
    Invoke-WarmRunRegressionInternal
} elseif ($RunWarmRunRegression -and $rawPortDiversityAutoConcurrency) {
    # LANDMARK: Raw diversity auto concurrency - avoid warm-run regression overrides
    Write-Warning 'Raw port diversity auto concurrency enabled; warm-run regression skipped for this run.'
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

# ST-J-002: Preflight telemetry integrity check - fail fast on polluted JSON
if ($latestIngestionMetricsEntry -and -not $SkipTelemetryIntegrityPreflight) {
    $integrityScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Test-TelemetryIntegrity.ps1'
    if (Test-Path -LiteralPath $integrityScript) {
        Write-Host ("Preflight: checking telemetry integrity for {0}..." -f $latestIngestionMetricsEntry.FullName) -ForegroundColor Cyan
        try {
            & $integrityScript -Path $latestIngestionMetricsEntry.FullName -PassThru | Out-Null
        } catch {
            Write-Host '' -ForegroundColor Red
            Write-Host '=== TELEMETRY INTEGRITY PREFLIGHT FAILED ===' -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
            Write-Host ''
            throw ("Preflight check failed: telemetry file contains invalid JSON. Use -SkipTelemetryIntegrityPreflight to bypass.")
        }
        Write-Host ("Preflight: telemetry integrity OK.") -ForegroundColor Green
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
    if ($RunQueueDelayHarness) {
        # LANDMARK: Queue delay sample floor - expand host sweep for stable sample size
        try {
            $queueHosts = Resolve-QueueDelayHarnessHosts -ExplicitHosts $QueueDelayHarnessHosts -SiteFilter $QueueDelayHarnessSiteFilter -MaxHosts $QueueDelayHarnessMaxHosts -RepositoryRoot $repositoryRoot -ModulesPath $modulesPath
            if ($queueHosts -and $queueHosts.Count -gt 0) {
                $dispatchHarness = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Invoke-RoutingQueueSweep.ps1'
                if (Test-Path -LiteralPath $dispatchHarness) {
                    $dispatchDir = Join-Path -Path $repositoryRoot -ChildPath 'Logs\DispatchHarness'
                    if (-not (Test-Path -LiteralPath $dispatchDir)) {
                        New-Item -ItemType Directory -Path $dispatchDir -Force | Out-Null
                    }
                    $queueHarnessSummary = Join-Path -Path $dispatchDir -ChildPath ("RoutingQueueSweep-pipeline-{0}.json" -f $metricsReportSuffix)
                    Write-Host ("Running dispatcher harness sweep for queue delay telemetry ({0} host(s))..." -f $queueHosts.Count) -ForegroundColor Cyan
                    & $dispatchHarness -Hosts $queueHosts -QueueDelayWarningMs $QueueDelayHarnessWarningMs -QueueDelayCriticalMs $QueueDelayHarnessCriticalMs -OutputDirectory $dispatchDir -SummaryPath $queueHarnessSummary | Out-Null
                } else {
                    Write-Warning ("Queue delay harness script '{0}' not found; skipping dispatcher sweep." -f $dispatchHarness)
                }
            } else {
                Write-Warning 'Queue delay harness skipped: no hosts resolved.'
            }
        } catch {
            Write-Warning ("Queue delay harness sweep failed: {0}" -f $_.Exception.Message)
        }
    }

    $queueMetricsCount = 0
    $streamMetricsCount = 0
    if ($latestIngestionMetricsEntry) {
        $queueMetricsCount = Get-TelemetryEventCount -MetricsPath $latestIngestionMetricsEntry.FullName -EventName 'InterfacePortQueueMetrics'
        $streamMetricsCount = Get-TelemetryEventCount -MetricsPath $latestIngestionMetricsEntry.FullName -EventName 'InterfacePortStreamMetrics'
    }

    $queueDelayMinimumEventCount = 10
    if ($latestIngestionMetricsEntry -and (
            ($RunQueueDelayHarness -and $queueMetricsCount -lt $queueDelayMinimumEventCount) -or
            ($ForcePortBatchReadySynthesis.IsPresent -and $queueMetricsCount -eq 0 -and $streamMetricsCount -eq 0)
        )) {
        # LANDMARK: Queue delay harness fallback - seed stream/queue metrics via headless checklist
        $checklistScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Invoke-InterfacesViewChecklist.ps1'
        if (-not (Test-Path -LiteralPath $checklistScript)) {
            Write-Warning ("Interfaces view checklist script '{0}' not found; queue delay telemetry may be incomplete." -f $checklistScript)
        } else {
            $checklistOutput = Join-Path -Path $reportsDirectory -ChildPath ("InterfacesViewChecklist-{0}.json" -f $metricsReportSuffix)
            $checklistSummary = Join-Path -Path $reportsDirectory -ChildPath ("InterfacesViewQuickstart-{0}.json" -f $metricsReportSuffix)
            $checklistArgs = @(
                '-NoLogo',
                '-NoProfile',
                '-STA',
                '-File',
                $checklistScript,
                '-MaxHosts',
                $QueueDelayHarnessMaxHosts,
                '-SynthesizePortBatchReady:$false',
                '-OutputPath',
                $checklistOutput,
                '-SummaryPath',
                $checklistSummary
            )
            if ($QueueDelayHarnessSiteFilter -and $QueueDelayHarnessSiteFilter.Count -gt 0) {
                $siteToken = ($QueueDelayHarnessSiteFilter -join ',')
                if (-not [string]::IsNullOrWhiteSpace($siteToken)) {
                    $checklistArgs += @('-SiteFilter', $siteToken)
                }
            }

            Write-Host ("Running headless Interfaces checklist to seed telemetry (QueueMetrics={0}, StreamMetrics={1})..." -f $queueMetricsCount, $streamMetricsCount) -ForegroundColor Cyan
            try {
                $pwshCommand = Get-Command -Name 'pwsh' -ErrorAction Stop
                & $pwshCommand.Source @checklistArgs
                $checklistExit = $LASTEXITCODE
                if ($checklistExit -ne 0) {
                    Write-Warning ("Interfaces checklist exited with code {0}; queue delay telemetry may remain incomplete." -f $checklistExit)
                }
            } catch {
                Write-Warning ("Interfaces checklist launch failed: {0}" -f $_.Exception.Message)
            }

            if ($latestIngestionMetricsEntry) {
                $queueMetricsCount = Get-TelemetryEventCount -MetricsPath $latestIngestionMetricsEntry.FullName -EventName 'InterfacePortQueueMetrics'
                $streamMetricsCount = Get-TelemetryEventCount -MetricsPath $latestIngestionMetricsEntry.FullName -EventName 'InterfacePortStreamMetrics'
                Write-Host ("Queue/stream metrics after checklist: Queue={0}, Stream={1}" -f $queueMetricsCount, $streamMetricsCount) -ForegroundColor DarkCyan
            }
        }
    }
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
        if ($ForcePortBatchReadySynthesis.IsPresent) {
            # LANDMARK: PortBatchReady synthesis - allow synthesized batches for diversity guard
            if (-not $latestIngestionMetricsEntry) {
                Write-Warning 'PortBatchReady synthesis skipped: no ingestion metrics files were found.'
            } else {
                $portBatchSynthScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Add-PortBatchReadyTelemetry.ps1'
                if (-not (Test-Path -LiteralPath $portBatchSynthScript)) {
                    Write-Warning ("PortBatchReady synthesis script '{0}' not found; skipping synthesis." -f $portBatchSynthScript)
                } else {
                    Write-Host ("Forcing PortBatchReady synthesis into '{0}'..." -f $latestIngestionMetricsEntry.FullName) -ForegroundColor Cyan
                    & $portBatchSynthScript -MetricsPath $latestIngestionMetricsEntry.FullName -InPlace -Force | Out-Null
                }
            }
        }
    } catch {
        throw ("PortBatchReady synthesis failed: {0}" -f $_.Exception.Message)
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
                 # LANDMARK: Raw diversity artifacts - stable naming for auto concurrency raw pass
                 $portDiversityReportSuffix = $metricsReportSuffix
                 if ($rawPortDiversityAutoConcurrency) {
                     $portDiversityReportSuffix = "{0}-raw-auto-{1}" -f $metricsReportSuffix, (Get-Date -Format 'yyyyMMdd-HHmmss')
                 }
                 $portDiversityReportPath = Join-Path -Path $reportsDirectory -ChildPath ("PortBatchSiteDiversity-{0}.json" -f $portDiversityReportSuffix)
                 # LANDMARK: Raw diversity report metadata - record effective concurrency + event mode
                 $concurrencyProfileSummary = Get-ConcurrencyProfileSummaryFromMetrics -MetricsPath $latestIngestionMetricsEntry.FullName
                 $manualOverridesApplied = $null
                 if ($concurrencyProfileSummary -and ($concurrencyProfileSummary.PSObject.Properties.Name -contains 'ManualOverrides')) {
                     $manualOverridesApplied = [bool]$concurrencyProfileSummary.ManualOverrides
                 }
                 # LANDMARK: Gate artifact traceability - log exact input paths used for evaluation
                 Write-Host ("Port batch diversity metrics file: {0}" -f $latestIngestionMetricsEntry.FullName) -ForegroundColor DarkCyan
                 Write-Host ("Validating port batch site diversity into '{0}'..." -f $portDiversityReportPath) -ForegroundColor Cyan
                 $portDiversityEndUtc = $ingestionEndUtc
                 if ($latestIngestionMetricsEntry) {
                    # LANDMARK: Port diversity window - refresh end timestamp once telemetry is flushed
                    $resolvedEndUtc = Get-TelemetryEventLatestTimestamp -MetricsPath $latestIngestionMetricsEntry.FullName -EventName 'PortBatchReady' -SinceTimestamp $ingestionStartUtc
                    if ($resolvedEndUtc -and (-not $portDiversityEndUtc -or $resolvedEndUtc -gt $portDiversityEndUtc)) {
                        $portDiversityEndUtc = $resolvedEndUtc
                        if ($ingestionEndFallbackUsed) {
                            Write-Host ("Port batch diversity end resolved from telemetry: {0}" -f $portDiversityEndUtc.ToString('o')) -ForegroundColor DarkCyan
                        }
                    }
                 }
                 # LANDMARK: Gate artifact traceability - log diversity window selection
                 $diversityWindowStart = if ($ingestionStartUtc) { $ingestionStartUtc.ToString('o') } else { 'n/a' }
                 $diversityWindowEnd = if ($portDiversityEndUtc) { $portDiversityEndUtc.ToString('o') } else { 'n/a' }
                 Write-Host ("Port batch diversity window: start={0} end={1}" -f $diversityWindowStart, $diversityWindowEnd) -ForegroundColor DarkCyan
                 try {
                    $diversityArgs = @{
                        MetricsPath          = $latestIngestionMetricsEntry.FullName
                        MaxAllowedConsecutive= $maxConsecutive
                        OutputPath           = $portDiversityReportPath
                        AllowNoParse         = $true
                    }
                    if ($manualOverridesApplied -ne $null) {
                        $diversityArgs['ManualOverridesApplied'] = $manualOverridesApplied
                    }
                    if ($concurrencyProfileSummary) {
                        $diversityArgs['ConcurrencyProfile'] = $concurrencyProfileSummary
                    }
                    if ($rawPortDiversityAutoConcurrency) {
                        $diversityArgs['RawAutoConcurrencyMode'] = $true
                    }
                    if ($ingestionStartUtc) {
                        # LANDMARK: Port diversity window - limit evaluation to current run
                        $diversityArgs['SinceTimestamp'] = $ingestionStartUtc
                    }
                    if ($portDiversityEndUtc) {
                        # LANDMARK: Port diversity window - cap evaluation before warm-run regression
                        $diversityArgs['UntilTimestamp'] = $portDiversityEndUtc
                    }
                    if (-not $ForcePortBatchReadySynthesis.IsPresent) {
                        # LANDMARK: Port diversity raw evaluation - ignore synthesized events when not forced
                        $diversityArgs['IgnoreSynthesizedEvents'] = $true
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
                AllowNoParse           = $true
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
    $overrideReset = $null
    try {
        $overrideReset = Reset-ConcurrencyOverrideSettings -SettingsPath $settingsPath -Label 'StateTracePipeline'
    } catch {
        Write-Warning ("Failed to reset concurrency overrides: {0}" -f $_.Exception.Message)
    }
    try {
        Write-ConcurrencyOverrideTelemetry -ParameterOverrides $parameterOverrides -ResetResult $overrideReset -Label 'StateTracePipeline'
    } catch { }
    if ($rawPortDiversityAutoConcurrency -and $rawPortDiversitySnapshot) {
        # LANDMARK: Raw diversity auto concurrency - restore original settings after run
        try {
            $restored = Set-ConcurrencyOverrideSnapshot -Snapshot $rawPortDiversitySnapshot
            if ($restored -and $VerboseParsing) {
                Write-Host 'Restored concurrency override settings after raw diversity pass.' -ForegroundColor DarkGray
            }
        } catch {
            Write-Warning ("Failed to restore concurrency override snapshot: {0}" -f $_.Exception.Message)
        }
    }
    if ($rawPortDiversityAutoConcurrency -and $rawPortDiversityHistorySnapshot) {
        # LANDMARK: Raw diversity auto concurrency - restore ingestion history after run
        try {
            if ($rawPortDiversityHistorySnapshot.Path -and (Test-Path -LiteralPath $rawPortDiversityHistorySnapshot.Path)) {
                Remove-Item -LiteralPath $rawPortDiversityHistorySnapshot.Path -Recurse -Force
            }
            if ($rawPortDiversityHistorySnapshot.Existed -and $rawPortDiversityHistorySnapshot.BackupPath -and (Test-Path -LiteralPath $rawPortDiversityHistorySnapshot.BackupPath)) {
                Move-Item -LiteralPath $rawPortDiversityHistorySnapshot.BackupPath -Destination $rawPortDiversityHistorySnapshot.Path -Force
            }
        } catch {
            Write-Warning ("Failed to restore ingestion history snapshot: {0}" -f $_.Exception.Message)
        }
    }
    if ($skipSiteCacheGuard) {
        Restore-SkipSiteCacheUpdateSetting -Guard $skipSiteCacheGuard
    }
}
