Set-StrictMode -Version Latest

function New-SummaryView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Window]$Window,
        [Parameter(Mandatory=$true)][string]$ScriptDir
    )

    $summaryView = ViewCompositionModule\Set-StView -Window $Window -ScriptDir $ScriptDir -ViewName 'SummaryView' -HostControlName 'SummaryHost' -GlobalVariableName 'summaryView'
    if (-not $summaryView) { return }

    $refreshBtn = $summaryView.FindName('RefreshSummaryButton')
    $lastUpdatedText = $summaryView.FindName('SummaryLastUpdatedText')

    $refreshAction = {
        try { DeviceInsightsModule\Update-SummaryAsync } catch {
            try { DeviceInsightsModule\Update-Summary } catch { Write-Verbose "Caught exception in SummaryViewModule.psm1: $($_.Exception.Message)" }
        }
        if ($lastUpdatedText) {
            $lastUpdatedText.Text = "Updated: $(Get-Date -Format 'HH:mm:ss')"
        }
    }.GetNewClosure()

    # Refresh button click
    if ($refreshBtn) {
        $refreshBtn.Add_Click({ & $refreshAction }.GetNewClosure())
    }

    # F5 key to refresh
    $summaryView.Add_PreviewKeyDown({
        param($sender, $e)
        if ($e.Key -eq 'F5') {
            & $refreshAction
            $e.Handled = $true
        }
    }.GetNewClosure())

    # Initial load
    & $refreshAction
}

Export-ModuleMember -Function New-SummaryView
