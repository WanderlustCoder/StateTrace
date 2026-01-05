# Plan Z - Change Management & Maintenance Windows

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

## Objective
Provide comprehensive change management and maintenance window planning capabilities. Enable network teams to plan, document, track, and verify network changes with proper rollback procedures and impact analysis.

## Problem Statement
Network teams struggle with:
- Planning and scheduling maintenance windows across multiple devices
- Documenting changes before, during, and after implementation
- Tracking change history and correlating with incidents
- Generating change request documentation for approval processes
- Verifying changes were implemented correctly
- Managing rollback procedures when changes fail

## Current status (2026-01)
**In Progress (4/6 Done)**. Core change management module, tests, and UI view integrated into MainWindow.

Delivered:
- ChangeManagementModule.psm1 (~1650 lines) with change requests, maintenance windows, templates, history
- 48 Pester tests (all passing) covering CRUD, workflow, rollback, statistics
- ChangeManagementView.xaml with 5 tabs: Changes, Maintenance Windows, Templates, History, Statistics
- ChangeManagementViewModule.psm1 with view wiring and event handlers
- 6 built-in templates: VLAN-Addition, Port-Configuration, Firmware-Upgrade, ACL-Modification, Routing-Change, Emergency-Fix
- Change status workflow: Draft → Submitted → Approved → InProgress → Completed/Failed/RolledBack
- Blackout period detection and maintenance window conflict checking

Pending:
- Advanced calendar visualization
- Real-time change execution tracking with device capture

## Proposed Features

### Z.1 Change Request Management
- **Change Request Creation**: Document changes with:
  - Change ID (auto-generated or linked to ticketing system)
  - Title and description
  - Affected devices/sites
  - Change type (standard, normal, emergency)
  - Risk level (low, medium, high, critical)
  - Planned start/end times
  - Implementation steps
  - Rollback procedures
  - Success criteria
- **Change Templates**: Pre-defined templates for common changes:
  - VLAN addition/modification
  - Port configuration changes
  - Routing updates
  - Firmware upgrades
  - Access list modifications
- **Approval Workflow**: Track approvals (offline documentation)

### Z.2 Maintenance Window Scheduling
- **Calendar View**: Visual calendar showing:
  - Planned maintenance windows
  - Recurring maintenance schedules
  - Blackout periods (no changes allowed)
  - Conflict indicators
- **Window Definition**: Define maintenance windows with:
  - Start/end date and time
  - Affected scope (devices, sites, services)
  - Change requests associated
  - Personnel assigned
- **Conflict Detection**: Identify:
  - Overlapping maintenance windows
  - Changes during blackout periods
  - Too many simultaneous changes
  - Resource conflicts (same engineer, same device)

### Z.3 Pre-Change Validation
- **Pre-Check Capture**: Document baseline state:
  - Current configurations (snapshot)
  - Interface states
  - Routing tables
  - Expected command outputs
- **Impact Analysis**: Estimate change impact:
  - Devices affected
  - Services impacted
  - Users/ports affected
  - Redundancy during change
- **Checklist Generation**: Create implementation checklists

### Z.4 Change Execution Tracking
- **Step-by-Step Logging**: Track during implementation:
  - Timestamp for each step
  - Actual vs planned timing
  - Commands executed
  - Outputs received
  - Issues encountered
- **Real-Time Status**: Change status tracking:
  - Not Started → In Progress → Completed/Failed/Rolled Back
  - Step completion tracking
  - Deviation alerts

### Z.5 Post-Change Verification
- **Verification Checklist**: Confirm success:
  - Configuration matches expected
  - Services restored
  - No unexpected alerts
  - Performance within bounds
- **Comparison Reports**: Pre vs post state:
  - Configuration diff
  - Interface state changes
  - Routing table changes
- **Sign-Off Documentation**: Capture completion evidence

### Z.6 Rollback Management
- **Rollback Procedures**: Document rollback steps
- **Rollback Triggers**: Define when to rollback:
  - Time-based (if not complete by X)
  - Condition-based (if Y fails)
  - Manual trigger
- **Rollback Execution**: Track rollback steps if needed
- **Rollback Verification**: Confirm return to baseline

### Z.7 Change History & Analytics
- **Change Log**: Searchable history of all changes
- **Analytics Dashboard**:
  - Changes by type/risk/outcome
  - Success rate trends
  - Average implementation time
  - Rollback frequency
