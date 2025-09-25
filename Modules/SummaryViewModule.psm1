function New-SummaryView {
    
    param(
        [Parameter(Mandatory=$true)][System.Windows.Window]$Window,
        [Parameter(Mandatory=$true)][string]$ScriptDir
    )
    $summaryView = New-StView -Window $Window -ScriptDir $ScriptDir -ViewName 'SummaryView' -HostControlName 'SummaryHost' -GlobalVariableName 'summaryView'
    if (-not $summaryView) { return }

    if (Get-Command Update-Summary -ErrorAction SilentlyContinue) {
        Update-Summary
    }
}

Export-ModuleMember -Function New-SummaryView


