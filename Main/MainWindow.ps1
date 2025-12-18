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

function Write-Diag {
    param([string]$Message)
    if (-not $Global:StateTraceDebug) { return }
    try {
        $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        $line = "[$ts] $Message"
        Write-Verbose $line
        if ($script:DiagLogPath) {
            Add-Content -LiteralPath $script:DiagLogPath -Value $line -ErrorAction SilentlyContinue
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

if (-not (Get-Variable -Name DeviceDetailsRunspaceLock -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DeviceDetailsRunspaceLock = New-Object System.Threading.SemaphoreSlim 1, 1
}
if (-not (Get-Variable -Name DeviceDetailsRunspace -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DeviceDetailsRunspace = $null
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
    $params = @{ Window = $Window }
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
        'New-TemplatesView',
        'New-AlertsView'
        # 'Update-CompareView'  # deferred until after Update-DeviceFilter
    )

    # Auto-discover any additional New-*View commands, excluding Compare for now
    # Exclude helper commands that require extra mandatory parameters
    $excludeInitially = @('Update-CompareView')
    $discovered = Get-OptionalCommandSafe -Name 'New-*View' | Select-Object -ExpandProperty Name
    if ($discovered) {
        $extra = $discovered | Where-Object { ($viewsInOrder -notcontains $_) -and ($_ -notin $excludeInitially) }
        foreach ($v in ($extra | Sort-Object)) { $viewsInOrder += $v }
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
    $siteNames = [System.Collections.Generic.List[string]]::new()
    Get-ChildItem -LiteralPath $dataDir -Directory | ForEach-Object {
        $siteName = $_.Name
        $dbPath = Join-Path $_.FullName ("{0}.accdb" -f $siteName)
        if (Test-Path -LiteralPath $dbPath) {
            if (-not $siteNames.Contains($siteName)) { [void]$siteNames.Add($siteName) }
        }
    }

    # Fallback: include any .accdb files found anywhere under Data so non-nested
    # site databases still appear in the dropdown.
    Get-ChildItem -LiteralPath $dataDir -Filter '*.accdb' -File -Recurse | ForEach-Object {
        $leaf = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        if ([string]::IsNullOrWhiteSpace($leaf)) { return }
        if (-not $siteNames.Contains($leaf)) { [void]$siteNames.Add($leaf) }
    }

    return ($siteNames | Sort-Object -Unique)
}

function Populate-SiteDropdownWithAvailableSites {
    param(
        [Windows.Window]$Window,
        [string]$PreferredSelection,
        [switch]$PreserveExistingSelection
    )
    if (-not $Window) { return }
    $siteDropdown = $Window.FindName('SiteDropdown')
    if (-not $siteDropdown) { return }
    $sites = Get-AvailableSiteNames
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

function Update-ParserStatusIndicator {
    param([Windows.Window]$Window)
    $indicator = Get-ParserStatusControl -Window $Window
    if (-not $indicator) { return }

    if (-not $script:CurrentParserJob) {
        $indicator.Content = 'Parser idle'
        Set-ParserDetailText -Window $Window -Text ''
        if ($script:ParserStatusTimer) { $script:ParserStatusTimer.Stop() }
        return
    }

    $state = $script:CurrentParserJob.State
    if ($state -eq 'Running' -or $state -eq 'NotStarted') {
        $started = $null
        try { if ($script:ParserJobStartedAt) { $started = $script:ParserJobStartedAt.ToString('HH:mm:ss') } } catch { }
        if ($started) {
            $indicator.Content = "Parsing in progress (started $started)"
        } else {
            $indicator.Content = 'Parsing in progress...'
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
            $indicator.Content = ("Parsing finished at {0} (log: {1})" -f $stamp, $logPath)
        } else {
            $indicator.Content = "Parsing finished at $stamp"
        }
        $refreshFilter = $script:ParserPendingSiteFilter
        $script:ParserPendingSiteFilter = $null
        try { Initialize-DeviceViewFromCatalog -Window $Window -SiteFilter $refreshFilter } catch { }
        try { Populate-SiteDropdownWithAvailableSites -Window $Window -PreferredSelection $refreshFilter -PreserveExistingSelection } catch { }
        try { Update-FreshnessIndicator -Window $Window } catch { }
    } else {
        if ($logPath) {
            $indicator.Content = ("Parsing {0}. See {1}" -f $state.ToLower(), $logPath)
        } else {
            $indicator.Content = ("Parsing {0}" -f $state.ToLower())
        }
        $script:ParserPendingSiteFilter = $null
    }

    $script:ParserJobLogPath = $null
    Set-ParserDetailText -Window $Window -Text ''
    if ($script:ParserStatusTimer) { $script:ParserStatusTimer.Stop() }
}

function Get-SiteIngestionInfo {
    param([string]$Site)
    if ([string]::IsNullOrWhiteSpace($Site)) { return $null }
    $historyPath = Join-Path $scriptDir "..\Data\IngestionHistory\$Site.json"
    if (-not (Test-Path -LiteralPath $historyPath)) { return $null }
    $entries = $null
    try { $entries = Get-Content -LiteralPath $historyPath -Raw | ConvertFrom-Json } catch { $entries = $null }
    if (-not $entries) { return $null }
    $latest = $entries | Where-Object { $_.LastIngestedUtc } | Sort-Object { $_.LastIngestedUtc } -Descending | Select-Object -First 1
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
        $parsed = @()
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $parsed += ($line | ConvertFrom-Json -ErrorAction Stop) } catch { }
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
    if (-not $label) { return }

    $site = Get-SiteFilterSelection -Window $Window
    if (-not $site) {
        $label.Content = 'Freshness: select a site'
        return
    }

    $info = Get-SiteIngestionInfo -Site $site
    if (-not $info) {
        $label.Content = "Freshness: no history for $site"
        $label.ToolTip = "No ingestion history found under Data\\IngestionHistory\\$site.json"
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

    $providerInfo = Get-SiteCacheProviderFromMetrics -Site $site
    $providerText = if ($providerInfo) {
        if ($providerInfo.Reason) { "{0} ({1})" -f $providerInfo.Provider, $providerInfo.Reason } else { $providerInfo.Provider }
    } else {
        $info.Source
    }
    $label.Content = "Freshness: $site @ $($localTime.ToString('g')) ($ageText, source $providerText)"

    $tooltipParts = [System.Collections.Generic.List[string]]::new()
    $tooltipParts.Add("Ingestion history: $($info.HistoryPath)") | Out-Null
    if ($providerInfo) {
        $tooltipParts.Add("Metrics: $($providerInfo.MetricsLog)") | Out-Null
        $tooltipParts.Add("Provider: $($providerInfo.Provider)") | Out-Null
        if ($providerInfo.Reason) { $tooltipParts.Add("Reason: $($providerInfo.Reason)") | Out-Null }
        if ($providerInfo.Timestamp) { $tooltipParts.Add("Telemetry at: $($providerInfo.Timestamp.ToString('g'))") | Out-Null }
    }
    $label.ToolTip = [string]::Join("`n", $tooltipParts)
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
        [string]$SiteFilter
    )

    # Call the unified device helper functions directly (no module qualifier).
    $catalog = $null
    try {
        if ([string]::IsNullOrWhiteSpace($SiteFilter)) {
            $catalog = Get-DeviceSummaries
        } else {
            $catalog = Get-DeviceSummaries -SiteFilter $SiteFilter
        }
    } catch { $catalog = $null }
    $hostList = @()
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
        if ($hostList -and $hostList.Count -gt 0) {
            Initialize-DeviceFilters -Hostnames $hostList -Window $Window
        } else {
            Initialize-DeviceFilters -Window $Window
            $null = Invoke-OptionalCommandSafe -Name 'InterfaceModule\Set-HostLoadingIndicator' -Parameters @{ State = 'Hidden' }
        }
    } catch {}

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

    if ((Test-OptionalCommandAvailable -Name 'Update-CompareView') -and (Test-CompareSidebarVisible -Window $Window)) {
        try { Update-CompareView -Window $Window | Out-Null }
        catch { Write-Warning ("Failed to refresh Compare view: {0}" -f $_.Exception.Message) }
    }

    try {
        $hostDD = $Window.FindName('HostnameDropdown')
        if ($hostDD -and $hostDD.Items -and $hostDD.Items.Count -gt 0 -and $hostDD.SelectedIndex -lt 0) {
            $hostDD.SelectedIndex = 0
        }
        $null = Invoke-OptionalCommandSafe -Name 'InterfaceModule\Set-HostLoadingIndicator' -Parameters @{ State = 'Hidden' }
    } catch {}
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
    param([Parameter(Mandatory)][Windows.Window]$Window)

    try {
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

        $siteFilterValue = Get-SelectedSiteFilterValue -Window $Window
        Initialize-DeviceViewFromCatalog -Window $Window -SiteFilter $siteFilterValue
        Populate-SiteDropdownWithAvailableSites -Window $Window -PreferredSelection $siteFilterValue -PreserveExistingSelection
        Publish-UserActionTelemetry -Action 'LoadFromDb' -Site $siteFilterValue -Hostname (Get-SelectedHostname -Window $Window) -Context 'MainWindow'
    } catch {
        try { $global:PendingFilterRestore = $null } catch {}
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

if ($hostnameDropdown -and -not $script:HostnameHandlerAttached) {
    $hostnameDropdown.Add_SelectionChanged({
        param($sender,$e)
        $sel = [string]$sender.SelectedItem
        Get-HostnameChanged -Hostname $sel
    })
    $script:HostnameHandlerAttached = $true
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
            $runbookPath = Join-Path $scriptDir '..\docs\StateTrace_Operators_Runbook.md'
            if (Test-Path -LiteralPath $runbookPath) {
                try {
                    $runbookUri    = [Uri]::new((Resolve-Path -LiteralPath $runbookPath).ProviderPath)
                    $quickstartUri = $runbookUri.AbsoluteUri + '#start-here-quickstart'
                    Start-Process -FilePath $quickstartUri -ErrorAction SilentlyContinue | Out-Null
                } catch {}
            }
            Publish-UserActionTelemetry -Action 'HelpQuickstart' -Site (Get-SelectedSiteFilterValue -Window $window) -Hostname (Get-SelectedHostname -Window $window) -Context 'MainWindow'
            $helpXaml   = Get-Content $helpXamlPath -Raw
            $helpReader = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($helpXaml))
            $helpWin    = [Windows.Markup.XamlReader]::Load($helpReader)
            # Set owner so the help window centres relative to main window
            $helpWin.Owner = $window
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
        Ensure-ParserStatusTimer -Window $window
        Update-ParserStatusIndicator -Window $window
        try { Update-FreshnessIndicator -Window $window } catch { }
        try {
            $null = Invoke-OptionalCommandSafe -Name 'InterfaceModule\Set-HostLoadingIndicator' -Parameters @{ State = 'Hidden' }
        } catch {}
    } catch {
        Write-Warning ("Initialization failed: {0}" -f $_.Exception.Message)
    }
})
# === END Window Loaded handler ===

# 8) Show window
$window.ShowDialog() | Out-Null

# 9) Cleanup
