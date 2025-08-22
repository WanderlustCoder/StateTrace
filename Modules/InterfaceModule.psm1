<#
    .SYNOPSIS
        Combined module providing both the back‑end data functions and
        the user‑interface wiring for the Interfaces tab in the Network
        Reader GUI.

    .DESCRIPTION
        This module merges the functionality previously split between
        InterfaceModule.psm1 and InterfacesViewModule.psm1.  It exposes
        helper functions to query interface summaries, interface details,
        compare interface configurations and build new interface
        configurations, as well as the view initialisation logic used
        by the main window.  Where possible the implementation has been
        simplified to rely solely on the Access database for data rather
        than falling back to legacy CSV files.  Stale code paths and
        duplicate logic have been removed entirely.

        To initialise the Interfaces view, import this module and call
        `Initialize-InterfacesView` from your main script.  The other
        exported functions may be used by other view modules or helper
        scripts as required.

    .EXAMPLE
        Import-Module (Join-Path $scriptDir '..\Modules\InterfaceModule.psm1') -Force
        Initialize-InterfacesView -Window $window -ScriptDir $scriptDir
#>

Set-StrictMode -Version Latest

# Define a default path to the Interfaces view XAML.  This allows the
# module to locate its own view definition relative to its installation
# directory without relying on external variables such as `$ScriptDir`.
# Consumers may override this by passing the `-InterfacesViewXaml` parameter
# when calling `New-InterfacesView`.  See function definition below.
$script:InterfacesViewXamlDefault = Join-Path $PSScriptRoot '..\Views\InterfacesView.xaml'

function Get-InterfaceHostnames {
    <#
        .SYNOPSIS
            Return a list of all device hostnames known to the database.

        .DESCRIPTION
            Queries the DeviceSummary table in the StateTrace database and
            returns the Hostname column as a simple string array.  If the
            global database path (`$global:StateTraceDb`) has not been
            initialised, an empty array is returned.  Legacy CSV fallbacks
            have been removed – parsed CSV files are no longer consulted.

        .PARAMETER ParsedDataPath
            Ignored in this implementation.  Retained only for backwards
            compatibility with existing scripts that might still pass it.

        .OUTPUTS
            System.String[]

        .EXAMPLE
            $hosts = Get-InterfaceHostnames
    #>
    [CmdletBinding()]
    param([string]$ParsedDataPath)
    # Delegate to DeviceDataModule implementation.  The central module defines
    # Get-InterfaceHostnames which reads from the StateTrace database.  Pass
    # through all bound parameters to preserve backwards compatibility.  This
    # wrapper prevents duplicated logic in this module.
    return DeviceDataModule\Get-InterfaceHostnames @PSBoundParameters
}

function Get-InterfaceInfo {
    <#
        .SYNOPSIS
            Retrieves per‑interface details for a given device.

        .DESCRIPTION
            Queries the Interfaces table for all ports belonging to the
            specified hostname.  It then enriches the result with colour
            and compliance information based on the configured vendor
            templates (Cisco or Brocade), which are loaded from JSON files
            in the Templates folder.  If the database is not available or
            the query fails, an empty array is returned.  Legacy CSV
            fallbacks have been removed.

        .PARAMETER Hostname
            The device hostname whose interfaces should be returned.

        .PARAMETER TemplatesPath
            Optional path to the Templates directory.  If omitted, a
            relative path of `..\Templates` from the module location is
            used.

        .OUTPUTS
            PSCustomObject[]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )
    # Delegate to DeviceDataModule implementation.  This wrapper calls the
    # central Get-InterfaceInfo function defined in DeviceDataModule to
    # retrieve interface details and perform vendor-specific enrichment.  It
    # preserves the existing parameter set by passing through all bound
    # parameters via $PSBoundParameters.  By returning immediately, the
    # remainder of this function (legacy implementation) is bypassed.
    return DeviceDataModule\Get-InterfaceInfo @PSBoundParameters
    <#
        The legacy implementation that followed this return statement
        has been removed.  The logic to query the database, enrich
        results with template metadata and append Brocade authentication
        blocks now lives exclusively in DeviceDataModule.  This wrapper
        delegates to the central function and exits early, ensuring
        there is no duplicated or unreachable code in this module.  Any
        code appearing after this comment is intentionally disabled.
    #>
}

