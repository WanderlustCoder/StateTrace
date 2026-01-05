#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    View module for the Inventory & Asset Tracking interface.

.DESCRIPTION
    Provides the view wiring for InventoryView.xaml, connecting UI controls
    to the InventoryModule functions for asset management, warranty tracking,
    firmware compliance, and lifecycle planning.

.NOTES
    Plan X - Inventory & Asset Tracking
#>

function New-InventoryView {
    <#
    .SYNOPSIS
        Creates and initializes the Inventory view.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Window]$Window,
        [Parameter(Mandatory=$true)][string]$ScriptDir
    )

    # Load XAML using ViewCompositionModule pattern
    $view = ViewCompositionModule\Set-StView -Window $Window -ScriptDir $ScriptDir `
        -ViewName 'InventoryView' -HostControlName 'InventoryHost' `
        -GlobalVariableName 'inventoryView'
    if (-not $view) {
        return $null
    }

    # Initialize controls
    Initialize-InventoryControls -View $view

    # Wire up event handlers
    Register-InventoryEventHandlers -View $view

    # Load initial data
    Update-InventoryView -View $view

    return $view
}

function Initialize-InventoryControls {
    <#
    .SYNOPSIS
        Initializes dropdown controls with default values.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    # Initialize vendor filter dropdown
    $vendorDropdown = $View.FindName('VendorFilterDropdown')
    if ($vendorDropdown) {
        $vendorDropdown.Items.Clear()
        [void]$vendorDropdown.Items.Add('All Vendors')
        [void]$vendorDropdown.Items.Add('Cisco')
        [void]$vendorDropdown.Items.Add('Arista')
        [void]$vendorDropdown.Items.Add('Ruckus')
        [void]$vendorDropdown.Items.Add('Brocade')
        [void]$vendorDropdown.Items.Add('Juniper')
        $vendorDropdown.SelectedIndex = 0
    }

    # Initialize status filter dropdown
    $statusDropdown = $View.FindName('StatusFilterDropdown')
    if ($statusDropdown) {
        $statusDropdown.Items.Clear()
        [void]$statusDropdown.Items.Add('All Status')
        [void]$statusDropdown.Items.Add('Active')
        [void]$statusDropdown.Items.Add('Spare')
        [void]$statusDropdown.Items.Add('RMA')
        [void]$statusDropdown.Items.Add('Decommissioned')
        [void]$statusDropdown.Items.Add('Staging')
        $statusDropdown.SelectedIndex = 0
    }

    # Initialize site filter dropdown from existing assets
    Update-SiteFilterDropdown -View $View
}

function Update-SiteFilterDropdown {
    <#
    .SYNOPSIS
        Updates the site filter dropdown with sites from the database.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    $siteDropdown = $View.FindName('SiteFilterDropdown')
    if (-not $siteDropdown) { return }

    $siteDropdown.Items.Clear()
    [void]$siteDropdown.Items.Add('All Sites')

    $assets = Get-Asset
    $sites = $assets | Where-Object { $_.Site } | Select-Object -ExpandProperty Site -Unique | Sort-Object
    foreach ($site in $sites) {
        [void]$siteDropdown.Items.Add($site)
    }

    $siteDropdown.SelectedIndex = 0
}

