Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Creates and initializes the Log Analysis view.

.DESCRIPTION
    Loads LogAnalysisView.xaml using ViewCompositionModule, wires up event handlers,
    and provides log import, parsing, pattern detection, and search functionality.

.PARAMETER Window
    The parent MainWindow instance.

.PARAMETER ScriptDir
    The root script directory for locating XAML files.

.OUTPUTS
    System.Windows.Controls.UserControl - The initialized view.
#>
function New-LogAnalysisView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory=$true)]
        [string]$ScriptDir
    )

    try {
        $view = ViewCompositionModule\Set-StView -Window $Window -ScriptDir $ScriptDir `
            -ViewName 'LogAnalysisView' -HostControlName 'LogAnalysisHost' `
            -GlobalVariableName 'logAnalysisView'
        if (-not $view) { return }

        # Get controls from the view
        $importFileButton = $view.FindName('ImportFileButton')
        $pasteLogsButton = $view.FindName('PasteLogsButton')
        $formatDropdown = $view.FindName('FormatDropdown')
        $defaultHostnameBox = $view.FindName('DefaultHostnameBox')
        $clearLogsButton = $view.FindName('ClearLogsButton')
        $analyzeButton = $view.FindName('AnalyzeButton')
        $summaryText = $view.FindName('SummaryText')
        $criticalCount = $view.FindName('CriticalCount')
        $warningCount = $view.FindName('WarningCount')
        $noticeCount = $view.FindName('NoticeCount')
        $patternListBox = $view.FindName('PatternListBox')
        $searchKeywordBox = $view.FindName('SearchKeywordBox')
        $severityFilterDropdown = $view.FindName('SeverityFilterDropdown')
        $deviceFilterDropdown = $view.FindName('DeviceFilterDropdown')
        $searchButton = $view.FindName('SearchButton')
        $entryCountText = $view.FindName('EntryCountText')
        $exportButton = $view.FindName('ExportButton')
        $copySelectedButton = $view.FindName('CopySelectedButton')
        $logEntriesGrid = $view.FindName('LogEntriesGrid')
        $detailsPanel = $view.FindName('DetailsPanel')
        $detailsTitleText = $view.FindName('DetailsTitleText')
        $detailsContentBox = $view.FindName('DetailsContentBox')
        $statusText = $view.FindName('StatusText')
        $timeRangeText = $view.FindName('TimeRangeText')
        $formatText = $view.FindName('FormatText')

        # Store state in view's Tag
        $view.Tag = @{
            AllEntries = @()
            FilteredEntries = @()
            Patterns = @()
            ImportResult = $null
        }

        # Helper to get selected format
        function Get-SelectedFormat {
            $selected = $formatDropdown.SelectedItem
            if (-not $selected) { return 'Auto' }
            $content = $selected.Content
            switch ($content) {
                'Cisco IOS' { return 'CiscoIOS' }
                'Arista EOS' { return 'AristaEOS' }
                'RFC 5424' { return 'RFC5424' }
                'RFC 3164' { return 'RFC3164' }
                'Generic' { return 'Generic' }
                default { return 'Auto' }
            }
        }

        # Helper to update the summary display
        function Update-Summary {
            $entries = $view.Tag.AllEntries
            if ($entries.Count -eq 0) {
                $summaryText.Text = 'No logs loaded'
                $criticalCount.Text = '0 Critical'
                $warningCount.Text = '0 Warning'
                $noticeCount.Text = '0 Notice'
                $entryCountText.Text = '(0 entries)'
                $timeRangeText.Text = ''
                $formatText.Text = ''
                return
            }

            $stats = LogAnalysisModule\Get-LogSeverityStats -Entries $entries
            $devices = @($entries | ForEach-Object { $_.Hostname } | Where-Object { $_ } | Select-Object -Unique)
            $criticalTotal = $stats.Emergency + $stats.Alert + $stats.Critical
            $warningTotal = $stats.Error + $stats.Warning
            $noticeTotal = $stats.Notice + $stats.Informational + $stats.Debug

            $summaryText.Text = "$($entries.Count) entries | $($devices.Count) device(s)"
            $criticalCount.Text = "$criticalTotal Critical"
            $warningCount.Text = "$warningTotal Warning"
            $noticeCount.Text = "$noticeTotal Notice"

            # Time range
            $entriesWithTime = @($entries | Where-Object { $_.Timestamp })
            if ($entriesWithTime.Count -gt 0) {
                $sorted = $entriesWithTime | Sort-Object { $_.Timestamp }
                $start = $sorted[0].Timestamp.ToString('yyyy-MM-dd HH:mm')
                $end = $sorted[$sorted.Count - 1].Timestamp.ToString('yyyy-MM-dd HH:mm')
                $timeRangeText.Text = "Time: $start to $end"
            }

            # Format
            $importResult = $view.Tag.ImportResult
            if ($importResult -and $importResult.DetectedFormat) {
                $formatText.Text = "Format: $($importResult.DetectedFormat)"
            }

            # Update device filter dropdown
            $deviceFilterDropdown.Items.Clear()
            $allItem = New-Object System.Windows.Controls.ComboBoxItem
            $allItem.Content = 'All Devices'
            $allItem.IsSelected = $true
            $deviceFilterDropdown.Items.Add($allItem) | Out-Null
            foreach ($device in ($devices | Sort-Object)) {
                $item = New-Object System.Windows.Controls.ComboBoxItem
                $item.Content = $device
                $deviceFilterDropdown.Items.Add($item) | Out-Null
            }
        }

        # Helper to update the grid
        function Update-Grid {
            param([array]$Entries)
            $view.Tag.FilteredEntries = $Entries
            $logEntriesGrid.ItemsSource = $Entries
            $entryCountText.Text = "($($Entries.Count) entries)"
        }

        # Helper to run analysis
        function Run-Analysis {
            $entries = $view.Tag.AllEntries
            if ($entries.Count -eq 0) {
                $patternListBox.ItemsSource = @()
                return
            }

            $statusText.Text = 'Analyzing patterns...'
            try {
                $patterns = @(LogAnalysisModule\Find-LogPatterns -Entries $entries)
                $view.Tag.Patterns = $patterns

                # Add color property for display
                $displayPatterns = @($patterns | ForEach-Object {
                    $color = switch ($_.Severity) {
                        'Critical' { 'Red' }
                        'Error' { 'OrangeRed' }
                        'Warning' { 'Orange' }
                        'Notice' { 'DodgerBlue' }
                        default { 'Gray' }
                    }
                    [pscustomobject]@{
                        PatternName = $_.PatternName
                        Description = $_.Description
                        MatchCount = $_.MatchCount
                        Severity = $_.Severity
                        SeverityColor = $color
                        Pattern = $_
                    }
                })

                $patternListBox.ItemsSource = $displayPatterns
                $statusText.Text = "Found $($patterns.Count) pattern(s)"
            } catch {
                $statusText.Text = "Analysis error: $($_.Exception.Message)"
            }
        }

        # Helper to apply search filters
        function Apply-Filters {
            $entries = $view.Tag.AllEntries
            if ($entries.Count -eq 0) {
                Update-Grid -Entries @()
                return
            }

            $keyword = $searchKeywordBox.Text
            $sevSelected = $severityFilterDropdown.SelectedItem
            $devSelected = $deviceFilterDropdown.SelectedItem

            $params = @{ Entries = $entries }

            if (-not [string]::IsNullOrWhiteSpace($keyword)) {
                $params['Keyword'] = $keyword
            }

            if ($sevSelected -and $sevSelected.Content -ne 'All Severities') {
                switch ($sevSelected.Content) {
                    'Critical (0-2)' { $params['MaxSeverity'] = 2 }
                    'Error (3)' { $params['MaxSeverity'] = 3; $params['MinSeverity'] = 3 }
                    'Warning (4)' { $params['MaxSeverity'] = 4; $params['MinSeverity'] = 4 }
                    'Notice (5)' { $params['MaxSeverity'] = 5; $params['MinSeverity'] = 5 }
                    'Info (6-7)' { $params['MinSeverity'] = 6 }
                }
            }

            if ($devSelected -and $devSelected.Content -ne 'All Devices') {
                $params['Device'] = $devSelected.Content
            }

            try {
                $filtered = @(LogAnalysisModule\Search-LogEntries @params)
                Update-Grid -Entries $filtered
                $statusText.Text = "Showing $($filtered.Count) of $($entries.Count) entries"
            } catch {
                $statusText.Text = "Filter error: $($_.Exception.Message)"
            }
        }

        # Import File button click
        $importFileButton.Add_Click({
            param($sender, $e)
            try {
                $dialog = New-Object Microsoft.Win32.OpenFileDialog
                $dialog.Title = 'Select Log File'
                $dialog.Filter = 'Log files (*.log;*.txt)|*.log;*.txt|All files (*.*)|*.*'
                $dialog.Multiselect = $false

                if ($dialog.ShowDialog() -eq $true) {
                    $format = Get-SelectedFormat
                    $hostname = $defaultHostnameBox.Text

                    $statusText.Text = "Importing $($dialog.FileName)..."

                    $result = LogAnalysisModule\Import-LogFile -Path $dialog.FileName -Format $format -DefaultHostname $hostname
                    $view.Tag.AllEntries = $result.Entries
                    $view.Tag.ImportResult = $result

                    Update-Summary
                    Update-Grid -Entries $result.Entries
                    Run-Analysis

                    if ($result.ErrorCount -gt 0) {
                        $statusText.Text = "Imported $($result.ImportedCount) entries ($($result.ErrorCount) errors)"
                    } else {
                        $statusText.Text = "Imported $($result.ImportedCount) entries"
                    }
                }
            } catch {
                $statusText.Text = "Import error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Paste Logs button click
        $pasteLogsButton.Add_Click({
            param($sender, $e)
            try {
                $clipText = [System.Windows.Clipboard]::GetText()
                if ([string]::IsNullOrWhiteSpace($clipText)) {
                    $statusText.Text = 'Clipboard is empty'
                    return
                }

                $lines = $clipText -split "`r?`n"
                $format = Get-SelectedFormat
                $hostname = $defaultHostnameBox.Text

                $statusText.Text = "Parsing $($lines.Count) lines..."

                $result = LogAnalysisModule\Import-LogEntries -Entries $lines -Format $format -DefaultHostname $hostname
                $view.Tag.AllEntries = $result.Entries
                $view.Tag.ImportResult = $result

                Update-Summary
                Update-Grid -Entries $result.Entries
                Run-Analysis

                $statusText.Text = "Parsed $($result.ImportedCount) entries from clipboard"
            } catch {
                $statusText.Text = "Parse error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Clear button click
        $clearLogsButton.Add_Click({
            param($sender, $e)
            $view.Tag.AllEntries = @()
            $view.Tag.FilteredEntries = @()
            $view.Tag.Patterns = @()
            $view.Tag.ImportResult = $null

            $logEntriesGrid.ItemsSource = @()
            $patternListBox.ItemsSource = @()
            Update-Summary
            $detailsPanel.Visibility = 'Collapsed'
            $statusText.Text = 'Cleared all logs'
        }.GetNewClosure())

        # Analyze button click
        $analyzeButton.Add_Click({
            param($sender, $e)
            Run-Analysis
        }.GetNewClosure())

        # Search button click
        $searchButton.Add_Click({
            param($sender, $e)
            Apply-Filters
        }.GetNewClosure())

        # Search on Enter key
        $searchKeywordBox.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Return') {
                Apply-Filters
            }
        }.GetNewClosure())

        # Pattern selection change
        $patternListBox.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if ($selected -and $selected.Pattern) {
                $matchedEntries = $selected.Pattern.MatchedEntries
                if ($matchedEntries) {
                    Update-Grid -Entries $matchedEntries
                    $statusText.Text = "Showing $($matchedEntries.Count) entries for pattern: $($selected.PatternName)"
                }
            }
        }.GetNewClosure())

        # Grid selection change - show details
        $logEntriesGrid.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if ($selected) {
                $detailsPanel.Visibility = 'Visible'
                $detailsTitleText.Text = "$($selected.MessageType) - $($selected.SeverityName)"
                $detailsContentBox.Text = $selected.RawEntry
            } else {
                $detailsPanel.Visibility = 'Collapsed'
            }
        }.GetNewClosure())

        # Copy selected button
        $copySelectedButton.Add_Click({
            param($sender, $e)
            $selected = @($logEntriesGrid.SelectedItems)
            if ($selected.Count -gt 0) {
                $text = ($selected | ForEach-Object { $_.RawEntry }) -join "`r`n"
                [System.Windows.Clipboard]::SetText($text)
                $statusText.Text = "Copied $($selected.Count) entries to clipboard"
            }
        }.GetNewClosure())

        # Export button
        $exportButton.Add_Click({
            param($sender, $e)
            $entries = $view.Tag.FilteredEntries
            if ($entries.Count -eq 0) {
                $statusText.Text = 'No entries to export'
                return
            }

            try {
                $dialog = New-Object Microsoft.Win32.SaveFileDialog
                $dialog.Title = 'Export Log Entries'
                $dialog.Filter = 'CSV files (*.csv)|*.csv|Text files (*.txt)|*.txt'
                $dialog.DefaultExt = '.csv'

                if ($dialog.ShowDialog() -eq $true) {
                    if ($dialog.FileName -match '\.csv$') {
                        $entries | Export-Csv -Path $dialog.FileName -NoTypeInformation
                    } else {
                        ($entries | ForEach-Object { $_.RawEntry }) | Out-File -FilePath $dialog.FileName
                    }
                    $statusText.Text = "Exported $($entries.Count) entries to $($dialog.FileName)"
                }
            } catch {
                $statusText.Text = "Export error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Initialize
        $statusText.Text = 'Ready - Import or paste log entries to begin'

        return $view

    } catch {
        Write-Warning "Failed to initialize LogAnalysis view: $($_.Exception.Message)"
    }
}

function Initialize-LogAnalysisView {
    <#
    .SYNOPSIS
        Initializes the Log Analysis view for nested tab container use.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ContentControl]$Host
    )

    try {
        $viewPath = Join-Path $PSScriptRoot '..\Views\LogAnalysisView.xaml'
        if (-not (Test-Path $viewPath)) {
            Write-Warning "LogAnalysisView.xaml not found at: $viewPath"
            return
        }

        $xamlContent = Get-Content -Path $viewPath -Raw
        $xamlContent = $xamlContent -replace 'x:Class="[^"]*"', ''
        $xamlContent = $xamlContent -replace 'mc:Ignorable="d"', ''

        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlContent))
        $view = [System.Windows.Markup.XamlReader]::Load($reader)
        $Host.Content = $view

        # Initialize controls and event handlers
        Initialize-LogAnalysisControls -View $view

        return $view
    }
    catch {
        Write-Warning "Failed to initialize LogAnalysis view: $($_.Exception.Message)"
    }
}

