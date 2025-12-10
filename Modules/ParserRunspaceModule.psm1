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

if (-not (Get-Variable -Scope Script -Name SchedulerTelemetryWriter -ErrorAction SilentlyContinue)) {
    $script:SchedulerTelemetryWriter = {
        param([string]$Name, $Payload)
        TelemetryModule\Write-StTelemetryEvent -Name $Name -Payload $Payload
    }
}

function Set-SchedulerTelemetryWriter {
    [CmdletBinding()]
    param([scriptblock]$Writer)

    if ($Writer) {
        $script:SchedulerTelemetryWriter = $Writer
    } else {
        $script:SchedulerTelemetryWriter = {
            param([string]$Name, $Payload)
            TelemetryModule\Write-StTelemetryEvent -Name $Name -Payload $Payload
        }
    }
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

function Publish-SchedulerLaunchTelemetry {
    [CmdletBinding()]
    param(
        [string]$Site,
        [int]$ActiveWorkers,
        [int]$ActiveSites,
        [int]$ThreadBudget,
        [int]$QueuedJobs,
        [int]$QueuedSites
    )

    $payload = @{
        Site          = if ($Site) { ('' + $Site).Trim() } else { '' }
        ActiveWorkers = [Math]::Max(0, [int]$ActiveWorkers)
        ActiveSites   = [Math]::Max(0, [int]$ActiveSites)
        ThreadBudget  = [Math]::Max(0, [int]$ThreadBudget)
        QueuedJobs    = [Math]::Max(0, [int]$QueuedJobs)
        QueuedSites   = [Math]::Max(0, [int]$QueuedSites)
    }

    $writer = $script:SchedulerTelemetryWriter
    if ($writer) {
        try {
            & $writer -Name 'ParserSchedulerLaunch' -Payload $payload
        } catch { }
    } else {
        try {
            TelemetryModule\Write-StTelemetryEvent -Name 'ParserSchedulerLaunch' -Payload $payload
        } catch { }
    }
}

function Get-ParserModulePaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ModulesPath
    )

    $paths = [System.Collections.Generic.List[string]]::new()
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

    try {
        $parserModule = Get-Module -Name 'ParserPersistenceModule' -ErrorAction SilentlyContinue
        if ($parserModule) {
            $parserModule.Invoke({ Import-SiteExistingRowCacheSnapshotFromEnv }) | Out-Null
        }
    } catch {
        Write-Verbose ("Site existing row cache snapshot import skipped: {0}" -f $_.Exception.Message)
    }

    $script:WorkerModulesInitialized = $true
}

function Get-ParserAutoScaleProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$DeviceFiles,
        [int]$CpuCount = 0,
        [int]$ThreadCeiling = 0,
        [int]$MaxWorkersPerSite = 0,
        [int]$MaxActiveSites = 0,
        [int]$JobsPerThread = 0,
        [int]$MinRunspaces = 0
    )

    try {
        $cmd = Get-Command -Name 'ParserWorker\Get-AutoScaleConcurrencyProfile' -ErrorAction SilentlyContinue
        if (-not $cmd) { $cmd = Get-Command -Name 'Get-AutoScaleConcurrencyProfile' -Module 'ParserWorker' -ErrorAction SilentlyContinue }
        if (-not $cmd) { $cmd = Get-Command -Name 'Get-AutoScaleConcurrencyProfile' -ErrorAction SilentlyContinue }
        if (-not $cmd) { return $null }

        $args = @{
            DeviceFiles       = $DeviceFiles
            CpuCount          = $CpuCount
            ThreadCeiling     = $ThreadCeiling
            MaxWorkersPerSite = $MaxWorkersPerSite
            MaxActiveSites    = $MaxActiveSites
            JobsPerThread     = $JobsPerThread
            MinRunspaces      = $MinRunspaces
        }
        return & $cmd @args
    } catch {
        return $null
    }
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
        Buffer              = [System.Collections.Generic.List[object]]::new()
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
        [Parameter(Mandatory)][int]$JobsPerThread,
        [int]$MaxWorkersPerSite = 0,
        [int]$MaxActiveSites = 0
    )

    if ($MinThreads -lt 1) { $MinThreads = 1 }
    if ($JobsPerThread -lt 1) { $JobsPerThread = 1 }
    if ($MaxThreads -lt $MinThreads) { $MaxThreads = $MinThreads }
    if ($CpuCount -lt 1) { $CpuCount = 1 }
    if ($MaxWorkersPerSite -lt 0) { $MaxWorkersPerSite = 0 }
    if ($MaxActiveSites -lt 0) { $MaxActiveSites = 0 }

    $cpuBound = [Math]::Max($MinThreads, [Math]::Min($MaxThreads, $CpuCount * 2))
    $desired = [Math]::Max($MinThreads, $ActiveWorkers)

    if ($QueuedJobs -gt 0) {
        $needed = [Math]::Ceiling($QueuedJobs / $JobsPerThread)
        $desired = [Math]::Max($desired, $ActiveWorkers + $needed)
    } elseif ($desired -lt $MinThreads) {
        $desired = $MinThreads
    }

    $siteBound = $MaxThreads
    if ($MaxActiveSites -gt 0) {
        $siteBound = [Math]::Min($siteBound, [Math]::Max($MinThreads, $MaxActiveSites * [Math]::Max(1, $MaxWorkersPerSite)))
    } elseif ($MaxWorkersPerSite -gt 0) {
        $siteBound = [Math]::Min($siteBound, [Math]::Max($MinThreads, $MaxWorkersPerSite))
    }

    if ($desired -gt $cpuBound) { $desired = $cpuBound }
    if ($desired -gt $siteBound) { $desired = $siteBound }
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
        $combined = [System.Collections.Generic.List[object]]::new()
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

