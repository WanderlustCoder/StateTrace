# ComplianceDashboardViewModule.psm1
# View module for the Compliance Dashboard

Set-StrictMode -Version Latest

$script:View = $null
$script:CurrentResults = $null

function Initialize-ComplianceDashboardView {
    <#
    .SYNOPSIS
    Initializes the Compliance Dashboard view with data binding and event handlers.
    .PARAMETER View
    The loaded XAML UserControl.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Controls.UserControl]$View
    )

    $script:View = $View

    # Import required modules
    $projectRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $projectRoot 'Modules\ComplianceModule.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue
    Import-Module (Join-Path $projectRoot 'Modules\AuditTrailModule.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue

    # Get UI elements
    $frameworkSelector = $View.FindName('FrameworkSelector')
    $runValidationBtn = $View.FindName('RunValidationButton')
    $exportReportBtn = $View.FindName('ExportReportButton')
    $scheduleBtn = $View.FindName('ScheduleButton')
    $statusFilter = $View.FindName('StatusFilter')
    $categoryFilter = $View.FindName('CategoryFilter')
    $controlSearch = $View.FindName('ControlSearch')
    $auditDateRange = $View.FindName('AuditDateRange')
    $auditEventType = $View.FindName('AuditEventType')
    $exportAuditBtn = $View.FindName('ExportAuditButton')

    # Wire up event handlers
    if ($runValidationBtn) {
        $runValidationBtn.Add_Click({ Invoke-DashboardValidation })
    }

    if ($exportReportBtn) {
        $exportReportBtn.Add_Click({ Export-DashboardReport })
    }

    if ($frameworkSelector) {
        $frameworkSelector.Add_SelectionChanged({ Update-ControlsGrid })
    }

    if ($statusFilter) {
        $statusFilter.Add_SelectionChanged({ Update-ControlsGrid })
    }

    if ($categoryFilter) {
        $categoryFilter.Add_SelectionChanged({ Update-ControlsGrid })
    }

    if ($controlSearch) {
        $controlSearch.Add_TextChanged({ Update-ControlsGrid })
    }

    if ($auditDateRange) {
        $auditDateRange.Add_SelectionChanged({ Update-AuditGrid })
    }

    if ($auditEventType) {
        $auditEventType.Add_SelectionChanged({ Update-AuditGrid })
    }

    if ($exportAuditBtn) {
        $exportAuditBtn.Add_Click({ Export-AuditTrailReport })
    }

    # Framework card click handlers
    foreach ($fw in @('SOX', 'PCIDSS', 'HIPAA', 'NIST', 'CIS')) {
        $card = $View.FindName("${fw}Card")
        if ($card) {
            $card.Add_MouseLeftButtonUp({
                param($sender, $e)
                $fwName = $sender.Name -replace 'Card$', ''
                Set-FrameworkFilter -Framework $fwName
            }.GetNewClosure())
        }
    }

    # Load saved reports list
    Update-ReportsList

    # Initial audit grid load
    Update-AuditGrid

    Set-StatusText -Text "Ready - Click 'Run Validation' to start"

    Write-Verbose "[ComplianceDashboard] View initialized"
}

function Invoke-DashboardValidation {
    if (-not $script:View) { return }

    Set-StatusText -Text "Running compliance validation..."

    $frameworkSelector = $script:View.FindName('FrameworkSelector')
    $framework = 'All'

    if ($frameworkSelector -and $frameworkSelector.SelectedIndex -gt 0) {
        $framework = $frameworkSelector.SelectedItem.Content
    }

    try {
        $script:CurrentResults = Invoke-ComplianceValidation -Framework $framework -IncludeRemediation

        Update-ScoreCards
        Update-ControlsGrid
        Update-FindingsGrid
        Update-CategoryFilter

        $deviceCount = $script:View.FindName('DeviceCountText')
        if ($deviceCount) {
            $deviceCount.Text = [string]$script:CurrentResults.DeviceCount
        }

        $lastValidation = $script:View.FindName('LastValidationText')
        if ($lastValidation) {
            $lastValidation.Text = (Get-Date -Format 'HH:mm:ss')
        }

        Set-StatusText -Text "Validation complete - Score: $($script:CurrentResults.OverallScore)%"

    } catch {
        Set-StatusText -Text "Validation failed: $($_.Exception.Message)"
        Write-Verbose "[ComplianceDashboard] Validation error: $_"
    }
}

