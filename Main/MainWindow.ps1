Add-Type -AssemblyName PresentationFramework

$scriptDir = $PSScriptRoot

$Global:StateTraceDebug     = $false
$VerbosePreference          = 'SilentlyContinue'
$DebugPreference            = 'SilentlyContinue'
$ErrorActionPreference      = 'Continue'

function Ensure-StateTraceDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }

    $resolvedPath = $Path
    try { $resolvedPath = [System.IO.Path]::GetFullPath($Path) } catch { $resolvedPath = $Path }

    try { [System.IO.Directory]::CreateDirectory($resolvedPath) | Out-Null } catch { }

    return $resolvedPath
}

$startupLogDir = Join-Path $scriptDir '..\Logs\Diagnostics'
try {
    $null = Ensure-StateTraceDirectory -Path $startupLogDir
    $startupLogPath = Join-Path $startupLogDir ("UiStartup-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
} catch { $startupLogPath = $null }
function Write-StartupDiag {
    param([string]$Message)
    if (-not $startupLogPath) { return }
    try {
        $ts = (Get-Date).ToString('o')
        Add-Content -LiteralPath $startupLogPath -Value ("[$ts] {0}" -f $Message) -ErrorAction SilentlyContinue
    } catch { }
}

if (-not (Get-Variable -Name ModulesDirectory -Scope Script -ErrorAction SilentlyContinue)) {
    try {
        $script:ModulesDirectory = (Resolve-Path -LiteralPath (Join-Path $scriptDir '..\Modules')).Path
    } catch {
        $script:ModulesDirectory = Join-Path $scriptDir '..\Modules'
    }
}
if (-not (Get-Variable -Name DeviceLoaderModuleNames -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DeviceLoaderModuleNames = @(
        'DatabaseModule.psm1',
        'DeviceRepositoryModule.psm1',
        'TemplatesModule.psm1',
        'InterfaceModule.psm1',
        'DeviceDetailsModule.psm1'
    )
}
if (-not (Get-Variable -Name DeviceDetailsWarmupQueued -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DeviceDetailsWarmupQueued = $false
}
if (-not (Get-Variable -Name TabVisibilityHandlersAttached -Scope Script -ErrorAction SilentlyContinue)) {
    $script:TabVisibilityHandlersAttached = $false
}
$script:StateTraceSettingsPath = Join-Path $scriptDir '..\Data\StateTraceSettings.json'

if (-not (Get-Variable -Name ParserStatusTimer -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ParserStatusTimer = $null
}
if (-not (Get-Variable -Name CurrentParserJob -Scope Script -ErrorAction SilentlyContinue)) {
    $script:CurrentParserJob = $null
}
if (-not (Get-Variable -Name ParserJobLogPath -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ParserJobLogPath = $null
}
if (-not (Get-Variable -Name FreshnessCache -Scope Script -ErrorAction SilentlyContinue)) {
    $script:FreshnessCache = @{
        Site      = $null
        Info      = $null
        MetricsAt = $null
    }
}
if (-not (Get-Variable -Name ParserJobStartedAt -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ParserJobStartedAt = $null
}
if (-not (Get-Variable -Name ParserPendingSiteFilter -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ParserPendingSiteFilter = $null
}
if (-not (Get-Variable -Name InterfacesLoadAllowed -Scope Global -ErrorAction SilentlyContinue)) {
    $global:InterfacesLoadAllowed = $false
}
if (-not (Get-Variable -Name ProgrammaticHostnameUpdate -Scope Global -ErrorAction SilentlyContinue)) {
    $global:ProgrammaticHostnameUpdate = $false
}

function Publish-UserActionTelemetry {
    param(
        [string]$Action,
        [string]$Site,
        [string]$Hostname,
        [string]$Context
    )
    $payload = @{}
    if ($Action) { $payload['Action'] = $Action }
    if ($Site) { $payload['Site'] = $Site }
    if ($Hostname) { $payload['Hostname'] = $Hostname }
    if ($Context) { $payload['Context'] = $Context }
    $payload['Timestamp'] = (Get-Date).ToString('o')
    $null = Invoke-OptionalCommandSafe -Name 'TelemetryModule\Write-StTelemetryEvent' -Parameters @{
        Name    = 'UserAction'
        Payload = $payload
    }
}

function Load-StateTraceSettings {
    $settings = @{}
    if (Test-Path $script:StateTraceSettingsPath) {
        try {
            $json = Get-Content -LiteralPath $script:StateTraceSettingsPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($json)) {
                $parsed = $json | ConvertFrom-Json
                if ($parsed) {
                    foreach ($prop in $parsed.PSObject.Properties) {
                        $settings[$prop.Name] = $prop.Value
                    }
                }
            }
        } catch {
            $settings = @{}
        }
    }
    $script:StateTraceSettings = $settings
    return $script:StateTraceSettings
}

function Save-StateTraceSettings {
    param([hashtable]$Settings)
    if (-not $Settings) { $Settings = @{} }
    try {
        $json = $Settings | ConvertTo-Json -Depth 5
        $settingsDir = Split-Path -Parent $script:StateTraceSettingsPath
        $null = Ensure-StateTraceDirectory -Path $settingsDir
        $json | Out-File -LiteralPath $script:StateTraceSettingsPath -Encoding utf8
    } catch { }
}

$script:StateTraceSettings = Load-StateTraceSettings
if ($script:StateTraceSettings.ContainsKey('DebugOnNextLaunch') -and $script:StateTraceSettings['DebugOnNextLaunch']) {
    $Global:StateTraceDebug = $true
}

if (-not (Get-Variable -Name DiagWriter -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DiagWriter = $null
}
if (-not (Get-Variable -Name DiagWriterFallbackNotified -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DiagWriterFallbackNotified = $false
}
if (-not (Get-Variable -Name DiagWriterCreatedNotified -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DiagWriterCreatedNotified = $false
}

if (-not ('StateTrace.Diagnostics.AsyncDiagWriter' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading;

namespace StateTrace.Diagnostics
{
    public sealed class AsyncDiagWriter : IDisposable
    {
        private readonly ConcurrentQueue<string> _queue = new ConcurrentQueue<string>();
        private readonly AutoResetEvent _signal = new AutoResetEvent(false);
        private readonly Thread _thread;
        private readonly string _path;
        private volatile bool _disposed;

        public AsyncDiagWriter(string path)
        {
            if (string.IsNullOrWhiteSpace(path))
            {
                throw new ArgumentNullException("path");
            }

            _path = path;
            _thread = new Thread(WriterLoop)
            {
                IsBackground = true,
                Name = "StateTrace-DiagWriter"
            };
            _thread.Start();
        }

        public void Enqueue(string line)
        {
            if (_disposed) { return; }
            if (string.IsNullOrEmpty(line)) { return; }

            _queue.Enqueue(line);
            try { _signal.Set(); } catch { }
        }

        private void WriterLoop()
        {
            List<string> batch = new List<string>(64);
            string item = null;

            while (!_disposed)
            {
                try { _signal.WaitOne(250); } catch { }

                try
                {
                    batch.Clear();
                    while (_queue.TryDequeue(out item))
                    {
                        if (!string.IsNullOrEmpty(item))
                        {
                            batch.Add(item);
                        }

                        if (batch.Count >= 200)
                        {
                            break;
                        }
                    }

                    if (batch.Count > 0)
                    {
                        File.AppendAllLines(_path, batch, Encoding.UTF8);
                    }
                }
                catch
                {
                }
            }
        }

        public void Dispose()
        {
            _disposed = true;
            try { _signal.Set(); } catch { }
            try { _signal.Dispose(); } catch { }
        }
    }
}
'@
}

function Get-DiagWriter {
    if (-not $Global:StateTraceDebug) { return $null }
    if (-not $script:DiagLogPath) { return $null }

    $current = $script:DiagWriter
    if ($current) { return $current }

    try {
        $script:DiagWriter = [StateTrace.Diagnostics.AsyncDiagWriter]::new($script:DiagLogPath)
        if ($script:DiagWriter -and -not $script:DiagWriterCreatedNotified) {
            $script:DiagWriterCreatedNotified = $true
            Write-Verbose "[Write-Diag] AsyncDiagWriter enabled."
        }
    } catch {
        $script:DiagWriter = $null
    }

    return $script:DiagWriter
}

function Write-Diag {
    param([string]$Message)
    if (-not $Global:StateTraceDebug) { return }
    try {
        $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        $line = "[$ts] $Message"
        Write-Verbose $line
        if ($script:DiagLogPath) {
            try {
                $writer = Get-DiagWriter
                if ($writer) {
                    $writer.Enqueue($line)
                } elseif (-not $script:DiagWriterFallbackNotified) {
                    $script:DiagWriterFallbackNotified = $true
                    Write-Verbose "[Write-Diag] AsyncDiagWriter unavailable; skipping file diagnostics."
                }
            } catch { }
        }
    } catch { }
}

if ($Global:StateTraceDebug) {
    try {
        $userDocs = [Environment]::GetFolderPath('MyDocuments')
        $logRoot  = Ensure-StateTraceDirectory -Path (Join-Path $userDocs 'StateTrace\Logs')
        $script:DiagLogPath = Join-Path $logRoot (
            "StateTrace_Debug_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss')
        )
        '--- StateTrace diagnostic log ---' | Out-File -LiteralPath $script:DiagLogPath -Encoding utf8 -Force
        $null = Get-DiagWriter
        Write-Diag ("Logging to: $script:DiagLogPath")
    } catch { }
}

try {
    $ExecutionContext.SessionState.LanguageMode = [System.Management.Automation.PSLanguageMode]::FullLanguage
    Write-Diag ("Host LanguageMode: {0}" -f $ExecutionContext.SessionState.LanguageMode)
} catch {
    Write-Diag ("Host LanguageMode remains: {0}" -f $ExecutionContext.SessionState.LanguageMode)
}

try {
    $defaultRs = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
    if ($null -ne $defaultRs) {
        $defaultRs.SessionStateProxy.LanguageMode = [System.Management.Automation.PSLanguageMode]::FullLanguage
        Write-Diag (
            "Default runspace LanguageMode: {0}" -f $defaultRs.SessionStateProxy.LanguageMode
        )
    }
} catch {
    Write-Diag (
        "Failed to set default runspace LanguageMode; current: {0}" -f ([System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.SessionStateProxy.LanguageMode)
    )
}

try {
    $HostKeywordOK = $false
    try { if ($true) { $HostKeywordOK = $true } } catch { $HostKeywordOK = $false }
    Write-Diag ("Host keyword 'if' ok: {0}" -f $HostKeywordOK)
} catch { }

if (-not ('StateTrace.Threading.PowerShellThreadStartFactory' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
 using System;
 using System.Management.Automation;
 using System.Management.Automation.Runspaces;
 using System.Threading;

namespace StateTrace.Threading
{
    public static class PowerShellThreadStartFactory
    {
        public static ThreadStart Create(ScriptBlock action, PowerShell ps, string host)
        {
            if (action == null)
            {
                throw new ArgumentNullException("action");
            }

            if (ps == null)
            {
                throw new ArgumentNullException("ps");
            }

            return delegate
            {
                var runspace = ps.Runspace;
                var previous = Runspace.DefaultRunspace;
                try
                {
                    if (runspace != null)
                    {
                        var state = runspace.RunspaceStateInfo.State;
                        if (state == RunspaceState.BeforeOpen)
                        {
                            runspace.Open();
                        }

                        Runspace.DefaultRunspace = runspace;
                    }

                    action.Invoke(ps, host);
                }
                finally
                {
                    Runspace.DefaultRunspace = previous;
                }
            };
        }
    }
 }
'@
}

if (-not ('StateTrace.Threading.PowerShellInvokeWithUiCallbackThreadStartFactory' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;

namespace StateTrace.Threading
{
    public static class PowerShellInvokeWithUiCallbackThreadStartFactory
    {
        public static ThreadStart Create(PowerShell ps, SemaphoreSlim semaphore, SynchronizationContext uiContext, Action<object> callback, string tag)
        {
            if (ps == null)
            {
                throw new ArgumentNullException("ps");
            }
            if (uiContext == null)
            {
                throw new ArgumentNullException("uiContext");
            }
            if (callback == null)
            {
                throw new ArgumentNullException("callback");
            }

            return delegate
            {
                bool heldLock = false;

                try
                {
                    if (semaphore != null)
                    {
                        semaphore.Wait();
                        heldLock = true;
                    }

                    var runspace = ps.Runspace;
                    var previous = Runspace.DefaultRunspace;

                    try
                    {
                        if (runspace != null)
                        {
                            var state = runspace.RunspaceStateInfo.State;
                            if (state == RunspaceState.BeforeOpen)
                            {
                                runspace.Open();
                            }

                            Runspace.DefaultRunspace = runspace;
                        }

                        object payload = null;
                        try
                        {
                            Collection<PSObject> results = ps.Invoke();
                            if (results != null && results.Count > 0)
                            {
                                payload = results[0];
                            }
                        }
                        catch (Exception ex)
                        {
                            payload = new ErrorRecord(ex, "PowerShellInvokeFailed", ErrorCategory.NotSpecified, tag);
                        }

                        uiContext.Post(stateObj => callback(stateObj), payload);
                    }
                    finally
                    {
                        Runspace.DefaultRunspace = previous;
                    }
                }
                catch (Exception exOuter)
                {
                    try
                    {
                        var err = new ErrorRecord(exOuter, "PowerShellInvokeThreadStartFailed", ErrorCategory.NotSpecified, tag);
                        uiContext.Post(stateObj => callback(stateObj), err);
                    }
                    catch
                    {
                    }
                }
                finally
                {
                    try { ps.Commands.Clear(); } catch { }
                    try { ps.Dispose(); } catch { }

                    if (heldLock && semaphore != null)
                    {
                        try { semaphore.Release(); } catch { }
                    }
                }
            };
        }
    }
}
'@
}

if ($null -eq $Global:StateTraceDebug) { $Global:StateTraceDebug = $false }

$repoRoot = $null
try {
    $repoRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path
} catch {
    $repoRoot = (Split-Path -Parent $scriptDir)
}

$moduleLoaderPath = Join-Path $repoRoot 'Modules\ModuleLoaderModule.psm1'
try {
    if (-not (Test-Path -LiteralPath $moduleLoaderPath)) {
        throw "Module loader not found at ${moduleLoaderPath}"
    }

    Import-Module -Name $moduleLoaderPath -Force -ErrorAction Stop | Out-Null
    ModuleLoaderModule\Import-StateTraceModulesFromManifest -RepositoryRoot $repoRoot -Force | Out-Null
} catch {
    Write-Error "Failed to load modules from manifest: $($_.Exception.Message)"
    return
}

try {
    $dataDir = Ensure-StateTraceDirectory -Path (Join-Path $scriptDir '..\Data')
} catch {
    Write-Warning ("Failed to ensure Data directory exists: {0}" -f $_.Exception.Message)
}

# Initialize MainWindow.Services with repository root for settings access
try {
    $servicesModulePath = Join-Path $repoRoot 'Modules\MainWindow.Services.psm1'
    if (Test-Path -LiteralPath $servicesModulePath) {
        Import-Module -Name $servicesModulePath -Global -ErrorAction Stop
        MainWindow.Services\Initialize-MainWindowServices -RepositoryRoot $repoRoot | Out-Null
    }
} catch {
    Write-Warning ("Failed to initialize MainWindow.Services: {0}" -f $_.Exception.Message)
}

if (-not (Get-Variable -Name DeviceDetailsRunspaceLock -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DeviceDetailsRunspaceLock = New-Object System.Threading.SemaphoreSlim 1, 1
}
if (-not (Get-Variable -Name DeviceDetailsRunspace -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DeviceDetailsRunspace = $null
}

if (-not (Get-Variable -Name DatabaseImportRunspaceLock -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DatabaseImportRunspaceLock = New-Object System.Threading.SemaphoreSlim 1, 1
}
if (-not (Get-Variable -Name DatabaseImportRunspace -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DatabaseImportRunspace = $null
}
if (-not (Get-Variable -Name DatabaseImportInProgress -Scope Global -ErrorAction SilentlyContinue)) {
    $global:DatabaseImportInProgress = $false
}
if (-not (Get-Variable -Name DatabaseImportRequestId -Scope Global -ErrorAction SilentlyContinue)) {
    $global:DatabaseImportRequestId = 0
}

function Get-DeviceDetailsRunspace {
    if ($script:DeviceDetailsRunspace) {
        try {
            $state = $script:DeviceDetailsRunspace.RunspaceStateInfo.State
            if ($state -eq [System.Management.Automation.Runspaces.RunspaceState]::Opened) {
                $langMode = $null
                try { $langMode = $script:DeviceDetailsRunspace.SessionStateProxy.LanguageMode } catch { $langMode = $null }
                if ($langMode -ne [System.Management.Automation.PSLanguageMode]::FullLanguage) {
                    try { Write-Diag ("Device loader runspace language mode mismatch | Mode={0}" -f $langMode) } catch {}
                    try { $script:DeviceDetailsRunspace.SessionStateProxy.LanguageMode = [System.Management.Automation.PSLanguageMode]::FullLanguage } catch {}
                    try { $langMode = $script:DeviceDetailsRunspace.SessionStateProxy.LanguageMode } catch { $langMode = $null }
                    if ($langMode -ne [System.Management.Automation.PSLanguageMode]::FullLanguage) {
                        try { Write-Diag ("Device loader runspace discarded due to language mode reset failure | Mode={0}" -f $langMode) } catch {}
                        try { $script:DeviceDetailsRunspace.Dispose() } catch {}
                        $script:DeviceDetailsRunspace = $null
                    }
                }
                if ($script:DeviceDetailsRunspace) {
                    return $script:DeviceDetailsRunspace
                }
            }
            if ($state -eq [System.Management.Automation.Runspaces.RunspaceState]::Opening -or
                $state -eq [System.Management.Automation.Runspaces.RunspaceState]::Connecting) {
                $script:DeviceDetailsRunspace.Open()
                return $script:DeviceDetailsRunspace
            }
        } catch {
            try { Write-Diag ("Device loader runspace state check failed | Error={0}" -f $_.Exception.Message) } catch {}
            try { $script:DeviceDetailsRunspace.Dispose() } catch {}
            $script:DeviceDetailsRunspace = $null
        }
    }

    try {
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $iss.LanguageMode = [System.Management.Automation.PSLanguageMode]::FullLanguage
        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
        $rs.ApartmentState = [System.Threading.ApartmentState]::STA
        $rs.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
        $rs.Open()
        try { $rs.SessionStateProxy.LanguageMode = [System.Management.Automation.PSLanguageMode]::FullLanguage } catch {}
        $script:DeviceDetailsRunspace = $rs
        try {
            Write-Diag ("Device loader runspace created | Id={0} | LangMode={1}" -f $rs.Id, $rs.SessionStateProxy.LanguageMode)
        } catch {}
        return $script:DeviceDetailsRunspace
    } catch {
        try { Write-Diag ("Device loader runspace creation failed | Error={0}" -f $_.Exception.Message) } catch {}
        return $null
    }
}

function Get-DatabaseImportRunspace {
    if ($script:DatabaseImportRunspace) {
        try {
            $state = $script:DatabaseImportRunspace.RunspaceStateInfo.State
            if ($state -eq [System.Management.Automation.Runspaces.RunspaceState]::Opened) {
                $langMode = $null
                try { $langMode = $script:DatabaseImportRunspace.SessionStateProxy.LanguageMode } catch { $langMode = $null }
                if ($langMode -ne [System.Management.Automation.PSLanguageMode]::FullLanguage) {
                    try { Write-Diag ("DB import runspace language mode mismatch | Mode={0}" -f $langMode) } catch {}
                    try { $script:DatabaseImportRunspace.SessionStateProxy.LanguageMode = [System.Management.Automation.PSLanguageMode]::FullLanguage } catch {}
                    try { $langMode = $script:DatabaseImportRunspace.SessionStateProxy.LanguageMode } catch { $langMode = $null }
                    if ($langMode -ne [System.Management.Automation.PSLanguageMode]::FullLanguage) {
                        try { Write-Diag ("DB import runspace discarded due to language mode reset failure | Mode={0}" -f $langMode) } catch {}
                        try { $script:DatabaseImportRunspace.Dispose() } catch {}
                        $script:DatabaseImportRunspace = $null
                    }
                }
                if ($script:DatabaseImportRunspace) {
                    return $script:DatabaseImportRunspace
                }
            }
            if ($state -eq [System.Management.Automation.Runspaces.RunspaceState]::Opening -or
                $state -eq [System.Management.Automation.Runspaces.RunspaceState]::Connecting) {
                $script:DatabaseImportRunspace.Open()
                return $script:DatabaseImportRunspace
            }
        } catch {
            try { Write-Diag ("DB import runspace state check failed | Error={0}" -f $_.Exception.Message) } catch {}
            try { $script:DatabaseImportRunspace.Dispose() } catch {}
            $script:DatabaseImportRunspace = $null
        }
    }

    try {
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $iss.LanguageMode = [System.Management.Automation.PSLanguageMode]::FullLanguage
        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
        $rs.ApartmentState = [System.Threading.ApartmentState]::STA
        $rs.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
        $rs.Open()
        try { $rs.SessionStateProxy.LanguageMode = [System.Management.Automation.PSLanguageMode]::FullLanguage } catch {}
        $script:DatabaseImportRunspace = $rs
        try {
            Write-Diag ("DB import runspace created | Id={0} | LangMode={1}" -f $rs.Id, $rs.SessionStateProxy.LanguageMode)
        } catch {}
        return $script:DatabaseImportRunspace
    } catch {
        try { Write-Diag ("DB import runspace creation failed | Error={0}" -f $_.Exception.Message) } catch {}
        return $null
    }
}

function Queue-DeviceDetailsWarmup {
    if ($script:DeviceDetailsWarmupQueued) { return }
    $modulesDirLocal = $script:ModulesDirectory
    if (-not $modulesDirLocal) {
        try {
            $modulesDirLocal = (Resolve-Path -LiteralPath (Join-Path $scriptDir '..\Modules')).Path
        } catch {
            $modulesDirLocal = Join-Path $scriptDir '..\Modules'
        }
    }
    $moduleListLocal = @($script:DeviceLoaderModuleNames)
    $script:DeviceDetailsWarmupQueued = $true

    $warmupAction = {
        param($modulesDirParam, $moduleListParam)
        try {
            $rsWarm = Get-DeviceDetailsRunspace
            if (-not $rsWarm) {
                $script:DeviceDetailsWarmupQueued = $false
                return
            }
            $psWarm = $null
            try {
                $psWarm = [System.Management.Automation.PowerShell]::Create()
                $psWarm.Runspace = $rsWarm
                $warmupScript = @'
param($modulesDir, $moduleList)
if (-not $script:DeviceLoaderModulesLoaded) {
    $modules = @($moduleList)
    foreach ($name in $modules) {
        $modulePath = Join-Path $modulesDir $name
        if (Test-Path -LiteralPath $modulePath) {
            Import-Module -Name $modulePath -Global -ErrorAction Stop
        }
    }
    $script:DeviceLoaderModulesLoaded = $true
}
'@
                [void]$psWarm.AddScript($warmupScript)
                [void]$psWarm.AddArgument($modulesDirParam)
                [void]$psWarm.AddArgument($moduleListParam)
                $null = $psWarm.Invoke()
            } finally {
                if ($psWarm) { $psWarm.Dispose() }
            }
            try { Write-Diag ("Device loader warmup completed") } catch {}
        } catch {
            try { Write-Diag ("Device loader warmup failed | Error={0}" -f $_.Exception.Message) } catch {}
            $script:DeviceDetailsWarmupQueued = $false
        }
    }.GetNewClosure()

    try {
        [System.Windows.Application]::Current.Dispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::ApplicationIdle,
            [System.Action]{
                try {
                    if ($warmupAction) {
                        $null = $warmupAction.Invoke($modulesDirLocal, $moduleListLocal)
                    }
                } catch {
                    try { Write-Diag ("Device loader warmup execution failed | Error={0}" -f $_.Exception.Message) } catch {}
                    $script:DeviceDetailsWarmupQueued = $false
                }
            }
        ) | Out-Null
    } catch {
        try { Write-Diag ("Device loader warmup scheduling failed | Error={0}" -f $_.Exception.Message) } catch {}
        $script:DeviceDetailsWarmupQueued = $false
    }
}

function Update-DeviceInterfaceCacheSnapshot {
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][System.Collections.IEnumerable]$Collection
    )

    $hostKey = ('' + $Hostname).Trim()
    if ([string]::IsNullOrWhiteSpace($hostKey)) { return }
    if (-not (Get-Variable -Name DeviceInterfaceCache -Scope Global -ErrorAction SilentlyContinue)) {
        $global:DeviceInterfaceCache = @{}
    }

    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Collection) {
        if ($null -ne $item) { [void]$list.Add($item) }
    }
    $global:DeviceInterfaceCache[$hostKey] = $list
}

# Ensure a WPF Application exists so theme resources can be merged
try {
    $app = [System.Windows.Application]::Current
    if (-not $app) {
        $app = [System.Windows.Application]::new()
        $app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
    }
    Initialize-StateTraceTheme
    Update-StateTraceThemeResources
} catch {
    Write-Warning ("Theme initialization failed: {0}" -f $_.Exception.Message)
}

Queue-DeviceDetailsWarmup


function Initialize-ThemeSelector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Window]$Window
    )

    $selector = $Window.FindName('ThemeSelector')
    if (-not $selector) { return }

    $themes = Get-AvailableStateTraceThemes
    if (-not $themes) { $themes = @() }

    $selector.DisplayMemberPath = 'Display'
    $selector.SelectedValuePath = 'Name'
    $selector.ItemsSource = $themes

    $currentTheme = Get-StateTraceTheme
    if ($currentTheme) {
        $match = $null
        foreach ($theme in $themes) {
            if ($null -eq $theme) { continue }
            if ($theme -is [System.Management.Automation.PSObject] -and $theme.PSObject.Properties['Name']) {
                if ('' + $theme.PSObject.Properties['Name'].Value -eq $currentTheme) { $match = $theme; break }
            } elseif ($theme -is [System.Collections.IDictionary] -and $theme.Contains('Name')) {
                if ('' + $theme['Name'] -eq $currentTheme) { $match = $theme; break }
            } elseif ($theme -is [string]) {
                if ($theme -eq $currentTheme) { $match = $theme; break }
            }
        }

        if ($match) {
            $selector.SelectedItem = $match
        } else {
            $selector.SelectedValue = $currentTheme
        }
    }

    if (-not $selector.SelectedItem -and $selector.Items.Count -gt 0) {
        $selector.SelectedIndex = 0
    }

    $selector.Add_SelectionChanged({
        param($sender, $args)

        $selectedValue = $sender.SelectedValue
        if (-not $selectedValue -and $sender.SelectedItem) {
            $item = $sender.SelectedItem
            if ($item -is [System.Management.Automation.PSObject] -and $item.PSObject.Properties['Name']) {
                $selectedValue = '' + $item.PSObject.Properties['Name'].Value
            } elseif ($item -is [System.Collections.IDictionary] -and $item.Contains('Name')) {
                $selectedValue = '' + $item['Name']
            } elseif ($item -isnot [string]) {
                $selectedValue = '' + $item
            } else {
                $selectedValue = $item
            }
        }

        if ([string]::IsNullOrWhiteSpace($selectedValue)) { return }

        $resolvedSelection = '' + $selectedValue
        $current = Get-StateTraceTheme
        if ($resolvedSelection -eq $current) { return }

        try {
            Set-StateTraceTheme -Name $resolvedSelection | Out-Null
            Update-StateTraceThemeResources
        } catch {
            [System.Windows.MessageBox]::Show(("Failed to apply theme: {0}" -f $_.Exception.Message), 'Theme Error') | Out-Null
            if ($current) { $sender.SelectedValue = $current }
        }
    })
}
# === BEGIN Load MainWindow.xaml (MainWindow.ps1) ===
$xamlPath = Join-Path $scriptDir 'MainWindow.xaml'
if (-not (Test-Path -LiteralPath $xamlPath)) {
    throw ("Cannot find MainWindow.xaml at {0}" -f $xamlPath)
}

# Load XAML directly from a filestream (fewer allocations than StringReader+XmlTextReader)
$window = $null
$fs = [System.IO.File]::Open($xamlPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
try {
    $window = [Windows.Markup.XamlReader]::Load($fs)
} finally {
    $fs.Dispose()
}

Set-Variable -Name window -Value $window -Scope Global
Initialize-ThemeSelector -Window $window

# === BEGIN Show Commands UI binders (MainWindow.ps1) ===
function Set-ShowCommandsOSVersions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Controls.ComboBox]$Combo,
        [Parameter(Mandatory)][string]$Vendor
    )

    $versions = Get-ShowCommandsVersions -Vendor $Vendor
    $Combo.ItemsSource = $null
    $Combo.Items.Clear()
    $Combo.ItemsSource = $versions
    $Combo.SelectedIndex = if ($Combo.Items.Count -gt 0) { 0 } else { -1 }
}

# Back-compat wrapper if other code calls this name:
function Set-BrocadeOSFromConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Controls.ComboBox]$Dropdown)
    try { Set-ShowCommandsOSVersions -Combo $Dropdown -Vendor 'Brocade' }
    catch { Write-Warning ("Brocade OS populate failed: {0}" -f $_.Exception.Message) }
}

# === BEGIN View initialization helpers (MainWindow.ps1) ===
function Get-OptionalCommandSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    try { return Get-Command -Name $Name -ErrorAction SilentlyContinue } catch { return $null }
}

function Test-OptionalCommandAvailable {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    return (Get-OptionalCommandSafe -Name $Name) -ne $null
}

function Invoke-OptionalCommandSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [hashtable]$Parameters,
        [object[]]$ArgumentList,
        [switch]$RetryWithoutParameters
    )

    $hasParameters = $PSBoundParameters.ContainsKey('Parameters')
    $hasArgumentList = $PSBoundParameters.ContainsKey('ArgumentList')
    if ($hasParameters -and $hasArgumentList) {
        throw "Invoke-OptionalCommandSafe accepts either -Parameters or -ArgumentList, not both."
    }

    $cmd = Get-OptionalCommandSafe -Name $Name
    if (-not $cmd) { return $null }

    try {
        if ($hasParameters) { return & $cmd @Parameters }
        if ($hasArgumentList) { return & $cmd @ArgumentList }
        return & $cmd
    } catch {
        if ($RetryWithoutParameters.IsPresent -and ($hasParameters -or $hasArgumentList)) {
            try { return & $cmd } catch { return $null }
        }
        return $null
    }
}

function Initialize-View {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CommandName,
        [Parameter(Mandatory)][Windows.Window]$Window,
        [Parameter(Mandatory)][string]$ScriptDir
    )

    $viewName = ((($CommandName -replace '^New-','') -replace 'View$',''))
    $cmd = Get-OptionalCommandSafe -Name $CommandName
    if (-not $cmd) {
        Write-Warning ("{0} view module not loaded or {1} unavailable." -f $viewName, $CommandName)
        return
    }

    # Splat only what the command actually supports
    $params = @{}
    if ($cmd.Parameters.ContainsKey('Window')) { $params.Window = $Window }
    if ($cmd.Parameters.ContainsKey('ScriptDir')) { $params.ScriptDir = $ScriptDir }

    try { & $CommandName @params | Out-Null }
    catch { Write-Warning ("Failed to initialize {0} view: {1}" -f $viewName, $_.Exception.Message) }
}

# Initialize all views EXCEPT Compare on the first pass
if (-not $script:ViewsInitialized) {
    $viewsInOrder = @(
        'New-InterfacesView',
        'New-SpanView',
        'New-SearchInterfacesView',
        'New-SummaryView',
        'New-AlertsView',
        # Container views (Plan AF - Tab Consolidation)
        'New-DocumentationContainerView',
        'New-InfrastructureContainerView',
        'New-OperationsContainerView',
        'New-ToolsContainerView'
        # 'Update-CompareView'  # deferred until after Update-DeviceFilter
    )

    # Auto-discover any additional New-*View commands, excluding Compare for now
    # Exclude helper commands that require extra mandatory parameters
    # Exclude views that are now nested inside container tabs (Plan AF)
    $excludeInitially = @(
        'Update-CompareView',
        # Views now nested in DocumentationContainerView
        'New-TemplatesView',
        'New-DocumentationGeneratorView',
        'New-ConfigTemplateView',
        'New-CommandReferenceView',
        # Views now nested in InfrastructureContainerView
        'New-TopologyView',
        'New-CableDocumentationView',
        'New-IPAMView',
        'New-InventoryView',
        # Views now nested in OperationsContainerView
        'New-ChangeManagementView',
        'New-CapacityPlanningView',
        'New-LogAnalysisView',
        # Views now nested in ToolsContainerView
        'New-DecisionTreeView',
        'New-NetworkCalculatorView'
    )
    $discovered = Get-OptionalCommandSafe -Name 'New-*View' | Select-Object -ExpandProperty Name
    if ($discovered) {
        $extra = $discovered | Where-Object { ($viewsInOrder -notcontains $_) -and ($_ -notin $excludeInitially) }
        # Convert to List for efficient appending
        $viewsInOrderList = [System.Collections.Generic.List[string]]::new()
        foreach ($v in $viewsInOrder) { [void]$viewsInOrderList.Add($v) }
        foreach ($v in ($extra | Sort-Object)) { [void]$viewsInOrderList.Add($v) }
        $viewsInOrder = $viewsInOrderList
    }

    foreach ($v in $viewsInOrder) {
        Initialize-View -CommandName $v -Window $window -ScriptDir $scriptDir
    }

    $script:ViewsInitialized = $true
}

# Global flag used to suppress Request-DeviceFilterUpdate while we are programmatically
# modifying the filter dropdowns inside Update-DeviceFilter.  When this flag is
# set to $true, calls to Request-DeviceFilterUpdate will be ignored.  The flag is
# defined on the global scope so it can be accessed by both MainWindow.ps1 and
# FilterStateModule uses this flag to suppress programmatic filter updates.
if (-not $global:ProgrammaticFilterUpdate) {
    $global:ProgrammaticFilterUpdate = $false
}
# === END View initialization helpers (MainWindow.ps1) ===

function Register-TabVisibilityRefreshHandlers {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Windows.Window]$Window)

    if ($script:TabVisibilityHandlersAttached) { return }
    $script:TabVisibilityHandlersAttached = $true

    $wire = {
        param(
            [string]$HostControlName,
            [scriptblock]$OnVisible
        )

        if (-not $HostControlName -or -not $OnVisible) { return }

        $hostControl = $null
        try { $hostControl = $Window.FindName($HostControlName) } catch { $hostControl = $null }
        if (-not $hostControl) { return }

        $handler = {
            param($sender, $e)

            if (-not $sender -or -not $sender.IsVisible) { return }
            if (-not $global:InterfacesLoadAllowed) { return }

            try { & $OnVisible } catch { }
        }.GetNewClosure()

        try { $hostControl.Add_IsVisibleChanged($handler) } catch { }
    }

    & $wire 'SummaryHost'          {
        if (Test-OptionalCommandAvailable -Name 'Update-SummaryAsync') {
            Invoke-OptionalCommandSafe -Name 'Update-SummaryAsync' | Out-Null
        } else {
            Invoke-OptionalCommandSafe -Name 'Update-Summary' | Out-Null
        }
    }
    & $wire 'SearchInterfacesHost' {
        if (Test-OptionalCommandAvailable -Name 'Update-SearchGridAsync') {
            Invoke-OptionalCommandSafe -Name 'Update-SearchGridAsync' | Out-Null
        } else {
            Invoke-OptionalCommandSafe -Name 'Update-SearchGrid' | Out-Null
        }
    }
    & $wire 'AlertsHost'           {
        if (Test-OptionalCommandAvailable -Name 'Update-AlertsAsync') {
            Invoke-OptionalCommandSafe -Name 'Update-AlertsAsync' | Out-Null
        } else {
            Invoke-OptionalCommandSafe -Name 'Update-Alerts' | Out-Null
        }
    }
    & $wire 'SpanHost'             {
        $selected = $null
        try { $selected = Get-SelectedHostname -Window $Window } catch { $selected = $null }
        Invoke-OptionalCommandSafe -Name 'Get-SpanInfo' -ArgumentList @($selected) | Out-Null
    }
}

