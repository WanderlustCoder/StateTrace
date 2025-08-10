<#
    .SYNOPSIS
        Provides the view and logic for comparing two interface configurations.

    .DESCRIPTION
        This module implements a collapsible sidebar that is loaded into the
        CompareHost region defined in MainWindow.xaml.  It exposes two
        functions: New-CompareView, which loads the XAML, wires up
        dropdowns and buttons, and populates the host list; and
        Update-CompareView, which is called by the Interfaces module when
        the user selects two interfaces to compare.  The comparison view
        allows switching of devices and ports via dropdowns so that the
        user can quickly adjust their comparison.  Perâ€‘port configuration
        text is retrieved from the database via Get-InterfaceInfo and
        displayed side by side.  Commands that appear only in one
        configuration are highlighted in separate panels below the main
        views.  Colours for the configuration text are derived from
        vendor templates defined in the Templates folder (e.g. Cisco.json,
        Brocade.json) via the PortColor property exposed by
        Get-InterfaceInfo.

    .NOTES
        The module imports InterfaceModule.psm1 to access Get-DeviceSummaries
        and Get-InterfaceInfo.  It maintains scriptâ€‘scoped variables to
        reference controls so that they remain in scope when event
        handlers execute.
#>

Set-StrictMode -Version Latest

# Script‑scoped variables to hold references to controls and data
$script:compareView      = $null
$script:switch1Dropdown  = $null
$script:port1Dropdown    = $null
$script:switch2Dropdown  = $null
$script:port2Dropdown    = $null
$script:config1Box       = $null
$script:config2Box       = $null
$script:diff1Box         = $null
$script:diff2Box         = $null
$script:closeButton      = $null
$script:windowRef        = $null

# Flag to prevent recursive port list refreshes when updating dropdowns.  When
# set to $true, the Show-CurrentComparison function will skip refreshing
# ItemsSource collections.  This avoids re-entrancy when a port list update
# triggers a selection changed event that calls Show-CurrentComparison again.
$script:updatingPorts    = $false

# --- Helpers: place right after script-scoped variable block ---

function Get-PortsForHost {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Hostname)

    # Fetch a list of port names for the specified host.  Prefer using the
    # interfaces grid when it contains data for the host, otherwise fallback
    # to querying the database via Get-PortsFromDb, and finally to
    # Get-InterfaceInfo.  The result is sorted naturally.
    $ports = @()
    try {
        # Ensure interface commands are available (for Get-InterfaceInfo) if needed
        if (-not (Get-Command Get-InterfaceInfo -ErrorAction SilentlyContinue)) {
            try { Ensure-InterfaceCommands } catch { }
        }

    # Always attempt to retrieve port names from the database first, to avoid
        # relying on the main Interfaces grid (which may only contain ports for the
        # currently selected device in the main window).  If the database query
        # fails, fall back to Get-InterfaceInfo which in turn queries the DB and
        # augments with template information.
        #
        # 1. Query database via helper
        try {
            $ports = @(Get-PortsFromDb -Hostname $Hostname)
        } catch {
            $ports = @()
        }
        # 2. Fall back to Get-InterfaceInfo if needed
        if (-not $ports -or $ports.Count -eq 0) {
            if (Get-Command Get-InterfaceInfo -ErrorAction SilentlyContinue) {
                try {
                    $ports = @(
                        Get-InterfaceInfo -Hostname $Hostname |
                        Select-Object -ExpandProperty Port
                    )
                } catch {
                    $ports = @()
                }
            }
        }
        # 3. Final fall back: try to use interfaces grid if available.  This is
        # retained for completeness but will usually be empty for devices not
        # currently displayed in the main grid.
        if (-not $ports -or $ports.Count -eq 0) {
            if ($global:interfacesGrid -and $global:interfacesGrid.ItemsSource) {
                try {
                    $ports = @(
                        $global:interfacesGrid.ItemsSource |
                        Where-Object {
                            ($_.'Hostname' -as [string]) -eq $Hostname
                        } |
                        ForEach-Object { $_.Port }
                    )
                } catch {
                    $ports = @()
                }
            }
        }
        # Natural sort: pad numeric segments to four digits
        $ports = @(
            $ports |
            Sort-Object {
                [regex]::Replace($_, '\d+', {
                    param($m)
                    $m.Value.PadLeft(4, '0')
                })
            }
        )
        # Debug: output the number of ports and port names for the given host.  This
        # helps identify when the database query yields no ports.  We use
        # Write-Host so that debug information is visible in the PowerShell
        # console.
        try {
            $portsDbg = if ($ports) { $ports -join ', ' } else { '(none)' }
            Write-Host ("[Get-PortsForHost] Host $Hostname - Ports loaded ($($ports.Count)): $portsDbg") -ForegroundColor DarkCyan
        } catch { }
        return $ports
    } catch {
        return @()
    }
}

function Get-GridRowFor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][string]$Port
    )
    if ($global:interfacesGrid -and $global:interfacesGrid.ItemsSource) {
        try {
            return @(
                $global:interfacesGrid.ItemsSource |
                Where-Object {
                    ($_.'Hostname' -as [string]) -eq $Hostname -and
                    ($_.'Port'      -as [string]) -eq $Port
                }
            ) | Select-Object -First 1
        } catch { return $null }
    }
    return $null
}

function Get-AuthTemplateFromTooltip {
    [CmdletBinding()]
    param([string]$Text)
    if (-not $Text) { return '' }
    $m = [regex]::Match($Text, '^\s*AuthTemplate\s*:\s*(.+)$', 'IgnoreCase, Multiline')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}

# Query the database directly to retrieve the list of port names for a given
# hostname.  This helper bypasses the interfaces grid and retrieves port
# names from the Interfaces table in the StateTrace database.  It is used
# when the grid does not contain data for the requested host.  Returns
# an array of strings (port names) or an empty array on failure.
function Get-PortsFromDb {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Hostname)

    # We can only query the DB if the global database path is defined
    if (-not $global:StateTraceDb) { return @() }
    try {
        # Ensure Invoke-DbQuery is available by importing DatabaseModule globally
        if (-not (Get-Command Invoke-DbQuery -ErrorAction SilentlyContinue)) {
            $dbModulePath = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
            if (Test-Path $dbModulePath) {
                Import-Module $dbModulePath -Force -Global -ErrorAction Stop
            } else {
                return @()
            }
        }
        # Escape single quotes in hostname for SQL
        $escHost = $Hostname -replace "'", "''"
        $sql = "SELECT Port FROM Interfaces WHERE Hostname = '$escHost'"
        $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $sql
        $ports = @()
        if ($dt) {
            if ($dt -is [System.Data.DataTable]) {
                foreach ($row in $dt.Rows) { $ports += $row.Port }
            } else {
                foreach ($r in $dt) { if ($r.PSObject.Properties['Port']) { $ports += $r.Port } }
            }
        }
        return $ports
    } catch {
        return @()
    }
}

