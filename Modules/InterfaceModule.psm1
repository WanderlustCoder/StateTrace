# .SYNOPSIS

Set-StrictMode -Version Latest

# Ensure that the debounce timer variable exists in script scope.  Under
if (-not (Get-Variable -Name InterfacesFilterTimer -Scope Script -ErrorAction SilentlyContinue)) {
    $script:InterfacesFilterTimer = $null
}

# Helper: Gather selected or checked interface rows using typed lists.  This function
function Get-SelectedInterfaceRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Controls.DataGrid]$Grid
    )
    # Collect rows explicitly selected in the grid
    $selected = [System.Collections.Generic.List[object]]::new()
    foreach ($r in @($Grid.SelectedItems)) {
        [void]$selected.Add($r)
    }
    # Collect rows that have the IsSelected checkbox set
    $checked = [System.Collections.Generic.List[object]]::new()
    if ($Grid.ItemsSource -is [System.Collections.IEnumerable]) {
        foreach ($it in $Grid.ItemsSource) {
            $prop = $it.PSObject.Properties['IsSelected']
            if ($prop -and $prop.Value) {
                [void]$checked.Add($it)
            }
        }
    }
    # Prefer checked rows when present
    if ($checked.Count -gt 0) { return $checked }
    return $selected
}

# Define a default path to the Interfaces view XAML.  This allows the
$script:InterfacesViewXamlDefault = Join-Path $PSScriptRoot '..\Views\InterfacesView.xaml'

function Get-InterfaceHostnames {
    # .SYNOPSIS

    [CmdletBinding()]
    param([string]$ParsedDataPath)
    # Delegate to DeviceDataModule implementation.  The central module defines
    return DeviceDataModule\Get-InterfaceHostnames @PSBoundParameters
}

function Get-InterfaceInfo {
    # .SYNOPSIS

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )
    # Delegate to DeviceDataModule implementation.  This wrapper calls the
    return DeviceDataModule\Get-InterfaceInfo @PSBoundParameters
    # The legacy implementation that followed this return statement

}

function Compare-InterfaceConfigs {
    # .SYNOPSIS

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Switch1,
        [Parameter(Mandatory)][string]$Interface1,
        [Parameter(Mandatory)][string]$Switch2,
        [Parameter(Mandatory)][string]$Interface2,
        [string]$ScriptPath = (Join-Path $PSScriptRoot '..\Main\CompareConfigs.ps1')
    )
    # Prior to the refactor this function launched an external PowerShell

    throw "External compare script invocation has been removed. Please use the Compare sidebar to view diffs."
}

function Get-InterfaceConfiguration {
    # .SYNOPSIS

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
    return DeviceDataModule\Get-InterfaceConfiguration @PSBoundParameters
    # The original implementation that followed this return statement

}

function Get-SpanningTreeInfo {
    # .SYNOPSIS

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
    # .SYNOPSIS

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )
    # Delegate to DeviceDataModule implementation.  This wrapper calls the
    return DeviceDataModule\Get-ConfigurationTemplates @PSBoundParameters
    # The legacy implementation that queried the DeviceSummary table and

}