try { Register-TabVisibilityRefreshHandlers -Window $window } catch { }

# === BEGIN Main window control hooks (MainWindow.ps1) ===

function Set-EnvToggle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Checked
    )
    # Strings by design: downstream reads env flags, not booleans.
    $new = if ($Checked) { 'true' } else { 'false' }
    # Avoid needless writes
    $current = (Get-Item -Path ("Env:\{0}" -f $Name) -ErrorAction SilentlyContinue).Value
    if ($current -ne $new) {
        Set-Item -Path ("Env:\{0}" -f $Name) -Value $new
    }
}

function Get-AvailableSiteNames {
    $dataDir = Join-Path $scriptDir '..\Data'
    if (-not (Test-Path -LiteralPath $dataDir)) { return @() }

    $siteNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    # Preferred layout: Data\<Site>\<Site>.accdb
    try {
        $siteDirs = Get-ChildItem -LiteralPath $dataDir -Directory -ErrorAction SilentlyContinue
        foreach ($dir in @($siteDirs)) {
            $siteName = $dir.Name
            if ([string]::IsNullOrWhiteSpace($siteName)) { continue }
            $dbPath = Join-Path $dir.FullName ("{0}.accdb" -f $siteName)
            if (Test-Path -LiteralPath $dbPath) { [void]$siteNames.Add($siteName) }
        }
    } catch { }

    # Legacy layout: Data\<Site>.accdb (no recursion needed).
    try {
        $rootDbFiles = Get-ChildItem -LiteralPath $dataDir -Filter '*.accdb' -File -ErrorAction SilentlyContinue
        foreach ($file in @($rootDbFiles)) {
            $leaf = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            if ([string]::IsNullOrWhiteSpace($leaf)) { continue }
            if ($leaf -like 'PerfPipeline-*' -or [System.StringComparer]::OrdinalIgnoreCase.Equals($leaf, 'PerfPipeline')) { continue }
            [void]$siteNames.Add($leaf)
        }
    } catch { }

    # Rare fallback: deep nested .accdb files (avoid unless the common paths yielded nothing).
    if ($siteNames.Count -eq 0) {
        try {
            $deepDbFiles = Get-ChildItem -LiteralPath $dataDir -Filter '*.accdb' -File -Recurse -ErrorAction SilentlyContinue
            foreach ($file in @($deepDbFiles)) {
                $leaf = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                if ([string]::IsNullOrWhiteSpace($leaf)) { continue }
                if ($leaf -like 'PerfPipeline-*' -or [System.StringComparer]::OrdinalIgnoreCase.Equals($leaf, 'PerfPipeline')) { continue }
                [void]$siteNames.Add($leaf)
            }
        } catch { }
    }

    return (@($siteNames) | Sort-Object -Unique)
}

