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

        # Helper: Show cable details (as scriptblock for closure capture)
        $showCableDetails = {
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

        # Helper: Show panel details (as scriptblock for closure capture)
        $showPanelDetails = {
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
            & $showCableDetails $null
            $cableListBox.SelectedItem = $null
            $panelListBox.SelectedItem = $null
        }.GetNewClosure())

        # Event: Add Panel button
        $addPanelButton.Add_Click({
            param($sender, $e)
            & $showPanelDetails $null
            $cableListBox.SelectedItem = $null
            $panelListBox.SelectedItem = $null
        }.GetNewClosure())

        # Event: Cable list selection
        $cableListBox.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if ($selected) {
                $panelListBox.SelectedItem = $null
                & $showCableDetails $selected
            }
        }.GetNewClosure())

        # Event: Panel list selection
        $panelListBox.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if ($selected) {
                $cableListBox.SelectedItem = $null
                & $showPanelDetails $selected
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

function Initialize-CableDocumentationView {
    <#
    .SYNOPSIS
        Initializes the Cable Documentation view for nested tab container use.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ContentControl]$Host
    )

    try {
        $viewPath = Join-Path $PSScriptRoot '..\Views\CableDocumentationView.xaml'
        if (-not (Test-Path $viewPath)) {
            Write-Warning "CableDocumentationView.xaml not found at: $viewPath"
            return
        }

        $xamlContent = Get-Content -Path $viewPath -Raw
        $xamlContent = $xamlContent -replace 'x:Class="[^"]*"', ''
        $xamlContent = $xamlContent -replace 'mc:Ignorable="d"', ''

        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlContent))
        $view = [System.Windows.Markup.XamlReader]::Load($reader)
        $Host.Content = $view

        # Initialize the view with event handlers
        Initialize-CableDocumentationControls -View $view

        return $view
    }
    catch {
        Write-Warning "Failed to initialize CableDocumentation view: $($_.Exception.Message)"
    }
}

