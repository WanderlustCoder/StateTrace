##
# Predefine the search debounce timer variable so that StrictMode does not
# throw when it is referenced before initialisation.  The timer is
# initialised later in New-SearchInterfacesView if needed.
if (-not (Get-Variable -Name SearchUpdateTimer -Scope Script -ErrorAction SilentlyContinue)) {
    $script:SearchUpdateTimer = $null
}

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
    # Text changed triggers debounced search filtering.  A DispatcherTimer is
    # used to coalesce rapid keystrokes into a single update after the user
    # pauses typing.  Without debouncing, Update-SearchGrid would execute on
    # every key press which can noticeably slow the UI when searching large
    # data sets.  The timer is created once and reused across calls.
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
            # variables so that the timer persists across calls.
            $script:SearchUpdateTimer.Stop()
            $script:SearchUpdateTimer.Start()
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
    # Status and Auth filter dropdowns refresh the grid.  Use the same
    # debouncing mechanism as the search box so that multiple rapid
    # selection changes coalesce into one update.
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