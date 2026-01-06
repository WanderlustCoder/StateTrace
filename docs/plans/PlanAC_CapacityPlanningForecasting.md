# Plan AC - Capacity Planning & Forecasting

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

## Objective
Provide network capacity planning and growth forecasting tools. Enable network teams to track utilization trends, predict when capacity thresholds will be reached, and plan infrastructure upgrades proactively rather than reactively.

## Problem Statement
Network teams struggle with:
- Understanding current port utilization across sites
- Predicting when switches need additional capacity
- Planning for growth without over-provisioning
- Justifying infrastructure purchases with data
- Identifying underutilized equipment that could be redeployed
- Tracking utilization trends over time

## Current status (2026-01)
- **Complete (6/6 Done)**: Core module, tests, UI, MainWindow integration, scenario comparison, and budget reports
- Utilization tracking: Port, PoE, VLAN, and site aggregation
- Historical snapshots with trend data storage
- Linear regression forecasting with R-squared confidence
- Threshold management with warning/critical levels
- What-if scenario analysis: Add Users, Deploy VLAN, Add Equipment, Equipment Scenarios, Technology Refresh
- Enhanced scenario comparison: ROI analysis, payback period, best value recommendations
- Budget planning: Multi-year projections with inflation, TCO calculations, redeployment candidates
- Multi-format export: Text, HTML, JSON, CSV for capacity and budget reports
- 70 Pester tests passing

## Proposed Features

### AC.1 Utilization Tracking
- **Port Utilization Metrics**:
  - Total ports vs used ports per device
  - Access ports vs trunk ports
  - Available ports by VLAN
  - PoE capacity and usage
- **Aggregate Views**:
  - Utilization by site
  - Utilization by building/closet
  - Utilization by device role
  - Utilization by VLAN
- **Historical Snapshots**:
  - Daily/weekly/monthly utilization records
  - Trend data for forecasting

### AC.2 Growth Forecasting
- **Trend Analysis**:
  - Linear regression for port growth
  - Seasonal adjustment (academic calendars, etc.)
  - Moving averages for smoothing
- **Threshold Predictions**:
  - When will device reach 80% capacity?
  - When will site need additional switches?
  - When will PoE budget be exhausted?
- **Growth Rate Calculations**:
  - Ports added per month
  - Ports added per quarter
  - Year-over-year growth

### AC.3 Capacity Reports
- **Executive Summary**:
  - Overall network capacity health
  - Sites at risk of exhaustion
  - Recommended actions
- **Detailed Planning Report**:
  - Per-device utilization and forecast
  - Recommended upgrade timeline
  - Cost projections
- **What-If Analysis**:
  - If we add N users, what capacity do we need?
  - If we deploy new VLAN, where does it fit?
  - If we consolidate closets, what's the impact?

### AC.4 Budget Planning Support
- **Equipment Projections**:
  - Switches needed in next 1/3/5 years
  - Port licenses needed
  - PoE budget requirements
- **Cost Modeling**:
  - Estimated hardware costs
  - Licensing costs
  - Installation/cabling costs
- **Optimization Recommendations**:
  - Underutilized equipment to redeploy
  - Consolidation opportunities
  - Decommission candidates

### AC.5 Threshold Alerting
- **Configurable Thresholds**:
  - Warning at 70% utilization
  - Critical at 85% utilization
  - Custom per-site thresholds
- **Forecast Alerts**:
  - "Site X will reach 80% in 90 days"
  - "Device Y needs expansion by Q3"
- **Alert Dashboard**:
  - Current threshold violations
  - Upcoming capacity concerns

### AC.6 Planning Scenarios
- **Scenario Modeling**:
  - Add new building/site
  - Deploy new service (VoIP, IoT, etc.)
  - User population growth
  - Technology refresh (1G to 10G migration)
- **Comparison View**:
  - Current state vs planned state
  - Multiple scenarios side-by-side
  - Cost comparison

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-AC-001 | Utilization snapshot schema | Data | Done | CapacityPlanningModule.psm1 with snapshot storage |
| ST-AC-002 | Trend calculation engine | Tools | Done | Linear regression, growth rates, breach predictions |
| ST-AC-003 | Capacity dashboard | UI | Done | CapacityPlanningView.xaml with 6 tabs |
| ST-AC-004 | Threshold alerting | Tools | Done | Configurable warning/critical thresholds |
| ST-AC-005 | What-if scenario engine | Tools | Done | Equipment/tech refresh scenarios with ROI comparison |
| ST-AC-006 | Budget planning reports | Tools | Done | Multi-year projections, multi-format export |

