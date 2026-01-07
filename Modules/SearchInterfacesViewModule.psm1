Set-StrictMode -Version Latest

if (-not (Get-Variable -Name SearchUpdateTimer -Scope Script -ErrorAction SilentlyContinue)) {
    $script:SearchUpdateTimer = $null
}
$script:SearchHistoryMaxItems = 20

function script:Get-SearchHistory {
    $history = @()
    try {
        $settings = $null
        try { $settings = MainWindow.Services\Load-StateTraceSettings } catch { $settings = $null }
        if ($settings -and $settings.ContainsKey('SearchHistory')) {
            $history = @($settings['SearchHistory'])
        }
    } catch { }
    return $history
}

function script:Add-SearchHistoryItem {
    param([string]$Term)
    if ([string]::IsNullOrWhiteSpace($Term)) { return }
    $term = $Term.Trim()
    if ($term.Length -lt 2) { return }  # Don't save very short searches

    try {
        $settings = $null
        try { $settings = MainWindow.Services\Load-StateTraceSettings } catch { $settings = @{} }
        if (-not $settings) { $settings = @{} }

        $history = @()
        if ($settings.ContainsKey('SearchHistory')) {
            $history = @($settings['SearchHistory'])
        }

        # Remove if already exists (will re-add at top)
        $history = @($history | Where-Object { $_ -ne $term })

        # Add to beginning
        $history = @($term) + $history

        # Limit to max items
        if ($history.Count -gt $script:SearchHistoryMaxItems) {
            $history = $history[0..($script:SearchHistoryMaxItems - 1)]
        }

        $settings['SearchHistory'] = $history
        MainWindow.Services\Save-StateTraceSettings -Settings $settings
    } catch { }
}

function script:Update-SearchHistoryDropdown {
    param($SearchBox)
    if (-not $SearchBox) { return }

    $history = script:Get-SearchHistory
    $currentText = $SearchBox.Text

    $SearchBox.Items.Clear()
    foreach ($item in $history) {
        if ($item) { $SearchBox.Items.Add($item) | Out-Null }
    }

    # Restore text (clearing items resets it)
    $SearchBox.Text = $currentText
}

# === Filter Presets ===

function script:Get-FilterPresets {
    $presets = @{}
    try {
        $settings = $null
        try { $settings = MainWindow.Services\Load-StateTraceSettings } catch { $settings = $null }
        if ($settings -and $settings.ContainsKey('FilterPresets')) {
            $presets = $settings['FilterPresets']
            if (-not $presets) { $presets = @{} }
        }
    } catch { }
    return $presets
}

function script:Save-FilterPreset {
    param(
        [string]$Name,
        [string]$SearchTerm,
        [int]$StatusIndex,
        [int]$AuthIndex,
        [string]$VlanValue,
        [bool]$RegexEnabled
    )
    if ([string]::IsNullOrWhiteSpace($Name)) { return }

    try {
        $settings = $null
        try { $settings = MainWindow.Services\Load-StateTraceSettings } catch { $settings = @{} }
        if (-not $settings) { $settings = @{} }

        $presets = @{}
        if ($settings.ContainsKey('FilterPresets')) {
            $presets = $settings['FilterPresets']
            if (-not $presets) { $presets = @{} }
        }

        $presets[$Name] = @{
            SearchTerm   = $SearchTerm
            StatusIndex  = $StatusIndex
            AuthIndex    = $AuthIndex
            VlanValue    = $VlanValue
            RegexEnabled = $RegexEnabled
        }

        $settings['FilterPresets'] = $presets
        MainWindow.Services\Save-StateTraceSettings -Settings $settings
    } catch { }
}

function script:Delete-FilterPreset {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return }

    try {
        $settings = $null
        try { $settings = MainWindow.Services\Load-StateTraceSettings } catch { $settings = @{} }
        if (-not $settings) { return }

        if ($settings.ContainsKey('FilterPresets')) {
            $presets = $settings['FilterPresets']
            if ($presets -and $presets.ContainsKey($Name)) {
                $presets.Remove($Name)
                $settings['FilterPresets'] = $presets
                MainWindow.Services\Save-StateTraceSettings -Settings $settings
            }
        }
    } catch { }
}