function Compare-InterfaceConfigs {
    <#
        .SYNOPSIS
            Launches a comparison of two interfaces' configurations.

        .DESCRIPTION
            This helper invokes an external PowerShell script (`CompareConfigs.ps1`)
            to produce a side‑by‑side comparison of interface configuration
            differences.  The script is executed in a hidden PowerShell
            process and waits for completion.  No CSV logic is involved.

        .PARAMETER Switch1
            Hostname of the first switch.

        .PARAMETER Interface1
            Port identifier on the first switch.

        .PARAMETER Switch2
            Hostname of the second switch.

        .PARAMETER Interface2
            Port identifier on the second switch.

        .PARAMETER ScriptPath
            Optional path to the CompareConfigs.ps1 script.  By default
            resolves to a ../Main/CompareConfigs.ps1 relative to this
            module's location.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Switch1,
        [Parameter(Mandatory)][string]$Interface1,
        [Parameter(Mandatory)][string]$Switch2,
        [Parameter(Mandatory)][string]$Interface2,
        [string]$ScriptPath = (Join-Path $PSScriptRoot '..\Main\CompareConfigs.ps1')
    )
    <#
        Prior to the refactor this function launched an external PowerShell
        script to render a side‑by‑side comparison of two interfaces' configurations.
        The in‑application Compare view now implements its own diff logic and
        obtains all necessary configuration data from DeviceDataModule.  To avoid
        confusion and unintended external process launches the legacy behaviour
        has been disabled.  Should external comparisons be required in the
        future, implement a suitable helper in DeviceDataModule and call it
        from the Compare view instead.
    #>
    throw "External compare script invocation has been removed. Please use the Compare sidebar to view diffs."
}

function Get-InterfaceConfiguration {
    <#
        .SYNOPSIS
            Builds port configuration snippets based on a selected template.

        .DESCRIPTION
            Given a hostname, a list of port identifiers and a template name,
            this function constructs a set of configuration commands to
            apply the template to each port.  It queries existing
            configurations from the database in order to remove obsolete
            authentication commands.  Name and VLAN overrides can be
            supplied via hashtables.  Legacy CSV fallbacks have been
            removed; when the database is unavailable, an empty array is
            returned.

        .PARAMETER Hostname
            The device hostname.

        .PARAMETER Interfaces
            An array of port identifiers to which the template should be applied.

        .PARAMETER TemplateName
            The name of the template to apply.

        .PARAMETER NewNames
            A hashtable mapping ports to new descriptive names.  Optional.

        .PARAMETER NewVlans
            A hashtable mapping ports to new VLAN identifiers.  Optional.

        .PARAMETER TemplatesPath
            Optional path to the Templates directory.  Defaults to ../Templates
            relative to this module.  Used to load Cisco/Brocade template
            JSON files.

        .OUTPUTS
            System.String[]  – an array of configuration lines.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]  $Hostname,
        [Parameter(Mandatory)][string[]]$Interfaces,
        [Parameter(Mandatory)][string]  $TemplateName,
        [hashtable]$NewNames,
        [hashtable]$NewVlans,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )
    # Delegate to DeviceDataModule implementation.  This wrapper calls the
    # central Get-InterfaceConfiguration function defined in DeviceDataModule
    # to build port configuration snippets based on the selected template.
    # It passes through all bound parameters, ensuring that name and VLAN
    # overrides remain supported.
    return DeviceDataModule\Get-InterfaceConfiguration @PSBoundParameters
    <#
        The original implementation that followed this return statement
        has been removed.  The logic for assembling interface
        configuration snippets now resides in DeviceDataModule, so
        InterfaceModule simply forwards the call.  Retaining the
        legacy code here would serve no purpose and might cause
        confusion if accidentally executed.  Any code that previously
        existed below this comment is intentionally disabled.
    #>
}

