##
if (-not (Get-Variable -Name SearchUpdateTimer -Scope Script -ErrorAction SilentlyContinue)) {
    $script:SearchUpdateTimer = $null
}

function New-SearchInterfacesView {
    
    param(
        [Parameter(Mandatory=$true)][System.Windows.Window]$Window,
        [Parameter(Mandatory=$true)][string]$ScriptDir
    )
    $searchView = Set-StView -Window $Window -ScriptDir $ScriptDir -ViewName 'SearchInterfacesView' -HostControlName 'SearchInterfacesHost' -GlobalVariableName 'searchInterfacesView'
    if (-not $searchView) { return }
    # Acquire controls
    $searchBox      = $searchView.FindName('SearchBox')
    $searchClearBtn = $searchView.FindName('SearchClearButton')
    $searchGrid     = $searchView.FindName('SearchInterfacesGrid')
    $regexCheckbox  = $searchView.FindName('RegexCheckbox')
    $exportBtn      = $searchView.FindName('ExportSearchButton')
    $statusFilter   = $searchView.FindName('StatusFilter')
    $authFilter     = $searchView.FindName('AuthFilter')

    # Promote search box to the global scope so that its Text property can be
    if ($searchBox) { $global:searchBox = $searchBox }
    # Initialise regex flag
    DeviceInsightsModule\Set-SearchRegexEnabled -Enabled:$false
    # Clear button resets the search box and refreshes
    if ($searchClearBtn -and $searchBox) {
        $searchClearBtn.Add_Click({
            # reset the globally scoped search box so the handler always works
            $global:searchBox.Text = ''
            if (Get-Command Update-SearchGrid -ErrorAction SilentlyContinue) { Update-SearchGrid }
        })
    }
    # Text changed triggers debounced search filtering.  A DispatcherTimer is
    if ($searchBox) {
        # Initialise the debounce timer only once per module load
        if (-not $script:SearchUpdateTimer) {
            $script:SearchUpdateTimer = New-Object System.Windows.Threading.DispatcherTimer
            # 300ms delay to allow user input to settle before filtering
            $script:SearchUpdateTimer.Interval = [TimeSpan]::FromMilliseconds(300)
            $script:SearchUpdateTimer.add_Tick({
                # Stop the timer until the next request
                $script:SearchUpdateTimer.Stop()
                # Perform the actual grid update
                if (Get-Command Update-SearchGrid -ErrorAction SilentlyContinue) { Update-SearchGrid }
            })
        }
        $searchBox.Add_TextChanged({
            # Each keystroke resets the debounce timer.  Use script scope
            $script:SearchUpdateTimer.Stop()
            $script:SearchUpdateTimer.Start()
        })
    }
    # Regex checkbox toggles global flag and refreshes
    if ($regexCheckbox) {
        $regexCheckbox.Add_Checked({
            DeviceInsightsModule\Set-SearchRegexEnabled -Enabled:$true
            if (Get-Command Update-SearchGrid -ErrorAction SilentlyContinue) { Update-SearchGrid }
        })
        $regexCheckbox.Add_Unchecked({
            DeviceInsightsModule\Set-SearchRegexEnabled -Enabled:$false
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
    # Status and Auth filter dropdowns refresh the grid.  Use the same
    if ($statusFilter) {
        $statusFilter.Add_SelectionChanged({
            $script:SearchUpdateTimer.Stop()
            $script:SearchUpdateTimer.Start()
        })
    }
    if ($authFilter) {
        $authFilter.Add_SelectionChanged({
            $script:SearchUpdateTimer.Stop()
            $script:SearchUpdateTimer.Start()
        })
    }
    # Delay heavy site-wide load until the user searches.
    if ($searchGrid) { $searchGrid.ItemsSource = @() }
}

Export-ModuleMember -Function New-SearchInterfacesView



