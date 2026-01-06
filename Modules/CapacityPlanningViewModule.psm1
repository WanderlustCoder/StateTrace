#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    View module for the Capacity Planning UI.

.DESCRIPTION
    Wires up the CapacityPlanningView.xaml to the CapacityPlanningModule functions.
    Handles UI events and data binding for utilization tracking, forecasting,
    scenarios, budget planning, and threshold management.

.NOTES
    Plan AC - Capacity Planning & Forecasting
#>

# Module-level references to UI controls
$script:CapacityView = $null
$script:SiteUtilizationGrid = $null
$script:AlertsGrid = $null
$script:ForecastGrid = $null
$script:ThresholdsGrid = $null
$script:ReportsGrid = $null

function New-CapacityPlanningView {
    <#
    .SYNOPSIS
        Creates and initializes the Capacity Planning view.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Window]$Window,
        [Parameter(Mandatory=$true)][string]$ScriptDir
    )

    # Load XAML using ViewCompositionModule pattern
    $script:CapacityView = ViewCompositionModule\Set-StView -Window $Window -ScriptDir $ScriptDir `
        -ViewName 'CapacityPlanningView' -HostControlName 'CapacityPlanningHost' `
        -GlobalVariableName 'capacityPlanningView'
    if (-not $script:CapacityView) {
        return $null
    }

    # Get control references
    Get-CapacityPlanningControls

    # Wire up event handlers
    Register-CapacityPlanningEvents

    # Initialize data
    Update-CapacityPlanningDashboard
    Update-SiteUtilizationGrid
    Update-AlertsGrid
    Update-ThresholdsGrid
    Update-ForecastScopeCombo
    Update-ReportsGrid

    return $script:CapacityView
}

function Get-CapacityPlanningControls {
    <#
    .SYNOPSIS
        Gets references to UI controls.
    #>

    # Dashboard tab - Overall utilization
    $script:OverallUtilizationBar = $script:CapacityView.FindName('OverallUtilizationBar')
    $script:OverallUtilizationLabel = $script:CapacityView.FindName('OverallUtilizationLabel')
    $script:OverallUsedLabel = $script:CapacityView.FindName('OverallUsedLabel')
    $script:OverallAvailableLabel = $script:CapacityView.FindName('OverallAvailableLabel')
    $script:OverallTotalLabel = $script:CapacityView.FindName('OverallTotalLabel')

    # Dashboard - Site utilization grid
    $script:SiteUtilizationGrid = $script:CapacityView.FindName('SiteUtilizationGrid')
    $script:RefreshDashboardButton = $script:CapacityView.FindName('RefreshDashboardButton')

    # Dashboard - Quick stats
    $script:TotalPortsLabel = $script:CapacityView.FindName('TotalPortsLabel')
    $script:UsedPortsLabel = $script:CapacityView.FindName('UsedPortsLabel')
    $script:AvailablePortsLabel = $script:CapacityView.FindName('AvailablePortsLabel')
    $script:PoEUtilizationLabel = $script:CapacityView.FindName('PoEUtilizationLabel')
    $script:SitesCountLabel = $script:CapacityView.FindName('SitesCountLabel')
    $script:AlertsCountLabel = $script:CapacityView.FindName('AlertsCountLabel')

    # Dashboard - Alerts grid
    $script:AlertsGrid = $script:CapacityView.FindName('AlertsGrid')
    $script:ViewAlertDetailsButton = $script:CapacityView.FindName('ViewAlertDetailsButton')
    $script:DismissAlertButton = $script:CapacityView.FindName('DismissAlertButton')

    # Forecast tab
    $script:ForecastScopeCombo = $script:CapacityView.FindName('ForecastScopeCombo')
    $script:ForecastPeriodCombo = $script:CapacityView.FindName('ForecastPeriodCombo')
    $script:ForecastThresholdBox = $script:CapacityView.FindName('ForecastThresholdBox')
    $script:RunForecastButton = $script:CapacityView.FindName('RunForecastButton')
    $script:ExportForecastButton = $script:CapacityView.FindName('ExportForecastButton')

    # Forecast - Results
    $script:CurrentUtilizationLabel = $script:CapacityView.FindName('CurrentUtilizationLabel')
    $script:GrowthRateLabel = $script:CapacityView.FindName('GrowthRateLabel')
    $script:PortsPerMonthLabel = $script:CapacityView.FindName('PortsPerMonthLabel')
    $script:RSquaredLabel = $script:CapacityView.FindName('RSquaredLabel')
    $script:BreachDateLabel = $script:CapacityView.FindName('BreachDateLabel')
    $script:DaysUntilBreachLabel = $script:CapacityView.FindName('DaysUntilBreachLabel')
    $script:ForecastGrid = $script:CapacityView.FindName('ForecastGrid')

    # Scenarios tab
    $script:ScenarioTypeCombo = $script:CapacityView.FindName('ScenarioTypeCombo')
    $script:ScenarioScopeCombo = $script:CapacityView.FindName('ScenarioScopeCombo')
    $script:ScenarioValueBox = $script:CapacityView.FindName('ScenarioValueBox')
    $script:RunScenarioButton = $script:CapacityView.FindName('RunScenarioButton')
    $script:SaveScenarioButton = $script:CapacityView.FindName('SaveScenarioButton')
    $script:CompareScenarioButton = $script:CapacityView.FindName('CompareScenarioButton')

    # Scenarios - Results
    $script:ScenarioCurrentLabel = $script:CapacityView.FindName('ScenarioCurrentLabel')
    $script:ScenarioNewLabel = $script:CapacityView.FindName('ScenarioNewLabel')
    $script:ScenarioImpactLabel = $script:CapacityView.FindName('ScenarioImpactLabel')
    $script:ScenarioFeasibleLabel = $script:CapacityView.FindName('ScenarioFeasibleLabel')
    $script:ScenarioRecommendationBox = $script:CapacityView.FindName('ScenarioRecommendationBox')

    # Budget tab
    $script:BudgetYearCombo = $script:CapacityView.FindName('BudgetYearCombo')
    $script:BudgetGrowthBox = $script:CapacityView.FindName('BudgetGrowthBox')
    $script:CalculateBudgetButton = $script:CapacityView.FindName('CalculateBudgetButton')
    $script:ExportBudgetButton = $script:CapacityView.FindName('ExportBudgetButton')

    # Budget - Results
    $script:ProjectedPortsLabel = $script:CapacityView.FindName('ProjectedPortsLabel')
    $script:SwitchesNeededLabel = $script:CapacityView.FindName('SwitchesNeededLabel')
    $script:HardwareCostLabel = $script:CapacityView.FindName('HardwareCostLabel')
    $script:TotalCostLabel = $script:CapacityView.FindName('TotalCostLabel')
    $script:RedeploymentGrid = $script:CapacityView.FindName('RedeploymentGrid')

    # Thresholds tab
    $script:ThresholdsGrid = $script:CapacityView.FindName('ThresholdsGrid')
    $script:NewThresholdButton = $script:CapacityView.FindName('NewThresholdButton')
    $script:EditThresholdButton = $script:CapacityView.FindName('EditThresholdButton')
    $script:DeleteThresholdButton = $script:CapacityView.FindName('DeleteThresholdButton')
    $script:ApplyDefaultsButton = $script:CapacityView.FindName('ApplyDefaultsButton')

    # Default threshold controls
    $script:DefaultWarningBox = $script:CapacityView.FindName('DefaultWarningBox')
    $script:DefaultCriticalBox = $script:CapacityView.FindName('DefaultCriticalBox')
    $script:SaveDefaultsButton = $script:CapacityView.FindName('SaveDefaultsButton')

    # Reports tab
    $script:ReportsGrid = $script:CapacityView.FindName('ReportsGrid')
    $script:ReportTypeCombo = $script:CapacityView.FindName('ReportTypeCombo')
    $script:ReportScopeCombo = $script:CapacityView.FindName('ReportScopeCombo')
    $script:GenerateReportButton = $script:CapacityView.FindName('GenerateReportButton')
    $script:ViewReportButton = $script:CapacityView.FindName('ViewReportButton')
    $script:ExportReportButton = $script:CapacityView.FindName('ExportReportButton')
    $script:DeleteReportButton = $script:CapacityView.FindName('DeleteReportButton')
}

