Set-StrictMode -Version Latest

if (-not (Get-Variable -Scope Script -Name WorkerModulesInitialized -ErrorAction SilentlyContinue)) {
    $script:WorkerModulesInitialized = $false
}

if (-not (Get-Variable -Scope Script -Name ParserModuleNames -ErrorAction SilentlyContinue)) {
    $script:ParserModuleNames = @(
        'DeviceParsingCommon.psm1',
        'AristaModule.psm1',
        'CiscoModule.psm1',
        'BrocadeModule.psm1',
        'DeviceRepositoryModule.psm1',
        'ParserPersistenceModule.psm1',
        'DeviceLogParserModule.psm1',
        'DatabaseModule.psm1'
    )
}

if (-not (Get-Variable -Scope Script -Name PreservedRunspacePool -ErrorAction SilentlyContinue)) {
    $script:PreservedRunspacePool = $null
    $script:PreservedRunspaceConfig = $null
}

function Publish-RunspaceCacheTelemetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Stage,
        [string]$Site,
        [psobject]$Summary
    )

    $runspaceId = ''
    try {
        $currentRunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
        if ($currentRunspace) { $runspaceId = $currentRunspace.InstanceId.ToString() }
    } catch {
        $runspaceId = ''
    }

    $siteKey = if ($Site) { ('' + $Site).Trim() } else { '' }
    $cacheExists = $false
    $cacheStatus = ''
    $hostCount = 0
    $totalRows = 0
    $hostMapType = ''
    $entryType = ''
    $cachedAt = ''

    if ($Summary) {
        try {
            if ($Summary.PSObject.Properties.Name -contains 'CacheExists') {
                $cacheExists = [bool]$Summary.CacheExists
            }
        } catch { $cacheExists = $false }
        try {
            if ($Summary.PSObject.Properties.Name -contains 'CacheStatus') {
                $cacheStatus = '' + $Summary.CacheStatus
            }
        } catch { $cacheStatus = '' }
        try {
            if ($Summary.PSObject.Properties.Name -contains 'HostCount') {
                $hostCount = [int]$Summary.HostCount
            }
        } catch { $hostCount = 0 }
        try {
            if ($Summary.PSObject.Properties.Name -contains 'TotalRows') {
                $totalRows = [int]$Summary.TotalRows
            }
        } catch { $totalRows = 0 }
        try {
            if ($Summary.PSObject.Properties.Name -contains 'HostMapType') {
                $hostMapType = '' + $Summary.HostMapType
            }
        } catch { $hostMapType = '' }
        try {
            if ($Summary.PSObject.Properties.Name -contains 'EntryType') {
                $entryType = '' + $Summary.EntryType
            }
        } catch { $entryType = '' }
        try {
            if ($Summary.PSObject.Properties.Name -contains 'CachedAt' -and $null -ne $Summary.CachedAt) {
                $cachedAt = ([datetime]$Summary.CachedAt).ToString('o')
            }
        } catch { $cachedAt = '' }
    }

    $payload = @{
        Stage       = $Stage
        RunspaceId  = $runspaceId
        Site        = $siteKey
        CacheExists = $cacheExists
        CacheStatus = $cacheStatus
        HostCount   = $hostCount
        TotalRows   = $totalRows
        HostMapType = $hostMapType
        EntryType   = $entryType
        CachedAt    = $cachedAt
    }

    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'InterfaceSiteCacheRunspaceState' -Payload $payload
    } catch { }
}