function Initialize-LogAnalysisControls {
    <#
    .SYNOPSIS
        Wires up controls and event handlers for the Log Analysis view.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    # Get controls
    $importFileButton = $View.FindName('ImportFileButton')
    $pasteLogsButton = $View.FindName('PasteLogsButton')
    $formatDropdown = $View.FindName('FormatDropdown')
    $defaultHostnameBox = $View.FindName('DefaultHostnameBox')
    $clearLogsButton = $View.FindName('ClearLogsButton')
    $analyzeButton = $View.FindName('AnalyzeButton')
    $summaryText = $View.FindName('SummaryText')
    $criticalCount = $View.FindName('CriticalCount')
    $warningCount = $View.FindName('WarningCount')
    $noticeCount = $View.FindName('NoticeCount')
    $patternListBox = $View.FindName('PatternListBox')
    $searchKeywordBox = $View.FindName('SearchKeywordBox')
    $severityFilterDropdown = $View.FindName('SeverityFilterDropdown')
    $deviceFilterDropdown = $View.FindName('DeviceFilterDropdown')
    $searchButton = $View.FindName('SearchButton')
    $entryCountText = $View.FindName('EntryCountText')
    $exportButton = $View.FindName('ExportButton')
    $copySelectedButton = $View.FindName('CopySelectedButton')
    $logEntriesGrid = $View.FindName('LogEntriesGrid')
    $detailsPanel = $View.FindName('DetailsPanel')
    $detailsTitleText = $View.FindName('DetailsTitleText')
    $detailsContentBox = $View.FindName('DetailsContentBox')
    $statusText = $View.FindName('StatusText')
    $timeRangeText = $View.FindName('TimeRangeText')
    $formatText = $View.FindName('FormatText')

    # Store state in view's Tag
    $View.Tag = @{ AllEntries = @(); FilteredEntries = @(); Patterns = @(); ImportResult = $null }

    # Helper scriptblocks
    $getSelectedFormat = {
        $selected = $formatDropdown.SelectedItem
        if (-not $selected) { return 'Auto' }
        $content = $selected.Content
        switch ($content) { 'Cisco IOS' { return 'CiscoIOS' }; 'Arista EOS' { return 'AristaEOS' }; 'RFC 5424' { return 'RFC5424' }; 'RFC 3164' { return 'RFC3164' }; 'Generic' { return 'Generic' }; default { return 'Auto' } }
    }

    $updateSummary = {
        $entries = $View.Tag.AllEntries
        if ($entries.Count -eq 0) {
            if ($summaryText) { $summaryText.Text = 'No logs loaded' }
            if ($criticalCount) { $criticalCount.Text = '0 Critical' }
            if ($warningCount) { $warningCount.Text = '0 Warning' }
            if ($noticeCount) { $noticeCount.Text = '0 Notice' }
            if ($entryCountText) { $entryCountText.Text = '(0 entries)' }
            if ($timeRangeText) { $timeRangeText.Text = '' }
            if ($formatText) { $formatText.Text = '' }
            return
        }
        $stats = LogAnalysisModule\Get-LogSeverityStats -Entries $entries
        $devices = @($entries | ForEach-Object { $_.Hostname } | Where-Object { $_ } | Select-Object -Unique)
        $criticalTotal = $stats.Emergency + $stats.Alert + $stats.Critical
        $warningTotal = $stats.Error + $stats.Warning
        $noticeTotal = $stats.Notice + $stats.Informational + $stats.Debug
        if ($summaryText) { $summaryText.Text = "$($entries.Count) entries | $($devices.Count) device(s)" }
        if ($criticalCount) { $criticalCount.Text = "$criticalTotal Critical" }
        if ($warningCount) { $warningCount.Text = "$warningTotal Warning" }
        if ($noticeCount) { $noticeCount.Text = "$noticeTotal Notice" }
        $entriesWithTime = @($entries | Where-Object { $_.Timestamp })
        if ($entriesWithTime.Count -gt 0) {
            $sorted = $entriesWithTime | Sort-Object { $_.Timestamp }
            $start = $sorted[0].Timestamp.ToString('yyyy-MM-dd HH:mm')
            $end = $sorted[$sorted.Count - 1].Timestamp.ToString('yyyy-MM-dd HH:mm')
            if ($timeRangeText) { $timeRangeText.Text = "Time: $start to $end" }
        }
        $importResult = $View.Tag.ImportResult
        if ($importResult -and $importResult.DetectedFormat -and $formatText) { $formatText.Text = "Format: $($importResult.DetectedFormat)" }
        if ($deviceFilterDropdown) {
            $deviceFilterDropdown.Items.Clear()
            $allItem = New-Object System.Windows.Controls.ComboBoxItem; $allItem.Content = 'All Devices'; $allItem.IsSelected = $true; $deviceFilterDropdown.Items.Add($allItem) | Out-Null
            foreach ($device in ($devices | Sort-Object)) { $item = New-Object System.Windows.Controls.ComboBoxItem; $item.Content = $device; $deviceFilterDropdown.Items.Add($item) | Out-Null }
        }
    }

    $updateGrid = { param([array]$Entries); $View.Tag.FilteredEntries = $Entries; if ($logEntriesGrid) { $logEntriesGrid.ItemsSource = $Entries }; if ($entryCountText) { $entryCountText.Text = "($($Entries.Count) entries)" } }

    $runAnalysis = {
        $entries = $View.Tag.AllEntries
        if ($entries.Count -eq 0) { if ($patternListBox) { $patternListBox.ItemsSource = @() }; return }
        if ($statusText) { $statusText.Text = 'Analyzing patterns...' }
        try {
            $patterns = @(LogAnalysisModule\Find-LogPatterns -Entries $entries)
            $View.Tag.Patterns = $patterns
            $displayPatterns = @($patterns | ForEach-Object {
                $color = switch ($_.Severity) { 'Critical' { 'Red' }; 'Error' { 'OrangeRed' }; 'Warning' { 'Orange' }; 'Notice' { 'DodgerBlue' }; default { 'Gray' } }
                [pscustomobject]@{ PatternName = $_.PatternName; Description = $_.Description; MatchCount = $_.MatchCount; Severity = $_.Severity; SeverityColor = $color; Pattern = $_ }
            })
            if ($patternListBox) { $patternListBox.ItemsSource = $displayPatterns }
            if ($statusText) { $statusText.Text = "Found $($patterns.Count) pattern(s)" }
        } catch { if ($statusText) { $statusText.Text = "Analysis error: $($_.Exception.Message)" } }
    }

    $applyFilters = {
        $entries = $View.Tag.AllEntries
        if ($entries.Count -eq 0) { & $updateGrid @(); return }
        $keyword = $searchKeywordBox.Text
        $sevSelected = $severityFilterDropdown.SelectedItem
        $devSelected = $deviceFilterDropdown.SelectedItem
        $params = @{ Entries = $entries }
        if (-not [string]::IsNullOrWhiteSpace($keyword)) { $params['Keyword'] = $keyword }
        if ($sevSelected -and $sevSelected.Content -ne 'All Severities') {
            switch ($sevSelected.Content) { 'Critical (0-2)' { $params['MaxSeverity'] = 2 }; 'Error (3)' { $params['MaxSeverity'] = 3; $params['MinSeverity'] = 3 }; 'Warning (4)' { $params['MaxSeverity'] = 4; $params['MinSeverity'] = 4 }; 'Notice (5)' { $params['MaxSeverity'] = 5; $params['MinSeverity'] = 5 }; 'Info (6-7)' { $params['MinSeverity'] = 6 } }
        }
        if ($devSelected -and $devSelected.Content -ne 'All Devices') { $params['Device'] = $devSelected.Content }
        try {
            $filtered = @(LogAnalysisModule\Search-LogEntries @params)
            & $updateGrid $filtered
            if ($statusText) { $statusText.Text = "Showing $($filtered.Count) of $($entries.Count) entries" }
        } catch { if ($statusText) { $statusText.Text = "Filter error: $($_.Exception.Message)" } }
    }

    # Event handlers
    if ($importFileButton) {
        $importFileButton.Add_Click({
            try {
                $dialog = New-Object Microsoft.Win32.OpenFileDialog
                $dialog.Title = 'Select Log File'; $dialog.Filter = 'Log files (*.log;*.txt)|*.log;*.txt|All files (*.*)|*.*'
                if ($dialog.ShowDialog() -eq $true) {
                    $format = & $getSelectedFormat
                    $hostname = $defaultHostnameBox.Text
                    if ($statusText) { $statusText.Text = "Importing $($dialog.FileName)..." }
                    $result = LogAnalysisModule\Import-LogFile -Path $dialog.FileName -Format $format -DefaultHostname $hostname
                    $View.Tag.AllEntries = $result.Entries; $View.Tag.ImportResult = $result
                    & $updateSummary; & $updateGrid $result.Entries; & $runAnalysis
                    if ($statusText) { $statusText.Text = if ($result.ErrorCount -gt 0) { "Imported $($result.ImportedCount) entries ($($result.ErrorCount) errors)" } else { "Imported $($result.ImportedCount) entries" } }
                }
            } catch { if ($statusText) { $statusText.Text = "Import error: $($_.Exception.Message)" } }
        }.GetNewClosure())
    }

    if ($pasteLogsButton) {
        $pasteLogsButton.Add_Click({
            try {
                $clipText = [System.Windows.Clipboard]::GetText()
                if ([string]::IsNullOrWhiteSpace($clipText)) { if ($statusText) { $statusText.Text = 'Clipboard is empty' }; return }
                $lines = $clipText -split "`r?`n"
                $format = & $getSelectedFormat
                $hostname = $defaultHostnameBox.Text
                if ($statusText) { $statusText.Text = "Parsing $($lines.Count) lines..." }
                $result = LogAnalysisModule\Import-LogEntries -Entries $lines -Format $format -DefaultHostname $hostname
                $View.Tag.AllEntries = $result.Entries; $View.Tag.ImportResult = $result
                & $updateSummary; & $updateGrid $result.Entries; & $runAnalysis
                if ($statusText) { $statusText.Text = "Parsed $($result.ImportedCount) entries from clipboard" }
            } catch { if ($statusText) { $statusText.Text = "Parse error: $($_.Exception.Message)" } }
        }.GetNewClosure())
    }

    if ($clearLogsButton) {
        $clearLogsButton.Add_Click({
            $View.Tag.AllEntries = @(); $View.Tag.FilteredEntries = @(); $View.Tag.Patterns = @(); $View.Tag.ImportResult = $null
            if ($logEntriesGrid) { $logEntriesGrid.ItemsSource = @() }; if ($patternListBox) { $patternListBox.ItemsSource = @() }
            & $updateSummary; if ($detailsPanel) { $detailsPanel.Visibility = 'Collapsed' }; if ($statusText) { $statusText.Text = 'Cleared all logs' }
        }.GetNewClosure())
    }

    if ($analyzeButton) { $analyzeButton.Add_Click({ & $runAnalysis }.GetNewClosure()) }
    if ($searchButton) { $searchButton.Add_Click({ & $applyFilters }.GetNewClosure()) }
    if ($searchKeywordBox) { $searchKeywordBox.Add_KeyDown({ param($s,$e); if ($e.Key -eq 'Return') { & $applyFilters } }.GetNewClosure()) }

    if ($patternListBox) {
        $patternListBox.Add_SelectionChanged({
            param($s,$e); $selected = $s.SelectedItem
            if ($selected -and $selected.Pattern) { $matchedEntries = $selected.Pattern.MatchedEntries; if ($matchedEntries) { & $updateGrid $matchedEntries; if ($statusText) { $statusText.Text = "Showing $($matchedEntries.Count) entries for pattern: $($selected.PatternName)" } } }
        }.GetNewClosure())
    }

    if ($logEntriesGrid) {
        $logEntriesGrid.Add_SelectionChanged({
            param($s,$e); $selected = $s.SelectedItem
            if ($selected) {
                if ($detailsPanel) { $detailsPanel.Visibility = 'Visible' }
                if ($detailsTitleText) { $detailsTitleText.Text = "$($selected.MessageType) - $($selected.SeverityName)" }
                if ($detailsContentBox) { $detailsContentBox.Text = $selected.RawEntry }
            } else { if ($detailsPanel) { $detailsPanel.Visibility = 'Collapsed' } }
        }.GetNewClosure())
    }

    if ($copySelectedButton) {
        $copySelectedButton.Add_Click({
            $selected = @($logEntriesGrid.SelectedItems)
            if ($selected.Count -gt 0) { $text = ($selected | ForEach-Object { $_.RawEntry }) -join "`r`n"; [System.Windows.Clipboard]::SetText($text); if ($statusText) { $statusText.Text = "Copied $($selected.Count) entries to clipboard" } }
        }.GetNewClosure())
    }

    if ($exportButton) {
        $exportButton.Add_Click({
            $entries = $View.Tag.FilteredEntries
            if ($entries.Count -eq 0) { if ($statusText) { $statusText.Text = 'No entries to export' }; return }
            try {
                $dialog = New-Object Microsoft.Win32.SaveFileDialog; $dialog.Title = 'Export Log Entries'; $dialog.Filter = 'CSV files (*.csv)|*.csv|Text files (*.txt)|*.txt'; $dialog.DefaultExt = '.csv'
                if ($dialog.ShowDialog() -eq $true) {
                    if ($dialog.FileName -match '\.csv$') { $entries | Export-Csv -Path $dialog.FileName -NoTypeInformation } else { ($entries | ForEach-Object { $_.RawEntry }) | Out-File -FilePath $dialog.FileName }
                    if ($statusText) { $statusText.Text = "Exported $($entries.Count) entries to $($dialog.FileName)" }
                }
            } catch { if ($statusText) { $statusText.Text = "Export error: $($_.Exception.Message)" } }
        }.GetNewClosure())
    }

    if ($statusText) { $statusText.Text = 'Ready - Import or paste log entries to begin' }
}

Export-ModuleMember -Function New-LogAnalysisView, Initialize-LogAnalysisView
