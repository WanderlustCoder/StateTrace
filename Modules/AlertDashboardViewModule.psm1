# AlertDashboardViewModule.psm1
# View module for the Alert Dashboard

Set-StrictMode -Version Latest

$script:View = $null
$script:RefreshTimer = $null
$script:AutoRefreshInterval = 30  # seconds

function Initialize-AlertDashboardView {
    <#
    .SYNOPSIS
    Initializes the Alert Dashboard view with data binding and event handlers.
    .PARAMETER View
    The loaded XAML UserControl.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Controls.UserControl]$View
    )

    $script:View = $View

    # Import required modules
    $modulesRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $modulesRoot 'Modules\AlertRuleModule.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue

    # Initialize default rules if not already done
    try {
        $rules = Get-AlertRule
        if ($rules.Count -eq 0) {
            Initialize-DefaultAlertRules
        }
    } catch {
        Write-Verbose "[AlertDashboard] Could not initialize rules: $_"
    }

    # Get UI elements
    $refreshBtn = $View.FindName('RefreshButton')
    $clearAllBtn = $View.FindName('ClearAllButton')
    $configureBtn = $View.FindName('ConfigureButton')
    $severityFilter = $View.FindName('SeverityFilter')
    $categoryFilter = $View.FindName('CategoryFilter')
    $sourceFilter = $View.FindName('SourceFilter')
    $historyLimit = $View.FindName('HistoryLimit')

    # Wire up event handlers
    if ($refreshBtn) {
        $refreshBtn.Add_Click({ Update-AlertDashboard })
    }

    if ($clearAllBtn) {
        $clearAllBtn.Add_Click({ Clear-ResolvedAlerts })
    }

    if ($severityFilter) {
        $severityFilter.Add_SelectionChanged({ Update-ActiveAlertsGrid })
    }

    if ($categoryFilter) {
        $categoryFilter.Add_SelectionChanged({ Update-ActiveAlertsGrid })
    }

    if ($sourceFilter) {
        $sourceFilter.Add_TextChanged({ Update-ActiveAlertsGrid })
    }

    if ($historyLimit) {
        $historyLimit.Add_SelectionChanged({ Update-HistoryGrid })
    }

    # Context menu handlers
    $acknowledgeMenuItem = $View.FindName('AcknowledgeMenuItem')
    $resolveMenuItem = $View.FindName('ResolveMenuItem')

    if ($acknowledgeMenuItem) {
        $acknowledgeMenuItem.Add_Click({ Invoke-AcknowledgeSelected })
    }

    if ($resolveMenuItem) {
        $resolveMenuItem.Add_Click({ Invoke-ResolveSelected })
    }

    # Summary card click handlers
    foreach ($severity in @('Critical', 'High', 'Medium', 'Low', 'Total')) {
        $card = $View.FindName("${severity}Card")
        if ($card) {
            $card.Add_MouseLeftButtonUp({
                param($sender, $e)
                $severityName = $sender.Name -replace 'Card$', ''
                Set-SeverityFilter -Severity $severityName
            }.GetNewClosure())
        }
    }

    # Initial data load
    Update-AlertDashboard

    # Start auto-refresh timer
    Start-AutoRefresh

    Write-Verbose "[AlertDashboard] View initialized"
}

function Update-AlertDashboard {
    <#
    .SYNOPSIS
    Refreshes all dashboard data.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:View) { return }

    try {
        Update-SummaryCards
        Update-ActiveAlertsGrid
        Update-HistoryGrid
        Update-RulesGrid

        $lastUpdated = $script:View.FindName('LastUpdatedText')
        if ($lastUpdated) {
            $lastUpdated.Text = (Get-Date -Format 'HH:mm:ss')
        }

        $statusText = $script:View.FindName('StatusText')
        if ($statusText) {
            $statusText.Text = "Updated successfully"
        }

    } catch {
        Write-Verbose "[AlertDashboard] Update failed: $_"
        $statusText = $script:View.FindName('StatusText')
        if ($statusText) {
            $statusText.Text = "Error: $($_.Exception.Message)"
        }
    }
}

function Update-SummaryCards {
    if (-not $script:View) { return }

    try {
        $summary = Get-AlertSummary

        $criticalCount = $script:View.FindName('CriticalCount')
        $highCount = $script:View.FindName('HighCount')
        $mediumCount = $script:View.FindName('MediumCount')
        $lowCount = $script:View.FindName('LowCount')
        $totalCount = $script:View.FindName('TotalCount')

        if ($criticalCount) { $criticalCount.Text = [string]$summary.Critical }
        if ($highCount) { $highCount.Text = [string]$summary.High }
        if ($mediumCount) { $mediumCount.Text = [string]$summary.Medium }
        if ($lowCount) { $lowCount.Text = [string]$summary.Low }
        if ($totalCount) { $totalCount.Text = [string]$summary.TotalActive }

    } catch {
        Write-Verbose "[AlertDashboard] Summary update failed: $_"
    }
}