function Publish-RunspacePoolEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Operation,
        [string]$Reason,
        [System.Management.Automation.Runspaces.RunspacePool]$Pool,
        [hashtable]$PoolConfig
    )

    $poolId = ''
    $poolState = ''
    if ($Pool) {
        try { $poolId = $Pool.InstanceId.ToString() } catch { $poolId = '' }
        try { $poolState = '' + $Pool.RunspacePoolStateInfo.State } catch { $poolState = '' }
    }

    $modulesPath = ''
    $maxThreads = 0
    $minThreads = 0
    $jobsPerThread = 0
    $maxWorkersPerSite = 0
    $maxActiveSites = 0
    if ($PoolConfig) {
        if ($PoolConfig.ContainsKey('ModulesPath')) {
            try { $modulesPath = '' + $PoolConfig['ModulesPath'] } catch { $modulesPath = '' }
        }
        if ($PoolConfig.ContainsKey('MaxThreads')) {
            try { $maxThreads = [int]$PoolConfig['MaxThreads'] } catch { $maxThreads = 0 }
        }
        if ($PoolConfig.ContainsKey('MinThreads')) {
            try { $minThreads = [int]$PoolConfig['MinThreads'] } catch { $minThreads = 0 }
        }
        if ($PoolConfig.ContainsKey('JobsPerThread')) {
            try { $jobsPerThread = [int]$PoolConfig['JobsPerThread'] } catch { $jobsPerThread = 0 }
        }
        if ($PoolConfig.ContainsKey('MaxWorkersPerSite')) {
            try { $maxWorkersPerSite = [int]$PoolConfig['MaxWorkersPerSite'] } catch { $maxWorkersPerSite = 0 }
        }
        if ($PoolConfig.ContainsKey('MaxActiveSites')) {
            try { $maxActiveSites = [int]$PoolConfig['MaxActiveSites'] } catch { $maxActiveSites = 0 }
        }
    }

    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'ParserRunspacePoolState' -Payload @{
            Operation         = $Operation
            Reason            = if ($Reason) { $Reason } else { '' }
            PoolId            = $poolId
            PoolState         = $poolState
            ModulesPath       = $modulesPath
            MaxThreads        = $maxThreads
            MinThreads        = $minThreads
            JobsPerThread     = $jobsPerThread
            MaxWorkersPerSite = $maxWorkersPerSite
            MaxActiveSites    = $maxActiveSites
        }
    } catch { }
}

function Get-ParserModulePaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ModulesPath
    )

    $paths = New-Object 'System.Collections.Generic.List[string]'
    foreach ($name in $script:ParserModuleNames) {
        $combined = Join-Path $ModulesPath $name
        try {
            $full = [System.IO.Path]::GetFullPath($combined)
        } catch {
            $full = $combined
        }
        if (Test-Path -LiteralPath $full) { [void]$paths.Add($full) }
    }
    return $paths.ToArray()
}

function Get-RunspaceModuleImportList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ModulesPath
    )

    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($path in (Get-ParserModulePaths -ModulesPath $ModulesPath)) { [void]$set.Add($path) }

    $selfPath = Join-Path $ModulesPath 'ParserRunspaceModule.psm1'
    try { $selfPath = [System.IO.Path]::GetFullPath($selfPath) } catch { }
    if (Test-Path -LiteralPath $selfPath) { [void]$set.Add($selfPath) }
    return [string[]]$set
}

function Initialize-WorkerModules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ModulesPath
    )

    if ($script:WorkerModulesInitialized) { return }

    foreach ($path in (Get-ParserModulePaths -ModulesPath $ModulesPath)) {
        Import-Module -Name $path -ErrorAction Stop -Global | Out-Null
    }
    $script:WorkerModulesInitialized = $true
}

function Initialize-SchedulerMetricsContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ModulesPath,
        [int]$DeviceCount = 0,
        [int]$MaxThreads = 0,
        [int]$MaxWorkersPerSite = 0,
        [int]$MaxActiveSites = 0,
        [int]$MinThreads = 1,
        [int]$JobsPerThread = 2,
        [int]$CpuCount = 0,
        [switch]$AdaptiveThreads,
        [int]$MinIntervalSeconds = 5
    )

    try {
        $resolvedModules = [System.IO.Path]::GetFullPath($ModulesPath)
    } catch {
        $resolvedModules = $ModulesPath
    }

    $projectRoot = Split-Path -Path $resolvedModules -Parent
    if ([string]::IsNullOrWhiteSpace($projectRoot)) { return $null }

    $logsRoot = Join-Path $projectRoot 'Logs'
    $metricsRoot = Join-Path $logsRoot 'IngestionMetrics'
    try {
        if (-not (Test-Path -LiteralPath $logsRoot)) {
            New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null
        }
        if (-not (Test-Path -LiteralPath $metricsRoot)) {
            New-Item -ItemType Directory -Path $metricsRoot -Force | Out-Null
        }
    } catch {
        return $null
    }

    $fileName = '{0}.json' -f (Get-Date -Format 'yyyyMMdd')
    $filePath = Join-Path $metricsRoot $fileName

    $minThreads = [Math]::Max(1, $MinThreads)
    $jobsPerThread = [Math]::Max(1, $JobsPerThread)
    $cpuValue = if ($CpuCount -gt 0) { $CpuCount } else { [Environment]::ProcessorCount }

    return [PSCustomObject]@{
        FilePath            = $filePath
        Buffer              = New-Object 'System.Collections.Generic.List[object]'
        LastSnapshot        = $null
        LastSnapshotTime    = [DateTime]::MinValue
        MaxThreads          = $MaxThreads
        MaxWorkersPerSite   = $MaxWorkersPerSite
        MaxActiveSites      = $MaxActiveSites
        TotalDevices        = [Math]::Max(0, $DeviceCount)
        MinThreads          = $minThreads
        JobsPerThread       = $jobsPerThread
        CpuCount            = [Math]::Max(1, $cpuValue)
        AdaptiveEnabled     = $AdaptiveThreads.IsPresent
        MinIntervalSeconds  = [Math]::Max(0, $MinIntervalSeconds)
        CurrentThreadBudget = $null
    }
}