function Register-CapacityPlanningEvents {
    <#
    .SYNOPSIS
        Registers event handlers for UI controls.
    #>

    # Dashboard events
    if ($script:RefreshDashboardButton) {
        $script:RefreshDashboardButton.Add_Click({
            Update-CapacityPlanningDashboard
            Update-SiteUtilizationGrid
            Update-AlertsGrid
        })
    }

    if ($script:ViewAlertDetailsButton) {
        $script:ViewAlertDetailsButton.Add_Click({
            Show-AlertDetails
        })
    }

    if ($script:DismissAlertButton) {
        $script:DismissAlertButton.Add_Click({
            Dismiss-SelectedAlert
        })
    }

    # Forecast events
    if ($script:RunForecastButton) {
        $script:RunForecastButton.Add_Click({
            Run-CapacityForecast
        })
    }

    if ($script:ExportForecastButton) {
        $script:ExportForecastButton.Add_Click({
            Export-ForecastReport
        })
    }

    if ($script:ForecastScopeCombo) {
        $script:ForecastScopeCombo.Add_SelectionChanged({
            # Reset forecast results when scope changes
            Clear-ForecastResults
        })
    }

    # Scenario events
    if ($script:RunScenarioButton) {
        $script:RunScenarioButton.Add_Click({
            Run-CapacityScenario
        })
    }

    if ($script:SaveScenarioButton) {
        $script:SaveScenarioButton.Add_Click({
            Save-CurrentScenario
        })
    }

    if ($script:CompareScenarioButton) {
        $script:CompareScenarioButton.Add_Click({
            Compare-Scenarios
        })
    }

    if ($script:ScenarioTypeCombo) {
        $script:ScenarioTypeCombo.Add_SelectionChanged({
            Update-ScenarioInputLabel
        })
    }

    # Budget events
    if ($script:CalculateBudgetButton) {
        $script:CalculateBudgetButton.Add_Click({
            Calculate-BudgetProjection
        })
    }

    if ($script:ExportBudgetButton) {
        $script:ExportBudgetButton.Add_Click({
            Export-BudgetReport
        })
    }

    # Threshold events
    if ($script:NewThresholdButton) {
        $script:NewThresholdButton.Add_Click({
            New-ThresholdEntry
        })
    }

    if ($script:EditThresholdButton) {
        $script:EditThresholdButton.Add_Click({
            Edit-SelectedThreshold
        })
    }

    if ($script:DeleteThresholdButton) {
        $script:DeleteThresholdButton.Add_Click({
            Remove-SelectedThreshold
        })
    }

    if ($script:ApplyDefaultsButton) {
        $script:ApplyDefaultsButton.Add_Click({
            Apply-DefaultThresholds
        })
    }

    if ($script:SaveDefaultsButton) {
        $script:SaveDefaultsButton.Add_Click({
            Save-DefaultThresholds
        })
    }

    # Report events
    if ($script:GenerateReportButton) {
        $script:GenerateReportButton.Add_Click({
            Generate-CapacityReport
        })
    }

    if ($script:ViewReportButton) {
        $script:ViewReportButton.Add_Click({
            View-SelectedReport
        })
    }

    if ($script:ExportReportButton) {
        $script:ExportReportButton.Add_Click({
            Export-SelectedReport
        })
    }

    if ($script:DeleteReportButton) {
        $script:DeleteReportButton.Add_Click({
            Remove-SelectedReport
        })
    }
}

