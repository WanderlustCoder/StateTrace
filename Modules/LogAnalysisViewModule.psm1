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

Export-ModuleMember -Function New-LogAnalysisView