- **Correlation Analysis**: Link changes to incidents

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-Z-001 | Change request module | Data | Done | ChangeManagementModule.psm1 with 48 tests |
| ST-Z-002 | Maintenance window scheduling | UI | Done | Calendar view and conflict detection |
| ST-Z-003 | Pre-change capture | Tools | Done | Add-ChangeDevice with PreConfigSnapshot |
| ST-Z-004 | Change execution tracker | UI | Done | Step status tracking with progress view |
| ST-Z-005 | Post-change verification | Tools | Pending | Advanced automated verification checks |
| ST-Z-006 | Change analytics | UI | Done | Statistics tab with success rate tracking |

## Recently delivered
- `Modules/ChangeManagementModule.psm1` - Core module with change requests, windows, templates
- `Modules/Tests/ChangeManagementModule.Tests.ps1` - 48 Pester tests
- `Views/ChangeManagementView.xaml` - 5-tab UI layout
- `Modules/ChangeManagementViewModule.psm1` - View wiring

## Data Model (Proposed)

### ChangeRequest Table
```
ChangeID (PK), Title, Description, ChangeType, RiskLevel, Status,
PlannedStart, PlannedEnd, ActualStart, ActualEnd,
RequestedBy, ApprovedBy, ImplementedBy, CreatedDate, ModifiedDate
```

### ChangeDevice Table
```
ChangeID (FK), DeviceID (FK), ChangeRole, PreConfigSnapshot, PostConfigSnapshot,
PreStateSnapshot, PostStateSnapshot, Status, Notes
```

### ChangeStep Table
```
StepID (PK), ChangeID (FK), StepNumber, Description, ExpectedDuration,
ActualStart, ActualEnd, Status, CommandsExecuted, Output, Notes
```

### MaintenanceWindow Table
```
WindowID (PK), Title, StartTime, EndTime, Scope, IsRecurring,
RecurrencePattern, IsBlackout, CreatedBy, Notes
```

### ChangeWindowLink Table
```
ChangeID (FK), WindowID (FK), Notes
```

## Testing Requirements

### Unit Tests (`Modules/Tests/ChangeManagement.Tests.ps1`)