#region Dashboard Functions

function Update-CapacityPlanningDashboard {
    <#
    .SYNOPSIS
        Updates the dashboard with current utilization statistics.
    #>
    [CmdletBinding()]
    param()

    try {
        # Get overall site utilization
        $siteUtilization = Get-SiteUtilization

        if ($siteUtilization -and $siteUtilization.Count -gt 0) {
            $totalPorts = ($siteUtilization | Measure-Object -Property TotalPorts -Sum).Sum
            $usedPorts = ($siteUtilization | Measure-Object -Property UsedPorts -Sum).Sum
            $availablePorts = $totalPorts - $usedPorts
            $overallPercent = if ($totalPorts -gt 0) { [math]::Round(($usedPorts / $totalPorts) * 100, 1) } else { 0 }

            # Update overall utilization bar
            if ($script:OverallUtilizationBar) {
                $script:OverallUtilizationBar.Value = $overallPercent
            }
            if ($script:OverallUtilizationLabel) {
                $script:OverallUtilizationLabel.Content = "$overallPercent%"
            }
            if ($script:OverallUsedLabel) {
                $script:OverallUsedLabel.Content = "Used: $usedPorts"
            }
            if ($script:OverallAvailableLabel) {
                $script:OverallAvailableLabel.Content = "Available: $availablePorts"
            }
            if ($script:OverallTotalLabel) {
                $script:OverallTotalLabel.Content = "Total: $totalPorts"
            }

            # Update quick stats
            if ($script:TotalPortsLabel) {
                $script:TotalPortsLabel.Content = $totalPorts.ToString('N0')
            }
            if ($script:UsedPortsLabel) {
                $script:UsedPortsLabel.Content = $usedPorts.ToString('N0')
            }
            if ($script:AvailablePortsLabel) {
                $script:AvailablePortsLabel.Content = $availablePorts.ToString('N0')
            }
            if ($script:SitesCountLabel) {
                $script:SitesCountLabel.Content = $siteUtilization.Count.ToString()
            }
        }

        # Get PoE utilization if available
        if (Get-Command -Name 'Get-PoEUtilization' -ErrorAction SilentlyContinue) {
            $poeUtil = Get-PoEUtilization
            if ($script:PoEUtilizationLabel -and $poeUtil) {
                $script:PoEUtilizationLabel.Content = "$($poeUtil.Percentage)%"
            }
        }

        # Update alerts count
        $alerts = Get-CapacityAlerts
        if ($script:AlertsCountLabel) {
            $alertCount = if ($alerts) { @($alerts).Count } else { 0 }
            $script:AlertsCountLabel.Content = $alertCount.ToString()
        }
    }
    catch {
        Write-Warning "Failed to update dashboard: $_"
    }
}

function Update-SiteUtilizationGrid {
    <#
    .SYNOPSIS
        Updates the site utilization data grid.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:SiteUtilizationGrid) { return }

    try {
        $siteUtilization = Get-SiteUtilization

        $gridData = @()
        foreach ($site in $siteUtilization) {
            $status = 'Normal'
            if ($site.Percentage -ge 90) {
                $status = 'Critical'
            } elseif ($site.Percentage -ge 75) {
                $status = 'Warning'
            }

            $gridData += [PSCustomObject]@{
                SiteID        = $site.SiteID
                SiteName      = $site.SiteName
                TotalPorts    = $site.TotalPorts
                UsedPorts     = $site.UsedPorts
                AvailablePorts = $site.TotalPorts - $site.UsedPorts
                Utilization   = "$($site.Percentage)%"
                Status        = $status
            }
        }

        $script:SiteUtilizationGrid.ItemsSource = $gridData
    }
    catch {
        Write-Warning "Failed to update site utilization grid: $_"
    }
}

