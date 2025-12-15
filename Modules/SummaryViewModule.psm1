Set-StrictMode -Version Latest

function New-SummaryView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Window]$Window,
        [Parameter(Mandatory=$true)][string]$ScriptDir
    )

    $summaryView = ViewCompositionModule\Set-StView -Window $Window -ScriptDir $ScriptDir -ViewName 'SummaryView' -HostControlName 'SummaryHost' -GlobalVariableName 'summaryView'
    if (-not $summaryView) { return }

    try { DeviceInsightsModule\Update-Summary } catch { }
}

Export-ModuleMember -Function New-SummaryView