function Populate-SiteDropdownWithAvailableSites {
    param(
        [Windows.Window]$Window,
        [string[]]$Sites,
        [string]$PreferredSelection,
        [switch]$PreserveExistingSelection
    )
    if (-not $Window) { return }
    $siteDropdown = $Window.FindName('SiteDropdown')
    if (-not $siteDropdown) { return }
    $sites = $Sites
    if (-not $sites -or $sites.Count -eq 0) {
        $sites = Get-AvailableSiteNames
    }
    if (-not $sites -or $sites.Count -eq 0) { return }

    $previousProgrammaticFilterUpdate = $false
    try { $previousProgrammaticFilterUpdate = [bool]$global:ProgrammaticFilterUpdate } catch { $previousProgrammaticFilterUpdate = $false }
    $global:ProgrammaticFilterUpdate = $true
    try {
    $existingSelection = $null
    if ($PreserveExistingSelection -and $siteDropdown.SelectedItem) {
        $existingSelection = '' + $siteDropdown.SelectedItem
    }

    $items = [System.Collections.Generic.List[string]]::new()
    [void]$items.Add('All Sites')
    foreach ($site in $sites) { [void]$items.Add($site) }
    $siteDropdown.ItemsSource = $items

    $targetSelection = $null
    if (-not [string]::IsNullOrWhiteSpace($PreferredSelection)) {
        $targetSelection = $PreferredSelection
    } elseif (-not [string]::IsNullOrWhiteSpace($existingSelection)) {
        $targetSelection = $existingSelection
    }

    if (-not [string]::IsNullOrWhiteSpace($targetSelection)) {
        $matchIndex = -1
        for ($i = 0; $i -lt $items.Count; $i++) {
            $itemValue = '' + $items[$i]
            if ([System.StringComparer]::OrdinalIgnoreCase.Equals($itemValue, $targetSelection)) {
                $matchIndex = $i
                break
            }
        }
        if ($matchIndex -ge 0) {
            $siteDropdown.SelectedIndex = $matchIndex
        }
    }

    # Preserve any matched selection; only default if nothing is selected.
    if ($siteDropdown.SelectedIndex -lt 0) {
        if ($items.Count -gt 0) {
            $siteDropdown.SelectedIndex = 0
        } else {
            $siteDropdown.SelectedIndex = -1
        }
    }
    } finally {
        $global:ProgrammaticFilterUpdate = $previousProgrammaticFilterUpdate
    }

    try { Update-FreshnessIndicator -Window $Window } catch { }
    try { Update-PipelineHealthIndicator -Window $Window } catch { }
}

function Set-StateTraceDbPath {
    param(
        [string]$Site
    )

    $dataDir = Join-Path $scriptDir '..\Data'
    if (-not (Test-Path -LiteralPath $dataDir)) { return }
    $candidate = $null
    if (-not [string]::IsNullOrWhiteSpace($Site)) {
        $siteDir = Join-Path $dataDir $Site
        $siteDb = Join-Path $siteDir ("{0}.accdb" -f $Site)
        if (Test-Path -LiteralPath $siteDb) { $candidate = $siteDb }
    }
    if (-not $candidate) {
        $firstDir = Get-ChildItem -LiteralPath $dataDir -Directory | Select-Object -First 1
        if ($firstDir) {
            $siteDb = Join-Path $firstDir.FullName ("{0}.accdb" -f $firstDir.Name)
            if (Test-Path -LiteralPath $siteDb) { $candidate = $siteDb }
        }
    }
    if ($candidate) {
        $global:StateTraceDb = $candidate
        $env:StateTraceDbPath = $candidate
    }
}

function Get-SelectedSiteFilterValue {
    param([Windows.Window]$Window)
    if (-not $Window) { return $null }
    $siteDropdown = $Window.FindName('SiteDropdown')
    if (-not $siteDropdown) { return $null }
    $selection = $null
    try { $selection = '' + $siteDropdown.SelectedItem } catch { $selection = $null }
    if ([string]::IsNullOrWhiteSpace($selection)) {
        try { $selection = '' + $siteDropdown.Text } catch { $selection = $null }
    }
    if ([string]::IsNullOrWhiteSpace($selection) -or $selection -eq 'All Sites') { return $null }
    return $selection
}

function Get-SelectedHostname {
    param([Windows.Window]$Window)
    if (-not $Window) { return $null }
    $dd = $Window.FindName('HostnameDropdown')
    if (-not $dd) { return $null }
    $selection = $null
    try { $selection = '' + $dd.SelectedItem } catch { $selection = $null }
    if ([string]::IsNullOrWhiteSpace($selection)) {
        try { $selection = '' + $dd.Text } catch { $selection = $null }
    }
    if ([string]::IsNullOrWhiteSpace($selection)) { return $null }
    return $selection
}

function ConvertTo-PortPsObjectLocal {
    param(
        $Row,
        [string]$Hostname
    )

    if ($null -eq $Row) { return $null }

    $clone = [pscustomobject]@{}
    try {
        if ($Row -is [System.Data.DataRow] -and $Row.Table -and $Row.Table.Columns) {
            foreach ($col in $Row.Table.Columns) {
                $clone | Add-Member -NotePropertyName $col.ColumnName -NotePropertyValue $Row[$col.ColumnName] -Force
            }
        } elseif ($Row -is [System.Data.DataRowView] -and $Row.Row -and $Row.Row.Table) {
            foreach ($col in $Row.Row.Table.Columns) {
                $clone | Add-Member -NotePropertyName $col.ColumnName -NotePropertyValue $Row[$col.ColumnName] -Force
            }
        } elseif ($Row -is [psobject]) {
            foreach ($prop in $Row.PSObject.Properties) {
                $clone | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
            }
        } elseif ($Row -is [System.Collections.IDictionary]) {
            foreach ($key in $Row.Keys) {
                $clone | Add-Member -NotePropertyName $key -NotePropertyValue $Row[$key] -Force
            }
        }
    } catch { }

    $hostnameProp = $clone.PSObject.Properties['Hostname']
    if ($hostnameProp) {
        if ([string]::IsNullOrWhiteSpace(('' + $hostnameProp.Value))) {
            $hostnameProp.Value = $Hostname
        }
    } elseif ($Hostname) {
        $clone | Add-Member -NotePropertyName Hostname -NotePropertyValue $Hostname -Force
    }

    if (-not $clone.PSObject.Properties['IsSelected']) {
        $clone | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -Force
    }

    return $clone
}

function Convert-InterfaceCollectionForHost {
    param(
        $Collection,
        [string]$Hostname
    )
    if (-not $Collection) { return $Collection }

    $needsConversion = $false
    try {
        $first = $null
        foreach ($item in $Collection) { $first = $item; break }
        if ($first -is [System.Data.DataRow] -or $first -is [System.Data.DataRowView]) {
            $needsConversion = $true
        }
    } catch { $needsConversion = $false }

    if (-not $needsConversion) { return $Collection }

    $converted = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    foreach ($item in $Collection) {
        $clone = ConvertTo-PortPsObjectLocal -Row $item -Hostname $Hostname
        if ($null -ne $clone) { $converted.Add($clone) | Out-Null }
    }
    return $converted
}

function Initialize-FilterMetadataAtStartup {
    param(
        [Windows.Window]$Window,
        [object[]]$LocationEntries
    )
    if (-not $Window) { return }

    try {
        if (-not (Get-Module -Name DeviceCatalogModule)) {
            $modPath = Join-Path $scriptDir '..\\Modules\\DeviceCatalogModule.psm1'
            if (Test-Path -LiteralPath $modPath) {
                Import-Module -Name $modPath -Global -ErrorAction SilentlyContinue
            } else {
                Import-Module DeviceCatalogModule -ErrorAction SilentlyContinue
            }
        }
    } catch {}

    $locationEntries = @()
    try {
        if ($LocationEntries -and $LocationEntries.Count -gt 0) {
            $locationEntries = $LocationEntries
        }
    } catch { $locationEntries = @() }
    if (-not $locationEntries -or $locationEntries.Count -eq 0) {
        try { $locationEntries = DeviceCatalogModule\Get-DeviceLocationEntries } catch { $locationEntries = @() }
    }
    try { $global:DeviceLocationEntries = $locationEntries } catch { }

    try {
        FilterStateModule\Initialize-DeviceFilters -Window $Window -Hostnames @() -LocationEntries $locationEntries
        $hostDD = $Window.FindName('HostnameDropdown')
        if ($hostDD) {
            $global:ProgrammaticHostnameUpdate = $true
            try {
                $hostDD.ItemsSource = @()
                $hostDD.SelectedIndex = -1
            } finally {
                $global:ProgrammaticHostnameUpdate = $false
            }
        }
    } catch {}
    try { Update-DeviceFilter } catch {}
}

function Get-ParserStatusControl {
    param([Windows.Window]$Window)
    if (-not $Window) { return $null }
    try { return $Window.FindName('ParserStatusText') } catch { return $null }
}

function Ensure-ParserStatusTimer {
    param([Windows.Window]$Window)
    if ($script:ParserStatusTimer) { return }
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(1500)
    $timer.add_Tick({
        try {
            $target = $global:window
            if ($target) {
                Update-ParserStatusIndicator -Window $target
            }
        } catch { }
    })
    $script:ParserStatusTimer = $timer
}

function Set-ParserStatusWithColor {
    param(
        [System.Windows.Controls.Label]$Indicator,
        [string]$Text,
        [ValidateSet('Idle','Running','Success','Error')]
        [string]$State = 'Idle'
    )
    if (-not $Indicator) { return }
    $Indicator.Content = $Text
    $themeKey = switch ($State) {
        'Running' { 'Theme.Text.Warning' }
        'Success' { 'Theme.Text.Success' }
        'Error'   { 'Theme.Text.Error' }
        default   { 'Theme.Toolbar.Text' }
    }
    $Indicator.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, $themeKey)
}

function Update-ParserStatusIndicator {
    param([Windows.Window]$Window)
    $indicator = Get-ParserStatusControl -Window $Window
    if (-not $indicator) { return }

    if (-not $script:CurrentParserJob) {
        Set-ParserStatusWithColor -Indicator $indicator -Text 'Parser idle' -State Idle
        Set-ParserDetailText -Window $Window -Text ''
        if ($script:ParserStatusTimer) { $script:ParserStatusTimer.Stop() }
        return
    }

    $state = $script:CurrentParserJob.State
    if ($state -eq 'Running' -or $state -eq 'NotStarted') {
        $started = $null
        try { if ($script:ParserJobStartedAt) { $started = $script:ParserJobStartedAt.ToString('HH:mm:ss') } } catch { }
        if ($started) {
            Set-ParserStatusWithColor -Indicator $indicator -Text "Parsing in progress (started $started)" -State Running
        } else {
            Set-ParserStatusWithColor -Indicator $indicator -Text 'Parsing in progress...' -State Running
        }
        $tail = Get-ParserLogTailText -Path $script:ParserJobLogPath
        if ($tail) {
            Set-ParserDetailText -Window $Window -Text ("Last log: {0}" -f $tail)
        } else {
            Set-ParserDetailText -Window $Window -Text ''
        }
        return
    }

    $logPath = $script:ParserJobLogPath
    try { Receive-Job $script:CurrentParserJob | Out-Null } catch { }
    try { Remove-Job $script:CurrentParserJob -Force -ErrorAction SilentlyContinue } catch { }
    $script:CurrentParserJob = $null
    if ($state -eq 'Completed') {
        $stamp = (Get-Date).ToString('HH:mm:ss')
        if ($logPath) {
            Set-ParserStatusWithColor -Indicator $indicator -Text ("Parsing finished at {0} (log: {1})" -f $stamp, $logPath) -State Success
        } else {
            Set-ParserStatusWithColor -Indicator $indicator -Text "Parsing finished at $stamp" -State Success
        }
        $refreshFilter = $script:ParserPendingSiteFilter
        $script:ParserPendingSiteFilter = $null
        try { Invoke-DatabaseImport -Window $Window -SiteFilterOverride $refreshFilter -SkipTelemetry } catch { }
    } else {
        if ($logPath) {
            Set-ParserStatusWithColor -Indicator $indicator -Text ("Parsing {0}. See {1}" -f $state.ToLower(), $logPath) -State Error
        } else {
            Set-ParserStatusWithColor -Indicator $indicator -Text ("Parsing {0}" -f $state.ToLower()) -State Error
        }
        $script:ParserPendingSiteFilter = $null
    }

    $script:ParserJobLogPath = $null
    Set-ParserDetailText -Window $Window -Text ''
    if ($script:ParserStatusTimer) { $script:ParserStatusTimer.Stop() }
}

function Get-SiteIngestionInfo {
    param(
        [string]$Site,
        [string]$Hostname
    )
    if ([string]::IsNullOrWhiteSpace($Site)) { return $null }
    $historyPath = Join-Path $scriptDir "..\Data\IngestionHistory\$Site.json"
    if (-not (Test-Path -LiteralPath $historyPath)) { return $null }
    $entries = $null
    try { $entries = Get-Content -LiteralPath $historyPath -Raw | ConvertFrom-Json } catch { $entries = $null }
    if (-not $entries) { return $null }

    # Filter by hostname if provided, otherwise get the most recent across all hosts
    $candidates = $entries | Where-Object { $_.LastIngestedUtc }
    if (-not [string]::IsNullOrWhiteSpace($Hostname)) {
        $hostMatch = $candidates | Where-Object { $_.Hostname -eq $Hostname -or $_.ActualHostname -eq $Hostname }
        if ($hostMatch) { $candidates = $hostMatch }
    }
    $latest = $candidates | Sort-Object { $_.LastIngestedUtc } -Descending | Select-Object -First 1
    if (-not $latest) { return $null }
    $ingestedUtc = $null
    try { $ingestedUtc = [datetime]::Parse($latest.LastIngestedUtc).ToUniversalTime() } catch { $ingestedUtc = $null }
    if (-not $ingestedUtc) { return $null }
    $source = $latest.SiteCacheProvider
    if (-not $source -and $latest.CacheStatus) { $source = $latest.CacheStatus }
    if (-not $source -and $latest.Source) { $source = $latest.Source }
    if (-not $source) { $source = 'History' }
    return [pscustomobject]@{
        Site            = $Site
        Hostname        = $latest.Hostname
        LastIngestedUtc = $ingestedUtc
        Source          = $source
        HistoryPath     = $historyPath
    }
}

function Get-SiteCacheProviderFromMetrics {
    param([string]$Site)
    if ([string]::IsNullOrWhiteSpace($Site)) { return $null }
    $logDir = Join-Path $scriptDir '..\Logs\IngestionMetrics'
    if (-not (Test-Path -LiteralPath $logDir)) { return $null }
    $latest = Get-ChildItem -LiteralPath $logDir -Filter '*.json' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { return $null }
    if ($script:FreshnessCache.Site -eq $Site -and $script:FreshnessCache.MetricsAt -eq $latest.LastWriteTime) {
        return $script:FreshnessCache.Info
    }
    $telemetry = $null
    try { $telemetry = Get-Content -LiteralPath $latest.FullName -Raw | ConvertFrom-Json -ErrorAction Stop } catch { $telemetry = $null }
    if (-not $telemetry) {
        # Fallback to newline-delimited JSON
        $lines = Get-Content -LiteralPath $latest.FullName -ErrorAction SilentlyContinue
        $parsed = [System.Collections.Generic.List[object]]::new()
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { [void]$parsed.Add(($line | ConvertFrom-Json -ErrorAction Stop)) } catch { }
        }
        if ($parsed.Count -gt 0) { $telemetry = $parsed }
    }
    if (-not $telemetry) { return $null }

    $candidateEvents = $telemetry | Where-Object { $_.EventName -in @('DatabaseWriteBreakdown','InterfaceSiteCacheMetrics','InterfaceSyncTiming','InterfaceSiteCacheRunspaceState') -and $_.Site -eq $Site }
    if (-not $candidateEvents) { return $null }

    $best = $null
    foreach ($entry in $candidateEvents) {
        $provider = $null
        $reason = $null
        $status = $null
        if ($entry.PSObject.Properties.Name -contains 'SiteCacheProvider' -and $entry.SiteCacheProvider) { $provider = $entry.SiteCacheProvider }
        if ($entry.PSObject.Properties.Name -contains 'SiteCacheProviderReason' -and $entry.SiteCacheProviderReason) { $reason = $entry.SiteCacheProviderReason }
        if ($entry.PSObject.Properties.Name -contains 'CacheStatus' -and $entry.CacheStatus) { $status = $entry.CacheStatus }
        if (-not $provider -and $status) { $provider = $status }
        if (-not $provider -and $reason) { $provider = $reason }

        $timestamp = $null
        if ($entry.PSObject.Properties.Name -contains 'Timestamp' -and $entry.Timestamp) {
            try { $timestamp = [datetime]::Parse($entry.Timestamp).ToLocalTime() } catch { $timestamp = $null }
        }
        $candidate = [pscustomobject]@{
            Provider   = if ($provider) { $provider } else { 'Unknown' }
            Reason     = $reason
            CacheStatus= $status
            EventName  = $entry.EventName
            Timestamp  = $timestamp
        }
        if (-not $best -or ($timestamp -and $best.Timestamp -lt $timestamp)) {
            $best = $candidate
        }
    }

    if (-not $best) { return $null }
    $info = [pscustomobject]@{
        Provider   = $best.Provider
        Reason     = $best.Reason
        EventName  = $best.EventName
        Timestamp  = $best.Timestamp
        MetricsLog = $latest.FullName
    }
    $script:FreshnessCache = @{
        Site      = $Site
        Info      = $info
        MetricsAt = $latest.LastWriteTime
    }
    return $info
}

function Update-FreshnessIndicator {
    param([Windows.Window]$Window)
    $label = $Window.FindName('FreshnessLabel')
    $indicator = $Window.FindName('FreshnessIndicator')
    if (-not $label) { return }

    # Helper to set indicator color
    $setIndicatorColor = {
        param([string]$Color)
        if ($indicator) {
            $brush = switch ($Color) {
                'Green'  { [System.Windows.Media.Brushes]::LimeGreen }
                'Yellow' { [System.Windows.Media.Brushes]::Gold }
                'Orange' { [System.Windows.Media.Brushes]::Orange }
                'Red'    { [System.Windows.Media.Brushes]::OrangeRed }
                default  { [System.Windows.Media.Brushes]::Gray }
            }
            $indicator.Fill = $brush
        }
    }

    $site = Get-SelectedSiteFilterValue -Window $Window
    $hostname = Get-SelectedHostname -Window $Window
    if (-not $site) {
        $label.Content = 'Freshness: select a site'
        & $setIndicatorColor 'Gray'
        if ($indicator) { $indicator.ToolTip = 'Select a site to see data freshness' }
        return
    }

    $info = Get-SiteIngestionInfo -Site $site -Hostname $hostname
    if (-not $info) {
        $targetDesc = if ($hostname) { "$hostname ($site)" } else { $site }
        $label.Content = "Freshness: no history for $targetDesc"
        $label.ToolTip = "No ingestion history found under Data\\IngestionHistory\\$site.json"
        & $setIndicatorColor 'Gray'
        if ($indicator) { $indicator.ToolTip = 'No ingestion history available' }
        return
    }

    $localTime = $info.LastIngestedUtc.ToLocalTime()
    $age = [datetime]::UtcNow - $info.LastIngestedUtc
    $ageText = if ($age.TotalMinutes -lt 1) {
        '<1 min ago'
    } elseif ($age.TotalHours -lt 1) {
        ('{0:F0} min ago' -f [math]::Floor($age.TotalMinutes))
    } elseif ($age.TotalDays -lt 1) {
        ('{0:F1} h ago' -f $age.TotalHours)
    } else {
        ('{0:F1} d ago' -f $age.TotalDays)
    }

    # Set indicator color based on age thresholds
    # Green: <24h, Yellow: 24-48h, Orange: 48h-7d, Red: >7d
    $indicatorColor = if ($age.TotalHours -lt 24) {
        'Green'
    } elseif ($age.TotalHours -lt 48) {
        'Yellow'
    } elseif ($age.TotalDays -lt 7) {
        'Orange'
    } else {
        'Red'
    }
    & $setIndicatorColor $indicatorColor

    $providerInfo = Get-SiteCacheProviderFromMetrics -Site $site
    $providerText = if ($providerInfo) {
        if ($providerInfo.Reason) { "{0} ({1})" -f $providerInfo.Provider, $providerInfo.Reason } else { $providerInfo.Provider }
    } else {
        $info.Source
    }
    # Show hostname-specific info when a device is selected, otherwise show site-level
    $targetLabel = if ($info.Hostname -and $hostname) { $info.Hostname } else { $site }
    $label.Content = "Freshness: $targetLabel @ $($localTime.ToString('g')) ($ageText, source $providerText)"

    $tooltipParts = [System.Collections.Generic.List[string]]::new()
    if ($info.Hostname -and $hostname) {
        $tooltipParts.Add("Device: $($info.Hostname)") | Out-Null
    }
    $tooltipParts.Add("Site: $site") | Out-Null
    $tooltipParts.Add("Ingestion history: $($info.HistoryPath)") | Out-Null
    if ($providerInfo) {
        $tooltipParts.Add("Metrics: $($providerInfo.MetricsLog)") | Out-Null
        $tooltipParts.Add("Provider: $($providerInfo.Provider)") | Out-Null
        if ($providerInfo.Reason) { $tooltipParts.Add("Reason: $($providerInfo.Reason)") | Out-Null }
        if ($providerInfo.Timestamp) { $tooltipParts.Add("Telemetry at: $($providerInfo.Timestamp.ToString('g'))") | Out-Null }
    }
    $label.ToolTip = [string]::Join("`n", $tooltipParts)

    # Update indicator tooltip with freshness status
    if ($indicator) {
        $statusText = switch ($indicatorColor) {
            'Green'  { 'Fresh (< 24 hours old)' }
            'Yellow' { 'Warning (24-48 hours old)' }
            'Orange' { 'Stale (2-7 days old)' }
            'Red'    { 'Very stale (> 7 days old)' }
            default  { 'Unknown' }
        }
        $indicator.ToolTip = "$statusText`nLast ingest: $($localTime.ToString('g'))"
    }
}

