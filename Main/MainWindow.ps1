Add-Type -AssemblyName PresentationFramework

$Global:StateTraceDebug     = $false
$VerbosePreference          = 'SilentlyContinue'
$DebugPreference            = 'SilentlyContinue'
$ErrorActionPreference      = 'Continue'

if (-not (Get-Variable -Name InterfacePortCollections -Scope Global -ErrorAction SilentlyContinue)) {
    $global:InterfacePortCollections = @{}
}


$scriptDir    = $PSScriptRoot
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
$script:StateTraceSettingsPath = Join-Path $scriptDir '..\Data\StateTraceSettings.json'

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
        if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null }
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
        $logRoot  = Join-Path $userDocs 'StateTrace\Logs'
        if (-not (Test-Path $logRoot)) {
            New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
        }
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

$manifestPath = Join-Path $scriptDir '..\Modules\ModulesManifest.psd1'

try {
    if (-not (Test-Path $manifestPath)) {
        throw "Module manifest not found at ${manifestPath}"
    }

    $manifest =
        if (Get-Command Import-PowerShellDataFile -ErrorAction SilentlyContinue) {
            Import-PowerShellDataFile -Path $manifestPath
        } else {
            . $manifestPath
        }

    $modulesToImport = @()
    if ($manifest.ModulesToImport) {
        $modulesToImport = $manifest.ModulesToImport
    } elseif ($manifest.Modules) {
        $modulesToImport = $manifest.Modules
    } else {
        throw "No ModulesToImport defined in manifest."
    }

    # Import each module listed in the manifest
    foreach ($mod in $modulesToImport) {
        $modulePath = Join-Path $scriptDir "..\Modules\$mod"
        $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($mod)
        Write-Host "Loading module: $mod"
        try {
            Import-Module -Name $modulePath -Force -ErrorAction Stop
        } catch {
            Write-Warning ("Failed to import module {0} from {1}: {2}" -f $moduleName, $modulePath, $_.Exception.Message)
            throw
        }
    }
}
catch {
    Write-Error "Failed to load modules from manifest: $($_.Exception.Message)"
    return
}

try {
    $dataDir = Join-Path $scriptDir '..\Data'
    if (-not (Test-Path $dataDir)) {
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    }
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
                return $script:DeviceDetailsRunspace
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
        $script:DeviceDetailsRunspace = $rs
        try { Write-Diag ("Device loader runspace created | Id={0}" -f $rs.Id) } catch {}
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

    $list = New-Object 'System.Collections.Generic.List[object]'
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
function Initialize-View {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CommandName,
        [Parameter(Mandatory)][Windows.Window]$Window,
        [Parameter(Mandatory)][string]$ScriptDir
    )

    $viewName = ((($CommandName -replace '^New-','') -replace 'View$',''))
    $cmd = Get-Command -Name $CommandName -ErrorAction SilentlyContinue
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
    $discovered = Get-Command -Name 'New-*View' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
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

function Invoke-StateTraceRefresh {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Windows.Window]$Window)

    try {
        # Read checkboxes fresh each time (safe if UI is rebuilt)
        $includeArchiveCB    = $Window.FindName('IncludeArchiveCheckbox')
        $includeHistoricalCB = $Window.FindName('IncludeHistoricalCheckbox')

        if ($includeArchiveCB)    { Set-EnvToggle -Name 'IncludeArchive'    -Checked ([bool]$includeArchiveCB.IsChecked) }
        if ($includeHistoricalCB) { Set-EnvToggle -Name 'IncludeHistorical' -Checked ([bool]$includeHistoricalCB.IsChecked) }

        if ($global:StateTraceDb) { $env:StateTraceDbPath = $global:StateTraceDb }

        $parseCmd = Get-Command Invoke-StateTraceParsing -ErrorAction SilentlyContinue
        if ($parseCmd) {
            Invoke-StateTraceParsing -Synchronous
        } else {
            Write-Error ("Invoke-StateTraceParsing not found (module load failed).")
        }

        # Call the unified device helper functions directly (no module qualifier).
        $catalog = $null
        try { $catalog = Get-DeviceSummaries } catch { $catalog = $null }
        try {
            $hostList = $null
            if ($catalog -and $catalog.PSObject.Properties['Hostnames']) { $hostList = $catalog.Hostnames }
            if ($hostList) {
                Initialize-DeviceFilters -Hostnames $hostList -Window $window
            } else {
                Initialize-DeviceFilters -Window $window
            }
        } catch {}
        Update-DeviceFilter
        # Rebuild Compare view so its host list reflects the new parse
        if (Get-Command -Name Update-CompareView -ErrorAction SilentlyContinue) {
            try { Update-CompareView -Window $window | Out-Null }
            catch { Write-Warning ("Failed to refresh Compare view: {0}" -f $_.Exception.Message) }
        }

    } catch {
        Write-Warning ("Refresh failed: {0}" -f $_.Exception.Message)
    }
}

