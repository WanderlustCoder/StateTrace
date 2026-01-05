Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Creates and initializes the IPAM (IP Address Management) view.

.DESCRIPTION
    Loads IPAMView.xaml using ViewCompositionModule, wires up event handlers,
    and provides VLAN, subnet, and IP address management functionality.
    Part of Plan V - IP Address & VLAN Planning.

.PARAMETER Window
    The parent MainWindow instance.

.PARAMETER ScriptDir
    The root script directory for locating XAML files.

.OUTPUTS
    System.Windows.Controls.UserControl - The initialized view.
#>
function New-IPAMView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory=$true)]
        [string]$ScriptDir
    )

    try {
        $view = ViewCompositionModule\Set-StView -Window $Window -ScriptDir $ScriptDir `
            -ViewName 'IPAMView' -HostControlName 'IPAMHost' `
            -GlobalVariableName 'ipamView'
        if (-not $view) { return }

        # Get toolbar controls
        $addVlanButton = $view.FindName('AddVlanButton')
        $addSubnetButton = $view.FindName('AddSubnetButton')
        $addIPButton = $view.FindName('AddIPButton')
        $importButton = $view.FindName('ImportButton')
        $exportButton = $view.FindName('ExportButton')
        $checkConflictsButton = $view.FindName('CheckConflictsButton')
        $planSiteButton = $view.FindName('PlanSiteButton')
        $siteFilterCombo = $view.FindName('SiteFilterCombo')

        # Tab control
        $mainTabControl = $view.FindName('MainTabControl')

        # VLAN controls
        $vlanGrid = $view.FindName('VlanGrid')
        $vlanNumberBox = $view.FindName('VlanNumberBox')
        $vlanNameBox = $view.FindName('VlanNameBox')
        $vlanPurposeCombo = $view.FindName('VlanPurposeCombo')
        $vlanSiteBox = $view.FindName('VlanSiteBox')
        $vlanStatusCombo = $view.FindName('VlanStatusCombo')
        $vlanSVIBox = $view.FindName('VlanSVIBox')
        $vlanDescriptionBox = $view.FindName('VlanDescriptionBox')
        $saveVlanButton = $view.FindName('SaveVlanButton')
        $deleteVlanButton = $view.FindName('DeleteVlanButton')

        # Subnet controls
        $subnetGrid = $view.FindName('SubnetGrid')
        $subnetAddressBox = $view.FindName('SubnetAddressBox')
        $subnetPrefixBox = $view.FindName('SubnetPrefixBox')
        $subnetVlanBox = $view.FindName('SubnetVlanBox')
        $subnetSiteBox = $view.FindName('SubnetSiteBox')
        $subnetPurposeCombo = $view.FindName('SubnetPurposeCombo')
        $subnetGatewayBox = $view.FindName('SubnetGatewayBox')
        $subnetStatusCombo = $view.FindName('SubnetStatusCombo')
        $subnetMaskText = $view.FindName('SubnetMaskText')
        $subnetRangeText = $view.FindName('SubnetRangeText')
        $subnetHostsText = $view.FindName('SubnetHostsText')
        $saveSubnetButton = $view.FindName('SaveSubnetButton')
        $deleteSubnetButton = $view.FindName('DeleteSubnetButton')
        $splitSubnetButton = $view.FindName('SplitSubnetButton')

        # IP controls
        $ipGrid = $view.FindName('IPGrid')
        $ipAddressBox = $view.FindName('IPAddressBox')
        $ipDeviceBox = $view.FindName('IPDeviceBox')
        $ipInterfaceBox = $view.FindName('IPInterfaceBox')
        $ipTypeCombo = $view.FindName('IPTypeCombo')
        $ipDescriptionBox = $view.FindName('IPDescriptionBox')
        $saveIPButton = $view.FindName('SaveIPButton')
        $deleteIPButton = $view.FindName('DeleteIPButton')

        # Conflicts controls
        $refreshConflictsButton = $view.FindName('RefreshConflictsButton')
        $conflictSummaryText = $view.FindName('ConflictSummaryText')
        $conflictsGrid = $view.FindName('ConflictsGrid')

        # Statistics controls
        $totalVlansText = $view.FindName('TotalVlansText')
        $vlansByPurposeList = $view.FindName('VlansByPurposeList')
        $totalSubnetsText = $view.FindName('TotalSubnetsText')
        $totalHostsText = $view.FindName('TotalHostsText')
        $subnetsByPurposeList = $view.FindName('SubnetsByPurposeList')
        $totalIPsText = $view.FindName('TotalIPsText')
        $sitesListText = $view.FindName('SitesListText')

        $statusText = $view.FindName('StatusText')

        # Initialize database
        $dataPath = Join-Path $ScriptDir 'Data\IPAMDatabase.json'
        $script:ipamDb = IPAMModule\New-IPAMDatabase

        # Try to load existing data
        if (Test-Path $dataPath) {
            try {
                IPAMModule\Import-IPAMDatabase -Path $dataPath -Database $script:ipamDb | Out-Null
                $statusText.Text = "Loaded database from $dataPath"
            }
            catch {
                $statusText.Text = "Error loading database: $($_.Exception.Message)"
            }
        }

        # Store state in view's Tag
        $view.Tag = @{
            Database = $script:ipamDb
            DataPath = $dataPath
            IsNewVlan = $false
            IsNewSubnet = $false
            IsNewIP = $false
            SelectedVlan = $null
            SelectedSubnet = $null
            SelectedIP = $null
        }

        # Helper: Get selected combo content
        function Get-ComboValue {
            param($Combo)
            if ($Combo.SelectedItem) {
                return $Combo.SelectedItem.Content
            }
            return $null
        }

        # Helper: Select combo item by content
        function Select-ComboItem {
            param($Combo, $Value)
            foreach ($item in $Combo.Items) {
                if ($item.Content -eq $Value) {
                    $Combo.SelectedItem = $item
                    return
                }
            }
        }

        # Helper: Save database
        function Save-Database {
            $dataPath = $view.Tag.DataPath
            $db = $view.Tag.Database
            try {
                $dataDir = Split-Path $dataPath -Parent
                if (-not (Test-Path $dataDir)) {
                    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
                }
                IPAMModule\Export-IPAMDatabase -Path $dataPath -Database $db
                $statusText.Text = "Saved to $dataPath"
            }
            catch {
                $statusText.Text = "Error saving: $($_.Exception.Message)"
            }
        }

        # Helper: Refresh site filter
        function Refresh-SiteFilter {
            $db = $view.Tag.Database
            $stats = IPAMModule\Get-IPAMStats -Database $db
            $sites = @('(All Sites)') + @($stats.Sites | Where-Object { $_ })
            $siteFilterCombo.ItemsSource = $sites
            if ($siteFilterCombo.SelectedIndex -lt 0) {
                $siteFilterCombo.SelectedIndex = 0
            }
        }

        # Helper: Get current site filter
        function Get-SiteFilter {
            $selected = $siteFilterCombo.SelectedItem
            if ($selected -and $selected -ne '(All Sites)') {
                return $selected
            }
            return $null
        }

        # Helper: Refresh VLAN grid
        function Refresh-VlanGrid {
            $db = $view.Tag.Database
            $site = Get-SiteFilter
            $vlans = @(IPAMModule\Get-VLANRecord -Database $db -Site $site)
            $vlanGrid.ItemsSource = $vlans
        }

        # Helper: Refresh Subnet grid
        function Refresh-SubnetGrid {
            $db = $view.Tag.Database
            $site = Get-SiteFilter
            $subnets = @(IPAMModule\Get-SubnetRecord -Database $db -Site $site)
            $subnetGrid.ItemsSource = $subnets
        }

        # Helper: Refresh IP grid
        function Refresh-IPGrid {
            $db = $view.Tag.Database
            $ips = @(IPAMModule\Get-IPAddressRecord -Database $db)
            $ipGrid.ItemsSource = $ips
        }

        # Helper: Refresh conflicts
        function Refresh-Conflicts {
            $db = $view.Tag.Database
            $conflicts = @(IPAMModule\Find-IPAMConflicts -Database $db)
            $conflictsGrid.ItemsSource = $conflicts

            $critical = @($conflicts | Where-Object { $_.Severity -eq 'Critical' }).Count
            $warning = @($conflicts | Where-Object { $_.Severity -eq 'Warning' }).Count
            $conflictSummaryText.Text = "Found $($conflicts.Count) conflicts ($critical critical, $warning warnings)"
        }

        # Helper: Refresh statistics
        function Refresh-Stats {
            $db = $view.Tag.Database
            $stats = IPAMModule\Get-IPAMStats -Database $db

            $totalVlansText.Text = "Total VLANs: $($stats.TotalVLANs)"
            $totalSubnetsText.Text = "Total Subnets: $($stats.TotalSubnets)"
            $totalHostsText.Text = "Total Allocated Hosts: $($stats.TotalAllocatedHosts)"
            $totalIPsText.Text = "Total IP Records: $($stats.TotalIPAddresses)"

            if ($stats.Sites.Count -gt 0) {
                $sitesListText.Text = "Sites: $($stats.Sites -join ', ')"
            } else {
                $sitesListText.Text = "Sites: (none)"
            }

            # VLAN by purpose
            $vlanPurposeList = @()
            foreach ($key in $stats.VLANsByPurpose.Keys) {
                $vlanPurposeList += [PSCustomObject]@{ Key = $key; Value = $stats.VLANsByPurpose[$key] }
            }
            $vlansByPurposeList.ItemsSource = $vlanPurposeList

            # Subnet by purpose
            $subnetPurposeList = @()
            foreach ($key in $stats.SubnetsByPurpose.Keys) {
                $subnetPurposeList += [PSCustomObject]@{ Key = $key; Value = $stats.SubnetsByPurpose[$key] }
            }
            $subnetsByPurposeList.ItemsSource = $subnetPurposeList
        }

        # Helper: Refresh all grids
        function Refresh-All {
            Refresh-SiteFilter
            Refresh-VlanGrid
            Refresh-SubnetGrid
            Refresh-IPGrid
            Refresh-Stats
        }

        # Helper: Clear VLAN details
        function Clear-VlanDetails {
            $vlanNumberBox.Text = ''
            $vlanNameBox.Text = ''
            $vlanPurposeCombo.SelectedIndex = 0
            $vlanSiteBox.Text = ''
            $vlanStatusCombo.SelectedIndex = 0
            $vlanSVIBox.Text = ''
            $vlanDescriptionBox.Text = ''
            $view.Tag.SelectedVlan = $null
            $view.Tag.IsNewVlan = $true
        }

        # Helper: Show VLAN details
        function Show-VlanDetails {
            param($Vlan)
            if ($Vlan) {
                $view.Tag.SelectedVlan = $Vlan
                $view.Tag.IsNewVlan = $false
                $vlanNumberBox.Text = $Vlan.VlanNumber
                $vlanNameBox.Text = $Vlan.VlanName
                Select-ComboItem -Combo $vlanPurposeCombo -Value $Vlan.Purpose
                $vlanSiteBox.Text = $Vlan.Site
                Select-ComboItem -Combo $vlanStatusCombo -Value $Vlan.Status
                $vlanSVIBox.Text = $Vlan.SVIAddress
                $vlanDescriptionBox.Text = $Vlan.Description
            }
        }

        # Helper: Clear subnet details
        function Clear-SubnetDetails {
            $subnetAddressBox.Text = ''
            $subnetPrefixBox.Text = '24'
            $subnetVlanBox.Text = ''
            $subnetSiteBox.Text = ''
            $subnetPurposeCombo.SelectedIndex = 0
            $subnetGatewayBox.Text = ''
            $subnetStatusCombo.SelectedIndex = 0
            $subnetMaskText.Text = ''
            $subnetRangeText.Text = ''
            $subnetHostsText.Text = ''
            $view.Tag.SelectedSubnet = $null
            $view.Tag.IsNewSubnet = $true
        }

        # Helper: Show subnet details
        function Show-SubnetDetails {
            param($Subnet)
            if ($Subnet) {
                $view.Tag.SelectedSubnet = $Subnet
                $view.Tag.IsNewSubnet = $false
                $subnetAddressBox.Text = $Subnet.NetworkAddress
                $subnetPrefixBox.Text = $Subnet.PrefixLength
                $subnetVlanBox.Text = $Subnet.VlanNumber
                $subnetSiteBox.Text = $Subnet.Site
                Select-ComboItem -Combo $subnetPurposeCombo -Value $Subnet.Purpose
                $subnetGatewayBox.Text = $Subnet.GatewayAddress
                Select-ComboItem -Combo $subnetStatusCombo -Value $Subnet.Status
                $subnetMaskText.Text = "Mask: $($Subnet.SubnetMask)"
                $subnetRangeText.Text = "Range: $($Subnet.FirstUsable) - $($Subnet.LastUsable)"
                $subnetHostsText.Text = "Hosts: $($Subnet.TotalHosts)"
            }
        }

        # Helper: Update subnet calculation display
        function Update-SubnetCalc {
            $network = $subnetAddressBox.Text
            $prefixText = $subnetPrefixBox.Text
            if ([string]::IsNullOrWhiteSpace($network) -or [string]::IsNullOrWhiteSpace($prefixText)) {
                $subnetMaskText.Text = ''
                $subnetRangeText.Text = ''
                $subnetHostsText.Text = ''
                return
            }
            try {
                $prefix = [int]$prefixText
                if ($prefix -lt 1 -or $prefix -gt 32) { return }
                $details = IPAMModule\Get-SubnetDetails -NetworkAddress $network -PrefixLength $prefix
                if ($details) {
                    $subnetMaskText.Text = "Mask: $($details.SubnetMask)"
                    $subnetRangeText.Text = "Range: $($details.FirstUsable) - $($details.LastUsable)"
                    $subnetHostsText.Text = "Hosts: $($details.TotalHosts)"
                }
            }
            catch {
                # Ignore calculation errors during typing
            }
        }

        # Helper: Clear IP details
        function Clear-IPDetails {
            $ipAddressBox.Text = ''
            $ipDeviceBox.Text = ''
            $ipInterfaceBox.Text = ''
            $ipTypeCombo.SelectedIndex = 0
            $ipDescriptionBox.Text = ''
            $view.Tag.SelectedIP = $null
            $view.Tag.IsNewIP = $true
        }

        # Helper: Show IP details
        function Show-IPDetails {
            param($IP)
            if ($IP) {
                $view.Tag.SelectedIP = $IP
                $view.Tag.IsNewIP = $false
                $ipAddressBox.Text = $IP.IPAddress
                $ipDeviceBox.Text = $IP.DeviceName
                $ipInterfaceBox.Text = $IP.InterfaceName
                Select-ComboItem -Combo $ipTypeCombo -Value $IP.AddressType
                $ipDescriptionBox.Text = $IP.Description
            }
        }

        # Event: Add VLAN button
        $addVlanButton.Add_Click({
            param($sender, $e)
            Clear-VlanDetails
            $mainTabControl.SelectedIndex = 0  # Switch to VLANs tab
            $vlanGrid.SelectedItem = $null
            $statusText.Text = "New VLAN - fill in details and click Save"
        }.GetNewClosure())

        # Event: Add Subnet button
        $addSubnetButton.Add_Click({
            param($sender, $e)
            Clear-SubnetDetails
            $mainTabControl.SelectedIndex = 1  # Switch to Subnets tab
            $subnetGrid.SelectedItem = $null
            $statusText.Text = "New Subnet - fill in details and click Save"
        }.GetNewClosure())

        # Event: Add IP button
        $addIPButton.Add_Click({
            param($sender, $e)
            Clear-IPDetails
            $mainTabControl.SelectedIndex = 2  # Switch to IP Addresses tab
            $ipGrid.SelectedItem = $null
            $statusText.Text = "New IP Address - fill in details and click Save"
        }.GetNewClosure())

        # Event: VLAN grid selection
        $vlanGrid.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if ($selected) {
                Show-VlanDetails -Vlan $selected
            }
        }.GetNewClosure())

        # Event: Subnet grid selection
        $subnetGrid.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if ($selected) {
                Show-SubnetDetails -Subnet $selected
            }
        }.GetNewClosure())

        # Event: IP grid selection
        $ipGrid.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if ($selected) {
                Show-IPDetails -IP $selected
            }
        }.GetNewClosure())

        # Event: Save VLAN
        $saveVlanButton.Add_Click({
            param($sender, $e)
            $db = $view.Tag.Database

            $vlanNumText = $vlanNumberBox.Text
            if ([string]::IsNullOrWhiteSpace($vlanNumText) -or [string]::IsNullOrWhiteSpace($vlanNameBox.Text)) {
                $statusText.Text = 'Please enter VLAN number and name'
                return
            }

            try {
                $vlanNum = [int]$vlanNumText
                $purpose = Get-ComboValue -Combo $vlanPurposeCombo
                $status = Get-ComboValue -Combo $vlanStatusCombo

                if ($view.Tag.IsNewVlan) {
                    $params = @{
                        VlanNumber = $vlanNum
                        VlanName = $vlanNameBox.Text
                        Purpose = $purpose
                        Status = $status
                    }
                    if ($vlanSiteBox.Text) { $params['Site'] = $vlanSiteBox.Text }
                    if ($vlanSVIBox.Text) { $params['SVIAddress'] = $vlanSVIBox.Text }
                    if ($vlanDescriptionBox.Text) { $params['Description'] = $vlanDescriptionBox.Text }

                    $vlan = IPAMModule\New-VLAN @params
                    $result = IPAMModule\Add-VLAN -VLAN $vlan -Database $db
                    if ($result) {
                        $statusText.Text = "Created VLAN $vlanNum"
                    } else {
                        $statusText.Text = "Failed to add VLAN (may already exist)"
                        return
                    }
                }
                else {
                    $props = @{
                        VlanNumber = $vlanNum
                        VlanName = $vlanNameBox.Text
                        Purpose = $purpose
                        Site = $vlanSiteBox.Text
                        Status = $status
                        SVIAddress = $vlanSVIBox.Text
                        Description = $vlanDescriptionBox.Text
                    }
                    IPAMModule\Update-VLAN -VlanID $view.Tag.SelectedVlan.VlanID -Properties $props -Database $db | Out-Null
                    $statusText.Text = "Updated VLAN $vlanNum"
                }

                Save-Database
                Refresh-All
            }
            catch {
                $statusText.Text = "Error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Delete VLAN
        $deleteVlanButton.Add_Click({
            param($sender, $e)
            $vlan = $view.Tag.SelectedVlan
            if (-not $vlan) {
                $statusText.Text = 'Select a VLAN to delete'
                return
            }

            $result = [System.Windows.MessageBox]::Show(
                "Delete VLAN $($vlan.VlanNumber) ($($vlan.VlanName))?",
                "Confirm Delete",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning)

            if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                $db = $view.Tag.Database
                IPAMModule\Remove-VLAN -VlanID $vlan.VlanID -Database $db | Out-Null
                Clear-VlanDetails
                $statusText.Text = "Deleted VLAN $($vlan.VlanNumber)"
                Save-Database
                Refresh-All
            }
        }.GetNewClosure())

        # Event: Subnet address/prefix text changed - update calculation
        $subnetAddressBox.Add_TextChanged({
            param($sender, $e)
            Update-SubnetCalc
        }.GetNewClosure())

        $subnetPrefixBox.Add_TextChanged({
            param($sender, $e)
            Update-SubnetCalc
        }.GetNewClosure())

        # Event: Save Subnet
        $saveSubnetButton.Add_Click({
            param($sender, $e)
            $db = $view.Tag.Database

            if ([string]::IsNullOrWhiteSpace($subnetAddressBox.Text) -or [string]::IsNullOrWhiteSpace($subnetPrefixBox.Text)) {
                $statusText.Text = 'Please enter network address and prefix length'
                return
            }

            try {
                $prefix = [int]$subnetPrefixBox.Text
                $purpose = Get-ComboValue -Combo $subnetPurposeCombo
                $status = Get-ComboValue -Combo $subnetStatusCombo

                if ($view.Tag.IsNewSubnet) {
                    $params = @{
                        NetworkAddress = $subnetAddressBox.Text
                        PrefixLength = $prefix
                        Purpose = $purpose
                        Status = $status
                    }
                    if ($subnetVlanBox.Text) { $params['VlanNumber'] = [int]$subnetVlanBox.Text }
                    if ($subnetSiteBox.Text) { $params['Site'] = $subnetSiteBox.Text }
                    if ($subnetGatewayBox.Text) { $params['GatewayAddress'] = $subnetGatewayBox.Text }

                    $subnet = IPAMModule\New-Subnet @params
                    IPAMModule\Add-Subnet -Subnet $subnet -Database $db | Out-Null
                    $statusText.Text = "Created subnet $($subnetAddressBox.Text)/$prefix"
                }
                else {
                    # For updates, remove and re-add (simpler than partial update)
                    $oldSubnet = $view.Tag.SelectedSubnet
                    IPAMModule\Remove-Subnet -SubnetID $oldSubnet.SubnetID -Database $db | Out-Null

                    $params = @{
                        NetworkAddress = $subnetAddressBox.Text
                        PrefixLength = $prefix
                        Purpose = $purpose
                        Status = $status
                    }
                    if ($subnetVlanBox.Text) { $params['VlanNumber'] = [int]$subnetVlanBox.Text }
                    if ($subnetSiteBox.Text) { $params['Site'] = $subnetSiteBox.Text }
                    if ($subnetGatewayBox.Text) { $params['GatewayAddress'] = $subnetGatewayBox.Text }

                    $subnet = IPAMModule\New-Subnet @params
                    IPAMModule\Add-Subnet -Subnet $subnet -Database $db | Out-Null
                    $statusText.Text = "Updated subnet $($subnetAddressBox.Text)/$prefix"
                }

                Save-Database
                Refresh-All
            }
            catch {
                $statusText.Text = "Error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Delete Subnet
        $deleteSubnetButton.Add_Click({
            param($sender, $e)
            $subnet = $view.Tag.SelectedSubnet
            if (-not $subnet) {
                $statusText.Text = 'Select a subnet to delete'
                return
            }

            $result = [System.Windows.MessageBox]::Show(
                "Delete subnet $($subnet.NetworkAddress)/$($subnet.PrefixLength)?",
                "Confirm Delete",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning)

            if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                $db = $view.Tag.Database
                IPAMModule\Remove-Subnet -SubnetID $subnet.SubnetID -Database $db | Out-Null
                Clear-SubnetDetails
                $statusText.Text = "Deleted subnet $($subnet.NetworkAddress)/$($subnet.PrefixLength)"
                Save-Database
                Refresh-All
            }
        }.GetNewClosure())

        # Event: Split Subnet
        $splitSubnetButton.Add_Click({
            param($sender, $e)
            $subnet = $view.Tag.SelectedSubnet
            if (-not $subnet) {
                $statusText.Text = 'Select a subnet to split'
                return
            }

            # Split into next smaller prefix
            $newPrefix = $subnet.PrefixLength + 1
            if ($newPrefix -gt 30) {
                $statusText.Text = 'Cannot split subnet further'
                return
            }

            try {
                $newSubnets = IPAMModule\Split-Subnet -NetworkAddress $subnet.NetworkAddress `
                    -PrefixLength $subnet.PrefixLength -NewPrefixLength $newPrefix

                $msg = "Split $($subnet.NetworkAddress)/$($subnet.PrefixLength) into:`n"
                foreach ($ns in $newSubnets) {
                    $msg += "  $($ns.NetworkAddress)/$($ns.PrefixLength)`n"
                }
                $msg += "`nAdd these subnets?"

                $result = [System.Windows.MessageBox]::Show($msg, "Split Subnet",
                    [System.Windows.MessageBoxButton]::YesNo,
                    [System.Windows.MessageBoxImage]::Question)

                if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                    $db = $view.Tag.Database

                    # Remove original
                    IPAMModule\Remove-Subnet -SubnetID $subnet.SubnetID -Database $db | Out-Null

                    # Add new subnets
                    foreach ($ns in $newSubnets) {
                        $newSub = IPAMModule\New-Subnet -NetworkAddress $ns.NetworkAddress `
                            -PrefixLength $ns.PrefixLength -Purpose $subnet.Purpose `
                            -Site $subnet.Site -Status 'Available'
                        IPAMModule\Add-Subnet -Subnet $newSub -Database $db | Out-Null
                    }

                    $statusText.Text = "Split into $($newSubnets.Count) subnets"
                    Save-Database
                    Refresh-All
                }
            }
            catch {
                $statusText.Text = "Error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Save IP
        $saveIPButton.Add_Click({
            param($sender, $e)
            $db = $view.Tag.Database

            if ([string]::IsNullOrWhiteSpace($ipAddressBox.Text)) {
                $statusText.Text = 'Please enter an IP address'
                return
            }

            try {
                $addressType = Get-ComboValue -Combo $ipTypeCombo

                if ($view.Tag.IsNewIP) {
                    $params = @{
                        IPAddress = $ipAddressBox.Text
                        AddressType = $addressType
                    }
                    if ($ipDeviceBox.Text) { $params['DeviceName'] = $ipDeviceBox.Text }
                    if ($ipInterfaceBox.Text) { $params['InterfaceName'] = $ipInterfaceBox.Text }
                    if ($ipDescriptionBox.Text) { $params['Description'] = $ipDescriptionBox.Text }

                    $ip = IPAMModule\New-IPAddressRecord @params
                    IPAMModule\Add-IPAddressRecord -IPRecord $ip -Database $db | Out-Null
                    $statusText.Text = "Created IP record $($ipAddressBox.Text)"
                }
                else {
                    # Remove and re-add for update
                    $oldIP = $view.Tag.SelectedIP
                    IPAMModule\Remove-IPAddressRecord -AddressID $oldIP.AddressID -Database $db | Out-Null

                    $params = @{
                        IPAddress = $ipAddressBox.Text
                        AddressType = $addressType
                    }
                    if ($ipDeviceBox.Text) { $params['DeviceName'] = $ipDeviceBox.Text }
                    if ($ipInterfaceBox.Text) { $params['InterfaceName'] = $ipInterfaceBox.Text }
                    if ($ipDescriptionBox.Text) { $params['Description'] = $ipDescriptionBox.Text }

                    $ip = IPAMModule\New-IPAddressRecord @params
                    IPAMModule\Add-IPAddressRecord -IPRecord $ip -Database $db | Out-Null
                    $statusText.Text = "Updated IP record $($ipAddressBox.Text)"
                }

                Save-Database
                Refresh-All
            }
            catch {
                $statusText.Text = "Error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Delete IP
        $deleteIPButton.Add_Click({
            param($sender, $e)
            $ip = $view.Tag.SelectedIP
            if (-not $ip) {
                $statusText.Text = 'Select an IP record to delete'
                return
            }

            $result = [System.Windows.MessageBox]::Show(
                "Delete IP record $($ip.IPAddress)?",
                "Confirm Delete",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning)

            if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                $db = $view.Tag.Database
                IPAMModule\Remove-IPAddressRecord -AddressID $ip.AddressID -Database $db | Out-Null
                Clear-IPDetails
                $statusText.Text = "Deleted IP record $($ip.IPAddress)"
                Save-Database
                Refresh-All
            }
        }.GetNewClosure())

        # Event: Check Conflicts
        $checkConflictsButton.Add_Click({
            param($sender, $e)
            Refresh-Conflicts
            $mainTabControl.SelectedIndex = 3  # Switch to Conflicts tab
        }.GetNewClosure())

        # Event: Refresh Conflicts button
        $refreshConflictsButton.Add_Click({
            param($sender, $e)
            Refresh-Conflicts
        }.GetNewClosure())

        # Event: Plan Site
        $planSiteButton.Add_Click({
            param($sender, $e)
            # Simple site planning dialog
            $siteName = [Microsoft.VisualBasic.Interaction]::InputBox(
                "Enter site name for address plan:",
                "Plan Site",
                "NewSite")

            if ([string]::IsNullOrWhiteSpace($siteName)) { return }

            $supernet = [Microsoft.VisualBasic.Interaction]::InputBox(
                "Enter supernet (e.g., 10.1.0.0/16):",
                "Plan Site",
                "10.1.0.0/16")

            if ([string]::IsNullOrWhiteSpace($supernet)) { return }

            try {
                $parts = $supernet -split '/'
                $network = $parts[0]
                $prefix = [int]$parts[1]

                $db = $view.Tag.Database
                $plan = IPAMModule\New-SiteAddressPlan -SiteName $siteName `
                    -SupernetAddress $network -SupernetPrefix $prefix -Database $db

                $msg = "Site Plan for $siteName`n`n"
                foreach ($alloc in $plan.Allocations) {
                    $msg += "VLAN $($alloc.VlanNumber) ($($alloc.VLANType)): $($alloc.NetworkAddress)/$($alloc.PrefixLength)`n"
                }
                $msg += "`nApply this plan?"

                $result = [System.Windows.MessageBox]::Show($msg, "Site Address Plan",
                    [System.Windows.MessageBoxButton]::YesNo,
                    [System.Windows.MessageBoxImage]::Question)

                if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                    foreach ($alloc in $plan.Allocations) {
                        # Create VLAN
                        $vlan = IPAMModule\New-VLAN -VlanNumber $alloc.VlanNumber `
                            -VlanName "$siteName-$($alloc.VLANType)" `
                            -Purpose $alloc.VLANType -Site $siteName
                        IPAMModule\Add-VLAN -VLAN $vlan -Database $db -WarningAction SilentlyContinue | Out-Null

                        # Create Subnet
                        $subnet = IPAMModule\New-Subnet -NetworkAddress $alloc.NetworkAddress `
                            -PrefixLength $alloc.PrefixLength -VlanNumber $alloc.VlanNumber `
                            -Site $siteName -Purpose $alloc.VLANType `
                            -GatewayAddress $alloc.GatewayAddress
                        IPAMModule\Add-Subnet -Subnet $subnet -Database $db -WarningAction SilentlyContinue | Out-Null
                    }

                    $statusText.Text = "Applied site plan for $siteName"
                    Save-Database
                    Refresh-All
                }
            }
            catch {
                $statusText.Text = "Error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Site filter changed
        $siteFilterCombo.Add_SelectionChanged({
            param($sender, $e)
            Refresh-VlanGrid
            Refresh-SubnetGrid
        }.GetNewClosure())

        # Event: Import
        $importButton.Add_Click({
            param($sender, $e)
            try {
                $dialog = New-Object Microsoft.Win32.OpenFileDialog
                $dialog.Title = 'Import IPAM Database'
                $dialog.Filter = 'JSON files (*.json)|*.json'

                if ($dialog.ShowDialog() -eq $true) {
                    $db = $view.Tag.Database
                    $result = IPAMModule\Import-IPAMDatabase -Path $dialog.FileName -Database $db -Merge
                    $statusText.Text = "Imported $($result.VLANsImported) VLANs, $($result.SubnetsImported) subnets, $($result.IPAddressesImported) IPs"
                    Save-Database
                    Refresh-All
                }
            }
            catch {
                $statusText.Text = "Import error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Export
        $exportButton.Add_Click({
            param($sender, $e)
            try {
                $dialog = New-Object Microsoft.Win32.SaveFileDialog
                $dialog.Title = 'Export IPAM Database'
                $dialog.Filter = 'JSON files (*.json)|*.json'
                $dialog.DefaultExt = '.json'

                if ($dialog.ShowDialog() -eq $true) {
                    $db = $view.Tag.Database
                    IPAMModule\Export-IPAMDatabase -Path $dialog.FileName -Database $db
                    $statusText.Text = "Exported database to $($dialog.FileName)"
                }
            }
            catch {
                $statusText.Text = "Export error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Load Microsoft.VisualBasic for InputBox (if available)
        try {
            Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
        }
        catch {
            # InputBox won't be available, but other features still work
        }

        # Initial load
        Refresh-All
        $statusText.Text = 'Ready'

        return $view

    } catch {
        Write-Warning "Failed to initialize IPAM view: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function New-IPAMView