function Update-ActiveAlertsGrid {
    if (-not $script:View) { return }

    try {
        $grid = $script:View.FindName('ActiveAlertsGrid')
        if (-not $grid) { return }

        # Get filter values
        $severityFilter = $script:View.FindName('SeverityFilter')
        $categoryFilter = $script:View.FindName('CategoryFilter')
        $sourceFilter = $script:View.FindName('SourceFilter')

        $severity = $null
        $category = $null
        $source = $null

        if ($severityFilter -and $severityFilter.SelectedIndex -gt 0) {
            $severity = $severityFilter.SelectedItem.Content
        }
        if ($categoryFilter -and $categoryFilter.SelectedIndex -gt 0) {
            $category = $categoryFilter.SelectedItem.Content
        }
        if ($sourceFilter -and $sourceFilter.Text) {
            $source = "*$($sourceFilter.Text)*"
        }

        $params = @{}
        if ($severity) { $params.Severity = $severity }
        if ($category) { $params.Category = $category }
        if ($source) { $params.Source = $source }

        $alerts = Get-ActiveAlerts @params

        $grid.ItemsSource = $alerts

    } catch {
        Write-Verbose "[AlertDashboard] Active alerts update failed: $_"
    }
}

function Update-HistoryGrid {
    if (-not $script:View) { return }

    try {
        $grid = $script:View.FindName('HistoryGrid')
        $limitCombo = $script:View.FindName('HistoryLimit')

        if (-not $grid) { return }

        $limit = 100
        if ($limitCombo -and $limitCombo.SelectedItem) {
            $limit = [int]$limitCombo.SelectedItem.Content
        }

        $history = Get-AlertHistory -Last $limit
        $grid.ItemsSource = $history

    } catch {
        Write-Verbose "[AlertDashboard] History update failed: $_"
    }
}

function Update-RulesGrid {
    if (-not $script:View) { return }

    try {
        $grid = $script:View.FindName('RulesGrid')
        if (-not $grid) { return }

        $rules = Get-AlertRule
        $grid.ItemsSource = $rules

    } catch {
        Write-Verbose "[AlertDashboard] Rules update failed: $_"
    }
}

function Set-SeverityFilter {
    param([string]$Severity)

    if (-not $script:View) { return }

    $severityFilter = $script:View.FindName('SeverityFilter')
    if (-not $severityFilter) { return }

    $index = switch ($Severity) {
        'Critical' { 1 }
        'High' { 2 }
        'Medium' { 3 }
        'Low' { 4 }
        default { 0 }
    }

    $severityFilter.SelectedIndex = $index
}

function Invoke-AcknowledgeSelected {
    if (-not $script:View) { return }

    $grid = $script:View.FindName('ActiveAlertsGrid')
    if (-not $grid -or -not $grid.SelectedItem) { return }

    foreach ($item in $grid.SelectedItems) {
        Set-AlertAcknowledged -AlertId $item.Id
    }

    Update-AlertDashboard
}

function Invoke-ResolveSelected {
    if (-not $script:View) { return }

    $grid = $script:View.FindName('ActiveAlertsGrid')
    if (-not $grid -or -not $grid.SelectedItem) { return }

    foreach ($item in $grid.SelectedItems) {
        Clear-Alert -AlertId $item.Id
    }

    Update-AlertDashboard
}

function Clear-ResolvedAlerts {
    # This clears any stale alerts from the UI
    Update-AlertDashboard
}

function Start-AutoRefresh {
    if ($script:RefreshTimer) {
        $script:RefreshTimer.Stop()
        $script:RefreshTimer = $null
    }

    $script:RefreshTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:RefreshTimer.Interval = [TimeSpan]::FromSeconds($script:AutoRefreshInterval)
    $script:RefreshTimer.Add_Tick({ Update-AlertDashboard })
    $script:RefreshTimer.Start()

    Write-Verbose "[AlertDashboard] Auto-refresh started (${script:AutoRefreshInterval}s)"
}

function Stop-AutoRefresh {
    if ($script:RefreshTimer) {
        $script:RefreshTimer.Stop()
        $script:RefreshTimer = $null
        Write-Verbose "[AlertDashboard] Auto-refresh stopped"
    }
}

function Get-AlertDashboardView {
    return $script:View
}

Export-ModuleMember -Function @(
    'Initialize-AlertDashboardView',
    'Update-AlertDashboard',
    'Get-AlertDashboardView',
    'Start-AutoRefresh',
    'Stop-AutoRefresh'
)
