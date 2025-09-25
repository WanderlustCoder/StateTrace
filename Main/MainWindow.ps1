# === MainWindow.ps1 :: Bootstrap (WPF + Paths + Module Manifest) ===

# Load WPF once (PresentationFramework pulls in PresentationCore & WindowsBase).
Add-Type -AssemblyName PresentationFramework

# ---- Diagnostics configuration (startup) ----
# Disable verbose and debug output by default.  Setting StateTraceDebug to
# $false ensures Write-Diag becomes a no-op.  Verbose and debug streams are
# suppressed by switching the preferences to SilentlyContinue.  This prevents
# diagnostic chatter in the console and avoids creating log files unless
# explicitly re-enabled.
$Global:StateTraceDebug     = $false
$VerbosePreference          = 'SilentlyContinue'
$DebugPreference            = 'SilentlyContinue'
$ErrorActionPreference      = 'Continue'

# Define a simple diagnostic logger that writes both to the verbose stream and
# to a timestamped log file in the user's Documents\StateTrace\Logs directory.
function Write-Diag {
    param([string]$Message)
    # Only emit diagnostics when the global debug flag is enabled.  When
    # $Global:StateTraceDebug is $false, this function does nothing,
    # preventing verbose output and log file writes.
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

# Prepare diagnostic log directory and file only when debugging is enabled.
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

# Attempt to set the host runspace to FullLanguage (best effort).  Some enterprise
# environments default the host runspace to NoLanguage, which prevents
# PowerShell keywords (if/foreach/try) from functioning in the UI thread.  This
# try/catch ensures we at least attempt to elevate the LanguageMode; if the
# policy blocks it, we continue silently.  Verbose output will indicate the
# result when $Global:StateTraceDebug is enabled.
try {
    $ExecutionContext.SessionState.LanguageMode = [System.Management.Automation.PSLanguageMode]::FullLanguage
    Write-Diag ("Host LanguageMode: {0}" -f $ExecutionContext.SessionState.LanguageMode)
} catch {
    Write-Diag ("Host LanguageMode remains: {0}" -f $ExecutionContext.SessionState.LanguageMode)
}

# In some environments the host runspace's LanguageMode cannot be changed via
# $ExecutionContext.SessionState.  Attempt to update the default runspace
# LanguageMode via the SessionStateProxy as an additional best-effort fallback.
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

# Smoke test the 'if' keyword in the host runspace.  This small test attempts
# to execute a simple if statement; in NoLanguage mode it will throw and
# set $HostKeywordOK to false.  Logging helps diagnose LanguageMode issues.
try {
    $HostKeywordOK = $false
    try { if ($true) { $HostKeywordOK = $true } } catch { $HostKeywordOK = $false }
    Write-Diag ("Host keyword 'if' ok: {0}" -f $HostKeywordOK)
} catch { }

# Paths
$scriptDir    = $PSScriptRoot
if ($null -eq $Global:StateTraceDebug) { $Global:StateTraceDebug = $false }

# Load modules from the manifest (single source of truth)
$manifestPath = Join-Path $scriptDir '..\Modules\ModulesManifest.psd1'

try {
    if (-not (Test-Path $manifestPath)) {
        throw "Module manifest not found at ${manifestPath}"
    }

    $manifest =
        if (Get-Command Import-PowerShellDataFile -ErrorAction SilentlyContinue) {
            Import-PowerShellDataFile -Path $manifestPath
        } else {
            # PowerShell <5.0 fallback - use .psd1 as a ps1
            . $manifestPath
        }

    # The manifest should contain a ModulesToImport list.
    $modulesToImport = @()
    if ($manifest.ModulesToImport) {
        $modulesToImport = $manifest.ModulesToImport
    } elseif ($manifest.Modules) {
        # Fallback if a non-standard key is used
        $modulesToImport = $manifest.Modules
    } else {
        throw "No ModulesToImport defined in manifest."
    }

    # Import each module listed in the manifest
    foreach ($mod in $modulesToImport) {
        Write-Host "Loading module: $mod"
        Import-Module -Name (Join-Path $scriptDir "..\Modules\$mod")
    }
}
catch {
    Write-Error "Failed to load modules from manifest: $($_.Exception.Message)"
    return
}

## ---------------------------------------------------------------------
# Prior to implementing per-site databases, the application would create a single
# StateTrace.accdb database here via Initialize-StateTraceDatabase. With the
# introduction of per-site databases, we no longer create a global database at
# startup. Instead, each site-specific database will be created on demand by
# the parser when processing logs. We still ensure the Data directory exists
# here to avoid errors when saving databases later on.
try {
    $dataDir = Join-Path $scriptDir '..\Data'
    if (-not (Test-Path $dataDir)) {
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    }
} catch {
    Write-Warning ("Failed to ensure Data directory exists: {0}" -f $_.Exception.Message)
}
# === END Database Initialization (MainWindow.ps1) ===

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
    $excludeInitially = @('Update-CompareView','New-StView')
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
            Invoke-StateTraceParsing
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
                Import-Module -LiteralPath $modPath -Force -Global
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
        InterfaceModule\Set-InterfaceViewData -DeviceDetails $dto -DefaultHostname $hostTrim
    } catch {
        Write-Warning ("Failed to apply device details for {0}: {1}" -f $hostTrim, $_.Exception.Message)
    }
}