function Register-InventoryEventHandlers {
    <#
    .SYNOPSIS
        Registers event handlers for view controls.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    # Add Asset button
    $addButton = $View.FindName('AddAssetButton')
    if ($addButton) {
        $addButton.Add_Click({
            Show-AddAssetDialog -View $View
        }.GetNewClosure())
    }

    # Edit Asset button
    $editButton = $View.FindName('EditAssetButton')
    if ($editButton) {
        $editButton.Add_Click({
            $grid = $View.FindName('InventoryGrid')
            if ($grid -and $grid.SelectedItem) {
                Show-EditAssetDialog -View $View -Asset $grid.SelectedItem
            }
        }.GetNewClosure())
    }

    # Delete Asset button
    $deleteButton = $View.FindName('DeleteAssetButton')
    if ($deleteButton) {
        $deleteButton.Add_Click({
            $grid = $View.FindName('InventoryGrid')
            if ($grid -and $grid.SelectedItem) {
                $result = [System.Windows.MessageBox]::Show(
                    "Delete asset '$($grid.SelectedItem.Hostname)'?",
                    "Confirm Delete",
                    [System.Windows.MessageBoxButton]::YesNo,
                    [System.Windows.MessageBoxImage]::Question
                )
                if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                    Remove-Asset -AssetID $grid.SelectedItem.AssetID
                    Update-InventoryView -View $View
                    Update-StatusText -View $View -Text "Asset deleted: $($grid.SelectedItem.Hostname)"
                }
            }
        }.GetNewClosure())
    }

    # Filter dropdowns
    $vendorDropdown = $View.FindName('VendorFilterDropdown')
    if ($vendorDropdown) {
        $vendorDropdown.Add_SelectionChanged({
            Update-InventoryGrid -View $View
        }.GetNewClosure())
    }

    $siteDropdown = $View.FindName('SiteFilterDropdown')
    if ($siteDropdown) {
        $siteDropdown.Add_SelectionChanged({
            Update-InventoryGrid -View $View
        }.GetNewClosure())
    }

    $statusDropdown = $View.FindName('StatusFilterDropdown')
    if ($statusDropdown) {
        $statusDropdown.Add_SelectionChanged({
            Update-InventoryGrid -View $View
        }.GetNewClosure())
    }

    # Search box
    $searchBox = $View.FindName('SearchBox')
    if ($searchBox) {
        $searchBox.Add_TextChanged({
            Update-InventoryGrid -View $View
        }.GetNewClosure())
    }

    # Clear filter button
    $clearButton = $View.FindName('ClearFilterButton')
    if ($clearButton) {
        $clearButton.Add_Click({
            $View.FindName('VendorFilterDropdown').SelectedIndex = 0
            $View.FindName('SiteFilterDropdown').SelectedIndex = 0
            $View.FindName('StatusFilterDropdown').SelectedIndex = 0
            $View.FindName('SearchBox').Text = ''
            Update-InventoryGrid -View $View
        }.GetNewClosure())
    }

    # Import button
    $importButton = $View.FindName('ImportButton')
    if ($importButton) {
        $importButton.Add_Click({
            Import-InventoryFromCSV -View $View
        }.GetNewClosure())
    }

    # Export inventory button
    $exportButton = $View.FindName('ExportInventoryButton')
    if ($exportButton) {
        $exportButton.Add_Click({
            Export-InventoryToFile -View $View
        }.GetNewClosure())
    }

    # Export warranty report button
    $warrantyReportButton = $View.FindName('ExportWarrantyButton')
    if ($warrantyReportButton) {
        $warrantyReportButton.Add_Click({
            Export-WarrantyReportToFile -View $View
        }.GetNewClosure())
    }

    # Inventory grid selection changed
    $inventoryGrid = $View.FindName('InventoryGrid')
    if ($inventoryGrid) {
        $inventoryGrid.Add_SelectionChanged({
            $grid = $View.FindName('InventoryGrid')
            if ($grid.SelectedItem) {
                Update-AssetDetails -View $View -Asset $grid.SelectedItem
            }
        }.GetNewClosure())
    }

    # Alert period dropdown
    $alertPeriodDropdown = $View.FindName('AlertPeriodDropdown')
    if ($alertPeriodDropdown) {
        $alertPeriodDropdown.Add_SelectionChanged({
            Update-WarrantyAlerts -View $View
        }.GetNewClosure())
    }

    # Refresh alerts button
    $refreshAlertsButton = $View.FindName('RefreshAlertsButton')
    if ($refreshAlertsButton) {
        $refreshAlertsButton.Add_Click({
            Update-WarrantyAlerts -View $View
        }.GetNewClosure())
    }

    # Set minimum firmware button
    $setMinButton = $View.FindName('SetMinFirmwareButton')
    if ($setMinButton) {
        $setMinButton.Add_Click({
            Show-SetMinimumFirmwareDialog -View $View
        }.GetNewClosure())
    }

    # Check compliance button
    $checkComplianceButton = $View.FindName('CheckComplianceButton')
    if ($checkComplianceButton) {
        $checkComplianceButton.Add_Click({
            Update-FirmwareTab -View $View
            Update-StatusText -View $View -Text "Firmware compliance check completed"
        }.GetNewClosure())
    }

    # EoL period dropdown
    $eolPeriodDropdown = $View.FindName('EoLPeriodDropdown')
    if ($eolPeriodDropdown) {
        $eolPeriodDropdown.Add_SelectionChanged({
            Update-LifecycleTab -View $View
        }.GetNewClosure())
    }

    # Refresh lifecycle button
    $refreshLifecycleButton = $View.FindName('RefreshLifecycleButton')
    if ($refreshLifecycleButton) {
        $refreshLifecycleButton.Add_Click({
            Update-LifecycleTab -View $View
        }.GetNewClosure())
    }

    # History asset dropdown
    $historyAssetDropdown = $View.FindName('HistoryAssetDropdown')
    if ($historyAssetDropdown) {
        # Populate with asset hostnames
        $assets = Get-Asset
        foreach ($asset in $assets) {
            [void]$historyAssetDropdown.Items.Add($asset.Hostname)
        }
    }

    # Refresh history button
    $refreshHistoryButton = $View.FindName('RefreshHistoryButton')
    if ($refreshHistoryButton) {
        $refreshHistoryButton.Add_Click({
            $dropdown = $View.FindName('HistoryAssetDropdown')
            if ($dropdown -and $dropdown.SelectedItem) {
                $asset = Get-Asset -Hostname $dropdown.SelectedItem
                if ($asset) {
                    $history = Get-AssetHistory -AssetID $asset.AssetID
                    $historyGrid = $View.FindName('HistoryGrid')
                    if ($historyGrid) {
                        $historyGrid.ItemsSource = @($history)
                    }
                }
            }
        }.GetNewClosure())
    }

    # Show all history button
    $showAllHistoryButton = $View.FindName('ShowAllHistoryButton')
    if ($showAllHistoryButton) {
        $showAllHistoryButton.Add_Click({
            $history = Get-AssetHistory
            $historyGrid = $View.FindName('HistoryGrid')
            if ($historyGrid) {
                $historyGrid.ItemsSource = @($history)
            }
        }.GetNewClosure())
    }
}

