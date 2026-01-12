#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Pester tests for CapacityPlanningModule.

.DESCRIPTION
    Tests utilization calculations, trend analysis, threshold management,
    what-if scenarios, and budget planning.
#>

# Import the module under test
$modulePath = Join-Path $PSScriptRoot '..\CapacityPlanningModule.psm1'
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
}

Describe 'CapacityPlanningModule' {

    BeforeEach {
        # Initialize in test mode to avoid persisting data
        Initialize-CapacityPlanningDatabase -TestMode
    }

    AfterEach {
        Clear-CapacityPlanningData
    }

    #region Utilization Calculations

    Context 'Port Utilization' {
        It 'calculates device port utilization correctly' {
            $device = @{
                TotalPorts = 48
                UsedPorts = 36
            }

            $util = Get-PortUtilization -Device $device

            $util.Percentage | Should Be 75
            $util.AvailablePorts | Should Be 12
            $util.TotalPorts | Should Be 48
            $util.UsedPorts | Should Be 36
        }

        It 'handles zero total ports' {
            $device = @{ TotalPorts = 0; UsedPorts = 0 }
            $util = Get-PortUtilization -Device $device
            $util.Percentage | Should Be 0
        }

        It 'works with PSCustomObject input' {
            $device = [PSCustomObject]@{
                TotalPorts = 24
                UsedPorts = 18
            }
            $util = Get-PortUtilization -Device $device
            $util.Percentage | Should Be 75
        }
    }

    Context 'PoE Utilization' {
        It 'calculates PoE utilization correctly' {
            $device = @{
                PoEBudgetWatts = 740
                PoEUsedWatts = 550
            }

            $poe = Get-PoEUtilization -Device $device

            $poe.Percentage | Should BeGreaterThan 74
            $poe.AvailableWatts | Should Be 190
        }

        It 'handles zero budget' {
            $device = @{ PoEBudgetWatts = 0; PoEUsedWatts = 0 }
            $poe = Get-PoEUtilization -Device $device
            $poe.Percentage | Should Be 0
        }
    }

    Context 'Site Utilization' {
        It 'aggregates utilization by site' {
            $devices = @(
                @{ SiteID = 'SITE-A'; TotalPorts = 48; UsedPorts = 40 },
                @{ SiteID = 'SITE-A'; TotalPorts = 48; UsedPorts = 30 },
                @{ SiteID = 'SITE-B'; TotalPorts = 24; UsedPorts = 20 }
            )

            $siteUtil = Get-SiteUtilization -Devices $devices

            $siteA = $siteUtil | Where-Object { $_.SiteID -eq 'SITE-A' }
            $siteA.TotalPorts | Should Be 96
            $siteA.UsedPorts | Should Be 70
            $siteA.Percentage | Should BeGreaterThan 72
            $siteA.DeviceCount | Should Be 2
        }

        It 'sorts by utilization descending' {
            $devices = @(
                @{ SiteID = 'LOW'; TotalPorts = 100; UsedPorts = 20 },
                @{ SiteID = 'HIGH'; TotalPorts = 100; UsedPorts = 90 }
            )

            $siteUtil = Get-SiteUtilization -Devices $devices

            $siteUtil[0].SiteID | Should Be 'HIGH'
        }
    }

    Context 'VLAN Utilization' {
        It 'tracks utilization by VLAN' {
            $ports = @(
                @{ VLAN = 10; IsUsed = $true },
                @{ VLAN = 10; IsUsed = $true },
                @{ VLAN = 10; IsUsed = $false },
                @{ VLAN = 20; IsUsed = $true }
            )

            $vlanUtil = Get-VLANUtilization -Ports $ports

            $vlan10 = $vlanUtil | Where-Object { $_.VLAN -eq 10 }
            $vlan10.TotalPorts | Should Be 3
            $vlan10.UsedPorts | Should Be 2
        }

        It 'handles ports without VLAN' {
            $ports = @(
                @{ IsUsed = $true },
                @{ VLAN = 10; IsUsed = $false }
            )

            $vlanUtil = Get-VLANUtilization -Ports $ports

            @($vlanUtil).Count | Should Be 2
        }
    }

    #endregion

    #region Snapshot Management

    Context 'Utilization Snapshots' {
        It 'creates utilization snapshot' {
            $snapshot = New-UtilizationSnapshot -Scope 'Site' -ScopeID 'CAMPUS-MAIN' -TotalPorts 100 -UsedPorts 75

            $snapshot.SnapshotID | Should Not BeNullOrEmpty
            $snapshot.SnapshotDate | Should Not BeNullOrEmpty
            $snapshot.ScopeType | Should Be 'Site'
            $snapshot.ScopeID | Should Be 'CAMPUS-MAIN'
            $snapshot.Utilization | Should Be 75
        }

        It 'retrieves snapshots by scope' {
            $null = New-UtilizationSnapshot -Scope 'Site' -ScopeID 'SITE-A' -TotalPorts 100 -UsedPorts 50
            $null = New-UtilizationSnapshot -Scope 'Site' -ScopeID 'SITE-B' -TotalPorts 100 -UsedPorts 60
            $null = New-UtilizationSnapshot -Scope 'Device' -ScopeID 'SW-01' -TotalPorts 48 -UsedPorts 40

            $siteSnapshots = Get-UtilizationSnapshot -Scope 'Site'

            @($siteSnapshots).Count | Should Be 2
        }

        It 'retrieves snapshots by date range' {
            $null = New-UtilizationSnapshot -Scope 'Site' -ScopeID 'TEST' -TotalPorts 100 -UsedPorts 50

            $snapshots = Get-UtilizationSnapshot -StartDate (Get-Date).AddDays(-1) -EndDate (Get-Date).AddDays(1)

            @($snapshots).Count | Should BeGreaterThan 0
        }

        It 'calculates utilization percentage' {
            $snapshot = New-UtilizationSnapshot -Scope 'Site' -ScopeID 'TEST' -TotalPorts 200 -UsedPorts 150

            $snapshot.Utilization | Should Be 75
        }
    }

    #endregion

    #region Trend Analysis

    Context 'Growth Rate Calculation' {
        It 'calculates monthly growth rate' {
            $history = @(
                @{ Date = '2025-10-01'; UsedPorts = 100 },
                @{ Date = '2025-11-01'; UsedPorts = 108 },
                @{ Date = '2025-12-01'; UsedPorts = 115 },
                @{ Date = '2026-01-01'; UsedPorts = 122 }
            )

            $growth = Get-GrowthRate -History $history -Period Monthly

            $growth.PortsPerMonth | Should BeGreaterThan 7
            $growth.TotalChange | Should Be 22
            $growth.DataPoints | Should Be 4
        }

        It 'handles insufficient data' {
            $history = @(
                @{ Date = '2025-10-01'; UsedPorts = 100 }
            )

            $growth = Get-GrowthRate -History $history

            $growth.PortsPerMonth | Should Be 0
            $growth.DataPoints | Should Be 1
        }
    }

    Context 'Linear Regression Forecast' {
        It 'performs linear regression for forecasting' {
            $history = @(
                @{ Date = '2025-10-01'; UsedPorts = 100 },
                @{ Date = '2025-11-01'; UsedPorts = 108 },
                @{ Date = '2025-12-01'; UsedPorts = 116 },
                @{ Date = '2026-01-01'; UsedPorts = 124 }
            )

            $forecast = Get-LinearForecast -History $history

            $forecast.Slope | Should BeGreaterThan 0
            $forecast.RSquared | Should BeGreaterThan 0.9
        }

        It 'returns zero slope for single data point' {
            $history = @(
                @{ Date = '2025-10-01'; UsedPorts = 100 }
            )

            $forecast = Get-LinearForecast -History $history

            $forecast.Slope | Should Be 0
        }
    }

    Context 'Threshold Breach Prediction' {
        It 'predicts threshold breach date' {
            $history = @(
                @{ Date = (Get-Date).AddDays(-90).ToString('yyyy-MM-dd'); UsedPorts = 100 },
                @{ Date = (Get-Date).AddDays(-60).ToString('yyyy-MM-dd'); UsedPorts = 120 },
                @{ Date = (Get-Date).AddDays(-30).ToString('yyyy-MM-dd'); UsedPorts = 140 },
                @{ Date = (Get-Date).ToString('yyyy-MM-dd'); UsedPorts = 160 }
            )

            $prediction = Get-ThresholdBreachDate -History $history -TotalCapacity 200 -Threshold 0.80

            $prediction.WillBreach | Should Be $true
            $prediction.DaysUntilBreach | Should Not BeNullOrEmpty
        }

        It 'handles already breached threshold' {
            $history = @(
                @{ Date = (Get-Date).AddDays(-30).ToString('yyyy-MM-dd'); UsedPorts = 170 },
                @{ Date = (Get-Date).ToString('yyyy-MM-dd'); UsedPorts = 180 }
            )

            $prediction = Get-ThresholdBreachDate -History $history -TotalCapacity 200 -Threshold 0.80

            $prediction.WillBreach | Should Be $true
            $prediction.DaysUntilBreach | Should Be 0
            $prediction.Message | Should Match 'already breached'
        }

        It 'handles no growth scenario' {
            $history = @(
                @{ Date = (Get-Date).AddDays(-30).ToString('yyyy-MM-dd'); UsedPorts = 100 },
                @{ Date = (Get-Date).ToString('yyyy-MM-dd'); UsedPorts = 100 }
            )

            $prediction = Get-ThresholdBreachDate -History $history -TotalCapacity 200 -Threshold 0.80

            $prediction.WillBreach | Should Be $false
        }
    }

    Context 'Seasonal Analysis' {
        It 'detects seasonal patterns' {
            $history = @(
                @{ Date = '2025-01-15'; UsedPorts = 100 },
                @{ Date = '2025-04-15'; UsedPorts = 110 },
                @{ Date = '2025-07-15'; UsedPorts = 75 },
                @{ Date = '2025-10-15'; UsedPorts = 120 }
            )

            $seasonal = Get-SeasonalForecast -History $history

            $seasonal | Should Not BeNullOrEmpty
            $seasonal.QuarterAverages | Should Not BeNullOrEmpty
        }

        It 'requires minimum data points' {
            $history = @(
                @{ Date = '2025-01-01'; UsedPorts = 100 },
                @{ Date = '2025-02-01'; UsedPorts = 105 }
            )

            $seasonal = Get-SeasonalForecast -History $history

            $seasonal.HasSeasonalPattern | Should Be $false
            $seasonal.Message | Should Match 'Insufficient'
        }
    }

    #endregion

    #region Threshold Management

    Context 'Capacity Thresholds' {
        It 'initializes with default thresholds' {
            $thresholds = Get-CapacityThreshold

            @($thresholds).Count | Should BeGreaterThan 0
        }

        It 'creates custom threshold' {
            $threshold = New-CapacityThreshold -ScopeType 'Site' -ScopeID 'CAMPUS' -MetricName 'PortUtilization' -WarningLevel 75 -CriticalLevel 90 -IsEnabled

            $threshold.ThresholdID | Should Not BeNullOrEmpty
            $threshold.WarningLevel | Should Be 75
            $threshold.CriticalLevel | Should Be 90
            $threshold.IsEnabled | Should Be $true
        }
    }

    Context 'Capacity Warnings' {
        It 'identifies devices above warning threshold' {
            $devices = @(
                @{ Hostname = 'SW-01'; TotalPorts = 48; UsedPorts = 40 },
                @{ Hostname = 'SW-02'; TotalPorts = 48; UsedPorts = 30 },
                @{ Hostname = 'SW-03'; TotalPorts = 48; UsedPorts = 45 }
            )

            $warnings = Get-CapacityWarnings -Devices $devices -WarningThreshold 0.70

            @($warnings).Count | Should Be 2
            ($warnings.Hostname -contains 'SW-01') | Should Be $true
            ($warnings.Hostname -contains 'SW-03') | Should Be $true
        }

        It 'categorizes by severity level' {
            $device = @{ TotalPorts = 100; UsedPorts = 92 }

            $status = Get-CapacityStatus -Device $device -WarningThreshold 0.70 -CriticalThreshold 0.85

            $status.Severity | Should Be 'Critical'
        }

        It 'returns Normal for low utilization' {
            $device = @{ TotalPorts = 100; UsedPorts = 50 }

            $status = Get-CapacityStatus -Device $device -WarningThreshold 0.70 -CriticalThreshold 0.85

            $status.Severity | Should Be 'Normal'
        }
    }

    Context 'Forecast Alerts' {
        It 'generates forecast-based alerts' {
            $forecast = @{
                ProjectedExhaustionDate = (Get-Date).AddDays(60)
            }

            $alert = Get-ForecastAlert -Forecast $forecast -AlertDays 90

            $alert.ShouldAlert | Should Be $true
            $alert.DaysUntilExhaustion | Should BeGreaterThan 55
            $alert.DaysUntilExhaustion | Should BeLessThan 65
        }

        It 'does not alert for distant exhaustion' {
            $forecast = @{
                ProjectedExhaustionDate = (Get-Date).AddDays(365)
            }

            $alert = Get-ForecastAlert -Forecast $forecast -AlertDays 90

            $alert.ShouldAlert | Should Be $false
        }
    }

    #endregion

    #region What-If Scenarios

    Context 'Scenario Impact Analysis' {
        It 'calculates impact of adding users' {
            $currentState = @{
                TotalPorts = 100
                UsedPorts = 75
                PortsPerUser = 1.2
            }

            $impact = Get-ScenarioImpact -CurrentState $currentState -AddUsers 20

            $impact.NewUsedPorts | Should Be 99
            $impact.AdditionalPorts | Should Be 24
            $impact.CanAccommodate | Should Be $true
        }

        It 'detects when capacity is exceeded' {
            $currentState = @{
                TotalPorts = 100
                UsedPorts = 90
                PortsPerUser = 1.5
            }

            $impact = Get-ScenarioImpact -CurrentState $currentState -AddUsers 20

            $impact.CanAccommodate | Should Be $false
        }
    }

    Context 'VLAN Deployment Scenario' {
        It 'models new VLAN deployment' {
            $currentState = @{
                Devices = @(
                    @{ Hostname = 'SW-01'; TotalPorts = 48; UsedPorts = 35 },
                    @{ Hostname = 'SW-02'; TotalPorts = 48; UsedPorts = 40 }
                )
            }

            $scenario = New-VLANDeploymentScenario -CurrentState $currentState -NewVLAN 100 -EstimatedPorts 10

            $scenario.CanAccommodate | Should Be $true
            $scenario.RecommendedDevice | Should Be 'SW-01'
        }

        It 'detects insufficient capacity' {
            $currentState = @{
                Devices = @(
                    @{ Hostname = 'SW-01'; TotalPorts = 48; UsedPorts = 45 }
                )
            }

            $scenario = New-VLANDeploymentScenario -CurrentState $currentState -NewVLAN 100 -EstimatedPorts 10

            $scenario.CanAccommodate | Should Be $false
        }
    }

    Context 'Planning Scenarios' {
        It 'creates planning scenario' {
            $scenario = New-PlanningScenario -Name 'Add Building' -Description 'New building expansion' -CostEstimate 50000

            $scenario.ScenarioID | Should Not BeNullOrEmpty
            $scenario.Name | Should Be 'Add Building'
            $scenario.CostEstimate | Should Be 50000
        }

        It 'retrieves scenarios by name' {
            $null = New-PlanningScenario -Name 'Expansion Plan' -Description 'Test'
            $null = New-PlanningScenario -Name 'Consolidation' -Description 'Test'

            $scenarios = Get-PlanningScenario -Name 'Expansion'

            @($scenarios).Count | Should Be 1
            $scenarios[0].Name | Should Match 'Expansion'
        }
    }

    Context 'Scenario Comparison' {
        It 'compares multiple scenarios' {
            $scenarios = @(
                @{ Name = 'Add Switch'; Cost = 5000; CapacityGain = 48 },
                @{ Name = 'Upgrade to 10G'; Cost = 15000; CapacityGain = 0 },
                @{ Name = 'Consolidate'; Cost = 0; CapacityGain = 24 }
            )

            $comparison = Compare-Scenarios -Scenarios $scenarios

            $comparison[0].Name | Should Be 'Consolidate'
            $comparison[0].CostPerPort | Should Be 0
        }
    }

    #endregion

    #region Budget Planning

    Context 'Hardware Projections' {
        It 'estimates hardware needs for growth' {
            $projections = Get-HardwareProjection `
                -CurrentUtilization 0.75 `
                -GrowthRateMonthly 0.02 `
                -PlanningHorizonMonths 24 `
                -DeviceCapacity 48 `
                -CurrentTotalPorts 1000

            $projections.AdditionalDevicesNeeded | Should BeGreaterThan 0
        }

        It 'handles no growth scenario' {
            $projections = Get-HardwareProjection `
                -CurrentUtilization 0.50 `
                -GrowthRateMonthly 0 `
                -PlanningHorizonMonths 12 `
                -CurrentTotalPorts 100

            $projections.AdditionalPortsNeeded | Should Be 0
        }
    }

    Context 'Total Cost Estimation' {
        It 'calculates total cost of ownership' {
            $equipment = @(
                @{ Type = 'Switch'; Model = 'C9300-48P'; Count = 2; UnitCost = 5000 }
            )

            $tco = Get-TotalCostEstimate -Equipment $equipment `
                -InstallationCostPerDevice 500 `
                -YearlyMaintenancePercent 0.15 `
                -Years 5

            $tco.HardwareCost | Should Be 10000
            $tco.InstallationCost | Should Be 1000
            $tco.FiveYearTCO | Should BeGreaterThan 15000
        }

        It 'handles multiple equipment types' {
            $equipment = @(
                @{ Count = 2; UnitCost = 5000 },
                @{ Count = 1; UnitCost = 10000 }
            )

            $tco = Get-TotalCostEstimate -Equipment $equipment -InstallationCostPerDevice 500

            $tco.HardwareCost | Should Be 20000
            $tco.DeviceCount | Should Be 3
            $tco.InstallationCost | Should Be 1500
        }
    }

    Context 'Redeployment Candidates' {
        It 'identifies redeployment candidates' {
            $devices = @(
                @{ Hostname = 'SW-OLD'; UsedPorts = 5; TotalPorts = 48; Age = 2 },
                @{ Hostname = 'SW-FULL'; UsedPorts = 45; TotalPorts = 48; Age = 1 }
            )

            $candidates = Get-RedeploymentCandidates -Devices $devices -MaxUtilization 0.30

            @($candidates).Count | Should Be 1
            $candidates[0].Hostname | Should Be 'SW-OLD'
        }

        It 'sorts by utilization ascending' {
            $devices = @(
                @{ Hostname = 'SW-A'; UsedPorts = 10; TotalPorts = 48 },
                @{ Hostname = 'SW-B'; UsedPorts = 5; TotalPorts = 48 }
            )

            $candidates = Get-RedeploymentCandidates -Devices $devices -MaxUtilization 0.30

            $candidates[0].Hostname | Should Be 'SW-B'
        }
    }

    #endregion

    #region Reports

    Context 'Capacity Reports' {
        It 'generates executive capacity summary' {
            $report = New-CapacityReport -Type Executive

            ($report.Sections -contains 'Summary') | Should Be $true
            ($report.Sections -contains 'RiskAreas') | Should Be $true
            ($report.Sections -contains 'Recommendations') | Should Be $true
        }

        It 'generates detailed planning report' {
            $report = New-CapacityReport -Type Detailed -Scope 'Enterprise'

            ($report.Sections -contains 'DeviceDetails') | Should Be $true
            ($report.Sections -contains 'Forecasts') | Should Be $true
        }

        It 'generates summary report' {
            $report = New-CapacityReport -Type Summary

            ($report.Sections -contains 'Summary') | Should Be $true
            ($report.Sections -contains 'Utilization') | Should Be $true
        }
    }

    Context 'Statistics' {
        It 'returns capacity statistics' {
            $null = New-UtilizationSnapshot -Scope 'Site' -ScopeID 'TEST' -TotalPorts 100 -UsedPorts 50
            $null = New-PlanningScenario -Name 'Test' -Description 'Test'

            $stats = Get-CapacityStatistics

            $stats.TotalSnapshots | Should BeGreaterThan 0
            $stats.TotalScenarios | Should BeGreaterThan 0
        }
    }

    #endregion

    #region Enhanced Scenario Comparison (ST-AC-005)

    Context 'Equipment Scenarios' {
        It 'creates equipment scenario with costs' {
            $scenario = New-EquipmentScenario -Name 'Add Switches' -EquipmentType 'Switch' -Model 'C9300-48P' -Quantity 2 -PortsPerUnit 48 -UnitCost 5000

            $scenario.ScenarioID | Should Not BeNullOrEmpty
            $scenario.ScenarioType | Should Be 'AddEquipment'
            $scenario.TotalPortsAdded | Should Be 96
            $scenario.HardwareCost | Should Be 10000
            $scenario.TotalCost | Should Be 11000
        }

        It 'calculates cost per port' {
            $scenario = New-EquipmentScenario -Name 'Test' -EquipmentType 'Switch' -Model 'Test' -Quantity 1 -PortsPerUnit 48 -UnitCost 4800 -InstallationCostPerUnit 0

            $scenario.CostPerPort | Should Be 100
        }

        It 'includes PoE budget' {
            $scenario = New-EquipmentScenario -Name 'PoE Switch' -EquipmentType 'Switch' -Model 'C9300-48P' -Quantity 2 -PortsPerUnit 48 -UnitCost 5000 -PoEBudgetPerUnit 740

            $scenario.PoEBudgetAdded | Should Be 1480
        }
    }

    Context 'Technology Refresh Scenarios' {
        It 'creates technology refresh scenario' {
            $scenario = New-TechnologyRefreshScenario -Name '1G to 10G Upgrade' -RefreshType '1Gto10G' -DevicesToReplace 4 -OldDeviceValue 2000 -NewDeviceCost 5000

            $scenario.ScenarioID | Should Not BeNullOrEmpty
            $scenario.ScenarioType | Should Be 'TechnologyRefresh'
            $scenario.DevicesToReplace | Should Be 4
            $scenario.NewHardwareCost | Should Be 20000
        }

        It 'calculates trade-in value' {
            $scenario = New-TechnologyRefreshScenario -Name 'Refresh' -RefreshType '1Gto10G' -DevicesToReplace 2 -OldDeviceValue 1000 -NewDeviceCost 3000

            $scenario.TradeInValue | Should Be 200
        }

        It 'calculates net cost with disposal' {
            $scenario = New-TechnologyRefreshScenario -Name 'Refresh' -RefreshType '1Gto10G' -DevicesToReplace 2 -OldDeviceValue 1000 -NewDeviceCost 3000 -InstallationCostPerDevice 500 -DisposalCostPerDevice 50

            # NewHardwareCost: 6000 + Install: 1000 + Disposal: 100 - TradeIn: 200 = 6900
            $scenario.NetCost | Should Be 6900
        }

        It 'calculates capacity gain cost per port' {
            $scenario = New-TechnologyRefreshScenario -Name 'Refresh' -RefreshType '1Gto10G' -DevicesToReplace 1 -OldDeviceValue 1000 -NewDeviceCost 5000 -CapacityGainPerDevice 24 -InstallationCostPerDevice 0 -DisposalCostPerDevice 0

            # NetCost: 5000 - 100 (trade-in) = 4900, CapacityGain: 24
            $scenario.TotalCapacityGain | Should Be 24
            $scenario.CostPerPortGain | Should Not BeNullOrEmpty
        }
    }

    Context 'Advanced Scenario Comparison' {
        It 'compares equipment and refresh scenarios' {
            $null = New-EquipmentScenario -Name 'Add Switches' -EquipmentType 'Switch' -Model 'C9300-48P' -Quantity 2 -PortsPerUnit 48 -UnitCost 5000
            $null = New-TechnologyRefreshScenario -Name '1G Upgrade' -RefreshType '1Gto10G' -DevicesToReplace 2 -OldDeviceValue 2000 -NewDeviceCost 6000 -CapacityGainPerDevice 24

            $comparison = Get-ScenarioComparison

            $comparison.ScenariosCompared | Should Be 2
            $comparison.Results | Should Not BeNullOrEmpty
            $comparison.BestValue | Should Not BeNullOrEmpty
        }

        It 'calculates ROI when requested' {
            $null = New-EquipmentScenario -Name 'Test' -EquipmentType 'Switch' -Model 'Test' -Quantity 1 -PortsPerUnit 48 -UnitCost 4800

            $comparison = Get-ScenarioComparison -IncludeROI -ROIYears 5 -AnnualSavingsPerPort 100

            $comparison.Results[0].ROIPercent | Should Not BeNullOrEmpty
            $comparison.Results[0].PaybackMonths | Should Not BeNullOrEmpty
        }

        It 'provides recommendation' {
            $null = New-EquipmentScenario -Name 'Best Value' -EquipmentType 'Switch' -Model 'Test' -Quantity 1 -PortsPerUnit 48 -UnitCost 2400

            $comparison = Get-ScenarioComparison

            $comparison.Recommendation | Should Match 'Recommended'
        }

        It 'handles empty scenario list' {
            Clear-CapacityPlanningData

            $comparison = Get-ScenarioComparison

            $comparison.ScenariosCompared | Should Be 0
            $comparison.Recommendation | Should Match 'No scenarios'
        }
    }

    #endregion

    #region Budget Planning Reports (ST-AC-006)

    Context 'Budget Planning Report' {
        It 'generates multi-year budget report' {
            $report = Get-BudgetPlanningReport -Years 3 -CurrentTotalPorts 1000 -CurrentUtilization 0.70 -GrowthRateMonthly 0.02

            $report.ReportType | Should Be 'BudgetPlanning'
            $report.YearsPlanned | Should Be 3
            @($report.YearlyProjections).Count | Should Be 3
        }

        It 'projects yearly costs' {
            $report = Get-BudgetPlanningReport -Years 2 -CurrentTotalPorts 500 -CurrentUtilization 0.80 -GrowthRateMonthly 0.03

            $report.YearlyProjections[0].FiscalYear | Should Match 'FY'
            $report.YearlyProjections[0].YearTotalCost | Should Not BeNullOrEmpty
        }

        It 'calculates total budget required' {
            $report = Get-BudgetPlanningReport -Years 3

            $report.TotalBudgetRequired | Should Not BeNullOrEmpty
            $report.TotalDevicesNeeded | Should Not BeNullOrEmpty
        }

        It 'provides recommendations' {
            $report = Get-BudgetPlanningReport -Years 5 -CurrentUtilization 0.70 -GrowthRateMonthly 0.02

            @($report.Recommendations).Count | Should BeGreaterThan 0
        }

        It 'accounts for price inflation' {
            $report = Get-BudgetPlanningReport -Years 2 -AverageDeviceCost 5000 -AnnualPriceIncrease 0.05

            $report.AnnualPriceIncrease | Should Be 5
        }
    }

    Context 'Capacity Report Export' {
        It 'exports capacity report to Text' {
            $report = New-CapacityReport -Type 'Summary'
            $result = Export-CapacityReport -Report $report -Format 'Text' -OutputPath $env:TEMP

            $result.Path | Should Match '\.txt$'
            Test-Path $result.Path | Should Be $true
            $content = Get-Content $result.Path -Raw
            $content | Should Match 'CAPACITY PLANNING REPORT'

            Remove-Item $result.Path -Force -ErrorAction SilentlyContinue
        }

        It 'exports capacity report to HTML' {
            $report = New-CapacityReport -Type 'Summary'
            $result = Export-CapacityReport -Report $report -Format 'HTML' -OutputPath $env:TEMP

            $result.Path | Should Match '\.html$'
            Test-Path $result.Path | Should Be $true
            $content = Get-Content $result.Path -Raw
            $content | Should Match '<html>'

            Remove-Item $result.Path -Force -ErrorAction SilentlyContinue
        }

        It 'exports capacity report to JSON' {
            $report = New-CapacityReport -Type 'Summary'
            $result = Export-CapacityReport -Report $report -Format 'JSON' -OutputPath $env:TEMP

            $result.Path | Should Match '\.json$'
            Test-Path $result.Path | Should Be $true

            Remove-Item $result.Path -Force -ErrorAction SilentlyContinue
        }

        It 'exports capacity report to CSV' {
            $report = New-CapacityReport -Type 'Summary'
            $result = Export-CapacityReport -Report $report -Format 'CSV' -OutputPath $env:TEMP

            $result.Path | Should Match '\.csv$'
            Test-Path $result.Path | Should Be $true

            Remove-Item $result.Path -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Budget Report Export' {
        It 'exports budget report to Text' {
            $report = Get-BudgetPlanningReport -Years 2
            $result = Export-BudgetPlanningReport -Report $report -Format 'Text' -OutputPath $env:TEMP

            $result.Path | Should Match '\.txt$'
            Test-Path $result.Path | Should Be $true
            $content = Get-Content $result.Path -Raw
            $content | Should Match 'BUDGET PLANNING REPORT'

            Remove-Item $result.Path -Force -ErrorAction SilentlyContinue
        }

        It 'exports budget report to HTML' {
            $report = Get-BudgetPlanningReport -Years 2
            $result = Export-BudgetPlanningReport -Report $report -Format 'HTML' -OutputPath $env:TEMP

            $result.Path | Should Match '\.html$'
            Test-Path $result.Path | Should Be $true
            $content = Get-Content $result.Path -Raw
            $content | Should Match 'Budget Planning Report'
            $content | Should Match '<table>'

            Remove-Item $result.Path -Force -ErrorAction SilentlyContinue
        }

        It 'exports budget report to JSON' {
            $report = Get-BudgetPlanningReport -Years 2
            $result = Export-BudgetPlanningReport -Report $report -Format 'JSON' -OutputPath $env:TEMP

            $result.Path | Should Match '\.json$'
            Test-Path $result.Path | Should Be $true
            $content = Get-Content $result.Path -Raw
            $json = $content | ConvertFrom-Json
            $json.ReportType | Should Be 'BudgetPlanning'

            Remove-Item $result.Path -Force -ErrorAction SilentlyContinue
        }

        It 'exports budget projections to CSV' {
            $report = Get-BudgetPlanningReport -Years 3
            $result = Export-BudgetPlanningReport -Report $report -Format 'CSV' -OutputPath $env:TEMP

            $result.Path | Should Match '\.csv$'
            Test-Path $result.Path | Should Be $true
            $csv = Import-Csv $result.Path
            @($csv).Count | Should Be 3

            Remove-Item $result.Path -Force -ErrorAction SilentlyContinue
        }
    }

    #endregion
}
