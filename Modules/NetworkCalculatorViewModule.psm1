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

        #region ACL Builder Controls
        $aclNameBox = $view.FindName('ACLNameBox')
        $aclTemplateDropdown = $view.FindName('ACLTemplateDropdown')
        $aclLoadTemplateButton = $view.FindName('ACLLoadTemplateButton')
        $aclVendorDropdown = $view.FindName('ACLVendorDropdown')
        $aclActionDropdown = $view.FindName('ACLActionDropdown')
        $aclProtocolDropdown = $view.FindName('ACLProtocolDropdown')
        $aclSourceBox = $view.FindName('ACLSourceBox')
        $aclSourcePortBox = $view.FindName('ACLSourcePortBox')
        $aclDestBox = $view.FindName('ACLDestBox')
        $aclDestPortBox = $view.FindName('ACLDestPortBox')
        $aclRemarkBox = $view.FindName('ACLRemarkBox')
        $aclAddEntryButton = $view.FindName('ACLAddEntryButton')
        $aclEntriesGrid = $view.FindName('ACLEntriesGrid')
        $aclMoveUpButton = $view.FindName('ACLMoveUpButton')
        $aclMoveDownButton = $view.FindName('ACLMoveDownButton')
        $aclDeleteEntryButton = $view.FindName('ACLDeleteEntryButton')
        $aclClearAllButton = $view.FindName('ACLClearAllButton')
        $aclGenerateButton = $view.FindName('ACLGenerateButton')
        $aclCopyButton = $view.FindName('ACLCopyButton')
        $aclStatusLabel = $view.FindName('ACLStatusLabel')
        $aclOutputBox = $view.FindName('ACLOutputBox')

        # Store ACL entries in view Tag
        $view.Tag.ACLEntries = [System.Collections.Generic.List[PSCustomObject]]::new()

        # Populate template dropdown
        try {
            $templates = NetworkCalculatorModule\Get-ACLTemplates
            foreach ($template in $templates) {
                $item = New-Object System.Windows.Controls.ComboBoxItem
                $item.Content = $template.Name
                $item.Tag = $template
                $aclTemplateDropdown.Items.Add($item) | Out-Null
            }
            if ($aclTemplateDropdown.Items.Count -gt 0) {
                $aclTemplateDropdown.SelectedIndex = 0
            }
        } catch {
            # Ignore errors on template load
        }

        # Helper function to refresh grid
        $refreshACLGrid = {
            $entries = $view.Tag.ACLEntries
            $seq = 10
            foreach ($entry in $entries) {
                $entry.Sequence = $seq
                $seq += 10
            }
            $aclEntriesGrid.ItemsSource = $null
            $aclEntriesGrid.ItemsSource = @($entries)
        }

        # Load Template button click
        $aclLoadTemplateButton.Add_Click({
            param($sender, $e)
            if ($null -eq $aclTemplateDropdown.SelectedItem) { return }

            $template = $aclTemplateDropdown.SelectedItem.Tag
            if ($null -eq $template) { return }

            $view.Tag.ACLEntries.Clear()
            $aclNameBox.Text = $template.Name -replace '\s+', '-'

            foreach ($entryDef in $template.Entries) {
                try {
                    $entry = NetworkCalculatorModule\New-ACLEntry `
                        -Action $entryDef.Action `
                        -Protocol $entryDef.Protocol `
                        -SourceNetwork $entryDef.Source `
                        -DestinationNetwork $entryDef.Destination `
                        -SourcePort $entryDef.SourcePort `
                        -DestinationPort $entryDef.DestinationPort `
                        -Remark $entryDef.Remark
                    $view.Tag.ACLEntries.Add($entry)
                } catch {
                    # Skip invalid entries
                }
            }

            & $refreshACLGrid
            $aclStatusLabel.Content = "Loaded template: $($template.Name)"
        }.GetNewClosure())

        # Add Entry button click
        $aclAddEntryButton.Add_Click({
            param($sender, $e)
            $action = if ($aclActionDropdown.SelectedItem) { $aclActionDropdown.SelectedItem.Content } else { 'deny' }
            $protocol = if ($aclProtocolDropdown.SelectedItem) { $aclProtocolDropdown.SelectedItem.Content } else { 'ip' }
            $source = if ([string]::IsNullOrWhiteSpace($aclSourceBox.Text)) { 'any' } else { $aclSourceBox.Text.Trim() }
            $srcPort = $aclSourcePortBox.Text.Trim()
            $dest = if ([string]::IsNullOrWhiteSpace($aclDestBox.Text)) { 'any' } else { $aclDestBox.Text.Trim() }
            $dstPort = $aclDestPortBox.Text.Trim()
            $remark = $aclRemarkBox.Text.Trim()

            try {
                $entry = NetworkCalculatorModule\New-ACLEntry `
                    -Action $action `
                    -Protocol $protocol `
                    -SourceNetwork $source `
                    -DestinationNetwork $dest `
                    -SourcePort $srcPort `
                    -DestinationPort $dstPort `
                    -Remark $remark

                $view.Tag.ACLEntries.Add($entry)
                & $refreshACLGrid

                # Clear input fields
                $aclSourceBox.Text = ''
                $aclSourcePortBox.Text = ''
                $aclDestBox.Text = ''
                $aclDestPortBox.Text = ''
                $aclRemarkBox.Text = ''
                $aclStatusLabel.Content = "Entry added"
            } catch {
                $aclStatusLabel.Content = "Error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Move Up button click
        $aclMoveUpButton.Add_Click({
            param($sender, $e)
            $selected = $aclEntriesGrid.SelectedItem
            if ($null -eq $selected) { return }

            $entries = $view.Tag.ACLEntries
            $index = $entries.IndexOf($selected)
            if ($index -le 0) { return }

            $entries.RemoveAt($index)
            $entries.Insert($index - 1, $selected)
            & $refreshACLGrid
            $aclEntriesGrid.SelectedItem = $selected
        }.GetNewClosure())

        # Move Down button click
        $aclMoveDownButton.Add_Click({
            param($sender, $e)
            $selected = $aclEntriesGrid.SelectedItem
            if ($null -eq $selected) { return }

            $entries = $view.Tag.ACLEntries
            $index = $entries.IndexOf($selected)
            if ($index -lt 0 -or $index -ge $entries.Count - 1) { return }

            $entries.RemoveAt($index)
            $entries.Insert($index + 1, $selected)
            & $refreshACLGrid
            $aclEntriesGrid.SelectedItem = $selected
        }.GetNewClosure())

        # Delete Entry button click
        $aclDeleteEntryButton.Add_Click({
            param($sender, $e)
            $selected = $aclEntriesGrid.SelectedItem
            if ($null -eq $selected) { return }

            $result = [System.Windows.MessageBox]::Show(
                "Delete this ACL entry?",
                'Confirm Delete',
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Question
            )
            if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                $view.Tag.ACLEntries.Remove($selected) | Out-Null
                & $refreshACLGrid
                $aclStatusLabel.Content = "Entry deleted"
            }
        }.GetNewClosure())

        # Clear All button click
        $aclClearAllButton.Add_Click({
            param($sender, $e)
            $count = $view.Tag.ACLEntries.Count
            if ($count -eq 0) { return }

            $result = [System.Windows.MessageBox]::Show(
                "Clear all $count ACL entries?",
                'Confirm Clear All',
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning
            )
            if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                $view.Tag.ACLEntries.Clear()
                & $refreshACLGrid
                $aclOutputBox.Text = ''
                $aclStatusLabel.Content = "All entries cleared"
            }
        }.GetNewClosure())

        # Generate Config button click
        $aclGenerateButton.Add_Click({
            param($sender, $e)
            $entries = $view.Tag.ACLEntries
            if ($entries.Count -eq 0) {
                $aclStatusLabel.Content = "No entries to generate"
                return
            }

            $aclName = if ([string]::IsNullOrWhiteSpace($aclNameBox.Text)) { 'ACL-UNNAMED' } else { $aclNameBox.Text.Trim() }
            $vendor = if ($aclVendorDropdown.SelectedItem) { $aclVendorDropdown.SelectedItem.Content } else { 'Cisco' }

            try {
                $config = NetworkCalculatorModule\Get-ACLConfig -ACLName $aclName -Entries @($entries) -Vendor $vendor
                $aclOutputBox.Text = $config
                $aclStatusLabel.Content = "Config generated ($($entries.Count) entries)"
            } catch {
                $aclStatusLabel.Content = "Error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Copy to Clipboard button click
        $aclCopyButton.Add_Click({
            param($sender, $e)
            $config = $aclOutputBox.Text
            if ([string]::IsNullOrWhiteSpace($config)) {
                $aclStatusLabel.Content = "No config to copy"
                return
            }

            [System.Windows.Clipboard]::SetText($config)
            $aclStatusLabel.Content = "Config copied to clipboard"
        }.GetNewClosure())

        #endregion ACL Builder Controls

        return $view

    } catch {
        Write-Warning "Failed to initialize NetworkCalculator view: $($_.Exception.Message)"
    }
}

function Initialize-NetworkCalculatorView {
    <#
    .SYNOPSIS
        Initializes the Network Calculator view for nested tab container use.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ContentControl]$Host
    )

    try {
        $viewPath = Join-Path $PSScriptRoot '..\Views\NetworkCalculatorView.xaml'
        if (-not (Test-Path $viewPath)) {
            Write-Warning "NetworkCalculatorView.xaml not found at: $viewPath"
            return
        }

        $xamlContent = Get-Content -Path $viewPath -Raw
        $xamlContent = $xamlContent -replace 'x:Class="[^"]*"', ''
        $xamlContent = $xamlContent -replace 'mc:Ignorable="d"', ''

        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlContent))
        $view = [System.Windows.Markup.XamlReader]::Load($reader)
        $Host.Content = $view

        # Initialize controls and event handlers
        Initialize-NetworkCalculatorControls -View $view

        return $view
    }
    catch {
        Write-Warning "Failed to initialize NetworkCalculator view: $($_.Exception.Message)"
    }
}