function Update-InventoryView {
    <#
    .SYNOPSIS
        Updates all view components with current data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    # Update summary cards
    Update-SummaryCards -View $View

    # Update inventory grid
    Update-InventoryGrid -View $View

    # Update warranty alerts
    Update-WarrantyAlerts -View $View

    # Update firmware tab
    Update-FirmwareTab -View $View

    # Update lifecycle tab
    Update-LifecycleTab -View $View

    # Update site filter dropdown
    Update-SiteFilterDropdown -View $View

    # Update last update text
    $lastUpdateText = $View.FindName('LastUpdateText')
    if ($lastUpdateText) {
        $lastUpdateText.Text = "Last updated: $(Get-Date -Format 'HH:mm:ss')"
    }
}

function Update-SummaryCards {
    <#
    .SYNOPSIS
        Updates the summary cards at the top of the view.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    $summary = Get-InventorySummary
    $warrantySummary = Get-WarrantySummary
    $firmwareSummary = Get-FirmwareComplianceSummary

    # Total devices
    $totalCount = $View.FindName('TotalDevicesCount')
    if ($totalCount) {
        $totalCount.Text = $summary.TotalDevices.ToString()
    }

    # Active warranties
    $activeCount = $View.FindName('ActiveWarrantiesCount')
    if ($activeCount) {
        $activeCount.Text = $warrantySummary.Active.ToString()
    }

    # Expiring
    $expiringCount = $View.FindName('ExpiringCount')
    if ($expiringCount) {
        $expiringCount.Text = $warrantySummary.Expiring90Days.ToString()
    }

    # Expired
    $expiredCount = $View.FindName('ExpiredCount')
    if ($expiredCount) {
        $expiredCount.Text = $warrantySummary.Expired.ToString()
    }

    # Firmware compliance
    $fwCompliance = $View.FindName('FirmwareComplianceStatus')
    if ($fwCompliance) {
        $fwCompliance.Text = "$($firmwareSummary.CompliancePercent)%"
    }
}