function Get-NextSiteQueueJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$SiteQueues,
        [Parameter(Mandatory)][System.Collections.Generic.Queue[string]]$RotationQueue,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$ActiveEntries,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.HashSet[string]]$ActiveSiteSet,
        [int]$MaxWorkersPerSite = 0,
        [int]$MaxActiveSites = 0,
        [string]$LastLaunchedSite,
        [int]$LastSiteConsecutive = 0,
        [int]$MaxConsecutivePerSite = 0
    )

    if (-not $RotationQueue -or $RotationQueue.Count -eq 0) {
        return $null
    }

    $consecutiveLimiterEnabled = ($MaxConsecutivePerSite -gt 0 -and $LastSiteConsecutive -ge $MaxConsecutivePerSite -and -not [string]::IsNullOrWhiteSpace($LastLaunchedSite))
    $limitBypassActive = $false
    $attempt = 0
    do {
        $skipDueToConsecutiveLimit = $false
        $rotationChecks = $RotationQueue.Count
        for ($i = 0; $i -lt $rotationChecks; $i++) {
            if ($RotationQueue.Count -eq 0) { break }
            $siteKey = $RotationQueue.Peek()
            if ([string]::IsNullOrWhiteSpace($siteKey)) {
                [void]$RotationQueue.Dequeue()
                continue
            }

            $queue = $SiteQueues[$siteKey]
            if (-not $queue -or $queue.Count -eq 0) {
                [void]$RotationQueue.Dequeue()
                continue
            }

            $perSiteActive = 0
            foreach ($entry in $ActiveEntries) {
                if (-not $entry) { continue }
                $entrySite = '' + $entry.Site
                if ([string]::IsNullOrWhiteSpace($entrySite)) { continue }
                if ([System.StringComparer]::OrdinalIgnoreCase.Equals($entrySite, $siteKey)) {
                    $perSiteActive++
                }
            }

            if ($MaxWorkersPerSite -gt 0 -and $perSiteActive -ge $MaxWorkersPerSite) {
                [void]$RotationQueue.Dequeue()
                $RotationQueue.Enqueue($siteKey)
                continue
            }

            if ($MaxActiveSites -gt 0 -and $perSiteActive -eq 0 -and $ActiveSiteSet.Count -ge $MaxActiveSites) {
                return $null
            }

            if ($consecutiveLimiterEnabled -and $attempt -eq 0 -and [System.StringComparer]::OrdinalIgnoreCase.Equals($siteKey, $LastLaunchedSite)) {
                $skipDueToConsecutiveLimit = $true
                $limitBypassActive = $true
                [void]$RotationQueue.Dequeue()
                $RotationQueue.Enqueue($siteKey)
                continue
            }

            [void]$RotationQueue.Dequeue()
            $filePath = $queue.Dequeue()
            if ($queue.Count -gt 0) {
                $RotationQueue.Enqueue($siteKey)
            }

            $fairnessBypassUsed = ($limitBypassActive -and [System.StringComparer]::OrdinalIgnoreCase.Equals($siteKey, $LastLaunchedSite))

            return [pscustomobject]@{
                Site     = $siteKey
                FilePath = $filePath
                FairnessBypassUsed = $fairnessBypassUsed
            }
        }

        if (-not $skipDueToConsecutiveLimit) {
            break
        }
        $attempt++
    } while ($attempt -lt 2)

    return $null
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
        [int]$MaxConsecutiveSiteLaunches = 0,
        [switch]$AdaptiveThreads,
        [switch]$Synchronous,
        [switch]$UseAutoScaleProfile,
        [switch]$PreserveRunspacePool
    )

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

    if (-not $DeviceFiles -or $DeviceFiles.Count -eq 0) { return }

    # When a preserved runspace pool is requested, force the multi-runspace path even for single-threaded runs.
    if ($PreserveRunspacePool) {
        # Force a single runspace to maximize cache reuse across passes when preservation is requested.
        $MaxThreads = 1
        $MinThreads = 1
        $MaxWorkersPerSite = 1
        $MaxActiveSites = 1

        if ($MaxThreads -lt 1) { $MaxThreads = 1 }
        if ($MinThreads -lt 1) { $MinThreads = 1 }
        $Synchronous = $false
    }

    $useAutoScaleProfile = $UseAutoScaleProfile.IsPresent
    $hasThreadHint = $PSBoundParameters.ContainsKey('MaxThreads')
    $hasMinThreadHint = $PSBoundParameters.ContainsKey('MinThreads')
    $hasWorkerHint = $PSBoundParameters.ContainsKey('MaxWorkersPerSite')
    $hasActiveHint = $PSBoundParameters.ContainsKey('MaxActiveSites')
    $hasJobsHint = $PSBoundParameters.ContainsKey('JobsPerThread')
    $hasConcurrencyHints = ($hasThreadHint -or $hasMinThreadHint -or $hasWorkerHint -or $hasActiveHint -or $hasJobsHint)

    $consecutiveLimit = 0
    if ($MaxConsecutiveSiteLaunches -gt 0) {
        $consecutiveLimit = [Math]::Max(1, [int]$MaxConsecutiveSiteLaunches)
    }

    if (-not $PreserveRunspacePool.IsPresent -and $script:PreservedRunspacePool) {
        Publish-RunspacePoolEvent -Operation 'Reset' -Reason 'PreserveFlagNotSet' -Pool $script:PreservedRunspacePool -PoolConfig $script:PreservedRunspaceConfig
        Reset-DeviceParseRunspacePool
    }

    if ($MinThreads -lt 1) { $MinThreads = 1 }
    if ($JobsPerThread -lt 1) { $JobsPerThread = 1 }
    if ($MaxThreads -lt $MinThreads) { $MaxThreads = $MinThreads }

    $profileCpuCount = [Math]::Max(1, [Environment]::ProcessorCount)

    if (-not $useAutoScaleProfile -and -not $hasConcurrencyHints -and -not $Synchronous -and -not $PreserveRunspacePool.IsPresent) {
        $useAutoScaleProfile = $true
    }

    if ($useAutoScaleProfile) {
        $profile = Get-ParserAutoScaleProfile -DeviceFiles $DeviceFiles -CpuCount $profileCpuCount -ThreadCeiling $MaxThreads -MaxWorkersPerSite $MaxWorkersPerSite -MaxActiveSites $MaxActiveSites -JobsPerThread $JobsPerThread -MinRunspaces $MinThreads
        if ($profile) {
            if (-not $PSBoundParameters.ContainsKey('MaxThreads') -or $MaxThreads -le 0) { $MaxThreads = [int]$profile.ThreadCeiling }
            if (-not $PSBoundParameters.ContainsKey('MaxWorkersPerSite') -or $MaxWorkersPerSite -le 0) { $MaxWorkersPerSite = [int]$profile.MaxWorkersPerSite }
            if (-not $PSBoundParameters.ContainsKey('MaxActiveSites') -or $MaxActiveSites -le 0) { $MaxActiveSites = [int]$profile.MaxActiveSites }
            if (-not $PSBoundParameters.ContainsKey('JobsPerThread') -or $JobsPerThread -le 0) { $JobsPerThread = [int]$profile.JobsPerThread }
            if (-not $PSBoundParameters.ContainsKey('MinThreads') -or $MinThreads -le 0) { $MinThreads = [int]$profile.MinRunspaces }
            if ($MaxThreads -lt $MinThreads) { $MaxThreads = $MinThreads }
        }
    }

    $cpuCount = $profileCpuCount

    $enableVerbose = $false
    try { $enableVerbose = [bool]$Global:StateTraceDebug } catch { $enableVerbose = $false }

    Initialize-WorkerModules -ModulesPath $ModulesPath

    $siteQueues = [ordered]@{}
    $siteRotation = [System.Collections.Generic.Queue[string]]::new()
    foreach ($file in $DeviceFiles) {
        $hostToken = Get-HostnameFromPath -PathValue $file
        $siteKeyValue = Get-SiteKeyFromHostname -Hostname $hostToken
        if ([string]::IsNullOrWhiteSpace($siteKeyValue)) { $siteKeyValue = 'Unknown' }
        if (-not $siteQueues.Contains($siteKeyValue)) {
            $siteQueues[$siteKeyValue] = New-Object 'System.Collections.Generic.Queue[string]'
            [void]$siteRotation.Enqueue($siteKeyValue)
        }
        $siteQueues[$siteKeyValue].Enqueue($file)
    }

    if ($Synchronous -or $MaxThreads -le 1) {
        $activeEntries = [System.Collections.Generic.List[object]]::new()
        $activeSites = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $lastLaunchSite = ''
        $lastLaunchCount = 0

        while ($true) {
            $nextJob = Get-NextSiteQueueJob -SiteQueues $siteQueues -RotationQueue $siteRotation -ActiveEntries $activeEntries -ActiveSiteSet $activeSites -MaxWorkersPerSite $MaxWorkersPerSite -MaxActiveSites $MaxActiveSites -LastLaunchedSite $lastLaunchSite -LastSiteConsecutive $lastLaunchCount -MaxConsecutivePerSite $consecutiveLimit
            if (-not $nextJob) { break }

            $remainingQueued = 0
            $remainingQueuedSites = 0
            foreach ($queue in $siteQueues.Values) {
                $remainingQueued += $queue.Count
                if ($queue.Count -gt 0) { $remainingQueuedSites++ }
            }
            Publish-SchedulerLaunchTelemetry -Site $nextJob.Site -ActiveWorkers 1 -ActiveSites 1 -ThreadBudget 1 -QueuedJobs $remainingQueued -QueuedSites $remainingQueuedSites
            Invoke-DeviceParseWorker -FilePath $nextJob.FilePath -ModulesPath $ModulesPath -ArchiveRoot $ArchiveRoot -DatabasePath $DatabasePath -EnableVerbose:$enableVerbose -SiteKey $nextJob.Site

            $fairnessBypass = $false
            if ($nextJob.PSObject.Properties.Name -contains 'FairnessBypassUsed') {
                $fairnessBypass = [bool]$nextJob.FairnessBypassUsed
            }

            if ($fairnessBypass) {
                $lastLaunchSite = $nextJob.Site
                $lastLaunchCount = 1
            } elseif ([string]::IsNullOrWhiteSpace($lastLaunchSite) -or -not [System.StringComparer]::OrdinalIgnoreCase.Equals($lastLaunchSite, $nextJob.Site)) {
                $lastLaunchSite = $nextJob.Site
                $lastLaunchCount = 1
            } else {
                $lastLaunchCount++
            }
        }
        return
    }

    $pool = $null
    $resolvedModulesPath = $ModulesPath
    try {
        $resolvedModulesPath = [System.IO.Path]::GetFullPath($ModulesPath)
    } catch {
        $resolvedModulesPath = $ModulesPath
    }
    $poolConfig = @{
        ModulesPath       = $resolvedModulesPath
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

    $metricsContext = Initialize-SchedulerMetricsContext -ModulesPath $ModulesPath -DeviceCount $DeviceFiles.Count -MaxThreads $MaxThreads -MaxWorkersPerSite $MaxWorkersPerSite -MaxActiveSites $MaxActiveSites -MinThreads $MinThreads -JobsPerThread $JobsPerThread -CpuCount $cpuCount -AdaptiveThreads:$AdaptiveThreads
    $currentThreadLimit = $MaxThreads

    if ($metricsContext) {
        $initialQueued = 0
        $initialQueuedSites = 0
        foreach ($queue in $siteQueues.Values) {
            $initialQueued += $queue.Count
            if ($queue.Count -gt 0) { $initialQueuedSites++ }
        }
        if ($AdaptiveThreads) {
            $currentThreadLimit = Get-AdaptiveThreadBudget -ActiveWorkers 0 -QueuedJobs $initialQueued -CpuCount $cpuCount -MinThreads $MinThreads -MaxThreads $MaxThreads -JobsPerThread $JobsPerThread -MaxWorkersPerSite $MaxWorkersPerSite -MaxActiveSites $MaxActiveSites
        } else {
            $currentThreadLimit = $MaxThreads
        }
        Write-ParserSchedulerMetricSnapshot -Context $metricsContext -ActiveWorkers 0 -ActiveSites 0 -QueuedJobs $initialQueued -QueuedSites $initialQueuedSites -ThreadBudget $currentThreadLimit -Force
    }

    $active = [System.Collections.Generic.List[object]]::new()
    $lastLaunchSite = ''
    $lastLaunchCount = 0
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
                $currentThreadLimit = Get-AdaptiveThreadBudget -ActiveWorkers $active.Count -QueuedJobs $totalQueued -CpuCount $cpuCount -MinThreads $MinThreads -MaxThreads $MaxThreads -JobsPerThread $JobsPerThread -MaxWorkersPerSite $MaxWorkersPerSite -MaxActiveSites $MaxActiveSites
            } else {
                $currentThreadLimit = $MaxThreads
            }

            if ($metricsContext) {
                Write-ParserSchedulerMetricSnapshot -Context $metricsContext -ActiveWorkers $active.Count -ActiveSites $activeSiteSet.Count -QueuedJobs $totalQueued -QueuedSites $queuedSiteCount -ThreadBudget $currentThreadLimit
            }

            if ($totalQueued -eq 0 -and $active.Count -eq 0) { break }

            $launched = $false
            if ($active.Count -lt $currentThreadLimit) {
                $nextJob = Get-NextSiteQueueJob -SiteQueues $siteQueues -RotationQueue $siteRotation -ActiveEntries $active -ActiveSiteSet $activeSiteSet -MaxWorkersPerSite $MaxWorkersPerSite -MaxActiveSites $MaxActiveSites -LastLaunchedSite $lastLaunchSite -LastSiteConsecutive $lastLaunchCount -MaxConsecutivePerSite $consecutiveLimit
                if ($nextJob) {
                    $ps = [powershell]::Create()
                    $ps.RunspacePool = $pool
                    $null = $ps.AddCommand('ParserRunspaceModule\Invoke-DeviceParseWorker')
                    $null = $ps.AddParameter('FilePath', $nextJob.FilePath)
                    $null = $ps.AddParameter('ModulesPath', $ModulesPath)
                    $null = $ps.AddParameter('ArchiveRoot', $ArchiveRoot)
                    if ($DatabasePath) { $null = $ps.AddParameter('DatabasePath', $DatabasePath) }
                    $null = $ps.AddParameter('SiteKey', $nextJob.Site)
                    $null = $ps.AddParameter('EnableVerbose', $enableVerbose)
                    $async = $ps.BeginInvoke()
                    $active.Add([PSCustomObject]@{ Pipe = $ps; AsyncResult = $async; Site = $nextJob.Site })
                    [void]$activeSiteSet.Add($nextJob.Site)
                    $launched = $true

                    $remainingQueued = 0
                    $remainingQueuedSites = 0
                    foreach ($queue in $siteQueues.Values) {
                        $remainingQueued += $queue.Count
                        if ($queue.Count -gt 0) { $remainingQueuedSites++ }
                    }
                    Publish-SchedulerLaunchTelemetry -Site $nextJob.Site -ActiveWorkers $active.Count -ActiveSites $activeSiteSet.Count -ThreadBudget $currentThreadLimit -QueuedJobs $remainingQueued -QueuedSites $remainingQueuedSites

                    $fairnessBypass = $false
                    if ($nextJob.PSObject.Properties.Name -contains 'FairnessBypassUsed') {
                        $fairnessBypass = [bool]$nextJob.FairnessBypassUsed
                    }

                    if ($fairnessBypass) {
                        $lastLaunchSite = $nextJob.Site
                        $lastLaunchCount = 1
                    } elseif ([string]::IsNullOrWhiteSpace($lastLaunchSite) -or -not [System.StringComparer]::OrdinalIgnoreCase.Equals($lastLaunchSite, $nextJob.Site)) {
                        $lastLaunchSite = $nextJob.Site
                        $lastLaunchCount = 1
                    } else {
                        $lastLaunchCount++
                    }
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
        [switch]$Refresh,
        [System.Collections.IDictionary]$SiteEntries
    )

    if (-not $Sites -or $Sites.Count -eq 0) {
        try {
            Publish-RunspaceCacheTelemetry -Stage 'Warmup:SkippedNoSites' -Summary ([pscustomobject]@{ SiteCount = 0 })
        } catch { }
        return
    }

    $pool = $script:PreservedRunspacePool
    if (-not $pool) {
        $siteCountSummary = [pscustomobject]@{
            SiteCount = [int]$Sites.Count
            Reason    = 'MissingPreservedRunspacePool'
        }
        try { Publish-RunspaceCacheTelemetry -Stage 'Warmup:SkippedNoPool' -Summary $siteCountSummary } catch { }
        return
    }

    $jobs = [System.Collections.Generic.List[object]]::new()
    foreach ($site in $Sites) {
        if ([string]::IsNullOrWhiteSpace($site)) { continue }
        $lookupKey = ('' + $site).Trim()
        if ([string]::IsNullOrWhiteSpace($lookupKey)) { $lookupKey = '' + $site }
        $entryPayload = $null
        if ($SiteEntries) {
            try {
                if ($SiteEntries.Contains($lookupKey)) {
                    $entryPayload = $SiteEntries[$lookupKey]
                }
            } catch {
                $entryPayload = $null
            }
        }
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        $scriptBlock = {
            param($siteArg, [bool]$refreshFlag, $entryPayload)

            $resolvedSite = if ($siteArg) { ('' + $siteArg).Trim() } else { '' }
            $stageRoot = if ($refreshFlag) { 'WarmupRefresh' } else { 'WarmupProbe' }

            $beforeSummary = $null
            try { $beforeSummary = DeviceRepositoryModule\Get-InterfaceSiteCacheSummary -Site $resolvedSite } catch { $beforeSummary = $null }
            try { ParserRunspaceModule\Publish-RunspaceCacheTelemetry -Stage ($stageRoot + ':Before') -Site $resolvedSite -Summary $beforeSummary } catch { }

            if ($entryPayload) {
                try { DeviceRepositoryModule\Set-SharedSiteInterfaceCacheEntry -SiteKey $resolvedSite -Entry $entryPayload } catch { }
            }

            if ($refreshFlag) {
                DeviceRepositoryModule\Get-InterfaceSiteCache -Site $resolvedSite -Refresh | Out-Null
            } else {
                DeviceRepositoryModule\Get-InterfaceSiteCache -Site $resolvedSite | Out-Null
            }

            $afterSummary = $null
            try { $afterSummary = DeviceRepositoryModule\Get-InterfaceSiteCacheSummary -Site $resolvedSite } catch { $afterSummary = $null }
            try { ParserRunspaceModule\Publish-RunspaceCacheTelemetry -Stage ($stageRoot + ':After') -Site $resolvedSite -Summary $afterSummary } catch { }
        }
        $scriptText = $scriptBlock.ToString()
        # Use AddScript with explicit script text to avoid PowerShell treating tokens like "-join" as remaining scripts.
        $null = $ps.AddScript($scriptText, $true).AddArgument($site).AddArgument($Refresh.IsPresent).AddArgument($entryPayload)
        $async = $ps.BeginInvoke()
        $jobs.Add([pscustomobject]@{ Pipe = $ps; Async = $async })
    }

    foreach ($job in $jobs) {
        try { $job.Pipe.EndInvoke($job.Async) } catch { }
        $job.Pipe.Dispose()
    }

    if ($pool) {
        foreach ($site in $Sites) {
            if ([string]::IsNullOrWhiteSpace($site)) { continue }

            $resolvedSite = ('' + $site).Trim()
            if ([string]::IsNullOrWhiteSpace($resolvedSite)) { $resolvedSite = '' + $site }

            $postSummary = $null
            $summaryProbe = $null
            try {
                $summaryProbe = [powershell]::Create()
                $summaryProbe.RunspacePool = $pool
                $summaryScript = {
                    param($siteArg)

                    $summarySite = if ($siteArg) { ('' + $siteArg).Trim() } else { '' }
                    if ([string]::IsNullOrWhiteSpace($summarySite)) { return $null }

                    try { return DeviceRepositoryModule\Get-InterfaceSiteCacheSummary -Site $summarySite } catch { return $null }
                }

                $null = $summaryProbe.AddScript($summaryScript).AddArgument($resolvedSite)
                $summaryResult = $summaryProbe.Invoke()
                if ($summaryResult -and $summaryResult.Count -gt 0) {
                    $postSummary = $summaryResult[$summaryResult.Count - 1]
                }
            } catch {
                $postSummary = $null
            } finally {
                if ($summaryProbe) { try { $summaryProbe.Dispose() } catch { } }
            }

            try { Publish-RunspaceCacheTelemetry -Stage 'Warmup:PostJobs' -Site $resolvedSite -Summary $postSummary } catch { }
        }
    }
}