function script:Update-PresetDropdown {
    param($Dropdown)
    if (-not $Dropdown) { return }

    $presets = script:Get-FilterPresets
    $Dropdown.Items.Clear()

    # Add default "(None)" item
    $noneItem = New-Object System.Windows.Controls.ComboBoxItem
    $noneItem.Content = '(None)'
    $Dropdown.Items.Add($noneItem) | Out-Null

    # Add saved presets
    foreach ($name in ($presets.Keys | Sort-Object)) {
        $Dropdown.Items.Add($name) | Out-Null
    }

    $Dropdown.SelectedIndex = 0
}

# === Column Width Persistence ===

function script:Get-ColumnWidths {
    param([string]$GridName)
    $widths = @{}
    try {
        $settings = $null
        try { $settings = MainWindow.Services\Load-StateTraceSettings } catch { $settings = $null }
        if ($settings -and $settings.ContainsKey('ColumnWidths') -and $settings['ColumnWidths'].ContainsKey($GridName)) {
            $widths = $settings['ColumnWidths'][$GridName]
            if (-not $widths) { $widths = @{} }
        }
    } catch { }
    return $widths
}

function script:Save-ColumnWidths {
    param(
        [string]$GridName,
        [hashtable]$Widths
    )
    if ([string]::IsNullOrWhiteSpace($GridName)) { return }

    try {
        $settings = $null
        try { $settings = MainWindow.Services\Load-StateTraceSettings } catch { $settings = @{} }
        if (-not $settings) { $settings = @{} }

        if (-not $settings.ContainsKey('ColumnWidths')) {
            $settings['ColumnWidths'] = @{}
        }

        $settings['ColumnWidths'][$GridName] = $Widths
        MainWindow.Services\Save-StateTraceSettings -Settings $settings
    } catch { }
}

function script:Apply-ColumnWidths {
    param(
        $DataGrid,
        [string]$GridName
    )
    if (-not $DataGrid) { return }

    $widths = script:Get-ColumnWidths -GridName $GridName
    if (-not $widths -or $widths.Count -eq 0) { return }

    foreach ($col in $DataGrid.Columns) {
        $header = $col.Header
        if ($header -and $widths.ContainsKey($header)) {
            try {
                $col.Width = [double]$widths[$header]
            } catch { }
        }
    }
}

function script:Wire-ColumnWidthPersistence {
    param(
        $DataGrid,
        [string]$GridName
    )
    if (-not $DataGrid) { return }

    # Debounce timer for saving (avoid saving on every pixel change)
    $saveTimer = New-Object System.Windows.Threading.DispatcherTimer
    $saveTimer.Interval = [TimeSpan]::FromMilliseconds(500)

    $saveAction = {
        $saveTimer.Stop()
        $widths = @{}
        foreach ($col in $DataGrid.Columns) {
            $header = $col.Header
            if ($header) {
                $widths[$header] = $col.ActualWidth
            }
        }
        script:Save-ColumnWidths -GridName $GridName -Widths $widths
    }.GetNewClosure()

    $saveTimer.Add_Tick($saveAction)

    # Wire up column width change event
    foreach ($col in $DataGrid.Columns) {
        $col.Add_PropertyChanged({
            param($sender, $e)
            if ($e.PropertyName -eq 'ActualWidth' -or $e.PropertyName -eq 'Width') {
                $saveTimer.Stop()
                $saveTimer.Start()
            }
        })
    }
}