```powershell
Describe 'Change Request Management' -Tag 'ChangeManagement' {

    Describe 'Change Request Creation' {
        It 'creates change request with required fields' {
            $change = New-ChangeRequest -Title 'Add VLAN 100' `
                -Description 'Add new user VLAN' `
                -ChangeType 'Standard' `
                -RiskLevel 'Low' `
                -PlannedStart (Get-Date).AddDays(7) `
                -PlannedEnd (Get-Date).AddDays(7).AddHours(2)

            $change.ChangeID | Should -Match '^CHG-\d{8}-\d{4}$'
            $change.Status | Should -Be 'Draft'
        }

        It 'validates planned end after planned start' {
            { New-ChangeRequest -Title 'Test' `
                -PlannedStart (Get-Date).AddDays(7) `
                -PlannedEnd (Get-Date).AddDays(6) } | Should -Throw
        }

        It 'assigns risk level based on scope' {
            $change = New-ChangeRequest -Title 'Core router change' `
                -AffectedDevices @('CORE-01', 'CORE-02') `
                -AutoAssessRisk

            $change.RiskLevel | Should -BeIn @('High', 'Critical')
        }
    }

    Describe 'Maintenance Window Scheduling' {
        BeforeAll {
            # Create test windows
            $script:window1 = New-MaintenanceWindow -Title 'Weekly Maintenance' `
                -StartTime '2026-01-10 22:00' `
                -EndTime '2026-01-11 02:00'
        }

        It 'detects overlapping maintenance windows' {
            $conflicts = Test-MaintenanceWindowConflict `
                -StartTime '2026-01-10 23:00' `
                -EndTime '2026-01-11 01:00'

            $conflicts | Should -Not -BeNullOrEmpty
            $conflicts[0].WindowID | Should -Be $window1.WindowID
        }

        It 'allows non-overlapping windows' {
            $conflicts = Test-MaintenanceWindowConflict `
                -StartTime '2026-01-11 22:00' `
                -EndTime '2026-01-12 02:00'

            $conflicts | Should -BeNullOrEmpty
        }

        It 'detects blackout period violations' {
            New-MaintenanceWindow -Title 'Freeze Period' `
                -StartTime '2026-01-15 00:00' `
                -EndTime '2026-01-20 00:00' `
                -IsBlackout $true

            $violations = Test-BlackoutViolation `
                -PlannedStart '2026-01-17 10:00'

            $violations.IsViolation | Should -BeTrue
        }
    }

    Describe 'Pre-Change Validation' {
        It 'captures device baseline state' {
            $baseline = Capture-DeviceBaseline -DeviceID 'SW-01'

            $baseline.ConfigSnapshot | Should -Not -BeNullOrEmpty
            $baseline.Timestamp | Should -Not -BeNullOrEmpty
        }

        It 'generates impact analysis' {
            $change = New-ChangeRequest -Title 'Trunk modification' `
                -AffectedDevices @('DS-01')

            $impact = Get-ChangeImpact -ChangeID $change.ChangeID

            $impact.DevicesAffected | Should -BeGreaterThan 0
            $impact.PortsAffected | Should -Not -BeNullOrEmpty
        }

        It 'creates implementation checklist' {
            $change = New-ChangeRequest -Title 'VLAN Add' `
                -Template 'VLAN-Addition'

            $checklist = Get-ChangeChecklist -ChangeID $change.ChangeID

            $checklist.Steps.Count | Should -BeGreaterThan 0
            $checklist.Steps[0].Description | Should -Not -BeNullOrEmpty
        }
    }

    Describe 'Change Execution' {
        It 'tracks step completion' {
            $change = New-ChangeRequest -Title 'Test Change'
            Add-ChangeStep -ChangeID $change.ChangeID `
                -StepNumber 1 -Description 'Backup config'

            Set-ChangeStepStatus -ChangeID $change.ChangeID `
                -StepNumber 1 -Status 'Completed'

            $step = Get-ChangeStep -ChangeID $change.ChangeID -StepNumber 1
            $step.Status | Should -Be 'Completed'
            $step.ActualEnd | Should -Not -BeNullOrEmpty
        }

        It 'calculates change duration' {
            $change = New-ChangeRequest -Title 'Timed Change'
            Start-Change -ChangeID $change.ChangeID
            Start-Sleep -Seconds 2
            Complete-Change -ChangeID $change.ChangeID

            $duration = Get-ChangeDuration -ChangeID $change.ChangeID
            $duration.TotalSeconds | Should -BeGreaterThan 1
        }
    }

    Describe 'Post-Change Verification' {
        It 'compares pre and post configuration' {
            $change = Get-ChangeRequest -ChangeID 'CHG-TEST-001'

            $diff = Compare-ChangeConfigurations -ChangeID $change.ChangeID

            $diff.HasChanges | Should -BeTrue
            $diff.AddedLines | Should -Not -BeNullOrEmpty
        }

        It 'validates success criteria' {
            $change = Get-ChangeRequest -ChangeID 'CHG-TEST-001'

            $validation = Test-ChangeSuccess -ChangeID $change.ChangeID

            $validation.AllCriteriaMet | Should -BeTrue
        }
    }

    Describe 'Rollback Management' {
        It 'generates rollback commands' {
            $change = New-ChangeRequest -Title 'Config Change' `
                -ChangeCommands @('interface Gi1/0/1', 'switchport access vlan 100')

            $rollback = Get-RollbackCommands -ChangeID $change.ChangeID

            $rollback | Should -Not -BeNullOrEmpty
        }

        It 'tracks rollback execution' {
            $change = Get-ChangeRequest -ChangeID 'CHG-FAILED-001'

            Invoke-ChangeRollback -ChangeID $change.ChangeID

            $change = Get-ChangeRequest -ChangeID 'CHG-FAILED-001'
            $change.Status | Should -Be 'RolledBack'
        }
    }

    Describe 'Change Analytics' {
        It 'calculates success rate' {
            $stats = Get-ChangeStatistics -Period 'LastMonth'

            $stats.TotalChanges | Should -BeGreaterThan 0
            $stats.SuccessRate | Should -BeGreaterOrEqual 0
            $stats.SuccessRate | Should -BeLessOrEqual 100
        }

        It 'identifies high-risk patterns' {
            $patterns = Get-ChangeRiskPatterns

            $patterns | Should -Not -BeNullOrEmpty
        }
    }
}
```

## UI Mockup Concepts

### Change Request View
```
+------------------------------------------------------------------+
| Change Request: CHG-20260104-0001                     [Edit][Save]|
+------------------------------------------------------------------+
| Title: Add VLAN 100 for Finance Department                       |
| Status: [Approved]  Risk: [Medium]  Type: [Standard]             |
+------------------------------------------------------------------+
| SCHEDULE                          | SCOPE                        |
| Planned: 2026-01-10 22:00-00:00  | Devices: DS-01, DS-02        |
| Window: Weekly Maintenance        | Sites: Building A            |
| Duration: 2 hours                 | VLANs: 100 (new)             |
+------------------------------------------------------------------+
| IMPLEMENTATION STEPS                                              |
| [ ] 1. Capture pre-change configs         Est: 5 min             |
| [ ] 2. Create VLAN 100 on DS-01          Est: 2 min             |
| [ ] 3. Create VLAN 100 on DS-02          Est: 2 min             |
| [ ] 4. Configure trunk ports             Est: 10 min            |
| [ ] 5. Verify VLAN propagation           Est: 5 min             |
| [ ] 6. Capture post-change configs       Est: 5 min             |
+------------------------------------------------------------------+
| ROLLBACK PROCEDURE                                                |
| 1. Remove VLAN 100 from trunk ports                              |
| 2. Delete VLAN 100 from DS-01, DS-02                             |
| Trigger: If verification fails or services impacted              |
+------------------------------------------------------------------+
| [Start Implementation] [Generate Checklist] [Export PDF]         |
+------------------------------------------------------------------+
```

### Maintenance Calendar
```
+------------------------------------------------------------------+
| Maintenance Calendar - January 2026              [Month][Week]   |
+------------------------------------------------------------------+
|  Mon    |  Tue    |  Wed    |  Thu    |  Fri    |  Sat   | Sun  |
+------------------------------------------------------------------+
|    6    |    7    |    8    |    9    |   10    |   11   |  12  |
|         |         |         |         | [MAINT] |        |      |
|         |         |         |         | 22:00   |        |      |
+------------------------------------------------------------------+
|   13    |   14    |   15    |   16    |   17    |   18   |  19  |
|         |         |[BLACKOUT-----------------------BLACKOUT]     |
+------------------------------------------------------------------+
| Legend: [MAINT]=Maintenance  [BLACKOUT]=No Changes Allowed       |
| [+ New Window] [+ New Change] [View Conflicts]                   |
+------------------------------------------------------------------+
```

### Change Execution Dashboard
```
+------------------------------------------------------------------+
| LIVE: CHG-20260104-0001 - Add VLAN 100           Status: [75%]  |
+------------------------------------------------------------------+
| Started: 22:03  |  Elapsed: 00:47  |  ETA: 23:00                |
+------------------------------------------------------------------+
| STEP PROGRESS                                                     |
| [====] 1. Capture pre-change configs        DONE   22:03-22:08  |
| [====] 2. Create VLAN 100 on DS-01          DONE   22:10-22:12  |
| [====] 3. Create VLAN 100 on DS-02          DONE   22:15-22:17  |
| [==  ] 4. Configure trunk ports             IN PROGRESS  22:20  |
| [    ] 5. Verify VLAN propagation           PENDING              |
| [    ] 6. Capture post-change configs       PENDING              |
+------------------------------------------------------------------+
| CURRENT STEP OUTPUT:                                              |
| DS-01(config)# interface range Gi1/0/47-48                       |
| DS-01(config-if-range)# switchport trunk allowed vlan add 100    |
| DS-01(config-if-range)# exit                                     |
+------------------------------------------------------------------+
| [Pause] [Skip Step] [Abort & Rollback]                           |
+------------------------------------------------------------------+
```

## Automation hooks
- `Tools\New-ChangeRequest.ps1 -Template VLAN-Addition -Title "Add VLAN 100"`
- `Tools\Test-MaintenanceConflicts.ps1 -StartTime "2026-01-10 22:00"`
- `Tools\Capture-PreChangeBaseline.ps1 -ChangeID CHG-001 -Devices DS-01,DS-02`
- `Tools\Compare-ChangeState.ps1 -ChangeID CHG-001` for pre/post diff
- `Tools\Export-ChangeReport.ps1 -ChangeID CHG-001 -Format PDF`
- `Tools\Get-ChangeAnalytics.ps1 -Period LastQuarter`

## Telemetry gates
- Change creation emits `ChangeCreated` with type and risk level
- Execution tracking emits `ChangeStep` with timing and status
- Completion emits `ChangeCompleted` with duration and outcome
- Rollback emits `ChangeRollback` with trigger reason

## Dependencies
- Configuration capture from existing device data
- Compare view infrastructure for diff
- Port Reorg patterns for script generation

## References
- `docs/plans/PlanD_FeatureExpansion.md` (Port Reorg patterns)
- `docs/plans/PlanU_ConfigurationTemplates.md` (Template patterns)
- `docs/plans/PlanR_IncidentResponse.md` (Rollback patterns)