function Update-AlertsGrid {
    <#
    .SYNOPSIS
        Updates the alerts data grid.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:AlertsGrid) { return }

    try {
        $alerts = Get-CapacityAlerts

        $gridData = @()
        foreach ($alert in $alerts) {
            $gridData += [PSCustomObject]@{
                AlertID      = $alert.AlertID
                Severity     = $alert.Severity
                Scope        = $alert.Scope
                Message      = $alert.Message
                Utilization  = "$($alert.CurrentUtilization)%"
                Threshold    = "$($alert.Threshold)%"
                DetectedDate = $alert.DetectedDate
            }
        }

        $script:AlertsGrid.ItemsSource = $gridData
    }
    catch {
        Write-Warning "Failed to update alerts grid: $_"
    }
}

function Show-AlertDetails {
    <#
    .SYNOPSIS
        Shows details for the selected alert.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:AlertsGrid -or -not $script:AlertsGrid.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select an alert to view details.', 'No Selection', 'OK', 'Information')
        return
    }

    $alert = $script:AlertsGrid.SelectedItem
    $details = @"
Alert Details
=============
Severity: $($alert.Severity)
Scope: $($alert.Scope)
Message: $($alert.Message)
Current Utilization: $($alert.Utilization)
Threshold: $($alert.Threshold)
Detected: $($alert.DetectedDate)
"@

    [System.Windows.MessageBox]::Show($details, 'Alert Details', 'OK', 'Information')
}

function Dismiss-SelectedAlert {
    <#
    .SYNOPSIS
        Dismisses the selected alert.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:AlertsGrid -or -not $script:AlertsGrid.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select an alert to dismiss.', 'No Selection', 'OK', 'Information')
        return
    }

    $alert = $script:AlertsGrid.SelectedItem
    $result = [System.Windows.MessageBox]::Show(
        "Are you sure you want to dismiss this alert?`n`n$($alert.Message)",
        'Confirm Dismiss',
        'YesNo',
        'Question'
    )

    if ($result -eq 'Yes') {
        if (Get-Command -Name 'Remove-CapacityAlert' -ErrorAction SilentlyContinue) {
            Remove-CapacityAlert -AlertID $alert.AlertID
        }
        Update-AlertsGrid
        Update-CapacityPlanningDashboard
    }
}

#endregion

#region Forecast Functions

function Update-ForecastScopeCombo {
    <#
    .SYNOPSIS
        Populates the forecast scope combo box.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:ForecastScopeCombo) { return }

    try {
        $sites = Get-SiteUtilization
        $items = @('All Sites')

        foreach ($site in $sites) {
            $items += $site.SiteID
        }

        $script:ForecastScopeCombo.ItemsSource = $items
        $script:ForecastScopeCombo.SelectedIndex = 0
    }
    catch {
        Write-Warning "Failed to populate forecast scope: $_"
    }
}

function Clear-ForecastResults {
    <#
    .SYNOPSIS
        Clears the forecast results display.
    #>
    [CmdletBinding()]
    param()

    if ($script:CurrentUtilizationLabel) { $script:CurrentUtilizationLabel.Content = '-' }
    if ($script:GrowthRateLabel) { $script:GrowthRateLabel.Content = '-' }
    if ($script:PortsPerMonthLabel) { $script:PortsPerMonthLabel.Content = '-' }
    if ($script:RSquaredLabel) { $script:RSquaredLabel.Content = '-' }
    if ($script:BreachDateLabel) { $script:BreachDateLabel.Content = '-' }
    if ($script:DaysUntilBreachLabel) { $script:DaysUntilBreachLabel.Content = '-' }
    if ($script:ForecastGrid) { $script:ForecastGrid.ItemsSource = $null }
}