function Get-SpanningTreeInfo {
    <#
        .SYNOPSIS
            Retrieves spanning tree information for a device.

        .DESCRIPTION
            This function reads a CSV file named `<Hostname>_Span.csv` from
            the ParsedData directory and returns its contents as an array of
            objects.  At present the database does not store spanning tree
            data, so the CSV remains the sole source of information.  If the
            file does not exist or cannot be parsed, an empty array is
            returned.

        .PARAMETER Hostname
            The device hostname whose spanning tree data should be loaded.

        .PARAMETER ParsedDataPath
            Optional path to the ParsedData directory.  Defaults to
            `..\ParsedData` relative to this module.

        .OUTPUTS
            PSCustomObject[]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [string]$ParsedDataPath = (Join-Path $PSScriptRoot '..\ParsedData')
    )
    $spanFile = Join-Path $ParsedDataPath "${Hostname}_Span.csv"
    if (Test-Path $spanFile) {
        try {
            return Import-Csv $spanFile
        } catch {
            # Use formatted string expansion to avoid variable parsing issues with colon
            Write-Warning (
                "Failed to parse spanning tree CSV for {0}: {1}" -f $Hostname, $_.Exception.Message
            )
            return @()
        }
    }
    return @()
}

function Get-ConfigurationTemplates {
    <#
        .SYNOPSIS
            Returns a list of available configuration template names for a device.

        .DESCRIPTION
            Determines the vendor of the specified device by querying the
            DeviceSummary table, then loads the corresponding template JSON
            (Cisco.json or Brocade.json) from the Templates directory and
            returns the names of all templates.  Legacy CSV fallbacks have
            been removed.  If the database is unavailable or the JSON file
            cannot be loaded, an empty array is returned.

        .PARAMETER Hostname
            The device hostname.

        .PARAMETER TemplatesPath
            Optional path to the Templates directory.  Defaults to
            `..\Templates` relative to this module.

        .OUTPUTS
            System.String[]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )
    # Delegate to DeviceDataModule implementation.  This wrapper calls the
    # central Get-ConfigurationTemplates function defined in DeviceDataModule
    # which determines the vendor, loads the appropriate JSON and returns
    # available template names.  Pass through all bound parameters.
    return DeviceDataModule\Get-ConfigurationTemplates @PSBoundParameters
    <#
        The legacy implementation that queried the DeviceSummary table and
        manually loaded template JSON files has been removed.  All
        template retrieval logic now lives in DeviceDataModule.  This
        function simply proxies the call and exits immediately.  Any
        code that was previously present below this comment is intentionally
        disabled.
    #>
}

