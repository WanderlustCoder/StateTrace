function New-SummaryView {
    <#
        .SYNOPSIS
            Load and initialise the Summary view.

        .DESCRIPTION
            Loads SummaryView.xaml from the Views folder and sets it as the
            content of the SummaryHost control in the main window.  It
            exposes the view globally via $summaryView and triggers the
            Update-Summary helper (if available) to populate the initial
            metrics.

        .PARAMETER Window
            The main WPF window created by MainWindow.ps1.

        .PARAMETER ScriptDir
            The directory containing the Main scripts.  SummaryView.xaml is
            expected to reside in a ../Views folder relative to this path.
    #>
    param(
        [Parameter(Mandatory=$true)][Windows.Window]$Window,
        [Parameter(Mandatory=$true)][string]$ScriptDir
    )
    $summaryViewPath = Join-Path $ScriptDir '..\Views\SummaryView.xaml'
    if (-not (Test-Path $summaryViewPath)) {
        Write-Warning "SummaryView.xaml not found at $summaryViewPath"
        return
    }
    $summaryXaml   = Get-Content $summaryViewPath -Raw
    $reader        = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($summaryXaml))
    $summaryView   = [Windows.Markup.XamlReader]::Load($reader)
    $summaryHost   = $Window.FindName('SummaryHost')
    if ($summaryHost -is [System.Windows.Controls.ContentControl]) {
        $summaryHost.Content = $summaryView
    } else {
        Write-Warning "Could not find ContentControl 'SummaryHost'"
    }
    # Expose globally to support updates
    $global:summaryView = $summaryView
    # Immediately update metrics if the helper is present
    if (Get-Command Update-Summary -ErrorAction SilentlyContinue) {
        Update-Summary
    }
}

Export-ModuleMember -Function New-SummaryView