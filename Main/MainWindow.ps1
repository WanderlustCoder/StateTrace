# === MainWindow.ps1 :: Bootstrap (WPF + Paths + Module Manifest) ===

# Load WPF once (PresentationFramework pulls in PresentationCore & WindowsBase).
Add-Type -AssemblyName PresentationFramework

# Paths
$scriptDir    = $PSScriptRoot
# Ensure global debug flag initialized
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
            # PowerShell <5.0 fallback – use .psd1 as a ps1
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
## Database initialization
# === BEGIN Database Initialization (MainWindow.ps1) ===
# Uses DatabaseModule’s Initialize-StateTraceDatabase; sets $global:StateTraceDb and $env:StateTraceDbPath.
$null = Initialize-StateTraceDatabase -DataDir (Join-Path $scriptDir '..\Data')
# === END Database Initialization (MainWindow.ps1) ===


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
function Populate-BrocadeOSFromConfig {
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
        # 'New-CompareView'  # deferred until after Update-DeviceFilter
    )

    # Auto-discover any additional New-*View commands, excluding Compare for now
    $excludeInitially = @('New-CompareView')
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
# === END View initialization helpers (MainWindow.ps1) ===

# === BEGIN Main window control hooks (MainWindow.ps1) ===

function Set-EnvToggle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Checked
    )
    # Strings by design: downstream reads env flags, not booleans.
    $new = if ($Checked) { 'true' } else { '' }
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
        Get-DeviceSummaries
        Update-DeviceFilter
        # Rebuild Compare view so its host list reflects the new parse
        if (Get-Command -Name New-CompareView -ErrorAction SilentlyContinue) {
            try { New-CompareView -Window $window | Out-Null }
            catch { Write-Warning ("Failed to refresh Compare view: {0}" -f $_.Exception.Message) }
        }

    } catch {
        Write-Warning ("Refresh failed: {0}" -f $_.Exception.Message)
    }
}

function On-HostnameChanged {
    [CmdletBinding()]
    param([string]$Hostname)

    try {
        # Load device details synchronously.  Asynchronous invocation via
        # Load-DeviceDetailsAsync has been disabled due to stability issues on
        # PowerShell 5.1.  Using the synchronous helper ensures reliability
        # when selecting a new host from the dropdown.
        if ($Hostname) {
            Get-DeviceDetails $Hostname
            if (Get-Command Load-SpanInfo -ErrorAction SilentlyContinue) {
                Load-SpanInfo $Hostname
            }
        } else {
            # Clear span info when hostname is empty
            if (Get-Command Load-SpanInfo -ErrorAction SilentlyContinue) {
                Load-SpanInfo ''
            }
        }
    } catch {
        Write-Warning ("Hostname change handler failed: {0}" -f $_.Exception.Message)
    }
}

<#
    Load device details asynchronously.  This wrapper uses .NET tasks to run
    Get‑DeviceDetailsData on a background thread.  When the task completes, it
    marshals the result back to the UI thread via the WPF dispatcher.  It then
    populates the appropriate controls in the Interfaces view (HostnameBox,
    MakeBox, ModelBox, etc.), binds the interface list to the InterfacesGrid,
    and populates the configuration templates dropdown using Set‑DropdownItems.
    If no hostname is provided, the function clears the span info via
    Load‑SpanInfo when defined.  Any exceptions are silently swallowed to
    preserve UI stability.