function New-InterfacesView {
    [CmdletBinding()]
    param(
        # Parent window into which the Interfaces view will be loaded.
        [Parameter(Mandatory=$true)]
        [System.Windows.Window]$Window,
        # Optional script directory.  When provided, the view XAML will be
        # resolved relative to this path (../Views/InterfacesView.xaml).
        [string]$ScriptDir,
        # Optional explicit path to the Interfaces view XAML.  When
        # specified, this overrides both the ScriptDir and the module's
        # default view path.  Use this to load a custom view definition.
        [string]$InterfacesViewXaml
    )

    # Determine the XAML path to load.  Priority order:
    # 1) caller provided -InterfacesViewXaml argument
    # 2) caller provided -ScriptDir argument
    # 3) module default ($script:InterfacesViewXamlDefault)
    $interfacesViewXamlPath = $null
    if ($PSBoundParameters.ContainsKey('InterfacesViewXaml') -and $InterfacesViewXaml) {
        $interfacesViewXamlPath = $InterfacesViewXaml
    } elseif ($ScriptDir) {
        $interfacesViewXamlPath = Join-Path $ScriptDir '..\Views\InterfacesView.xaml'
    } else {
        $interfacesViewXamlPath = $script:InterfacesViewXamlDefault
    }

    # Validate that the XAML file exists before proceeding.
    if (-not (Test-Path $interfacesViewXamlPath)) {
        Write-Warning "Missing InterfacesView.xaml at $interfacesViewXamlPath"
        return
    }
    $ifaceXaml   = Get-Content $interfacesViewXamlPath -Raw
    $ifaceReader = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($ifaceXaml))
    $interfacesView = [Windows.Markup.XamlReader]::Load($ifaceReader)

    # Mount view
    $interfacesHost = $Window.FindName('InterfacesHost')
    if ($interfacesHost -is [System.Windows.Controls.ContentControl]) {
        $interfacesHost.Content = $interfacesView
    } else {
        Write-Warning "Could not find ContentControl 'InterfacesHost'"
    }

    # Grab controls
    $compareButton     = $interfacesView.FindName('CompareButton')
    $interfacesGrid    = $interfacesView.FindName('InterfacesGrid')
    $configureButton   = $interfacesView.FindName('ConfigureButton')
    $templateDropdown  = $interfacesView.FindName('ConfigOptionsDropdown')
    $filterBox         = $interfacesView.FindName('FilterBox')
    $clearBtn          = $interfacesView.FindName('ClearFilterButton')
    $copyDetailsButton = $interfacesView.FindName('CopyDetailsButton')

    #
    # Promote frequently used controls to the global scope.  When this function
    # completes, its local variables go out of scope and any scriptblocks
    # attached to UI events will no longer be able to access them.  Assigning
    # the controls to global variables ensures they remain available when
    # invoked later (for example, by the Copy Details button or filter box
    # handlers).  See FurtherFixes.docx step 1 for details.
    #
    if ($interfacesGrid)    { $global:interfacesGrid   = $interfacesGrid }
    if ($templateDropdown)  { $global:templateDropdown = $templateDropdown }
    if ($filterBox)         { $global:filterBox        = $filterBox }

    # ------------------------------
    # Compare button
    if ($compareButton) {
        $compareButton.Add_Click({
        # Prefer globally-scoped grid if we promoted it; fall back to find by name
        $grid = $global:interfacesGrid
        if (-not $grid) { $grid = $interfacesView.FindName('InterfacesGrid') }
        if (-not $grid) {
            [System.Windows.MessageBox]::Show("Interfaces grid not found.")
            return
        }

        # Commit any pending edits before we read selections
        [void]$grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true)
        [void]$grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row,  $true)

        # 1) Rows explicitly highlighted/selected in the grid
        $selectedRows = @($grid.SelectedItems)

        # 2) Rows checked via the checkbox column (robust to items w/o IsSelected)
        $itemsEnum = @()
        if ($grid.ItemsSource -is [System.Collections.IEnumerable]) {
            $itemsEnum = @($grid.ItemsSource)
        }
        $checkedRows = @()
        foreach ($item in $itemsEnum) {
            $prop = $item.PSObject.Properties['IsSelected']  # safe under StrictMode
            if ($prop -and $prop.Value) {
                $checkedRows += $item
            }
        }

        # Prefer checked boxes; fall back to selected rows
        if     ($checkedRows.Count  -eq 2) { $int1,$int2 = $checkedRows }
        elseif ($selectedRows.Count -eq 2) { $int1,$int2 = $selectedRows }
        else {
            [System.Windows.MessageBox]::Show("Select (or check) exactly two interfaces to compare.")
            return
        }

        # Validate we have needed fields
        foreach ($int in @($int1,$int2)) {
            foreach ($req in 'Hostname','Port') {
                if (-not $int.PSObject.Properties[$req]) {
                    [System.Windows.MessageBox]::Show("Selected items are missing '$req'.")
                    return
                }
            }
        }

        try {
            Update-CompareView -Switch1 $int1.Hostname -Interface1 $int1.Port `
                               -Switch2 $int2.Hostname -Interface2 $int2.Port `
                               -Row1 $int1 -Row2 $int2


            # Expand compare sidebar if collapsed
            $col = $Window.FindName('CompareColumn')
            if ($col -is [System.Windows.Controls.ColumnDefinition]) {
                # Expand the Compare sidebar to a wider width.  A 600 pixel width
                # provides enough room for long authentication commands to be displayed
                # without wrapping inside the config text boxes.
                if ($col.Width.Value -eq 0) { $col.Width = [System.Windows.GridLength]::new(600) }
            }
        } catch {
            [System.Windows.MessageBox]::Show("Compare failed:`n$($_.Exception.Message)")
        }
    })

    }

    if ($interfacesGrid) {
        # With SelectionUnit="CellOrRowHeader" and a two-way checkbox binding defined in the XAML, DataGrid checkboxes
        # update the IsSelected property immediately on click without any code-behind.  Therefore we no longer attach
        # preview click handlers or extra Checked/Unchecked handlers here.
    }

    # ------------------------------
    # Configure button (unchanged)
    if ($configureButton -and $interfacesGrid -and $templateDropdown) {
        $configureButton.Add_Click({
            # Use globally scoped grid and dropdown to avoid out-of-scope errors
            $grid = $global:interfacesGrid
            # Collect currently selected rows from the grid
            $selectedRows = @($grid.SelectedItems)
            # Also consider any rows checked via the IsSelected property in the checkbox column
            $checkedRows = @()
            try {
                $itemsEnum = @()
                if ($grid.ItemsSource -is [System.Collections.IEnumerable]) {
                    $itemsEnum = @($grid.ItemsSource)
                }
                foreach ($item in $itemsEnum) {
                    $prop = $item.PSObject.Properties['IsSelected']
                    if ($prop -and $prop.Value) { $checkedRows += $item }
                }
            } catch {}
            # Prefer checked rows when present; otherwise fall back to selected rows
            if ($checkedRows.Count -gt 0) {
                $selectedRows = $checkedRows
            }
            if (-not $selectedRows -or $selectedRows.Count -eq 0) {
                [System.Windows.MessageBox]::Show("No interfaces selected.")
                return
            }
            $template = $global:templateDropdown.SelectedItem
            if (-not $template) {
                [System.Windows.MessageBox]::Show("No template selected.")
                return
            }
            $hostname = $interfacesView.FindName('HostnameBox').Text
            try {
                $namesMap = @{}
                $vlansMap = @{}
                foreach ($int in $selectedRows) {
                    if ($int.Name -and $int.Name -ne '') { $namesMap[$int.Port] = $int.Name }
                    if ($int.VLAN -and $int.VLAN -ne '') { $vlansMap[$int.Port] = $int.VLAN }
                }
                $ports = $selectedRows | ForEach-Object { $_.Port }
                $lines = Get-InterfaceConfiguration -Hostname $hostname -Interfaces $ports -TemplateName $template -NewNames $namesMap -NewVlans $vlansMap
                Set-Clipboard -Value ($lines -join "`r`n")
                [System.Windows.MessageBox]::Show(($lines -join "`n"), "Generated Config")
            } catch {
                [System.Windows.MessageBox]::Show("Failed to build config:`n$($_.Exception.Message)")
            }
        })
    }

    # ------------------------------
    # Filter box
    if ($clearBtn -and $filterBox) {
        $clearBtn.Add_Click({
            # Access filter box via global scope to avoid missing variable errors
            $global:filterBox.Text  = ""
            $global:filterBox.Focus()
        })
    }
    if ($filterBox -and $interfacesGrid) {
        $filterBox.Add_TextChanged({
            # Capture text from globally scoped filter box
            $text = $global:filterBox.Text.ToLower()
            $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($global:interfacesGrid.ItemsSource)
            if ($null -eq $view) { return }
            $view.Filter = {
                param($item)
                return (
                    ($item.Port      -as [string]).ToLower().Contains($text) -or
                    ($item.Name      -as [string]).ToLower().Contains($text) -or
                    ($item.Status    -as [string]).ToLower().Contains($text) -or
                    ($item.VLAN      -as [string]).ToLower().Contains($text) -or
                    ($item.AuthState -as [string]).ToLower().Contains($text)
                )
            }
            $view.Refresh()
        })
    }

    # ------------------------------
    # Copy Details button
    if ($copyDetailsButton -and $interfacesGrid) {
        $copyDetailsButton.Add_Click({
            # Use global interfaces grid to read selected items
            $grid = $global:interfacesGrid
            # Gather selected rows and any rows checked via IsSelected
            $selectedRows = @($grid.SelectedItems)
            $checkedRows  = @()
            try {
                $itemsEnum = @()
                if ($grid.ItemsSource -is [System.Collections.IEnumerable]) {
                    $itemsEnum = @($grid.ItemsSource)
                }
                foreach ($item in $itemsEnum) {
                    $prop = $item.PSObject.Properties['IsSelected']
                    if ($prop -and $prop.Value) { $checkedRows += $item }
                }
            } catch {}
            if ($checkedRows.Count -gt 0) {
                $selectedRows = $checkedRows
            }
            if (-not $selectedRows -or $selectedRows.Count -eq 0) {
                [System.Windows.MessageBox]::Show("No interfaces selected.")
                return
            }
            $hostname = $interfacesView.FindName('HostnameBox').Text
            $header = @("Hostname: $hostname", "------------------------------", "")
            $output = foreach ($int in $selectedRows) {
                @(
                    "Port:        $($int.Port)",
                    "Name:        $($int.Name)",
                    "Status:      $($int.Status)",
                    "VLAN:        $($int.VLAN)",
                    "Duplex:      $($int.Duplex)",
                    "Speed:       $($int.Speed)",
                    "Type:        $($int.Type)",
                    "LearnedMACs: $($int.LearnedMACs)",
                    "AuthState:   $($int.AuthState)",
                    "AuthMode:    $($int.AuthMode)",
                    "Client MAC:  $($int.AuthClientMAC)",
                    "Config:",
                    "$($int.ToolTip)",
                    "------------------------------"
                ) -join "`r`n"
            }
            $final = $header + $output
            Set-Clipboard -Value ($final -join "`r`n")
            [System.Windows.MessageBox]::Show("Copied $($selectedRows.Count) interface(s) to clipboard.")
        })
    }

    # ------------------------------
    # Template dropdown color hint
    # Use global scope to ensure the control remains available when this event fires.
    if ($templateDropdown) {
        $templateDropdown.Add_SelectionChanged({
            $sel = $global:templateDropdown.SelectedItem
            $brush = [System.Windows.Media.Brushes]::Black
            if ($sel) {
                $lower = ('' + $sel).ToLower()
                if     ($lower -match 'cisco')   { $brush = [System.Windows.Media.Brushes]::DodgerBlue }
                elseif ($lower -match 'brocade') { $brush = [System.Windows.Media.Brushes]::Goldenrod }
                elseif ($lower -match 'arista')  { $brush = [System.Windows.Media.Brushes]::MediumSeaGreen }
            }
            $global:templateDropdown.Foreground = $brush
        })
    }

    $global:interfacesView = $interfacesView
}

Export-ModuleMember -Function Get-InterfaceInfo,Compare-InterfaceConfigs,Get-InterfaceConfiguration,Get-ConfigurationTemplates,Get-SpanningTreeInfo,New-InterfacesView