function Write-ParserSchedulerMetricSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][int]$ActiveWorkers,
        [Parameter(Mandatory)][int]$ActiveSites,
        [Parameter(Mandatory)][int]$QueuedJobs,
        [Parameter(Mandatory)][int]$QueuedSites,
        [int]$ThreadBudget = -1,
        [switch]$Force
    )

    if (-not $Context) { return }

    $budgetValue = $ThreadBudget
    if ($budgetValue -lt 0) {
        if ($Context.PSObject.Properties.Name -contains 'CurrentThreadBudget' -and $Context.CurrentThreadBudget -ne $null) {
            try { $budgetValue = [int]$Context.CurrentThreadBudget } catch { $budgetValue = $Context.MaxThreads }
        } else {
            $budgetValue = $Context.MaxThreads
        }
    }

    $now = Get-Date
    $entry = [ordered]@{
        Timestamp         = $now.ToString('o')
        ActiveWorkers     = $ActiveWorkers
        ActiveSites       = $ActiveSites
        QueuedJobs        = $QueuedJobs
        QueuedSites       = $QueuedSites
        TotalDevices      = $Context.TotalDevices
        MaxThreads        = $Context.MaxThreads
        MaxWorkersPerSite = $Context.MaxWorkersPerSite
        MaxActiveSites    = $Context.MaxActiveSites
        ThreadBudget      = $budgetValue
    }

    $shouldRecord = $Force.IsPresent
    if (-not $shouldRecord) {
        $previous = $Context.LastSnapshot
        if (-not $previous) {
            $shouldRecord = $true
        } else {
            $previousBudget = $null
            try { if ($previous.PSObject.Properties.Name -contains 'ThreadBudget') { $previousBudget = [int]$previous.ThreadBudget } } catch { $previousBudget = $null }
            if ($previous.ActiveWorkers -ne $ActiveWorkers -or
                $previous.QueuedJobs -ne $QueuedJobs -or
                $previous.ActiveSites -ne $ActiveSites -or
                $previous.QueuedSites -ne $QueuedSites -or
                $previousBudget -ne $budgetValue) {
                $shouldRecord = $true
            } else {
                $minInterval = 0
                try {
                    if ($Context.PSObject.Properties.Name -contains 'MinIntervalSeconds') {
                        $minInterval = [int]$Context.MinIntervalSeconds
                    }
                } catch {
                    $minInterval = 0
                }
                if ($minInterval -gt 0 -and ($now - $Context.LastSnapshotTime).TotalSeconds -ge $minInterval) {
                    $shouldRecord = $true
                }
            }
        }
    }

    if (-not $shouldRecord) { return }

    $Context.CurrentThreadBudget = $budgetValue
    $snapshot = [PSCustomObject]$entry
    $Context.Buffer.Add($snapshot) | Out-Null
    $Context.LastSnapshot = $snapshot
    $Context.LastSnapshotTime = $now
}


function Get-AdaptiveThreadBudget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$ActiveWorkers,
        [Parameter(Mandatory)][int]$QueuedJobs,
        [Parameter(Mandatory)][int]$CpuCount,
        [Parameter(Mandatory)][int]$MinThreads,
        [Parameter(Mandatory)][int]$MaxThreads,
        [Parameter(Mandatory)][int]$JobsPerThread
    )

    if ($MinThreads -lt 1) { $MinThreads = 1 }
    if ($JobsPerThread -lt 1) { $JobsPerThread = 1 }
    if ($MaxThreads -lt $MinThreads) { $MaxThreads = $MinThreads }
    if ($CpuCount -lt 1) { $CpuCount = 1 }

    $cpuBound = [Math]::Max($MinThreads, [Math]::Min($MaxThreads, $CpuCount * 2))
    $desired = [Math]::Max($MinThreads, $ActiveWorkers)

    if ($QueuedJobs -gt 0) {
        $needed = [Math]::Ceiling($QueuedJobs / $JobsPerThread)
        $desired = [Math]::Max($desired, $ActiveWorkers + $needed)
    } elseif ($desired -lt $MinThreads) {
        $desired = $MinThreads
    }

    if ($desired -gt $cpuBound) { $desired = $cpuBound }
    if ($desired -gt $MaxThreads) { $desired = $MaxThreads }
    if ($desired -lt $ActiveWorkers) { $desired = $ActiveWorkers }

    return [int][Math]::Max($MinThreads, $desired)
}