## Recently delivered
| ID | Title | Delivered | Notes |
|----|-------|-----------|-------|
| ST-AC-001 | Utilization snapshot schema | 2026-01-05 | `Modules/CapacityPlanningModule.psm1` |
| ST-AC-002 | Trend calculation engine | 2026-01-05 | Get-LinearForecast, Get-ThresholdBreachDate |
| ST-AC-003 | Capacity dashboard | 2026-01-05 | `Views/CapacityPlanningView.xaml`, view module |
| ST-AC-004 | Threshold alerting | 2026-01-05 | Get-CapacityAlerts, Add-CapacityThreshold |
| ST-AC-005 | What-if scenario engine | 2026-01-06 | New-EquipmentScenario, New-TechnologyRefreshScenario, Get-ScenarioComparison |
| ST-AC-006 | Budget planning reports | 2026-01-06 | Get-BudgetPlanningReport, Export-CapacityReport, Export-BudgetPlanningReport |

## Data Model (Proposed)

### UtilizationSnapshot Table
```
SnapshotID (PK), SnapshotDate, ScopeType, ScopeID,
TotalPorts, UsedPorts, AccessPorts, TrunkPorts,
PoEBudgetWatts, PoEUsedWatts, AvailableByVLAN, Notes
```

### CapacityThreshold Table
```
ThresholdID (PK), ScopeType, ScopeID, MetricName,
WarningLevel, CriticalLevel, IsEnabled, NotifyOnBreach
```

### GrowthForecast Table
```
ForecastID (PK), ScopeType, ScopeID, CalculatedDate,
GrowthRateMonthly, ProjectedExhaustionDate, ConfidenceLevel, Notes
```

### PlanningScenario Table
```
ScenarioID (PK), Name, Description, BaselineDate,
Assumptions, ProjectedChanges, CostEstimate, CreatedBy, CreatedDate
```

## Testing Requirements

### Unit Tests (`Modules/Tests/CapacityPlanningModule.Tests.ps1`)