function Initialize-NetworkCalculatorControls {
    <#
    .SYNOPSIS
        Wires up controls and event handlers for the Network Calculator view.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    # Get Subnet Calculator controls
    $subnetNetworkBox = $View.FindName('SubnetNetworkBox')
    $subnetCIDRDropdown = $View.FindName('SubnetCIDRDropdown')
    $subnetCalculateButton = $View.FindName('SubnetCalculateButton')
    $subnetNetworkResult = $View.FindName('SubnetNetworkResult')
    $subnetBroadcastResult = $View.FindName('SubnetBroadcastResult')
    $subnetMaskResult = $View.FindName('SubnetMaskResult')
    $subnetWildcardResult = $View.FindName('SubnetWildcardResult')
    $subnetFirstResult = $View.FindName('SubnetFirstResult')
    $subnetLastResult = $View.FindName('SubnetLastResult')
    $subnetHostsResult = $View.FindName('SubnetHostsResult')
    $subnetSplitDropdown = $View.FindName('SubnetSplitDropdown')
    $subnetSplitButton = $View.FindName('SubnetSplitButton')
    $subnetSplitGrid = $View.FindName('SubnetSplitGrid')
    $subnetCopyButton = $View.FindName('SubnetCopyButton')

    # Get VLAN Calculator controls
    $vlanExpandInput = $View.FindName('VLANExpandInput')
    $vlanExpandButton = $View.FindName('VLANExpandButton')
    $vlanExpandResult = $View.FindName('VLANExpandResult')
    $vlanCompressInput = $View.FindName('VLANCompressInput')
    $vlanCompressButton = $View.FindName('VLANCompressButton')
    $vlanCompressResult = $View.FindName('VLANCompressResult')

    # Get Bandwidth Calculator controls
    $bandwidthSizeBox = $View.FindName('BandwidthSizeBox')
    $bandwidthSizeUnit = $View.FindName('BandwidthSizeUnit')
    $bandwidthSpeedBox = $View.FindName('BandwidthSpeedBox')
    $bandwidthSpeedUnit = $View.FindName('BandwidthSpeedUnit')
    $bandwidthCalcButton = $View.FindName('BandwidthCalcButton')
    $bandwidthResult = $View.FindName('BandwidthResult')
    $convertValueBox = $View.FindName('ConvertValueBox')
    $convertFromUnit = $View.FindName('ConvertFromUnit')
    $convertToUnit = $View.FindName('ConvertToUnit')
    $convertButton = $View.FindName('ConvertButton')
    $convertResult = $View.FindName('ConvertResult')

    # Get IP Tools controls
    $ipValidateBox = $View.FindName('IPValidateBox')
    $ipValidateButton = $View.FindName('IPValidateButton')
    $ipValidateResult = $View.FindName('IPValidateResult')
    $ipCheckBox = $View.FindName('IPCheckBox')
    $subnetCheckBox = $View.FindName('SubnetCheckBox')
    $ipCheckButton = $View.FindName('IPCheckButton')
    $ipCheckResult = $View.FindName('IPCheckResult')

    # Get Ports Reference controls
    $portSearchBox = $View.FindName('PortSearchBox')
    $portSearchButton = $View.FindName('PortSearchButton')
    $portShowAllButton = $View.FindName('PortShowAllButton')
    $portsGrid = $View.FindName('PortsGrid')

    # Store state in view's Tag
    $View.Tag = @{ CurrentSubnetInfo = $null }

    # Populate CIDR dropdown (8-30)
    if ($subnetCIDRDropdown) {
        for ($i = 8; $i -le 30; $i++) { $item = New-Object System.Windows.Controls.ComboBoxItem; $item.Content = $i; $subnetCIDRDropdown.Items.Add($item) | Out-Null }
        $subnetCIDRDropdown.SelectedIndex = 16
    }

    # Populate split dropdown
    if ($subnetSplitDropdown) {
        for ($i = 9; $i -le 30; $i++) { $item = New-Object System.Windows.Controls.ComboBoxItem; $item.Content = "/$i"; $subnetSplitDropdown.Items.Add($item) | Out-Null }
        $subnetSplitDropdown.SelectedIndex = 0
    }

    # Subnet Calculate button
    if ($subnetCalculateButton) {
        $subnetCalculateButton.Add_Click({
            param($s,$e)
            $network = if ($subnetNetworkBox) { $subnetNetworkBox.Text } else { '' }
            $cidr = if ($subnetCIDRDropdown -and $subnetCIDRDropdown.SelectedItem) { [int]$subnetCIDRDropdown.SelectedItem.Content } else { 24 }
            if ([string]::IsNullOrWhiteSpace($network)) { return }
            try {
                $info = NetworkCalculatorModule\Get-SubnetInfo -Network $network -CIDR $cidr
                $View.Tag.CurrentSubnetInfo = $info
                if ($subnetNetworkResult) { $subnetNetworkResult.Text = $info.NetworkAddress }
                if ($subnetBroadcastResult) { $subnetBroadcastResult.Text = $info.BroadcastAddress }
                if ($subnetMaskResult) { $subnetMaskResult.Text = $info.SubnetMask }
                if ($subnetWildcardResult) { $subnetWildcardResult.Text = $info.WildcardMask }
                if ($subnetFirstResult) { $subnetFirstResult.Text = $info.FirstUsable }
                if ($subnetLastResult) { $subnetLastResult.Text = $info.LastUsable }
                if ($subnetHostsResult) { $subnetHostsResult.Text = $info.TotalHosts.ToString() }
                if ($subnetSplitDropdown) { $subnetSplitDropdown.Items.Clear(); for ($i = $cidr + 1; $i -le 30; $i++) { $item = New-Object System.Windows.Controls.ComboBoxItem; $item.Content = "/$i"; $subnetSplitDropdown.Items.Add($item) | Out-Null }; if ($subnetSplitDropdown.Items.Count -gt 0) { $subnetSplitDropdown.SelectedIndex = 0 } }
                if ($subnetSplitGrid) { $subnetSplitGrid.ItemsSource = $null }
            } catch {
                if ($subnetNetworkResult) { $subnetNetworkResult.Text = "Error" }
                if ($subnetHostsResult) { $subnetHostsResult.Text = $_.Exception.Message }
            }
        }.GetNewClosure())
    }

    if ($subnetNetworkBox) { $subnetNetworkBox.Add_KeyDown({ param($s,$e); if ($e.Key -eq 'Return' -and $subnetCalculateButton) { $subnetCalculateButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } }.GetNewClosure()) }

    # Subnet Split button
    if ($subnetSplitButton) {
        $subnetSplitButton.Add_Click({
            param($s,$e)
            $info = $View.Tag.CurrentSubnetInfo
            if ($null -eq $info) { return }
            $targetPrefix = if ($subnetSplitDropdown -and $subnetSplitDropdown.SelectedItem) { [int]($subnetSplitDropdown.SelectedItem.Content -replace '^/', '') } else { return }
            try { $subnets = NetworkCalculatorModule\Split-Subnet -NetworkAddress $info.NetworkAddress -CurrentPrefix $info.CIDR -TargetPrefix $targetPrefix; if ($subnetSplitGrid) { $subnetSplitGrid.ItemsSource = $subnets } } catch { if ($subnetSplitGrid) { $subnetSplitGrid.ItemsSource = $null } }
        }.GetNewClosure())
    }

    # Subnet Copy button
    if ($subnetCopyButton) {
        $subnetCopyButton.Add_Click({
            param($s,$e)
            $info = $View.Tag.CurrentSubnetInfo
            if ($null -eq $info) { return }
            $text = "Network: $($info.NetworkAddress)/$($info.CIDR)`nSubnet Mask: $($info.SubnetMask)`nWildcard: $($info.WildcardMask)`nBroadcast: $($info.BroadcastAddress)`nFirst Usable: $($info.FirstUsable)`nLast Usable: $($info.LastUsable)`nTotal Hosts: $($info.TotalHosts)"
            [System.Windows.Clipboard]::SetText($text)
        }.GetNewClosure())
    }

    # VLAN Expand button
    if ($vlanExpandButton) {
        $vlanExpandButton.Add_Click({
            param($s,$e)
            $range = if ($vlanExpandInput) { $vlanExpandInput.Text } else { '' }
            if ([string]::IsNullOrWhiteSpace($range)) { if ($vlanExpandResult) { $vlanExpandResult.Text = '' }; return }
            try { $vlans = NetworkCalculatorModule\Expand-VLANRange -Range $range; if ($vlanExpandResult) { $vlanExpandResult.Text = ($vlans -join ', ') } } catch { if ($vlanExpandResult) { $vlanExpandResult.Text = "Error: $($_.Exception.Message)" } }
        }.GetNewClosure())
    }
    if ($vlanExpandInput) { $vlanExpandInput.Add_KeyDown({ param($s,$e); if ($e.Key -eq 'Return' -and $vlanExpandButton) { $vlanExpandButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } }.GetNewClosure()) }

    # VLAN Compress button
    if ($vlanCompressButton) {
        $vlanCompressButton.Add_Click({
            param($s,$e)
            $input = if ($vlanCompressInput) { $vlanCompressInput.Text } else { '' }
            if ([string]::IsNullOrWhiteSpace($input)) { if ($vlanCompressResult) { $vlanCompressResult.Text = '' }; return }
            try { $vlans = @($input -split '\s*,\s*' | ForEach-Object { [int]$_ }); $result = NetworkCalculatorModule\Compress-VLANList -VLANs $vlans; if ($vlanCompressResult) { $vlanCompressResult.Text = $result } } catch { if ($vlanCompressResult) { $vlanCompressResult.Text = "Error: $($_.Exception.Message)" } }
        }.GetNewClosure())
    }
    if ($vlanCompressInput) { $vlanCompressInput.Add_KeyDown({ param($s,$e); if ($e.Key -eq 'Return' -and $vlanCompressButton) { $vlanCompressButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } }.GetNewClosure()) }

    # Bandwidth Calculate button
    if ($bandwidthCalcButton) {
        $bandwidthCalcButton.Add_Click({
            param($s,$e)
            $sizeText = if ($bandwidthSizeBox) { $bandwidthSizeBox.Text } else { '' }
            $sizeUnit = if ($bandwidthSizeUnit -and $bandwidthSizeUnit.SelectedItem) { $bandwidthSizeUnit.SelectedItem.Content } else { 'MB' }
            $speedText = if ($bandwidthSpeedBox) { $bandwidthSpeedBox.Text } else { '' }
            $speedUnit = if ($bandwidthSpeedUnit -and $bandwidthSpeedUnit.SelectedItem) { $bandwidthSpeedUnit.SelectedItem.Content } else { 'Mbps' }
            if ([string]::IsNullOrWhiteSpace($sizeText) -or [string]::IsNullOrWhiteSpace($speedText)) { if ($bandwidthResult) { $bandwidthResult.Text = '' }; return }
            try {
                $size = [double]$sizeText; $speed = [double]$speedText
                $sizeBytes = switch ($sizeUnit) { 'MB' { $size * 1024 * 1024 }; 'GB' { $size * 1024 * 1024 * 1024 }; 'TB' { $size * 1024 * 1024 * 1024 * 1024 }; default { $size * 1024 * 1024 } }
                $speedBps = switch ($speedUnit) { 'Mbps' { $speed * 1000000 }; 'Gbps' { $speed * 1000000000 }; default { $speed * 1000000 } }
                $result = NetworkCalculatorModule\Get-TransferTime -SizeBytes $sizeBytes -BandwidthBps $speedBps
                if ($bandwidthResult) { $bandwidthResult.Text = $result.FormattedTime }
            } catch { if ($bandwidthResult) { $bandwidthResult.Text = "Error: $($_.Exception.Message)" } }
        }.GetNewClosure())
    }
    if ($bandwidthSizeBox) { $bandwidthSizeBox.Add_KeyDown({ param($s,$e); if ($e.Key -eq 'Return' -and $bandwidthCalcButton) { $bandwidthCalcButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } }.GetNewClosure()) }
    if ($bandwidthSpeedBox) { $bandwidthSpeedBox.Add_KeyDown({ param($s,$e); if ($e.Key -eq 'Return' -and $bandwidthCalcButton) { $bandwidthCalcButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } }.GetNewClosure()) }

    # Unit Convert button
    if ($convertButton) {
        $convertButton.Add_Click({
            param($s,$e)
            $valueText = if ($convertValueBox) { $convertValueBox.Text } else { '' }
            $fromUnit = if ($convertFromUnit -and $convertFromUnit.SelectedItem) { $convertFromUnit.SelectedItem.Content } else { 'Mbps' }
            $toUnit = if ($convertToUnit -and $convertToUnit.SelectedItem) { $convertToUnit.SelectedItem.Content } else { 'Gbps' }
            if ([string]::IsNullOrWhiteSpace($valueText)) { if ($convertResult) { $convertResult.Text = '' }; return }
            try { $value = [double]$valueText; $result = NetworkCalculatorModule\Convert-BandwidthUnit -Value $value -FromUnit $fromUnit -ToUnit $toUnit; if ($convertResult) { $convertResult.Text = [math]::Round($result, 4).ToString() } } catch { if ($convertResult) { $convertResult.Text = "Error" } }
        }.GetNewClosure())
    }
    if ($convertValueBox) { $convertValueBox.Add_KeyDown({ param($s,$e); if ($e.Key -eq 'Return' -and $convertButton) { $convertButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } }.GetNewClosure()) }

    # IP Validate button
    if ($ipValidateButton) {
        $ipValidateButton.Add_Click({
            param($s,$e)
            $ip = if ($ipValidateBox) { $ipValidateBox.Text } else { '' }
            if ([string]::IsNullOrWhiteSpace($ip)) { if ($ipValidateResult) { $ipValidateResult.Text = '' }; return }
            try { $info = NetworkCalculatorModule\Get-IPAddressInfo -IPAddress $ip; $lines = @("Valid: $($info.IsValid)"); if ($info.IsValid) { $lines += "Type: $($info.AddressType)"; $lines += "Class: $($info.Class)"; $lines += "Binary: $($info.Binary)" }; if ($ipValidateResult) { $ipValidateResult.Text = $lines -join "`r`n" } } catch { if ($ipValidateResult) { $ipValidateResult.Text = "Error: $($_.Exception.Message)" } }
        }.GetNewClosure())
    }
    if ($ipValidateBox) { $ipValidateBox.Add_KeyDown({ param($s,$e); if ($e.Key -eq 'Return' -and $ipValidateButton) { $ipValidateButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } }.GetNewClosure()) }

    # IP Check button
    if ($ipCheckButton) {
        $ipCheckButton.Add_Click({
            param($s,$e)
            $ip = if ($ipCheckBox) { $ipCheckBox.Text } else { '' }
            $subnet = if ($subnetCheckBox) { $subnetCheckBox.Text } else { '' }
            if ([string]::IsNullOrWhiteSpace($ip) -or [string]::IsNullOrWhiteSpace($subnet)) { if ($ipCheckResult) { $ipCheckResult.Text = '' }; return }
            try { $result = NetworkCalculatorModule\Test-IPInSubnet -IPAddress $ip -Subnet $subnet; if ($ipCheckResult) { $ipCheckResult.Text = if ($result) { "Yes" } else { "No" } } } catch { if ($ipCheckResult) { $ipCheckResult.Text = "Error" } }
        }.GetNewClosure())
    }
    if ($ipCheckBox) { $ipCheckBox.Add_KeyDown({ param($s,$e); if ($e.Key -eq 'Return' -and $ipCheckButton) { $ipCheckButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } }.GetNewClosure()) }
    if ($subnetCheckBox) { $subnetCheckBox.Add_KeyDown({ param($s,$e); if ($e.Key -eq 'Return' -and $ipCheckButton) { $ipCheckButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } }.GetNewClosure()) }

    # Port Search button
    if ($portSearchButton) {
        $portSearchButton.Add_Click({
            param($s,$e)
            $query = if ($portSearchBox) { $portSearchBox.Text } else { '' }
            if ([string]::IsNullOrWhiteSpace($query)) { if ($portsGrid) { $portsGrid.ItemsSource = $null }; return }
            try { $results = NetworkCalculatorModule\Get-WellKnownPorts | Where-Object { $_.Port -eq $query -or $_.Service -like "*$query*" }; if ($portsGrid) { $portsGrid.ItemsSource = @($results) } } catch { if ($portsGrid) { $portsGrid.ItemsSource = $null } }
        }.GetNewClosure())
    }
    if ($portSearchBox) { $portSearchBox.Add_KeyDown({ param($s,$e); if ($e.Key -eq 'Return' -and $portSearchButton) { $portSearchButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } }.GetNewClosure()) }

    # Port Show All button
    if ($portShowAllButton) {
        $portShowAllButton.Add_Click({
            param($s,$e)
            try { $ports = NetworkCalculatorModule\Get-WellKnownPorts; if ($portsGrid) { $portsGrid.ItemsSource = @($ports) } } catch { if ($portsGrid) { $portsGrid.ItemsSource = $null } }
        }.GetNewClosure())
    }

    # Load initial ports list
    try { $ports = NetworkCalculatorModule\Get-WellKnownPorts; if ($portsGrid) { $portsGrid.ItemsSource = @($ports) } } catch { Write-Verbose "Caught exception in NetworkCalculatorViewModule.psm1: $($_.Exception.Message)" }
}

Export-ModuleMember -Function New-NetworkCalculatorView, Initialize-NetworkCalculatorView