function Show-DeviceDetails {
    [CmdletBinding()]
    param([Parameter()][string]$Hostname)

    $hostTrim = ('' + $Hostname).Trim()
    if ([string]::IsNullOrWhiteSpace($hostTrim)) { return }

    if (-not (Get-Command -Name 'DeviceDetailsModule\Get-DeviceDetails' -ErrorAction SilentlyContinue)) {
        try {
            $modPath = Join-Path $scriptDir '..\\Modules\\DeviceDetailsModule.psm1'
            if (Test-Path -LiteralPath $modPath) {
                Import-Module -Name $modPath -Global -ErrorAction Stop
            } else {
                Import-Module DeviceDetailsModule -ErrorAction Stop
            }
        } catch {
            Write-Warning ("Failed to import DeviceDetailsModule: {0}" -f $_.Exception.Message)
        }
    }

    $dto = $null
    try {
        $dto = DeviceDetailsModule\Get-DeviceDetails -Hostname $hostTrim
    } catch {
        [System.Windows.MessageBox]::Show("Error loading ${hostTrim}:`n$($_.Exception.Message)")
        return
    }
    if (-not $dto) {
        [System.Windows.MessageBox]::Show("No device details available for ${hostTrim}.")
        return
    }

    try {
        $cachedCollection = $null
        try {
            if ($global:InterfacePortCollections -and $global:InterfacePortCollections.ContainsKey($hostTrim)) {
                $cachedCollection = $global:InterfacePortCollections[$hostTrim]
            }
        } catch { $cachedCollection = $null }
        if ($cachedCollection) {
            try { $dto.Interfaces = $cachedCollection } catch {}
        }

        InterfaceModule\Set-InterfaceViewData -DeviceDetails $dto -DefaultHostname $hostTrim
        $initialCount = 0
        try { $initialCount = @($dto.Interfaces).Count } catch { $initialCount = 0 }
        try { Write-Diag ("Show-DeviceDetails applied | Host={0} | Interfaces={1}" -f $hostTrim, $initialCount) } catch {}
    } catch {
        Write-Warning ("Failed to apply device details for {0}: {1}" -f $hostTrim, $_.Exception.Message)
        try { Write-Diag ("Show-DeviceDetails failed | Host={0} | Error={1}" -f $hostTrim, $_.Exception.Message) } catch {}
    }
}