function New-InterfacesView {
    [CmdletBinding()]
    param(
        # Parent window into which the Interfaces view will be loaded.
        [Parameter(Mandatory=$true)]
        [System.Windows.Window]$Window,
        # Optional script directory.  When provided, the view XAML will be
        [string]$ScriptDir,
        # Optional explicit path to the Interfaces view XAML.  When
        [string]$InterfacesViewXaml
    )

    # Determine the XAML path to load.  Priority order:
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
    if ($interfacesGrid)    { $global:interfacesGrid   = $interfacesGrid }
    if ($templateDropdown)  { $global:templateDropdown = $templateDropdown }
    if ($filterBox)         { $global:filterBox        = $filterBox }

    # ------------------------------
    if ($compareButton) {
        $compareButton.Add_Click({
        # Prefer globally-scoped grid if we promoted it; fall back to find by name
        $grid = $global:interfacesGrid
        if (-not $grid) { $grid = $interfacesView.FindName('InterfacesGrid') }
        if (-not $grid) {
            [System.Windows.MessageBox]::Show("Interfaces grid not found.")
            return
        }
        # Commit any pending edits before reading selections
        [void]$grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true)
        [void]$grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row,  $true)
        # Gather checked or selected rows using typed-list helper
        $rows = Get-SelectedInterfaceRows -Grid $grid
        if ($rows.Count -ne 2) {
            [System.Windows.MessageBox]::Show("Select (or check) exactly two interfaces to compare.")
            return
        }
        $int1,$int2 = $rows

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
            Set-CompareSelection -Switch1 $int1.Hostname -Interface1 $int1.Port `
                               -Switch2 $int2.Hostname -Interface2 $int2.Port `
                               -Row1 $int1 -Row2 $int2

            # Expand compare sidebar if collapsed
            $col = $Window.FindName('CompareColumn')
            if ($col -is [System.Windows.Controls.ColumnDefinition]) {
                # Expand the Compare sidebar to a wider width.  A 600 pixel width
                if ($col.Width.Value -eq 0) { $col.Width = [System.Windows.GridLength]::new(600) }
            }
        } catch {
            [System.Windows.MessageBox]::Show("Compare failed:`n$($_.Exception.Message)")
        }
    })

    }

    if ($interfacesGrid) {
        # With SelectionUnit="CellOrRowHeader" and a two-way checkbox binding defined in the XAML, DataGrid checkboxes
    }

    # ------------------------------
    if ($configureButton -and $interfacesGrid -and $templateDropdown) {
        $configureButton.Add_Click({
            # Use globally scoped grid and dropdown to avoid out-of-scope errors
            $grid = $global:interfacesGrid
            # Gather rows using helper; prefer checked rows
            $selectedRows = Get-SelectedInterfaceRows -Grid $grid
            if ($selectedRows.Count -eq 0) {
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
    if ($clearBtn -and $filterBox) {
        $clearBtn.Add_Click({
            # Access filter box via global scope to avoid missing variable errors
            $global:filterBox.Text  = ""
            $global:filterBox.Focus()
        })
    }
    if ($filterBox -and $interfacesGrid) {
        # Initialise a debounce timer for the filter box if it does not exist.  This
        if (-not $script:InterfacesFilterTimer) {
            $script:InterfacesFilterTimer = New-Object System.Windows.Threading.DispatcherTimer
            # Use a 300ms interval to match the search debounce and allow the user
            $script:InterfacesFilterTimer.Interval = [TimeSpan]::FromMilliseconds(300)
            $script:InterfacesFilterTimer.add_Tick({
                # Stop the timer so it can be restarted by the next key press
                $script:InterfacesFilterTimer.Stop()
                try {
                    # Safely coerce the filter box text to a string.  Avoid calling
                    $txt  = ('' + $global:filterBox.Text)
                    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($global:interfacesGrid.ItemsSource)
                    if ($null -eq $view) { return }
                    $view.Filter = {
                        param($item)
                        # Coerce each field to a string to avoid calling methods on $null.  Casting
                        return (
                            (('' + $item.Port      ).IndexOf($txt, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                            (('' + $item.Name      ).IndexOf($txt, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                            (('' + $item.Status    ).IndexOf($txt, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                            (('' + $item.VLAN      ).IndexOf($txt, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                            (('' + $item.AuthState ).IndexOf($txt, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
                        )
                    }
                    $view.Refresh()
                } catch {
                    # Swallow exceptions to avoid crashing the UI on bad filter values
                }
            })
        }
        # On every key press, restart the debounce timer; the filter will
        $filterBox.Add_TextChanged({
            if ($script:InterfacesFilterTimer) {
                $script:InterfacesFilterTimer.Stop()
                $script:InterfacesFilterTimer.Start()
            }
        })
    }

    # ------------------------------
    if ($copyDetailsButton -and $interfacesGrid) {
        $copyDetailsButton.Add_Click({
            # Use global interfaces grid to read selected items
            $grid = $global:interfacesGrid
            # Gather selected or checked rows using helper
            $selectedRows = Get-SelectedInterfaceRows -Grid $grid
            if ($selectedRows.Count -eq 0) {
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
    if ($templateDropdown) {
        $templateDropdown.Add_SelectionChanged({
            $sel = $global:templateDropdown.SelectedItem
            $brush = [System.Windows.Media.Brushes]::Black
            if ($sel) {
                # Perform case-insensitive substring checks without converting
                $text = '' + $sel
                if     ($text -match '(?i)cisco')   { $brush = [System.Windows.Media.Brushes]::DodgerBlue }
                elseif ($text -match '(?i)brocade') { $brush = [System.Windows.Media.Brushes]::Goldenrod }
                elseif ($text -match '(?i)arista')  { $brush = [System.Windows.Media.Brushes]::MediumSeaGreen }
            }
            $global:templateDropdown.Foreground = $brush
        })
    }

    $global:interfacesView = $interfacesView
}

Export-ModuleMember -Function Get-InterfaceInfo,Compare-InterfaceConfigs,Get-InterfaceConfiguration,Get-ConfigurationTemplates,Get-SpanningTreeInfo,New-InterfacesView