function Initialize-CableDocumentationControls {
    <#
    .SYNOPSIS
        Wires up controls and event handlers for the Cable Documentation view.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    # Get controls from the view
    $addCableButton = $View.FindName('AddCableButton')
    $addPanelButton = $View.FindName('AddPanelButton')
    $importButton = $View.FindName('ImportButton')
    $exportButton = $View.FindName('ExportButton')
    $importCsvButton = $View.FindName('ImportCsvButton')
    $generateLabelsButton = $View.FindName('GenerateLabelsButton')
    $filterBox = $View.FindName('FilterBox')
    $clearFilterButton = $View.FindName('ClearFilterButton')

    $cableListBox = $View.FindName('CableListBox')
    $panelListBox = $View.FindName('PanelListBox')
    $cableCountLabel = $View.FindName('CableCountLabel')
    $panelCountLabel = $View.FindName('PanelCountLabel')

    $detailsTitleLabel = $View.FindName('DetailsTitleLabel')
    $detailsTabControl = $View.FindName('DetailsTabControl')
    $cableDetailsTab = $View.FindName('CableDetailsTab')
    $panelDetailsTab = $View.FindName('PanelDetailsTab')
    $cableDetailsGrid = $View.FindName('CableDetailsGrid')
    $panelDetailsGrid = $View.FindName('PanelDetailsGrid')

    # Cable detail controls
    $cableIdBox = $View.FindName('CableIdBox')
    $sourceTypeCombo = $View.FindName('SourceTypeCombo')
    $sourceDeviceBox = $View.FindName('SourceDeviceBox')
    $sourcePortBox = $View.FindName('SourcePortBox')
    $destTypeCombo = $View.FindName('DestTypeCombo')
    $destDeviceBox = $View.FindName('DestDeviceBox')
    $destPortBox = $View.FindName('DestPortBox')
    $cableTypeCombo = $View.FindName('CableTypeCombo')
    $lengthBox = $View.FindName('LengthBox')
    $colorBox = $View.FindName('ColorBox')
    $statusCombo = $View.FindName('StatusCombo')
    $notesBox = $View.FindName('NotesBox')
    $saveCableButton = $View.FindName('SaveCableButton')
    $deleteCableButton = $View.FindName('DeleteCableButton')
    $cableLabelButton = $View.FindName('CableLabelButton')
    $cableCreatedText = $View.FindName('CableCreatedText')
    $cableModifiedText = $View.FindName('CableModifiedText')

    # Panel detail controls
    $panelIdBox = $View.FindName('PanelIdBox')
    $panelNameBox = $View.FindName('PanelNameBox')
    $panelLocationBox = $View.FindName('PanelLocationBox')
    $panelRackIdBox = $View.FindName('PanelRackIdBox')
    $panelRackUBox = $View.FindName('PanelRackUBox')
    $panelPortCountText = $View.FindName('PanelPortCountText')
    $savePanelButton = $View.FindName('SavePanelButton')
    $deletePanelButton = $View.FindName('DeletePanelButton')
    $panelLabelsButton = $View.FindName('PanelLabelsButton')
    $portGrid = $View.FindName('PortGrid')
    $portUtilizationLabel = $View.FindName('PortUtilizationLabel')

    # Stats controls
    $totalCablesText = $View.FindName('TotalCablesText')
    $activeCablesText = $View.FindName('ActiveCablesText')
    $reservedCablesText = $View.FindName('ReservedCablesText')
    $faultyCablesText = $View.FindName('FaultyCablesText')
    $plannedCablesText = $View.FindName('PlannedCablesText')
    $totalPanelsText = $View.FindName('TotalPanelsText')
    $totalPortsText = $View.FindName('TotalPortsText')
    $usedPortsText = $View.FindName('UsedPortsText')
    $availablePortsText = $View.FindName('AvailablePortsText')
    $cableTypesItemsControl = $View.FindName('CableTypesItemsControl')

    $statusText = $View.FindName('StatusText')

    # Initialize database
    $scriptDir = Split-Path $PSScriptRoot -Parent
    $dataPath = Join-Path $scriptDir 'Data\CableDatabase.json'
    $cableDb = CableDocumentationModule\New-CableDatabase

    if (Test-Path $dataPath) {
        try {
            CableDocumentationModule\Import-CableDatabase -Path $dataPath -Database $cableDb | Out-Null
            if ($statusText) { $statusText.Text = "Loaded database from $dataPath" }
        } catch {
            if ($statusText) { $statusText.Text = "Error loading database: $($_.Exception.Message)" }
        }
    }

    # Store state in view's Tag
    $View.Tag = @{
        Database = $cableDb
        DataPath = $dataPath
        IsNewCable = $false
        IsNewPanel = $false
        SelectedCable = $null
        SelectedPanel = $null
    }

    # Helper functions as scriptblocks
    $selectComboItem = {
        param($Combo, $Value)
        foreach ($item in $Combo.Items) {
            if ($item.Content -eq $Value) {
                $Combo.SelectedItem = $item
                return
            }
        }
    }

    $getComboValue = {
        param($Combo)
        if ($Combo.SelectedItem) { return $Combo.SelectedItem.Content }
        return $null
    }

    $updateStats = {
        $db = $View.Tag.Database
        $stats = CableDocumentationModule\Get-CableDatabaseStats -Database $db
        if ($totalCablesText) { $totalCablesText.Text = "Total Cables: $($stats.TotalCables)" }
        $active = if ($stats.CablesByStatus['Active']) { $stats.CablesByStatus['Active'] } else { 0 }
        $reserved = if ($stats.CablesByStatus['Reserved']) { $stats.CablesByStatus['Reserved'] } else { 0 }
        $faulty = if ($stats.CablesByStatus['Faulty']) { $stats.CablesByStatus['Faulty'] } else { 0 }
        $planned = if ($stats.CablesByStatus['Planned']) { $stats.CablesByStatus['Planned'] } else { 0 }
        if ($activeCablesText) { $activeCablesText.Text = "Active: $active" }
        if ($reservedCablesText) { $reservedCablesText.Text = "Reserved: $reserved" }
        if ($faultyCablesText) { $faultyCablesText.Text = "Faulty: $faulty" }
        if ($plannedCablesText) { $plannedCablesText.Text = "Planned: $planned" }
        if ($totalPanelsText) { $totalPanelsText.Text = "Total Panels: $($stats.TotalPatchPanels)" }
        if ($totalPortsText) { $totalPortsText.Text = "Total Ports: $($stats.TotalPanelPorts)" }
        if ($usedPortsText) { $usedPortsText.Text = "Used Ports: $($stats.UsedPanelPorts)" }
        if ($availablePortsText) { $availablePortsText.Text = "Available: $($stats.AvailablePorts)" }
        $typesList = @()
        foreach ($key in $stats.CablesByType.Keys) {
            $typesList += [PSCustomObject]@{ Key = $key; Value = $stats.CablesByType[$key] }
        }
        if ($cableTypesItemsControl) { $cableTypesItemsControl.ItemsSource = $typesList }
    }

    $saveDatabase = {
        $dataPath = $View.Tag.DataPath
        $db = $View.Tag.Database
        try {
            $dataDir = Split-Path $dataPath -Parent
            if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
            CableDocumentationModule\Export-CableDatabase -Path $dataPath -Database $db
            if ($statusText) { $statusText.Text = "Saved to $dataPath" }
        } catch {
            if ($statusText) { $statusText.Text = "Error saving: $($_.Exception.Message)" }
        }
    }

    $refreshLists = {
        $filter = $filterBox.Text
        $db = $View.Tag.Database
        $cables = @(CableDocumentationModule\Get-CableRun -Database $db)
        $panels = @(CableDocumentationModule\Get-PatchPanel -Database $db)
        if (-not [string]::IsNullOrWhiteSpace($filter)) {
            $cables = @($cables | Where-Object {
                $_.CableID -like "*$filter*" -or $_.SourceDevice -like "*$filter*" -or
                $_.DestDevice -like "*$filter*" -or $_.Notes -like "*$filter*"
            })
            $panels = @($panels | Where-Object {
                $_.PanelID -like "*$filter*" -or $_.PanelName -like "*$filter*" -or $_.Location -like "*$filter*"
            })
        }
        if ($cableListBox) { $cableListBox.ItemsSource = $cables }
        if ($panelListBox) { $panelListBox.ItemsSource = $panels }
        if ($cableCountLabel) { $cableCountLabel.Content = "($($cables.Count))" }
        if ($panelCountLabel) { $panelCountLabel.Content = "($($panels.Count))" }
        & $updateStats
    }

    $showCableDetails = {
        param($Cable)
        $View.Tag.SelectedCable = $Cable
        $View.Tag.IsNewCable = ($Cable -eq $null)
        if ($cableDetailsGrid) { $cableDetailsGrid.Visibility = 'Visible' }
        if ($panelDetailsGrid) { $panelDetailsGrid.Visibility = 'Collapsed' }
        if ($detailsTabControl) { $detailsTabControl.SelectedItem = $cableDetailsTab }
        if ($Cable) {
            if ($detailsTitleLabel) { $detailsTitleLabel.Content = "Cable: $($Cable.CableID)" }
            if ($cableIdBox) { $cableIdBox.Text = $Cable.CableID }
            & $selectComboItem $sourceTypeCombo $Cable.SourceType
            if ($sourceDeviceBox) { $sourceDeviceBox.Text = $Cable.SourceDevice }
            if ($sourcePortBox) { $sourcePortBox.Text = $Cable.SourcePort }
            & $selectComboItem $destTypeCombo $Cable.DestType
            if ($destDeviceBox) { $destDeviceBox.Text = $Cable.DestDevice }
            if ($destPortBox) { $destPortBox.Text = $Cable.DestPort }
            & $selectComboItem $cableTypeCombo $Cable.CableType
            if ($lengthBox) { $lengthBox.Text = $Cable.Length }
            if ($colorBox) { $colorBox.Text = $Cable.Color }
            & $selectComboItem $statusCombo $Cable.Status
            if ($notesBox) { $notesBox.Text = $Cable.Notes }
            if ($Cable.CreatedDate -and $cableCreatedText) { $cableCreatedText.Text = $Cable.CreatedDate.ToString('yyyy-MM-dd HH:mm') }
            if ($Cable.ModifiedDate -and $cableModifiedText) { $cableModifiedText.Text = $Cable.ModifiedDate.ToString('yyyy-MM-dd HH:mm') }
        } else {
            if ($detailsTitleLabel) { $detailsTitleLabel.Content = "New Cable" }
            if ($cableIdBox) { $cableIdBox.Text = '' }
            if ($sourceTypeCombo) { $sourceTypeCombo.SelectedIndex = 0 }
            if ($sourceDeviceBox) { $sourceDeviceBox.Text = '' }
            if ($sourcePortBox) { $sourcePortBox.Text = '' }
            if ($destTypeCombo) { $destTypeCombo.SelectedIndex = 0 }
            if ($destDeviceBox) { $destDeviceBox.Text = '' }
            if ($destPortBox) { $destPortBox.Text = '' }
            if ($cableTypeCombo) { $cableTypeCombo.SelectedIndex = 1 }
            if ($lengthBox) { $lengthBox.Text = '' }
            if ($colorBox) { $colorBox.Text = '' }
            if ($statusCombo) { $statusCombo.SelectedIndex = 0 }
            if ($notesBox) { $notesBox.Text = '' }
            if ($cableCreatedText) { $cableCreatedText.Text = '' }
            if ($cableModifiedText) { $cableModifiedText.Text = '' }
        }
    }

    $showPanelDetails = {
        param($Panel)
        $View.Tag.SelectedPanel = $Panel
        $View.Tag.IsNewPanel = ($Panel -eq $null)
        if ($cableDetailsGrid) { $cableDetailsGrid.Visibility = 'Collapsed' }
        if ($panelDetailsGrid) { $panelDetailsGrid.Visibility = 'Visible' }
        if ($detailsTabControl) { $detailsTabControl.SelectedItem = $panelDetailsTab }
        if ($Panel) {
            if ($detailsTitleLabel) { $detailsTitleLabel.Content = "Panel: $($Panel.PanelName)" }
            if ($panelIdBox) { $panelIdBox.Text = $Panel.PanelID }
            if ($panelNameBox) { $panelNameBox.Text = $Panel.PanelName }
            if ($panelLocationBox) { $panelLocationBox.Text = $Panel.Location }
            if ($panelRackIdBox) { $panelRackIdBox.Text = $Panel.RackID }
            if ($panelRackUBox) { $panelRackUBox.Text = $Panel.RackU }
            if ($panelPortCountText) { $panelPortCountText.Text = "$($Panel.PortCount) ports" }
            $portItems = @()
            $usedCount = 0
            foreach ($port in $Panel.Ports) {
                $tooltip = "Port $($port.PortNumber)"
                if ($port.Label) { $tooltip += ": $($port.Label)" }
                if ($port.CableID) { $tooltip += " [Cable: $($port.CableID)]" }
                $tooltip += " - $($port.Status)"
                $portItems += [PSCustomObject]@{ PortNumber = $port.PortNumber; Label = $port.Label; Status = $port.Status; CableID = $port.CableID; ToolTip = $tooltip }
                if ($port.Status -eq 'Connected' -or $port.CableID) { $usedCount++ }
            }
            if ($portGrid) { $portGrid.ItemsSource = $portItems }
            if ($portUtilizationLabel) { $portUtilizationLabel.Content = "($usedCount/$($Panel.PortCount) used)" }
        } else {
            if ($detailsTitleLabel) { $detailsTitleLabel.Content = "New Patch Panel" }
            if ($panelIdBox) { $panelIdBox.Text = '' }
            if ($panelNameBox) { $panelNameBox.Text = '' }
            if ($panelLocationBox) { $panelLocationBox.Text = '' }
            if ($panelRackIdBox) { $panelRackIdBox.Text = '' }
            if ($panelRackUBox) { $panelRackUBox.Text = '' }
            if ($panelPortCountText) { $panelPortCountText.Text = '24 ports (default)' }
            if ($portGrid) { $portGrid.ItemsSource = @() }
            if ($portUtilizationLabel) { $portUtilizationLabel.Content = '(0/24 used)' }
        }
    }

    # Register event handlers
    if ($addCableButton) { $addCableButton.Add_Click({ & $showCableDetails $null; if ($cableListBox) { $cableListBox.SelectedItem = $null }; if ($panelListBox) { $panelListBox.SelectedItem = $null } }.GetNewClosure()) }
    if ($addPanelButton) { $addPanelButton.Add_Click({ & $showPanelDetails $null; if ($cableListBox) { $cableListBox.SelectedItem = $null }; if ($panelListBox) { $panelListBox.SelectedItem = $null } }.GetNewClosure()) }
    if ($cableListBox) { $cableListBox.Add_SelectionChanged({ param($s,$e); $sel = $s.SelectedItem; if ($sel) { if ($panelListBox) { $panelListBox.SelectedItem = $null }; & $showCableDetails $sel } }.GetNewClosure()) }
    if ($panelListBox) { $panelListBox.Add_SelectionChanged({ param($s,$e); $sel = $s.SelectedItem; if ($sel) { if ($cableListBox) { $cableListBox.SelectedItem = $null }; & $showPanelDetails $sel } }.GetNewClosure()) }
    if ($filterBox) { $filterBox.Add_TextChanged({ & $refreshLists }.GetNewClosure()) }
    if ($clearFilterButton) { $clearFilterButton.Add_Click({ if ($filterBox) { $filterBox.Text = '' } }.GetNewClosure()) }

    if ($saveCableButton) {
        $saveCableButton.Add_Click({
            $db = $View.Tag.Database
            $sourceType = & $getComboValue $sourceTypeCombo
            $destType = & $getComboValue $destTypeCombo
            $cableType = & $getComboValue $cableTypeCombo
            $status = & $getComboValue $statusCombo
            if ([string]::IsNullOrWhiteSpace($sourceDeviceBox.Text) -or [string]::IsNullOrWhiteSpace($destDeviceBox.Text)) {
                if ($statusText) { $statusText.Text = 'Please fill in required fields' }
                return
            }
            try {
                if ($View.Tag.IsNewCable) {
                    $params = @{ SourceType=$sourceType; SourceDevice=$sourceDeviceBox.Text; SourcePort=$sourcePortBox.Text; DestType=$destType; DestDevice=$destDeviceBox.Text; DestPort=$destPortBox.Text; CableType=$cableType; Status=$status }
                    if ($cableIdBox.Text) { $params['CableID'] = $cableIdBox.Text }
                    if ($lengthBox.Text) { $params['Length'] = $lengthBox.Text }
                    if ($colorBox.Text) { $params['Color'] = $colorBox.Text }
                    if ($notesBox.Text) { $params['Notes'] = $notesBox.Text }
                    $cable = CableDocumentationModule\New-CableRun @params
                    CableDocumentationModule\Add-CableRun -Cable $cable -Database $db | Out-Null
                    if ($statusText) { $statusText.Text = "Created cable $($cable.CableID)" }
                } else {
                    $props = @{ SourceType=$sourceType; SourceDevice=$sourceDeviceBox.Text; SourcePort=$sourcePortBox.Text; DestType=$destType; DestDevice=$destDeviceBox.Text; DestPort=$destPortBox.Text; CableType=$cableType; Length=$lengthBox.Text; Color=$colorBox.Text; Status=$status; Notes=$notesBox.Text }
                    CableDocumentationModule\Update-CableRun -CableID $cableIdBox.Text -Properties $props -Database $db | Out-Null
                    if ($statusText) { $statusText.Text = "Updated cable $($cableIdBox.Text)" }
                }
                & $saveDatabase
                & $refreshLists
            } catch { if ($statusText) { $statusText.Text = "Error: $($_.Exception.Message)" } }
        }.GetNewClosure())
    }

    if ($deleteCableButton) {
        $deleteCableButton.Add_Click({
            $cable = $View.Tag.SelectedCable
            if (-not $cable) { return }
            $result = [System.Windows.MessageBox]::Show("Delete cable $($cable.CableID)?", "Confirm Delete", 'YesNo', 'Warning')
            if ($result -eq 'Yes') {
                $db = $View.Tag.Database
                CableDocumentationModule\Remove-CableRun -CableID $cable.CableID -Database $db | Out-Null
                if ($cableDetailsGrid) { $cableDetailsGrid.Visibility = 'Collapsed' }
                if ($statusText) { $statusText.Text = "Deleted cable $($cable.CableID)" }
                & $saveDatabase
                & $refreshLists
            }
        }.GetNewClosure())
    }

    if ($savePanelButton) {
        $savePanelButton.Add_Click({
            $db = $View.Tag.Database
            if ([string]::IsNullOrWhiteSpace($panelNameBox.Text)) {
                if ($statusText) { $statusText.Text = 'Please enter a panel name' }
                return
            }
            try {
                if ($View.Tag.IsNewPanel) {
                    $params = @{ PanelName = $panelNameBox.Text }
                    if ($panelIdBox.Text) { $params['PanelID'] = $panelIdBox.Text }
                    if ($panelLocationBox.Text) { $params['Location'] = $panelLocationBox.Text }
                    if ($panelRackIdBox.Text) { $params['RackID'] = $panelRackIdBox.Text }
                    if ($panelRackUBox.Text) { $params['RackU'] = $panelRackUBox.Text }
                    $panel = CableDocumentationModule\New-PatchPanel @params
                    CableDocumentationModule\Add-PatchPanel -Panel $panel -Database $db | Out-Null
                    if ($statusText) { $statusText.Text = "Created panel $($panel.PanelName)" }
                } else {
                    $panel = $View.Tag.SelectedPanel
                    $panel.PanelName = $panelNameBox.Text
                    $panel.Location = $panelLocationBox.Text
                    $panel.RackID = $panelRackIdBox.Text
                    $panel.RackU = $panelRackUBox.Text
                    $panel.ModifiedDate = Get-Date
                    if ($statusText) { $statusText.Text = "Updated panel $($panel.PanelName)" }
                }
                & $saveDatabase
                & $refreshLists
            } catch { if ($statusText) { $statusText.Text = "Error: $($_.Exception.Message)" } }
        }.GetNewClosure())
    }

    if ($deletePanelButton) {
        $deletePanelButton.Add_Click({
            $panel = $View.Tag.SelectedPanel
            if (-not $panel) { return }
            $result = [System.Windows.MessageBox]::Show("Delete panel $($panel.PanelName)?", "Confirm Delete", 'YesNo', 'Warning')
            if ($result -eq 'Yes') {
                $db = $View.Tag.Database
                CableDocumentationModule\Remove-PatchPanel -PanelID $panel.PanelID -Database $db | Out-Null
                if ($panelDetailsGrid) { $panelDetailsGrid.Visibility = 'Collapsed' }
                if ($statusText) { $statusText.Text = "Deleted panel $($panel.PanelName)" }
                & $saveDatabase
                & $refreshLists
            }
        }.GetNewClosure())
    }

    if ($importButton) {
        $importButton.Add_Click({
            try {
                $dialog = New-Object Microsoft.Win32.OpenFileDialog
                $dialog.Title = 'Import Cable Database'
                $dialog.Filter = 'JSON files (*.json)|*.json'
                if ($dialog.ShowDialog() -eq $true) {
                    $db = $View.Tag.Database
                    $result = CableDocumentationModule\Import-CableDatabase -Path $dialog.FileName -Database $db -Merge
                    if ($statusText) { $statusText.Text = "Imported $($result.CablesImported) cables, $($result.PanelsImported) panels" }
                    & $saveDatabase
                    & $refreshLists
                }
            } catch { if ($statusText) { $statusText.Text = "Import error: $($_.Exception.Message)" } }
        }.GetNewClosure())
    }

    if ($exportButton) {
        $exportButton.Add_Click({
            try {
                $dialog = New-Object Microsoft.Win32.SaveFileDialog
                $dialog.Title = 'Export Cable Database'
                $dialog.Filter = 'JSON files (*.json)|*.json'
                $dialog.DefaultExt = '.json'
                if ($dialog.ShowDialog() -eq $true) {
                    $db = $View.Tag.Database
                    CableDocumentationModule\Export-CableDatabase -Path $dialog.FileName -Database $db
                    if ($statusText) { $statusText.Text = "Exported database to $($dialog.FileName)" }
                }
            } catch { if ($statusText) { $statusText.Text = "Export error: $($_.Exception.Message)" } }
        }.GetNewClosure())
    }

    # Initial load
    & $refreshLists
    if ($statusText) { $statusText.Text = 'Ready' }
}

Export-ModuleMember -Function New-CableDocumentationView, Initialize-CableDocumentationView