#>
function Load-DeviceDetailsAsync {
    <#
        Retrieve device details on a background thread to avoid blocking the UI thread.  This
        implementation has been rewritten for PowerShell 5.1 compatibility.  It no longer
        passes script blocks or untyped delegates to .NET methods which do not support
        them.  Instead, the code constructs an explicit script string and executes it on
        a dedicated background thread using a synchronous Invoke() call rather than
        BeginInvoke().  The dispatcher is invoked via [System.Action] to marshal updates
        back to the UI.

        When asynchronous invocation fails for any reason, the function writes a warning
        and does not throw.  Callers should fall back to a synchronous Get‑DeviceDetails
        invocation if desired.
    #>
    [CmdletBinding()]
    param(
        [string]$Hostname
    )
    # Determine if debug output is enabled
    $debug = ($Global:StateTraceDebug -eq $true)
    if ($debug) {
        Write-Verbose ("Load-DeviceDetailsAsync: called with Hostname='{0}'" -f ($Hostname -as [string]))
    }
    # If no host is provided, clear span info and return
    if (-not $Hostname) {
        if (Get-Command Load-SpanInfo -ErrorAction SilentlyContinue) {
            try { [System.Windows.Application]::Current.Dispatcher.Invoke([System.Action]{ Load-SpanInfo '' }) } catch {}
        }
        return
    }

    # Resolve the module path to an absolute path.  Join-Path with '..' segments may
    # yield a relative string; Resolve-Path expands it to a full filesystem path.
    try {
        $modulePath = (Resolve-Path -LiteralPath (Join-Path $scriptDir "..\Modules\DeviceDataModule.psm1")).Path
    } catch {
        # Fallback to direct join if Resolve-Path fails
        $modulePath = Join-Path $scriptDir "..\Modules\DeviceDataModule.psm1"
    }
    try {
        # Create a dedicated STA runspace for background processing.  Running the
        # device data retrieval in a separate runspace avoids blocking the UI
        # thread and does not rely on .NET Tasks which are not always available.
        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $rs.ApartmentState = [System.Threading.ApartmentState]::STA
        $rs.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
        $rs.Open()
        if ($debug) {
            Write-Verbose ("Load-DeviceDetailsAsync: runspace created (Id={0})" -f $rs.Id)
        }

        # Create a PowerShell instance bound to the new runspace
        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $rs
        if ($debug) {
            Write-Verbose "Load-DeviceDetailsAsync: PowerShell instance created for background runspace"
        }

        # Build a script string instead of passing a ScriptBlock.  Passing a string
        # ensures the AddScript method binds to the correct overload in PowerShell 5.1.
        $scriptText = @"
param(\$hn, \$modPath)
Import-Module -LiteralPath \$modPath -ErrorAction Stop
\$res = \$null
try {
    \$res = Get-DeviceDetailsData -Hostname \$hn
} catch {
    # Return the error record to be handled on the UI thread
    \$res = \$_
}
return \$res
"@
        # Add the script and arguments to the PowerShell instance
        [void]$ps.AddScript($scriptText)
        [void]$ps.AddArgument($Hostname)
        [void]$ps.AddArgument($modulePath)
        if ($debug) {
            Write-Verbose "Load-DeviceDetailsAsync: script and arguments added to PowerShell instance"
        }

        # Execute the device details retrieval on a dedicated background thread instead of using
        # PowerShell.BeginInvoke(), which has limited overloads in PowerShell 5.1.  We create a
        # [Thread] object to run the synchronous Invoke() call on our background runspace and
        # marshal results back to the UI thread via the WPF Dispatcher.  This avoids the
        # overload issues encountered with BeginInvoke().
        if ($Global:StateTraceDebug -eq $true) {
            Write-Verbose ("Load-DeviceDetailsAsync: starting background thread for '{0}'" -f $Hostname)
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
                # Emit verbose output when debug is enabled
                if ($Global:StateTraceDebug -eq $true) {
                    try {
                        $typeName = if ($null -ne $data) { $data.GetType().FullName } else { 'null' }
                        Write-Verbose ("Load-DeviceDetailsAsync: thread received result of type '{0}'" -f $typeName)
                    } catch {}
                }
                # Marshal UI updates back to the dispatcher thread.  Passing the result as
                # an argument avoids capturing variables from the background runspace,
                # which can lead to crashes when selecting a host.  Dispatcher.Invoke
                # can take a scriptblock and an argument array; the scriptblock declares
                # a parameter to receive the result object.
                $uiAction = {
                    param($dto)
                    try {
                        # If an error record or null result was returned, display a warning and exit
                        if (-not $dto -or ($dto -is [System.Management.Automation.ErrorRecord])) {
                            if ($dto -and $dto.Exception) {
                                Write-Warning ("Load-DeviceDetailsAsync error: {0}" -f $dto.Exception.Message)
                            }
                            # Clear the interfaces grid on failure
                            if ($global:interfacesView) {
                                $view = $global:interfacesView
                                $grid = $view.FindName('InterfacesGrid')
                                if ($grid) { $grid.ItemsSource = $null }
                            }
                            return
                        }
                        # Extract summary, interfaces and templates from the returned object
                        $summary    = $dto.Summary
                        $interfaces = $dto.Interfaces
                        $templates  = $dto.Templates
                        # Update the Interfaces view controls if available
                        if ($global:interfacesView) {
                            $view = $global:interfacesView
                            # Update summary fields safely
                            $view.FindName('HostnameBox').Text        = $summary.Hostname
                            $view.FindName('MakeBox').Text            = $summary.Make
                            $view.FindName('ModelBox').Text           = $summary.Model
                            $view.FindName('UptimeBox').Text          = $summary.Uptime
                            $view.FindName('PortCountBox').Text       = $summary.Ports
                            $view.FindName('AuthDefaultVLANBox').Text = $summary.AuthDefaultVLAN
                            $view.FindName('BuildingBox').Text        = $summary.Building
                            $view.FindName('RoomBox').Text            = $summary.Room
                            # Bind interfaces list to grid
                            $grid = $view.FindName('InterfacesGrid')
                            if ($grid) { $grid.ItemsSource = $interfaces }
                            # Populate configuration template dropdown
                            $combo = $view.FindName('ConfigOptionsDropdown')
                            if ($combo) { Set-DropdownItems -Control $combo -Items $templates }
                        }
                        # Load span info using vendor-specific helper if present
                        if (Get-Command Load-SpanInfo -ErrorAction SilentlyContinue) {
                            try { Load-SpanInfo $summary.Hostname } catch {}
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
                    Write-Warning ("Load-DeviceDetailsAsync dispatcher invocation failed: {0}" -f $_.Exception.Message)
                }
            } catch {
                # Log any exceptions thrown during Invoke
                Write-Warning ("Load-DeviceDetailsAsync thread encountered an exception: {0}" -f $_.Exception.Message)
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
        Write-Warning ("Load-DeviceDetailsAsync failed to start: {0}" -f $_.Exception.Message)
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
        On-HostnameChanged -Hostname $sel
    })
    $script:HostnameHandlerAttached = $true
}

# === END Main window control hooks (MainWindow.ps1) ===


# === BEGIN Filter dropdown hooks (MainWindow.ps1) ===

# Debounced updater so cascaded changes trigger a single refresh.
if (-not $script:FilterUpdateTimer) {
    # Create a debounced timer for device filter updates.  The interval was
    # previously set to 120ms which could trigger frequent refreshes on rapid
    # changes.  Increase this to 300ms to allow the user to finish typing or
    # selecting before the filter logic runs, reducing unnecessary work and
    # improving responsiveness.  See performance plan phase 1.
    $script:FilterUpdateTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:FilterUpdateTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $script:FilterUpdateTimer.add_Tick({
        $script:FilterUpdateTimer.Stop()
        try {
            # Refresh device filter using the unified helper
            Update-DeviceFilter

            # Keep Compare in sync with current filters/hosts
            if (Get-Command -Name New-CompareView -ErrorAction SilentlyContinue) {
                try { New-CompareView -Window $window | Out-Null } catch {}
            }
        } catch {
            Write-Warning ("Device filter update failed: {0}" -f $_.Exception.Message)
        }
    })
}

function Request-DeviceFilterUpdate {
    # restart the timer; successive calls coalesce into one update
    $script:FilterUpdateTimer.Stop()
    $script:FilterUpdateTimer.Start()
}

# Track which controls we’ve already wired to avoid duplicate subscriptions.
if (-not $script:FilterHandlers) { $script:FilterHandlers = @{} }

function Hook-FilterDropdowns {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Windows.Window]$Window)

    foreach ($name in 'SiteDropdown','BuildingDropdown','RoomDropdown') {
        if ($script:FilterHandlers.ContainsKey($name)) { continue }
        $ctrl = $Window.FindName($name)
        if ($ctrl) {
            $ctrl.Add_SelectionChanged({ Request-DeviceFilterUpdate })
            $script:FilterHandlers[$name] = $true
        }
    }
}