function Run-CapacityForecast {
    <#
    .SYNOPSIS
        Runs capacity forecast for the selected scope.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:ForecastScopeCombo) { return }

    $scope = $script:ForecastScopeCombo.SelectedItem
    $period = if ($script:ForecastPeriodCombo) { $script:ForecastPeriodCombo.SelectedItem } else { '12 Months' }
    $threshold = if ($script:ForecastThresholdBox) {
        [int]$script:ForecastThresholdBox.Text
    } else {
        80
    }

    try {
        # Get historical data
        $history = Get-UtilizationHistory -Scope $scope

        if (-not $history -or $history.Count -lt 2) {
            [System.Windows.MessageBox]::Show(
                'Insufficient historical data for forecasting. At least 2 data points required.',
                'Insufficient Data',
                'OK',
                'Warning'
            )
            return
        }

        # Run linear forecast
        $forecast = Get-LinearForecast -History $history

        # Update display
        if ($script:CurrentUtilizationLabel) {
            $current = $history[-1].Percentage
            $script:CurrentUtilizationLabel.Content = "$current%"
        }

        if ($script:GrowthRateLabel -and $forecast.Slope) {
            $monthlyGrowth = [math]::Round($forecast.Slope * 30, 2)
            $script:GrowthRateLabel.Content = "$monthlyGrowth% / month"
        }

        if ($script:PortsPerMonthLabel -and $forecast.PortsPerMonth) {
            $script:PortsPerMonthLabel.Content = "$($forecast.PortsPerMonth) ports/month"
        }

        if ($script:RSquaredLabel -and $forecast.RSquared) {
            $script:RSquaredLabel.Content = [math]::Round($forecast.RSquared, 3).ToString()
        }

        # Calculate breach date
        $breachInfo = Get-ThresholdBreachDate -History $history -Threshold $threshold

        if ($script:BreachDateLabel) {
            if ($breachInfo.BreachDate) {
                $script:BreachDateLabel.Content = $breachInfo.BreachDate.ToString('yyyy-MM-dd')
            } else {
                $script:BreachDateLabel.Content = 'Not projected'
            }
        }

        if ($script:DaysUntilBreachLabel) {
            if ($breachInfo.DaysUntilBreach) {
                $script:DaysUntilBreachLabel.Content = "$($breachInfo.DaysUntilBreach) days"
            } else {
                $script:DaysUntilBreachLabel.Content = 'N/A'
            }
        }

        # Generate forecast timeline grid
        if ($script:ForecastGrid) {
            $months = switch ($period) {
                '3 Months' { 3 }
                '6 Months' { 6 }
                '12 Months' { 12 }
                '24 Months' { 24 }
                default { 12 }
            }

            $gridData = @()
            for ($i = 1; $i -le $months; $i++) {
                $forecastDate = (Get-Date).AddMonths($i)
                $projectedUtil = [math]::Round($history[-1].Percentage + ($forecast.Slope * 30 * $i), 1)
                $projectedUtil = [math]::Min($projectedUtil, 100)

                $status = 'Normal'
                if ($projectedUtil -ge 90) { $status = 'Critical' }
                elseif ($projectedUtil -ge $threshold) { $status = 'Warning' }

                $gridData += [PSCustomObject]@{
                    Month            = $forecastDate.ToString('MMM yyyy')
                    ProjectedUtil    = "$projectedUtil%"
                    ProjectedUsed    = [int]($history[-1].UsedPorts + ($forecast.PortsPerMonth * $i))
                    Status           = $status
                }
            }

            $script:ForecastGrid.ItemsSource = $gridData
        }
    }
    catch {
        Write-Warning "Failed to run forecast: $_"
        [System.Windows.MessageBox]::Show("Forecast error: $_", 'Error', 'OK', 'Error')
    }
}

function Export-ForecastReport {
    <#
    .SYNOPSIS
        Exports the current forecast to a file.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:ForecastGrid -or -not $script:ForecastGrid.ItemsSource) {
        [System.Windows.MessageBox]::Show('No forecast data to export. Run a forecast first.', 'No Data', 'OK', 'Information')
        return
    }

    $saveDialog = New-Object Microsoft.Win32.SaveFileDialog
    $saveDialog.Filter = 'CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'
    $saveDialog.FileName = "CapacityForecast_$(Get-Date -Format 'yyyyMMdd').csv"

    if ($saveDialog.ShowDialog()) {
        try {
            $script:ForecastGrid.ItemsSource | Export-Csv -Path $saveDialog.FileName -NoTypeInformation
            [System.Windows.MessageBox]::Show("Forecast exported to:`n$($saveDialog.FileName)", 'Export Complete', 'OK', 'Information')
        }
        catch {
            [System.Windows.MessageBox]::Show("Export failed: $_", 'Error', 'OK', 'Error')
        }
    }
}

#endregion

#region Scenario Functions

function Update-ScenarioInputLabel {
    <#
    .SYNOPSIS
        Updates the scenario input label based on selected type.
    #>
    [CmdletBinding()]
    param()

    # This would update a label to show context-appropriate input prompt
    # e.g., "Number of users" for Add Users, "Ports required" for Deploy VLAN
}