function Update-InventoryGrid {
    <#
    .SYNOPSIS
        Updates the inventory grid with filtered data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    $assets = Get-Asset

    # Apply filters
    $vendorDropdown = $View.FindName('VendorFilterDropdown')
    if ($vendorDropdown -and $vendorDropdown.SelectedItem -and $vendorDropdown.SelectedItem -ne 'All Vendors') {
        $assets = $assets | Where-Object { $_.Vendor -eq $vendorDropdown.SelectedItem }
    }

    $siteDropdown = $View.FindName('SiteFilterDropdown')
    if ($siteDropdown -and $siteDropdown.SelectedItem -and $siteDropdown.SelectedItem -ne 'All Sites') {
        $assets = $assets | Where-Object { $_.Site -eq $siteDropdown.SelectedItem }
    }

    $statusDropdown = $View.FindName('StatusFilterDropdown')
    if ($statusDropdown -and $statusDropdown.SelectedItem -and $statusDropdown.SelectedItem -ne 'All Status') {
        $assets = $assets | Where-Object { $_.Status -eq $statusDropdown.SelectedItem }
    }

    $searchBox = $View.FindName('SearchBox')
    if ($searchBox -and $searchBox.Text) {
        $searchText = $searchBox.Text
        $assets = $assets | Where-Object {
            $_.Hostname -like "*$searchText*" -or
            $_.SerialNumber -like "*$searchText*" -or
            $_.AssetTag -like "*$searchText*"
        }
    }

    $grid = $View.FindName('InventoryGrid')
    if ($grid) {
        $grid.ItemsSource = @($assets)
    }
}

function Update-AssetDetails {
    <#
    .SYNOPSIS
        Updates the asset details panel with selected asset information.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View,

        [Parameter(Mandatory)]
        $Asset
    )

    # Device info
    $View.FindName('DetailHostname').Text = $Asset.Hostname
    $View.FindName('DetailVendor').Text = $Asset.Vendor
    $View.FindName('DetailModel').Text = $Asset.Model
    $View.FindName('DetailSerial').Text = $Asset.SerialNumber
    $View.FindName('DetailAssetTag').Text = $Asset.AssetTag
    $View.FindName('DetailFirmware').Text = $Asset.FirmwareVersion
    $View.FindName('DetailStatus').Text = $Asset.Status

    # Location
    $View.FindName('DetailSite').Text = $Asset.Site
    $View.FindName('DetailBuilding').Text = $Asset.Building
    $View.FindName('DetailRack').Text = $Asset.Rack
    $View.FindName('DetailRackU').Text = if ($Asset.RackU) { $Asset.RackU.ToString() } else { '' }

    # Warranty
    $View.FindName('DetailWarrantyExpires').Text = if ($Asset.WarrantyExpiration) { $Asset.WarrantyExpiration.ToString('yyyy-MM-dd') } else { 'N/A' }
    $View.FindName('DetailDaysLeft').Text = if ($null -ne $Asset.DaysUntilExpiration) { $Asset.DaysUntilExpiration.ToString() } else { 'N/A' }
    $View.FindName('DetailContract').Text = $Asset.SupportContract
    $View.FindName('DetailSupportLevel').Text = $Asset.SupportLevel

    # Modules
    $modulesListBox = $View.FindName('ModulesListBox')
    if ($modulesListBox) {
        $modulesListBox.Items.Clear()
        $modules = Get-AssetModule -AssetID $Asset.AssetID
        foreach ($module in $modules) {
            [void]$modulesListBox.Items.Add("$($module.ModuleType): $($module.PartNumber) ($($module.SlotPosition))")
        }
    }

    # Notes
    $View.FindName('DetailNotes').Text = $Asset.Notes
}

function Update-WarrantyAlerts {
    <#
    .SYNOPSIS
        Updates the warranty alerts tab.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    # Get alert period
    $alertDropdown = $View.FindName('AlertPeriodDropdown')
    $daysAhead = 90
    if ($alertDropdown -and $alertDropdown.SelectedItem) {
        $content = $alertDropdown.SelectedItem.Content
        if ($content -match '(\d+)') {
            $daysAhead = [int]$Matches[1]
        }
    }

    # Update expiring grid
    $expiringGrid = $View.FindName('ExpiringWarrantiesGrid')
    if ($expiringGrid) {
        $expiring = Get-ExpiringWarranties -DaysAhead $daysAhead
        $expiringGrid.ItemsSource = @($expiring)
    }

    # Update expired grid
    $expiredGrid = $View.FindName('ExpiredWarrantiesGrid')
    if ($expiredGrid) {
        $expired = Get-ExpiredWarranties
        $expiredGrid.ItemsSource = @($expired)
    }
}

