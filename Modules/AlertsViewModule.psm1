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
                $rows = $grid.ItemsSource
                ViewCompositionModule\Export-StRowsWithFormatChoice -Rows $rows -DefaultBaseName 'Alerts' -EmptyMessage 'No alerts to export.' -SuccessNoun 'alerts' -FailureMessagePrefix 'Failed to export alerts' -SuppressDialogs:$SuppressDialogs
            })
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



