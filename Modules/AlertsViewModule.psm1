Set-StrictMode -Version Latest

function New-AlertsView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Window]$Window,
        [Parameter(Mandatory=$true)][string]$ScriptDir
    )
    try {
        $alertsView = ViewCompositionModule\Set-StView -Window $Window -ScriptDir $ScriptDir -ViewName 'AlertsView' -HostControlName 'AlertsHost' -GlobalVariableName 'alertsView'
        if (-not $alertsView) { return }

        if (Get-Command -Name 'DeviceInsightsModule\Update-Alerts' -ErrorAction SilentlyContinue) {
            DeviceInsightsModule\Update-Alerts
        }

        $expAlertsBtn = $alertsView.FindName('ExportAlertsButton')
        if ($expAlertsBtn) {
            $expAlertsBtn.Add_Click({
                $grid = $alertsView.FindName('AlertsGrid')
                if (-not $grid) { return }
                $rows = $grid.ItemsSource
                ViewCompositionModule\Export-StRowsToCsv -Rows $rows -DefaultFileName 'Alerts.csv' -EmptyMessage 'No alerts to export.' -SuccessNoun 'alerts' -FailureMessagePrefix 'Failed to export alerts'
            })
        }
    } catch {
        Write-Warning "Failed to initialize Alerts view: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function New-AlertsView



