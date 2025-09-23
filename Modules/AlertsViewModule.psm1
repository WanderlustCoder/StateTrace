function New-AlertsView {
    
    param(
        [Parameter(Mandatory=$true)][System.Windows.Window]$Window,
        [Parameter(Mandatory=$true)][string]$ScriptDir
    )
    $alertsViewPath = Join-Path $ScriptDir '..\Views\AlertsView.xaml'
    if (-not (Test-Path $alertsViewPath)) {
        Write-Warning "AlertsView.xaml not found at $alertsViewPath"
        return
    }
    $alertXaml   = Get-Content $alertsViewPath -Raw
    $reader      = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($alertXaml))
    try {
        $alertsView = [Windows.Markup.XamlReader]::Load($reader)
        $alertsHost = $Window.FindName('AlertsHost')
        if ($alertsHost -is [System.Windows.Controls.ContentControl]) {
            $alertsHost.Content = $alertsView
        } else {
            Write-Warning "Could not find ContentControl 'AlertsHost'"
        }
        # Expose globally
        $global:alertsView = $alertsView
        # Compute alerts immediately using GuiModule helper, if available
        if (Get-Command Update-Alerts -ErrorAction SilentlyContinue) {
            Update-Alerts
        }
        # Wire up export button
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
        Write-Warning "Failed to load AlertsView: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function New-AlertsView