function Update-FirmwareTab {
    <#
    .SYNOPSIS
        Updates the firmware compliance tab.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    # Update below minimum grid
    $belowMinGrid = $View.FindName('BelowMinimumGrid')
    if ($belowMinGrid) {
        $belowMin = Get-DevicesBelowMinimumFirmware
        $belowMinGrid.ItemsSource = @($belowMin)
    }

    # Update vulnerable devices grid
    $vulnerableGrid = $View.FindName('VulnerableDevicesGrid')
    if ($vulnerableGrid) {
        $vulnerable = Get-VulnerableDevices
        $vulnerableGrid.ItemsSource = @($vulnerable)
    }

    # Update requirements grid
    # Note: We need to access the internal requirements list
    # For now, this would require exposing a function from InventoryModule
}

function Update-LifecycleTab {
    <#
    .SYNOPSIS
        Updates the lifecycle planning tab.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    # Get EoL period
    $eolDropdown = $View.FindName('EoLPeriodDropdown')
    $daysAhead = 730 # 2 years default
    if ($eolDropdown -and $eolDropdown.SelectedItem) {
        $content = $eolDropdown.SelectedItem.Content
        if ($content -match '(\d+)') {
            $years = [int]$Matches[1]
            $daysAhead = $years * 365
        }
    }

    # Update EoL devices grid
    $eolGrid = $View.FindName('EoLDevicesGrid')
    if ($eolGrid) {
        $approaching = Get-DevicesApproachingEoL -DaysAhead $daysAhead
        $eolGrid.ItemsSource = @($approaching)
    }

    # Update lifecycle database grid
    $lifecycleGrid = $View.FindName('LifecycleDatabaseGrid')
    if ($lifecycleGrid) {
        $lifecycle = Get-LifecycleInfo
        $lifecycleGrid.ItemsSource = @($lifecycle)
    }
}

function Update-StatusText {
    <#
    .SYNOPSIS
        Updates the status bar text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View,

        [Parameter(Mandatory)]
        [string]$Text
    )

    $statusText = $View.FindName('StatusText')
    if ($statusText) {
        $statusText.Text = $Text
    }
}