function Update-ScoreCards {
    if (-not $script:View -or -not $script:CurrentResults) { return }

    # Overall score
    $overallScoreValue = $script:View.FindName('OverallScoreValue')
    $overallStatusText = $script:View.FindName('OverallStatusText')
    $overallScoreCard = $script:View.FindName('OverallScoreCard')

    if ($overallScoreValue) {
        $overallScoreValue.Text = "$($script:CurrentResults.OverallScore)%"
    }
    if ($overallStatusText) {
        $overallStatusText.Text = $script:CurrentResults.OverallStatus
    }

    # Update card background based on score
    if ($overallScoreCard) {
        $brush = switch ($script:CurrentResults.OverallStatus) {
            'Compliant' {
                $gb = [System.Windows.Media.LinearGradientBrush]::new()
                $gb.StartPoint = [System.Windows.Point]::new(0, 0)
                $gb.EndPoint = [System.Windows.Point]::new(1, 1)
                $gb.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromRgb(76, 175, 80), 0))
                $gb.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromRgb(46, 125, 50), 1))
                $gb
            }
            'Partially Compliant' {
                $gb = [System.Windows.Media.LinearGradientBrush]::new()
                $gb.StartPoint = [System.Windows.Point]::new(0, 0)
                $gb.EndPoint = [System.Windows.Point]::new(1, 1)
                $gb.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromRgb(255, 152, 0), 0))
                $gb.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromRgb(230, 81, 0), 1))
                $gb
            }
            default {
                $gb = [System.Windows.Media.LinearGradientBrush]::new()
                $gb.StartPoint = [System.Windows.Point]::new(0, 0)
                $gb.EndPoint = [System.Windows.Point]::new(1, 1)
                $gb.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromRgb(244, 67, 54), 0))
                $gb.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromRgb(183, 28, 28), 1))
                $gb
            }
        }
        $overallScoreCard.Background = $brush
    }

    # Framework cards
    $frameworkMap = @{
        'SOX' = 'SOX'
        'PCI-DSS' = 'PCIDSS'
        'HIPAA' = 'HIPAA'
        'NIST' = 'NIST'
        'CIS' = 'CIS'
    }

    foreach ($fwKey in $script:CurrentResults.Frameworks.Keys) {
        $fw = $script:CurrentResults.Frameworks[$fwKey]
        $cardName = $frameworkMap[$fwKey]

        $scoreText = $script:View.FindName("${cardName}Score")
        $statusText = $script:View.FindName("${cardName}Status")

        if ($scoreText) { $scoreText.Text = "$($fw.Score)%" }
        if ($statusText) { $statusText.Text = $fw.Status }
    }
}

function Update-ControlsGrid {
    if (-not $script:View -or -not $script:CurrentResults) { return }

    $grid = $script:View.FindName('ControlsGrid')
    if (-not $grid) { return }

    # Get filter values
    $statusFilter = $script:View.FindName('StatusFilter')
    $categoryFilter = $script:View.FindName('CategoryFilter')
    $controlSearch = $script:View.FindName('ControlSearch')
    $frameworkSelector = $script:View.FindName('FrameworkSelector')

    $statusValue = if ($statusFilter -and $statusFilter.SelectedIndex -gt 0) { $statusFilter.SelectedItem.Content } else { $null }
    $categoryValue = if ($categoryFilter -and $categoryFilter.SelectedIndex -gt 0) { $categoryFilter.SelectedItem.Content } else { $null }
    $searchValue = if ($controlSearch) { $controlSearch.Text } else { $null }
    $frameworkValue = if ($frameworkSelector -and $frameworkSelector.SelectedIndex -gt 0) { $frameworkSelector.SelectedItem.Content } else { $null }

    # Collect all controls
    $allControls = [System.Collections.Generic.List[object]]::new()

    foreach ($fwKey in $script:CurrentResults.Frameworks.Keys) {
        $fw = $script:CurrentResults.Frameworks[$fwKey]

        # Skip if framework filter doesn't match
        if ($frameworkValue -and $fwKey -ne $frameworkValue) { continue }

        foreach ($ctrl in $fw.Controls) {
            $obj = [PSCustomObject]@{
                Framework = $fwKey
                Id = $ctrl.Id
                Name = $ctrl.Name
                Category = $ctrl.Category
                Score = $ctrl.Score
                Status = $ctrl.Status
                Weight = $ctrl.Weight
                Description = $ctrl.Description
            }
            [void]$allControls.Add($obj)
        }
    }

    # Apply filters
    $filtered = $allControls

    if ($statusValue) {
        $filtered = $filtered | Where-Object { $_.Status -eq $statusValue }
    }
    if ($categoryValue) {
        $filtered = $filtered | Where-Object { $_.Category -eq $categoryValue }
    }
    if ($searchValue) {
        $filtered = $filtered | Where-Object {
            $_.Id -like "*$searchValue*" -or
            $_.Name -like "*$searchValue*" -or
            $_.Category -like "*$searchValue*"
        }
    }

    $grid.ItemsSource = $filtered
}

function Update-FindingsGrid {
    if (-not $script:View -or -not $script:CurrentResults) { return }

    $grid = $script:View.FindName('FindingsGrid')
    if (-not $grid) { return }

    $findings = [System.Collections.Generic.List[object]]::new()

    foreach ($fwKey in $script:CurrentResults.Frameworks.Keys) {
        $fw = $script:CurrentResults.Frameworks[$fwKey]

        foreach ($ctrl in $fw.Controls) {
            if ($ctrl.Findings -and $ctrl.Findings.Count -gt 0) {
                foreach ($finding in $ctrl.Findings) {
                    $obj = [PSCustomObject]@{
                        Framework = $fwKey
                        ControlId = $ctrl.Id
                        Finding = $finding
                        Remediation = $ctrl.Remediation
                    }
                    [void]$findings.Add($obj)
                }
            }
        }
    }

    $grid.ItemsSource = $findings
}