function Finalize-SchedulerMetricsContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context
    )

    if (-not $Context) { return }
    if (-not $Context.Buffer -or $Context.Buffer.Count -eq 0) { return }

    try {
        $combined = New-Object 'System.Collections.Generic.List[object]'
        try {
            if (Test-Path -LiteralPath $Context.FilePath) {
                $existingRaw = Get-Content -LiteralPath $Context.FilePath -Raw -ErrorAction Stop
                if (-not [string]::IsNullOrWhiteSpace($existingRaw)) {
                    $existing = $existingRaw | ConvertFrom-Json -ErrorAction Stop
                    if ($existing -is [System.Collections.IEnumerable] -and -not ($existing -is [string])) {
                        foreach ($item in $existing) { $combined.Add($item) }
                    } elseif ($existing) {
                        $combined.Add($existing)
                    }
                }
            }
        } catch {
            $combined.Clear()
        }

        foreach ($entry in $Context.Buffer) { $combined.Add($entry) }

        $json = $combined | ConvertTo-Json -Depth 4
        Set-Content -LiteralPath $Context.FilePath -Value $json -Encoding UTF8 -Force
    } catch {
        # Swallow telemetry write errors to keep ingestion resilient.
    }
}


function Invoke-DeviceParseWorker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string]$ModulesPath,
        [Parameter(Mandatory=$true)][string]$ArchiveRoot,
        [string]$DatabasePath,
        [string]$SiteKey,
        [bool]$EnableVerbose = $false
    )

    if ($EnableVerbose) {
        $VerbosePreference = 'Continue'
        $DebugPreference   = 'Continue'
    } else {
        $VerbosePreference = 'SilentlyContinue'
        $DebugPreference   = 'SilentlyContinue'
    }
    $ErrorActionPreference = 'Stop'

    $userDocs = [Environment]::GetFolderPath('MyDocuments')
    $logDir   = Join-Path $userDocs 'StateTrace\Logs'
    try {
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
    } catch { }
    $logPath  = Join-Path $logDir ('StateTrace_Worker_{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
    $logToFile = $EnableVerbose

    $writeLog = {
        param([string]$Message)
        try {
            $line = "[{0}] [Worker] {1}" -f (Get-Date -Format 'HH:mm:ss.fff'), $Message
            if ($logToFile) {
                Add-Content -LiteralPath $logPath -Value $line -ErrorAction SilentlyContinue
            }
            Write-Verbose $line
        } catch {
            Write-Verbose $Message
        }
    }

    $langMode = $ExecutionContext.SessionState.LanguageMode
    $keywordsOk = $false
    try { if ($true) { $keywordsOk = $true } } catch { $keywordsOk = $false }
    & $writeLog ("LangMode={0} | keyword_if_ok={1}" -f $langMode, $keywordsOk)
    if ($langMode -ne [System.Management.Automation.PSLanguageMode]::FullLanguage) {
        throw "Worker runspace LanguageMode is $langMode (expected FullLanguage)"
    }

    $resolvedSiteKey = ''
    if ($PSBoundParameters.ContainsKey('SiteKey') -and -not [string]::IsNullOrWhiteSpace($SiteKey)) {
        $resolvedSiteKey = ('' + $SiteKey).Trim()
    }
    if ([string]::IsNullOrWhiteSpace($resolvedSiteKey)) {
        try {
            $hostToken = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
            if (-not [string]::IsNullOrWhiteSpace($hostToken)) {
                $resolvedSiteKey = $hostToken
                $siteCmd = Get-Command -Name 'DeviceRepositoryModule\Get-SiteFromHostname' -ErrorAction SilentlyContinue
                if ($siteCmd) {
                    $candidateSite = & $siteCmd -Hostname $hostToken
                    if (-not [string]::IsNullOrWhiteSpace($candidateSite)) {
                        $resolvedSiteKey = ('' + $candidateSite).Trim()
                    }
                }
            }
        } catch {
            $resolvedSiteKey = ''
        }
    }
    if ([string]::IsNullOrWhiteSpace($resolvedSiteKey)) { $resolvedSiteKey = 'Unknown' }

    Initialize-WorkerModules -ModulesPath $ModulesPath

    $preSummary = $null
    try { $preSummary = DeviceRepositoryModule\Get-InterfaceSiteCacheSummary -Site $resolvedSiteKey } catch { $preSummary = $null }
    Publish-RunspaceCacheTelemetry -Stage 'Worker:PreParse' -Site $resolvedSiteKey -Summary $preSummary

    $parseSucceeded = $false
    try {
        & $writeLog ("Parsing: {0}" -f $FilePath)
        DeviceLogParserModule\Invoke-DeviceLogParsing -FilePath $FilePath -ArchiveRoot $ArchiveRoot -DatabasePath $DatabasePath
        & $writeLog ("Parsing complete: {0}" -f $FilePath)
        $parseSucceeded = $true
    } catch {
        $message = $_.Exception.Message
        $position = ''
        try { $position = $_.InvocationInfo.PositionMessage } catch { }
        $stack = ''
        try { $stack = $_.ScriptStackTrace } catch { }

        $builder = [System.Text.StringBuilder]::new()
        [void]$builder.Append("Log parsing failed in worker: $message")
        [void]$builder.Append("`nWorker LangMode: $langMode")
        if ($_.FullyQualifiedErrorId) { [void]$builder.Append("`nFQEID: $($_.FullyQualifiedErrorId)") }
        if ($_.CategoryInfo)         { [void]$builder.Append("`nCategory: $($_.CategoryInfo)") }
        if ($position) { [void]$builder.Append("`nPosition:`n$position") }
        if ($stack)    { [void]$builder.Append("`nStack:`n$stack") }
        $formatted = $builder.ToString()
        & $writeLog $formatted
        throw $formatted
    } finally {
        $postSummary = $null
        try { $postSummary = DeviceRepositoryModule\Get-InterfaceSiteCacheSummary -Site $resolvedSiteKey } catch { $postSummary = $null }
        $postStage = if ($parseSucceeded) { 'Worker:PostParse' } else { 'Worker:PostParseError' }
        Publish-RunspaceCacheTelemetry -Stage $postStage -Site $resolvedSiteKey -Summary $postSummary
    }
}

