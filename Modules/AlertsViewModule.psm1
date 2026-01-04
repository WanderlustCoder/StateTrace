Set-StrictMode -Version Latest

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
                ViewCompositionModule\Export-StRowsToCsv -Rows $rows -DefaultFileName 'Alerts.csv' -EmptyMessage 'No alerts to export.' -SuccessNoun 'alerts' -FailureMessagePrefix 'Failed to export alerts' -SuppressDialogs:$SuppressDialogs
            })
        }
    } catch {
        Write-Warning "Failed to initialize Alerts view: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function New-AlertsView



