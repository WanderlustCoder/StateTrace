Set-StrictMode -Version Latest

if (-not (Get-Variable -Name SearchUpdateTimer -Scope Script -ErrorAction SilentlyContinue)) {
    $script:SearchUpdateTimer = $null
}

function New-SearchInterfacesView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Window]$Window,
        [Parameter(Mandatory=$true)][string]$ScriptDir,
        [switch]$SuppressDialogs
    )

    $requestSearchUpdate = {
        try { DeviceInsightsModule\Update-SearchGridAsync } catch {
            try { DeviceInsightsModule\Update-SearchGrid } catch { }
        }
    }

    $searchView = ViewCompositionModule\Set-StView -Window $Window -ScriptDir $ScriptDir -ViewName 'SearchInterfacesView' -HostControlName 'SearchInterfacesHost' -GlobalVariableName 'searchInterfacesView'
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
            & $requestSearchUpdate
        }.GetNewClosure())
    }
    # Text changed triggers debounced search filtering.  A DispatcherTimer is
    if ($searchBox) {
        # Initialise the debounce timer only once per module load
        if (-not $script:SearchUpdateTimer) {
            $script:SearchUpdateTimer = ViewCompositionModule\New-StDebounceTimer -DelayMs 300 -Action $requestSearchUpdate
        }
        $searchBox.Add_TextChanged({
            # Each keystroke resets the debounce timer.  Use script scope
            if ($script:SearchUpdateTimer) {
                $script:SearchUpdateTimer.Stop()
                $script:SearchUpdateTimer.Start()
            }
        })
    }
    # Regex checkbox toggles global flag and refreshes
    if ($regexCheckbox) {
        $regexCheckbox.Add_Checked({
            DeviceInsightsModule\Set-SearchRegexEnabled -Enabled:$true
            & $requestSearchUpdate
        }.GetNewClosure())
        $regexCheckbox.Add_Unchecked({
            DeviceInsightsModule\Set-SearchRegexEnabled -Enabled:$false
            & $requestSearchUpdate
        }.GetNewClosure())
    }
    # Export button writes current search results to CSV
    if ($exportBtn) {
        $exportBtn.Add_Click({
            if (-not $searchGrid) { return }
            $rows = $searchGrid.ItemsSource
            ViewCompositionModule\Export-StRowsToCsv -Rows $rows -DefaultFileName 'SearchResults.csv' -EmptyMessage 'No results to export.' -SuccessNoun 'rows' -FailureMessagePrefix 'Failed to export' -SuppressDialogs:$SuppressDialogs
        }.GetNewClosure())
    }
    # Status and Auth filter dropdowns refresh the grid.  Use the same
    $restartSearchDebounce = {
        if ($script:SearchUpdateTimer) {
            $script:SearchUpdateTimer.Stop()
            $script:SearchUpdateTimer.Start()
        } else {
            & $requestSearchUpdate
        }
    }.GetNewClosure()
    if ($statusFilter) {
        $statusFilter.Add_SelectionChanged({
            & $restartSearchDebounce
        }.GetNewClosure())
    }
    if ($authFilter) {
        $authFilter.Add_SelectionChanged({
            & $restartSearchDebounce
        }.GetNewClosure())
    }
    # Delay heavy site-wide load until the user searches.
    if ($searchGrid) { $searchGrid.ItemsSource = @() }
}

Export-ModuleMember -Function New-SearchInterfacesView