function New-SearchInterfacesView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Window]$Window,
        [Parameter(Mandatory=$true)][string]$ScriptDir,
        [switch]$SuppressDialogs
    )

    $requestSearchUpdate = {
        try { DeviceInsightsModule\Update-SearchGridAsync } catch {
            try { DeviceInsightsModule\Update-SearchGrid } catch { }
        }
    }

    # Save search to history when debounce timer fires (actual search happens)
    $requestSearchUpdateWithHistory = {
        $term = $global:searchBox.Text
        if ($term -and $term.Length -ge 2) {
            script:Add-SearchHistoryItem -Term $term
            script:Update-SearchHistoryDropdown -SearchBox $global:searchBox
        }
        & $requestSearchUpdate
    }.GetNewClosure()

    $searchView = ViewCompositionModule\Set-StView -Window $Window -ScriptDir $ScriptDir -ViewName 'SearchInterfacesView' -HostControlName 'SearchInterfacesHost' -GlobalVariableName 'searchInterfacesView'
    if (-not $searchView) { return }
    # Acquire controls
    $searchBox      = $searchView.FindName('SearchBox')
    $searchClearBtn = $searchView.FindName('SearchClearButton')
    $searchGrid     = $searchView.FindName('SearchInterfacesGrid')
    $resultsStatus  = $searchView.FindName('SearchResultsStatus')
    $regexCheckbox  = $searchView.FindName('RegexCheckbox')
    $exportBtn      = $searchView.FindName('ExportSearchButton')
    $statusFilter   = $searchView.FindName('StatusFilter')
    $authFilter     = $searchView.FindName('AuthFilter')
    $vlanFilter     = $searchView.FindName('VlanFilter')
    $loadMoreBtn    = $searchView.FindName('LoadMoreButton')
    $presetDropdown = $searchView.FindName('FilterPresetDropdown')
    $savePresetBtn  = $searchView.FindName('SavePresetButton')
    $deletePresetBtn = $searchView.FindName('DeletePresetButton')

    # Promote search box to the global scope so that its Text property can be
    if ($searchBox) { $global:searchBox = $searchBox }
    # Initialise regex flag
    DeviceInsightsModule\Set-SearchRegexEnabled -Enabled:$false

    # Helper to update row count display
    $updateRowCount = {
        if ($resultsStatus -and $searchGrid) {
            $count = 0
            if ($searchGrid.ItemsSource) {
                $count = @($searchGrid.ItemsSource).Count
            }
            $resultsStatus.Text = "$count result$(if ($count -ne 1) { 's' })"
        }
    }.GetNewClosure()

    # Wire up ItemsSource changes to update row count
    if ($searchGrid) {
        $dpd = [System.ComponentModel.DependencyPropertyDescriptor]::FromProperty(
            [System.Windows.Controls.ItemsControl]::ItemsSourceProperty,
            [System.Windows.Controls.DataGrid])
        if ($dpd) {
            $dpd.AddValueChanged($searchGrid, {
                & $updateRowCount
            }.GetNewClosure())
        }
    }

    # Populate search history dropdown
    if ($searchBox) {
        script:Update-SearchHistoryDropdown -SearchBox $searchBox
    }

    # Clear button resets the search box and refreshes
    if ($searchClearBtn -and $searchBox) {
        $searchClearBtn.Add_Click({
            # reset the globally scoped search box so the handler always works
            $global:searchBox.Text = ''
            & $requestSearchUpdate
        }.GetNewClosure())
    }
    # Text changed triggers debounced search filtering.  A DispatcherTimer is
    if ($searchBox) {
        # Initialise the debounce timer only once per module load
        if (-not $script:SearchUpdateTimer) {
            $script:SearchUpdateTimer = ViewCompositionModule\New-StDebounceTimer -DelayMs 300 -Action $requestSearchUpdateWithHistory
        }
        $searchBox.Add_TextChanged({
            # Each keystroke resets the debounce timer.  Use script scope
            if ($script:SearchUpdateTimer) {
                $script:SearchUpdateTimer.Stop()
                $script:SearchUpdateTimer.Start()
            }
        })
        # Handle dropdown selection - apply the selected history item
        $searchBox.Add_SelectionChanged({
            param($sender, $e)
            if ($sender.SelectedItem -and -not [string]::IsNullOrEmpty($sender.SelectedItem)) {
                $sender.Text = $sender.SelectedItem
            }
        })
    }
    # Regex checkbox toggles global flag and refreshes
    if ($regexCheckbox) {
        $regexCheckbox.Add_Checked({
            DeviceInsightsModule\Set-SearchRegexEnabled -Enabled:$true
            & $requestSearchUpdate
        }.GetNewClosure())
        $regexCheckbox.Add_Unchecked({
            DeviceInsightsModule\Set-SearchRegexEnabled -Enabled:$false
            & $requestSearchUpdate
        }.GetNewClosure())
    }
    # Export button writes current search results (CSV or JSON format choice)
    if ($exportBtn) {
        $exportBtn.Add_Click({
            if (-not $searchGrid) { return }
            $rows = @($searchGrid.ItemsSource)
            if ($rows.Count -eq 0) {
                if (-not $SuppressDialogs) {
                    [System.Windows.MessageBox]::Show('No results to export.', 'Export', 'OK', 'Information') | Out-Null
                }
                return
            }
            # Confirm large exports
            if ($rows.Count -gt 500 -and -not $SuppressDialogs) {
                $result = [System.Windows.MessageBox]::Show(
                    "Export $($rows.Count) rows?",
                    'Confirm Export',
                    [System.Windows.MessageBoxButton]::YesNo,
                    [System.Windows.MessageBoxImage]::Question
                )
                if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }
            }
            ViewCompositionModule\Export-StRowsWithFormatChoice -Rows $rows -DefaultBaseName 'SearchResults' -EmptyMessage 'No results to export.' -SuccessNoun 'rows' -FailureMessagePrefix 'Failed to export' -SuppressDialogs:$SuppressDialogs
        }.GetNewClosure())
    }
    # Status and Auth filter dropdowns refresh the grid.  Use the same
    $restartSearchDebounce = {
        if ($script:SearchUpdateTimer) {
            $script:SearchUpdateTimer.Stop()
            $script:SearchUpdateTimer.Start()
        } else {
            & $requestSearchUpdate
        }
    }.GetNewClosure()
    if ($statusFilter) {
        $statusFilter.Add_SelectionChanged({
            & $restartSearchDebounce
        }.GetNewClosure())
    }
    if ($authFilter) {
        $authFilter.Add_SelectionChanged({
            & $restartSearchDebounce
        }.GetNewClosure())
    }
    if ($vlanFilter) {
        $vlanFilter.Add_SelectionChanged({
            & $restartSearchDebounce
        }.GetNewClosure())
        # Promote to global so DeviceInsightsModule can populate it
        $global:vlanFilter = $vlanFilter
    }
    # Load More button loads the next page of results
    if ($loadMoreBtn) {
        $loadMoreBtn.Add_Click({
            DeviceInsightsModule\Invoke-LoadMoreSearchResults
        })
    }

    # === Filter Presets Handlers ===
    if ($presetDropdown) {
        script:Update-PresetDropdown -Dropdown $presetDropdown

        $presetDropdown.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if (-not $selected) { return }

            # Handle ComboBoxItem vs string
            $presetName = if ($selected -is [System.Windows.Controls.ComboBoxItem]) {
                $selected.Content
            } else {
                $selected
            }

            if ($presetName -eq '(None)') { return }

            $presets = script:Get-FilterPresets
            if ($presets.ContainsKey($presetName)) {
                $preset = $presets[$presetName]

                # Apply preset values
                if ($global:searchBox -and $preset.ContainsKey('SearchTerm')) {
                    $global:searchBox.Text = $preset['SearchTerm']
                }
                if ($statusFilter -and $preset.ContainsKey('StatusIndex')) {
                    $statusFilter.SelectedIndex = [int]$preset['StatusIndex']
                }
                if ($authFilter -and $preset.ContainsKey('AuthIndex')) {
                    $authFilter.SelectedIndex = [int]$preset['AuthIndex']
                }
                if ($regexCheckbox -and $preset.ContainsKey('RegexEnabled')) {
                    $regexCheckbox.IsChecked = [bool]$preset['RegexEnabled']
                }
                # VLAN filter - find matching item by content
                if ($vlanFilter -and $preset.ContainsKey('VlanValue')) {
                    $vlanValue = $preset['VlanValue']
                    for ($i = 0; $i -lt $vlanFilter.Items.Count; $i++) {
                        $item = $vlanFilter.Items[$i]
                        $itemContent = if ($item -is [System.Windows.Controls.ComboBoxItem]) { $item.Content } else { $item }
                        if ($itemContent -eq $vlanValue) {
                            $vlanFilter.SelectedIndex = $i
                            break
                        }
                    }
                }
            }
        }.GetNewClosure())
    }

    if ($savePresetBtn) {
        $savePresetBtn.Add_Click({
            $name = [Microsoft.VisualBasic.Interaction]::InputBox('Enter a name for this filter preset:', 'Save Preset', '')
            if ([string]::IsNullOrWhiteSpace($name)) { return }

            # Get current filter values
            $searchTerm = if ($global:searchBox) { $global:searchBox.Text } else { '' }
            $statusIdx = if ($statusFilter) { $statusFilter.SelectedIndex } else { 0 }
            $authIdx = if ($authFilter) { $authFilter.SelectedIndex } else { 0 }
            $regexOn = if ($regexCheckbox) { $regexCheckbox.IsChecked -eq $true } else { $false }

            # Get VLAN filter value
            $vlanValue = 'All'
            if ($vlanFilter -and $vlanFilter.SelectedItem) {
                $sel = $vlanFilter.SelectedItem
                $vlanValue = if ($sel -is [System.Windows.Controls.ComboBoxItem]) { $sel.Content } else { $sel }
            }

            script:Save-FilterPreset -Name $name -SearchTerm $searchTerm -StatusIndex $statusIdx -AuthIndex $authIdx -VlanValue $vlanValue -RegexEnabled $regexOn
            script:Update-PresetDropdown -Dropdown $presetDropdown

            [System.Windows.MessageBox]::Show("Preset '$name' saved.", 'Preset Saved', 'OK', 'Information') | Out-Null
        }.GetNewClosure())
    }

    if ($deletePresetBtn) {
        $deletePresetBtn.Add_Click({
            if (-not $presetDropdown -or $presetDropdown.SelectedIndex -le 0) {
                [System.Windows.MessageBox]::Show('Select a preset to delete.', 'Delete Preset', 'OK', 'Warning') | Out-Null
                return
            }

            $selected = $presetDropdown.SelectedItem
            $presetName = if ($selected -is [System.Windows.Controls.ComboBoxItem]) { $selected.Content } else { $selected }

            if ($presetName -eq '(None)') { return }

            $result = [System.Windows.MessageBox]::Show("Delete preset '$presetName'?", 'Confirm Delete', 'YesNo', 'Question')
            if ($result -eq 'Yes') {
                script:Delete-FilterPreset -Name $presetName
                script:Update-PresetDropdown -Dropdown $presetDropdown
            }
        }.GetNewClosure())
    }

    # Context menu handlers
    if ($searchGrid -and $searchGrid.ContextMenu) {
        $contextMenu = $searchGrid.ContextMenu
        $copyRowItem = $contextMenu.Items | Where-Object { $_.Name -eq 'CopyRowMenuItem' } | Select-Object -First 1
        $copyCellItem = $contextMenu.Items | Where-Object { $_.Name -eq 'CopyCellMenuItem' } | Select-Object -First 1
        $copyAllItem = $contextMenu.Items | Where-Object { $_.Name -eq 'CopyAllMenuItem' } | Select-Object -First 1
        $exportSelectedItem = $contextMenu.Items | Where-Object { $_.Name -eq 'ExportSelectedMenuItem' } | Select-Object -First 1

        if ($copyRowItem) {
            $copyRowItem.Add_Click({
                $selected = $searchGrid.SelectedItems
                if ($selected.Count -eq 0) { return }
                $text = ($selected | ForEach-Object {
                    "$($_.Hostname)`t$($_.Port)`t$($_.Name)`t$($_.Status)`t$($_.VLAN)`t$($_.Duplex)`t$($_.Speed)`t$($_.Type)`t$($_.LearnedMACs)`t$($_.AuthState)`t$($_.AuthMode)`t$($_.AuthClientMAC)"
                }) -join "`r`n"
                [System.Windows.Clipboard]::SetText($text)
            }.GetNewClosure())
        }
        if ($copyCellItem) {
            $copyCellItem.Add_Click({
                $cell = $searchGrid.CurrentCell
                if ($null -eq $cell -or $null -eq $cell.Item) { return }
                $propName = $cell.Column.SortMemberPath
                if (-not $propName) { $propName = $cell.Column.Header }
                $value = $cell.Item.$propName
                if ($null -ne $value) { [System.Windows.Clipboard]::SetText([string]$value) }
            }.GetNewClosure())
        }
        if ($copyAllItem) {
            $copyAllItem.Add_Click({
                $rows = $searchGrid.ItemsSource
                if (-not $rows -or $rows.Count -eq 0) { return }
                $header = "Switch`tPort`tName`tStatus`tVLAN`tDuplex`tSpeed`tType`tLearnedMACs`tAuthState`tAuthMode`tClient MAC"
                $lines = @($header) + ($rows | ForEach-Object {
                    "$($_.Hostname)`t$($_.Port)`t$($_.Name)`t$($_.Status)`t$($_.VLAN)`t$($_.Duplex)`t$($_.Speed)`t$($_.Type)`t$($_.LearnedMACs)`t$($_.AuthState)`t$($_.AuthMode)`t$($_.AuthClientMAC)"
                })
                [System.Windows.Clipboard]::SetText($lines -join "`r`n")
            }.GetNewClosure())
        }
        if ($exportSelectedItem) {
            $exportSelectedItem.Add_Click({
                $selected = @($searchGrid.SelectedItems)
                if ($selected.Count -eq 0) {
                    [System.Windows.MessageBox]::Show('No rows selected.', 'Export', 'OK', 'Information') | Out-Null
                    return
                }
                ViewCompositionModule\Export-StRowsWithFormatChoice -Rows $selected -DefaultBaseName 'SearchResults_Selected' -EmptyMessage 'No rows selected.' -SuccessNoun 'rows' -FailureMessagePrefix 'Failed to export' -SuppressDialogs:$SuppressDialogs
            }.GetNewClosure())
        }
    }

    # Keyboard shortcuts
    if ($searchView) {
        $searchView.Add_PreviewKeyDown({
            param($sender, $e)
            if ($e.Key -eq 'F' -and [System.Windows.Input.Keyboard]::Modifiers -eq 'Control') {
                # Ctrl+F - Focus search box
                if ($searchBox) { $searchBox.Focus() }
                $e.Handled = $true
            }
            elseif ($e.Key -eq 'C' -and [System.Windows.Input.Keyboard]::Modifiers -eq 'Control') {
                # Ctrl+C - Copy selected rows
                $selected = $searchGrid.SelectedItems
                if ($selected.Count -gt 0) {
                    $text = ($selected | ForEach-Object {
                        "$($_.Hostname)`t$($_.Port)`t$($_.Name)`t$($_.Status)`t$($_.VLAN)"
                    }) -join "`r`n"
                    [System.Windows.Clipboard]::SetText($text)
                    $e.Handled = $true
                }
            }
            elseif ($e.Key -eq 'E' -and [System.Windows.Input.Keyboard]::Modifiers -eq 'Control') {
                # Ctrl+E - Export
                if ($exportBtn) { $exportBtn.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
                $e.Handled = $true
            }
            elseif ($e.Key -eq 'Escape') {
                # Escape - Clear all filters
                if ($searchBox) { $searchBox.Text = '' }
                if ($statusFilter) { $statusFilter.SelectedIndex = 0 }
                if ($authFilter) { $authFilter.SelectedIndex = 0 }
                if ($vlanFilter) { $vlanFilter.SelectedIndex = 0 }
                if ($presetDropdown) { $presetDropdown.SelectedIndex = 0 }
                & $requestSearchUpdate
                $e.Handled = $true
            }
        }.GetNewClosure())
    }

    # Column width persistence
    if ($searchGrid) {
        script:Apply-ColumnWidths -DataGrid $searchGrid -GridName 'SearchInterfacesGrid'
        script:Wire-ColumnWidthPersistence -DataGrid $searchGrid -GridName 'SearchInterfacesGrid'
    }

    # Delay heavy site-wide load until the user searches.
    if ($searchGrid) { $searchGrid.ItemsSource = @() }
}

Export-ModuleMember -Function New-SearchInterfacesView