function Get-HostnameChanged {
    [CmdletBinding()]
    param([string]$Hostname)

    try {
        # Load device details synchronously.  Asynchronous invocation via
        if ($Hostname) {
            Show-DeviceDetails $Hostname
            try {
                Import-DeviceDetailsAsync -Hostname $Hostname
            } catch {
                Write-Warning ("Hostname change handler failed to queue async device load for {0}: {1}" -f $Hostname, $_.Exception.Message)
            }
            if (Get-Command Get-SpanInfo -ErrorAction SilentlyContinue) {
                Get-SpanInfo $Hostname
            }
        } else {
            # Clear span info when hostname is empty
            if (Get-Command Get-SpanInfo -ErrorAction SilentlyContinue) {
                Get-SpanInfo ''
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
    if ($debug) {
        Write-Verbose ("Import-DeviceDetailsAsync: called with Hostname='{0}'" -f $hostTrim)
    }
    try { Write-Diag ("Import-DeviceDetailsAsync start | Host={0}" -f $hostTrim) } catch {}
    # If no host is provided, clear span info and return
    if ([string]::IsNullOrWhiteSpace($hostTrim)) {
        if (Get-Command Get-SpanInfo -ErrorAction SilentlyContinue) {
            try { [System.Windows.Application]::Current.Dispatcher.Invoke([System.Action]{ Get-SpanInfo '' }) } catch {}
        }
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
param($hn, $modulesDir, $diagPath, $moduleList)
$diagStamp = {
    param($text)
    if (-not $diagPath) { return }
    try {
        $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        Add-Content -LiteralPath $diagPath -Value ("[{0}] {1}" -f $timestamp, $text) -ErrorAction SilentlyContinue
    } catch {}
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
                        # Load span info using vendor-specific helper if present
                        if (Get-Command Get-SpanInfo -ErrorAction SilentlyContinue) {
                            try { Get-SpanInfo $defaultHost } catch {}
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
                                if (-not (Get-Variable -Name InterfacePortCollections -Scope Global -ErrorAction SilentlyContinue)) {
                                    $global:InterfacePortCollections = @{}
                                }
                                $global:InterfacePortCollections[$deviceHost] = $collection

                                if (-not (Get-Variable -Name DeviceInterfaceCache -Scope Global -ErrorAction SilentlyContinue)) {
                                    $global:DeviceInterfaceCache = @{}
                                }
                                $global:DeviceInterfaceCache[$deviceHost] = $collection
                            })
                        } catch {
                            try {
                                if (-not (Get-Variable -Name InterfacePortCollections -Scope Global -ErrorAction SilentlyContinue)) {
                                    $global:InterfacePortCollections = @{}
                                }
                                $global:InterfacePortCollections[$deviceHost] = $collection

                                if (-not (Get-Variable -Name DeviceInterfaceCache -Scope Global -ErrorAction SilentlyContinue)) {
                                    $global:DeviceInterfaceCache = @{}
                                }
                                $global:DeviceInterfaceCache[$deviceHost] = $collection
                            } catch {}
                        }
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

                                    try {
                                        if (Get-Command -Name 'FilterStateModule\Get-SelectedLocation' -ErrorAction SilentlyContinue) {
                                            $currentLocation = $null
                                            try { $currentLocation = FilterStateModule\Get-SelectedLocation } catch { $currentLocation = $null }
                                            $updateParams = @{}
                                            if ($currentLocation) {
                                                if ($currentLocation.PSObject.Properties['Site'] -and $currentLocation.Site) {
                                                    $updateParams.Site = '' + $currentLocation.Site
                                                }
                                            if ($currentLocation.PSObject.Properties['Zone'] -and $currentLocation.Zone) {
                                                $updateParams.ZoneSelection = '' + $currentLocation.Zone
                                                $updateParams.ZoneToLoad = '' + $currentLocation.Zone
                                            }
                                        }
                                        if (Get-Command -Name 'DeviceCatalogModule\Get-DeviceSummaries' -ErrorAction SilentlyContinue) {
                                            $needsCatalogRefresh = $false
                                            try {
                                                if (-not (Get-Variable -Name DeviceMetadata -Scope Global -ErrorAction SilentlyContinue)) {
                                                    $needsCatalogRefresh = $true
                                                } else {
                                                    $metaEntry = $null
                                                    try {
                                                        if ($global:DeviceMetadata.ContainsKey($deviceHost)) {
                                                            $metaEntry = $global:DeviceMetadata[$deviceHost]
                                                        }
                                                    } catch { $metaEntry = $null }
                                                    if (-not $metaEntry -or -not $metaEntry.PSObject.Properties['Site'] -or [string]::IsNullOrWhiteSpace($metaEntry.Site)) {
                                                        $needsCatalogRefresh = $true
                                                    }
                                                }
                                            } catch {
                                                $needsCatalogRefresh = $true
                                            }
                                            if ($needsCatalogRefresh) {
                                                try { DeviceCatalogModule\Get-DeviceSummaries | Out-Null } catch {}
                                            }
                                        }
                                        if (Get-Command -Name 'DeviceRepositoryModule\Update-GlobalInterfaceList' -ErrorAction SilentlyContinue) {
                                            try { DeviceRepositoryModule\Update-GlobalInterfaceList @updateParams | Out-Null } catch {}
                                        }
                                        } elseif (Get-Command -Name 'DeviceRepositoryModule\Update-GlobalInterfaceList' -ErrorAction SilentlyContinue) {
                                            try { DeviceRepositoryModule\Update-GlobalInterfaceList | Out-Null } catch {}
                                        }

                                        $allCount = 0
                                        try { $allCount = ViewStateService\Get-SequenceCount -Value $global:AllInterfaces } catch { $allCount = 0 }
                                        try { Write-Diag ("Interface aggregate refreshed | Host={0} | GlobalInterfaces={1}" -f $deviceHost, $allCount) } catch {}

                                        if (Get-Command -Name 'DeviceInsightsModule\Update-Summary' -ErrorAction SilentlyContinue) {
                                            try { DeviceInsightsModule\Update-Summary } catch {}
                                        }
                                        if (Get-Command -Name 'DeviceInsightsModule\Update-Alerts' -ErrorAction SilentlyContinue) {
                                            try { DeviceInsightsModule\Update-Alerts } catch {}
                                        }
                                        if (Get-Command -Name 'DeviceInsightsModule\Update-SearchGrid' -ErrorAction SilentlyContinue) {
                                            try { DeviceInsightsModule\Update-SearchGrid } catch {}
                                        }
                                    } catch {
                                        try { Write-Diag ("Interface aggregate refresh failed | Host={0} | Error={1}" -f $deviceHost, $_.Exception.Message) } catch {}
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

                if (Get-Command -Name 'TelemetryModule\Write-StTelemetryEvent' -ErrorAction SilentlyContinue) {
                    $telemetryPayload = @{
                        Hostname          = $deviceHost
                        InvokeDurationMs  = $invokeDurationMs
                        StreamDurationMs  = $streamDurationMs
                        FirstBatchMs      = (if ($firstBatchDelayMs -ne $null) { $firstBatchDelayMs } else { 0.0 })
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
                    try { TelemetryModule\Write-StTelemetryEvent -Name 'DeviceDetailsLoadMetrics' -Payload $telemetryPayload } catch { }
                }

                try { DeviceRepositoryModule\Clear-InterfacePortStream -Hostname $deviceHost } catch { }
                & $logAsync ("Async cleared port stream for host {0}" -f $deviceHost)
                [System.Windows.Application]::Current.Dispatcher.Invoke([System.Action]{ InterfaceModule\Hide-PortLoadingIndicator })
            } catch {
                # Log any exceptions thrown during Invoke
                Write-Warning ("Import-DeviceDetailsAsync thread encountered an exception: {0}" -f $_.Exception.Message)
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
            if (Get-Command -Name Update-CompareView -ErrorAction SilentlyContinue) {
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

# === BEGIN Window Loaded handler (patched) ===
$window.Add_Loaded({
    try {
        # Make DB path visible to child code
        if ($global:StateTraceDb) { $env:StateTraceDbPath = $global:StateTraceDb }

        # Parse logs
        if (Get-Command Invoke-StateTraceParsing -ErrorAction SilentlyContinue) {
            Invoke-StateTraceParsing -Synchronous
        } else {
            Write-Error "Invoke-StateTraceParsing not found (module load failed)"
        }

        # Bind summaries and filters (this populates HostnameDropdown)
        $catalog = $null
        try { $catalog = Get-DeviceSummaries } catch { $catalog = $null }
        try {
            $hostList = $null
            if ($catalog -and $catalog.PSObject.Properties['Hostnames']) { $hostList = $catalog.Hostnames }
            if ($hostList) {
                Initialize-DeviceFilters -Hostnames $hostList -Window $window
            } else {
                Initialize-DeviceFilters -Window $window
            }
        } catch {}
        Update-DeviceFilter   # <-- critical

        # Now build Compare so it can read the host list
        if (Get-Command -Name Update-CompareView -ErrorAction SilentlyContinue) {
            try { Update-CompareView -Window $window | Out-Null }
            catch { Write-Warning ("Failed to initialize Compare view after parsing: {0}" -f $_.Exception.Message) }
        }

        # Seed details for the first host (optional)
        $hostDD = $window.FindName('HostnameDropdown')
        if ($hostDD -and $hostDD.Items.Count -gt 0) {
            $first = $hostDD.Items[0]
            # Load details for the first host via the unified helper
            Show-DeviceDetails $first
            if (Get-Command Get-SpanInfo -ErrorAction SilentlyContinue) { Get-SpanInfo $first }
        }
    } catch {
        [System.Windows.MessageBox]::Show(("Log parsing failed:`n{0}" -f $_.Exception.Message), "Error")
    }
})
# === END Window Loaded handler (patched) ===



if ($window.FindName('HostnameDropdown').Items.Count -gt 0) {
    $first = $window.FindName('HostnameDropdown').Items[0]
    # Load details for the first host using the unified helper
    Show-DeviceDetails $first
    if (Get-Command Get-SpanInfo -ErrorAction SilentlyContinue) {
        Get-SpanInfo $first
    }
}

# 8) Show window
$window.ShowDialog() | Out-Null

# 9) Cleanup
    $hostTrim = ('' + $Hostname).Trim()
