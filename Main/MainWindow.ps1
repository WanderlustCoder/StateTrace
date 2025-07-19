Add-Type -AssemblyName PresentationFramework

# 1) Paths
$scriptDir           = Split-Path -Parent $MyInvocation.MyCommand.Path
$parserScript        = Join-Path $scriptDir '..\NetworkReader.ps1'
$interfaceModulePath = Join-Path $scriptDir '..\Modules\InterfaceModule.psm1'
$interfacesViewXaml  = Join-Path $scriptDir '..\Views\InterfacesView.xaml'


# 2) Import Interfaces module
if (-not (Test-Path $interfaceModulePath)) {
    Write-Error "Cannot find InterfaceModule at $interfaceModulePath"
    exit 1
}
Import-Module $interfaceModulePath -Force

# 3) Load MainWindow.xaml
$xamlPath = Join-Path $scriptDir 'MainWindow.xaml'
if (-not (Test-Path $xamlPath)) {
    Write-Error "Cannot find MainWindow.xaml at $xamlPath"
    exit 1
}
$xamlContent = Get-Content $xamlPath -Raw
$reader      = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($xamlContent))
$window      = [Windows.Markup.XamlReader]::Load($reader)

Set-Variable -Name window -Value $window -Scope Global

# 4) Helpers

function Load-DeviceSummaries {
    $names = Get-DeviceSummaries
    $dd    = $window.FindName('HostnameDropdown')
    $dd.ItemsSource = $names
    if ($names.Count -gt 0) { $dd.SelectedIndex = 0 }
}

function Load-DeviceDetails {
    param($hostname)
    try {
        $base     = Join-Path (Join-Path $scriptDir '..\ParsedData') $hostname
        $summary  = @(Import-Csv "${base}_Summary.csv")[0]

        $window.FindName('HostnameBox').Text        = $summary.Hostname
        $window.FindName('MakeBox').Text            = $summary.Make
        $window.FindName('ModelBox').Text           = $summary.Model
        $window.FindName('UptimeBox').Text          = $summary.Uptime
        $window.FindName('PortCountBox').Text       = $summary.InterfaceCount
        $window.FindName('AuthDefaultVLANBox').Text = $summary.AuthDefaultVLAN

        $grid = $interfacesView.FindName('InterfacesGrid')
        $grid.ItemsSource = Get-InterfaceInfo -Hostname $hostname

        $combo = $interfacesView.FindName('ConfigOptionsDropdown')
        $combo.ItemsSource = Get-ConfigurationTemplates -Hostname $hostname
        if ($combo.Items.Count -gt 0) { $combo.SelectedIndex = 0 }

    } catch {
        [System.Windows.MessageBox]::Show("Error loading ${hostname}:`n$($_.Exception.Message)")
    }
}