function Run-CapacityScenario {
    <#
    .SYNOPSIS
        Runs a what-if scenario analysis.
    #>
    [CmdletBinding()]
    param()

    $scenarioType = if ($script:ScenarioTypeCombo) { $script:ScenarioTypeCombo.SelectedItem } else { 'Add Users' }
    $scope = if ($script:ScenarioScopeCombo) { $script:ScenarioScopeCombo.SelectedItem } else { 'All Sites' }
    $value = if ($script:ScenarioValueBox) { [int]$script:ScenarioValueBox.Text } else { 10 }

    try {
        # Get current utilization
        $current = Get-SiteUtilization | Where-Object { $scope -eq 'All Sites' -or $_.SiteID -eq $scope }

        if (-not $current) {
            [System.Windows.MessageBox]::Show('No utilization data available for the selected scope.', 'No Data', 'OK', 'Warning')
            return
        }

        $totalPorts = ($current | Measure-Object -Property TotalPorts -Sum).Sum
        $usedPorts = ($current | Measure-Object -Property UsedPorts -Sum).Sum
        $currentPercent = [math]::Round(($usedPorts / $totalPorts) * 100, 1)

        # Calculate scenario impact based on type
        $additionalPorts = switch ($scenarioType) {
            'Add Users' { $value * 2 }  # Assume 2 ports per user (data + voice)
            'Deploy VLAN' { $value }     # Direct port count
            'Add Equipment' { $value * 48 }  # Assume 48-port switches
            default { $value }
        }

        $newUsed = $usedPorts + $additionalPorts
        $newPercent = [math]::Round(($newUsed / $totalPorts) * 100, 1)
        $impactPercent = $newPercent - $currentPercent
        $canAccommodate = $newPercent -lt 95

        # Update display
        if ($script:ScenarioCurrentLabel) {
            $script:ScenarioCurrentLabel.Content = "$currentPercent% ($usedPorts ports)"
        }

        if ($script:ScenarioNewLabel) {
            $script:ScenarioNewLabel.Content = "$newPercent% ($newUsed ports)"
        }

        if ($script:ScenarioImpactLabel) {
            $script:ScenarioImpactLabel.Content = "+$impactPercent% (+$additionalPorts ports)"
        }

        if ($script:ScenarioFeasibleLabel) {
            $script:ScenarioFeasibleLabel.Content = if ($canAccommodate) { 'Yes' } else { 'No - Capacity exceeded' }
            $script:ScenarioFeasibleLabel.Foreground = if ($canAccommodate) {
                [System.Windows.Media.Brushes]::Green
            } else {
                [System.Windows.Media.Brushes]::Red
            }
        }

        if ($script:ScenarioRecommendationBox) {
            $recommendation = if ($canAccommodate) {
                if ($newPercent -ge 80) {
                    "Scenario is feasible but will push utilization to $newPercent%. Consider planning for capacity expansion."
                } else {
                    "Scenario is feasible with comfortable headroom remaining ($([math]::Round(100 - $newPercent, 1))% available)."
                }
            } else {
                $needed = $newUsed - [math]::Floor($totalPorts * 0.9)
                "Cannot accommodate without expansion. Need approximately $needed additional ports to maintain 90% headroom."
            }
            $script:ScenarioRecommendationBox.Text = $recommendation
        }
    }
    catch {
        Write-Warning "Failed to run scenario: $_"
        [System.Windows.MessageBox]::Show("Scenario error: $_", 'Error', 'OK', 'Error')
    }
}

function Save-CurrentScenario {
    <#
    .SYNOPSIS
        Saves the current scenario for later comparison.
    #>
    [CmdletBinding()]
    param()

    if (Get-Command -Name 'Save-CapacityScenario' -ErrorAction SilentlyContinue) {
        $scenarioType = if ($script:ScenarioTypeCombo) { $script:ScenarioTypeCombo.SelectedItem } else { 'Add Users' }
        $scope = if ($script:ScenarioScopeCombo) { $script:ScenarioScopeCombo.SelectedItem } else { 'All Sites' }
        $value = if ($script:ScenarioValueBox) { [int]$script:ScenarioValueBox.Text } else { 10 }

        Save-CapacityScenario -Type $scenarioType -Scope $scope -Value $value
        [System.Windows.MessageBox]::Show('Scenario saved successfully.', 'Saved', 'OK', 'Information')
    }
}

function Compare-Scenarios {
    <#
    .SYNOPSIS
        Opens a comparison view for saved scenarios.
    #>
    [CmdletBinding()]
    param()

    [System.Windows.MessageBox]::Show('Scenario comparison feature coming soon.', 'Coming Soon', 'OK', 'Information')
}

#endregion

#region Budget Functions

function Calculate-BudgetProjection {
    <#
    .SYNOPSIS
        Calculates budget projections based on growth forecast.
    #>
    [CmdletBinding()]
    param()

    $year = if ($script:BudgetYearCombo) { $script:BudgetYearCombo.SelectedItem } else { '2026' }
    $growthPercent = if ($script:BudgetGrowthBox) { [double]$script:BudgetGrowthBox.Text } else { 10 }

    try {
        $current = Get-SiteUtilization
        $totalPorts = ($current | Measure-Object -Property TotalPorts -Sum).Sum
        $usedPorts = ($current | Measure-Object -Property UsedPorts -Sum).Sum

        # Calculate projected growth
        $additionalPorts = [math]::Ceiling($usedPorts * ($growthPercent / 100))
        $projectedUsed = $usedPorts + $additionalPorts

        # Calculate switches needed (48-port switches)
        $switchesNeeded = [math]::Ceiling($additionalPorts / 48)

        # Get cost estimate
        if (Get-Command -Name 'Get-TotalCostEstimate' -ErrorAction SilentlyContinue) {
            $costEstimate = Get-TotalCostEstimate -SwitchCount $switchesNeeded
        } else {
            # Default estimates
            $hardwareCost = $switchesNeeded * 8000  # $8k per switch
            $costEstimate = @{
                HardwareCost = $hardwareCost
                TotalCost = $hardwareCost * 1.5  # Include installation and maintenance
            }
        }

        # Update display
        if ($script:ProjectedPortsLabel) {
            $script:ProjectedPortsLabel.Content = "$additionalPorts ports needed"
        }

        if ($script:SwitchesNeededLabel) {
            $script:SwitchesNeededLabel.Content = "$switchesNeeded switches"
        }

        if ($script:HardwareCostLabel) {
            $script:HardwareCostLabel.Content = '$' + $costEstimate.HardwareCost.ToString('N0')
        }

        if ($script:TotalCostLabel) {
            $script:TotalCostLabel.Content = '$' + $costEstimate.TotalCost.ToString('N0')
        }

        # Update redeployment candidates
        if ($script:RedeploymentGrid -and (Get-Command -Name 'Get-RedeploymentCandidates' -ErrorAction SilentlyContinue)) {
            $candidates = Get-RedeploymentCandidates
            $script:RedeploymentGrid.ItemsSource = $candidates
        }
    }
    catch {
        Write-Warning "Failed to calculate budget: $_"
        [System.Windows.MessageBox]::Show("Budget calculation error: $_", 'Error', 'OK', 'Error')
    }
}

