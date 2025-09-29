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

    Initialize-WorkerModules -ModulesPath $ModulesPath

    try {
        & $writeLog ("Parsing: {0}" -f $FilePath)
        DeviceLogParserModule\Invoke-DeviceLogParsing -FilePath $FilePath -ArchiveRoot $ArchiveRoot -DatabasePath $DatabasePath
        & $writeLog ("Parsing complete: {0}" -f $FilePath)
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
        [switch]$Synchronous
    )

    if (-not $DeviceFiles -or $DeviceFiles.Count -eq 0) { return }

    if ($MinThreads -lt 1) { $MinThreads = 1 }
    if ($JobsPerThread -lt 1) { $JobsPerThread = 1 }
    if ($MaxThreads -lt $MinThreads) { $MaxThreads = $MinThreads }
    $cpuCount = [Math]::Max(1, [Environment]::ProcessorCount)

    $enableVerbose = $false
    try { $enableVerbose = [bool]$Global:StateTraceDebug } catch { $enableVerbose = $false }

    Initialize-WorkerModules -ModulesPath $ModulesPath

    if ($Synchronous -or $MaxThreads -le 1) {
        foreach ($file in $DeviceFiles) {
            Invoke-DeviceParseWorker -FilePath $file -ModulesPath $ModulesPath -ArchiveRoot $ArchiveRoot -DatabasePath $DatabasePath -EnableVerbose:$enableVerbose
        }
        return
    }

    $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $sessionState.ApartmentState = [System.Threading.ApartmentState]::STA
    $sessionState.LanguageMode = [System.Management.Automation.PSLanguageMode]::FullLanguage
    $importList = Get-RunspaceModuleImportList -ModulesPath $ModulesPath
    if ($importList -and $importList.Count -gt 0) { $null = $sessionState.ImportPSModule($importList) }
    $pool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads, $sessionState, $Host)
    try { $pool.ApartmentState = [System.Threading.ApartmentState]::STA } catch { }
    $pool.Open()

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
                    $null = $ps.AddParameter('EnableVerbose', $enableVerbose)
                    $async = $ps.BeginInvoke()
                    $active.Add([PSCustomObject]@{ Pipe = $ps; AsyncResult = $async; Site = $siteKey })
                    [void]$activeSiteSet.Add($siteKey)
                    $launched = $true

                    if ($active.Count -ge $currentThreadLimit) { break }
                }
            }

            $completed = @()
            foreach ($entry in @($active)) {
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
        foreach ($entry in @($active)) {
            try { $entry.Pipe.EndInvoke($entry.AsyncResult) } catch { }
            $entry.Pipe.Dispose()
        }
        $pool.Close()
        $pool.Dispose()

        if ($metricsContext) {
            Finalize-SchedulerMetricsContext -Context $metricsContext
        }
    }
}

Export-ModuleMember -Function Invoke-DeviceParseWorker, Invoke-DeviceParsingJobs