# Query a specific interface row directly from the Interfaces table in the
# StateTrace database.  This helper is used as a final fallback when
# Get-InterfaceInfo does not return a matching object for a given host
# and port.  It returns a PSCustomObject with Hostname, Port,
# AuthTemplate, Config and PortColor properties, or $null if no row
# exists.  Debug messages report the outcome of the query.
function Get-InterfaceRowFromDb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][string]$Port
    )
    # Only proceed if a database path is available
    if (-not $global:StateTraceDb) {
        return $null
    }
    try {
        # Ensure DatabaseModule is imported to obtain Invoke-DbQuery
        if (-not (Get-Command Invoke-DbQuery -ErrorAction SilentlyContinue)) {
            $dbModulePath = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
            if (Test-Path $dbModulePath) {
                Import-Module $dbModulePath -Force -Global -ErrorAction Stop
            }
        }
        # Escape single quotes in identifiers
        $escHost = $Hostname -replace "'", "''"
        $escPort = $Port -replace "'", "''"
        $sql = "SELECT Port, AuthTemplate, Config, PortColor FROM Interfaces WHERE Hostname = '$escHost' AND Port = '$escPort'"
        $dt  = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $sql
        $result = $null
        if ($dt) {
            # Convert first row into PSCustomObject
            if ($dt -is [System.Data.DataTable]) {
                if ($dt.Rows.Count -gt 0) {
                    $r = $dt.Rows[0]
                    $result = [PSCustomObject]@{
                        Hostname     = $Hostname
                        Port         = $r.Port
                        AuthTemplate = $r.AuthTemplate
                        Config       = $r.Config
                        PortColor    = $r.PortColor
                    }
                }
            } else {
                $r = $dt | Select-Object -First 1
                if ($r -and $r.PSObject.Properties['Port']) {
                    $result = [PSCustomObject]@{
                        Hostname     = $Hostname
                        Port         = $r.Port
                        AuthTemplate = $r.AuthTemplate
                        Config       = $r.Config
                        PortColor    = $r.PortColor
                    }
                }
            }
        }
        # Debug: report whether a row was retrieved directly from the DB
        try {
            $status = if ($result) { 'found' } else { 'not found' }
            # Use subexpressions around variables followed by a colon to avoid parsing
            Write-Host ("[Get-InterfaceRowFromDb] $($Hostname) $($Port): $status") -ForegroundColor DarkCyan
        } catch { }
        return $result
    } catch {
        try {
            Write-Host (
                "[Get-InterfaceRowFromDb] Error querying $($Hostname) $($Port): $($_.Exception.Message)"
            ) -ForegroundColor Yellow
        } catch { }
        return $null
    }
}

# Query the global authentication block for a given device from the database.  The
# AuthBlock contains global authentication configuration (e.g. for 802.1X) and
# should be appended to per‑port configurations when comparing ports.  Returns
# an array of lines or an empty array if none is found.  Debug messages
# report what was loaded.
function Get-AuthBlockForHost {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Hostname)

    # Without a database path there is nothing to query
    if (-not $global:StateTraceDb) { return @() }
    try {
        # Ensure Invoke-DbQuery is available by importing DatabaseModule if needed
        if (-not (Get-Command Invoke-DbQuery -ErrorAction SilentlyContinue)) {
            $dbModulePath = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
            if (Test-Path $dbModulePath) {
                Import-Module $dbModulePath -Force -Global -ErrorAction Stop
            } else {
                Write-Host "[Get-AuthBlockForHost] Database module not found" -ForegroundColor Yellow
                return @()
            }
        }
        # Escape single quotes in hostname
        $escHost = $Hostname -replace "'", "''"
        $sql = "SELECT AuthBlock FROM DeviceSummary WHERE Hostname = '$escHost'"
        $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $sql
        $lines = @()
        if ($dt) {
            $abText = $null
            if ($dt -is [System.Data.DataTable]) {
                if ($dt.Rows.Count -gt 0) {
                    $abText = '' + $dt.Rows[0].AuthBlock
                }
            } else {
                $row = $dt | Select-Object -First 1
                if ($row -and $row.PSObject.Properties['AuthBlock']) {
                    $abText = '' + $row.AuthBlock
                }
            }
            if ($abText -and $abText.Trim() -ne '') {
                $lines = $abText -split "`r?`n"
            }
        }
        # Debug: print the auth block lines
        try {
            $dbg = if ($lines) { $lines -join '; ' } else { '(none)' }
            Write-Host ("[Get-AuthBlockForHost] Host $Hostname - AuthBlock lines loaded: $dbg") -ForegroundColor DarkCyan
        } catch { }
        return $lines
    } catch {
        # Use subexpressions $() to delimit variables followed by a colon within
        # interpolated strings.  Without this, PowerShell interprets the colon
        # as part of the variable name, causing a "Variable reference is not
        # valid" error when the script is run.  For example, writing
        # "... for $Hostname: ..." without braces will attempt to resolve a
        # variable named "Hostname:".
        Write-Host (
            "[Get-AuthBlockForHost] Failed to load AuthBlock for $($Hostname): $($_.Exception.Message)"
        ) -ForegroundColor Yellow
        return @()
    }
}

# The original Set-CompareFromRows implementation is deprecated and has been replaced
# with a more robust version later in this file.  We remove this definition to
# avoid ambiguity and ensure the updated function is used.
# --- end helpers ---


# Ensure InterfaceModule commands exist without trampling state
function Ensure-InterfaceCommands {
    if (-not (Get-Command Get-DeviceSummaries -ErrorAction SilentlyContinue) -or
        -not (Get-Command Get-InterfaceInfo   -ErrorAction SilentlyContinue)) {
        try {
            Import-Module (Join-Path $PSScriptRoot 'InterfaceModule.psm1') -ErrorAction Stop
        } catch {
            Write-Warning "Unable to import InterfaceModule.psm1: $($_.Exception.Message)"
        }
    }
}

# Re-resolve controls in case first pass missed them
function Resolve-CompareControls {
    if (-not $script:compareView) { return $false }
    if (-not $script:switch1Dropdown) { $script:switch1Dropdown = $script:compareView.FindName('Switch1Dropdown') }
    if (-not $script:port1Dropdown)   { $script:port1Dropdown   = $script:compareView.FindName('Port1Dropdown')   }
    if (-not $script:switch2Dropdown) { $script:switch2Dropdown = $script:compareView.FindName('Switch2Dropdown') }
    if (-not $script:port2Dropdown)   { $script:port2Dropdown   = $script:compareView.FindName('Port2Dropdown')   }
    if (-not $script:config1Box)      { $script:config1Box      = $script:compareView.FindName('Config1Box')      }
    if (-not $script:config2Box)      { $script:config2Box      = $script:compareView.FindName('Config2Box')      }
    if (-not $script:diff1Box)        { $script:diff1Box        = $script:compareView.FindName('Diff1Box')        }
    if (-not $script:diff2Box)        { $script:diff2Box        = $script:compareView.FindName('Diff2Box')        }
    if (-not $script:closeButton)     { $script:closeButton     = $script:compareView.FindName('CloseCompareButton') }
    return ($script:switch1Dropdown -and $script:port1Dropdown -and $script:switch2Dropdown -and $script:port2Dropdown)
}


<#
    Helper: Load and prepare the compare view.  Should be called once from
    MainWindow.ps1 during application startup.  It resolves the XAML file
    relative to the module directory, inserts the view into the main
    window, populates dropdowns and attaches event handlers.