function Get-LatestPipelineLogPath {
    <#
    .SYNOPSIS
    Returns the path to the latest pipeline log file.
    #>
    $repoRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path
    $logsDir = Join-Path $repoRoot 'Logs\Verification'

    if (-not (Test-Path -LiteralPath $logsDir)) {
        # Fallback to IngestionMetrics if Verification doesn't exist
        $logsDir = Join-Path $repoRoot 'Logs\IngestionMetrics'
    }

    if (-not (Test-Path -LiteralPath $logsDir)) {
        return $null
    }

    # Find the most recent log file
    $logFiles = Get-ChildItem -LiteralPath $logsDir -Filter '*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($logFiles) {
        return $logFiles.FullName
    }

    # If no .log files, try .json files
    $jsonFiles = Get-ChildItem -LiteralPath $logsDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($jsonFiles) {
        return $jsonFiles.FullName
    }

    return $null
}

function Update-PipelineHealthIndicator {
    <#
    .SYNOPSIS
    Updates the pipeline health label with the last run status.
    #>
    param([Windows.Window]$Window)

    $healthLabel = $Window.FindName('PipelineHealthLabel')
    $viewLogButton = $Window.FindName('ViewPipelineLogButton')
    if (-not $healthLabel) { return }

    $repoRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path
    $metricsDir = Join-Path $repoRoot 'Logs\IngestionMetrics'

    # Find the latest metrics file
    $latestMetrics = $null
    if (Test-Path -LiteralPath $metricsDir) {
        $latestMetrics = Get-ChildItem -LiteralPath $metricsDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch 'QueueDelaySummary|WarmRunTelemetry|DiffHotspots' } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    }

    if (-not $latestMetrics) {
        $healthLabel.Content = 'Pipeline: no runs recorded'
        $healthLabel.ToolTip = 'Run Tools\Invoke-StateTracePipeline.ps1 to ingest logs'
        if ($viewLogButton) { $viewLogButton.Visibility = 'Collapsed' }
        return
    }

    $lastRunTime = $latestMetrics.LastWriteTime
    $age = [datetime]::Now - $lastRunTime
    $ageText = if ($age.TotalMinutes -lt 1) {
        '<1 min ago'
    } elseif ($age.TotalHours -lt 1) {
        ('{0:F0} min ago' -f [math]::Floor($age.TotalMinutes))
    } elseif ($age.TotalDays -lt 1) {
        ('{0:F1} h ago' -f $age.TotalHours)
    } else {
        ('{0:F1} d ago' -f $age.TotalDays)
    }

    $healthLabel.Content = "Pipeline: last run $ageText"
    $healthLabel.ToolTip = "Last pipeline run: $($lastRunTime.ToString('g'))`nMetrics: $($latestMetrics.Name)"

    # Show the View Log button if we have a log
    $logPath = Get-LatestPipelineLogPath
    if ($viewLogButton) {
        $viewLogButton.Visibility = if ($logPath) { 'Visible' } else { 'Collapsed' }
    }
}

function Set-ParserDetailText {
    param([Windows.Window]$Window, [string]$Text)
    if (-not $Window) { return }
    $detailLabel = $Window.FindName('ParserDetailText')
    if (-not $detailLabel) { return }
    $detailLabel.Content = if ($Text) { $Text } else { '' }
}

function Get-ParserLogTailText {
    param(
        [string]$Path,
        [int]$TailCount = 25
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $lines = $null
    try { $lines = Get-Content -LiteralPath $Path -Tail $TailCount -ErrorAction Stop } catch { return $null }
    if (-not $lines) { return $null }

    $lines = $lines | ForEach-Object { ($_ -replace [char]0, '') }
    $candidate = ($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1)
    if ([string]::IsNullOrWhiteSpace($candidate)) { return $null }

    $candidate = $candidate.Trim()
    if ($candidate.Length -gt 140) {
        $candidate = $candidate.Substring(0,137) + '...'
    }
    return $candidate
}

function Reset-ParserCachesForRefresh {
    [CmdletBinding()]
    param([string]$SiteFilter)

    try { Write-Diag ("Parser refresh: clearing caches | SiteFilter={0}" -f $SiteFilter) } catch {}

    $repoRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path

    $historyDir = Join-Path $repoRoot 'Data\IngestionHistory'
    if (Test-Path -LiteralPath $historyDir) {
        $historyTargets = @()
        try { $historyTargets = Get-ChildItem -LiteralPath $historyDir -File -ErrorAction SilentlyContinue } catch { $historyTargets = @() }
        foreach ($item in @($historyTargets)) {
            try { Remove-Item -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue } catch {}
        }
        try { Write-Diag ("Parser refresh: cleared ingestion history files ({0})" -f $historyTargets.Count) } catch {}
    }

    # Clear site databases so subsequent scans rebuild from logs when force reload is requested.
    $sitesToClear = @()
    if (-not [string]::IsNullOrWhiteSpace($SiteFilter)) {
        $sitesToClear = @($SiteFilter)
    } else {
        $dataRoot = Join-Path $repoRoot 'Data'
        if (Test-Path -LiteralPath $dataRoot) {
            try {
                $dirs = Get-ChildItem -LiteralPath $dataRoot -Directory -ErrorAction SilentlyContinue
                $sitesToClear = @($dirs | ForEach-Object { $_.Name })
            } catch { $sitesToClear = @() }
        }
    }
    foreach ($site in @($sitesToClear)) {
        if ([string]::IsNullOrWhiteSpace($site)) { continue }
        $siteDir = Join-Path $repoRoot ("Data\\{0}" -f $site)
        if (Test-Path -LiteralPath $siteDir) {
            try { Remove-Item -LiteralPath $siteDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
    try { Write-Diag ("Parser refresh: cleared site directories for {0}" -f ([string]::Join(',', $sitesToClear))) } catch {}

    $cacheModulePath = Join-Path $script:ModulesDirectory 'DeviceRepository.Cache.psm1'
    if (Test-Path -LiteralPath $cacheModulePath) {
        try { Import-Module -Name $cacheModulePath -Global -ErrorAction SilentlyContinue } catch { }
    }

    try { DeviceRepository.Cache\Clear-SharedSiteInterfaceCache -Reason 'UIForceReparse' } catch { }
    try { DeviceRepositoryModule\Clear-SiteInterfaceCache -Reason 'UIForceReparse' } catch { }
    try { ParserPersistenceModule\Clear-SiteExistingRowCache } catch { }

    try { Write-Diag "Parser refresh: caches cleared" } catch {}
    $global:InterfacesLoadAllowed = $false
}

function Start-ParserBackgroundJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Windows.Window]$Window,
        [bool]$IncludeArchive,
        [bool]$IncludeHistorical,
        [string]$SiteFilter,
        [bool]$ForceReload
    )

    $global:InterfacesLoadAllowed = $true

    if ($script:CurrentParserJob -and ($script:CurrentParserJob.State -in @('Running','NotStarted'))) {
        [System.Windows.MessageBox]::Show('Parsing is already running. Monitor the parser status indicator for progress.', 'Parsing in progress')
        return
    }

    $repoRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path
    $logDir = Join-Path $repoRoot 'Logs\UI'
    $null = Ensure-StateTraceDirectory -Path $logDir
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logPath = Join-Path $logDir ("ParserJob-{0}.log" -f $timestamp)
    try { Write-StartupDiag ("Starting parser job (RepoRoot={0}, LogPath={1})" -f $repoRoot, $logPath) } catch { }
    try {
        $queuedHeader = "Parser job queued at {0:o} (IncludeArchive={1}, IncludeHistorical={2}, ForceReload={3})" -f (Get-Date), $IncludeArchive, $IncludeHistorical, $ForceReload
        Set-Content -LiteralPath $logPath -Value $queuedHeader -Encoding UTF8 -ErrorAction Stop
    } catch {
        try { Write-StartupDiag ("Failed to initialize parser job log at {0}: {1}" -f $logPath, $_.Exception.Message) } catch { }
    }

    $job = $null
    try {
        $job = Start-Job -Name ("StateTraceParser-{0}" -f $timestamp) -ArgumentList @(
            $repoRoot,
            $IncludeArchive,
            $IncludeHistorical,
            $logPath,
            $ForceReload
        ) -ScriptBlock {
        param($RepoRoot,$IncludeArchive,$IncludeHistorical,$LogPath,$ForceReload)
        Push-Location $RepoRoot
        try {
            $logParent = Split-Path -Parent $LogPath
            if ($logParent) {
                try { [System.IO.Directory]::CreateDirectory($logParent) | Out-Null } catch { }
            }
            $pipeline = Join-Path $RepoRoot 'Tools\Invoke-StateTracePipeline.ps1'
            $env:IncludeArchive    = if ($IncludeArchive)    { '1' } else { '0' }
            $env:IncludeHistorical = if ($IncludeHistorical){ '1' } else { '0' }
            if ($ForceReload) { $env:STATETRACE_SHARED_CACHE_SNAPSHOT = '' }
            $ErrorActionPreference = 'Stop'
            $header = "Parser job started at {0:o} (IncludeArchive={1}, IncludeHistorical={2})" -f (Get-Date), $IncludeArchive, $IncludeHistorical
            Set-Content -LiteralPath $LogPath -Value $header -Encoding UTF8
            if (Test-Path -LiteralPath $pipeline) {
                $pipelineParams = @{
                    VerboseParsing              = $true
                    ResetExtractedLogs          = $true
                    VerifyTelemetryCompleteness = $true
                    FailOnTelemetryMissing      = $false
                    FailOnSchedulerFairness     = $true
                    SkipPortDiversityGuard      = $true
                    QuickMode                   = $true
                    SkipTests                   = $true
                }
                if ($ForceReload) {
                    $pipelineParams.DisableSharedCacheSnapshot = $true
                    $pipelineParams.DisablePreserveRunspace  = $true
                    $pipelineParams.DisableSkipSiteCacheUpdate = $true
                }
                & $pipeline @pipelineParams -ErrorAction Stop *>&1 |
                    Out-File -FilePath $LogPath -Append -Encoding UTF8
            } else {
                $moduleLoaderPath = Join-Path $RepoRoot 'Modules\ModuleLoaderModule.psm1'
                if (Test-Path -LiteralPath $moduleLoaderPath) {
                    try {
                        Import-Module -Name $moduleLoaderPath -Force -ErrorAction Stop | Out-Null
                        ModuleLoaderModule\Import-StateTraceModulesFromManifest -RepositoryRoot $RepoRoot -Exclude @('ParserWorker.psm1') -Force | Out-Null
                    } catch {
                        $msg = "Failed to import module manifest modules: {0}" -f $_.Exception.Message
                        try { Add-Content -LiteralPath $LogPath -Value $msg -Encoding UTF8 } catch { }
                        try { Write-Warning $msg } catch { }

                        $fallbackModules = @(
                            (Join-Path $RepoRoot 'Modules\LogIngestionModule.psm1'),
                            (Join-Path $RepoRoot 'Modules\ParserRunspaceModule.psm1')
                        )
                        foreach ($fallbackModulePath in $fallbackModules) {
                            if (-not (Test-Path -LiteralPath $fallbackModulePath)) { continue }
                            try {
                                Import-Module -Name $fallbackModulePath -Force -Global -ErrorAction Stop | Out-Null
                            } catch {
                                $fallbackMsg = "Failed to import fallback module at {0}: {1}" -f $fallbackModulePath, $_.Exception.Message
                                try { Add-Content -LiteralPath $LogPath -Value $fallbackMsg -Encoding UTF8 } catch { }
                                try { Write-Warning $fallbackMsg } catch { }
                            }
                        }
                    }
                }

                Import-Module (Join-Path $RepoRoot 'Modules\ParserWorker.psm1') -Force -ErrorAction Stop | Out-Null
                Invoke-StateTraceParsing -Synchronous -ErrorAction Stop *>&1 |
                    Out-File -FilePath $LogPath -Append -Encoding UTF8
            }
            $footer = "Parser job completed successfully at {0:o}" -f (Get-Date)
            Add-Content -LiteralPath $LogPath -Value $footer -Encoding UTF8
        } catch {
            $errorText = "Parser job failed at {0:o}: {1}" -f (Get-Date), ($_ | Out-String)
            Add-Content -LiteralPath $LogPath -Value $errorText -Encoding UTF8
            throw
        } finally {
            Pop-Location
        }
    }
    } catch {
        [System.Windows.MessageBox]::Show(("Failed to start parsing job: {0}" -f $_.Exception.Message), 'Parsing error')
        return
    }

    $script:CurrentParserJob = $job
    $script:ParserJobStartedAt = Get-Date
    $script:ParserJobLogPath = $logPath
    $script:ParserPendingSiteFilter = $SiteFilter
    Ensure-ParserStatusTimer -Window $Window
    Update-ParserStatusIndicator -Window $Window
    if ($script:ParserStatusTimer) { $script:ParserStatusTimer.Start() }
}

function Invoke-StateTraceRefresh {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Windows.Window]$Window)

    try {
        # Read checkboxes fresh each time (safe if UI is rebuilt)
        $includeArchiveCB    = $Window.FindName('IncludeArchiveCheckbox')
        $includeHistoricalCB = $Window.FindName('IncludeHistoricalCheckbox')
        $forceReloadCB       = $Window.FindName('ForceReloadCheckbox')

        $includeArchiveFlag = $false
        $includeHistoricalFlag = $false
        $forceReloadFlag = $false
        if ($includeArchiveCB) {
            $includeArchiveFlag = [bool]$includeArchiveCB.IsChecked
            Set-EnvToggle -Name 'IncludeArchive' -Checked $includeArchiveFlag
        }
        if ($includeHistoricalCB) {
            $includeHistoricalFlag = [bool]$includeHistoricalCB.IsChecked
            Set-EnvToggle -Name 'IncludeHistorical' -Checked $includeHistoricalFlag
        }
        if ($forceReloadCB) {
            $forceReloadFlag = [bool]$forceReloadCB.IsChecked
        }

        if ($global:StateTraceDb) { $env:StateTraceDbPath = $global:StateTraceDb }

        $siteFilterValue = Get-SelectedSiteFilterValue -Window $Window

        if ($forceReloadFlag) {
            Reset-ParserCachesForRefresh -SiteFilter $siteFilterValue
        }

        Start-ParserBackgroundJob -Window $Window -IncludeArchive $includeArchiveFlag -IncludeHistorical $includeHistoricalFlag -SiteFilter $siteFilterValue -ForceReload $forceReloadFlag
        Publish-UserActionTelemetry -Action 'ScanLogs' -Site $siteFilterValue -Hostname (Get-SelectedHostname -Window $Window) -Context 'MainWindow'

    } catch {
        Write-Warning ("Refresh failed: {0}" -f $_.Exception.Message)
    }
}