function Get-HostnameChanged {
    [CmdletBinding()]
    param([string]$Hostname)

    try {
        # Load device details synchronously.  Asynchronous invocation via
        if ($Hostname) {
            Show-DeviceDetails $Hostname
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
    if ($debug) {
        Write-Verbose ("Import-DeviceDetailsAsync: called with Hostname='{0}'" -f ($Hostname -as [string]))
    }
    # If no host is provided, clear span info and return
    if (-not $Hostname) {
        if (Get-Command Get-SpanInfo -ErrorAction SilentlyContinue) {
            try { [System.Windows.Application]::Current.Dispatcher.Invoke([System.Action]{ Get-SpanInfo '' }) } catch {}
        }
        return
    }

    try {
        $modulesDir = (Resolve-Path -LiteralPath (Join-Path $scriptDir "..\Modules")).Path
    } catch {
        $modulesDir = Join-Path $scriptDir "..\Modules"
    }

    try {
        # Create a dedicated STA runspace for background processing.  Use a custom
        # InitialSessionState with FullLanguage enabled so that script keywords
        # (`if`, `foreach`, `try`, etc.) and advanced language features work even
        # when the host or policy would otherwise restrict the language mode.
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $iss.LanguageMode = [System.Management.Automation.PSLanguageMode]::FullLanguage
        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
        $rs.ApartmentState = [System.Threading.ApartmentState]::STA
        $rs.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
        $rs.Open()
        if ($debug) {
            Write-Verbose ("Import-DeviceDetailsAsync: runspace created (Id={0})" -f $rs.Id)
        }

        # Create a PowerShell instance bound to the new runspace
        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $rs
        if ($debug) {
            Write-Verbose "Import-DeviceDetailsAsync: PowerShell instance created for background runspace"
        }

        # Build a script string instead of passing a ScriptBlock.  Passing a string
        $scriptText = @'
param($hn, $modulesDir)
$modules = @(
    'DatabaseModule.psm1',
    'DeviceRepositoryModule.psm1',
    'TemplatesModule.psm1',
    'InterfaceModule.psm1',
    'DeviceDetailsModule.psm1'
)
foreach ($name in $modules) {
    $modulePath = Join-Path $modulesDir $name
    if (Test-Path -LiteralPath $modulePath) {
        Import-Module -LiteralPath $modulePath -Force -Global -ErrorAction Stop
    }
}
$res = $null
try {
    $res = Get-DeviceDetailsData -Hostname $hn
} catch {
    $res = $_
}
return $res
'@
        # Add the script and arguments to the PowerShell instance
        [void]$ps.AddScript($scriptText)
        [void]$ps.AddArgument($Hostname)
        [void]$ps.AddArgument($modulesDir)
        if ($debug) {
            Write-Verbose "Import-DeviceDetailsAsync: script and arguments added to PowerShell instance"
        }

        # Execute the device details retrieval on a dedicated background thread instead of using
        if ($Global:StateTraceDebug -eq $true) {
            Write-Verbose ("Import-DeviceDetailsAsync: starting background thread for '{0}'" -f $Hostname)
        }
        $threadScript = {
            param([System.Management.Automation.PowerShell]$psCmd)
            try {
                # Invoke the script synchronously in the background thread
                $results = $psCmd.Invoke()
                # Take the first result if multiple were returned
                if ($results -is [System.Collections.IEnumerable]) {
                    $data = $results | Select-Object -First 1
                } else {
                    $data = $results
                }
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
                        $defaultHost = $Hostname
                        if ($summary -and $summary.PSObject.Properties['Hostname']) {
                            $defaultHost = [string]$summary.Hostname
                        }
                        try {
                            InterfaceModule\Set-InterfaceViewData -DeviceDetails $dto -DefaultHostname $defaultHost
                        } catch {
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
                # Invoke the UI action with the result.  Wrap in try/catch to handle dispatcher errors.
                try {
                    [System.Windows.Application]::Current.Dispatcher.Invoke($uiAction, @($data))
                } catch {
                    # Log any dispatcher invocation errors but do not crash
                    Write-Warning ("Import-DeviceDetailsAsync dispatcher invocation failed: {0}" -f $_.Exception.Message)
                }
            } catch {
                # Log any exceptions thrown during Invoke
                Write-Warning ("Import-DeviceDetailsAsync thread encountered an exception: {0}" -f $_.Exception.Message)
            } finally {
                # Clean up the runspace and PowerShell instance
                try { $psCmd.Runspace.Close() } catch {}
                $psCmd.Dispose()
            }
        }
        # Build the thread start delegate and launch the background thread
        $threadStart = [System.Threading.ThreadStart]{ $threadScript.Invoke($ps) }
        $workerThread = [System.Threading.Thread]::new($threadStart)
        $workerThread.ApartmentState = [System.Threading.ApartmentState]::STA
        $workerThread.Start()
    } catch {
        # On failure to create runspace or begin invocation, log and return
        Write-Warning ("Import-DeviceDetailsAsync failed to start: {0}" -f $_.Exception.Message)
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

# === BEGIN Window Loaded handler (patched) ===
$window.Add_Loaded({
    try {
        # Make DB path visible to child code
        if ($global:StateTraceDb) { $env:StateTraceDbPath = $global:StateTraceDb }

        # Parse logs
        if (Get-Command Invoke-StateTraceParsing -ErrorAction SilentlyContinue) {
            Invoke-StateTraceParsing
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
$parsedDir = Join-Path $scriptDir '..\ParsedData'
if (Test-Path $parsedDir) {
    try {
        # Faster: remove the directory and recreate it, avoiding an expensive recursive enumeration.
        Remove-Item -LiteralPath $parsedDir -Recurse -Force -ErrorAction Stop
        New-Item -ItemType Directory -Path $parsedDir | Out-Null
    } catch {
        Write-Warning "Failed to reset ParsedData: $_"
    }
}