function Get-RunspaceSharedCacheSummary {
    [CmdletBinding()]
    param()

    $pool = $script:PreservedRunspacePool
    if (-not $pool) { return @() }

    $ps = $null
    try {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        $scriptBlock = {
            $store = DeviceRepositoryModule\Get-SharedSiteInterfaceCacheStore
            $summary = [System.Collections.Generic.List[psobject]]::new()
            if ($store -is [System.Collections.IDictionary]) {
                foreach ($key in @($store.Keys)) {
                    $entry = $null
                    try { $entry = DeviceRepositoryModule\Get-SharedSiteInterfaceCacheEntry -SiteKey $key } catch { $entry = $null }
                    $hostCount = 0
                    $totalRows = 0
                    $cacheStatus = ''
                    if ($entry) {
                        if ($entry.PSObject.Properties.Name -contains 'HostMap' -and $entry.HostMap -is [System.Collections.IDictionary]) {
                            try { $hostCount = [int]$entry.HostMap.Count } catch { $hostCount = 0 }
                            foreach ($map in @($entry.HostMap.Values)) {
                                if ($map -is [System.Collections.IDictionary]) {
                                    try { $totalRows += [int]$map.Count } catch { }
                                }
                            }
                        }
                        if ($hostCount -le 0 -and $entry.PSObject.Properties.Name -contains 'HostCount') {
                            try { $hostCount = [int]$entry.HostCount } catch { }
                        }
                        if ($totalRows -le 0 -and $entry.PSObject.Properties.Name -contains 'TotalRows') {
                            try { $totalRows = [int]$entry.TotalRows } catch { }
                        }
                        if ($entry.PSObject.Properties.Name -contains 'CacheStatus') {
                            try { $cacheStatus = '' + $entry.CacheStatus } catch { $cacheStatus = '' }
                        }
                    }
                    $summary.Add([pscustomobject]@{
                            Site        = $key
                            HostCount   = $hostCount
                            TotalRows   = $totalRows
                            CacheStatus = $cacheStatus
                        }) | Out-Null
                }
            }
            return ,$summary.ToArray()
        }
        $results = $ps.AddScript($scriptBlock, $true).Invoke()
        if (-not $results) { return @() }
        return @($results)
    } catch {
        return @()
    } finally {
        if ($ps) { try { $ps.Dispose() } catch { } }
    }
}