function Export-BudgetReport {
    <#
    .SYNOPSIS
        Exports the budget projection to a file.
    #>
    [CmdletBinding()]
    param()

    $saveDialog = New-Object Microsoft.Win32.SaveFileDialog
    $saveDialog.Filter = 'CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'
    $saveDialog.FileName = "CapacityBudget_$(Get-Date -Format 'yyyyMMdd').csv"

    if ($saveDialog.ShowDialog()) {
        try {
            $report = @{
                GeneratedDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                ProjectedPorts = $script:ProjectedPortsLabel.Content
                SwitchesNeeded = $script:SwitchesNeededLabel.Content
                HardwareCost = $script:HardwareCostLabel.Content
                TotalCost = $script:TotalCostLabel.Content
            }
            [PSCustomObject]$report | Export-Csv -Path $saveDialog.FileName -NoTypeInformation
            [System.Windows.MessageBox]::Show("Budget report exported to:`n$($saveDialog.FileName)", 'Export Complete', 'OK', 'Information')
        }
        catch {
            [System.Windows.MessageBox]::Show("Export failed: $_", 'Error', 'OK', 'Error')
        }
    }
}

#endregion

#region Threshold Functions

function Update-ThresholdsGrid {
    <#
    .SYNOPSIS
        Updates the thresholds data grid.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:ThresholdsGrid) { return }

    try {
        $thresholds = Get-CapacityThreshold

        $gridData = @()
        foreach ($threshold in $thresholds) {
            $gridData += [PSCustomObject]@{
                ThresholdID    = $threshold.ThresholdID
                Scope          = $threshold.Scope
                MetricType     = $threshold.MetricType
                WarningLevel   = "$($threshold.WarningLevel)%"
                CriticalLevel  = "$($threshold.CriticalLevel)%"
                IsEnabled      = $threshold.IsEnabled
            }
        }

        $script:ThresholdsGrid.ItemsSource = $gridData
    }
    catch {
        Write-Warning "Failed to update thresholds grid: $_"
    }
}

function New-ThresholdEntry {
    <#
    .SYNOPSIS
        Creates a new threshold entry.
    #>
    [CmdletBinding()]
    param()

    # For now, show a simple message. Full implementation would use a dialog.
    [System.Windows.MessageBox]::Show(
        'To add a new threshold, use PowerShell:`nAdd-CapacityThreshold -Scope "SITE-A" -MetricType "Port" -WarningLevel 75 -CriticalLevel 90',
        'Add Threshold',
        'OK',
        'Information'
    )
}

function Edit-SelectedThreshold {
    <#
    .SYNOPSIS
        Edits the selected threshold.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:ThresholdsGrid -or -not $script:ThresholdsGrid.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select a threshold to edit.', 'No Selection', 'OK', 'Information')
        return
    }

    $threshold = $script:ThresholdsGrid.SelectedItem
    [System.Windows.MessageBox]::Show(
        "Edit threshold for scope: $($threshold.Scope)`nUse Set-CapacityThreshold to modify.",
        'Edit Threshold',
        'OK',
        'Information'
    )
}

function Remove-SelectedThreshold {
    <#
    .SYNOPSIS
        Removes the selected threshold.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:ThresholdsGrid -or -not $script:ThresholdsGrid.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select a threshold to delete.', 'No Selection', 'OK', 'Information')
        return
    }

    $threshold = $script:ThresholdsGrid.SelectedItem
    $result = [System.Windows.MessageBox]::Show(
        "Delete threshold for scope '$($threshold.Scope)'?",
        'Confirm Delete',
        'YesNo',
        'Question'
    )

    if ($result -eq 'Yes') {
        if (Get-Command -Name 'Remove-CapacityThreshold' -ErrorAction SilentlyContinue) {
            Remove-CapacityThreshold -ThresholdID $threshold.ThresholdID
        }
        Update-ThresholdsGrid
    }
}

function Apply-DefaultThresholds {
    <#
    .SYNOPSIS
        Applies default thresholds to all scopes.
    #>
    [CmdletBinding()]
    param()

    $result = [System.Windows.MessageBox]::Show(
        'Apply default thresholds to all sites?',
        'Apply Defaults',
        'YesNo',
        'Question'
    )

    if ($result -eq 'Yes') {
        $warning = if ($script:DefaultWarningBox) { [int]$script:DefaultWarningBox.Text } else { 75 }
        $critical = if ($script:DefaultCriticalBox) { [int]$script:DefaultCriticalBox.Text } else { 90 }

        $sites = Get-SiteUtilization
        foreach ($site in $sites) {
            if (Get-Command -Name 'Add-CapacityThreshold' -ErrorAction SilentlyContinue) {
                Add-CapacityThreshold -Scope $site.SiteID -MetricType 'Port' -WarningLevel $warning -CriticalLevel $critical
            }
        }

        Update-ThresholdsGrid
        [System.Windows.MessageBox]::Show('Default thresholds applied to all sites.', 'Complete', 'OK', 'Information')
    }
}