#>
function New-CompareView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Window]$Window
    )

    $script:windowRef = $Window

    # Ensure interface-related commands are available before any data lookups.  This
    # imports the InterfaceModule if needed so that Get-InterfaceInfo and
    # related functions can be called from within this module.  Without
    # importing these commands, fetching ports or interface details for
    # devices that are not currently displayed in the main grid can fail.
    try {
        Ensure-InterfaceCommands
    } catch {
        Write-Warning "Failed to ensure interface commands: $($_.Exception.Message)"
    }

    # Resolve and load XAML
    $xamlPath = Join-Path $PSScriptRoot '..\Views\CompareView.xaml'
    if (-not (Test-Path $xamlPath)) {
        Write-Warning "Compare view XAML not found at $xamlPath"
        return
    }
    try {
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction SilentlyContinue
        $xaml     = Get-Content $xamlPath -Raw
        $reader   = [System.Xml.XmlTextReader]::new([System.IO.StringReader]::new($xaml))
        $viewCtrl = [System.Windows.Markup.XamlReader]::Load($reader)
    } catch {
        Write-Warning "Failed to load compare view from ${xamlPath}: $($_.Exception.Message)"
        return
    }
    if (-not $viewCtrl) { return }

    # Insert into CompareHost
    $compareHost = $Window.FindName('CompareHost')
    if ($compareHost -is [System.Windows.Controls.ContentControl]) {
        $compareHost.Content = $viewCtrl
    } else {
        Write-Warning "Could not find ContentControl 'CompareHost' in the main window"
        return
    }

    # Store view reference & resolve controls
    $script:compareView = $viewCtrl
    Resolve-CompareControls | Out-Null

    # Always populate the switch dropdowns from the database directly.  Relying on
    # the main window's HostnameDropdown ties the compare view to whatever device list
    # happens to be loaded in the primary interface tab.  To make this view
    # independent, query the database for all device hostnames directly via
    # Invoke-DbQuery.  If that fails, fall back to Get-DeviceSummaries.
    $allHosts = @()
    try {
        # Load device hostnames directly from the database without updating the main window
        if ($global:StateTraceDb -and (Get-Command Invoke-DbQuery -ErrorAction SilentlyContinue)) {
            $dtHosts = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Hostname FROM DeviceSummary ORDER BY Hostname"
            if ($dtHosts) {
                # Convert DataTable or object array into a list of hostnames
                if ($dtHosts -is [System.Data.DataTable]) {
                    foreach ($r in $dtHosts.Rows) { $allHosts += '' + $r.Hostname }
                } else {
                    foreach ($r in $dtHosts) { if ($r.PSObject.Properties['Hostname']) { $allHosts += '' + $r.Hostname } }
                }
            }
        }
    } catch {
        $allHosts = @()
    }
    # If no hosts were loaded from the database, fall back to the main window's
    # HostnameDropdown list.  We intentionally avoid calling Get-DeviceSummaries
    # here because that function updates the primary interface and resets the
    # selected device.  By simply reading the ItemsSource from the existing
    # dropdown, we maintain independence without side effects.
    if (-not $allHosts -or $allHosts.Count -eq 0) {
        try {
            $hostDD = $Window.FindName('HostnameDropdown')
            if ($hostDD -and $hostDD.ItemsSource) {
                $allHosts = @($hostDD.ItemsSource)
            } else {
                $allHosts = @()
            }
        } catch {
            $allHosts = @()
        }
    }
    if ($script:switch1Dropdown) { $script:switch1Dropdown.ItemsSource = $allHosts }
    if ($script:switch2Dropdown) { $script:switch2Dropdown.ItemsSource = $allHosts }

    # Debug: output loaded hosts and database path.  This helps diagnose cases
    # where the host list is unexpectedly empty.  Use Write-Host so messages
    # appear in the PowerShell console but do not interfere with the GUI.
    try {
        $dbPathDbg = if ($global:StateTraceDb) { $global:StateTraceDb } else { '(null)' }
        $hostListDbg = if ($allHosts) { $allHosts -join ', ' } else { '(none)' }
        Write-Host ("[CompareView] DB path: $dbPathDbg" ) -ForegroundColor DarkCyan
        Write-Host ("[CompareView] Hosts loaded ($($allHosts.Count)): $hostListDbg") -ForegroundColor DarkCyan
    } catch { }

    # Wire selection handlers (unchanged)
    if ($script:switch1Dropdown) {
        $script:switch1Dropdown.Add_SelectionChanged({
            # Update the list of ports for the newly selected host on the left side.  Do not
            # call Show-CurrentComparison here; instead rely on the port dropdown's
            # SelectionChanged event to update the display once the first port is
            # selected.  This avoids an intermediate call where the selected port
            # still points at the previous device and the colour resets to black.
            $selHost = $script:switch1Dropdown.SelectedItem
            if ($script:port1Dropdown) {
                try {
                    if ($selHost) {
                        try { Ensure-InterfaceCommands } catch { }
                        $script:port1Dropdown.ItemsSource = @(Get-PortsForHost -Hostname $selHost)
                        if ($script:port1Dropdown.ItemsSource -and $script:port1Dropdown.ItemsSource.Count -gt 0) {
                            try {
                                $script:port1Dropdown.SelectedIndex = 0
                            } catch {
                                $script:port1Dropdown.SelectedItem = $script:port1Dropdown.ItemsSource[0]
                            }
                        } else {
                            $script:port1Dropdown.SelectedItem = $null
                        }
                    } else {
                        $script:port1Dropdown.ItemsSource = @()
                        $script:port1Dropdown.SelectedItem = $null
                    }
                } catch {
                    $script:port1Dropdown.ItemsSource = @()
                    $script:port1Dropdown.SelectedItem = $null
                }
            }
        })
    }

    if ($script:switch2Dropdown) {
        $script:switch2Dropdown.Add_SelectionChanged({
            # Update the list of ports for the newly selected host on the right side.  Do not
            # call Show-CurrentComparison here; rely on the port dropdown's event to
            # update the view after the first port is selected.
            $selHost = $script:switch2Dropdown.SelectedItem
            if ($script:port2Dropdown) {
                try {
                    if ($selHost) {
                        try { Ensure-InterfaceCommands } catch { }
                        $script:port2Dropdown.ItemsSource = @(Get-PortsForHost -Hostname $selHost)
                        if ($script:port2Dropdown.ItemsSource -and $script:port2Dropdown.ItemsSource.Count -gt 0) {
                            try {
                                $script:port2Dropdown.SelectedIndex = 0
                            } catch {
                                $script:port2Dropdown.SelectedItem = $script:port2Dropdown.ItemsSource[0]
                            }
                        } else {
                            $script:port2Dropdown.SelectedItem = $null
                        }
                    } else {
                        $script:port2Dropdown.ItemsSource = @()
                        $script:port2Dropdown.SelectedItem = $null
                    }
                } catch {
                    $script:port2Dropdown.ItemsSource = @()
                    $script:port2Dropdown.SelectedItem = $null
                }
            }
        })
    }

    if ($script:port1Dropdown) { $script:port1Dropdown.Add_SelectionChanged({ Show-CurrentComparison }) }
    if ($script:port2Dropdown) { $script:port2Dropdown.Add_SelectionChanged({ Show-CurrentComparison }) }

    if ($script:closeButton) {
        $script:closeButton.Add_Click({
            if ($script:windowRef) {
                $col = $script:windowRef.FindName('CompareColumn')
                if ($col -is [System.Windows.Controls.ColumnDefinition]) {
                    $col.Width = [System.Windows.GridLength]::new(0)
                }
            }
        })
    }
    $script:auth1Text       = $viewCtrl.FindName('AuthTemplate1Text')
    $script:auth2Text       = $viewCtrl.FindName('AuthTemplate2Text')
}

