Set-StrictMode -Version Latest

# === Column Width Persistence (shared with SearchInterfacesViewModule pattern) ===

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
    param([string]$GridName, [hashtable]$Widths)
    if ([string]::IsNullOrWhiteSpace($GridName)) { return }
    try {
        $settings = $null
        try { $settings = MainWindow.Services\Load-StateTraceSettings } catch { $settings = @{} }
        if (-not $settings) { $settings = @{} }
        if (-not $settings.ContainsKey('ColumnWidths')) { $settings['ColumnWidths'] = @{} }
        $settings['ColumnWidths'][$GridName] = $Widths
        MainWindow.Services\Save-StateTraceSettings -Settings $settings
    } catch { }
}

function script:Apply-ColumnWidths {
    param($DataGrid, [string]$GridName)
    if (-not $DataGrid) { return }
    $widths = script:Get-ColumnWidths -GridName $GridName
    if (-not $widths -or $widths.Count -eq 0) { return }
    foreach ($col in $DataGrid.Columns) {
        $header = $col.Header
        if ($header -and $widths.ContainsKey($header)) {
            try { $col.Width = [double]$widths[$header] } catch { }
        }
    }
}

function script:Wire-ColumnWidthPersistence {
    param($DataGrid, [string]$GridName)
    if (-not $DataGrid) { return }
    $saveTimer = New-Object System.Windows.Threading.DispatcherTimer
    $saveTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $saveAction = {
        $saveTimer.Stop()
        $widths = @{}
        foreach ($col in $DataGrid.Columns) {
            $header = $col.Header
            if ($header) { $widths[$header] = $col.ActualWidth }
        }
        script:Save-ColumnWidths -GridName $GridName -Widths $widths
    }.GetNewClosure()
    $saveTimer.Add_Tick($saveAction)
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

function New-AlertsView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Window]$Window,
        [Parameter(Mandatory=$true)][string]$ScriptDir,
        [switch]$SuppressDialogs
    )
    try {
        $alertsView = ViewCompositionModule\Set-StView -Window $Window -ScriptDir $ScriptDir -ViewName 'AlertsView' -HostControlName 'AlertsHost' -GlobalVariableName 'alertsView'
        if (-not $alertsView) { return }

        $alertsGrid = $alertsView.FindName('AlertsGrid')

        try {
            DeviceInsightsModule\Update-AlertsAsync
        } catch [System.Management.Automation.CommandNotFoundException] {
            try { DeviceInsightsModule\Update-Alerts } catch [System.Management.Automation.CommandNotFoundException] { }
        }

        $expAlertsBtn = $alertsView.FindName('ExportAlertsButton')
        if ($expAlertsBtn) {
            $expAlertsBtn.Add_Click({
                $grid = $alertsView.FindName('AlertsGrid')
                if (-not $grid) { return }
                $rows = @($grid.ItemsSource)
                if ($rows.Count -eq 0) {
                    if (-not $SuppressDialogs) {
                        [System.Windows.MessageBox]::Show('No alerts to export.', 'Export', 'OK', 'Information') | Out-Null
                    }
                    return
                }
                # Confirm large exports
                if ($rows.Count -gt 500 -and -not $SuppressDialogs) {
                    $result = [System.Windows.MessageBox]::Show(
                        "Export $($rows.Count) alerts?",
                        'Confirm Export',
                        [System.Windows.MessageBoxButton]::YesNo,
                        [System.Windows.MessageBoxImage]::Question
                    )
                    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }
                }
                ViewCompositionModule\Export-StRowsWithFormatChoice -Rows $rows -DefaultBaseName 'Alerts' -EmptyMessage 'No alerts to export.' -SuccessNoun 'alerts' -FailureMessagePrefix 'Failed to export alerts' -SuppressDialogs:$SuppressDialogs
            })
        }

        # Context menu handlers
        if ($alertsGrid -and $alertsGrid.ContextMenu) {
            $contextMenu = $alertsGrid.ContextMenu
            $copyRowItem = $contextMenu.Items | Where-Object { $_.Name -eq 'CopyRowMenuItem' } | Select-Object -First 1
            $copyCellItem = $contextMenu.Items | Where-Object { $_.Name -eq 'CopyCellMenuItem' } | Select-Object -First 1
            $copyAllItem = $contextMenu.Items | Where-Object { $_.Name -eq 'CopyAllMenuItem' } | Select-Object -First 1
            $exportSelectedItem = $contextMenu.Items | Where-Object { $_.Name -eq 'ExportSelectedMenuItem' } | Select-Object -First 1

            if ($copyRowItem) {
                $copyRowItem.Add_Click({
                    $selected = $alertsGrid.SelectedItems
                    if ($selected.Count -eq 0) { return }
                    $text = ($selected | ForEach-Object {
                        "$($_.Hostname)`t$($_.Port)`t$($_.Name)`t$($_.Status)`t$($_.VLAN)`t$($_.Duplex)`t$($_.AuthState)`t$($_.Reason)"
                    }) -join "`r`n"
                    [System.Windows.Clipboard]::SetText($text)
                }.GetNewClosure())
            }
            if ($copyCellItem) {
                $copyCellItem.Add_Click({
                    $cell = $alertsGrid.CurrentCell
                    if ($null -eq $cell -or $null -eq $cell.Item) { return }
                    $propName = $cell.Column.SortMemberPath
                    if (-not $propName) { $propName = $cell.Column.Header }
                    $value = $cell.Item.$propName
                    if ($null -ne $value) { [System.Windows.Clipboard]::SetText([string]$value) }
                }.GetNewClosure())
            }
            if ($copyAllItem) {
                $copyAllItem.Add_Click({
                    $rows = $alertsGrid.ItemsSource
                    if (-not $rows -or $rows.Count -eq 0) { return }
                    $header = "Switch`tPort`tName`tStatus`tVLAN`tDuplex`tAuthState`tReason"
                    $lines = @($header) + ($rows | ForEach-Object {
                        "$($_.Hostname)`t$($_.Port)`t$($_.Name)`t$($_.Status)`t$($_.VLAN)`t$($_.Duplex)`t$($_.AuthState)`t$($_.Reason)"
                    })
                    [System.Windows.Clipboard]::SetText($lines -join "`r`n")
                }.GetNewClosure())
            }
            if ($exportSelectedItem) {
                $exportSelectedItem.Add_Click({
                    $selected = @($alertsGrid.SelectedItems)
                    if ($selected.Count -eq 0) {
                        [System.Windows.MessageBox]::Show('No rows selected.', 'Export', 'OK', 'Information') | Out-Null
                        return
                    }
                    ViewCompositionModule\Export-StRowsWithFormatChoice -Rows $selected -DefaultBaseName 'Alerts_Selected' -EmptyMessage 'No rows selected.' -SuccessNoun 'alerts' -FailureMessagePrefix 'Failed to export' -SuppressDialogs:$SuppressDialogs
                }.GetNewClosure())
            }
        }

        # Keyboard shortcuts
        if ($alertsView) {
            $alertsView.Add_PreviewKeyDown({
                param($sender, $e)
                if ($e.Key -eq 'C' -and [System.Windows.Input.Keyboard]::Modifiers -eq 'Control') {
                    # Ctrl+C - Copy selected rows
                    $selected = $alertsGrid.SelectedItems
                    if ($selected.Count -gt 0) {
                        $text = ($selected | ForEach-Object {
                            "$($_.Hostname)`t$($_.Port)`t$($_.Name)`t$($_.Status)`t$($_.Reason)"
                        }) -join "`r`n"
                        [System.Windows.Clipboard]::SetText($text)
                        $e.Handled = $true
                    }
                }
                elseif ($e.Key -eq 'E' -and [System.Windows.Input.Keyboard]::Modifiers -eq 'Control') {
                    # Ctrl+E - Export
                    if ($expAlertsBtn) { $expAlertsBtn.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
                    $e.Handled = $true
                }
            }.GetNewClosure())
        }

        # Column width persistence
        if ($alertsGrid) {
            script:Apply-ColumnWidths -DataGrid $alertsGrid -GridName 'AlertsGrid'
            script:Wire-ColumnWidthPersistence -DataGrid $alertsGrid -GridName 'AlertsGrid'
        }
    } catch {
        Write-Warning "Failed to initialize Alerts view: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function New-AlertsView



