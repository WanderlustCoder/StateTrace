Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Creates and initializes the Network Calculator view.

.DESCRIPTION
    Loads NetworkCalculatorView.xaml using ViewCompositionModule, wires up event handlers,
    and provides subnet, VLAN, bandwidth, IP tools, and port reference functionality.

.PARAMETER Window
    The parent MainWindow instance.

.PARAMETER ScriptDir
    The root script directory for locating XAML files.

.OUTPUTS
    System.Windows.Controls.UserControl - The initialized view.
#>
function New-NetworkCalculatorView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory=$true)]
        [string]$ScriptDir
    )

    try {
        $view = ViewCompositionModule\Set-StView -Window $Window -ScriptDir $ScriptDir `
            -ViewName 'NetworkCalculatorView' -HostControlName 'NetworkCalculatorHost' `
            -GlobalVariableName 'networkCalculatorView'
        if (-not $view) { return }

        # Get Subnet Calculator controls
        $subnetNetworkBox = $view.FindName('SubnetNetworkBox')
        $subnetCIDRDropdown = $view.FindName('SubnetCIDRDropdown')
        $subnetCalculateButton = $view.FindName('SubnetCalculateButton')
        $subnetNetworkResult = $view.FindName('SubnetNetworkResult')
        $subnetBroadcastResult = $view.FindName('SubnetBroadcastResult')
        $subnetMaskResult = $view.FindName('SubnetMaskResult')
        $subnetWildcardResult = $view.FindName('SubnetWildcardResult')
        $subnetFirstResult = $view.FindName('SubnetFirstResult')
        $subnetLastResult = $view.FindName('SubnetLastResult')
        $subnetHostsResult = $view.FindName('SubnetHostsResult')
        $subnetSplitDropdown = $view.FindName('SubnetSplitDropdown')
        $subnetSplitButton = $view.FindName('SubnetSplitButton')
        $subnetSplitGrid = $view.FindName('SubnetSplitGrid')
        $subnetCopyButton = $view.FindName('SubnetCopyButton')

        # Get VLAN Calculator controls
        $vlanExpandInput = $view.FindName('VLANExpandInput')
        $vlanExpandButton = $view.FindName('VLANExpandButton')
        $vlanExpandResult = $view.FindName('VLANExpandResult')
        $vlanCompressInput = $view.FindName('VLANCompressInput')
        $vlanCompressButton = $view.FindName('VLANCompressButton')
        $vlanCompressResult = $view.FindName('VLANCompressResult')

        # Get Bandwidth Calculator controls
        $bandwidthSizeBox = $view.FindName('BandwidthSizeBox')
        $bandwidthSizeUnit = $view.FindName('BandwidthSizeUnit')
        $bandwidthSpeedBox = $view.FindName('BandwidthSpeedBox')
        $bandwidthSpeedUnit = $view.FindName('BandwidthSpeedUnit')
        $bandwidthCalcButton = $view.FindName('BandwidthCalcButton')
        $bandwidthResult = $view.FindName('BandwidthResult')
        $convertValueBox = $view.FindName('ConvertValueBox')
        $convertFromUnit = $view.FindName('ConvertFromUnit')
        $convertToUnit = $view.FindName('ConvertToUnit')
        $convertButton = $view.FindName('ConvertButton')
        $convertResult = $view.FindName('ConvertResult')

        # Get IP Tools controls
        $ipValidateBox = $view.FindName('IPValidateBox')
        $ipValidateButton = $view.FindName('IPValidateButton')
        $ipValidateResult = $view.FindName('IPValidateResult')
        $ipCheckBox = $view.FindName('IPCheckBox')
        $subnetCheckBox = $view.FindName('SubnetCheckBox')
        $ipCheckButton = $view.FindName('IPCheckButton')
        $ipCheckResult = $view.FindName('IPCheckResult')

        # Get Ports Reference controls
        $portSearchBox = $view.FindName('PortSearchBox')
        $portSearchButton = $view.FindName('PortSearchButton')
        $portShowAllButton = $view.FindName('PortShowAllButton')
        $portsGrid = $view.FindName('PortsGrid')

        # Store current subnet calculation in view's Tag
        $view.Tag = @{
            CurrentSubnetInfo = $null
        }

        # Populate CIDR dropdown (8-30)
        for ($i = 8; $i -le 30; $i++) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = $i
            $subnetCIDRDropdown.Items.Add($item) | Out-Null
        }
        $subnetCIDRDropdown.SelectedIndex = 16  # Default to /24

        # Populate split dropdown (one prefix higher than current)
        for ($i = 9; $i -le 30; $i++) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = "/$i"
            $subnetSplitDropdown.Items.Add($item) | Out-Null
        }
        $subnetSplitDropdown.SelectedIndex = 0

        # Subnet Calculate button click
        $subnetCalculateButton.Add_Click({
            param($sender, $e)
            $network = $subnetNetworkBox.Text
            $cidr = if ($subnetCIDRDropdown.SelectedItem) { [int]$subnetCIDRDropdown.SelectedItem.Content } else { 24 }

            if ([string]::IsNullOrWhiteSpace($network)) {
                return
            }

            try {
                $info = NetworkCalculatorModule\Get-SubnetInfo -Network $network -CIDR $cidr
                $view.Tag.CurrentSubnetInfo = $info

                $subnetNetworkResult.Text = $info.NetworkAddress
                $subnetBroadcastResult.Text = $info.BroadcastAddress
                $subnetMaskResult.Text = $info.SubnetMask
                $subnetWildcardResult.Text = $info.WildcardMask
                $subnetFirstResult.Text = $info.FirstUsable
                $subnetLastResult.Text = $info.LastUsable
                $subnetHostsResult.Text = $info.TotalHosts.ToString()

                # Update split dropdown to only show valid options
                $subnetSplitDropdown.Items.Clear()
                for ($i = $cidr + 1; $i -le 30; $i++) {
                    $item = New-Object System.Windows.Controls.ComboBoxItem
                    $item.Content = "/$i"
                    $subnetSplitDropdown.Items.Add($item) | Out-Null
                }
                if ($subnetSplitDropdown.Items.Count -gt 0) {
                    $subnetSplitDropdown.SelectedIndex = 0
                }

                $subnetSplitGrid.ItemsSource = $null
            } catch {
                $subnetNetworkResult.Text = "Error"
                $subnetBroadcastResult.Text = ""
                $subnetMaskResult.Text = ""
                $subnetWildcardResult.Text = ""
                $subnetFirstResult.Text = ""
                $subnetLastResult.Text = ""
                $subnetHostsResult.Text = $_.Exception.Message
            }
        }.GetNewClosure())

        # Subnet calculate on Enter key
        $subnetNetworkBox.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Return') {
                $subnetCalculateButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        }.GetNewClosure())

        # Subnet Split button click
        $subnetSplitButton.Add_Click({
            param($sender, $e)
            $info = $view.Tag.CurrentSubnetInfo
            if ($null -eq $info) {
                return
            }

            $targetPrefix = if ($subnetSplitDropdown.SelectedItem) {
                [int]($subnetSplitDropdown.SelectedItem.Content -replace '^/', '')
            } else {
                return
            }

            try {
                $subnets = NetworkCalculatorModule\Split-Subnet -NetworkAddress $info.NetworkAddress -CurrentPrefix $info.CIDR -TargetPrefix $targetPrefix
                $subnetSplitGrid.ItemsSource = $subnets
            } catch {
                $subnetSplitGrid.ItemsSource = $null
            }
        }.GetNewClosure())

        # Subnet Copy button click
        $subnetCopyButton.Add_Click({
            param($sender, $e)
            $info = $view.Tag.CurrentSubnetInfo
            if ($null -eq $info) {
                return
            }

            $text = @"
Network: $($info.NetworkAddress)/$($info.CIDR)
Subnet Mask: $($info.SubnetMask)
Wildcard: $($info.WildcardMask)
Broadcast: $($info.BroadcastAddress)
First Usable: $($info.FirstUsable)
Last Usable: $($info.LastUsable)
Total Hosts: $($info.TotalHosts)
"@
            [System.Windows.Clipboard]::SetText($text)
        }.GetNewClosure())

        # VLAN Expand button click
        $vlanExpandButton.Add_Click({
            param($sender, $e)
            $range = $vlanExpandInput.Text
            if ([string]::IsNullOrWhiteSpace($range)) {
                $vlanExpandResult.Text = ''
                return
            }

            try {
                $vlans = NetworkCalculatorModule\Expand-VLANRange -Range $range
                $vlanExpandResult.Text = ($vlans -join ', ')
            } catch {
                $vlanExpandResult.Text = "Error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # VLAN Expand on Enter key
        $vlanExpandInput.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Return') {
                $vlanExpandButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        }.GetNewClosure())

        # VLAN Compress button click
        $vlanCompressButton.Add_Click({
            param($sender, $e)
            $input = $vlanCompressInput.Text
            if ([string]::IsNullOrWhiteSpace($input)) {
                $vlanCompressResult.Text = ''
                return
            }

            try {
                $vlans = @($input -split '\s*,\s*' | ForEach-Object { [int]$_ })
                $result = NetworkCalculatorModule\Compress-VLANList -VLANs $vlans
                $vlanCompressResult.Text = $result
            } catch {
                $vlanCompressResult.Text = "Error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # VLAN Compress on Enter key
        $vlanCompressInput.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Return') {
                $vlanCompressButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        }.GetNewClosure())

        # Bandwidth Calculate button click
        $bandwidthCalcButton.Add_Click({
            param($sender, $e)
            $sizeText = $bandwidthSizeBox.Text
            $sizeUnit = if ($bandwidthSizeUnit.SelectedItem) { $bandwidthSizeUnit.SelectedItem.Content } else { 'MB' }
            $speedText = $bandwidthSpeedBox.Text
            $speedUnit = if ($bandwidthSpeedUnit.SelectedItem) { $bandwidthSpeedUnit.SelectedItem.Content } else { 'Mbps' }

            if ([string]::IsNullOrWhiteSpace($sizeText) -or [string]::IsNullOrWhiteSpace($speedText)) {
                $bandwidthResult.Text = ''
                return
            }

            try {
                $size = [double]$sizeText
                $speed = [double]$speedText

                # Convert size to bytes
                $sizeBytes = switch ($sizeUnit) {
                    'MB' { $size * 1024 * 1024 }
                    'GB' { $size * 1024 * 1024 * 1024 }
                    'TB' { $size * 1024 * 1024 * 1024 * 1024 }
                    default { $size * 1024 * 1024 }
                }

                # Convert speed to bps
                $speedBps = switch ($speedUnit) {
                    'Mbps' { $speed * 1000000 }
                    'Gbps' { $speed * 1000000000 }
                    default { $speed * 1000000 }
                }

                $result = NetworkCalculatorModule\Get-TransferTime -SizeBytes $sizeBytes -BandwidthBps $speedBps
                $bandwidthResult.Text = $result.FormattedTime
            } catch {
                $bandwidthResult.Text = "Error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Bandwidth calculate on Enter key
        $bandwidthSizeBox.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Return') {
                $bandwidthCalcButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        }.GetNewClosure())

        $bandwidthSpeedBox.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Return') {
                $bandwidthCalcButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        }.GetNewClosure())

        # Unit Convert button click
        $convertButton.Add_Click({
            param($sender, $e)
            $valueText = $convertValueBox.Text
            $fromUnit = if ($convertFromUnit.SelectedItem) { $convertFromUnit.SelectedItem.Content } else { 'Mbps' }
            $toUnit = if ($convertToUnit.SelectedItem) { $convertToUnit.SelectedItem.Content } else { 'Gbps' }

            if ([string]::IsNullOrWhiteSpace($valueText)) {
                $convertResult.Text = ''
                return
            }

            try {
                $value = [double]$valueText
                $result = NetworkCalculatorModule\Convert-BandwidthUnit -Value $value -FromUnit $fromUnit -ToUnit $toUnit
                $convertResult.Text = [math]::Round($result, 4).ToString()
            } catch {
                $convertResult.Text = "Error"
            }
        }.GetNewClosure())

        # Convert on Enter key
        $convertValueBox.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Return') {
                $convertButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        }.GetNewClosure())

        # IP Validate button click
        $ipValidateButton.Add_Click({
            param($sender, $e)
            $ip = $ipValidateBox.Text
            if ([string]::IsNullOrWhiteSpace($ip)) {
                $ipValidateResult.Text = ''
                return
            }

            try {
                $info = NetworkCalculatorModule\Get-IPAddressInfo -IPAddress $ip
                $lines = @()
                $lines += "Valid: $($info.IsValid)"
                if ($info.IsValid) {
                    $lines += "Type: $($info.AddressType)"
                    $lines += "Class: $($info.Class)"
                    $lines += "Binary: $($info.Binary)"
                }
                $ipValidateResult.Text = $lines -join "`r`n"
            } catch {
                $ipValidateResult.Text = "Error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # IP validate on Enter key
        $ipValidateBox.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Return') {
                $ipValidateButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        }.GetNewClosure())

        # IP Check button click
        $ipCheckButton.Add_Click({
            param($sender, $e)
            $ip = $ipCheckBox.Text
            $subnet = $subnetCheckBox.Text

            if ([string]::IsNullOrWhiteSpace($ip) -or [string]::IsNullOrWhiteSpace($subnet)) {
                $ipCheckResult.Text = ''
                return
            }

            try {
                $result = NetworkCalculatorModule\Test-IPInSubnet -IPAddress $ip -Subnet $subnet
                $ipCheckResult.Text = if ($result) { "Yes" } else { "No" }
            } catch {
                $ipCheckResult.Text = "Error"
            }
        }.GetNewClosure())

        # IP check on Enter key
        $ipCheckBox.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Return') {
                $ipCheckButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        }.GetNewClosure())

        $subnetCheckBox.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Return') {
                $ipCheckButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        }.GetNewClosure())

        # Port Search button click
        $portSearchButton.Add_Click({
            param($sender, $e)
            $query = $portSearchBox.Text
            if ([string]::IsNullOrWhiteSpace($query)) {
                $portsGrid.ItemsSource = $null
                return
            }

            try {
                $results = NetworkCalculatorModule\Get-WellKnownPorts | Where-Object {
                    $_.Port -eq $query -or $_.Service -like "*$query*"
                }
                $portsGrid.ItemsSource = @($results)
            } catch {
                $portsGrid.ItemsSource = $null
            }
        }.GetNewClosure())

        # Port search on Enter key
        $portSearchBox.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Return') {
                $portSearchButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        }.GetNewClosure())

        # Port Show All button click
        $portShowAllButton.Add_Click({
            param($sender, $e)
            try {
                $ports = NetworkCalculatorModule\Get-WellKnownPorts
                $portsGrid.ItemsSource = @($ports)
            } catch {
                $portsGrid.ItemsSource = $null
            }
        }.GetNewClosure())

        # Load initial ports list
        try {
            $ports = NetworkCalculatorModule\Get-WellKnownPorts
            $portsGrid.ItemsSource = @($ports)
        } catch {
            # Ignore errors on initial load
        }

        return $view

    } catch {
        Write-Warning "Failed to initialize NetworkCalculator view: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function New-NetworkCalculatorView