# Populate the compare panes directly from two interface rows (no refetch)
function Set-CompareFromRows {
    param(
        [Parameter(Mandatory)][psobject]$Row1,
        [Parameter(Mandatory)][psobject]$Row2
    )
    try {
        # Retrieve colour information from the row objects.  Colours are
        # associated with the template name and used to set the foreground
        # colour of the template labels.  Default to black when not
        # specified.
        # Determine the port colour for each side.  Avoid using the PSObject.Properties
        # indexer here because it may return $null when the underlying object is a
        # DataRow or other type that still exposes the property via its dynamic
        # accessor.  Instead, check the PortColor property directly.  If it
        # exists and is non-empty, use it; otherwise fall back to Black.
        $color1 = 'Black'
        if ($Row1) {
            try {
                $colVal1 = $Row1.PortColor
                if ($colVal1 -ne $null -and "$colVal1".Trim() -ne '') {
                    $color1 = '' + $colVal1
                }
            } catch { }
        }
        $color2 = 'Black'
        if ($Row2) {
            try {
                $colVal2 = $Row2.PortColor
                if ($colVal2 -ne $null -and "$colVal2".Trim() -ne '') {
                    $color2 = '' + $colVal2
                }
            } catch { }
        }

        # Debug: Show the raw colour values and template names for both sides before any
        # conversions occur.  Use subexpression $() around variables followed by a
        # colon to prevent PowerShell from interpreting the colon as part of the
        # variable name in debug output.  This output helps diagnose cases where
        # PortColor is unexpectedly null or fails to convert via BrushConverter.
        try {
            $tplName1 = ''
            $tplName2 = ''
            if ($Row1.PSObject.Properties['AuthTemplate']) { $tplName1 = $Row1.AuthTemplate }
            if ($Row1.PSObject.Properties['ComputedTemplate'] -and $Row1.ComputedTemplate) { $tplName1 = $Row1.ComputedTemplate }
            if ($Row2.PSObject.Properties['AuthTemplate']) { $tplName2 = $Row2.AuthTemplate }
            if ($Row2.PSObject.Properties['ComputedTemplate'] -and $Row2.ComputedTemplate) { $tplName2 = $Row2.ComputedTemplate }
            Write-Host (
                "[Set-CompareFromRows] colour debug - Row1: PortColor=$($Row1.PortColor), raw colour=$($color1), template=$($tplName1); " +
                "Row2: PortColor=$($Row2.PortColor), raw colour=$($color2), template=$($tplName2)"
            ) -ForegroundColor DarkCyan
        } catch { }

        # Extract the template name and configuration lines for each row.  Prefer
        # the AuthTemplate and Config properties that were added to the
        # InterfaceInfo objects.  These values come directly from the
        # database and avoid parsing the ToolTip string.  If either
        # property is missing (for example, if the row is an older
        # object), fall back to parsing the ToolTip as before.
        # Determine the template name to display.  Prefer the computed
        # template (if present) to reflect the actual configuration, falling
        # back to the AuthTemplate from the database.  This prevents
        # mismatches where a port is labelled flexible even though it is
        # missing required commands like dot1x port-control auto.
        $auth1Name = ''
        $cfg1Lines = @()
        if ($Row1.PSObject.Properties['AuthTemplate'] -and $Row1.PSObject.Properties['Config']) {
            # Use the raw configuration if present.  Split into lines on CR/LF.
            # Choose the display name: prefer the parser-assigned AuthTemplate
            # because it reflects the global authentication state.  Only if
            # AuthTemplate is missing do we fall back to a computed match.
            $auth1Name = ''
            if ($Row1.PSObject.Properties['AuthTemplate'] -and $Row1.AuthTemplate) {
                $auth1Name = '' + $Row1.AuthTemplate
            } elseif ($Row1.PSObject.Properties['ComputedTemplate'] -and $Row1.ComputedTemplate) {
                $auth1Name = '' + $Row1.ComputedTemplate
            }
            $cfgRaw1   = '' + ($Row1.Config)
            if ($cfgRaw1 -and $cfgRaw1.Trim() -ne '') {
                $cfg1Lines = @($cfgRaw1 -split "`r?`n")
            } else {
                $cfg1Lines = @()
            }
        } else {
            # Fallback: parse the ToolTip to extract the template name and
            # configuration lines.  The first line of the tooltip is the
            # template header (AuthTemplate: <name>), followed by a blank line
            # and then the configuration.  Remove the header and any blank
            # lines immediately after.
            $tooltip1 = '' + ($Row1.ToolTip)
            if ($tooltip1) {
                $allLines1 = @($tooltip1 -split "`r?`n")
                if ($allLines1.Count -gt 0) {
                    $m1 = [regex]::Match($allLines1[0], '^\s*AuthTemplate\s*:\s*(.+)$', 'IgnoreCase')
                    if ($m1.Success) {
                        $auth1Name = $m1.Groups[1].Value.Trim()
                        $cfg1Lines = $allLines1[1..($allLines1.Count - 1)]
                        # Remove leading blank lines
                        while ($cfg1Lines.Count -gt 0 -and ($cfg1Lines[0].Trim() -eq '')) {
                            $cfg1Lines = if ($cfg1Lines.Count -gt 1) { $cfg1Lines[1..($cfg1Lines.Count - 1)] } else { @() }
                        }
                    } else {
                        $cfg1Lines = $allLines1
                    }
                }
            }
        }

        $auth2Name = ''
        $cfg2Lines = @()
        if ($Row2.PSObject.Properties['AuthTemplate'] -and $Row2.PSObject.Properties['Config']) {
            $auth2Name = ''
            # Prefer the parser-assigned AuthTemplate for display; fallback to
            # ComputedTemplate only when AuthTemplate is missing.
            if ($Row2.PSObject.Properties['AuthTemplate'] -and $Row2.AuthTemplate) {
                $auth2Name = '' + $Row2.AuthTemplate
            } elseif ($Row2.PSObject.Properties['ComputedTemplate'] -and $Row2.ComputedTemplate) {
                $auth2Name = '' + $Row2.ComputedTemplate
            }
            $cfgRaw2   = '' + ($Row2.Config)
            if ($cfgRaw2 -and $cfgRaw2.Trim() -ne '') {
                $cfg2Lines = @($cfgRaw2 -split "`r?`n")
            } else {
                $cfg2Lines = @()
            }
        } else {
            $tooltip2 = '' + ($Row2.ToolTip)
            if ($tooltip2) {
                $allLines2 = @($tooltip2 -split "`r?`n")
                if ($allLines2.Count -gt 0) {
                    $m2 = [regex]::Match($allLines2[0], '^\s*AuthTemplate\s*:\s*(.+)$', 'IgnoreCase')
                    if ($m2.Success) {
                        $auth2Name = $m2.Groups[1].Value.Trim()
                        $cfg2Lines = $allLines2[1..($allLines2.Count - 1)]
                        while ($cfg2Lines.Count -gt 0 -and ($cfg2Lines[0].Trim() -eq '')) {
                            $cfg2Lines = if ($cfg2Lines.Count -gt 1) { $cfg2Lines[1..($cfg2Lines.Count - 1)] } else { @() }
                        }
                    } else {
                        $cfg2Lines = $allLines2
                    }
                }
            }
        }

        # Update the template labels, prefixing with "Template:" if a name exists
        if ($script:auth1Text) {
            $script:auth1Text.Text = if ($auth1Name) { "Template: $auth1Name" } else { '' }
            # Colour the template text according to the port's template colour.  Use a
            # BrushConverter to support arbitrary colour names and hex codes.  If
            # conversion fails, fall back to Black.
            try {
                # Debug: log which colour will be used for the left template label before conversion
                try { Write-Host ("[Set-CompareFromRows] Setting left template colour to '$color1'") -ForegroundColor DarkCyan } catch { }
                # Always use BrushConverter to interpret colour names or hex codes.
                # Fall back to black only if conversion fails.
                $bc = New-Object System.Windows.Media.BrushConverter
                $script:auth1Text.Foreground = $bc.ConvertFromString($color1)
            } catch {
                $script:auth1Text.Foreground = [System.Windows.Media.Brushes]::Black
            }
        }
        if ($script:auth2Text) {
            $script:auth2Text.Text = if ($auth2Name) { "Template: $auth2Name" } else { '' }
            try {
                # Debug: log which colour will be used for the right template label before conversion
                try { Write-Host ("[Set-CompareFromRows] Setting right template colour to '$color2'") -ForegroundColor DarkCyan } catch { }
                # Always use BrushConverter for the right side as well.  Fallback to black on failure.
                $bc2 = New-Object System.Windows.Media.BrushConverter
                $script:auth2Text.Foreground = $bc2.ConvertFromString($color2)
            } catch {
                $script:auth2Text.Foreground = [System.Windows.Media.Brushes]::Black
            }
        }

        # Append the device-level AuthBlock to each config if not already present.
        # Check for the marker and, if missing, query the AuthBlock and append it.
        $containsAuth1 = $false
        foreach ($lna in $cfg1Lines) { if ($lna -match '(?i)GLOBAL AUTH BLOCK') { $containsAuth1 = $true; break } }
        if (-not $containsAuth1) {
            $abL = Get-AuthBlockForHost -Hostname $Row1.Hostname
            if ($abL -and $abL.Count -gt 0) {
                $cfg1Lines += ''
                $cfg1Lines += '! GLOBAL AUTH BLOCK'
                $cfg1Lines += $abL
                try { Write-Host ("[Set-CompareFromRows] Appended AuthBlock to config for $($Row1.Hostname)") -ForegroundColor DarkCyan } catch { }
            }
        }
        $containsAuth2 = $false
        foreach ($lnb in $cfg2Lines) { if ($lnb -match '(?i)GLOBAL AUTH BLOCK') { $containsAuth2 = $true; break } }
        if (-not $containsAuth2) {
            $abR = Get-AuthBlockForHost -Hostname $Row2.Hostname
            if ($abR -and $abR.Count -gt 0) {
                $cfg2Lines += ''
                $cfg2Lines += '! GLOBAL AUTH BLOCK'
                $cfg2Lines += $abR
                try { Write-Host ("[Set-CompareFromRows] Appended AuthBlock to config for $($Row2.Hostname)") -ForegroundColor DarkCyan } catch { }
            }
        }
        # Convert configuration arrays back into strings for the UI
        $cfg1Text = ($cfg1Lines -join "`r`n")
        $cfg2Text = ($cfg2Lines -join "`r`n")
        if ($script:config1Box) {
            $script:config1Box.Text = $cfg1Text
            # Always display configuration text in black for readability
            $script:config1Box.Foreground = [System.Windows.Media.Brushes]::Black
            # Compute a dynamic height based on the number of lines.  Each
            # line is approximately 18 pixels tall (12pt font plus
            # padding).  We deliberately do not clamp to an upper bound so
            # that the box grows tall enough to display all lines.  A
            # minimum height of 40 pixels ensures at least one line is
            # visible.
            $lineCount1 = if ($cfg1Lines) { $cfg1Lines.Count } else { 1 }
            $height1 = [Math]::Max(40, $lineCount1 * 18)
            $script:config1Box.Height = $height1
        }
        if ($script:config2Box) {
            $script:config2Box.Text = $cfg2Text
            $script:config2Box.Foreground = [System.Windows.Media.Brushes]::Black
            $lineCount2 = if ($cfg2Lines) { $cfg2Lines.Count } else { 1 }
            $height2 = [Math]::Max(40, $lineCount2 * 18)
            $script:config2Box.Height = $height2
        }

        # Compute differences on the trimmed, non-empty configuration lines
        $diffList1 = @(); $diffList2 = @()
        $cfg1LinesTrim = @(); if ($cfg1Lines) { $cfg1LinesTrim = $cfg1Lines | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } }
        $cfg2LinesTrim = @(); if ($cfg2Lines) { $cfg2LinesTrim = $cfg2Lines | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } }
        $comparison = $null
        try {
            $comparison = Compare-Object -ReferenceObject $cfg1LinesTrim -DifferenceObject $cfg2LinesTrim
        } catch {
            $comparison = $null
        }
        if ($comparison) {
            $diffList1 = @($comparison | Where-Object { $_.SideIndicator -eq '<=' } | Select-Object -ExpandProperty InputObject)
            $diffList2 = @($comparison | Where-Object { $_.SideIndicator -eq '=>' } | Select-Object -ExpandProperty InputObject)
        }
        if ($script:diff1Box) { $script:diff1Box.Text = ($diffList1 -join "`r`n") }
        if ($script:diff2Box) { $script:diff2Box.Text = ($diffList2 -join "`r`n") }
    } catch {
        # On failure, clear all text boxes to avoid partial displays
        if ($script:auth1Text)  { $script:auth1Text.Text  = '' }
        if ($script:auth2Text)  { $script:auth2Text.Text  = '' }
        if ($script:config1Box) {
            $script:config1Box.Text = ''
            # Reset to a minimal height (approx 40px) when no content is present
            $script:config1Box.Height = 40
        }
        if ($script:config2Box) {
            $script:config2Box.Text = ''
            $script:config2Box.Height = 40
        }
        if ($script:diff1Box)   { $script:diff1Box.Text   = '' }
        if ($script:diff2Box)   { $script:diff2Box.Text   = '' }
        Write-Warning "Set-CompareFromRows failed: $($_.Exception.Message)"
    }
}