function Initialize-DeviceViewFromCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Windows.Window]$Window,
        [string]$SiteFilter,
        [object]$CatalogData
    )

    $initStopwatch = $null
    try { $initStopwatch = [System.Diagnostics.Stopwatch]::StartNew() } catch { $initStopwatch = $null }
    try { Write-Diag ("Initialize-DeviceViewFromCatalog start | SiteFilter={0} | HasCatalog={1}" -f $SiteFilter, [bool]$CatalogData) } catch { }

    $previousProgrammaticHostnameUpdate = $false
    try { $previousProgrammaticHostnameUpdate = [bool]$global:ProgrammaticHostnameUpdate } catch { $previousProgrammaticHostnameUpdate = $false }
    $global:ProgrammaticHostnameUpdate = $true
    try {

    $hostList = @()
    $targetHostnameToLoad = $null
    # Call the unified device helper functions directly (no module qualifier).
    $catalog = $null
    if ($CatalogData) {
        $catalog = $CatalogData
        try {
            if ($catalog.PSObject.Properties['Metadata']) { $global:DeviceMetadata = $catalog.Metadata }
            if ($catalog.PSObject.Properties['LocationEntries']) { $global:DeviceLocationEntries = $catalog.LocationEntries }
            if ($catalog.PSObject.Properties['HostnameOrder']) {
                $global:DeviceHostnameOrder = @($catalog.HostnameOrder)
            } elseif ($catalog.PSObject.Properties['Hostnames']) {
                $global:DeviceHostnameOrder = @($catalog.Hostnames)
            }
        } catch { }
    } else {
        try {
            if ([string]::IsNullOrWhiteSpace($SiteFilter)) {
                $catalog = Get-DeviceSummaries
            } else {
                $catalog = Get-DeviceSummaries -SiteFilter $SiteFilter
            }
        } catch { $catalog = $null }
    }

    if ($catalog -and $catalog.PSObject.Properties['Hostnames']) {
        $hostList = @($catalog.Hostnames)
    }
    if ($SiteFilter -and $catalog -and $catalog.Metadata) {
        $comparison = [System.StringComparer]::OrdinalIgnoreCase
        $filteredHosts = [System.Collections.Generic.List[string]]::new()
        foreach ($hostname in $hostList) {
            $meta = $null
            if ($catalog.Metadata.ContainsKey($hostname)) {
                $meta = $catalog.Metadata[$hostname]
            }
            $siteName = ''
            if ($meta -and $meta.PSObject.Properties['Site']) {
                $siteName = '' + $meta.Site
            }
            if ($comparison.Equals($siteName, $SiteFilter)) {
                $filteredHosts.Add($hostname) | Out-Null
            }
        }
        $hostList = $filteredHosts
        if ($hostList.Count -eq 0) {
            [System.Windows.MessageBox]::Show(("No hosts found for site '{0}'." -f $SiteFilter), "No Data")
        }
    }

    try {
        $locationEntries = $null
        try {
            if ($catalog -and $catalog.PSObject.Properties['LocationEntries']) {
                $locationEntries = $catalog.LocationEntries
            }
        } catch { $locationEntries = $null }

        if ($hostList -and $hostList.Count -gt 0) {
            if ($locationEntries) {
                Initialize-DeviceFilters -Hostnames $hostList -Window $Window -LocationEntries $locationEntries
            } else {
                Initialize-DeviceFilters -Hostnames $hostList -Window $Window
            }
        } else {
            Initialize-DeviceFilters -Window $Window
            $null = Invoke-OptionalCommandSafe -Name 'InterfaceModule\Set-HostLoadingIndicator' -Parameters @{ State = 'Hidden' }
        }
    } catch {}

    try {
        if ($initStopwatch) {
            Write-Diag ("Initialize-DeviceViewFromCatalog after Initialize-DeviceFilters | HostCount={0} | ElapsedMs={1}" -f @($hostList).Count, [Math]::Round($initStopwatch.Elapsed.TotalMilliseconds, 3))
        }
    } catch { }

    # Ensure the site dropdown reflects the chosen SiteFilter when loading from DB
    try {
        $siteDD = $Window.FindName('SiteDropdown')
        if ($siteDD -and -not [string]::IsNullOrWhiteSpace($SiteFilter)) {
            $global:ProgrammaticFilterUpdate = $true
            try {
                $targetSite = '' + $SiteFilter
                $match = $null
                foreach ($item in @($siteDD.Items)) {
                    $candidate = '' + $item
                    if ([System.StringComparer]::OrdinalIgnoreCase.Equals($candidate, $targetSite)) {
                        $match = $item
                        break
                    }
                }
                if ($match) {
                    $siteDD.SelectedItem = $match
                }
            } finally {
                $global:ProgrammaticFilterUpdate = $false
            }
        }
    } catch {}

    try {
        $siteTarget = $SiteFilter
        if (-not $siteTarget -and $hostList -and $catalog -and $catalog.Metadata) {
            $first = $hostList | Select-Object -First 1
            if ($first -and $catalog.Metadata.ContainsKey($first)) {
                $meta = $catalog.Metadata[$first]
                if ($meta -and $meta.PSObject.Properties['Site']) {
                    $siteTarget = '' + $meta.Site
                }
            }
        }
        Set-StateTraceDbPath -Site $siteTarget
    } catch {}

    try { Update-DeviceFilter } catch {}

    try {
        if ($initStopwatch) {
            Write-Diag ("Initialize-DeviceViewFromCatalog after Update-DeviceFilter | ElapsedMs={0}" -f [Math]::Round($initStopwatch.Elapsed.TotalMilliseconds, 3))
        }
    } catch { }

    if ((Test-OptionalCommandAvailable -Name 'Update-CompareView') -and (Test-CompareSidebarVisible -Window $Window)) {
        try { Update-CompareView -Window $Window | Out-Null }
        catch { Write-Warning ("Failed to refresh Compare view: {0}" -f $_.Exception.Message) }
    }

    try {
        $hostDD = $Window.FindName('HostnameDropdown')
        if ($hostDD) {
            $selected = $null
            try { $selected = '' + $hostDD.SelectedItem } catch { $selected = $null }

            $isAllSites = [string]::IsNullOrWhiteSpace($SiteFilter)
            $hostCount = 0
            try { $hostCount = [int]$hostDD.Items.Count } catch { $hostCount = 0 }

            # Avoid auto-loading device details when loading All Sites (often very large).
            if ($isAllSites) {
                try { $hostDD.SelectedIndex = -1 } catch { }
            } else {
                if ($hostCount -gt 0 -and ($hostDD.SelectedIndex -lt 0)) {
                    try { $hostDD.SelectedIndex = 0 } catch { }
                }

                # Auto-load the selected hostname when a site scope is selected.  Device details are
                # loaded asynchronously, so this is safe even for large site catalogs.
                if ([string]::IsNullOrWhiteSpace($selected) -and $hostCount -gt 0) {
                    try { $selected = '' + $hostDD.SelectedItem } catch { $selected = $null }
                }
                if ([string]::IsNullOrWhiteSpace($selected) -and $hostCount -gt 0) {
                    try { $selected = '' + ($hostDD.Items | Select-Object -First 1) } catch { $selected = $null }
                }
                if (-not [string]::IsNullOrWhiteSpace($selected)) {
                    $targetHostnameToLoad = $selected
                }
            }
        }
        $null = Invoke-OptionalCommandSafe -Name 'InterfaceModule\Set-HostLoadingIndicator' -Parameters @{ State = 'Hidden' }
    } catch {}
    } finally {
        $global:ProgrammaticHostnameUpdate = $previousProgrammaticHostnameUpdate
    }

    if ($targetHostnameToLoad) {
        try {
            $hostToLoadLocal = '' + $targetHostnameToLoad
            $invokeHostnameChanged = {
                try { Get-HostnameChanged -Hostname $hostToLoadLocal } catch { }
            }.GetNewClosure()

            $dispatcher = $null
            try { if ($Window -and $Window.Dispatcher) { $dispatcher = $Window.Dispatcher } } catch { $dispatcher = $null }
            if (-not $dispatcher) {
                try { $dispatcher = [System.Windows.Application]::Current.Dispatcher } catch { $dispatcher = $null }
            }

            if ($dispatcher) {
                $null = $dispatcher.BeginInvoke(
                    [System.Windows.Threading.DispatcherPriority]::Background,
                    [System.Action]$invokeHostnameChanged
                )
            }
        } catch { }
    }

    try {
        if ($initStopwatch) {
            $initStopwatch.Stop()
            Write-Diag ("Initialize-DeviceViewFromCatalog end | ElapsedMs={0}" -f [Math]::Round($initStopwatch.Elapsed.TotalMilliseconds, 3))
        }
    } catch { }
}

function Test-CompareSidebarVisible {
    [CmdletBinding()]
    param([Windows.Window]$Window)

    if (-not $Window) { return $false }

    try {
        $compareCol = $Window.FindName('CompareColumn')
        if ($compareCol -is [System.Windows.Controls.ColumnDefinition]) {
            try {
                if ($compareCol.Width.Value -gt 0) { return $true }
            } catch { }
        }
    } catch { }

    return $false
}

function Invoke-DatabaseImport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Windows.Window]$Window,
        [string]$SiteFilterOverride,
        [switch]$SkipTelemetry
    )

    try {
        if ($global:DatabaseImportInProgress) {
            try { Write-Diag ("Database import already in progress; ignoring request. CurrentRequestId={0}" -f $global:DatabaseImportRequestId) } catch {}
            return
        }

        $global:DatabaseImportInProgress = $true
        $requestId = 0
        try {
            $global:DatabaseImportRequestId = [int]$global:DatabaseImportRequestId + 1
            $requestId = [int]$global:DatabaseImportRequestId
        } catch {
            $requestId = [int][Environment]::TickCount
            try { $global:DatabaseImportRequestId = $requestId } catch { }
        }

        $global:InterfacesLoadAllowed = $true
        if ($global:StateTraceDb) { $env:StateTraceDbPath = $global:StateTraceDb }

        # Preserve the current filter selections (site/zone/building/room) so Load-from-DB does not
        # reset the user's location scope when we rebuild dropdown contents from catalog metadata.
        try {
            $loc = $null
            try {
                $loc = FilterStateModule\Get-SelectedLocation -Window $Window
            } catch {
                try { $loc = Get-SelectedLocation -Window $Window } catch { $loc = $null }
            }
            if ($loc -is [hashtable]) {
                $global:PendingFilterRestore = @{
                    Site     = if ($loc.ContainsKey('Site')) { '' + $loc.Site } else { '' }
                    Zone     = if ($loc.ContainsKey('Zone')) { '' + $loc.Zone } else { '' }
                    Building = if ($loc.ContainsKey('Building')) { '' + $loc.Building } else { '' }
                    Room     = if ($loc.ContainsKey('Room')) { '' + $loc.Room } else { '' }
                }
            } elseif ($loc) {
                $global:PendingFilterRestore = @{
                    Site     = if ($loc.PSObject.Properties['Site']) { '' + $loc.Site } else { '' }
                    Zone     = if ($loc.PSObject.Properties['Zone']) { '' + $loc.Zone } else { '' }
                    Building = if ($loc.PSObject.Properties['Building']) { '' + $loc.Building } else { '' }
                    Room     = if ($loc.PSObject.Properties['Room']) { '' + $loc.Room } else { '' }
                }
            }
        } catch {}

        $siteFilterValue = $null
        if ($PSBoundParameters.ContainsKey('SiteFilterOverride')) {
            if ([string]::IsNullOrWhiteSpace($SiteFilterOverride) -or [System.StringComparer]::OrdinalIgnoreCase.Equals($SiteFilterOverride, 'All Sites')) {
                $siteFilterValue = $null
            } else {
                $siteFilterValue = '' + $SiteFilterOverride
            }
        } else {
            $siteFilterValue = Get-SelectedSiteFilterValue -Window $Window
        }

        try {
            $loadBtn = $Window.FindName('LoadDatabaseButton')
            if ($loadBtn) { $loadBtn.IsEnabled = $false }
        } catch { }

        $modulesDir = $script:ModulesDirectory
        if (-not $modulesDir) {
            try {
                $modulesDir = (Resolve-Path -LiteralPath (Join-Path $scriptDir '..\Modules')).Path
            } catch {
                $modulesDir = Join-Path $scriptDir '..\Modules'
            }
        }

        $rs = Get-DatabaseImportRunspace
        if (-not $rs) {
            throw "Database import runspace unavailable."
        }

        $ps = $null
        try {
            $ps = [System.Management.Automation.PowerShell]::Create()
            $ps.Runspace = $rs

            $scriptText = @'
param(
    [string]$modulesDir,
    [string]$siteFilter
)
$ErrorActionPreference = 'Stop'

if (-not $script:CatalogModulesLoaded) {
    $moduleList = @(
        'DeviceRepositoryModule.psm1',
        'DeviceCatalogModule.psm1'
    )
    foreach ($name in $moduleList) {
        $modulePath = Join-Path $modulesDir $name
        if (Test-Path -LiteralPath $modulePath) {
            Import-Module -Name $modulePath -Global -Force -ErrorAction Stop
        }
    }
    $script:CatalogModulesLoaded = $true
}

$catalog = $null
if ([string]::IsNullOrWhiteSpace($siteFilter)) {
    $catalog = DeviceCatalogModule\Get-DeviceSummaries
} else {
    $catalog = DeviceCatalogModule\Get-DeviceSummaries -SiteFilter $siteFilter
}

$sites = @()
try {
    $paths = DeviceRepositoryModule\Get-AllSiteDbPaths
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($p in @($paths)) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $leaf = [System.IO.Path]::GetFileNameWithoutExtension($p)
        if ([string]::IsNullOrWhiteSpace($leaf)) { continue }
        [void]$set.Add($leaf)
    }
    $sites = @($set | Sort-Object -Unique)
} catch {
    $sites = @()
}

return [pscustomobject]@{
    Catalog = $catalog
    Sites   = $sites
}
'@

            [void]$ps.AddScript($scriptText)
            [void]$ps.AddArgument($modulesDir)
            [void]$ps.AddArgument($siteFilterValue)

            $diagRequestId = $requestId
            $diagSite = $siteFilterValue
            try { Write-Diag ("Invoke-DatabaseImport async dispatch | RequestId={0} | SiteFilter={1}" -f $diagRequestId, $diagSite) } catch {}

            $applyRequestId = $diagRequestId
            $applySiteFilterValue = $siteFilterValue
            $applyWindow = $Window
            $applySkipTelemetry = [bool]$SkipTelemetry
            $applyDelegateAction = {
                param($dto)
                $shouldFinalize = $false
                try {
                    $defaultRunspaceId = ''
                    try {
                        $defaultRunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
                        if ($defaultRunspace) { $defaultRunspaceId = '' + $defaultRunspace.Id }
                    } catch { $defaultRunspaceId = '' }

                    $threadId = 0
                    try { $threadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId } catch { $threadId = 0 }

                    $globalRequestId = $null
                    try { $globalRequestId = [int]$global:DatabaseImportRequestId } catch { $globalRequestId = $null }

                    $scriptRequestId = $null
                    try { $scriptRequestId = $script:DatabaseImportRequestId } catch { $scriptRequestId = $null }

                    try {
                        Write-Diag ("Invoke-DatabaseImport UI apply start | RequestId={0} | GlobalCurrent={1} | ScriptCurrent={2} | ThreadId={3} | DefaultRunspaceId={4}" -f $applyRequestId, $globalRequestId, $scriptRequestId, $threadId, $defaultRunspaceId)
                    } catch {}

                    if ($null -ne $globalRequestId -and ($applyRequestId -ne $globalRequestId)) {
                        try { Write-Diag ("Invoke-DatabaseImport stale completion ignored | RequestId={0} | GlobalCurrent={1}" -f $applyRequestId, $globalRequestId) } catch {}
                        return
                    }

                    $shouldFinalize = $true

                    if (-not $dto -or ($dto -is [System.Management.Automation.ErrorRecord])) {
                        if ($dto -and $dto.Exception) {
                            Write-Warning ("Database import failed: {0}" -f $dto.Exception.Message)
                        } else {
                            Write-Warning "Database import failed: no result returned."
                        }
                        return
                    }

                    $catalog = $null
                    $sites = @()
                    try { if ($dto.PSObject.Properties['Catalog']) { $catalog = $dto.Catalog } } catch { $catalog = $null }
                    try { if ($dto.PSObject.Properties['Sites']) { $sites = @($dto.Sites) } } catch { $sites = @() }

                    Initialize-DeviceViewFromCatalog -Window $applyWindow -SiteFilter $applySiteFilterValue -CatalogData $catalog

                    if ($sites -and $sites.Count -gt 0) {
                        Populate-SiteDropdownWithAvailableSites -Window $applyWindow -Sites $sites -PreferredSelection $applySiteFilterValue -PreserveExistingSelection
                    } else {
                        Populate-SiteDropdownWithAvailableSites -Window $applyWindow -PreferredSelection $applySiteFilterValue -PreserveExistingSelection
                    }

                    if (-not $applySkipTelemetry) {
                        Publish-UserActionTelemetry -Action 'LoadFromDb' -Site $applySiteFilterValue -Hostname (Get-SelectedHostname -Window $applyWindow) -Context 'MainWindow'
                    }
                } catch {
                    Write-Warning ("Database import UI apply failed: {0}" -f $_.Exception.Message)
                } finally {
                    if ($shouldFinalize) {
                        try {
                            $loadBtn = $applyWindow.FindName('LoadDatabaseButton')
                            if ($loadBtn) { $loadBtn.IsEnabled = $true }
                        } catch { }
                        $global:DatabaseImportInProgress = $false
                    }
                }
            }.GetNewClosure()
            $applyDelegate = [System.Action[object]]$applyDelegateAction

            $uiContext = $null
            try { $uiContext = [System.Threading.SynchronizationContext]::Current } catch { $uiContext = $null }
            if (-not $uiContext) {
                try {
                    $uiContext = [System.Windows.Threading.DispatcherSynchronizationContext]::new([System.Windows.Application]::Current.Dispatcher)
                } catch {
                    $uiContext = $null
                }
            }
            if (-not $uiContext) {
                throw "Database import cannot start: UI synchronization context unavailable."
            }

            $threadTag = 'DBImport-{0}' -f $requestId
            $threadStart = [StateTrace.Threading.PowerShellInvokeWithUiCallbackThreadStartFactory]::Create(
                $ps,
                $script:DatabaseImportRunspaceLock,
                $uiContext,
                $applyDelegate,
                $threadTag
            )
            $workerThread = [System.Threading.Thread]::new($threadStart)
            $workerThread.IsBackground = $true
            $workerThread.ApartmentState = [System.Threading.ApartmentState]::STA
            $workerThread.Start()
        } catch {
            try { if ($ps) { $ps.Dispose() } } catch {}
            throw
        }
    } catch {
        try { $global:PendingFilterRestore = $null } catch {}
        try {
            $loadBtn = $Window.FindName('LoadDatabaseButton')
            if ($loadBtn) { $loadBtn.IsEnabled = $true }
        } catch { }
        $global:DatabaseImportInProgress = $false
        Write-Warning ("Database import failed: {0}" -f $_.Exception.Message)
    }
}

function Get-HostnameChanged {
    [CmdletBinding()]
    param([string]$Hostname)

    if (-not $global:InterfacesLoadAllowed) {
        $null = Invoke-OptionalCommandSafe -Name 'InterfaceModule\Set-HostLoadingIndicator' -Parameters @{ State = 'Hidden' }
        return
    }

    if ($global:ProgrammaticHostnameUpdate) { return }

    try {
        $currentIndex = 0
        $totalHosts = 0
        try {
            $hostDropdownRef = $null
            if ($global:window) {
                $hostDropdownRef = $global:window.FindName('HostnameDropdown')
            }
            if ($hostDropdownRef) {
                if ($hostDropdownRef.Items) {
                    $totalHosts = [int]$hostDropdownRef.Items.Count
                }
                $selectedIndex = $hostDropdownRef.SelectedIndex
                if ($selectedIndex -ge 0) {
                    $currentIndex = [int]$selectedIndex + 1
                }
            }
        } catch {
            $currentIndex = 0
            $totalHosts = 0
        }

        $hostIndicatorCmd = Get-OptionalCommandSafe -Name 'InterfaceModule\Set-HostLoadingIndicator'
  
        # Load device details asynchronously.
        if ($Hostname) {
            if ($hostIndicatorCmd) {
                try {
                    InterfaceModule\Set-HostLoadingIndicator -Hostname $Hostname -CurrentIndex $currentIndex -TotalHosts $totalHosts -State 'Loading'
                } catch {}
            }
            try {
                Import-DeviceDetailsAsync -Hostname $Hostname
            } catch {
                Write-Warning ("Hostname change handler failed to queue async device load for {0}: {1}" -f $Hostname, $_.Exception.Message)
                if ($hostIndicatorCmd) {
                    try { InterfaceModule\Set-HostLoadingIndicator -State 'Hidden' } catch {}
                }
            }

            $spanVisible = $false
            try {
                $spanHostCtrl = $null
                if ($global:window) { $spanHostCtrl = $global:window.FindName('SpanHost') }
                if ($spanHostCtrl -and $spanHostCtrl.IsVisible) { $spanVisible = $true }
            } catch { $spanVisible = $false }
            if ($spanVisible) {
                $null = Invoke-OptionalCommandSafe -Name 'Get-SpanInfo' -ArgumentList @($Hostname)
            }
        } else {
            if ($hostIndicatorCmd) {
                try { InterfaceModule\Set-HostLoadingIndicator -State 'Hidden' } catch {}
            }
            # Clear span info when hostname is empty
            $spanVisible = $false
            try {
                $spanHostCtrl = $null
                if ($global:window) { $spanHostCtrl = $global:window.FindName('SpanHost') }
                if ($spanHostCtrl -and $spanHostCtrl.IsVisible) { $spanVisible = $true }
            } catch { $spanVisible = $false }
            if ($spanVisible) {
                $null = Invoke-OptionalCommandSafe -Name 'Get-SpanInfo' -ArgumentList @('')
            }
        }
    } catch {
        Write-Warning ("Hostname change handler failed: {0}" -f $_.Exception.Message)
    }
}