```powershell
Describe 'Capacity Planning' -Tag 'CapacityPlanning' {

    Describe 'Utilization Calculations' {
        It 'calculates device port utilization correctly' {
            $device = @{
                TotalPorts = 48
                UsedPorts = 36
            }

            $util = Get-PortUtilization -Device $device

            $util.Percentage | Should -Be 75
            $util.AvailablePorts | Should -Be 12
        }

        It 'aggregates utilization by site' {
            $devices = @(
                @{ SiteID = 'SITE-A'; TotalPorts = 48; UsedPorts = 40 },
                @{ SiteID = 'SITE-A'; TotalPorts = 48; UsedPorts = 30 },
                @{ SiteID = 'SITE-B'; TotalPorts = 24; UsedPorts = 20 }
            )

            $siteUtil = Get-SiteUtilization -Devices $devices

            $siteA = $siteUtil | Where-Object { $_.SiteID -eq 'SITE-A' }
            $siteA.TotalPorts | Should -Be 96
            $siteA.UsedPorts | Should -Be 70
            $siteA.Percentage | Should -BeGreaterThan 72
        }

        It 'calculates PoE utilization' {
            $device = @{
                PoEBudgetWatts = 740
                PoEUsedWatts = 550
            }

            $poe = Get-PoEUtilization -Device $device

            $poe.Percentage | Should -BeGreaterThan 74
            $poe.AvailableWatts | Should -Be 190
        }

        It 'tracks utilization by VLAN' {
            $ports = @(
                @{ VLAN = 10; IsUsed = $true },
                @{ VLAN = 10; IsUsed = $true },
                @{ VLAN = 10; IsUsed = $false },
                @{ VLAN = 20; IsUsed = $true }
            )

            $vlanUtil = Get-VLANUtilization -Ports $ports

            $vlan10 = $vlanUtil | Where-Object { $_.VLAN -eq 10 }
            $vlan10.TotalPorts | Should -Be 3
            $vlan10.UsedPorts | Should -Be 2
        }
    }

    Describe 'Trend Analysis' {
        BeforeAll {
            # Create test historical data
            $script:testHistory = @(
                @{ Date = '2025-10-01'; UsedPorts = 100 },
                @{ Date = '2025-11-01'; UsedPorts = 108 },
                @{ Date = '2025-12-01'; UsedPorts = 115 },
                @{ Date = '2026-01-01'; UsedPorts = 122 }
            )
        }

        It 'calculates monthly growth rate' {
            $growth = Get-GrowthRate -History $testHistory -Period Monthly

            $growth.PortsPerMonth | Should -BeGreaterThan 7
            $growth.PortsPerMonth | Should -BeLessThan 8
        }

        It 'performs linear regression for forecasting' {
            $forecast = Get-LinearForecast -History $testHistory

            $forecast.Slope | Should -BeGreaterThan 0
            $forecast.RSquared | Should -BeGreaterThan 0.9
        }

        It 'predicts threshold breach date' {
            $prediction = Get-ThresholdBreachDate -History $testHistory `
                -TotalCapacity 200 -Threshold 0.80

            $prediction.ProjectedDate | Should -BeOfType [DateTime]
            $prediction.DaysUntilBreach | Should -BeGreaterThan 0
        }

        It 'handles seasonal variations' {
            $seasonalHistory = @(
                @{ Date = '2025-01-01'; UsedPorts = 100 },
                @{ Date = '2025-06-01'; UsedPorts = 80 },  # Summer dip
                @{ Date = '2025-09-01'; UsedPorts = 110 },
                @{ Date = '2026-01-01'; UsedPorts = 105 }
            )

            $forecast = Get-SeasonalForecast -History $seasonalHistory

            $forecast.HasSeasonalPattern | Should -BeTrue
        }
    }

    Describe 'Threshold Management' {
        It 'identifies devices above warning threshold' {
            $devices = @(
                @{ Hostname = 'SW-01'; TotalPorts = 48; UsedPorts = 40 },  # 83%
                @{ Hostname = 'SW-02'; TotalPorts = 48; UsedPorts = 30 },  # 63%
                @{ Hostname = 'SW-03'; TotalPorts = 48; UsedPorts = 45 }   # 94%
            )

            $warnings = Get-CapacityWarnings -Devices $devices -WarningThreshold 0.70

            $warnings.Count | Should -Be 2
            $warnings.Hostname | Should -Contain 'SW-01'
            $warnings.Hostname | Should -Contain 'SW-03'
        }

        It 'categorizes by severity level' {
            $device = @{ TotalPorts = 100; UsedPorts = 92 }

            $status = Get-CapacityStatus -Device $device `
                -WarningThreshold 0.70 -CriticalThreshold 0.85

            $status.Severity | Should -Be 'Critical'
        }

        It 'generates forecast-based alerts' {
            $forecast = @{
                ProjectedExhaustionDate = (Get-Date).AddDays(60)
            }

            $alert = Get-ForecastAlert -Forecast $forecast -AlertDays 90

            $alert.ShouldAlert | Should -BeTrue
            $alert.Message | Should -Match '60 days'
        }
    }

    Describe 'What-If Scenarios' {
        It 'calculates impact of adding users' {
            $currentState = @{
                TotalPorts = 100
                UsedPorts = 75
                PortsPerUser = 1.2
            }

            $impact = Get-ScenarioImpact -CurrentState $currentState -AddUsers 20

            $impact.NewUsedPorts | Should -Be 99
            $impact.NewUtilization | Should -Be 99
        }

        It 'models new VLAN deployment' {
            $currentState = @{
                Devices = @(
                    @{ Hostname = 'SW-01'; TotalPorts = 48; UsedPorts = 35 },
                    @{ Hostname = 'SW-02'; TotalPorts = 48; UsedPorts = 40 }
                )
            }

            $scenario = New-VLANDeploymentScenario -CurrentState $currentState `
                -NewVLAN 100 -EstimatedPorts 15

            $scenario.CanAccommodate | Should -BeTrue
            $scenario.RecommendedDevice | Should -Be 'SW-01'
        }

        It 'compares multiple scenarios' {
            $scenarios = @(
                @{ Name = 'Add Switch'; Cost = 5000; CapacityGain = 48 },
                @{ Name = 'Upgrade to 10G'; Cost = 15000; CapacityGain = 0 },
                @{ Name = 'Consolidate'; Cost = 0; CapacityGain = 24 }
            )

            $comparison = Compare-Scenarios -Scenarios $scenarios

            $comparison[0].CostPerPort | Should -BeLessThan $comparison[1].CostPerPort
        }
    }

    Describe 'Budget Planning' {
        It 'estimates hardware needs for growth' {
            $projections = Get-HardwareProjection `
                -CurrentUtilization 0.75 `
                -GrowthRateMonthly 0.02 `
                -PlanningHorizonMonths 24 `
                -DeviceCapacity 48

            $projections.AdditionalDevicesNeeded | Should -BeGreaterThan 0
        }

        It 'calculates total cost of ownership' {
            $equipment = @(
                @{ Type = 'Switch'; Model = 'C9300-48P'; Count = 2; UnitCost = 5000 }
            )

            $tco = Get-TotalCostEstimate -Equipment $equipment `
                -InstallationCostPerDevice 500 `
                -YearlyMaintenancePercent 0.15 `
                -Years 5

            $tco.HardwareCost | Should -Be 10000
            $tco.InstallationCost | Should -Be 1000
            $tco.FiveYearTCO | Should -BeGreaterThan 15000
        }

        It 'identifies redeployment candidates' {
            $devices = @(
                @{ Hostname = 'SW-OLD'; UsedPorts = 5; TotalPorts = 48; Age = 2 },
                @{ Hostname = 'SW-FULL'; UsedPorts = 45; TotalPorts = 48; Age = 1 }
            )

            $candidates = Get-RedeploymentCandidates -Devices $devices `
                -MaxUtilization 0.30

            $candidates.Count | Should -Be 1
            $candidates[0].Hostname | Should -Be 'SW-OLD'
        }
    }

    Describe 'Snapshot Management' {
        It 'creates utilization snapshot' {
            $snapshot = New-UtilizationSnapshot -Scope 'Site' -ScopeID 'CAMPUS-MAIN'

            $snapshot.SnapshotID | Should -Not -BeNullOrEmpty
            $snapshot.SnapshotDate | Should -BeOfType [DateTime]
        }

        It 'retrieves historical snapshots' {
            $history = Get-UtilizationHistory -Scope 'Site' -ScopeID 'CAMPUS-MAIN' `
                -StartDate '2025-10-01' -EndDate '2026-01-01'

            $history | Should -Not -BeNullOrEmpty
        }

        It 'aggregates snapshots for trend analysis' {
            $aggregated = Get-AggregatedTrend -Scope 'Site' -ScopeID 'CAMPUS-MAIN' `
                -Granularity Monthly -Periods 6

            $aggregated.Count | Should -BeLessOrEqual 6
        }
    }

    Describe 'Report Generation' {
        It 'generates executive capacity summary' {
            $report = New-CapacityReport -Type Executive

            $report.Sections | Should -Contain 'Summary'
            $report.Sections | Should -Contain 'RiskAreas'
            $report.Sections | Should -Contain 'Recommendations'
        }

        It 'generates detailed planning report' {
            $report = New-CapacityReport -Type Detailed -Scope 'Enterprise'

            $report.DeviceDetails | Should -Not -BeNullOrEmpty
            $report.Forecasts | Should -Not -BeNullOrEmpty
        }

        It 'exports report to Excel format' {
            $report = New-CapacityReport -Type Summary
            $path = Export-CapacityReport -Report $report -Format Excel

            Test-Path $path | Should -BeTrue
        }
    }
}
```

## UI Mockup Concepts

### Capacity Dashboard
```
+------------------------------------------------------------------+
| Network Capacity Dashboard                    [Refresh][Settings]|
+------------------------------------------------------------------+
| OVERALL HEALTH                                                   |
| [============================] 68% utilized (4,080 / 6,000 ports)|
+------------------------------------------------------------------+
| ALERTS                              | FORECAST                   |
| [!] 3 devices above 85%             | 80% threshold: ~6 months  |
| [!] Campus B approaching 80%        | Growth rate: 2.1%/month   |
| [i] 12 devices below 30%            | Next purchase: Q3 2026    |
+------------------------------------------------------------------+
| SITE UTILIZATION                                                 |
| Campus Main    [==================] 78%     +1.8%/mo            |
| Campus North   [==============    ] 62%     +2.4%/mo            |
| Data Center    [==========        ] 45%     +0.5%/mo            |
| Remote Sites   [================  ] 71%     +3.1%/mo            |
+------------------------------------------------------------------+
| [View Details] [Run Forecast] [Create Scenario] [Generate Report]|
+------------------------------------------------------------------+
```

### Forecast View
```
+------------------------------------------------------------------+
| Capacity Forecast: Campus Main                                   |
+------------------------------------------------------------------+
|                                                                  |
|  100% |                                           *** Critical  |
|   90% |                                    ****                 |
|   80% |                             *****  - - - Warning        |
|   70% |                      ******                             |
|   60% |               *******                                   |
|   50% |        *******                                          |
|       +------+------+------+------+------+------+------+        |
|       Oct    Nov    Dec    Jan    Feb    Mar    Apr             |
|       2025   2025   2025   2026   2026   2026   2026            |
|                                                                  |
+------------------------------------------------------------------+
| Forecast Summary:                                                |
| - Current: 78% (468/600 ports)                                  |
| - 80% threshold reached: March 2026 (+/- 2 weeks)               |
| - 90% threshold reached: July 2026 (+/- 1 month)                |
| - Recommended action: Order 2x 48-port switches by Feb 2026     |
+------------------------------------------------------------------+
```

### What-If Scenario Builder
```
+------------------------------------------------------------------+
| Scenario Planner                                      [Compare]  |
+------------------------------------------------------------------+
| CURRENT STATE                 | SCENARIO: Add 50 Users          |
| Total Ports: 600              | New Users: [50        ]         |
| Used Ports: 468 (78%)         | Ports/User: [1.2      ]         |
| Available: 132                | New VoIP Phones: [x]            |
|                               | New Printers: [ ]               |
+------------------------------------------------------------------+
| IMPACT ANALYSIS                                                  |
| Additional ports needed: 60                                      |
| Projected utilization: 88%                                       |
| Status: EXCEEDS WARNING THRESHOLD                                |
|                                                                  |
| RECOMMENDATIONS                                                  |
| Option 1: Add 2x C9300-48P switches ($10,400)                   |
| Option 2: Redeploy SW-IDLE-01 from storage (+48 ports, $500)    |
| Option 3: Consolidate underutilized closets (+35 ports, $200)   |
+------------------------------------------------------------------+
| [Save Scenario] [Export Analysis] [Apply to Plan]                |
+------------------------------------------------------------------+
```

## Automation hooks
- `Tools\New-UtilizationSnapshot.ps1 -Scope Enterprise` to capture current state
- `Tools\Get-CapacityForecast.ps1 -Site CAMPUS-MAIN -Months 12` for predictions
- `Tools\Get-CapacityWarnings.ps1 -Threshold 80` for at-risk devices
- `Tools\New-CapacityScenario.ps1 -AddUsers 100 -NewVLAN 150` for planning
- `Tools\Export-CapacityReport.ps1 -Type Executive -Format PDF`
- `Tools\Get-RedeploymentCandidates.ps1 -MaxUtilization 30` for optimization

## Telemetry gates
- Snapshot creation emits `CapacitySnapshot` with scope and totals
- Forecast generation emits `CapacityForecast` with predictions
- Threshold breaches emit `CapacityAlert` with severity
- Scenario modeling emits `CapacityScenario` with parameters

## Dependencies
- Device and interface data from existing modules
- Historical snapshot storage
- Report generation infrastructure (Plan AA)

## References
- `docs/plans/PlanX_InventoryAssetTracking.md` (Hardware data)
- `docs/plans/PlanV_IPAddressVLANPlanning.md` (VLAN capacity)
- `docs/plans/PlanAA_DocumentationGenerator.md` (Report generation)
