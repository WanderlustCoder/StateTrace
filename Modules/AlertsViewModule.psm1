function New-AlertsView {
    
    param(
        [Parameter(Mandatory=$true)][System.Windows.Window]$Window,
        [Parameter(Mandatory=$true)][string]$ScriptDir
    )
    try {
        $alertsView = New-StView -Window $Window -ScriptDir $ScriptDir -ViewName 'AlertsView' -HostControlName 'AlertsHost' -GlobalVariableName 'alertsView'
        if (-not $alertsView) { return }

        if (Get-Command Update-Alerts -ErrorAction SilentlyContinue) {
            Update-Alerts
        }

        $expAlertsBtn = $alertsView.FindName('ExportAlertsButton')
        if ($expAlertsBtn) {
            $expAlertsBtn.Add_Click({
                $grid = $alertsView.FindName('AlertsGrid')
                if (-not $grid) { return }
                $rows = $grid.ItemsSource
                if (-not $rows -or $rows.Count -eq 0) {
                    [System.Windows.MessageBox]::Show('No alerts to export.')
                    return
                }
                $dlg = New-Object Microsoft.Win32.SaveFileDialog
                $dlg.Filter = 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'
                $dlg.FileName = 'Alerts.csv'
                if ($dlg.ShowDialog() -eq $true) {
                    $path = $dlg.FileName
                    try {
                        $rows | Export-Csv -Path $path -NoTypeInformation
                        [System.Windows.MessageBox]::Show("Exported $($rows.Count) alerts to $path", 'Export Complete')
                    } catch {
                        [System.Windows.MessageBox]::Show("Failed to export alerts: $($_.Exception.Message)")
                    }
                }
            })
        }
    } catch {
        Write-Warning "Failed to initialize Alerts view: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function New-AlertsView