function Import-DeviceDetailsAsync {
    
    [CmdletBinding()]
    param(
        [string]$Hostname
    )
    $debug = ($Global:StateTraceDebug -eq $true)
    $hostTrim = ('' + $Hostname).Trim()
    if (-not $global:StateTraceDb) {
        try { Set-StateTraceDbPath } catch {}
    }
    if ($debug) {
        Write-Verbose ("Import-DeviceDetailsAsync: called with Hostname='{0}'" -f $hostTrim)
    }
    try { Write-Diag ("Import-DeviceDetailsAsync start | Host={0}" -f $hostTrim) } catch {}
    # If no host is provided, clear span info and return
    if ([string]::IsNullOrWhiteSpace($hostTrim)) {
        $null = Invoke-OptionalCommandSafe -Name 'InterfaceModule\Set-HostLoadingIndicator' -Parameters @{ State = 'Hidden' }
        try { [System.Windows.Application]::Current.Dispatcher.Invoke([System.Action]{ Invoke-OptionalCommandSafe -Name 'Get-SpanInfo' -ArgumentList @('') | Out-Null }) } catch {}
        return
    }

    $modulesDir = $script:ModulesDirectory
    if (-not $modulesDir) {
        try {
            $modulesDir = (Resolve-Path -LiteralPath (Join-Path $scriptDir "..\Modules")).Path
        } catch {
            $modulesDir = Join-Path $scriptDir "..\Modules"
        }
    }

    $rs = Get-DeviceDetailsRunspace
    if (-not $rs) {
        Write-Warning ("Import-DeviceDetailsAsync failed to acquire a device loader runspace.")
        return
    }

    $ps = $null
    try {
        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $rs
        if ($debug) {
            Write-Verbose ("Import-DeviceDetailsAsync: using pooled runspace (Id={0})" -f $rs.Id)
        }
    } catch {
        Write-Warning ("Import-DeviceDetailsAsync: failed to attach PowerShell to runspace: {0}" -f $_.Exception.Message)
        return
    }

    try {
        # Build a script string instead of passing a ScriptBlock.  Passing a string
        $scriptText = @'
param($hn, $modulesDir, $diagPath, $moduleList, $dbPath)
$diagStamp = {
    param($text)
    if (-not $diagPath) { return }
    try {
        $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        Add-Content -LiteralPath $diagPath -Value ("[{0}] {1}" -f $timestamp, $text) -ErrorAction SilentlyContinue
    } catch {}
}
$ErrorActionPreference = 'Stop'
if (-not [string]::IsNullOrWhiteSpace($dbPath)) {
    $global:StateTraceDb = $dbPath
    $env:StateTraceDbPath = $dbPath
}
$modulesLoadedNow = $false
if (-not $script:DeviceLoaderModulesLoaded) {
    $modules = @($moduleList)
    foreach ($name in $modules) {
        $modulePath = Join-Path $modulesDir $name
        if (Test-Path -LiteralPath $modulePath) {
            Import-Module -Name $modulePath -Global -ErrorAction Stop
        }
    }
    $script:DeviceLoaderModulesLoaded = $true
    $modulesLoadedNow = $true
}
$res = $null
try {
    & $diagStamp ("Async thread modules ready for host {0} | LoadedNow={1}" -f $hn, $modulesLoadedNow)
    $res = DeviceDetailsModule\Get-DeviceDetailsData -Hostname $hn
} catch {
    $res = $_
}
return $res
'@
        # Add the script and arguments to the PowerShell instance
        [void]$ps.AddScript($scriptText)
        [void]$ps.AddArgument($hostTrim)
        [void]$ps.AddArgument($modulesDir)
        [void]$ps.AddArgument($script:DiagLogPath)
        [void]$ps.AddArgument($script:DeviceLoaderModuleNames)
        [void]$ps.AddArgument($global:StateTraceDb)
        if ($debug) {
            Write-Verbose "Import-DeviceDetailsAsync: script and arguments added to PowerShell instance"
        }

        # Execute the device details retrieval on a dedicated background thread instead of using
        if ($Global:StateTraceDebug -eq $true) {
            Write-Verbose ("Import-DeviceDetailsAsync: starting background thread for '{0}'" -f $hostTrim)
        }
        try { Write-Diag ("Import-DeviceDetailsAsync thread launching | Host={0}" -f $hostTrim) } catch {}

        $uiContext = $null
        try { $uiContext = [System.Threading.SynchronizationContext]::Current } catch { $uiContext = $null }
        if (-not $uiContext) {
            try {
                $uiContext = [System.Windows.Threading.DispatcherSynchronizationContext]::new([System.Windows.Application]::Current.Dispatcher)
            } catch {
                $uiContext = $null
            }
        }
        if (-not $uiContext) {
            throw "Import-DeviceDetailsAsync cannot start: UI synchronization context unavailable."
        }

        $deviceHostForUi = $hostTrim
        $uiCallback = {
            param($dto)
            try {
                if (-not $dto -or ($dto -is [System.Management.Automation.ErrorRecord])) {
                    if ($dto -and $dto.Exception) {
                        Write-Warning ("Import-DeviceDetailsAsync error: {0}" -f $dto.Exception.Message)
                        try { Write-Diag ("Import-DeviceDetailsAsync error detail | Host={0} | Error={1}" -f $deviceHostForUi, $dto.Exception.ToString()) } catch {}
                    }

                    try {
                        if ($global:interfacesView) {
                            $view = $global:interfacesView
                            $grid = $view.FindName('InterfacesGrid')
                            if ($grid) { $grid.ItemsSource = $null }
                        }
                    } catch { }

                    $null = Invoke-OptionalCommandSafe -Name 'InterfaceModule\Hide-PortLoadingIndicator'
                    $null = Invoke-OptionalCommandSafe -Name 'InterfaceModule\Set-HostLoadingIndicator' -Parameters @{ State = 'Hidden' }
                    return
                }

                $defaultHost = $deviceHostForUi
                try {
                    if ($dto.PSObject.Properties['Summary'] -and $dto.Summary -and $dto.Summary.PSObject.Properties['Hostname']) {
                        $candidate = ('' + $dto.Summary.Hostname).Trim()
                        if (-not [string]::IsNullOrWhiteSpace($candidate)) { $defaultHost = $candidate }
                    }
                } catch { $defaultHost = $deviceHostForUi }

                try {
                    InterfaceModule\Set-InterfaceViewData -DeviceDetails $dto -DefaultHostname $defaultHost
                } catch {
                    try { Write-Diag ("InterfaceViewData failed | Host={0} | Error={1}" -f $defaultHost, $_.Exception.Message) } catch {}
                }

                try {
                    $interfaces = $null
                    if ($dto.PSObject.Properties['Interfaces']) { $interfaces = $dto.Interfaces }
                    if ($interfaces) {
                        if (-not (Get-Variable -Name DeviceInterfaceCache -Scope Global -ErrorAction SilentlyContinue)) {
                            $global:DeviceInterfaceCache = @{}
                        }
                        $global:DeviceInterfaceCache[$deviceHostForUi] = $interfaces
                    }
                } catch { }

                $null = Invoke-OptionalCommandSafe -Name 'InterfaceModule\Hide-PortLoadingIndicator'
                $null = Invoke-OptionalCommandSafe -Name 'InterfaceModule\Set-HostLoadingIndicator' -Parameters @{ Hostname = $deviceHostForUi; State = 'Loaded' }
                try { Request-DeviceFilterUpdate } catch { }
            } catch {
            }
        }
        $uiDelegate = [System.Action[object]]$uiCallback

        $threadTag = $hostTrim
        $threadStart = [StateTrace.Threading.PowerShellInvokeWithUiCallbackThreadStartFactory]::Create(
            $ps,
            $script:DeviceDetailsRunspaceLock,
            $uiContext,
            $uiDelegate,
            $threadTag
        )
        $workerThread = [System.Threading.Thread]::new($threadStart)
        $workerThread.IsBackground = $true
        $workerThread.ApartmentState = [System.Threading.ApartmentState]::STA
        $workerThread.Start()
        return
        $diagPathLocal = $script:DiagLogPath
        $threadScript = {
            param([System.Management.Automation.PowerShell]$psCmd, [string]$deviceHost)
            $logAsync = {
                param($message)
                if (-not $diagPathLocal) { return }
                try {
                    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
                    Add-Content -LiteralPath $diagPathLocal -Value ("[{0}] {1}" -f $stamp, $message) -ErrorAction SilentlyContinue
                } catch {}
            }
            $semaphore = $script:DeviceDetailsRunspaceLock
            $heldLock = $false
            try {
                if ($semaphore) {
                    try {
                        $semaphore.Wait()
                        $heldLock = $true
                    } catch {
                        $heldLock = $false
                    }
                }
                # Invoke the script synchronously in the background thread
                $invokeStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $results = $psCmd.Invoke()
                $invokeStopwatch.Stop()
                # Take the first result if multiple were returned
                if ($results -is [System.Collections.IEnumerable]) {
                    $data = $results | Select-Object -First 1
                } else {
                    $data = $results
                }
                $invokeDurationMs = 0.0
                try {
                    if ($invokeStopwatch) {
                        $invokeDurationMs = [Math]::Round($invokeStopwatch.Elapsed.TotalMilliseconds, 3)
                    }
                } catch { $invokeDurationMs = 0.0 }

                & $logAsync ("Async thread received device details result for host {0}" -f $deviceHost)
                if ($Global:StateTraceDebug -eq $true) {
                    try {
                        $typeName = if ($null -ne $data) { $data.GetType().FullName } else { 'null' }
                        Write-Verbose ("Import-DeviceDetailsAsync: thread received result of type '{0}'" -f $typeName)
                    } catch {}
                }
                # Marshal UI updates back to the dispatcher thread.  Passing the result as
                $uiAction = {
                    param($dto)
                    try {
                        # If an error record or null result was returned, display a warning and exit
                        if (-not $dto -or ($dto -is [System.Management.Automation.ErrorRecord])) {
                            if ($dto -and $dto.Exception) {
                                Write-Warning ("Import-DeviceDetailsAsync error: {0}" -f $dto.Exception.Message)
                                try { Write-Diag ("Import-DeviceDetailsAsync error detail | Host={0} | Error={1}" -f $deviceHost, $dto.Exception.ToString()) } catch {}
                            }
                            # Clear the interfaces grid on failure
                            if ($global:interfacesView) {
                                $view = $global:interfacesView
                                $grid = $view.FindName('InterfacesGrid')
                                if ($grid) { $grid.ItemsSource = $null }
                            }
                            return
                        }
                        # Extract summary information for downstream helpers
                        $summary = $null
                        if ($dto -and $dto.PSObject.Properties['Summary']) { $summary = $dto.Summary }
                        $defaultHost = $deviceHost
                        if ($summary -and $summary.PSObject.Properties['Hostname']) {
                            $defaultHost = [string]$summary.Hostname
                        }
                        try { Write-Diag ("InterfaceViewData scheduling | Host={0}" -f $defaultHost) } catch {}
                        try {
                            InterfaceModule\Set-InterfaceViewData -DeviceDetails $dto -DefaultHostname $defaultHost
                            $ifaceCount = 0
                            try { $ifaceCount = @($dto.Interfaces).Count } catch { $ifaceCount = 0 }
                            try { Write-Diag ("InterfaceViewData applied | Host={0} | Interfaces={1}" -f $defaultHost, $ifaceCount) } catch {}
                        } catch {
                            try { Write-Diag ("InterfaceViewData failed | Host={0} | Error={1}" -f $defaultHost, $_.Exception.Message) } catch {}
                            if ($debug) {
                                Write-Verbose ("Import-DeviceDetailsAsync: failed to apply device details: {0}" -f $_.Exception.Message)
                            }
                        }
                    } catch {
                        # Swallow UI update exceptions to prevent crashes
                    }
                }
                $uiAction = $uiAction.GetNewClosure()
                $uiDelegate = [System.Action[object]]$uiAction
                # Invoke the UI action with the result.  Wrap in try/catch to handle dispatcher errors.
                try {
                    [System.Windows.Application]::Current.Dispatcher.Invoke($uiDelegate, $data)
                } catch {
                    # Log any dispatcher invocation errors but do not crash
                    Write-Warning ("Import-DeviceDetailsAsync dispatcher invocation failed: {0}" -f $_.Exception.Message)
                }

                if ($data -and -not ($data -is [System.Management.Automation.ErrorRecord])) {
                    $collection = $null
                    try {
                        if ($data.PSObject.Properties['Interfaces']) { $collection = $data.Interfaces }
                    } catch { $collection = $null }

                    $collection = Convert-InterfaceCollectionForHost -Collection $collection -Hostname $deviceHost
                    try { $data.Interfaces = $collection } catch { }

                    try { DeviceRepositoryModule\Initialize-InterfacePortStream -Hostname $deviceHost } catch { }
                    & $logAsync ("Async stream initialized for host {0}" -f $deviceHost)

                    $streamStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    $firstBatchTimer = [System.Diagnostics.Stopwatch]::StartNew()
                    $firstBatchDelayMs = $null
                    $streamDurationMs = 0.0
                    $totalDispatcherMs = 0.0
                    $totalAppendMs = 0.0
                    $totalIndicatorMs = 0.0
                    $batchesProcessed = 0

                    $initialStatus = $null
                    try { $initialStatus = DeviceRepositoryModule\Get-InterfacePortStreamStatus -Hostname $deviceHost } catch { $initialStatus = $null }
                    if ($initialStatus) {
                        [System.Windows.Application]::Current.Dispatcher.Invoke([System.Action]{
                            InterfaceModule\Set-PortLoadingIndicator -Loaded $initialStatus.PortsDelivered -Total $initialStatus.TotalPorts -BatchesRemaining $initialStatus.BatchesRemaining
                        })
                    }

                    if ($null -ne $collection) {
                        try {
                            [System.Windows.Application]::Current.Dispatcher.Invoke([System.Action]{
                                if (-not (Get-Variable -Name DeviceInterfaceCache -Scope Global -ErrorAction SilentlyContinue)) {
                                    $global:DeviceInterfaceCache = @{}
                                }
                                $global:DeviceInterfaceCache[$deviceHost] = $collection
                            })
                        } catch {
                            try {
                                if (-not (Get-Variable -Name DeviceInterfaceCache -Scope Global -ErrorAction SilentlyContinue)) {
                                    $global:DeviceInterfaceCache = @{}
                                }
                                $global:DeviceInterfaceCache[$deviceHost] = $collection
                            } catch {}
                        }

                        $collectionCount = 0
                        try {
                            if (Test-OptionalCommandAvailable -Name 'ViewStateService\Get-SequenceCount') {
                                $collectionCount = ViewStateService\Get-SequenceCount -Value $collection
                            } elseif ($collection -is [System.Collections.ICollection]) {
                                $collectionCount = [int]$collection.Count
                            } else {
                                $collectionCount = @($collection).Count
                            }
                        } catch { $collectionCount = 0 }

                        $streamingRequired = ($collectionCount -le 0)

                        if (-not $streamingRequired) {
                            $converted = $collection
                            $needsConversion = $false
                            try {
                                $firstItem = $null
                                foreach ($item in $collection) { $firstItem = $item; break }
                                if ($firstItem -is [System.Data.DataRow] -or $firstItem -is [System.Data.DataRowView]) {
                                    $needsConversion = $true
                                }
                            } catch { $needsConversion = $false }

                            if ($needsConversion) {
                                try {
                                    $convertedList = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
                                    foreach ($item in $collection) {
                                        $clone = $item
                                        try { $clone = DeviceRepositoryModule\ConvertTo-PortPsObject -Row $item -Hostname $deviceHost } catch { }
                                        if ($null -ne $clone) { $convertedList.Add($clone) | Out-Null }
                                    }
                                    if ($convertedList) {
                                        $converted = $convertedList
                                        try { $data.Interfaces = $converted } catch { }
                                    }
                                } catch { }
                            }
                            $collection = $converted

                            try {
                                [System.Windows.Application]::Current.Dispatcher.Invoke([System.Action]{
                                    try {
                                        if (-not (Get-Variable -Name DeviceInterfaceCache -Scope Global -ErrorAction SilentlyContinue)) {
                                            $global:DeviceInterfaceCache = @{}
                                        }
                                        $global:DeviceInterfaceCache[$deviceHost] = $collection
                                    } catch { }
                                    try {
                                        $grid = $null
                                        try { $grid = $global:interfacesGrid } catch { $grid = $null }
                                        if (-not $grid -and $global:interfacesView) {
                                            try { $grid = $global:interfacesView.FindName('InterfacesGrid') } catch { $grid = $null }
                                        }
                                        if ($grid) { $grid.ItemsSource = $collection }
                                    } catch { }

                                    try { InterfaceModule\Set-PortLoadingIndicator -Loaded $collectionCount -Total $collectionCount -BatchesRemaining 0 } catch {}
                                })
                            } catch { }
                            try { Write-Diag ("Port stream skipped | Host={0} | ExistingCount={1}" -f $deviceHost, $collectionCount) } catch {}
                        }

                        if ($streamingRequired) {
                            while ($true) {
                                $batch = $null
                                try { $batch = DeviceRepositoryModule\Get-InterfacePortBatch -Hostname $deviceHost } catch { $batch = $null }
                                if ($batch) {
                                    $portList = $batch.Ports
                                    $portItems = $portList
                                    if (-not ($portItems -is [System.Collections.ICollection])) {
                                        $portItems = @($portItems)
                                    }
                                    $batchCount = 0
                                    try { $batchCount = $portItems.Count } catch { $batchCount = 0 }
                                    & $logAsync ("Async retrieved batch for host {0} with {1} port(s). Completed={2}" -f $deviceHost, $batchCount, $batch.Completed)

                                    $batchSize = 0
                                    try {
                                        if ($portItems) { $batchSize = [int]$portItems.Count }
                                    } catch { $batchSize = 0 }

                                    $appendDurationMs = 0.0
                                    $indicatorDurationMs = 0.0
                                    $dispatcherDurationMs = 0.0

                                    $dispatcherStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                                    $uiMetrics = [System.Windows.Application]::Current.Dispatcher.Invoke([System.Func[object]]{
                                        $localAppend = 0.0
                                        $localIndicator = 0.0

                                        try {
                                            $appendSw = [System.Diagnostics.Stopwatch]::StartNew()
                                            foreach ($row in $portItems) { $collection.Add($row) }
                                            $appendSw.Stop()
                                            $localAppend = [Math]::Round($appendSw.Elapsed.TotalMilliseconds, 3)
                                        } catch {
                                            $localAppend = 0.0
                                        }

                                        try {
                                            $indicatorSw = [System.Diagnostics.Stopwatch]::StartNew()
                                            InterfaceModule\Set-PortLoadingIndicator -Loaded $batch.PortsDelivered -Total $batch.TotalPorts -BatchesRemaining $batch.BatchesRemaining
                                            $indicatorSw.Stop()
                                            $localIndicator = [Math]::Round($indicatorSw.Elapsed.TotalMilliseconds, 3)
                                        } catch {
                                            $localIndicator = 0.0
                                        }

                                        return [pscustomobject]@{
                                            AppendDurationMs    = $localAppend
                                            IndicatorDurationMs = $localIndicator
                                        }
                                    })
                                    $dispatcherStopwatch.Stop()
                                    $dispatcherDurationMs = [Math]::Round($dispatcherStopwatch.Elapsed.TotalMilliseconds, 3)
                                    $collectionCount = 0
                                    try { $collectionCount = @($collection).Count } catch { $collectionCount = 0 }
                                    try { Write-Diag ("Interface batch appended | Host={0} | BatchSize={1} | CollectionCount={2}" -f $deviceHost, $batchSize, $collectionCount) } catch {}

                                    if ($uiMetrics) {
                                        if ($uiMetrics.PSObject.Properties['AppendDurationMs']) {
                                            $appendDurationMs = [double]$uiMetrics.AppendDurationMs
                                        }
                                        if ($uiMetrics.PSObject.Properties['IndicatorDurationMs']) {
                                            $indicatorDurationMs = [double]$uiMetrics.IndicatorDurationMs
                                        }
                                    }

                                    try {
                                        DeviceRepositoryModule\Set-InterfacePortDispatchMetrics -Hostname $deviceHost -BatchId $batch.BatchId -BatchOrdinal $batch.BatchOrdinal -BatchCount $batch.BatchCount -BatchSize $batchSize -PortsDelivered $batch.PortsDelivered -TotalPorts $batch.TotalPorts -DispatcherDurationMs $dispatcherDurationMs -AppendDurationMs $appendDurationMs -IndicatorDurationMs $indicatorDurationMs
                                    } catch { }

                                    $batchesProcessed++
                                    try {
                                        $totalDispatcherMs += $dispatcherDurationMs
                                        $totalAppendMs += $appendDurationMs
                                        $totalIndicatorMs += $indicatorDurationMs
                                    } catch { }
                                    if ($firstBatchDelayMs -eq $null -and $firstBatchTimer) {
                                        try { $firstBatchDelayMs = [Math]::Round($firstBatchTimer.Elapsed.TotalMilliseconds, 3) } catch { $firstBatchDelayMs = 0.0 }
                                    }

                                    if ($batch.Completed) { break }
                                    continue
                                }

                                else {
                                    & $logAsync ("Async Get-InterfacePortBatch returned null for host {0}; exiting loop" -f $deviceHost)
                                    break
                                }

                                $streamStatus = $null
                                try { $streamStatus = DeviceRepositoryModule\Get-InterfacePortStreamStatus -Hostname $deviceHost } catch { $streamStatus = $null }
                                if ($streamStatus -and $streamStatus.Completed) { break }
                                Start-Sleep -Milliseconds 150
                            }
                        }
                     }

                }

                if ($streamStopwatch) {
                    try {
                        $streamStopwatch.Stop()
                        $streamDurationMs = [Math]::Round($streamStopwatch.Elapsed.TotalMilliseconds, 3)
                    } catch { $streamDurationMs = 0.0 }
                }
                if ($firstBatchDelayMs -eq $null) {
                    if ($batchesProcessed -gt 0 -and $streamDurationMs -gt 0) {
                        $firstBatchDelayMs = $streamDurationMs
                    } else {
                        $firstBatchDelayMs = 0.0
                    }
                }

                if ($collection) {
                    try {
                        [System.Windows.Application]::Current.Dispatcher.Invoke([System.Action]{
                            try { Update-DeviceInterfaceCacheSnapshot -Hostname $deviceHost -Collection $collection } catch {}
                        })
                    } catch {}
                }

                $finalCollectionCount = 0
                try { $finalCollectionCount = [int](@($collection).Count) } catch { $finalCollectionCount = 0 }

                $queueMetrics = $null
                try { $queueMetrics = DeviceRepositoryModule\Get-LastInterfacePortQueueMetrics } catch { $queueMetrics = $null }

                try {
                    Write-Diag ("Device load metrics | Host={0} | InvokeMs={1} | StreamMs={2} | FirstBatchMs={3} | Batches={4} | Interfaces={5}" -f $deviceHost, $invokeDurationMs, $streamDurationMs, $firstBatchDelayMs, $batchesProcessed, $finalCollectionCount)
                } catch {}

                $telemetryPayload = @{
                    Hostname          = $deviceHost
                    InvokeDurationMs  = $invokeDurationMs
                    StreamDurationMs  = $streamDurationMs
                    FirstBatchMs      = $(if ($firstBatchDelayMs -ne $null) { $firstBatchDelayMs } else { 0.0 })
                    BatchesProcessed  = $batchesProcessed
                    InterfaceCount    = $finalCollectionCount
                    AppendWorkMs      = [Math]::Round($totalAppendMs, 3)
                    DispatcherWorkMs  = [Math]::Round($totalDispatcherMs, 3)
                    IndicatorWorkMs   = [Math]::Round($totalIndicatorMs, 3)
                }
                if ($queueMetrics) {
                    try {
                        if ($queueMetrics.PSObject.Properties['ChunkSize']) { $telemetryPayload.ChunkSize = [int]$queueMetrics.ChunkSize }
                        if ($queueMetrics.PSObject.Properties['ChunkSource']) { $telemetryPayload.ChunkSource = '' + $queueMetrics.ChunkSource }
                        if ($queueMetrics.PSObject.Properties['BatchCount']) { $telemetryPayload.PlannedBatchCount = [int]$queueMetrics.BatchCount }
                        if ($queueMetrics.PSObject.Properties['TotalPorts']) { $telemetryPayload.QueuePorts = [int]$queueMetrics.TotalPorts }
                    } catch { }
                }
                $null = Invoke-OptionalCommandSafe -Name 'TelemetryModule\Write-StTelemetryEvent' -Parameters @{
                    Name    = 'DeviceDetailsLoadMetrics'
                    Payload = $telemetryPayload
                } | Out-Null

                try { DeviceRepositoryModule\Clear-InterfacePortStream -Hostname $deviceHost } catch { }
                & $logAsync ("Async cleared port stream for host {0}" -f $deviceHost)
                $hostIndicatorAvailable = $false
                $deviceHostLocal = $deviceHost
                try {
                    $hostIndicatorAvailable = Test-OptionalCommandAvailable -Name 'InterfaceModule\Set-HostLoadingIndicator'
                } catch { $hostIndicatorAvailable = $false }
                $hostIndicatorAvailableLocal = $hostIndicatorAvailable
                [System.Windows.Application]::Current.Dispatcher.Invoke([System.Action]{
                    InterfaceModule\Hide-PortLoadingIndicator
                    if ($hostIndicatorAvailableLocal) {
                        try { InterfaceModule\Set-HostLoadingIndicator -Hostname $deviceHostLocal -State 'Loaded' } catch {}
                    }
                })
            } catch {
                # Log any exceptions thrown during Invoke
                Write-Warning ("Import-DeviceDetailsAsync thread encountered an exception: {0}" -f $_.Exception.Message)
                try {
                    $null = Invoke-OptionalCommandSafe -Name 'InterfaceModule\Set-HostLoadingIndicator' -Parameters @{ State = 'Hidden' }
                } catch {}
                try {
                    if ($script:DeviceDetailsRunspace -and
                        $script:DeviceDetailsRunspace.RunspaceStateInfo.State -eq [System.Management.Automation.Runspaces.RunspaceState]::Broken) {
                        $script:DeviceDetailsRunspace.Dispose()
                        $script:DeviceDetailsRunspace = $null
                    }
                } catch { }
            } finally {
                # Clean up the PowerShell instance and release the pooled runspace lock
                try { $psCmd.Commands.Clear() } catch {}
                $psCmd.Dispose()
                if ($heldLock -and $semaphore) {
                    try { $semaphore.Release() } catch {}
                }
            }
        }
        # Build the thread start delegate and launch the background thread
        $threadStart = [StateTrace.Threading.PowerShellThreadStartFactory]::Create($threadScript, $ps, $hostTrim)
        $workerThread = [System.Threading.Thread]::new($threadStart)
        $workerThread.ApartmentState = [System.Threading.ApartmentState]::STA
        $workerThread.Start()
    } catch {
        Write-Warning ("Import-DeviceDetailsAsync failed to dispatch background load: {0}" -f $_.Exception.Message)
        try { if ($ps) { $ps.Dispose() } } catch {}
    }
}

