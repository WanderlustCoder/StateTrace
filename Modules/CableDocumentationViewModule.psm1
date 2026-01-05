Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Creates and initializes the Cable Documentation view.

.DESCRIPTION
    Loads CableDocumentationView.xaml using ViewCompositionModule, wires up event handlers,
    and provides cable/patch panel management functionality.
    Part of Plan T - Cable & Port Documentation.

.PARAMETER Window
    The parent MainWindow instance.

.PARAMETER ScriptDir
    The root script directory for locating XAML files.

.OUTPUTS
    System.Windows.Controls.UserControl - The initialized view.
#>
function New-CableDocumentationView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory=$true)]
        [string]$ScriptDir
    )

    try {
        $view = ViewCompositionModule\Set-StView -Window $Window -ScriptDir $ScriptDir `
            -ViewName 'CableDocumentationView' -HostControlName 'CableDocumentationHost' `
            -GlobalVariableName 'cableDocumentationView'
        if (-not $view) { return }

        # Get controls from the view
        $addCableButton = $view.FindName('AddCableButton')
        $addPanelButton = $view.FindName('AddPanelButton')
        $importButton = $view.FindName('ImportButton')
        $exportButton = $view.FindName('ExportButton')
        $importCsvButton = $view.FindName('ImportCsvButton')
        $generateLabelsButton = $view.FindName('GenerateLabelsButton')
        $filterBox = $view.FindName('FilterBox')
        $clearFilterButton = $view.FindName('ClearFilterButton')

        $cableListBox = $view.FindName('CableListBox')
        $panelListBox = $view.FindName('PanelListBox')
        $cableCountLabel = $view.FindName('CableCountLabel')
        $panelCountLabel = $view.FindName('PanelCountLabel')

        $detailsTitleLabel = $view.FindName('DetailsTitleLabel')
        $detailsTabControl = $view.FindName('DetailsTabControl')
        $cableDetailsTab = $view.FindName('CableDetailsTab')
        $panelDetailsTab = $view.FindName('PanelDetailsTab')
        $cableDetailsGrid = $view.FindName('CableDetailsGrid')
        $panelDetailsGrid = $view.FindName('PanelDetailsGrid')

        # Cable detail controls
        $cableIdBox = $view.FindName('CableIdBox')
        $sourceTypeCombo = $view.FindName('SourceTypeCombo')
        $sourceDeviceBox = $view.FindName('SourceDeviceBox')
        $sourcePortBox = $view.FindName('SourcePortBox')
        $destTypeCombo = $view.FindName('DestTypeCombo')
        $destDeviceBox = $view.FindName('DestDeviceBox')
        $destPortBox = $view.FindName('DestPortBox')
        $cableTypeCombo = $view.FindName('CableTypeCombo')
        $lengthBox = $view.FindName('LengthBox')
        $colorBox = $view.FindName('ColorBox')
        $statusCombo = $view.FindName('StatusCombo')
        $notesBox = $view.FindName('NotesBox')
        $saveCableButton = $view.FindName('SaveCableButton')
        $deleteCableButton = $view.FindName('DeleteCableButton')
        $cableLabelButton = $view.FindName('CableLabelButton')
        $cableCreatedText = $view.FindName('CableCreatedText')
        $cableModifiedText = $view.FindName('CableModifiedText')

        # Panel detail controls
        $panelIdBox = $view.FindName('PanelIdBox')
        $panelNameBox = $view.FindName('PanelNameBox')
        $panelLocationBox = $view.FindName('PanelLocationBox')
        $panelRackIdBox = $view.FindName('PanelRackIdBox')
        $panelRackUBox = $view.FindName('PanelRackUBox')
        $panelPortCountText = $view.FindName('PanelPortCountText')
        $savePanelButton = $view.FindName('SavePanelButton')
        $deletePanelButton = $view.FindName('DeletePanelButton')
        $panelLabelsButton = $view.FindName('PanelLabelsButton')
        $portGrid = $view.FindName('PortGrid')
        $portUtilizationLabel = $view.FindName('PortUtilizationLabel')

        # Stats controls
        $totalCablesText = $view.FindName('TotalCablesText')
        $activeCablesText = $view.FindName('ActiveCablesText')
        $reservedCablesText = $view.FindName('ReservedCablesText')
        $faultyCablesText = $view.FindName('FaultyCablesText')
        $plannedCablesText = $view.FindName('PlannedCablesText')
        $totalPanelsText = $view.FindName('TotalPanelsText')
        $totalPortsText = $view.FindName('TotalPortsText')
        $usedPortsText = $view.FindName('UsedPortsText')
        $availablePortsText = $view.FindName('AvailablePortsText')
        $cableTypesItemsControl = $view.FindName('CableTypesItemsControl')

        $statusText = $view.FindName('StatusText')

        # Initialize database from settings or create new
        $dataPath = Join-Path $ScriptDir 'Data\CableDatabase.json'
        $script:cableDb = CableDocumentationModule\New-CableDatabase

        # Try to load existing data
        if (Test-Path $dataPath) {
            try {
                CableDocumentationModule\Import-CableDatabase -Path $dataPath -Database $script:cableDb | Out-Null
                $statusText.Text = "Loaded database from $dataPath"
            }
            catch {
                $statusText.Text = "Error loading database: $($_.Exception.Message)"
            }
        }

        # Store state in view's Tag
        $view.Tag = @{
            Database = $script:cableDb
            DataPath = $dataPath
            IsNewCable = $false
            IsNewPanel = $false
            SelectedCable = $null
            SelectedPanel = $null
        }

        # Helper: Refresh lists
        function Refresh-Lists {
            $filter = $filterBox.Text
            $db = $view.Tag.Database

            # Get all cables and panels
            $cables = @(CableDocumentationModule\Get-CableRun -Database $db)
            $panels = @(CableDocumentationModule\Get-PatchPanel -Database $db)

            # Apply filter
            if (-not [string]::IsNullOrWhiteSpace($filter)) {
                $cables = @($cables | Where-Object {
                    $_.CableID -like "*$filter*" -or
                    $_.SourceDevice -like "*$filter*" -or
                    $_.DestDevice -like "*$filter*" -or
                    $_.Notes -like "*$filter*"
                })
                $panels = @($panels | Where-Object {
                    $_.PanelID -like "*$filter*" -or
                    $_.PanelName -like "*$filter*" -or
                    $_.Location -like "*$filter*"
                })
            }

            $cableListBox.ItemsSource = $cables
            $panelListBox.ItemsSource = $panels
            $cableCountLabel.Content = "($($cables.Count))"
            $panelCountLabel.Content = "($($panels.Count))"

            # Update stats
            Update-Stats
        }

        # Helper: Update statistics
        function Update-Stats {
            $db = $view.Tag.Database
            $stats = CableDocumentationModule\Get-CableDatabaseStats -Database $db

            $totalCablesText.Text = "Total Cables: $($stats.TotalCables)"

            $active = if ($stats.CablesByStatus['Active']) { $stats.CablesByStatus['Active'] } else { 0 }
            $reserved = if ($stats.CablesByStatus['Reserved']) { $stats.CablesByStatus['Reserved'] } else { 0 }
            $faulty = if ($stats.CablesByStatus['Faulty']) { $stats.CablesByStatus['Faulty'] } else { 0 }
            $planned = if ($stats.CablesByStatus['Planned']) { $stats.CablesByStatus['Planned'] } else { 0 }

            $activeCablesText.Text = "Active: $active"
            $reservedCablesText.Text = "Reserved: $reserved"
            $faultyCablesText.Text = "Faulty: $faulty"
            $plannedCablesText.Text = "Planned: $planned"

            $totalPanelsText.Text = "Total Panels: $($stats.TotalPatchPanels)"
            $totalPortsText.Text = "Total Ports: $($stats.TotalPanelPorts)"
            $usedPortsText.Text = "Used Ports: $($stats.UsedPanelPorts)"
            $availablePortsText.Text = "Available: $($stats.AvailablePorts)"

            # Cable types
            $typesList = @()
            foreach ($key in $stats.CablesByType.Keys) {
                $typesList += [PSCustomObject]@{ Key = $key; Value = $stats.CablesByType[$key] }
            }
            $cableTypesItemsControl.ItemsSource = $typesList
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
                CableDocumentationModule\Export-CableDatabase -Path $dataPath -Database $db
                $statusText.Text = "Saved to $dataPath"
            }
            catch {
                $statusText.Text = "Error saving: $($_.Exception.Message)"
            }
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

        # Helper: Get selected combo content
        function Get-ComboValue {
            param($Combo)
            if ($Combo.SelectedItem) {
                return $Combo.SelectedItem.Content
            }
            return $null
        }

        # Helper: Show cable details
        function Show-CableDetails {
            param($Cable)
            $view.Tag.SelectedCable = $Cable
            $view.Tag.IsNewCable = ($Cable -eq $null)

            $cableDetailsGrid.Visibility = 'Visible'
            $panelDetailsGrid.Visibility = 'Collapsed'
            $detailsTabControl.SelectedItem = $cableDetailsTab

            if ($Cable) {
                $detailsTitleLabel.Content = "Cable: $($Cable.CableID)"
                $cableIdBox.Text = $Cable.CableID
                Select-ComboItem -Combo $sourceTypeCombo -Value $Cable.SourceType
                $sourceDeviceBox.Text = $Cable.SourceDevice
                $sourcePortBox.Text = $Cable.SourcePort
                Select-ComboItem -Combo $destTypeCombo -Value $Cable.DestType
                $destDeviceBox.Text = $Cable.DestDevice
                $destPortBox.Text = $Cable.DestPort
                Select-ComboItem -Combo $cableTypeCombo -Value $Cable.CableType
                $lengthBox.Text = $Cable.Length
                $colorBox.Text = $Cable.Color
                Select-ComboItem -Combo $statusCombo -Value $Cable.Status
                $notesBox.Text = $Cable.Notes
                if ($Cable.CreatedDate) {
                    $cableCreatedText.Text = $Cable.CreatedDate.ToString('yyyy-MM-dd HH:mm')
                }
                if ($Cable.ModifiedDate) {
                    $cableModifiedText.Text = $Cable.ModifiedDate.ToString('yyyy-MM-dd HH:mm')
                }
            }
            else {
                # New cable
                $detailsTitleLabel.Content = "New Cable"
                $cableIdBox.Text = ''
                $sourceTypeCombo.SelectedIndex = 0
                $sourceDeviceBox.Text = ''
                $sourcePortBox.Text = ''
                $destTypeCombo.SelectedIndex = 0
                $destDeviceBox.Text = ''
                $destPortBox.Text = ''
                $cableTypeCombo.SelectedIndex = 1
                $lengthBox.Text = ''
                $colorBox.Text = ''
                $statusCombo.SelectedIndex = 0
                $notesBox.Text = ''
                $cableCreatedText.Text = ''
                $cableModifiedText.Text = ''
            }
        }

        # Helper: Show panel details
        function Show-PanelDetails {
            param($Panel)
            $view.Tag.SelectedPanel = $Panel
            $view.Tag.IsNewPanel = ($Panel -eq $null)

            $cableDetailsGrid.Visibility = 'Collapsed'
            $panelDetailsGrid.Visibility = 'Visible'
            $detailsTabControl.SelectedItem = $panelDetailsTab

            if ($Panel) {
                $detailsTitleLabel.Content = "Panel: $($Panel.PanelName)"
                $panelIdBox.Text = $Panel.PanelID
                $panelNameBox.Text = $Panel.PanelName
                $panelLocationBox.Text = $Panel.Location
                $panelRackIdBox.Text = $Panel.RackID
                $panelRackUBox.Text = $Panel.RackU
                $panelPortCountText.Text = "$($Panel.PortCount) ports"

                # Build port display items
                $portItems = @()
                $usedCount = 0
                foreach ($port in $Panel.Ports) {
                    $tooltip = "Port $($port.PortNumber)"
                    if ($port.Label) { $tooltip += ": $($port.Label)" }
                    if ($port.CableID) { $tooltip += " [Cable: $($port.CableID)]" }
                    $tooltip += " - $($port.Status)"

                    $portItems += [PSCustomObject]@{
                        PortNumber = $port.PortNumber
                        Label = $port.Label
                        Status = $port.Status
                        CableID = $port.CableID
                        ToolTip = $tooltip
                    }
                    if ($port.Status -eq 'Connected' -or $port.CableID) { $usedCount++ }
                }
                $portGrid.ItemsSource = $portItems
                $portUtilizationLabel.Content = "($usedCount/$($Panel.PortCount) used)"
            }
            else {
                # New panel
                $detailsTitleLabel.Content = "New Patch Panel"
                $panelIdBox.Text = ''
                $panelNameBox.Text = ''
                $panelLocationBox.Text = ''
                $panelRackIdBox.Text = ''
                $panelRackUBox.Text = ''
                $panelPortCountText.Text = '24 ports (default)'
                $portGrid.ItemsSource = @()
                $portUtilizationLabel.Content = '(0/24 used)'
            }
        }

        # Event: Add Cable button
        $addCableButton.Add_Click({
            param($sender, $e)
            Show-CableDetails -Cable $null
            $cableListBox.SelectedItem = $null
            $panelListBox.SelectedItem = $null
        }.GetNewClosure())

        # Event: Add Panel button
        $addPanelButton.Add_Click({
            param($sender, $e)
            Show-PanelDetails -Panel $null
            $cableListBox.SelectedItem = $null
            $panelListBox.SelectedItem = $null
        }.GetNewClosure())

        # Event: Cable list selection
        $cableListBox.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if ($selected) {
                $panelListBox.SelectedItem = $null
                Show-CableDetails -Cable $selected
            }
        }.GetNewClosure())

        # Event: Panel list selection
        $panelListBox.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if ($selected) {
                $cableListBox.SelectedItem = $null
                Show-PanelDetails -Panel $selected
            }
        }.GetNewClosure())

        # Event: Save Cable
        $saveCableButton.Add_Click({
            param($sender, $e)
            $db = $view.Tag.Database

            $sourceType = Get-ComboValue -Combo $sourceTypeCombo
            $destType = Get-ComboValue -Combo $destTypeCombo
            $cableType = Get-ComboValue -Combo $cableTypeCombo
            $status = Get-ComboValue -Combo $statusCombo

            if ([string]::IsNullOrWhiteSpace($sourceDeviceBox.Text) -or
                [string]::IsNullOrWhiteSpace($sourcePortBox.Text) -or
                [string]::IsNullOrWhiteSpace($destDeviceBox.Text) -or
                [string]::IsNullOrWhiteSpace($destPortBox.Text)) {
                $statusText.Text = 'Please fill in all required fields'
                return
            }

            try {
                if ($view.Tag.IsNewCable) {
                    # Create new cable
                    $params = @{
                        SourceType = $sourceType
                        SourceDevice = $sourceDeviceBox.Text
                        SourcePort = $sourcePortBox.Text
                        DestType = $destType
                        DestDevice = $destDeviceBox.Text
                        DestPort = $destPortBox.Text
                        CableType = $cableType
                        Status = $status
                    }
                    if ($cableIdBox.Text) { $params['CableID'] = $cableIdBox.Text }
                    if ($lengthBox.Text) { $params['Length'] = $lengthBox.Text }
                    if ($colorBox.Text) { $params['Color'] = $colorBox.Text }
                    if ($notesBox.Text) { $params['Notes'] = $notesBox.Text }

                    $cable = CableDocumentationModule\New-CableRun @params
                    CableDocumentationModule\Add-CableRun -Cable $cable -Database $db | Out-Null
                    $statusText.Text = "Created cable $($cable.CableID)"
                }
                else {
                    # Update existing cable
                    $props = @{
                        SourceType = $sourceType
                        SourceDevice = $sourceDeviceBox.Text
                        SourcePort = $sourcePortBox.Text
                        DestType = $destType
                        DestDevice = $destDeviceBox.Text
                        DestPort = $destPortBox.Text
                        CableType = $cableType
                        Length = $lengthBox.Text
                        Color = $colorBox.Text
                        Status = $status
                        Notes = $notesBox.Text
                    }
                    CableDocumentationModule\Update-CableRun -CableID $cableIdBox.Text -Properties $props -Database $db | Out-Null
                    $statusText.Text = "Updated cable $($cableIdBox.Text)"
                }

                Save-Database
                Refresh-Lists
            }
            catch {
                $statusText.Text = "Error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Delete Cable
        $deleteCableButton.Add_Click({
            param($sender, $e)
            $cable = $view.Tag.SelectedCable
            if (-not $cable) { return }

            $result = [System.Windows.MessageBox]::Show(
                "Delete cable $($cable.CableID)?",
                "Confirm Delete",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning)

            if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                $db = $view.Tag.Database
                CableDocumentationModule\Remove-CableRun -CableID $cable.CableID -Database $db | Out-Null
                $cableDetailsGrid.Visibility = 'Collapsed'
                $detailsTitleLabel.Content = 'Select an item'
                $statusText.Text = "Deleted cable $($cable.CableID)"
                Save-Database
                Refresh-Lists
            }
        }.GetNewClosure())

        # Event: Save Panel
        $savePanelButton.Add_Click({
            param($sender, $e)
            $db = $view.Tag.Database

            if ([string]::IsNullOrWhiteSpace($panelNameBox.Text)) {
                $statusText.Text = 'Please enter a panel name'
                return
            }

            try {
                if ($view.Tag.IsNewPanel) {
                    # Create new panel
                    $params = @{
                        PanelName = $panelNameBox.Text
                    }
                    if ($panelIdBox.Text) { $params['PanelID'] = $panelIdBox.Text }
                    if ($panelLocationBox.Text) { $params['Location'] = $panelLocationBox.Text }
                    if ($panelRackIdBox.Text) { $params['RackID'] = $panelRackIdBox.Text }
                    if ($panelRackUBox.Text) { $params['RackU'] = $panelRackUBox.Text }

                    $panel = CableDocumentationModule\New-PatchPanel @params
                    CableDocumentationModule\Add-PatchPanel -Panel $panel -Database $db | Out-Null
                    $statusText.Text = "Created panel $($panel.PanelName)"
                }
                else {
                    # Update existing panel - update properties directly
                    $panel = $view.Tag.SelectedPanel
                    $panel.PanelName = $panelNameBox.Text
                    $panel.Location = $panelLocationBox.Text
                    $panel.RackID = $panelRackIdBox.Text
                    $panel.RackU = $panelRackUBox.Text
                    $panel.ModifiedDate = Get-Date
                    $statusText.Text = "Updated panel $($panel.PanelName)"
                }

                Save-Database
                Refresh-Lists
            }
            catch {
                $statusText.Text = "Error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Delete Panel
        $deletePanelButton.Add_Click({
            param($sender, $e)
            $panel = $view.Tag.SelectedPanel
            if (-not $panel) { return }

            $result = [System.Windows.MessageBox]::Show(
                "Delete panel $($panel.PanelName)?",
                "Confirm Delete",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning)

            if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                $db = $view.Tag.Database
                CableDocumentationModule\Remove-PatchPanel -PanelID $panel.PanelID -Database $db | Out-Null
                $panelDetailsGrid.Visibility = 'Collapsed'
                $detailsTitleLabel.Content = 'Select an item'
                $statusText.Text = "Deleted panel $($panel.PanelName)"
                Save-Database
                Refresh-Lists
            }
        }.GetNewClosure())

        # Event: Generate Labels
        $generateLabelsButton.Add_Click({
            param($sender, $e)
            $selected = @($cableListBox.SelectedItems)
            if ($selected.Count -eq 0) {
                $statusText.Text = 'Select cables to generate labels'
                return
            }

            try {
                $labels = @($selected | ForEach-Object {
                    CableDocumentationModule\New-CableLabel -Cable $_ -LabelType 'Full'
                })

                $dialog = New-Object Microsoft.Win32.SaveFileDialog
                $dialog.Title = 'Export Cable Labels'
                $dialog.Filter = 'HTML files (*.html)|*.html|Text files (*.txt)|*.txt|CSV files (*.csv)|*.csv'
                $dialog.DefaultExt = '.html'

                if ($dialog.ShowDialog() -eq $true) {
                    $format = switch -Regex ($dialog.FileName) {
                        '\.html$' { 'HTML' }
                        '\.csv$' { 'CSV' }
                        default { 'Text' }
                    }
                    $output = $labels | CableDocumentationModule\Export-CableLabels -Format $format
                    $output | Out-File -FilePath $dialog.FileName -Encoding UTF8
                    $statusText.Text = "Exported $($labels.Count) labels to $($dialog.FileName)"
                }
            }
            catch {
                $statusText.Text = "Error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Cable Label button
        $cableLabelButton.Add_Click({
            param($sender, $e)
            $cable = $view.Tag.SelectedCable
            if (-not $cable) { return }

            try {
                $label = CableDocumentationModule\New-CableLabel -Cable $cable -LabelType 'Full'
                $text = $label.Lines -join "`r`n"
                [System.Windows.Clipboard]::SetText($text)
                $statusText.Text = "Label copied to clipboard"
            }
            catch {
                $statusText.Text = "Error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Import
        $importButton.Add_Click({
            param($sender, $e)
            try {
                $dialog = New-Object Microsoft.Win32.OpenFileDialog
                $dialog.Title = 'Import Cable Database'
                $dialog.Filter = 'JSON files (*.json)|*.json'

                if ($dialog.ShowDialog() -eq $true) {
                    $db = $view.Tag.Database
                    $result = CableDocumentationModule\Import-CableDatabase -Path $dialog.FileName -Database $db -Merge
                    $statusText.Text = "Imported $($result.CablesImported) cables, $($result.PanelsImported) panels"
                    Save-Database
                    Refresh-Lists
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
                $dialog.Title = 'Export Cable Database'
                $dialog.Filter = 'JSON files (*.json)|*.json'
                $dialog.DefaultExt = '.json'

                if ($dialog.ShowDialog() -eq $true) {
                    $db = $view.Tag.Database
                    CableDocumentationModule\Export-CableDatabase -Path $dialog.FileName -Database $db
                    $statusText.Text = "Exported database to $($dialog.FileName)"
                }
            }
            catch {
                $statusText.Text = "Export error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Import CSV
        $importCsvButton.Add_Click({
            param($sender, $e)
            try {
                $dialog = New-Object Microsoft.Win32.OpenFileDialog
                $dialog.Title = 'Import Cable Runs from CSV'
                $dialog.Filter = 'CSV files (*.csv)|*.csv'

                if ($dialog.ShowDialog() -eq $true) {
                    $db = $view.Tag.Database
                    $result = CableDocumentationModule\Import-CableRunsFromCsv -Path $dialog.FileName -Database $db
                    $statusText.Text = "Imported $($result.Imported) cables ($($result.Errors) errors)"
                    Save-Database
                    Refresh-Lists
                }
            }
            catch {
                $statusText.Text = "Import error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Filter change
        $filterBox.Add_TextChanged({
            param($sender, $e)
            Refresh-Lists
        }.GetNewClosure())

        # Event: Clear filter
        $clearFilterButton.Add_Click({
            param($sender, $e)
            $filterBox.Text = ''
        }.GetNewClosure())

        # Initial load
        Refresh-Lists
        $statusText.Text = 'Ready'

        return $view

    } catch {
        Write-Warning "Failed to initialize CableDocumentation view: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function New-CableDocumentationView