<#
    Helper: Compute and display the comparison based on the current
    selections in the dropdown controls.  If both a switch and port
    selection exist for each side, it retrieves the perâ€‘port tooltips
    via Get-InterfaceInfo, sets the configuration text boxes and
    populates the difference panels.  Colours are derived from the
    PortColor property on each interface.
#>
function Show-CurrentComparison {
    try {
        # Always ensure the interface commands are available before performing
        # any lookups.  Without this, Get-InterfaceInfo may not be loaded
        # when the Compare view is invoked independently of the Interfaces tab.
        try { Ensure-InterfaceCommands } catch { }

        $s1 = if ($script:switch1Dropdown) { $script:switch1Dropdown.SelectedItem } else { $null }
        $p1 = if ($script:port1Dropdown)   { $script:port1Dropdown.SelectedItem   } else { $null }
        $s2 = if ($script:switch2Dropdown) { $script:switch2Dropdown.SelectedItem } else { $null }
        $p2 = if ($script:port2Dropdown)   { $script:port2Dropdown.SelectedItem   } else { $null }

        # Note: We no longer refresh the port lists here.  The switch
        # selection event handlers (in New-CompareView) and Update-CompareView
        # are responsible for populating the port dropdowns.  Removing this
        # automatic refresh prevents unintended clearing of one side when the
        # other is changed and avoids recursive SelectionChanged events.

        # Determine whether each side has both a switch and port selected
        $show1 = ($s1 -and $p1)
        $show2 = ($s2 -and $p2)

        # Retrieve rows for each selected side independently by querying the
        # database through Get-InterfaceInfo.  Do not rely on the global
        # interfaces grid for lookups; the grid may only contain data for the
        # currently selected device in the main window.  By always calling
        # Get-InterfaceInfo we ensure we have the full set of ports and the
        # ToolTip/PortColor properties needed for comparison.  Exceptions are
        # swallowed so that a missing host or port simply yields an empty row.
        $row1 = $null
        $row2 = $null
        if ($show1) {
            try {
                $tmp1 = Get-InterfaceInfo -Hostname $s1
                if ($tmp1) {
                    $row1 = @($tmp1 | Where-Object { $_.Port -eq $p1 } | Select-Object -First 1)
                }
            } catch {
                $row1 = $null
            }
            # Fallback to the interfaces grid if the row could not be found via DB
            if (-not $row1) {
                try {
                    # Attempt to retrieve the row from the interfaces grid as a secondary fallback
                    $row1 = Get-GridRowFor -Hostname $s1 -Port $p1
                } catch {
                    $row1 = $null
                }
            }
            # Final fallback: query the database directly for the specific interface if no row was found
            if (-not $row1) {
                try {
                    $row1 = Get-InterfaceRowFromDb -Hostname $s1 -Port $p1
                } catch {
                    $row1 = $null
                }
            }
            # Debug: output whether the row was found for side 1 and basic details.  Display
            # the template name if available, otherwise the first line of the tooltip.
            try {
                $status1 = if ($row1) { 'found' } else { 'not found' }
                $port1Dbg = if ($p1) { $p1 } else { '(none)' }
                $tpl1Dbg  = ''
                if ($row1) {
                    if ($row1.PSObject.Properties['AuthTemplate']) {
                        $tpl1Dbg = "AuthTemplate: " + ($row1.AuthTemplate)
                    } elseif ($row1.ToolTip) {
                        $tpl1Dbg = ($row1.ToolTip -split "`r?`n")[0]
                    } else {
                        $tpl1Dbg = '(no template)'
                    }
                } else {
                    $tpl1Dbg = '(no row)'
                }
                Write-Host ("[Show-CurrentComparison] Side 1 ($s1 $port1Dbg): $status1. Info: $tpl1Dbg") -ForegroundColor DarkCyan
                # Debug: display the PortColor of the retrieved row on the left side
                try {
                    if ($row1) {
                        Write-Host ("[Show-CurrentComparison] Side 1 colour: PortColor=$($row1.PortColor)") -ForegroundColor DarkCyan
                    }
                } catch { }
            } catch { }
        }
        if ($show2) {
            try {
                $tmp2 = Get-InterfaceInfo -Hostname $s2
                if ($tmp2) {
                    $row2 = @($tmp2 | Where-Object { $_.Port -eq $p2 } | Select-Object -First 1)
                }
            } catch {
                $row2 = $null
            }
            if (-not $row2) {
                try {
                    $row2 = Get-GridRowFor -Hostname $s2 -Port $p2
                } catch {
                    $row2 = $null
                }
            }
            # Final fallback: query the database directly for the specific interface on the right side
            if (-not $row2) {
                try {
                    $row2 = Get-InterfaceRowFromDb -Hostname $s2 -Port $p2
                } catch {
                    $row2 = $null
                }
            }
            # Debug: output whether the row was found for side 2 and basic details.  Display
            # the template name if available, otherwise the first line of the tooltip.
            try {
                $status2 = if ($row2) { 'found' } else { 'not found' }
                $port2Dbg = if ($p2) { $p2 } else { '(none)' }
                $tpl2Dbg  = ''
                if ($row2) {
                    if ($row2.PSObject.Properties['AuthTemplate']) {
                        $tpl2Dbg = "AuthTemplate: " + ($row2.AuthTemplate)
                    } elseif ($row2.ToolTip) {
                        $tpl2Dbg = ($row2.ToolTip -split "`r?`n")[0]
                    } else {
                        $tpl2Dbg = '(no template)'
                    }
                } else {
                    $tpl2Dbg = '(no row)'
                }
                Write-Host ("[Show-CurrentComparison] Side 2 ($s2 $port2Dbg): $status2. Info: $tpl2Dbg") -ForegroundColor DarkCyan
                # Debug: display the PortColor of the retrieved row on the right side
                try {
                    if ($row2) {
                        Write-Host ("[Show-CurrentComparison] Side 2 colour: PortColor=$($row2.PortColor)") -ForegroundColor DarkCyan
                    }
                } catch { }
            } catch { }
        }

        # If both rows exist, use the full compare logic (which also computes diffs)
        if ($row1 -and $row2) {
            Set-CompareFromRows -Row1 $row1 -Row2 $row2
            return
        }

        # Otherwise update each side separately and clear the diff panels.  This
        # allows technicians to examine the config of a single port without
        # selecting a comparison partner.
        # Left side update
        if ($row1) {
            # Determine the template name and configuration lines for the left side.
            $auth1Name = ''
            $cfg1Lines = @()
            if ($row1.PSObject.Properties['AuthTemplate'] -and $row1.PSObject.Properties['Config']) {
                # Use the AuthTemplate and Config properties if they are present.
                $auth1Name = '' + $row1.AuthTemplate
                $cfgRawL = '' + ($row1.Config)
                if ($cfgRawL -and $cfgRawL.Trim() -ne '') {
                    $cfg1Lines = @($cfgRawL -split "`r?`n")
                } else {
                    $cfg1Lines = @()
                }
            } else {
                # Fallback: parse the tooltip for the template name and config lines.
                $tooltipL = '' + ($row1.ToolTip)
                if ($tooltipL) {
                    $allLinesL = @($tooltipL -split "`r?`n")
                    if ($allLinesL.Count -gt 0) {
                        $mL = [regex]::Match($allLinesL[0], '^\s*AuthTemplate\s*:\s*(.+)$', 'IgnoreCase')
                        if ($mL.Success) {
                            $auth1Name = $mL.Groups[1].Value.Trim()
                            $cfg1Lines = if ($allLinesL.Count -gt 1) { $allLinesL[1..($allLinesL.Count - 1)] } else { @() }
                            while ($cfg1Lines.Count -gt 0 -and ($cfg1Lines[0].Trim() -eq '')) {
                                $cfg1Lines = if ($cfg1Lines.Count -gt 1) { $cfg1Lines[1..($cfg1Lines.Count - 1)] } else { @() }
                            }
                        } else {
                            $cfg1Lines = $allLinesL
                        }
                    }
                }
            }
            # Update the template label text and colour.  Prefer the computed template name
            # if available, falling back to the database AuthTemplate.  This keeps the
            # display aligned with the actual configuration rather than the DB label.
            if ($script:auth1Text) {
                $dispNameL = ''
                if ($row1.PSObject.Properties['ComputedTemplate'] -and $row1.ComputedTemplate) {
                    $dispNameL = '' + $row1.ComputedTemplate
                } elseif ($row1.PSObject.Properties['AuthTemplate']) {
                    $dispNameL = '' + $row1.AuthTemplate
                }
                $script:auth1Text.Text = if ($dispNameL) { "Template: $dispNameL" } else { '' }
                # Colour according to port's template colour
                # Determine the colour for the left template label.  Do not rely on
                # PSObject.Properties here because it may be $null on certain
                # objects like DataRow.  Instead, access PortColor directly
                # and fall back to Black when not present or empty.
                $colorL = 'Black'
                try {
                    if ($row1) {
                        $cTmp = $row1.PortColor
                        if ($cTmp -ne $null -and "$cTmp".Trim() -ne '') { $colorL = '' + $cTmp }
                    }
                } catch { }
                # Debug: log the colour selected for the left template label
                try {
                    Write-Host ("[Show-CurrentComparison] Setting left label colour to '$($colorL)'") -ForegroundColor DarkCyan
                } catch { }
                # Use BrushConverter to allow custom colours; fall back to standard Brushes on failure
                try {
                    # Use BrushConverter exclusively; fallback to black on failure
                    $bcL = New-Object System.Windows.Media.BrushConverter
                    $script:auth1Text.Foreground = $bcL.ConvertFromString($colorL)
                } catch {
                    $script:auth1Text.Foreground = [System.Windows.Media.Brushes]::Black
                }
            }
            if ($script:config1Box) {
                # Append the device-level AuthBlock if it is not already included in the config.
                $containsAuth1 = $false
                foreach ($ln in $cfg1Lines) {
                    if ($ln -match '(?i)GLOBAL AUTH BLOCK') { $containsAuth1 = $true; break }
                }
                if (-not $containsAuth1) {
                    $abLinesL = Get-AuthBlockForHost -Hostname $s1
                    if ($abLinesL -and $abLinesL.Count -gt 0) {
                        $cfg1Lines += ''
                        $cfg1Lines += '! GLOBAL AUTH BLOCK'
                        $cfg1Lines += $abLinesL
                        try { Write-Host ("[Show-CurrentComparison] Appended AuthBlock to config for $s1 (left)") -ForegroundColor DarkCyan } catch { }
                    }
                }
                # Debug: output how many configuration lines were loaded for the left side and
                # show the first non-empty line if available.  This helps verify that
                # the raw Config property is being used rather than the tooltip.
                try {
                    $lineCountDbgL = if ($cfg1Lines) { $cfg1Lines.Count } else { 0 }
                    # Find the first non-empty line in the config
                    $firstLineL = '(none)'
                    if ($cfg1Lines) {
                        foreach ($lnDbg in $cfg1Lines) {
                            if ($lnDbg.Trim() -ne '') { $firstLineL = $lnDbg.Trim(); break }
                        }
                    }
                    # Use subexpressions $() around variables followed by a colon to prevent
                    # PowerShell from interpreting the colon as part of the variable name.
                    Write-Host (
                        "[Show-CurrentComparison] Config lines for $($s1) $($p1): $($lineCountDbgL). First line: $($firstLineL)"
                    ) -ForegroundColor DarkCyan
                } catch { }
                # Set the configuration text and adjust the textbox height
                $cfgTextL = ($cfg1Lines -join "`r`n")
                $script:config1Box.Text = $cfgTextL
                $script:config1Box.Foreground = [System.Windows.Media.Brushes]::Black
                $lineCountL = if ($cfg1Lines) { $cfg1Lines.Count } else { 1 }
                $heightL = [Math]::Max(40, $lineCountL * 18)
                $script:config1Box.Height = $heightL
            }
        } else {
            # No row; clear left side
            if ($script:auth1Text) { $script:auth1Text.Text = '' }
            if ($script:config1Box) {
                $script:config1Box.Text = ''
                $script:config1Box.Height = 40
            }
        }

        # Right side update
        if ($row2) {
            # Determine the template name and configuration lines for the right side.
            $auth2Name = ''
            $cfg2Lines = @()
            if ($row2.PSObject.Properties['AuthTemplate'] -and $row2.PSObject.Properties['Config']) {
                $auth2Name = '' + $row2.AuthTemplate
                $cfgRawR = '' + ($row2.Config)
                if ($cfgRawR -and $cfgRawR.Trim() -ne '') {
                    $cfg2Lines = @($cfgRawR -split "`r?`n")
                } else {
                    $cfg2Lines = @()
                }
            } else {
                $tooltipR = '' + ($row2.ToolTip)
                if ($tooltipR) {
                    $allLinesR = @($tooltipR -split "`r?`n")
                    if ($allLinesR.Count -gt 0) {
                        $mR = [regex]::Match($allLinesR[0], '^\s*AuthTemplate\s*:\s*(.+)$', 'IgnoreCase')
                        if ($mR.Success) {
                            $auth2Name = $mR.Groups[1].Value.Trim()
                            $cfg2Lines = if ($allLinesR.Count -gt 1) { $allLinesR[1..($allLinesR.Count - 1)] } else { @() }
                            while ($cfg2Lines.Count -gt 0 -and ($cfg2Lines[0].Trim() -eq '')) {
                                $cfg2Lines = if ($cfg2Lines.Count -gt 1) { $cfg2Lines[1..($cfg2Lines.Count - 1)] } else { @() }
                            }
                        } else {
                            $cfg2Lines = $allLinesR
                        }
                    }
                }
            }
            # Update the template label text and colour for the right side
            if ($script:auth2Text) {
                # Prefer the computed template name when available for the right side
                $dispNameR = ''
                if ($row2.PSObject.Properties['ComputedTemplate'] -and $row2.ComputedTemplate) {
                    $dispNameR = '' + $row2.ComputedTemplate
                } elseif ($row2.PSObject.Properties['AuthTemplate']) {
                    $dispNameR = '' + $row2.AuthTemplate
                }
                $script:auth2Text.Text = if ($dispNameR) { "Template: $dispNameR" } else { '' }
                # Determine the colour for the right template label.  Use direct
                # property access to avoid issues with PSObject.Properties when
                # the object originates from a DataRow.  Fall back to Black on
                # failure or null values.
                $colorR = 'Black'
                try {
                    if ($row2) {
                        $cTmpR = $row2.PortColor
                        if ($cTmpR -ne $null -and "$cTmpR".Trim() -ne '') { $colorR = '' + $cTmpR }
                    }
                } catch { }
                # Debug: log the colour selected for the right template label
                try {
                    Write-Host ("[Show-CurrentComparison] Setting right label colour to '$($colorR)'") -ForegroundColor DarkCyan
                } catch { }
                try {
                    # Use BrushConverter exclusively for the right side; fallback to black
                    $bcR = New-Object System.Windows.Media.BrushConverter
                    $script:auth2Text.Foreground = $bcR.ConvertFromString($colorR)
                } catch {
                    $script:auth2Text.Foreground = [System.Windows.Media.Brushes]::Black
                }
            }
            if ($script:config2Box) {
                # Append the device-level AuthBlock to the right side configuration if necessary
                $containsAuth2 = $false
                foreach ($lnR in $cfg2Lines) {
                    if ($lnR -match '(?i)GLOBAL AUTH BLOCK') { $containsAuth2 = $true; break }
                }
                if (-not $containsAuth2) {
                    $abLinesR = Get-AuthBlockForHost -Hostname $s2
                    if ($abLinesR -and $abLinesR.Count -gt 0) {
                        $cfg2Lines += ''
                        $cfg2Lines += '! GLOBAL AUTH BLOCK'
                        $cfg2Lines += $abLinesR
                        try { Write-Host ("[Show-CurrentComparison] Appended AuthBlock to config for $s2 (right)") -ForegroundColor DarkCyan } catch { }
                    }
                }
                # Debug: output how many configuration lines were loaded for the right side and
                # show the first non-empty line if available.  This aids verification that
                # we are using the Config property rather than the tooltip.
                try {
                    $lineCountDbgR = if ($cfg2Lines) { $cfg2Lines.Count } else { 0 }
                    $firstLineR = '(none)'
                    if ($cfg2Lines) {
                        foreach ($lnDbg2 in $cfg2Lines) {
                            if ($lnDbg2.Trim() -ne '') { $firstLineR = $lnDbg2.Trim(); break }
                        }
                    }
                    Write-Host (
                        "[Show-CurrentComparison] Config lines for $($s2) $($p2): $($lineCountDbgR). First line: $($firstLineR)"
                    ) -ForegroundColor DarkCyan
                } catch { }
                # Populate the configuration text and adjust the height
                $cfgTextR = ($cfg2Lines -join "`r`n")
                $script:config2Box.Text = $cfgTextR
                $script:config2Box.Foreground = [System.Windows.Media.Brushes]::Black
                $lineCountR = if ($cfg2Lines) { $cfg2Lines.Count } else { 1 }
                $heightR = [Math]::Max(40, $lineCountR * 18)
                $script:config2Box.Height = $heightR
            }
        } else {
            # No row; clear right side
            if ($script:auth2Text) { $script:auth2Text.Text = '' }
            if ($script:config2Box) {
                $script:config2Box.Text = ''
                $script:config2Box.Height = 40
            }
        }

        # Clear diff panels when both sides are not selected
        if ($script:diff1Box) { $script:diff1Box.Text = '' }
        if ($script:diff2Box) { $script:diff2Box.Text = '' }
        return
    } catch {
        if ($script:auth1Text) { $script:auth1Text.Text = '' }
        if ($script:auth2Text) { $script:auth2Text.Text = '' }
        if ($script:config1Box) { $script:config1Box.Text = '' }
        if ($script:config2Box) { $script:config2Box.Text = '' }
        if ($script:diff1Box)   { $script:diff1Box.Text   = '' }
        if ($script:diff2Box)   { $script:diff2Box.Text   = '' }
        Write-Warning "Failed to compute comparison: $($_.Exception.Message)"
    }
}