function Show-AddAssetDialog {
    <#
    .SYNOPSIS
        Shows a dialog to add a new asset.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    # Simple input dialog using MessageBox for now
    # In production, this would be a proper dialog window

    $hostname = Read-HostDialog -Title "Add Asset" -Prompt "Enter hostname:"
    if (-not $hostname) { return }

    $vendor = Read-HostDialog -Title "Add Asset" -Prompt "Enter vendor (Cisco/Arista/Ruckus):"
    $model = Read-HostDialog -Title "Add Asset" -Prompt "Enter model:"
    $serial = Read-HostDialog -Title "Add Asset" -Prompt "Enter serial number:"
    $site = Read-HostDialog -Title "Add Asset" -Prompt "Enter site:"

    try {
        $params = @{ Hostname = $hostname }
        if ($vendor) { $params.Vendor = $vendor }
        if ($model) { $params.Model = $model }
        if ($serial) { $params.SerialNumber = $serial }
        if ($site) { $params.Site = $site }

        $asset = New-Asset @params
        Update-InventoryView -View $View
        Update-StatusText -View $View -Text "Asset added: $hostname"
    }
    catch {
        [System.Windows.MessageBox]::Show(
            "Failed to add asset: $($_.Exception.Message)",
            "Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}

function Show-EditAssetDialog {
    <#
    .SYNOPSIS
        Shows a dialog to edit an existing asset.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View,

        [Parameter(Mandatory)]
        $Asset
    )

    # Simple status change dialog for now
    $statusOptions = @('Active', 'Spare', 'RMA', 'Decommissioned', 'Staging')
    $currentIndex = $statusOptions.IndexOf($Asset.Status)
    if ($currentIndex -lt 0) { $currentIndex = 0 }

    $newStatus = Read-HostDialog -Title "Change Status" -Prompt "Enter new status (Active/Spare/RMA/Decommissioned/Staging):" -Default $Asset.Status

    if ($newStatus -and $statusOptions -contains $newStatus) {
        try {
            Set-AssetStatus -AssetID $Asset.AssetID -Status $newStatus
            Update-InventoryView -View $View
            Update-StatusText -View $View -Text "Asset status updated: $($Asset.Hostname)"
        }
        catch {
            [System.Windows.MessageBox]::Show(
                "Failed to update asset: $($_.Exception.Message)",
                "Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
        }
    }
}

function Show-SetMinimumFirmwareDialog {
    <#
    .SYNOPSIS
        Shows a dialog to set minimum firmware requirements.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    $vendor = Read-HostDialog -Title "Set Minimum Firmware" -Prompt "Enter vendor (Cisco/Arista/Ruckus):"
    if (-not $vendor) { return }

    $platform = Read-HostDialog -Title "Set Minimum Firmware" -Prompt "Enter platform (e.g., C9300):"
    if (-not $platform) { return }

    $minVersion = Read-HostDialog -Title "Set Minimum Firmware" -Prompt "Enter minimum version (e.g., 17.06.03):"
    if (-not $minVersion) { return }

    $reason = Read-HostDialog -Title "Set Minimum Firmware" -Prompt "Enter reason:"

    try {
        Set-MinimumFirmware -Vendor $vendor -Platform $platform -MinVersion $minVersion -Reason $reason
        Update-FirmwareTab -View $View
        Update-StatusText -View $View -Text "Minimum firmware set for $vendor $platform"
    }
    catch {
        [System.Windows.MessageBox]::Show(
            "Failed to set minimum firmware: $($_.Exception.Message)",
            "Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}

function Read-HostDialog {
    <#
    .SYNOPSIS
        Simple input dialog wrapper.
    #>
    [CmdletBinding()]
    param(
        [string]$Title = "Input",
        [string]$Prompt = "Enter value:",
        [string]$Default = ""
    )

    # Use InputBox from Microsoft.VisualBasic if available
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic
        return [Microsoft.VisualBasic.Interaction]::InputBox($Prompt, $Title, $Default)
    }
    catch {
        # Fallback - return empty (dialog not available)
        return $null
    }
}

function Import-InventoryFromCSV {
    <#
    .SYNOPSIS
        Shows file dialog and imports inventory from CSV.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
    $dialog.Title = "Select Inventory CSV File"

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $result = Import-AssetInventory -Path $dialog.FileName
            Update-InventoryView -View $View

            [System.Windows.MessageBox]::Show(
                "Imported $($result.ImportedCount) of $($result.TotalRows) assets.`nErrors: $($result.Errors.Count)",
                "Import Complete",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            )

            Update-StatusText -View $View -Text "Imported $($result.ImportedCount) assets"
        }
        catch {
            [System.Windows.MessageBox]::Show(
                "Failed to import: $($_.Exception.Message)",
                "Import Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
        }
    }
}

function Export-InventoryToFile {
    <#
    .SYNOPSIS
        Shows file dialog and exports inventory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = "CSV files (*.csv)|*.csv|JSON files (*.json)|*.json"
    $dialog.Title = "Export Inventory"
    $dialog.FileName = "Inventory_$(Get-Date -Format 'yyyyMMdd')"

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $format = 'CSV'
            if ($dialog.FileName -like '*.json') {
                $format = 'JSON'
            }

            $result = Export-AssetInventory -Path $dialog.FileName -Format $format
            Update-StatusText -View $View -Text "Exported $($result.ExportedCount) assets to $($result.Path)"

            [System.Windows.MessageBox]::Show(
                "Exported $($result.ExportedCount) assets",
                "Export Complete",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            )
        }
        catch {
            [System.Windows.MessageBox]::Show(
                "Failed to export: $($_.Exception.Message)",
                "Export Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
        }
    }
}

function Export-WarrantyReportToFile {
    <#
    .SYNOPSIS
        Shows folder dialog and exports warranty report.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select folder for warranty report"

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $result = Export-WarrantyReport -Format 'HTML' -OutputPath $dialog.SelectedPath -ExpiringWithin 90
            Update-StatusText -View $View -Text "Warranty report saved to $($result.Path)"

            [System.Windows.MessageBox]::Show(
                "Report saved to:`n$($result.Path)",
                "Report Generated",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            )

            # Open the report
            Start-Process $result.Path
        }
        catch {
            [System.Windows.MessageBox]::Show(
                "Failed to generate report: $($_.Exception.Message)",
                "Report Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
        }
    }
}

# Export functions
Export-ModuleMember -Function @(
    'New-InventoryView'
    'Update-InventoryView'
    'Update-SummaryCards'
    'Update-InventoryGrid'
    'Update-WarrantyAlerts'
    'Update-FirmwareTab'
    'Update-LifecycleTab'
)