function Initialize-RunspaceSharedCacheStore {
    [CmdletBinding()]
    param()

    $pool = $script:PreservedRunspacePool
    if (-not $pool) { return @() }

    $ps = $null
    try {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        $scriptBlock = {
            param($storeKey)

            $store = $null
            try { $store = DeviceRepositoryModule\Get-SharedSiteInterfaceCacheStore } catch { $store = $null }
            if (-not ($store -is [System.Collections.IDictionary])) {
                $store = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase)
            }

            try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetStore($store) } catch { }
            if ($storeKey) {
                try { [System.AppDomain]::CurrentDomain.SetData($storeKey, $store) } catch { }
            }
            try { $script:SharedSiteInterfaceCache = $store } catch { }

            return @{
                EntryCount = if ($store -is [System.Collections.IDictionary]) { $store.Count } else { 0 }
                StoreHash  = if ($store) { [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($store) } else { 0 }
            }
        }
        $storeKeyValue = $null
        try { $storeKeyValue = $script:SharedSiteInterfaceCacheKey } catch { $storeKeyValue = 'StateTrace.Repository.SharedSiteInterfaceCache' }
        $results = $ps.AddScript($scriptBlock, $true).AddArgument($storeKeyValue).Invoke()
        if (-not $results) { return @() }
        return @($results)
    } catch {
        return @()
    } finally {
        if ($ps) { try { $ps.Dispose() } catch { } }
    }
}