function Save-DefaultThresholds {
    <#
    .SYNOPSIS
        Saves the default threshold values.
    #>
    [CmdletBinding()]
    param()

    $warning = if ($script:DefaultWarningBox) { [int]$script:DefaultWarningBox.Text } else { 75 }
    $critical = if ($script:DefaultCriticalBox) { [int]$script:DefaultCriticalBox.Text } else { 90 }

    # Save to settings
    if (Get-Command -Name 'Set-StateTraceSettings' -ErrorAction SilentlyContinue) {
        Set-StateTraceSettings -Key 'CapacityPlanning.DefaultWarning' -Value $warning
        Set-StateTraceSettings -Key 'CapacityPlanning.DefaultCritical' -Value $critical
    }

    [System.Windows.MessageBox]::Show("Default thresholds saved:`nWarning: $warning%`nCritical: $critical%", 'Saved', 'OK', 'Information')
}

#endregion

#region Report Functions

function Update-ReportsGrid {
    <#
    .SYNOPSIS
        Updates the reports data grid.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:ReportsGrid) { return }

    try {
        $reports = Get-CapacityReport

        $gridData = @()
        foreach ($report in $reports) {
            $gridData += [PSCustomObject]@{
                ReportID      = $report.ReportID
                ReportType    = $report.ReportType
                Scope         = $report.Scope
                GeneratedDate = $report.GeneratedDate
                FilePath      = $report.FilePath
            }
        }

        $script:ReportsGrid.ItemsSource = $gridData
    }
    catch {
        Write-Warning "Failed to update reports grid: $_"
    }
}

function Generate-CapacityReport {
    <#
    .SYNOPSIS
        Generates a new capacity report.
    #>
    [CmdletBinding()]
    param()

    $reportType = if ($script:ReportTypeCombo) { $script:ReportTypeCombo.SelectedItem } else { 'Executive' }
    $scope = if ($script:ReportScopeCombo) { $script:ReportScopeCombo.SelectedItem } else { 'All Sites' }

    try {
        if (Get-Command -Name 'New-CapacityReport' -ErrorAction SilentlyContinue) {
            $report = New-CapacityReport -Type $reportType -Scope $scope
            Update-ReportsGrid
            [System.Windows.MessageBox]::Show("Report generated: $($report.FilePath)", 'Report Generated', 'OK', 'Information')
        } else {
            [System.Windows.MessageBox]::Show('Report generation not available.', 'Not Available', 'OK', 'Warning')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Failed to generate report: $_", 'Error', 'OK', 'Error')
    }
}

function View-SelectedReport {
    <#
    .SYNOPSIS
        Views the selected report.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:ReportsGrid -or -not $script:ReportsGrid.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select a report to view.', 'No Selection', 'OK', 'Information')
        return
    }

    $report = $script:ReportsGrid.SelectedItem
    if (Test-Path $report.FilePath) {
        Start-Process $report.FilePath
    } else {
        [System.Windows.MessageBox]::Show("Report file not found: $($report.FilePath)", 'Not Found', 'OK', 'Warning')
    }
}

function Export-SelectedReport {
    <#
    .SYNOPSIS
        Exports the selected report to a new location.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:ReportsGrid -or -not $script:ReportsGrid.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select a report to export.', 'No Selection', 'OK', 'Information')
        return
    }

    $report = $script:ReportsGrid.SelectedItem
    $saveDialog = New-Object Microsoft.Win32.SaveFileDialog
    $saveDialog.Filter = 'All Files (*.*)|*.*'
    $saveDialog.FileName = Split-Path $report.FilePath -Leaf

    if ($saveDialog.ShowDialog()) {
        try {
            Copy-Item -Path $report.FilePath -Destination $saveDialog.FileName -Force
            [System.Windows.MessageBox]::Show("Report exported to:`n$($saveDialog.FileName)", 'Export Complete', 'OK', 'Information')
        }
        catch {
            [System.Windows.MessageBox]::Show("Export failed: $_", 'Error', 'OK', 'Error')
        }
    }
}

function Remove-SelectedReport {
    <#
    .SYNOPSIS
        Deletes the selected report.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:ReportsGrid -or -not $script:ReportsGrid.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select a report to delete.', 'No Selection', 'OK', 'Information')
        return
    }

    $report = $script:ReportsGrid.SelectedItem
    $result = [System.Windows.MessageBox]::Show(
        "Delete report '$($report.ReportType) - $($report.Scope)'?",
        'Confirm Delete',
        'YesNo',
        'Question'
    )

    if ($result -eq 'Yes') {
        if (Get-Command -Name 'Remove-CapacityReport' -ErrorAction SilentlyContinue) {
            Remove-CapacityReport -ReportID $report.ReportID
        }
        if (Test-Path $report.FilePath) {
            Remove-Item -Path $report.FilePath -Force -ErrorAction SilentlyContinue
        }
        Update-ReportsGrid
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'New-CapacityPlanningView'
)