# 5) Inject InterfacesView
if (Test-Path $interfacesViewXaml) {
    $ifaceXaml     = Get-Content $interfacesViewXaml -Raw
    $ifaceReader   = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($ifaceXaml))
    $interfacesView= [Windows.Markup.XamlReader]::Load($ifaceReader)

    $interfacesHost = $window.FindName('InterfacesHost')
    if ($interfacesHost -is [System.Windows.Controls.ContentControl]) {
        $interfacesHost.Content = $interfacesView
    } else {
        Write-Warning "Could not find ContentControl 'InterfacesHost'"
    }

    $compareButton      = $interfacesView.FindName('CompareButton')
    $interfacesGrid     = $interfacesView.FindName('InterfacesGrid')
    $configureButton    = $interfacesView.FindName('ConfigureButton')
    $templateDropdown   = $interfacesView.FindName('ConfigOptionsDropdown')
    $filterBox          = $interfacesView.FindName('FilterBox')
    $clearBtn           = $interfacesView.FindName('ClearFilterButton')
    $copyDetailsButton  = $interfacesView.FindName('CopyDetailsButton')

    # 5b) Compare button
    if ($compareButton -and $interfacesGrid) {
        $compareButton.Add_Click({
            $selected = $interfacesGrid.ItemsSource | Where-Object { $_.IsSelected }
            if ($selected.Count -ne 2) {
                [System.Windows.MessageBox]::Show("Select exactly two interfaces to compare.")
                return
            }

            $int1 = $selected[0]
            $int2 = $selected[1]

            try {
                Compare-InterfaceConfigs `
                    -Switch1 $int1.Hostname -Interface1 $int1.Port `
                    -Switch2 $int2.Hostname -Interface2 $int2.Port
            } catch {
                [System.Windows.MessageBox]::Show("Compare failed:`n$($_.Exception.Message)")
            }
        })
    }

    # 5c) Configure button
    if ($configureButton -and $interfacesGrid -and $templateDropdown) {
        $configureButton.Add_Click({
            $selected = $interfacesGrid.ItemsSource | Where-Object { $_.IsSelected }
            if (-not $selected) {
                [System.Windows.MessageBox]::Show("No interfaces selected.")
                return
            }

            $template = $templateDropdown.SelectedItem
            if (-not $template) {
                [System.Windows.MessageBox]::Show("No template selected.")
                return
            }

            $hostname = $window.FindName('HostnameBox').Text

            try {
                $ports = $selected | ForEach-Object { $_.Port }
                $lines = Get-InterfaceConfiguration -Hostname $hostname -Interfaces $ports -TemplateName $template
                Set-Clipboard -Value ($lines -join "`r`n")
                [System.Windows.MessageBox]::Show(($lines -join "`n"), "Generated Config")
            } catch {
                [System.Windows.MessageBox]::Show("Failed to build config:`n$($_.Exception.Message)")
            }
        })
    }

    # 5d) Filter logic
    if ($clearBtn -and $filterBox -and $interfacesGrid) {
        $clearBtn.Add_Click({
            $filterBox.Text = ""
            $filterBox.Focus()
        })
    }

    if ($filterBox -and $interfacesGrid) {
        $filterBox.Add_TextChanged({
            $text = $filterBox.Text.ToLower()
            $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($interfacesGrid.ItemsSource)
            if ($null -eq $view) { return }

            $view.Filter = {
                param ($item)
                return (
                    ($item.Port       -as [string]).ToLower().Contains($text) -or
                    ($item.Name       -as [string]).ToLower().Contains($text) -or
                    ($item.Status     -as [string]).ToLower().Contains($text) -or
                    ($item.VLAN       -as [string]).ToLower().Contains($text) -or
                    ($item.AuthState  -as [string]).ToLower().Contains($text)
                )
            }
            $view.Refresh()
        })
    }

    # 5e) Copy Details button
    if ($copyDetailsButton -and $interfacesGrid) {
        $copyDetailsButton.Add_Click({
            $selected = $interfacesGrid.ItemsSource | Where-Object { $_.IsSelected }
            if (-not $selected -or $selected.Count -eq 0) {
                [System.Windows.MessageBox]::Show("No interfaces selected.")
                return
            }

            $hostname = $window.FindName('HostnameBox').Text
            $summaryPath = Join-Path (Join-Path $scriptDir '..\ParsedData') "${hostname}_Summary.csv"

            $authBlock = ""
            if (Test-Path $summaryPath) {
                $summary = @(Import-Csv $summaryPath)[0]
                if ($summary.AuthBlock -and $summary.AuthBlock.Trim() -ne "") {
                    $authBlock = $summary.AuthBlock.Trim()
                }
            }

            $header = @("Hostname: $hostname","------------------------------")
            if ($authBlock -ne "") {
                $header += @("Auth Block:", $authBlock, "","------------------------------")
            } else {
                $header += ""
            }

            $output = foreach ($int in $selected) {
                $lines = @(
                    "Port:        $($int.Port)"
                    "Name:        $($int.Name)"
                    "Status:      $($int.Status)"
                    "VLAN:        $($int.VLAN)"
                    "Duplex:      $($int.Duplex)"
                    "Speed:       $($int.Speed)"
                    "Type:        $($int.Type)"
                    "LearnedMACs: $($int.LearnedMACs)"
                    "AuthState:   $($int.AuthState)"
                    "AuthMode:    $($int.AuthMode)"
                    "Client MAC:  $($int.AuthClientMAC)"
                    "Config:"
                    "$($int.ToolTip)"
                    "------------------------------"
                )
                $lines -join "`r`n"
            }

            $final = $header + $output
            Set-Clipboard -Value ($final -join "`r`n")

            [System.Windows.MessageBox]::Show("Copied $($selected.Count) interface(s) with auth block to clipboard.")
        })
    }
    
} else {
    Write-Warning "Missing InterfacesView.xaml at $interfacesViewXaml"
}

# 6) Hook up main window controls
$refreshBtn = $window.FindName('RefreshButton')
if ($refreshBtn) {
    $refreshBtn.Add_Click({
        & "$parserScript"
        Load-DeviceSummaries
    })
}

$hostnameDropdown = $window.FindName('HostnameDropdown')
if ($hostnameDropdown) {
    $hostnameDropdown.Add_SelectionChanged({
        $sel = $hostnameDropdown.SelectedItem
        if ($sel) { Load-DeviceDetails $sel }
    })
}

# 7) Load initial state
try {
    & "$parserScript"
    Load-DeviceSummaries
} catch {
    [System.Windows.MessageBox]::Show("Log parsing failed:`n$($_.Exception.Message)", "Error")
}


if ($window.FindName('HostnameDropdown').Items.Count -gt 0) {
    Load-DeviceDetails $window.FindName('HostnameDropdown').Items[0]
}

# 8) Show window
$window.ShowDialog() | Out-Null

# 9) Cleanup
$parsedDir = Join-Path $scriptDir '..\ParsedData'
if (Test-Path $parsedDir) {
    try { Get-ChildItem $parsedDir -Recurse | Remove-Item -Force -Recurse }
    catch { Write-Warning "Failed to clear ParsedData: $_" }
}