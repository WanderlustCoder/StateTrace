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

# --- Helpers: place right after script-scoped variable block ---

function Get-PortsForHost {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Hostname)

    $ports = @()

    # Prefer the live Interfaces grid if present (fast path, no DB timing)
    if ($global:interfacesGrid -and $global:interfacesGrid.ItemsSource) {
        try {
            $ports = @(
                $global:interfacesGrid.ItemsSource |
                Where-Object {
                    ($_.'Hostname' -as [string]) -eq $Hostname
                } |
                Sort-Object Port |
                ForEach-Object { $_.Port }
            )
        } catch { $ports = @() }
    }

    # Fallback to Get-InterfaceInfo if we didn't get anything from the grid
    if (-not $ports -or $ports.Count -eq 0) {
        if (Get-Command Get-InterfaceInfo -ErrorAction SilentlyContinue) {
            try {
                $ports = @(
                    Get-InterfaceInfo -Hostname $Hostname |
                    Sort-Object Port |
                    Select-Object -ExpandProperty Port
                )
            } catch { $ports = @() }
        }
    }

    return $ports
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

function Set-CompareFromRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Row1,
        [Parameter(Mandatory)][psobject]$Row2
    )

    # Pull tooltip/config and colours
    $tooltip1 = '' + ($Row1.ToolTip)
    $tooltip2 = '' + ($Row2.ToolTip)
    $color1   = if ($Row1.PSObject.Properties['PortColor'] -and $Row1.PortColor) { '' + $Row1.PortColor } else { 'Black' }
    $color2   = if ($Row2.PSObject.Properties['PortColor'] -and $Row2.PortColor) { '' + $Row2.PortColor } else { 'Black' }

    # AuthTemplate labels
    $auth1 = Get-AuthTemplateFromTooltip -Text $tooltip1
    $auth2 = Get-AuthTemplateFromTooltip -Text $tooltip2
    if ($script:auth1Text) { $script:auth1Text.Text = ('AuthTemplate: ' + $auth1) }
    if ($script:auth2Text) { $script:auth2Text.Text = ('AuthTemplate: ' + $auth2) }

    # Config text + colour
    if ($script:config1Box) {
        $script:config1Box.Text = $tooltip1
        try { $script:config1Box.Foreground = [System.Windows.Media.Brushes]::$color1 } catch { $script:config1Box.Foreground = [System.Windows.Media.Brushes]::Black }
    }
    if ($script:config2Box) {
        $script:config2Box.Text = $tooltip2
        try { $script:config2Box.Foreground = [System.Windows.Media.Brushes]::$color2 } catch { $script:config2Box.Foreground = [System.Windows.Media.Brushes]::Black }
    }

    # Diffs
    $lines1 = @(); if ($tooltip1) { $lines1 = ($tooltip1 -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } }
    $lines2 = @(); if ($tooltip2) { $lines2 = ($tooltip2 -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } }
    $diff1 = @(); $diff2 = @()
    $comp = $null
    try { $comp = Compare-Object -ReferenceObject $lines1 -DifferenceObject $lines2 } catch { $comp = $null }
    if ($comp) {
        $diff1 = @($comp | Where-Object { $_.SideIndicator -eq '<=' } | Select-Object -ExpandProperty InputObject)
        $diff2 = @($comp | Where-Object { $_.SideIndicator -eq '=>' } | Select-Object -ExpandProperty InputObject)
    }
    if ($script:diff1Box) { $script:diff1Box.Text = ($diff1 -join "`r`n") }
    if ($script:diff2Box) { $script:diff2Box.Text = ($diff2 -join "`r`n") }
}
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

    # Use the main window's existing host list
    $mainHosts = @()
    $hostDD = $Window.FindName('HostnameDropdown')
    if ($hostDD -and $hostDD.ItemsSource) {
        $mainHosts = @($hostDD.ItemsSource)
    } else {
        # Fallback if needed
        if (Get-Command Get-DeviceSummaries -ErrorAction SilentlyContinue) {
            try { $mainHosts = @(Get-DeviceSummaries) } catch { $mainHosts = @() }
        }
    }
    if ($script:switch1Dropdown) { $script:switch1Dropdown.ItemsSource = $mainHosts }
    if ($script:switch2Dropdown) { $script:switch2Dropdown.ItemsSource = $mainHosts }

    # Wire selection handlers (unchanged)
    if ($script:switch1Dropdown) {
        $script:switch1Dropdown.Add_SelectionChanged({
            $selHost = $script:switch1Dropdown.SelectedItem
            if ($script:port1Dropdown) {
                try {
                    if ($selHost) {
                        $script:port1Dropdown.ItemsSource = @(Get-PortsForHost -Hostname $selHost)
                    } else {
                        $script:port1Dropdown.ItemsSource = @()
                    }
                } catch {
                    $script:port1Dropdown.ItemsSource = @()
                }
            }
            if ($script:port1Dropdown) { $script:port1Dropdown.SelectedItem = $null }
        })
    }

    if ($script:switch2Dropdown) {
        $script:switch2Dropdown.Add_SelectionChanged({
            $selHost = $script:switch2Dropdown.SelectedItem
            if ($script:port2Dropdown) {
                try {
                    if ($selHost) {
                        $script:port2Dropdown.ItemsSource = @(Get-PortsForHost -Hostname $selHost)
                    } else {
                        $script:port2Dropdown.ItemsSource = @()
                    }
                } catch {
                    $script:port2Dropdown.ItemsSource = @()
                }
            }
            if ($script:port2Dropdown) { $script:port2Dropdown.SelectedItem = $null }
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
        # Config text & colour from the selected rows
        $tooltip1 = '' + ($Row1.ToolTip)
        $tooltip2 = '' + ($Row2.ToolTip)
        $color1   = if ($Row1.PortColor) { '' + $Row1.PortColor } else { 'Black' }
        $color2   = if ($Row2.PortColor) { '' + $Row2.PortColor } else { 'Black' }

        if ($script:config1Box) {
            $script:config1Box.Text = $tooltip1
            try { $script:config1Box.Foreground = [System.Windows.Media.Brushes]::$color1 } catch { $script:config1Box.Foreground = [System.Windows.Media.Brushes]::Black }
        }
        if ($script:config2Box) {
            $script:config2Box.Text = $tooltip2
            try { $script:config2Box.Foreground = [System.Windows.Media.Brushes]::$color2 } catch { $script:config2Box.Foreground = [System.Windows.Media.Brushes]::Black }
        }

        # Split lines and compute differences (case-sensitive here to be precise)
        $lines1 = @(); if ($tooltip1) { $lines1 = ($tooltip1 -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } }
        $lines2 = @(); if ($tooltip2) { $lines2 = ($tooltip2 -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } }
        $comp = Compare-Object -ReferenceObject $lines1 -DifferenceObject $lines2
        $diff1Lines = @(); $diff2Lines = @()
        if ($comp) {
            $diff1Lines = @($comp | Where-Object { $_.SideIndicator -eq '<=' } | Select-Object -ExpandProperty InputObject)
            $diff2Lines = @($comp | Where-Object { $_.SideIndicator -eq '=>' } | Select-Object -ExpandProperty InputObject)
        }

        if ($script:diff1Box) { $script:diff1Box.Text = ($diff1Lines -join "`r`n") }
        if ($script:diff2Box) { $script:diff2Box.Text = ($diff2Lines -join "`r`n") }
    } catch {
        if ($script:config1Box) { $script:config1Box.Text = '' }
        if ($script:config2Box) { $script:config2Box.Text = '' }
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
        $s1 = if ($script:switch1Dropdown) { $script:switch1Dropdown.SelectedItem } else { $null }
        $p1 = if ($script:port1Dropdown)   { $script:port1Dropdown.SelectedItem   } else { $null }
        $s2 = if ($script:switch2Dropdown) { $script:switch2Dropdown.SelectedItem } else { $null }
        $p2 = if ($script:port2Dropdown)   { $script:port2Dropdown.SelectedItem   } else { $null }

        if (-not $s1 -or -not $p1 -or -not $s2 -or -not $p2) {
            if ($script:auth1Text) { $script:auth1Text.Text = '' }
            if ($script:auth2Text) { $script:auth2Text.Text = '' }
            if ($script:config1Box) { $script:config1Box.Text = '' }
            if ($script:config2Box) { $script:config2Box.Text = '' }
            if ($script:diff1Box)   { $script:diff1Box.Text   = '' }
            if ($script:diff2Box)   { $script:diff2Box.Text   = '' }
            return
        }

        $row1 = Get-GridRowFor -Hostname $s1 -Port $p1
        $row2 = Get-GridRowFor -Hostname $s2 -Port $p2

        # Fallback to DB if the grid doesn't have the rows (rare)
        if (-not $row1 -and (Get-Command Get-InterfaceInfo -ErrorAction SilentlyContinue)) {
            try { $row1 = @(Get-InterfaceInfo -Hostname $s1 | Where-Object { $_.Port -eq $p1 } | Select-Object -First 1) } catch { $row1 = $null }
        }
        if (-not $row2 -and (Get-Command Get-InterfaceInfo -ErrorAction SilentlyContinue)) {
            try { $row2 = @(Get-InterfaceInfo -Hostname $s2 | Where-Object { $_.Port -eq $p2 } | Select-Object -First 1) } catch { $row2 = $null }
        }

        if ($row1 -and $row2) {
            Set-CompareFromRows -Row1 $row1 -Row2 $row2
        } else {
            if ($script:auth1Text) { $script:auth1Text.Text = '' }
            if ($script:auth2Text) { $script:auth2Text.Text = '' }
            if ($script:config1Box) { $script:config1Box.Text = '' }
            if ($script:config2Box) { $script:config2Box.Text = '' }
            if ($script:diff1Box)   { $script:diff1Box.Text   = '' }
            if ($script:diff2Box)   { $script:diff2Box.Text   = '' }
        }
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
        # Use main window host dropdown's ItemsSource if available
        $hosts = @()
        if ($script:windowRef) {
            $hostDD = $script:windowRef.FindName('HostnameDropdown')
            if ($hostDD -and $hostDD.ItemsSource) { $hosts = @($hostDD.ItemsSource) }
        }
        if (-not $hosts -or $hosts.Count -eq 0) {
            if (Get-Command Get-DeviceSummaries -ErrorAction SilentlyContinue) {
                try { $hosts = @(Get-DeviceSummaries) } catch { $hosts = @() }
            }
        }
        if ($script:switch1Dropdown -and ((-not $script:switch1Dropdown.ItemsSource) -or (@($script:switch1Dropdown.ItemsSource).Count -eq 0))) {
            $script:switch1Dropdown.ItemsSource = $hosts
        }
        if ($script:switch2Dropdown -and ((-not $script:switch2Dropdown.ItemsSource) -or (@($script:switch2Dropdown.ItemsSource).Count -eq 0))) {
            $script:switch2Dropdown.ItemsSource = $hosts
        }

        # Select devices
        if ($script:switch1Dropdown) { $script:switch1Dropdown.SelectedItem = $Switch1 }
        if ($script:switch2Dropdown) { $script:switch2Dropdown.SelectedItem = $Switch2 }

        # Populate ports from the grid (fallback to DB)
        if ($script:port1Dropdown) {
            try {
                $script:port1Dropdown.ItemsSource = @(Get-PortsForHost -Hostname $Switch1)
            } catch { $script:port1Dropdown.ItemsSource = @() }
            $script:port1Dropdown.SelectedItem = $Interface1
        }
        if ($script:port2Dropdown) {
            try {
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