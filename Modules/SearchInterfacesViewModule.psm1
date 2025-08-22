function New-SearchInterfacesView {
    <#
        .SYNOPSIS
            Load and initialise the SearchInterfaces view.

        .DESCRIPTION
            This function loads the SearchInterfacesView.xaml file, inserts it into
            the host window and wires up event handlers for search filtering,
            regex toggling, exporting and status/auth filtering.  It relies on
            helper functions such as Update-SearchResults, Update-SearchGrid
            and Update-GlobalInterfaceList provided by GuiModule.psm1.

        .PARAMETER Window
            The main WPF window created by MainWindow.ps1.

        .PARAMETER ScriptDir
            The directory containing the Main scripts.  The view XAML is
            expected to reside in a ../Views folder relative to this path.
    #>
    param(
        [Parameter(Mandatory=$true)][Windows.Window]$Window,
        [Parameter(Mandatory=$true)][string]$ScriptDir
    )
    $searchXamlPath = Join-Path $ScriptDir '..\Views\SearchInterfacesView.xaml'
    if (-not (Test-Path $searchXamlPath)) {
        Write-Warning "SearchInterfacesView.xaml not found at $searchXamlPath"
        return
    }
    $searchXaml   = Get-Content $searchXamlPath -Raw
    $reader       = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($searchXaml))
    $searchView   = [Windows.Markup.XamlReader]::Load($reader)
    # Host injection
    $searchHost   = $Window.FindName('SearchInterfacesHost')
    if ($searchHost -is [System.Windows.Controls.ContentControl]) {
        $searchHost.Content = $searchView
    } else {
        Write-Warning "Could not find ContentControl 'SearchInterfacesHost'"
    }
    # Expose view globally
    $global:searchInterfacesView = $searchView
    # Acquire controls
    $searchBox      = $searchView.FindName('SearchBox')
    $searchClearBtn = $searchView.FindName('SearchClearButton')
    $searchGrid     = $searchView.FindName('SearchInterfacesGrid')
    $regexCheckbox  = $searchView.FindName('RegexCheckbox')
    $exportBtn      = $searchView.FindName('ExportSearchButton')
    $statusFilter   = $searchView.FindName('StatusFilter')
    $authFilter     = $searchView.FindName('AuthFilter')

    # Promote search box to the global scope so that its Text property can be
    # referenced from event handlers after this function completes.  See
    # FurtherFixes.docx step 2 – without this, the $searchBox variable goes
    # out of scope and the TextChanged scriptblock cannot access it.
    if ($searchBox) { $global:searchBox = $searchBox }
    # Initialise regex flag
    $script:SearchRegexEnabled = $false
    # Clear button resets the search box and refreshes
    if ($searchClearBtn -and $searchBox) {
        $searchClearBtn.Add_Click({
            # reset the globally scoped search box so the handler always works
            $global:searchBox.Text = ''
            if (Get-Command Update-SearchGrid -ErrorAction SilentlyContinue) { Update-SearchGrid }
        })
    }
    # Text changed triggers live search filtering
    if ($searchBox) {
        $searchBox.Add_TextChanged({
                Update-SearchGrid            
        })
    }
    # Regex checkbox toggles global flag and refreshes
    if ($regexCheckbox) {
        $regexCheckbox.Add_Checked({
            $script:SearchRegexEnabled = $true
            if (Get-Command Update-SearchGrid -ErrorAction SilentlyContinue) { Update-SearchGrid }
        })
        $regexCheckbox.Add_Unchecked({
            $script:SearchRegexEnabled = $false
            if (Get-Command Update-SearchGrid -ErrorAction SilentlyContinue) { Update-SearchGrid }
        })
    }
    # Export button writes current search results to CSV
    if ($exportBtn) {
        $exportBtn.Add_Click({
            if (-not $searchGrid) { return }
            $rows = $searchGrid.ItemsSource
            if (-not $rows -or $rows.Count -eq 0) {
                [System.Windows.MessageBox]::Show('No results to export.')
                return
            }
            $dlg = New-Object Microsoft.Win32.SaveFileDialog
            $dlg.Filter = 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'
            $dlg.FileName = 'SearchResults.csv'
            if ($dlg.ShowDialog() -eq $true) {
                $path = $dlg.FileName
                try {
                    $rows | Export-Csv -Path $path -NoTypeInformation
                    [System.Windows.MessageBox]::Show("Exported $($rows.Count) rows to $path", 'Export Complete')
                } catch {
                    [System.Windows.MessageBox]::Show("Failed to export: $($_.Exception.Message)")
                }
            }
        })
    }
    # Status and Auth filter dropdowns refresh the grid
    if ($statusFilter) {
        $statusFilter.Add_SelectionChanged({
            if (Get-Command Update-SearchGrid -ErrorAction SilentlyContinue) { Update-SearchGrid }
        })
    }
    if ($authFilter) {
        $authFilter.Add_SelectionChanged({
            if (Get-Command Update-SearchGrid -ErrorAction SilentlyContinue) { Update-SearchGrid }
        })
    }
    # Delay heavy site-wide load until the user searches.
    if ($searchGrid) { $searchGrid.ItemsSource = @() }
}

Export-ModuleMember -Function New-SearchInterfacesView