function Set-RunspaceSharedCacheEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Entries
    )

    $pool = $script:PreservedRunspacePool
    if (-not $pool) { return }
    if (-not $Entries -or $Entries.Count -eq 0) { return }

    Initialize-RunspaceSharedCacheStore | Out-Null

    $storeKeyValue = $null
    try { $storeKeyValue = $script:SharedSiteInterfaceCacheKey } catch { $storeKeyValue = 'StateTrace.Repository.SharedSiteInterfaceCache' }

    $jobs = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($Entries)) {
        if (-not $entry) { continue }
        $siteKey = ''
        if ($entry.PSObject.Properties.Name -contains 'Site') {
            $siteKey = ('' + $entry.Site).Trim()
        } elseif ($entry.PSObject.Properties.Name -contains 'SiteKey') {
            $siteKey = ('' + $entry.SiteKey).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }
        $payload = $null
        if ($entry.PSObject.Properties.Name -contains 'Entry') {
            $payload = $entry.Entry
        } else {
            $payload = $entry
        }
        if (-not $payload) { continue }

        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        $scriptBlock = {
            param($siteKeyArg, $entryArg, $storeKey)

            $normalizedSite = if ($siteKeyArg) { ('' + $siteKeyArg).Trim() } else { '' }
            if ([string]::IsNullOrWhiteSpace($normalizedSite) -or -not $entryArg) { return }

            try {
                $store = DeviceRepositoryModule\Get-SharedSiteInterfaceCacheStore
                if ($store -isnot [System.Collections.IDictionary]) {
                    $store = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase)
                }
                try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetStore($store) } catch { }
                if ($storeKey) {
                    try { [System.AppDomain]::CurrentDomain.SetData($storeKey, $store) } catch { }
                }
                try { $script:SharedSiteInterfaceCache = $store } catch { }

                DeviceRepositoryModule\Set-SharedSiteInterfaceCacheEntry -SiteKey $normalizedSite -Entry $entryArg | Out-Null
            } catch { }

            try {
                # Ensure the shared store is promoted to the current AppDomain holder.
                $store = DeviceRepositoryModule\Get-SharedSiteInterfaceCacheStore
                if ($store -is [System.Collections.IDictionary]) {
                    try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetStore($store) } catch { }
                    if ($storeKey) {
                        try { [System.AppDomain]::CurrentDomain.SetData($storeKey, $store) } catch { }
                    }
                }
            } catch { }
        }
        $null = $ps.AddScript($scriptBlock, $true).AddArgument($siteKey).AddArgument($payload).AddArgument($storeKeyValue)
        $async = $ps.BeginInvoke()
        $jobs.Add([pscustomobject]@{ Pipe = $ps; Async = $async })
    }

    foreach ($job in $jobs) {
        try { $job.Pipe.EndInvoke($job.Async) } catch { }
        $job.Pipe.Dispose()
    }
}

Export-ModuleMember -Function Invoke-DeviceParseWorker, Invoke-DeviceParsingJobs, Reset-DeviceParseRunspacePool, Invoke-InterfaceSiteCacheWarmup, Publish-RunspaceCacheTelemetry, Get-RunspaceSharedCacheSummary, Set-RunspaceSharedCacheEntries, Initialize-RunspaceSharedCacheStore