function Invoke-DeviceParsingJobs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string[]]$DeviceFiles,
        [Parameter(Mandatory=$true)][string]$ModulesPath,
        [Parameter(Mandatory=$true)][string]$ArchiveRoot,
        [string]$DatabasePath,
        [int]$MaxThreads = 20,
        [int]$MinThreads = 1,
        [int]$JobsPerThread = 2,
        [int]$MaxWorkersPerSite = 1,
        [int]$MaxActiveSites = 0,
        [switch]$AdaptiveThreads,
        [switch]$Synchronous,
        [switch]$PreserveRunspacePool
    )

    if (-not $DeviceFiles -or $DeviceFiles.Count -eq 0) { return }

    if (-not $PreserveRunspacePool.IsPresent -and $script:PreservedRunspacePool) {
        Publish-RunspacePoolEvent -Operation 'Reset' -Reason 'PreserveFlagNotSet' -Pool $script:PreservedRunspacePool -PoolConfig $script:PreservedRunspaceConfig
        Reset-DeviceParseRunspacePool
    }

    if ($MinThreads -lt 1) { $MinThreads = 1 }
    if ($JobsPerThread -lt 1) { $JobsPerThread = 1 }
    if ($MaxThreads -lt $MinThreads) { $MaxThreads = $MinThreads }
    $cpuCount = [Math]::Max(1, [Environment]::ProcessorCount)

    $enableVerbose = $false
    try { $enableVerbose = [bool]$Global:StateTraceDebug } catch { $enableVerbose = $false }

    Initialize-WorkerModules -ModulesPath $ModulesPath

    if ($Synchronous -or $MaxThreads -le 1) {
        foreach ($file in $DeviceFiles) {
            $siteKeyValue = 'Unknown'
            try {
                $hostToken = [System.IO.Path]::GetFileNameWithoutExtension($file)
                if (-not [string]::IsNullOrWhiteSpace($hostToken)) {
                    $siteKeyValue = $hostToken
                    $siteCmd = Get-Command -Name 'DeviceRepositoryModule\Get-SiteFromHostname' -ErrorAction SilentlyContinue
                    if ($siteCmd) {
                        $candidateSite = & $siteCmd -Hostname $hostToken
                        if (-not [string]::IsNullOrWhiteSpace($candidateSite)) {
                            $siteKeyValue = ('' + $candidateSite).Trim()
                        }
                    }
                }
            } catch {
                $siteKeyValue = 'Unknown'
            }
            Invoke-DeviceParseWorker -FilePath $file -ModulesPath $ModulesPath -ArchiveRoot $ArchiveRoot -DatabasePath $DatabasePath -EnableVerbose:$enableVerbose -SiteKey $siteKeyValue
        }
        return
    }

    $pool = $null
    $poolConfig = @{
        ModulesPath      = (try { [System.IO.Path]::GetFullPath($ModulesPath) } catch { $ModulesPath })
        MaxThreads       = [int]$MaxThreads
        MinThreads       = [int]$MinThreads
        JobsPerThread    = [int]$JobsPerThread
        MaxWorkersPerSite = [int]$MaxWorkersPerSite
        MaxActiveSites    = [int]$MaxActiveSites
    }

    if ($PreserveRunspacePool) {
        $existingPool = $script:PreservedRunspacePool
        $existingConfig = $script:PreservedRunspaceConfig
        if ($existingPool -and $existingConfig) {
            $stateName = '' + $existingPool.RunspacePoolStateInfo.State
            if ([System.StringComparer]::OrdinalIgnoreCase.Equals($stateName, 'Opened')) {
                $configMatches = $true
                foreach ($key in $poolConfig.Keys) {
                    if (-not $existingConfig.ContainsKey($key)) {
                        $configMatches = $false
                        break
                    }
                    $currentValue = $poolConfig[$key]
                    $previousValue = $existingConfig[$key]
                    if ($key -eq 'ModulesPath') {
                        $leftValue = if ($null -ne $previousValue) { '' + $previousValue } else { '' }
                        $rightValue = if ($null -ne $currentValue) { '' + $currentValue } else { '' }
                        if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($leftValue, $rightValue)) {
                            $configMatches = $false
                            break
                        }
                    } else {
                        if ($previousValue -ne $currentValue) {
                            $configMatches = $false
                            break
                        }
                    }
                }

                if ($configMatches) {
                    $pool = $existingPool
                    Publish-RunspacePoolEvent -Operation 'Reuse' -Pool $existingPool -PoolConfig $existingConfig
                } else {
                    Publish-RunspacePoolEvent -Operation 'Reset' -Reason 'ConfigChanged' -Pool $existingPool -PoolConfig $existingConfig
                    Reset-DeviceParseRunspacePool
                }
            } else {
                Publish-RunspacePoolEvent -Operation 'Reset' -Reason 'PoolNotOpen' -Pool $existingPool -PoolConfig $existingConfig
                Reset-DeviceParseRunspacePool
            }
        }
    }

    if (-not $pool) {
        $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $sessionState.ApartmentState = [System.Threading.ApartmentState]::STA
        $sessionState.LanguageMode = [System.Management.Automation.PSLanguageMode]::FullLanguage
        $importList = Get-RunspaceModuleImportList -ModulesPath $ModulesPath
        if ($importList -and $importList.Count -gt 0) { $null = $sessionState.ImportPSModule($importList) }
        $pool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads, $sessionState, $Host)
        try { $pool.ApartmentState = [System.Threading.ApartmentState]::STA } catch { }
        $pool.Open()
        if ($PreserveRunspacePool) {
            $script:PreservedRunspacePool = $pool
            $script:PreservedRunspaceConfig = $poolConfig
        }
        Publish-RunspacePoolEvent -Operation 'Create' -Pool $pool -PoolConfig $poolConfig
    } elseif ($PreserveRunspacePool) {
        $script:PreservedRunspaceConfig = $poolConfig
    }

    function Get-HostnameFromPath([string]$PathValue) {
        if ([string]::IsNullOrWhiteSpace($PathValue)) { return 'Unknown' }
        try {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($PathValue)
            if ([string]::IsNullOrWhiteSpace($name)) { return 'Unknown' }
            return $name
        } catch {
            return 'Unknown'
        }
    }

    function Get-SiteKeyFromHostname([string]$Hostname) {
        if ([string]::IsNullOrWhiteSpace($Hostname)) { return 'Unknown' }
        try {
            $cmd = Get-Command -Name 'DeviceRepositoryModule\Get-SiteFromHostname' -ErrorAction Stop
            $site = & $cmd -Hostname $Hostname
            if (-not [string]::IsNullOrWhiteSpace($site)) { return $site }
        } catch { }
        return $Hostname
    }

    $metricsContext = Initialize-SchedulerMetricsContext -ModulesPath $ModulesPath -DeviceCount $DeviceFiles.Count -MaxThreads $MaxThreads -MaxWorkersPerSite $MaxWorkersPerSite -MaxActiveSites $MaxActiveSites -MinThreads $MinThreads -JobsPerThread $JobsPerThread -CpuCount $cpuCount -AdaptiveThreads:$AdaptiveThreads
    $currentThreadLimit = $MaxThreads

    $siteQueues = [ordered]@{}
    foreach ($file in $DeviceFiles) {
        $host = Get-HostnameFromPath -PathValue $file
        $siteKey = Get-SiteKeyFromHostname -Hostname $host
        if (-not $siteQueues.Contains($siteKey)) {
            $siteQueues[$siteKey] = New-Object 'System.Collections.Generic.Queue[string]'
        }
        $siteQueues[$siteKey].Enqueue($file)
    }

    if ($metricsContext) {
        $initialQueued = 0
        $initialQueuedSites = 0
        foreach ($queue in $siteQueues.Values) {
            $initialQueued += $queue.Count
            if ($queue.Count -gt 0) { $initialQueuedSites++ }
        }
        if ($AdaptiveThreads) {
            $currentThreadLimit = Get-AdaptiveThreadBudget -ActiveWorkers 0 -QueuedJobs $initialQueued -CpuCount $cpuCount -MinThreads $MinThreads -MaxThreads $MaxThreads -JobsPerThread $JobsPerThread
        } else {
            $currentThreadLimit = $MaxThreads
        }
        Write-ParserSchedulerMetricSnapshot -Context $metricsContext -ActiveWorkers 0 -ActiveSites 0 -QueuedJobs $initialQueued -QueuedSites $initialQueuedSites -ThreadBudget $currentThreadLimit -Force
    }

    $active = New-Object 'System.Collections.Generic.List[object]'
    try {
        while ($true) {
            $activeSiteSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($entry in $active) { [void]$activeSiteSet.Add($entry.Site) }

            $totalQueued = 0
            $queuedSiteCount = 0
            foreach ($queue in $siteQueues.Values) {
                $totalQueued += $queue.Count
                if ($queue.Count -gt 0) { $queuedSiteCount++ }
            }

            if ($AdaptiveThreads) {
                $currentThreadLimit = Get-AdaptiveThreadBudget -ActiveWorkers $active.Count -QueuedJobs $totalQueued -CpuCount $cpuCount -MinThreads $MinThreads -MaxThreads $MaxThreads -JobsPerThread $JobsPerThread
            } else {
                $currentThreadLimit = $MaxThreads
            }

            if ($metricsContext) {
                Write-ParserSchedulerMetricSnapshot -Context $metricsContext -ActiveWorkers $active.Count -ActiveSites $activeSiteSet.Count -QueuedJobs $totalQueued -QueuedSites $queuedSiteCount -ThreadBudget $currentThreadLimit
            }

            if ($totalQueued -eq 0 -and $active.Count -eq 0) { break }

            $launched = $false
            if ($active.Count -lt $currentThreadLimit) {
                foreach ($siteKey in $siteQueues.Keys) {
                    $queue = $siteQueues[$siteKey]
                    if ($queue.Count -eq 0) { continue }

                    $perSiteActive = 0
                    foreach ($entry in $active) { if ([System.StringComparer]::OrdinalIgnoreCase.Equals($entry.Site, $siteKey)) { $perSiteActive++ } }
                    if ($MaxWorkersPerSite -gt 0 -and $perSiteActive -ge $MaxWorkersPerSite) { continue }
                    if ($MaxActiveSites -gt 0 -and $perSiteActive -eq 0 -and $activeSiteSet.Count -ge $MaxActiveSites) { continue }

                    $file = $queue.Dequeue()
                    $ps = [powershell]::Create()
                    $ps.RunspacePool = $pool
                    $null = $ps.AddCommand('ParserRunspaceModule\Invoke-DeviceParseWorker')
                    $null = $ps.AddParameter('FilePath', $file)
                    $null = $ps.AddParameter('ModulesPath', $ModulesPath)
                    $null = $ps.AddParameter('ArchiveRoot', $ArchiveRoot)
                    if ($DatabasePath) { $null = $ps.AddParameter('DatabasePath', $DatabasePath) }
                    $null = $ps.AddParameter('SiteKey', $siteKey)
                    $null = $ps.AddParameter('EnableVerbose', $enableVerbose)
                    $async = $ps.BeginInvoke()
                    $active.Add([PSCustomObject]@{ Pipe = $ps; AsyncResult = $async; Site = $siteKey })
                    [void]$activeSiteSet.Add($siteKey)
                    $launched = $true

                    if ($active.Count -ge $currentThreadLimit) { break }
                }
            }

            $completed = @()
            foreach ($entry in $active.ToArray()) {
                if ($entry.AsyncResult.IsCompleted) {
                    try { $entry.Pipe.EndInvoke($entry.AsyncResult) } catch { } finally { $entry.Pipe.Dispose() }
                    $completed += $entry
                }
            }
            if ($completed.Count -gt 0) {
                foreach ($entry in $completed) { [void]$active.Remove($entry) }
                continue
            }

            if (-not $launched) { Start-Sleep -Milliseconds 25 }
        }


        if ($metricsContext) {
            Write-ParserSchedulerMetricSnapshot -Context $metricsContext -ActiveWorkers 0 -ActiveSites 0 -QueuedJobs 0 -QueuedSites 0 -ThreadBudget $currentThreadLimit -Force
        }

    } finally {
        foreach ($entry in $active.ToArray()) {
            try { $entry.Pipe.EndInvoke($entry.AsyncResult) } catch { }
            $entry.Pipe.Dispose()
        }

        if ($PreserveRunspacePool) {
            if ($pool -ne $script:PreservedRunspacePool) {
                try { $pool.Close() } catch { }
                try { $pool.Dispose() } catch { }
            }
        } else {
            try { $pool.Close() } catch { }
            try { $pool.Dispose() } catch { }
            if ($script:PreservedRunspacePool -eq $pool) {
                $script:PreservedRunspacePool = $null
                $script:PreservedRunspaceConfig = $null
            }
        }

        if ($metricsContext) {
            Finalize-SchedulerMetricsContext -Context $metricsContext
        }
    }
}