function Update-CompareView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Switch1,
        [Parameter(Mandatory)][string]$Interface1,
        [Parameter(Mandatory)][string]$Switch2,
        [Parameter(Mandatory)][string]$Interface2,
        [psobject]$Row1,
        [psobject]$Row2
    )

    if (-not $script:compareView) { return }

    # Re-resolve controls in case New-CompareView ran before XAML fully injected
    if (-not $script:switch1Dropdown) { $script:switch1Dropdown = $script:compareView.FindName('Switch1Dropdown') }
    if (-not $script:port1Dropdown)   { $script:port1Dropdown   = $script:compareView.FindName('Port1Dropdown')   }
    if (-not $script:switch2Dropdown) { $script:switch2Dropdown = $script:compareView.FindName('Switch2Dropdown') }
    if (-not $script:port2Dropdown)   { $script:port2Dropdown   = $script:compareView.FindName('Port2Dropdown')   }
    if (-not $script:config1Box)      { $script:config1Box      = $script:compareView.FindName('Config1Box')      }
    if (-not $script:config2Box)      { $script:config2Box      = $script:compareView.FindName('Config2Box')      }
    if (-not $script:diff1Box)        { $script:diff1Box        = $script:compareView.FindName('Diff1Box')        }
    if (-not $script:diff2Box)        { $script:diff2Box        = $script:compareView.FindName('Diff2Box')        }
    if (-not $script:auth1Text)       { $script:auth1Text       = $script:compareView.FindName('AuthTemplate1Text') }
    if (-not $script:auth2Text)       { $script:auth2Text       = $script:compareView.FindName('AuthTemplate2Text') }

    try {
        # Always populate the switch lists from the database rather than relying on
        # the main window's host dropdown.  This decouples the compare view
        # from the state of the Interfaces tab.  Ensure the necessary
        # interface commands are loaded first, then call Get-DeviceSummaries.
        # Always populate the switch lists from the database.  If the list is empty,
        # fall back to the main window's HostnameDropdown list so that the
        # dropdowns are not blank.  This fallback ensures usability when the
        # database path has not been initialised yet.
        $hosts = @()
        try {
            # Load device hostnames directly from the database without updating the main window
            if ($global:StateTraceDb -and (Get-Command Invoke-DbQuery -ErrorAction SilentlyContinue)) {
                $dtHosts = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Hostname FROM DeviceSummary ORDER BY Hostname"
                if ($dtHosts) {
                    if ($dtHosts -is [System.Data.DataTable]) {
                        foreach ($r in $dtHosts.Rows) { $hosts += '' + $r.Hostname }
                    } else {
                        foreach ($r in $dtHosts) { if ($r.PSObject.Properties['Hostname']) { $hosts += '' + $r.Hostname } }
                    }
                }
            }
        } catch {
            $hosts = @()
        }
        # If no hosts were loaded from the DB, fall back to the main window's
        # HostnameDropdown list.  Avoid invoking Get-DeviceSummaries here because
        # that function updates the primary interface state (selects the first
        # device) and triggers unwanted side effects.  Reading the ItemsSource
        # directly does not affect the main UI and preserves independence.
        if (-not $hosts -or $hosts.Count -eq 0) {
            try {
                if ($script:windowRef) {
                    $hostDD = $script:windowRef.FindName('HostnameDropdown')
                    if ($hostDD -and $hostDD.ItemsSource) {
                        $hosts = @($hostDD.ItemsSource)
                    } else {
                        $hosts = @()
                    }
                } else {
                    $hosts = @()
                }
            } catch {
                $hosts = @()
            }
        }
        if ($script:switch1Dropdown) { $script:switch1Dropdown.ItemsSource = $hosts }
        if ($script:switch2Dropdown) { $script:switch2Dropdown.ItemsSource = $hosts }

        # Debug: output loaded hosts and database path in update scenario.  This
        # assists in diagnosing when the host list appears empty after a
        # comparison is initiated from the Interfaces view.
        try {
            $dbPathDbg2 = if ($global:StateTraceDb) { $global:StateTraceDb } else { '(null)' }
            $hostDbg2  = if ($hosts) { $hosts -join ', ' } else { '(none)' }
            Write-Host ("[Update-CompareView] DB path: $dbPathDbg2") -ForegroundColor DarkCyan
            Write-Host ("[Update-CompareView] Hosts loaded ($($hosts.Count)): $hostDbg2") -ForegroundColor DarkCyan
        } catch { }

        # Select devices
        if ($script:switch1Dropdown) { $script:switch1Dropdown.SelectedItem = $Switch1 }
        if ($script:switch2Dropdown) { $script:switch2Dropdown.SelectedItem = $Switch2 }

        # Populate ports from the grid (fallback to DB)
        if ($script:port1Dropdown) {
            try {
                # Ensure interface commands before fetching ports
                try { Ensure-InterfaceCommands } catch { }
                $script:port1Dropdown.ItemsSource = @(Get-PortsForHost -Hostname $Switch1)
            } catch { $script:port1Dropdown.ItemsSource = @() }
            $script:port1Dropdown.SelectedItem = $Interface1
        }
        if ($script:port2Dropdown) {
            try {
                try { Ensure-InterfaceCommands } catch { }
                $script:port2Dropdown.ItemsSource = @(Get-PortsForHost -Hostname $Switch2)
            } catch { $script:port2Dropdown.ItemsSource = @() }
            $script:port2Dropdown.SelectedItem = $Interface2
        }

        # Render immediately if rows were provided by the Interfaces view
        if ($Row1 -and $Row2) {
            Set-CompareFromRows -Row1 $Row1 -Row2 $Row2
        } else {
            Show-CurrentComparison
        }
    } catch {
        Write-Warning "Failed to update compare view: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function New-CompareView,Update-CompareView