# Wire events exactly once
$refreshBtn       = $window.FindName('RefreshButton')
$hostnameDropdown = $window.FindName('HostnameDropdown')

if ($refreshBtn -and -not $script:RefreshHandlerAttached) {
    $refreshBtn.Add_Click({ param($sender,$e) Invoke-StateTraceRefresh -Window $window })
    $script:RefreshHandlerAttached = $true
}

$loadDbButton = $window.FindName('LoadDatabaseButton')
if ($loadDbButton -and -not $script:LoadDatabaseHandlerAttached) {
    $loadDbButton.Add_Click({ param($sender,$e) Invoke-DatabaseImport -Window $window })
    $script:LoadDatabaseHandlerAttached = $true
}

# View Pipeline Log button - opens the latest pipeline log file
$viewLogButton = $window.FindName('ViewPipelineLogButton')
if ($viewLogButton -and -not $script:ViewLogHandlerAttached) {
    $viewLogButton.Add_Click({
        param($sender,$e)
        $logPath = Get-LatestPipelineLogPath
        if ($logPath -and (Test-Path -LiteralPath $logPath)) {
            try {
                Start-Process -FilePath $logPath
            } catch {
                [System.Windows.MessageBox]::Show("Failed to open log: $_", "Error", 'OK', 'Error')
            }
        } else {
            [System.Windows.MessageBox]::Show("No pipeline log found.", "Info", 'OK', 'Information')
        }
    })
    $script:ViewLogHandlerAttached = $true
}

# Refresh from DB button - reloads interface data without re-parsing
$refreshDbButton = $window.FindName('RefreshFromDbButton')
if ($refreshDbButton -and -not $script:RefreshDbHandlerAttached) {
    $refreshDbButton.Add_Click({
        param($sender,$e)
        # Emit telemetry for the action
        $site = Get-SelectedSiteFilterValue -Window $window
        Publish-UserActionTelemetry -Action 'RefreshFromDb' -Site $site
        # Reload from database without parsing
        Invoke-DatabaseImport -Window $window
    })
    $script:RefreshDbHandlerAttached = $true
}

if ($hostnameDropdown -and -not $script:HostnameHandlerAttached) {
    $hostnameDropdown.Add_SelectionChanged({
        param($sender,$e)
        $sel = [string]$sender.SelectedItem
        Get-HostnameChanged -Hostname $sel
        # Update freshness indicator to show device-specific timestamp
        try { Update-FreshnessIndicator -Window $window } catch { }
        # Persist last selected hostname for session restore
        if (-not $global:ProgrammaticHostnameUpdate -and $sel) {
            try {
                if (-not $script:StateTraceSettings) { $script:StateTraceSettings = @{} }
                $script:StateTraceSettings['LastHostname'] = $sel
                Save-StateTraceSettings -Settings $script:StateTraceSettings
            } catch { }
            # Add to recent devices list
            try {
                if (-not $script:RecentDevices) { $script:RecentDevices = @() }
                # Remove if already in list, then add to front
                $script:RecentDevices = @($sel) + @($script:RecentDevices | Where-Object { $_ -ne $sel }) | Select-Object -First 10
                # Update the dropdown
                $recentDD = $window.FindName('RecentDevicesDropdown')
                if ($recentDD) {
                    $recentDD.Items.Clear()
                    foreach ($device in $script:RecentDevices) {
                        [void]$recentDD.Items.Add($device)
                    }
                }
            } catch { }
        }
    })
    $script:HostnameHandlerAttached = $true
}

# Wire up Recent Devices dropdown to allow jumping to a device
$recentDevicesDropdown = $window.FindName('RecentDevicesDropdown')
if ($recentDevicesDropdown -and -not $script:RecentDevicesHandlerAttached) {
    $recentDevicesDropdown.Add_SelectionChanged({
        param($sender,$e)
        $sel = [string]$sender.SelectedItem
        if ($sel -and -not $global:ProgrammaticHostnameUpdate) {
            # Set the hostname dropdown to this device
            $hostDD = $window.FindName('HostnameDropdown')
            if ($hostDD) {
                $global:ProgrammaticHostnameUpdate = $true
                try {
                    $hostDD.SelectedItem = $sel
                } finally {
                    $global:ProgrammaticHostnameUpdate = $false
                }
                Get-HostnameChanged -Hostname $sel
            }
        }
    })
    $script:RecentDevicesHandlerAttached = $true
}

# === END Main window control hooks (MainWindow.ps1) ===

# === BEGIN Filter dropdown hooks (MainWindow.ps1) ===

# Debounced updater so cascaded changes trigger a single refresh.
if (-not $script:FilterUpdateTimer) {
    # Create a debounced timer for device filter updates.  The interval was
    $script:FilterUpdateTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:FilterUpdateTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $script:FilterUpdateTimer.add_Tick({
        $script:FilterUpdateTimer.Stop()
        try {
            # Refresh device filter using the unified helper
            Update-DeviceFilter

            # Keep Compare in sync with current filters/hosts
            if ($global:InterfacesLoadAllowed -and (Test-OptionalCommandAvailable -Name 'Update-CompareView') -and (Test-CompareSidebarVisible -Window $window)) {
                try { Update-CompareView -Window $window | Out-Null } catch {}
            }
        } catch {
            $emsg = $_.Exception.Message
            $pos  = ''
            try { $pos = $_.InvocationInfo.PositionMessage } catch { }
            $stk  = ''
            try { $stk = $_.ScriptStackTrace } catch { }
            # Log to UI and diagnostics log
            Write-Warning ("Device filter update failed: {0}" -f $emsg)
            Write-Diag ("Filter fail | LangMode={0} | FQEID={1} | Cat={2}" -f $ExecutionContext.SessionState.LanguageMode, $_.FullyQualifiedErrorId, $_.CategoryInfo)
            if ($pos) { Write-Diag ("Position: " + ($pos -replace "`r?`n", " | ")) }
            if ($stk) { Write-Diag ("Stack: " + ($stk -replace "`r?`n", " | ")) }
            # Mark the filter updater as faulted to prevent repeated attempts.  The
            # DeviceFilterUpdating flag prevents concurrent calls, but a recurrent
            # failure can still result in an endless loop if we keep retrying.
            FilterStateModule\Set-FilterFaulted -Faulted $true
        }
    })
}

function Request-DeviceFilterUpdate {
    # Do not re-arm the filter timer if a prior invocation has faulted or if we are
    # performing a programmatic dropdown update.  When the filter state is marked
    # faulted (set by the timer catch handler), we suppress all further filter
    # updates to avoid an endless loop.  When $global:ProgrammaticFilterUpdate
    # is true (set by Update-DeviceFilter while repopulating dropdowns), we
    # ignore user-initiated selection events to prevent recursive updates.
    if ((FilterStateModule\Get-FilterFaulted) -or $global:ProgrammaticFilterUpdate) {
        Write-Diag "Request-DeviceFilterUpdate suppressed (faulted or programmatic update)"
        return
    }
    # Restart the timer; successive calls coalesce into one update
    $script:FilterUpdateTimer.Stop()
    $script:FilterUpdateTimer.Start()
    if ($window) {
        try { Update-FreshnessIndicator -Window $window } catch { }
    }
}

# Track which controls we've already wired to avoid duplicate subscriptions.
if (-not $script:FilterHandlers) { $script:FilterHandlers = @{} }

function Get-FilterDropdowns {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Windows.Window]$Window)

    # Include ZoneDropdown alongside Site, Building and Room so that changing
    # zone triggers the debounced filter update as well.
    foreach ($name in 'SiteDropdown','ZoneDropdown','BuildingDropdown','RoomDropdown') {
        if ($script:FilterHandlers.ContainsKey($name)) { continue }
        $ctrl = $Window.FindName($name)
        if ($ctrl) {
            $ctrl.Add_SelectionChanged({ Request-DeviceFilterUpdate })
            $script:FilterHandlers[$name] = $true
        }
    }

    # Add site persistence handler (separate from filter update to preserve session)
    $siteDD = $Window.FindName('SiteDropdown')
    if ($siteDD -and -not $script:FilterHandlers.ContainsKey('SiteDropdown_Persist')) {
        $siteDD.Add_SelectionChanged({
            param($sender,$e)
            if (-not $global:ProgrammaticFilterUpdate) {
                $sel = $null
                try { $sel = [string]$sender.SelectedItem } catch { }
                if ($sel) {
                    try {
                        if (-not $script:StateTraceSettings) { $script:StateTraceSettings = @{} }
                        $script:StateTraceSettings['LastSite'] = $sel
                        Save-StateTraceSettings -Settings $script:StateTraceSettings
                    } catch { }
                }
            }
        })
        $script:FilterHandlers['SiteDropdown_Persist'] = $true
    }
}

# Wire them now (safe to call multiple times; wiring is idempotent)
Get-FilterDropdowns -Window $window

# === END Filter dropdown hooks (MainWindow.ps1) ===

# Hook up ShowCisco and ShowBrocade buttons to copy show command sequences
$showCiscoBtn   = $window.FindName('ShowCiscoButton')
$showBrocadeBtn = $window.FindName('ShowBrocadeButton')
$brocadeOSDD    = $window.FindName('BrocadeOSDropdown')
if ($brocadeOSDD) { Set-BrocadeOSFromConfig -Dropdown $brocadeOSDD }

if ($showCiscoBtn) {
    $showCiscoBtn.Add_Click({
        try {
            $cmds = Get-ShowCommands -Vendor 'Cisco'
            if (-not $cmds -or $cmds.Count -eq 0) {
                [System.Windows.MessageBox]::Show("No Cisco show commands found in ShowCommands.json.")
                return
            }
            Set-Clipboard -Value ($cmds -join "`r`n")
            [System.Windows.MessageBox]::Show(("Copied {0} Cisco command(s) to clipboard." -f $cmds.Count))
        } catch {
            [System.Windows.MessageBox]::Show("Show commands configuration error:`n$($_.Exception.Message)")
        }
})
}

if ($showBrocadeBtn) {
    $showBrocadeBtn.Add_Click({
        try {
            # Determine the selected OS version from dropdown.  Default to the current
            # Brocade OS group used in ShowCommands.json (8.3 and above) if no selection
            # is made.  The available versions are dynamically populated into the
            # BrocadeOSDropdown via Set-ShowCommandsOSVersions.
            $osVersion = '8.3 and above'
            if ($brocadeOSDD -and $brocadeOSDD.SelectedItem) {
                $sel = $brocadeOSDD.SelectedItem
                if ($sel -is [System.Windows.Controls.ComboBoxItem]) { $osVersion = '' + $sel.Content } else { $osVersion = '' + $sel }
            }
            $cmds = Get-ShowCommands -Vendor 'Brocade' -OSVersion $osVersion
            if (-not $cmds -or $cmds.Count -eq 0) {
                [System.Windows.MessageBox]::Show(("No Brocade show commands found for OS {0} in ShowCommands.json." -f $osVersion))
                return
            }
            Set-Clipboard -Value ($cmds -join "`r`n")
            [System.Windows.MessageBox]::Show(("Copied {0} Brocade command(s) to clipboard for {1}." -f $cmds.Count, $osVersion))
        } catch {
            [System.Windows.MessageBox]::Show("Show commands configuration error:`n$($_.Exception.Message)")
        }
})
}