function Reset-DeviceParseRunspacePool {
    [CmdletBinding()]
    param()

    if ($script:PreservedRunspacePool) {
        Publish-RunspacePoolEvent -Operation 'Dispose' -Reason 'ResetDeviceParseRunspacePool' -Pool $script:PreservedRunspacePool -PoolConfig $script:PreservedRunspaceConfig
        try { $script:PreservedRunspacePool.Close() } catch { }
        try { $script:PreservedRunspacePool.Dispose() } catch { }
    }

    $script:PreservedRunspacePool = $null
    $script:PreservedRunspaceConfig = $null
}

function Invoke-InterfaceSiteCacheWarmup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Sites,
        [switch]$Refresh
    )

    if (-not $Sites -or $Sites.Count -eq 0) { return }

    $pool = $script:PreservedRunspacePool
    if (-not $pool) { return }

    $jobs = New-Object 'System.Collections.Generic.List[object]'
    foreach ($site in $Sites) {
        if ([string]::IsNullOrWhiteSpace($site)) { continue }
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        $scriptBlock = {
            param($siteArg, [bool]$refreshFlag)

            $resolvedSite = if ($siteArg) { ('' + $siteArg).Trim() } else { '' }
            $stageRoot = if ($refreshFlag) { 'WarmupRefresh' } else { 'WarmupProbe' }

            $beforeSummary = $null
            try { $beforeSummary = DeviceRepositoryModule\Get-InterfaceSiteCacheSummary -Site $resolvedSite } catch { $beforeSummary = $null }
            try { ParserRunspaceModule\Publish-RunspaceCacheTelemetry -Stage ($stageRoot + ':Before') -Site $resolvedSite -Summary $beforeSummary } catch { }

            if ($refreshFlag) {
                DeviceRepositoryModule\Get-InterfaceSiteCache -Site $resolvedSite -Refresh | Out-Null
            } else {
                DeviceRepositoryModule\Get-InterfaceSiteCache -Site $resolvedSite | Out-Null
            }

            $afterSummary = $null
            try { $afterSummary = DeviceRepositoryModule\Get-InterfaceSiteCacheSummary -Site $resolvedSite } catch { $afterSummary = $null }
            try { ParserRunspaceModule\Publish-RunspaceCacheTelemetry -Stage ($stageRoot + ':After') -Site $resolvedSite -Summary $afterSummary } catch { }
        }
        $null = $ps.AddScript($scriptBlock).AddArgument($site).AddArgument($Refresh.IsPresent)
        $async = $ps.BeginInvoke()
        $jobs.Add([pscustomobject]@{ Pipe = $ps; Async = $async })
    }

    foreach ($job in $jobs) {
        try { $job.Pipe.EndInvoke($job.Async) } catch { }
        $job.Pipe.Dispose()
    }
}

Export-ModuleMember -Function Invoke-DeviceParseWorker, Invoke-DeviceParsingJobs, Reset-DeviceParseRunspacePool, Invoke-InterfaceSiteCacheWarmup, Publish-RunspaceCacheTelemetry



