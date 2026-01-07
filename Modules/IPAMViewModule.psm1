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

        # Wizard controls
        $wizardPanel = $view.FindName('WizardPanel')
        $wizardSiteNameBox = $view.FindName('WizardSiteNameBox')
        $wizardSupernetBox = $view.FindName('WizardSupernetBox')
        $wizardPrefixCombo = $view.FindName('WizardPrefixCombo')
        $wizardGrowthSlider = $view.FindName('WizardGrowthSlider')
        $wizardGrowthText = $view.FindName('WizardGrowthText')
        $wizardPreviewPanel = $view.FindName('WizardPreviewPanel')
        $wizardPreviewBox = $view.FindName('WizardPreviewBox')
        $wizardDataCheck = $view.FindName('WizardDataCheck')
        $wizardDataHostsBox = $view.FindName('WizardDataHostsBox')
        $wizardDataSubnetText = $view.FindName('WizardDataSubnetText')
        $wizardVoiceCheck = $view.FindName('WizardVoiceCheck')
        $wizardVoiceHostsBox = $view.FindName('WizardVoiceHostsBox')
        $wizardVoiceSubnetText = $view.FindName('WizardVoiceSubnetText')
        $wizardMgmtCheck = $view.FindName('WizardMgmtCheck')
        $wizardMgmtHostsBox = $view.FindName('WizardMgmtHostsBox')
        $wizardMgmtSubnetText = $view.FindName('WizardMgmtSubnetText')
        $wizardGuestCheck = $view.FindName('WizardGuestCheck')
        $wizardGuestHostsBox = $view.FindName('WizardGuestHostsBox')
        $wizardGuestSubnetText = $view.FindName('WizardGuestSubnetText')
        $wizardIoTCheck = $view.FindName('WizardIoTCheck')
        $wizardIoTHostsBox = $view.FindName('WizardIoTHostsBox')
        $wizardIoTSubnetText = $view.FindName('WizardIoTSubnetText')
        $wizardServerCheck = $view.FindName('WizardServerCheck')
        $wizardServerHostsBox = $view.FindName('WizardServerHostsBox')
        $wizardServerSubnetText = $view.FindName('WizardServerSubnetText')
        $wizardGenerateButton = $view.FindName('WizardGenerateButton')
        $wizardApplyButton = $view.FindName('WizardApplyButton')
        $wizardCancelButton = $view.FindName('WizardCancelButton')

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
            WizardPlan = $null
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

        # Helper: Validate IPv4 address format
        function Test-IPv4Address {
            param([string]$Address)
            if ([string]::IsNullOrWhiteSpace($Address)) { return $false }
            $parts = $Address.Trim() -split '\.'
            if ($parts.Count -ne 4) { return $false }
            foreach ($part in $parts) {
                $octet = 0
                if (-not [int]::TryParse($part, [ref]$octet)) { return $false }
                if ($octet -lt 0 -or $octet -gt 255) { return $false }
            }
            return $true
        }

        # Helper: Validate VLAN number (1-4094)
        function Test-VlanNumber {
            param([string]$VlanText)
            if ([string]::IsNullOrWhiteSpace($VlanText)) { return $false }
            $vlan = 0
            if (-not [int]::TryParse($VlanText.Trim(), [ref]$vlan)) { return $false }
            return ($vlan -ge 1 -and $vlan -le 4094)
        }

        # Helper: Validate subnet prefix (0-32)
        function Test-SubnetPrefix {
            param([string]$PrefixText)
            if ([string]::IsNullOrWhiteSpace($PrefixText)) { return $false }
            $prefix = 0
            if (-not [int]::TryParse($PrefixText.Trim(), [ref]$prefix)) { return $false }
            return ($prefix -ge 0 -and $prefix -le 32)
        }

        # Helper: Save database (scriptblock for closure capture)
        $saveDatabase = {
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

        # Helper: Refresh site filter (scriptblock for closure capture)
        $refreshSiteFilter = {
            $db = $view.Tag.Database
            $stats = IPAMModule\Get-IPAMStats -Database $db
            $sites = @('(All Sites)') + @($stats.Sites | Where-Object { $_ })
            $siteFilterCombo.ItemsSource = $sites
            if ($siteFilterCombo.SelectedIndex -lt 0) {
                $siteFilterCombo.SelectedIndex = 0
            }
        }

        # Helper: Get current site filter (scriptblock for closure capture)
        $getSiteFilter = {
            $selected = $siteFilterCombo.SelectedItem
            if ($selected -and $selected -ne '(All Sites)') {
                return $selected
            }
            return $null
        }

        # Helper: Refresh VLAN grid (scriptblock for closure capture)
        $refreshVlanGrid = {
            $db = $view.Tag.Database
            $site = & $getSiteFilter
            $vlans = @(IPAMModule\Get-VLANRecord -Database $db -Site $site)
            $vlanGrid.ItemsSource = $vlans
        }

        # Helper: Refresh Subnet grid (scriptblock for closure capture)
        $refreshSubnetGrid = {
            $db = $view.Tag.Database
            $site = & $getSiteFilter
            $subnets = @(IPAMModule\Get-SubnetRecord -Database $db -Site $site)
            $subnetGrid.ItemsSource = $subnets
        }

        # Helper: Refresh IP grid (scriptblock for closure capture)
        $refreshIPGrid = {
            $db = $view.Tag.Database
            $ips = @(IPAMModule\Get-IPAddressRecord -Database $db)
            $ipGrid.ItemsSource = $ips
        }

        # Helper: Refresh conflicts (scriptblock for closure capture)
        $refreshConflicts = {
            $db = $view.Tag.Database
            $conflicts = @(IPAMModule\Find-IPAMConflicts -Database $db)
            $conflictsGrid.ItemsSource = $conflicts

            $critical = @($conflicts | Where-Object { $_.Severity -eq 'Critical' }).Count
            $warning = @($conflicts | Where-Object { $_.Severity -eq 'Warning' }).Count
            $conflictSummaryText.Text = "Found $($conflicts.Count) conflicts ($critical critical, $warning warnings)"
        }

        # Helper: Refresh statistics (scriptblock for closure capture)
        $refreshStats = {
            $db = $view.Tag.Database
            $stats = IPAMModule\Get-IPAMStats -Database $db

            $totalVlansText.Text = "Total VLANs: $($stats.TotalVLANs)"
            $totalSubnetsText.Text = "Total Subnets: $($stats.TotalSubnets)"
            $totalHostsText.Text = "Total Allocated Hosts: $($stats.TotalAllocatedHosts)"
            $totalIPsText.Text = "Total IP Records: $($stats.TotalIPAddresses)"

            $sites = @($stats.Sites)
            if ($sites.Count -gt 0) {
                $sitesListText.Text = "Sites: $($sites -join ', ')"
            } else {
                $sitesListText.Text = "Sites: (none)"
            }

            # VLAN by purpose
            $vlanPurposeList = @()
            if ($stats.VLANsByPurpose) {
                foreach ($key in $stats.VLANsByPurpose.Keys) {
                    $vlanPurposeList += [PSCustomObject]@{ Key = $key; Value = $stats.VLANsByPurpose[$key] }
                }
            }
            $vlansByPurposeList.ItemsSource = $vlanPurposeList

            # Subnet by purpose
            $subnetPurposeList = @()
            if ($stats.SubnetsByPurpose) {
                foreach ($key in $stats.SubnetsByPurpose.Keys) {
                    $subnetPurposeList += [PSCustomObject]@{ Key = $key; Value = $stats.SubnetsByPurpose[$key] }
                }
            }
            $subnetsByPurposeList.ItemsSource = $subnetPurposeList
        }

        # Helper: Refresh all grids (scriptblock for closure capture)
        $refreshAll = {
            & $refreshSiteFilter
            & $refreshVlanGrid
            & $refreshSubnetGrid
            & $refreshIPGrid
            & $refreshStats
        }

        # Helper: Clear VLAN details (scriptblock for closure capture)
        $clearVlanDetails = {
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

        # Helper: Show VLAN details (scriptblock for closure capture)
        $showVlanDetails = {
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

        # Helper: Clear subnet details (scriptblock for closure capture)
        $clearSubnetDetails = {
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

        # Helper: Show subnet details (scriptblock for closure capture)
        $showSubnetDetails = {
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

        # Helper: Update subnet calculation display (scriptblock for closure capture)
        $updateSubnetCalc = {
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

        # Helper: Clear IP details (scriptblock for closure capture)
        $clearIPDetails = {
            $ipAddressBox.Text = ''
            $ipDeviceBox.Text = ''
            $ipInterfaceBox.Text = ''
            $ipTypeCombo.SelectedIndex = 0
            $ipDescriptionBox.Text = ''
            $view.Tag.SelectedIP = $null
            $view.Tag.IsNewIP = $true
        }

        # Helper: Show IP details (scriptblock for closure capture)
        $showIPDetails = {
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
            & $clearVlanDetails
            $mainTabControl.SelectedIndex = 0  # Switch to VLANs tab
            $vlanGrid.SelectedItem = $null
            $statusText.Text = "New VLAN - fill in details and click Save"
        }.GetNewClosure())

        # Event: Add Subnet button
        $addSubnetButton.Add_Click({
            param($sender, $e)
            & $clearSubnetDetails
            $mainTabControl.SelectedIndex = 1  # Switch to Subnets tab
            $subnetGrid.SelectedItem = $null
            $statusText.Text = "New Subnet - fill in details and click Save"
        }.GetNewClosure())

        # Event: Add IP button
        $addIPButton.Add_Click({
            param($sender, $e)
            & $clearIPDetails
            $mainTabControl.SelectedIndex = 2  # Switch to IP Addresses tab
            $ipGrid.SelectedItem = $null
            $statusText.Text = "New IP Address - fill in details and click Save"
        }.GetNewClosure())

        # Event: VLAN grid selection
        $vlanGrid.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if ($selected) {
                & $showVlanDetails $selected
            }
        }.GetNewClosure())

        # Double-click to focus first editable field
        $vlanGrid.Add_MouseDoubleClick({
            param($sender, $e)
            if ($sender.SelectedItem -and $vlanNameBox) {
                $vlanNameBox.Focus()
                $vlanNameBox.SelectAll()
            }
        }.GetNewClosure())

        # Event: Subnet grid selection
        $subnetGrid.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if ($selected) {
                & $showSubnetDetails $selected
            }
        }.GetNewClosure())

        # Double-click to focus first editable field
        $subnetGrid.Add_MouseDoubleClick({
            param($sender, $e)
            if ($sender.SelectedItem -and $subnetAddressBox) {
                $subnetAddressBox.Focus()
                $subnetAddressBox.SelectAll()
            }
        }.GetNewClosure())

        # Event: IP grid selection
        $ipGrid.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if ($selected) {
                & $showIPDetails $selected
            }
        }.GetNewClosure())

        # Double-click to focus first editable field
        $ipGrid.Add_MouseDoubleClick({
            param($sender, $e)
            if ($sender.SelectedItem -and $ipAddressBox) {
                $ipAddressBox.Focus()
                $ipAddressBox.SelectAll()
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

            # Validate VLAN number
            if (-not (Test-VlanNumber -VlanText $vlanNumText)) {
                [System.Windows.MessageBox]::Show('VLAN number must be between 1 and 4094.', 'Invalid VLAN', 'OK', 'Warning')
                return
            }

            # Validate SVI address if provided
            if (-not [string]::IsNullOrWhiteSpace($vlanSVIBox.Text)) {
                if (-not (Test-IPv4Address -Address $vlanSVIBox.Text)) {
                    [System.Windows.MessageBox]::Show('SVI address must be a valid IPv4 address (e.g., 10.1.10.1).', 'Invalid SVI Address', 'OK', 'Warning')
                    return
                }
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

                & $saveDatabase
                & $refreshAll
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
                & $clearVlanDetails
                $statusText.Text = "Deleted VLAN $($vlan.VlanNumber)"
                & $saveDatabase
                & $refreshAll
            }
        }.GetNewClosure())

        # Event: Subnet address/prefix text changed - update calculation
        $subnetAddressBox.Add_TextChanged({
            param($sender, $e)
            & $updateSubnetCalc
        }.GetNewClosure())

        $subnetPrefixBox.Add_TextChanged({
            param($sender, $e)
            & $updateSubnetCalc
        }.GetNewClosure())

        # Event: Save Subnet
        $saveSubnetButton.Add_Click({
            param($sender, $e)
            $db = $view.Tag.Database

            if ([string]::IsNullOrWhiteSpace($subnetAddressBox.Text) -or [string]::IsNullOrWhiteSpace($subnetPrefixBox.Text)) {
                $statusText.Text = 'Please enter network address and prefix length'
                return
            }

            # Validate network address
            if (-not (Test-IPv4Address -Address $subnetAddressBox.Text)) {
                [System.Windows.MessageBox]::Show('Network address must be a valid IPv4 address (e.g., 10.1.10.0).', 'Invalid Network Address', 'OK', 'Warning')
                return
            }

            # Validate prefix length
            if (-not (Test-SubnetPrefix -PrefixText $subnetPrefixBox.Text)) {
                [System.Windows.MessageBox]::Show('Prefix length must be between 0 and 32.', 'Invalid Prefix', 'OK', 'Warning')
                return
            }

            # Validate gateway address if provided
            if (-not [string]::IsNullOrWhiteSpace($subnetGatewayBox.Text)) {
                if (-not (Test-IPv4Address -Address $subnetGatewayBox.Text)) {
                    [System.Windows.MessageBox]::Show('Gateway address must be a valid IPv4 address.', 'Invalid Gateway', 'OK', 'Warning')
                    return
                }
            }

            # Validate VLAN number if provided
            if (-not [string]::IsNullOrWhiteSpace($subnetVlanBox.Text)) {
                if (-not (Test-VlanNumber -VlanText $subnetVlanBox.Text)) {
                    [System.Windows.MessageBox]::Show('VLAN number must be between 1 and 4094.', 'Invalid VLAN', 'OK', 'Warning')
                    return
                }
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

                & $saveDatabase
                & $refreshAll
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
                & $clearSubnetDetails
                $statusText.Text = "Deleted subnet $($subnet.NetworkAddress)/$($subnet.PrefixLength)"
                & $saveDatabase
                & $refreshAll
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
                    & $saveDatabase
                    & $refreshAll
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

            # Validate IP address format
            if (-not (Test-IPv4Address -Address $ipAddressBox.Text)) {
                [System.Windows.MessageBox]::Show('IP address must be a valid IPv4 address (e.g., 10.1.10.5).', 'Invalid IP Address', 'OK', 'Warning')
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

                & $saveDatabase
                & $refreshAll
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
                & $clearIPDetails
                $statusText.Text = "Deleted IP record $($ip.IPAddress)"
                & $saveDatabase
                & $refreshAll
            }
        }.GetNewClosure())

        # Event: Check Conflicts
        $checkConflictsButton.Add_Click({
            param($sender, $e)
            & $refreshConflicts
            $mainTabControl.SelectedIndex = 3  # Switch to Conflicts tab
        }.GetNewClosure())

        # Event: Refresh Conflicts button
        $refreshConflictsButton.Add_Click({
            param($sender, $e)
            & $refreshConflicts
        }.GetNewClosure())

        # ========================================
        # SITE PLANNING WIZARD
        # ========================================

        # Helper: Calculate recommended prefix for host count
        function Get-RecommendedPrefix {
            param([int]$HostCount, [double]$GrowthFactor = 0.25)
            $hostsNeeded = [math]::Ceiling($HostCount * (1 + $GrowthFactor))
            # Add 2 for network and broadcast
            $hostsNeeded += 2
            # Find smallest prefix that fits
            for ($prefix = 30; $prefix -ge 16; $prefix--) {
                $hostsAvailable = [math]::Pow(2, (32 - $prefix))
                if ($hostsAvailable -ge $hostsNeeded) {
                    return $prefix
                }
            }
            return 16
        }

        # Helper: Update subnet recommendation text
        $updateSubnetRecommendations = {
            $growth = $wizardGrowthSlider.Value / 100.0

            # Data
            if ($wizardDataCheck.IsChecked) {
                $hosts = 100; try { $hosts = [int]$wizardDataHostsBox.Text } catch {}
                $wizardDataSubnetText.Text = "/$(Get-RecommendedPrefix -HostCount $hosts -GrowthFactor $growth)"
            }

            # Voice
            if ($wizardVoiceCheck.IsChecked) {
                $hosts = 50; try { $hosts = [int]$wizardVoiceHostsBox.Text } catch {}
                $wizardVoiceSubnetText.Text = "/$(Get-RecommendedPrefix -HostCount $hosts -GrowthFactor $growth)"
            }

            # Management
            if ($wizardMgmtCheck.IsChecked) {
                $hosts = 20; try { $hosts = [int]$wizardMgmtHostsBox.Text } catch {}
                $wizardMgmtSubnetText.Text = "/$(Get-RecommendedPrefix -HostCount $hosts -GrowthFactor $growth)"
            }

            # Guest
            if ($wizardGuestCheck.IsChecked) {
                $hosts = 50; try { $hosts = [int]$wizardGuestHostsBox.Text } catch {}
                $wizardGuestSubnetText.Text = "/$(Get-RecommendedPrefix -HostCount $hosts -GrowthFactor $growth)"
            }

            # IoT
            if ($wizardIoTCheck.IsChecked) {
                $hosts = 30; try { $hosts = [int]$wizardIoTHostsBox.Text } catch {}
                $wizardIoTSubnetText.Text = "/$(Get-RecommendedPrefix -HostCount $hosts -GrowthFactor $growth)"
            }

            # Server
            if ($wizardServerCheck.IsChecked) {
                $hosts = 20; try { $hosts = [int]$wizardServerHostsBox.Text } catch {}
                $wizardServerSubnetText.Text = "/$(Get-RecommendedPrefix -HostCount $hosts -GrowthFactor $growth)"
            }
        }

        # Helper: Reset wizard to initial state
        $resetWizard = {
            $wizardSiteNameBox.Text = ''
            $wizardSupernetBox.Text = ''
            $wizardPrefixCombo.SelectedIndex = 0
            $wizardGrowthSlider.Value = 25
            $wizardGrowthText.Text = '25%'
            $wizardDataCheck.IsChecked = $true
            $wizardDataHostsBox.Text = '100'
            $wizardVoiceCheck.IsChecked = $true
            $wizardVoiceHostsBox.Text = '50'
            $wizardMgmtCheck.IsChecked = $true
            $wizardMgmtHostsBox.Text = '20'
            $wizardGuestCheck.IsChecked = $false
            $wizardGuestHostsBox.Text = '50'
            $wizardIoTCheck.IsChecked = $false
            $wizardIoTHostsBox.Text = '30'
            $wizardServerCheck.IsChecked = $false
            $wizardServerHostsBox.Text = '20'
            $wizardPreviewPanel.Visibility = 'Collapsed'
            $wizardApplyButton.Visibility = 'Collapsed'
            $view.Tag.WizardPlan = $null
            & $updateSubnetRecommendations
        }

        # Event: Plan Site button - show wizard
        $planSiteButton.Add_Click({
            param($sender, $e)
            & $resetWizard
            $mainTabControl.Visibility = 'Collapsed'
            $wizardPanel.Visibility = 'Visible'
            $statusText.Text = 'Configure site address requirements'
        }.GetNewClosure())

        # Event: Growth slider changed
        $wizardGrowthSlider.Add_ValueChanged({
            param($sender, $e)
            $val = [math]::Round($sender.Value)
            $wizardGrowthText.Text = "$val%"
            & $updateSubnetRecommendations
        }.GetNewClosure())

        # Event: Host count text changed - update recommendations
        $wizardDataHostsBox.Add_TextChanged({ & $updateSubnetRecommendations }.GetNewClosure())
        $wizardVoiceHostsBox.Add_TextChanged({ & $updateSubnetRecommendations }.GetNewClosure())
        $wizardMgmtHostsBox.Add_TextChanged({ & $updateSubnetRecommendations }.GetNewClosure())
        $wizardGuestHostsBox.Add_TextChanged({ & $updateSubnetRecommendations }.GetNewClosure())
        $wizardIoTHostsBox.Add_TextChanged({ & $updateSubnetRecommendations }.GetNewClosure())
        $wizardServerHostsBox.Add_TextChanged({ & $updateSubnetRecommendations }.GetNewClosure())

        # Event: Generate Plan button
        $wizardGenerateButton.Add_Click({
            param($sender, $e)

            $siteName = $wizardSiteNameBox.Text
            $supernetAddr = $wizardSupernetBox.Text

            if ([string]::IsNullOrWhiteSpace($siteName)) {
                $statusText.Text = 'Please enter a site name'
                return
            }
            if ([string]::IsNullOrWhiteSpace($supernetAddr)) {
                $statusText.Text = 'Please enter a supernet address'
                return
            }

            try {
                $prefixItem = $wizardPrefixCombo.SelectedItem
                $supernetPrefix = [int]$prefixItem.Content
                $growth = $wizardGrowthSlider.Value / 100.0

                # Build VLAN requirements hashtable
                $vlanReqs = @{}

                if ($wizardDataCheck.IsChecked) {
                    $hosts = 100; try { $hosts = [int]$wizardDataHostsBox.Text } catch {}
                    $vlanReqs['Data'] = @{ Hosts = $hosts; VlanNumber = 10 }
                }
                if ($wizardVoiceCheck.IsChecked) {
                    $hosts = 50; try { $hosts = [int]$wizardVoiceHostsBox.Text } catch {}
                    $vlanReqs['Voice'] = @{ Hosts = $hosts; VlanNumber = 20 }
                }
                if ($wizardMgmtCheck.IsChecked) {
                    $hosts = 20; try { $hosts = [int]$wizardMgmtHostsBox.Text } catch {}
                    $vlanReqs['Management'] = @{ Hosts = $hosts; VlanNumber = 100 }
                }
                if ($wizardGuestCheck.IsChecked) {
                    $hosts = 50; try { $hosts = [int]$wizardGuestHostsBox.Text } catch {}
                    $vlanReqs['Guest'] = @{ Hosts = $hosts; VlanNumber = 40 }
                }
                if ($wizardIoTCheck.IsChecked) {
                    $hosts = 30; try { $hosts = [int]$wizardIoTHostsBox.Text } catch {}
                    $vlanReqs['IoT'] = @{ Hosts = $hosts; VlanNumber = 50 }
                }
                if ($wizardServerCheck.IsChecked) {
                    $hosts = 20; try { $hosts = [int]$wizardServerHostsBox.Text } catch {}
                    $vlanReqs['Server'] = @{ Hosts = $hosts; VlanNumber = 30 }
                }

                if ($vlanReqs.Count -eq 0) {
                    $statusText.Text = 'Please select at least one VLAN type'
                    return
                }

                $db = $view.Tag.Database
                $plan = IPAMModule\New-SiteAddressPlan -SiteName $siteName `
                    -SupernetAddress $supernetAddr -SupernetPrefix $supernetPrefix `
                    -VLANRequirements $vlanReqs -GrowthFactor $growth -Database $db

                # Store plan for apply
                $view.Tag.WizardPlan = $plan

                # Build preview text
                $preview = [System.Text.StringBuilder]::new()
                [void]$preview.AppendLine("Site Address Plan: $siteName")
                [void]$preview.AppendLine("Supernet: $supernetAddr/$supernetPrefix")
                [void]$preview.AppendLine("Growth Factor: $([math]::Round($growth * 100))%")
                [void]$preview.AppendLine("")
                [void]$preview.AppendLine("Allocations:")
                [void]$preview.AppendLine("-" * 50)

                foreach ($alloc in $plan.Allocations) {
                    $line = "VLAN {0,3} ({1,-12}): {2}/{3}" -f $alloc.VlanNumber, $alloc.VLANType, $alloc.NetworkAddress, $alloc.PrefixLength
                    [void]$preview.AppendLine($line)
                    [void]$preview.AppendLine("  Gateway: $($alloc.GatewayAddress)")
                    [void]$preview.AppendLine("  Hosts:   $($alloc.TotalHosts) usable")
                    [void]$preview.AppendLine("")
                }

                $totalHosts = ($plan.Allocations | ForEach-Object { $_.TotalHosts } | Measure-Object -Sum).Sum
                [void]$preview.AppendLine("-" * 50)
                [void]$preview.AppendLine("Total VLANs: $($plan.Allocations.Count)")
                [void]$preview.AppendLine("Total Hosts: $totalHosts")

                $wizardPreviewBox.Text = $preview.ToString()
                $wizardPreviewPanel.Visibility = 'Visible'
                $wizardApplyButton.Visibility = 'Visible'
                $statusText.Text = 'Plan generated - review and click Apply to create VLANs and subnets'
            }
            catch {
                $statusText.Text = "Error generating plan: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Apply Plan button
        $wizardApplyButton.Add_Click({
            param($sender, $e)
            $plan = $view.Tag.WizardPlan
            if (-not $plan) {
                $statusText.Text = 'No plan to apply - generate a plan first'
                return
            }

            try {
                $db = $view.Tag.Database
                $siteName = $wizardSiteNameBox.Text
                $created = 0

                foreach ($alloc in $plan.Allocations) {
                    # Create VLAN
                    $vlan = IPAMModule\New-VLAN -VlanNumber $alloc.VlanNumber `
                        -VlanName "$siteName-$($alloc.VLANType)" `
                        -Purpose $alloc.VLANType -Site $siteName -Status 'Active'
                    IPAMModule\Add-VLAN -VLAN $vlan -Database $db -WarningAction SilentlyContinue | Out-Null

                    # Create Subnet
                    $subnet = IPAMModule\New-Subnet -NetworkAddress $alloc.NetworkAddress `
                        -PrefixLength $alloc.PrefixLength -VlanNumber $alloc.VlanNumber `
                        -Site $siteName -Purpose $alloc.VLANType `
                        -GatewayAddress $alloc.GatewayAddress -Status 'Active'
                    IPAMModule\Add-Subnet -Subnet $subnet -Database $db -WarningAction SilentlyContinue | Out-Null

                    $created++
                }

                & $saveDatabase
                & $refreshAll

                # Close wizard
                $wizardPanel.Visibility = 'Collapsed'
                $mainTabControl.Visibility = 'Visible'
                $view.Tag.WizardPlan = $null
                $statusText.Text = "Applied site plan for $siteName - created $created VLANs and subnets"
            }
            catch {
                $statusText.Text = "Error applying plan: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Cancel button
        $wizardCancelButton.Add_Click({
            param($sender, $e)
            $wizardPanel.Visibility = 'Collapsed'
            $mainTabControl.Visibility = 'Visible'
            $view.Tag.WizardPlan = $null
            $statusText.Text = 'Site planning cancelled'
        }.GetNewClosure())

        # Event: Site filter changed
        $siteFilterCombo.Add_SelectionChanged({
            param($sender, $e)
            & $refreshVlanGrid
            & $refreshSubnetGrid
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
                    & $saveDatabase
                    & $refreshAll
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
        & $refreshAll
        $statusText.Text = 'Ready'

        return $view

    } catch {
        Write-Warning "Failed to initialize IPAM view: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function New-IPAMView