# Help button: open the help window when clicked.
$helpBtn = $window.FindName('HelpButton')
if ($helpBtn) {
    $helpBtn.Add_Click({
        $helpXamlPath = Join-Path $scriptDir '..\Views\HelpWindow.xaml'
        if (-not (Test-Path $helpXamlPath)) {
            [System.Windows.MessageBox]::Show('Help file not found.')
            return
        }
        try {
            Publish-UserActionTelemetry -Action 'HelpOpened' -Site (Get-SelectedSiteFilterValue -Window $window) -Hostname (Get-SelectedHostname -Window $window) -Context 'MainWindow'
            $helpXaml   = Get-Content $helpXamlPath -Raw
            $helpReader = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($helpXaml))
            $helpWin    = [Windows.Markup.XamlReader]::Load($helpReader)
            # Set owner so the help window centres relative to main window
            $helpWin.Owner = $window

            # Wire up navigation sidebar
            $helpNavList = $helpWin.FindName('HelpNavList')
            $helpContentPanel = $helpWin.FindName('HelpContentPanel')

            # Map of section tags to section names
            $sectionMap = @{
                'quickstart'      = 'QuickStartSection'
                'overview'        = 'OverviewSection'
                'mainwindow'      = 'MainWindowSection'
                'interfaces'      = 'InterfacesSection'
                'compare'         = 'CompareSection'
                'search'          = 'SearchSection'
                'summary'         = 'SummarySection'
                'portreorg'       = 'PortReorgSection'
                'alerts'          = 'AlertsSection'
                'span'            = 'SpanSection'
                'documentation'   = 'DocumentationSection'
                'infrastructure'  = 'InfrastructureSection'
                'operations'      = 'OperationsSection'
                'tools'           = 'ToolsSection'
                'themes'          = 'ThemesSection'
                'shortcuts'       = 'ShortcutsSection'
                'troubleshooting' = 'TroubleshootingSection'
                'faq'             = 'FAQSection'
                'glossary'        = 'GlossarySection'
            }

            # Function to show a specific section
            $showSection = {
                param($sectionTag)
                foreach ($child in $helpContentPanel.Children) {
                    if ($child -is [System.Windows.Controls.StackPanel] -and $child.Name) {
                        $child.Visibility = [System.Windows.Visibility]::Collapsed
                    }
                }
                $sectionName = $sectionMap[$sectionTag]
                if ($sectionName) {
                    $section = $helpWin.FindName($sectionName)
                    if ($section) {
                        $section.Visibility = [System.Windows.Visibility]::Visible
                    }
                }
            }

            # Handle navigation selection changes
            if ($helpNavList) {
                $helpNavList.Add_SelectionChanged({
                    param($sender, $e)
                    $selectedItem = $sender.SelectedItem
                    if ($selectedItem -and $selectedItem.Tag) {
                        & $showSection $selectedItem.Tag
                    }
                }.GetNewClosure())
            }

            # Wire up search functionality
            $helpSearchBox = $helpWin.FindName('HelpSearchBox')
            if ($helpSearchBox) {
                $helpSearchBox.Add_TextChanged({
                    param($sender, $e)
                    $searchText = $sender.Text.ToLower().Trim()
                    if ([string]::IsNullOrWhiteSpace($searchText)) {
                        # Show all nav items when search is cleared
                        foreach ($item in $helpNavList.Items) {
                            $item.Visibility = [System.Windows.Visibility]::Visible
                        }
                        return
                    }
                    # Filter nav items based on search text
                    foreach ($item in $helpNavList.Items) {
                        $itemText = $item.Content.ToString().ToLower()
                        $itemTag = $item.Tag.ToString().ToLower()
                        if ($itemText.Contains($searchText) -or $itemTag.Contains($searchText)) {
                            $item.Visibility = [System.Windows.Visibility]::Visible
                        } else {
                            $item.Visibility = [System.Windows.Visibility]::Collapsed
                        }
                    }
                }.GetNewClosure())
            }

            $helpWin.ShowDialog() | Out-Null
        } catch {
            [System.Windows.MessageBox]::Show("Failed to load help: $($_.Exception.Message)")
        }
    })
}

$debugNextToggle = $window.FindName('DebugNextLaunchCheckbox')
if ($debugNextToggle) {
    $initialDebug = $false
    if ($script:StateTraceSettings.ContainsKey('DebugOnNextLaunch')) {
        $initialDebug = [bool]$script:StateTraceSettings['DebugOnNextLaunch']
    }
    $debugNextToggle.IsChecked = $initialDebug

    $updateDebugPreference = {
        param($sender, $eventArgs)
        try {
            $checked = $sender.IsChecked -eq $true
            if (-not $script:StateTraceSettings) { $script:StateTraceSettings = @{} }
            $script:StateTraceSettings['DebugOnNextLaunch'] = $checked
            Save-StateTraceSettings -Settings $script:StateTraceSettings
            $Global:StateTraceDebug = $checked
        } catch { }
    }

    $debugNextToggle.Add_Checked($updateDebugPreference)
    $debugNextToggle.Add_Unchecked($updateDebugPreference)
}

# === BEGIN Window Loaded handler ===
$window.Add_Loaded({
    try {
        Write-StartupDiag "Loaded: cwd=$(Get-Location); scriptDir=$scriptDir"
        if ($global:StateTraceDb) { $env:StateTraceDbPath = $global:StateTraceDb }
        try {
            $sitesAvailable = @()
            try { $sitesAvailable = Get-AvailableSiteNames } catch { $sitesAvailable = @() }
            Write-StartupDiag ("Get-AvailableSiteNames -> {0}" -f (($sitesAvailable) -join ', '))
            Populate-SiteDropdownWithAvailableSites -Window $window
            $siteDD = $window.FindName('SiteDropdown')
            if ($siteDD) {
                $items = @($siteDD.ItemsSource)
                Write-StartupDiag ("After Populate-SiteDropdownWithAvailableSites items={0}" -f ($items -join ', '))
            }
        } catch { Write-StartupDiag ("Populate-SiteDropdownWithAvailableSites failed: {0}" -f $_.Exception.Message) }
        try {
            $locationEntries = @()
            try { $locationEntries = DeviceCatalogModule\Get-DeviceLocationEntries } catch { $locationEntries = @() }
            Write-StartupDiag ("Location entries count={0}; sample={1}" -f $locationEntries.Count, (($locationEntries | Select-Object -First 3 | ForEach-Object { "Site=$($_.Site);Zone=$($_.Zone);Building=$($_.Building);Room=$($_.Room)" }) -join ' | '))
            Initialize-FilterMetadataAtStartup -Window $window -LocationEntries $locationEntries
            $siteDD2 = $window.FindName('SiteDropdown')
            if ($siteDD2) {
                $items2 = @($siteDD2.ItemsSource)
                Write-StartupDiag ("After Initialize-FilterMetadataAtStartup items={0}" -f ($items2 -join ', '))
            }
            try {
                $locCount = 0
                try { $locCount = $global:DeviceLocationEntries.Count } catch { }
                Write-StartupDiag ("Global DeviceLocationEntries count={0}" -f $locCount)
                $snap = Invoke-OptionalCommandSafe -Name 'ViewStateService\Get-FilterSnapshot' -Parameters @{
                    DeviceMetadata  = $global:DeviceMetadata
                    LocationEntries = $global:DeviceLocationEntries
                }
                if ($snap) {
                    $sitesLog      = @($snap.Sites) -join ', '
                    $zonesLog      = @($snap.Zones) -join ', '
                    $buildingsLog  = @($snap.Buildings) -join ', '
                    $roomsLog      = @($snap.Rooms) -join ', '
                    $hostsLog      = @($snap.Hostnames) -join ', '
                    $zoneToLoadLog = if ($snap.ZoneToLoad) { '' + $snap.ZoneToLoad } else { '' }
                    Write-StartupDiag ("FilterSnapshot sites=[{0}] zones=[{1}] buildings=[{2}] rooms=[{3}] hosts=[{4}] zoneToLoad={5}" -f $sitesLog, $zonesLog, $buildingsLog, $roomsLog, $hostsLog, $zoneToLoadLog)
                }
            } catch { Write-StartupDiag ("FilterSnapshot probe failed: {0}" -f $_.Exception.Message) }
        } catch { Write-StartupDiag ("Initialize-FilterMetadataAtStartup failed: {0}" -f $_.Exception.Message) }

        # Restore last selected site and hostname from settings
        try {
            if ($script:StateTraceSettings) {
                $lastSite = $script:StateTraceSettings['LastSite']
                $lastHost = $script:StateTraceSettings['LastHostname']
                Write-StartupDiag ("Restoring session: LastSite={0} LastHostname={1}" -f $lastSite, $lastHost)

                if ($lastSite) {
                    $siteDD = $window.FindName('SiteDropdown')
                    if ($siteDD -and $siteDD.ItemsSource) {
                        $items = @($siteDD.ItemsSource)
                        if ($items -contains $lastSite) {
                            $global:ProgrammaticFilterUpdate = $true
                            try {
                                $siteDD.SelectedItem = $lastSite
                                Write-StartupDiag ("Restored site selection: {0}" -f $lastSite)
                            } finally {
                                $global:ProgrammaticFilterUpdate = $false
                            }
                        }
                    }
                }

                if ($lastHost) {
                    $hostDD = $window.FindName('HostnameDropdown')
                    if ($hostDD -and $hostDD.ItemsSource) {
                        $items = @($hostDD.ItemsSource)
                        if ($items -contains $lastHost) {
                            $global:ProgrammaticHostnameUpdate = $true
                            try {
                                $hostDD.SelectedItem = $lastHost
                                Write-StartupDiag ("Restored hostname selection: {0}" -f $lastHost)
                            } finally {
                                $global:ProgrammaticHostnameUpdate = $false
                            }
                        }
                    }
                }
            }
        } catch { Write-StartupDiag ("Session restore failed: {0}" -f $_.Exception.Message) }

        Ensure-ParserStatusTimer -Window $window
        Update-ParserStatusIndicator -Window $window
        try { Update-FreshnessIndicator -Window $window } catch { }
        try { Update-PipelineHealthIndicator -Window $window } catch { }
        try {
            $null = Invoke-OptionalCommandSafe -Name 'InterfaceModule\Set-HostLoadingIndicator' -Parameters @{ State = 'Hidden' }
        } catch {}
    } catch {
        Write-Warning ("Initialization failed: {0}" -f $_.Exception.Message)
    }
})
# === END Window Loaded handler ===

# 7b) Window Closing handler - cleanup timers and runspaces
$window.Add_Closing({
    param($sender, $e)
    try {
        # Stop timers
        if ($script:ParserStatusTimer) { try { $script:ParserStatusTimer.Stop() } catch {} }
        if ($script:FilterUpdateTimer) { try { $script:FilterUpdateTimer.Stop() } catch {} }

        # Dispose runspaces
        if ($script:DeviceDetailsRunspace) {
            try { $script:DeviceDetailsRunspace.Close() } catch {}
            try { $script:DeviceDetailsRunspace.Dispose() } catch {}
        }
        if ($script:DatabaseImportRunspace) {
            try { $script:DatabaseImportRunspace.Close() } catch {}
            try { $script:DatabaseImportRunspace.Dispose() } catch {}
        }

        # Stop any module-level timers
        try {
            $searchTimer = Get-Variable -Name 'SearchUpdateTimer' -Scope Script -ErrorAction SilentlyContinue
            if ($searchTimer -and $searchTimer.Value) { $searchTimer.Value.Stop() }
        } catch {}
    } catch {}
})

# 7c) Quick Navigation Dialog helper
function Show-QuickNavigationDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Window]$ParentWindow
    )

    # Define navigation items: main tabs and sub-tabs
    $allItems = @(
        [PSCustomObject]@{ Shortcut = 'Ctrl+1'; Display = 'Summary'; MainTab = 0; SubTab = -1 }
        [PSCustomObject]@{ Shortcut = 'Ctrl+2'; Display = 'Interfaces'; MainTab = 1; SubTab = -1 }
        [PSCustomObject]@{ Shortcut = 'Ctrl+3'; Display = 'SPAN'; MainTab = 2; SubTab = -1 }
        [PSCustomObject]@{ Shortcut = 'Ctrl+4'; Display = 'Search'; MainTab = 3; SubTab = -1 }
        [PSCustomObject]@{ Shortcut = 'Ctrl+5'; Display = 'Alerts'; MainTab = 4; SubTab = -1 }
        [PSCustomObject]@{ Shortcut = 'Ctrl+6'; Display = 'Docs > Generator'; MainTab = 5; SubTab = 0 }
        [PSCustomObject]@{ Shortcut = ''; Display = 'Docs > Config Templates'; MainTab = 5; SubTab = 1 }
        [PSCustomObject]@{ Shortcut = ''; Display = 'Docs > Templates'; MainTab = 5; SubTab = 2 }
        [PSCustomObject]@{ Shortcut = ''; Display = 'Docs > Cmd Reference'; MainTab = 5; SubTab = 3 }
        [PSCustomObject]@{ Shortcut = 'Ctrl+7'; Display = 'Infra > Topology'; MainTab = 6; SubTab = 0 }
        [PSCustomObject]@{ Shortcut = ''; Display = 'Infra > Cables'; MainTab = 6; SubTab = 1 }
        [PSCustomObject]@{ Shortcut = ''; Display = 'Infra > IPAM'; MainTab = 6; SubTab = 2 }
        [PSCustomObject]@{ Shortcut = ''; Display = 'Infra > Inventory'; MainTab = 6; SubTab = 3 }
        [PSCustomObject]@{ Shortcut = 'Ctrl+8'; Display = 'Ops > Changes'; MainTab = 7; SubTab = 0 }
        [PSCustomObject]@{ Shortcut = ''; Display = 'Ops > Capacity'; MainTab = 7; SubTab = 1 }
        [PSCustomObject]@{ Shortcut = ''; Display = 'Ops > Log Analysis'; MainTab = 7; SubTab = 2 }
        [PSCustomObject]@{ Shortcut = 'Ctrl+9'; Display = 'Tools > Troubleshoot'; MainTab = 8; SubTab = 0 }
        [PSCustomObject]@{ Shortcut = ''; Display = 'Tools > Calculator'; MainTab = 8; SubTab = 1 }
    )

    # Load dialog XAML
    $dialogXaml = Join-Path $scriptDir '..\Views\QuickNavigationDialog.xaml'
    if (-not (Test-Path $dialogXaml)) {
        Write-Warning "QuickNavigationDialog.xaml not found"
        return
    }

    try {
        $xamlContent = Get-Content -Path $dialogXaml -Raw
        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlContent))
        $dialog = [System.Windows.Markup.XamlReader]::Load($reader)
        $dialog.Owner = $ParentWindow

        # Get controls
        $searchBox = $dialog.FindName('SearchBox')
        $navList = $dialog.FindName('NavigationList')

        # Initialize list
        $navList.ItemsSource = $allItems
        $navList.SelectedIndex = 0

        # Filter on text change
        $searchBox.Add_TextChanged({
            param($s, $ev)
            $filter = $searchBox.Text.Trim().ToLower()
            if ([string]::IsNullOrEmpty($filter)) {
                $navList.ItemsSource = $allItems
            } else {
                $filtered = @($allItems | Where-Object { $_.Display.ToLower().Contains($filter) })
                $navList.ItemsSource = $filtered
            }
            if ($navList.Items.Count -gt 0) {
                $navList.SelectedIndex = 0
            }
        })

        # Navigate on Enter or double-click
        $navigateAction = {
            $selected = $navList.SelectedItem
            if ($selected) {
                $mainTab = $ParentWindow.FindName('MainTabControl')
                if ($mainTab -and $selected.MainTab -ge 0) {
                    $mainTab.SelectedIndex = $selected.MainTab

                    # Handle sub-tab navigation
                    if ($selected.SubTab -ge 0) {
                        $containerNames = @{
                            5 = 'DocumentationContainerHost'
                            6 = 'InfrastructureContainerHost'
                            7 = 'OperationsContainerHost'
                            8 = 'ToolsContainerHost'
                        }
                        $tabControlNames = @{
                            5 = 'DocumentationTabControl'
                            6 = 'InfrastructureTabControl'
                            7 = 'OperationsTabControl'
                            8 = 'ToolsTabControl'
                        }
                        $containerName = $containerNames[$selected.MainTab]
                        $tabControlName = $tabControlNames[$selected.MainTab]
                        if ($containerName -and $tabControlName) {
                            $containerHost = $ParentWindow.FindName($containerName)
                            if ($containerHost -and $containerHost.Content) {
                                $subTabControl = $containerHost.Content.FindName($tabControlName)
                                if ($subTabControl) {
                                    $subTabControl.SelectedIndex = $selected.SubTab
                                }
                            }
                        }
                    }
                }
                $dialog.Close()
            }
        }

        $searchBox.Add_KeyDown({
            param($s, $ev)
            switch ($ev.Key) {
                'Return' {
                    & $navigateAction
                    $ev.Handled = $true
                }
                'Down' {
                    if ($navList.SelectedIndex -lt ($navList.Items.Count - 1)) {
                        $navList.SelectedIndex++
                    }
                    $ev.Handled = $true
                }
                'Up' {
                    if ($navList.SelectedIndex -gt 0) {
                        $navList.SelectedIndex--
                    }
                    $ev.Handled = $true
                }
                'Escape' {
                    $dialog.Close()
                    $ev.Handled = $true
                }
            }
        })

        $navList.Add_MouseDoubleClick({
            param($s, $ev)
            & $navigateAction
        })

        $navList.Add_KeyDown({
            param($s, $ev)
            if ($ev.Key -eq 'Return') {
                & $navigateAction
                $ev.Handled = $true
            } elseif ($ev.Key -eq 'Escape') {
                $dialog.Close()
                $ev.Handled = $true
            }
        })

        # Close on Escape at window level
        $dialog.Add_KeyDown({
            param($s, $ev)
            if ($ev.Key -eq 'Escape') {
                $dialog.Close()
                $ev.Handled = $true
            }
        })

        # Focus search box when dialog opens
        $dialog.Add_Loaded({
            $searchBox.Focus()
        })

        $null = $dialog.ShowDialog()
    } catch {
        Write-Warning ("Quick navigation dialog failed: {0}" -f $_.Exception.Message)
    }
}

# 7d) Keyboard shortcuts - Ctrl+1-9 for tab switching, Ctrl+J/F/T for navigation
$window.Add_PreviewKeyDown({
    param($sender, $e)

    $tabControl = $sender.FindName('MainTabControl')

    # Handle Escape key (no modifier required)
    if ($e.Key -eq 'Escape') {
        # Clear filter boxes if they have focus or content
        $filterBox = $global:filterBox
        if ($filterBox -and $filterBox.Text) {
            $filterBox.Text = ''
            $e.Handled = $true
            return
        }
        # Clear search box in SearchInterfacesView
        try {
            $searchHost = $sender.FindName('SearchInterfacesHost')
            if ($searchHost -and $searchHost.Content) {
                $searchBox = $searchHost.Content.FindName('SearchBox')
                if ($searchBox -and $searchBox.Text) {
                    $searchBox.Text = ''
                    $e.Handled = $true
                    return
                }
            }
        } catch { }
        return
    }

    # Only handle Ctrl shortcuts below this point
    if (-not [System.Windows.Input.Keyboard]::Modifiers.HasFlag([System.Windows.Input.ModifierKeys]::Control)) {
        return
    }

    if (-not $tabControl) { return }

    $tabIndex = -1
    switch ($e.Key) {
        'D1' { $tabIndex = 0 }  # Ctrl+1: Summary
        'D2' { $tabIndex = 1 }  # Ctrl+2: Interfaces
        'D3' { $tabIndex = 2 }  # Ctrl+3: SPAN
        'D4' { $tabIndex = 3 }  # Ctrl+4: Search
        'D5' { $tabIndex = 4 }  # Ctrl+5: Alerts
        'D6' { $tabIndex = 5 }  # Ctrl+6: Docs
        'D7' { $tabIndex = 6 }  # Ctrl+7: Infra
        'D8' { $tabIndex = 7 }  # Ctrl+8: Ops
        'D9' { $tabIndex = 8 }  # Ctrl+9: Tools
        'J' {
            # Ctrl+J: Show quick navigation menu
            Show-QuickNavigationDialog -ParentWindow $sender
            $e.Handled = $true
            return
        }
        'F' {
            # Ctrl+F: Switch to Search tab and focus search box
            $tabControl.SelectedIndex = 3  # Search tab
            try {
                $searchHost = $sender.FindName('SearchInterfacesHost')
                if ($searchHost -and $searchHost.Content) {
                    $searchBox = $searchHost.Content.FindName('SearchBox')
                    if ($searchBox) {
                        $searchBox.Focus()
                        $searchBox.SelectAll()
                    }
                }
            } catch { }
            $e.Handled = $true
            return
        }
        'T' {
            # Ctrl+T: Focus hostname dropdown for quick device selection
            $hostDD = $sender.FindName('HostnameDropdown')
            if ($hostDD) {
                $hostDD.Focus()
                $hostDD.IsDropDownOpen = $true
            }
            $e.Handled = $true
            return
        }
        'G' {
            # Ctrl+G: Focus filter box on current view (Interfaces tab)
            $filterBox = $global:filterBox
            if ($filterBox) {
                $filterBox.Focus()
                $filterBox.SelectAll()
            }
            $e.Handled = $true
            return
        }
    }

    if ($tabIndex -ge 0 -and $tabIndex -lt $tabControl.Items.Count) {
        $tabControl.SelectedIndex = $tabIndex
        $e.Handled = $true
    }
})

# 8) Show window
$window.ShowDialog() | Out-Null

# 9) Cleanup and exit
exit 0