function Update-CategoryFilter {
    if (-not $script:View -or -not $script:CurrentResults) { return }

    $categoryFilter = $script:View.FindName('CategoryFilter')
    if (-not $categoryFilter) { return }

    # Collect unique categories
    $categories = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($fw in $script:CurrentResults.Frameworks.Values) {
        foreach ($ctrl in $fw.Controls) {
            if ($ctrl.Category) {
                [void]$categories.Add($ctrl.Category)
            }
        }
    }

    $categoryFilter.Items.Clear()
    $categoryFilter.Items.Add([System.Windows.Controls.ComboBoxItem]@{ Content = 'All Categories' }) | Out-Null

    foreach ($cat in ($categories | Sort-Object)) {
        $categoryFilter.Items.Add([System.Windows.Controls.ComboBoxItem]@{ Content = $cat }) | Out-Null
    }

    $categoryFilter.SelectedIndex = 0
}

function Update-AuditGrid {
    if (-not $script:View) { return }

    $grid = $script:View.FindName('AuditGrid')
    $dateRange = $script:View.FindName('AuditDateRange')
    $eventType = $script:View.FindName('AuditEventType')

    if (-not $grid) { return }

    try {
        # Determine date range
        $days = switch ($dateRange.SelectedIndex) {
            0 { 1 }
            1 { 7 }
            2 { 30 }
            3 { 90 }
            default { 7 }
        }

        $startDate = (Get-Date).AddDays(-$days)
        $eventTypeValue = if ($eventType -and $eventType.SelectedIndex -gt 0) {
            $eventType.SelectedItem.Content
        } else { $null }

        $params = @{ StartDate = $startDate; Last = 500 }
        if ($eventTypeValue) { $params.EventType = $eventTypeValue }

        $events = Get-AuditEvents @params

        $grid.ItemsSource = $events

    } catch {
        Write-Verbose "[ComplianceDashboard] Audit grid error: $_"
    }
}

function Update-ReportsList {
    if (-not $script:View) { return }

    $listBox = $script:View.FindName('ReportsList')
    if (-not $listBox) { return }

    $projectRoot = Split-Path -Parent $PSScriptRoot
    $reportsPath = Join-Path $projectRoot 'Logs\Reports\Compliance'

    if (Test-Path $reportsPath) {
        $reports = Get-ChildItem -Path $reportsPath -Filter '*.html' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 20

        $listBox.Items.Clear()
        foreach ($report in $reports) {
            $item = [System.Windows.Controls.ListBoxItem]::new()
            $item.Content = $report.Name
            $item.Tag = $report.FullName
            $listBox.Items.Add($item) | Out-Null
        }
    }
}

function Set-FrameworkFilter {
    param([string]$Framework)

    if (-not $script:View) { return }

    $frameworkSelector = $script:View.FindName('FrameworkSelector')
    if (-not $frameworkSelector) { return }

    $index = switch ($Framework) {
        'SOX' { 1 }
        'PCIDSS' { 2 }
        'PCI-DSS' { 2 }
        'HIPAA' { 3 }
        'NIST' { 4 }
        'CIS' { 5 }
        default { 0 }
    }

    $frameworkSelector.SelectedIndex = $index
}

function Export-DashboardReport {
    if (-not $script:View -or -not $script:CurrentResults) {
        Set-StatusText -Text "Run validation first before exporting"
        return
    }

    try {
        $reportPath = Export-ComplianceReport -Results $script:CurrentResults -Format 'HTML'
        Update-ReportsList
        Set-StatusText -Text "Report exported: $reportPath"

        # Try to open the report
        Start-Process $reportPath -ErrorAction SilentlyContinue

    } catch {
        Set-StatusText -Text "Export failed: $($_.Exception.Message)"
    }
}

function Export-AuditTrailReport {
    if (-not $script:View) { return }

    $dateRange = $script:View.FindName('AuditDateRange')

    $days = switch ($dateRange.SelectedIndex) {
        0 { 1 }
        1 { 7 }
        2 { 30 }
        3 { 90 }
        default { 7 }
    }

    try {
        $startDate = (Get-Date).AddDays(-$days)
        $reportPath = Export-AuditReport -StartDate $startDate -Format 'HTML'

        Set-StatusText -Text "Audit report exported: $reportPath"
        Start-Process $reportPath -ErrorAction SilentlyContinue

    } catch {
        Set-StatusText -Text "Export failed: $($_.Exception.Message)"
    }
}

function Set-StatusText {
    param([string]$Text)

    if (-not $script:View) { return }

    $statusText = $script:View.FindName('StatusText')
    if ($statusText) {
        $statusText.Text = $Text
    }
}

function Get-ComplianceDashboardView {
    return $script:View
}

Export-ModuleMember -Function @(
    'Initialize-ComplianceDashboardView',
    'Invoke-DashboardValidation',
    'Get-ComplianceDashboardView'
)