# Wire them now (safe to call multiple times; wiring is idempotent)
Hook-FilterDropdowns -Window $window

# === END Filter dropdown hooks (MainWindow.ps1) ===


# Hook up ShowCisco and ShowBrocade buttons to copy show command sequences
$showCiscoBtn   = $window.FindName('ShowCiscoButton')
$showBrocadeBtn = $window.FindName('ShowBrocadeButton')
$brocadeOSDD    = $window.FindName('BrocadeOSDropdown')
if ($brocadeOSDD) { Populate-BrocadeOSFromConfig -Dropdown $brocadeOSDD }


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
            # Determine the selected OS version from dropdown; default to first item
            $osVersion = 'v8.0.30'
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
        # Populate hostnames and apply location filters using unified helper functions
        Get-DeviceSummaries
        Update-DeviceFilter   # <-- critical

        # Now build Compare so it can read the host list
        if (Get-Command -Name New-CompareView -ErrorAction SilentlyContinue) {
            try { New-CompareView -Window $window | Out-Null }
            catch { Write-Warning ("Failed to initialize Compare view after parsing: {0}" -f $_.Exception.Message) }
        }

        # Seed details for the first host (optional)
        $hostDD = $window.FindName('HostnameDropdown')
        if ($hostDD -and $hostDD.Items.Count -gt 0) {
            $first = $hostDD.Items[0]
            # Load details for the first host via the unified helper
            Get-DeviceDetails $first
            if (Get-Command Load-SpanInfo -ErrorAction SilentlyContinue) { Load-SpanInfo $first }
        }
    } catch {
        [System.Windows.MessageBox]::Show(("Log parsing failed:`n{0}" -f $_.Exception.Message), "Error")
    }
})
# === END Window Loaded handler (patched) ===




if ($window.FindName('HostnameDropdown').Items.Count -gt 0) {
    $first = $window.FindName('HostnameDropdown').Items[0]
    # Load details for the first host using the unified helper
    Get-DeviceDetails $first
    if (Get-Command Load-SpanInfo -ErrorAction SilentlyContinue) {
        Load-SpanInfo $first
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
