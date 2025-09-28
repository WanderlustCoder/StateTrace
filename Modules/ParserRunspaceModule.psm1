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
        [int]$MaxWorkersPerSite = 1,
        [int]$MaxActiveSites = 0,
        [switch]$Synchronous
    )

    if (-not $DeviceFiles -or $DeviceFiles.Count -eq 0) { return }

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

    $siteQueues = [ordered]@{}
    foreach ($file in $DeviceFiles) {
        $host = Get-HostnameFromPath -PathValue $file
        $siteKey = Get-SiteKeyFromHostname -Hostname $host
        if (-not $siteQueues.Contains($siteKey)) {
            $siteQueues[$siteKey] = New-Object 'System.Collections.Generic.Queue[string]'
        }
        $siteQueues[$siteKey].Enqueue($file)
    }

    $workerScript = {
        param($filePath, $modulesPath, $archiveRoot, $dbPath, [bool]$enableVerbose)
        ParserRunspaceModule\Invoke-DeviceParseWorker -FilePath $filePath -ModulesPath $modulesPath -ArchiveRoot $archiveRoot -DatabasePath $dbPath -EnableVerbose:$enableVerbose
    }

    $active = New-Object 'System.Collections.Generic.List[object]'
    try {
        while ($true) {
            $pending = $false
            foreach ($queue in $siteQueues.Values) {
                if ($queue.Count -gt 0) { $pending = $true; break }
            }
            if (-not $pending -and $active.Count -eq 0) { break }

            $launched = $false
            if ($active.Count -lt $MaxThreads) {
                $activeSites = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($entry in $active) { [void]$activeSites.Add($entry.Site) }

                foreach ($siteKey in $siteQueues.Keys) {
                    $queue = $siteQueues[$siteKey]
                    if ($queue.Count -eq 0) { continue }

                    $perSiteActive = 0
                    foreach ($entry in $active) { if ([System.StringComparer]::OrdinalIgnoreCase.Equals($entry.Site, $siteKey)) { $perSiteActive++ } }
                    if ($MaxWorkersPerSite -gt 0 -and $perSiteActive -ge $MaxWorkersPerSite) { continue }
                    if ($MaxActiveSites -gt 0 -and $perSiteActive -eq 0 -and $activeSites.Count -ge $MaxActiveSites) { continue }

                    $file = $queue.Dequeue()
                    $ps = [powershell]::Create()
                    $ps.RunspacePool = $pool
                    $null = $ps.AddScript($workerScript).AddArgument($file).AddArgument($ModulesPath).AddArgument($ArchiveRoot).AddArgument($DatabasePath).AddArgument($enableVerbose)
                    $async = $ps.BeginInvoke()
                    $active.Add([PSCustomObject]@{ Pipe = $ps; AsyncResult = $async; Site = $siteKey })
                    [void]$activeSites.Add($siteKey)
                    $launched = $true

                    if ($active.Count -ge $MaxThreads) { break }
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
    } finally {
        foreach ($entry in @($active)) {
            try { $entry.Pipe.EndInvoke($entry.AsyncResult) } catch { }
            $entry.Pipe.Dispose()
        }
        $pool.Close()
        $pool.Dispose()
    }
}

Export-ModuleMember -Function Invoke-DeviceParseWorker, Invoke-DeviceParsingJobs



