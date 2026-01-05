# ChangeManagementModule.Tests.ps1
# Pester 3.x compatible tests for Change Management functionality

$ModulePath = Join-Path $PSScriptRoot '..\ChangeManagementModule.psm1'
Import-Module $ModulePath -Force

Describe 'ChangeManagementModule' {

    BeforeEach {
        Remove-TestChangeData
    }

    Context 'Change Request Management' {

        It 'Creates a change request with required fields' {
            $change = New-ChangeRequest -Title 'Add VLAN 100' -Description 'Add new VLAN for marketing' -RequestedBy 'jsmith'
            $change | Should Not BeNullOrEmpty
            $change.Title | Should Be 'Add VLAN 100'
            $change.Status | Should Be 'Draft'
            $change.ChangeID | Should Match '^CHG-\d{8}-\d{4}$'
        }

        It 'Creates a change request from template' {
            $change = New-ChangeRequest -Title 'VLAN Addition' -Description 'Add VLAN 200' -RequestedBy 'admin' -Template 'VLAN-Addition'
            $change | Should Not BeNullOrEmpty
            $change.ChangeType | Should Be 'Standard'
            $steps = @(Get-ChangeStep -ChangeID $change.ChangeID)
            $steps.Count | Should BeGreaterThan 0
        }

        It 'Gets change requests by status' {
            New-ChangeRequest -Title 'Change 1' -Description 'Desc 1' -RequestedBy 'user1'
            New-ChangeRequest -Title 'Change 2' -Description 'Desc 2' -RequestedBy 'user2'

            $drafts = @(Get-ChangeRequest -Status 'Draft')
            $drafts.Count | Should Be 2
        }

        It 'Gets change request by ID' {
            $change = New-ChangeRequest -Title 'Test Change' -Description 'Test' -RequestedBy 'admin'
            $retrieved = Get-ChangeRequest -ChangeID $change.ChangeID
            $retrieved.Title | Should Be 'Test Change'
        }

        It 'Updates change request properties' {
            $change = New-ChangeRequest -Title 'Original Title' -Description 'Test' -RequestedBy 'admin'
            Update-ChangeRequest -ChangeID $change.ChangeID -Title 'Updated Title'

            $updated = Get-ChangeRequest -ChangeID $change.ChangeID
            $updated.Title | Should Be 'Updated Title'
        }

        It 'Removes a change request' {
            $change = New-ChangeRequest -Title 'To Delete' -Description 'Test' -RequestedBy 'admin'
            Remove-ChangeRequest -ChangeID $change.ChangeID

            $retrieved = Get-ChangeRequest -ChangeID $change.ChangeID
            $retrieved | Should BeNullOrEmpty
        }

        It 'Validates change type values' {
            $change = New-ChangeRequest -Title 'Emergency Fix' -Description 'Critical' -RequestedBy 'admin' -ChangeType 'Emergency'
            $change.ChangeType | Should Be 'Emergency'
        }

        It 'Validates risk level values' {
            $change = New-ChangeRequest -Title 'Critical Change' -Description 'Urgent' -RequestedBy 'admin' -RiskLevel 'Critical'
            $change.RiskLevel | Should Be 'Critical'
        }

        It 'Gets all change requests' {
            New-ChangeRequest -Title 'VLAN Addition' -Description 'Add VLAN' -RequestedBy 'admin'
            New-ChangeRequest -Title 'Port Config' -Description 'Configure port' -RequestedBy 'admin'
            New-ChangeRequest -Title 'VLAN Removal' -Description 'Remove VLAN' -RequestedBy 'admin'

            $results = @(Get-ChangeRequest)
            $results.Count | Should Be 3
        }
    }

    Context 'Change Step Management' {

        It 'Adds steps to a change request' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin'
            Add-ChangeStep -ChangeID $change.ChangeID -StepNumber 1 -Description 'Step 1' -Commands 'show version'

            $steps = @(Get-ChangeStep -ChangeID $change.ChangeID)
            $steps.Count | Should Be 1
            $steps[0].Description | Should Be 'Step 1'
        }

        It 'Sets step status' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin'
            Add-ChangeStep -ChangeID $change.ChangeID -StepNumber 1 -Description 'Step 1' -Commands 'show version'

            Set-ChangeStepStatus -ChangeID $change.ChangeID -StepNumber 1 -Status 'Completed' -ActualOutput 'Version 15.1'

            $steps = @(Get-ChangeStep -ChangeID $change.ChangeID)
            $steps[0].Status | Should Be 'Completed'
            $steps[0].ActualOutput | Should Be 'Version 15.1'
        }

        It 'Gets steps in order' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin'
            Add-ChangeStep -ChangeID $change.ChangeID -StepNumber 3 -Description 'Third' -Commands 'cmd3'
            Add-ChangeStep -ChangeID $change.ChangeID -StepNumber 1 -Description 'First' -Commands 'cmd1'
            Add-ChangeStep -ChangeID $change.ChangeID -StepNumber 2 -Description 'Second' -Commands 'cmd2'

            $steps = @(Get-ChangeStep -ChangeID $change.ChangeID)
            $steps[0].StepNumber | Should Be 1
            $steps[1].StepNumber | Should Be 2
            $steps[2].StepNumber | Should Be 3
        }

        It 'Gets specific step by number' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin'
            Add-ChangeStep -ChangeID $change.ChangeID -StepNumber 1 -Description 'First Step' -Commands 'cmd1'
            Add-ChangeStep -ChangeID $change.ChangeID -StepNumber 2 -Description 'Second Step' -Commands 'cmd2'

            $step = Get-ChangeStep -ChangeID $change.ChangeID -StepNumber 2
            $step.Description | Should Be 'Second Step'
        }
    }

    Context 'Change Execution Workflow' {

        It 'Starts a change execution' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin'
            Update-ChangeRequest -ChangeID $change.ChangeID -Status 'Approved'

            Start-Change -ChangeID $change.ChangeID -ImplementedBy 'engineer1'

            $updated = Get-ChangeRequest -ChangeID $change.ChangeID
            $updated.Status | Should Be 'InProgress'
            $updated.ImplementedBy | Should Be 'engineer1'
        }

        It 'Starts change in Draft status' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin'
            # Change is in Draft status - module allows this

            $started = Start-Change -ChangeID $change.ChangeID -ImplementedBy 'engineer1'
            $started.Status | Should Be 'InProgress'
        }

        It 'Completes a change successfully' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin'
            Update-ChangeRequest -ChangeID $change.ChangeID -Status 'Approved'
            Start-Change -ChangeID $change.ChangeID -ImplementedBy 'engineer1'

            Complete-Change -ChangeID $change.ChangeID -CompletionNotes 'Completed without issues'

            $updated = Get-ChangeRequest -ChangeID $change.ChangeID
            $updated.Status | Should Be 'Completed'
        }

        It 'Fails a change with reason' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin'
            Update-ChangeRequest -ChangeID $change.ChangeID -Status 'Approved'
            Start-Change -ChangeID $change.ChangeID -ImplementedBy 'engineer1'

            Fail-Change -ChangeID $change.ChangeID -FailureReason 'Configuration conflict'

            $updated = Get-ChangeRequest -ChangeID $change.ChangeID
            $updated.Status | Should Be 'Failed'
            $updated.Notes | Should Match 'Configuration conflict'
        }

        It 'Gets change duration' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin'
            Start-Change -ChangeID $change.ChangeID -ImplementedBy 'engineer1'

            $duration = Get-ChangeDuration -ChangeID $change.ChangeID
            $duration | Should Not BeNullOrEmpty
        }

        It 'Gets change progress' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin'
            Add-ChangeStep -ChangeID $change.ChangeID -StepNumber 1 -Description 'Step 1' -Commands 'cmd1'
            Add-ChangeStep -ChangeID $change.ChangeID -StepNumber 2 -Description 'Step 2' -Commands 'cmd2'
            Set-ChangeStepStatus -ChangeID $change.ChangeID -StepNumber 1 -Status 'Completed'

            $progress = Get-ChangeProgress -ChangeID $change.ChangeID
            $progress.TotalSteps | Should Be 2
            $progress.CompletedSteps | Should Be 1
            $progress.ProgressPercent | Should Be 50
        }
    }

    Context 'Rollback Management' {

        It 'Gets rollback commands from template' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin' -Template 'VLAN-Addition'

            $rollback = @(Get-RollbackCommands -ChangeID $change.ChangeID)
            $rollback.Count | Should BeGreaterThan 0
        }

        It 'Gets explicit rollback commands' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin' -RollbackCommands @('no vlan 100', 'exit')

            $rollback = @(Get-RollbackCommands -ChangeID $change.ChangeID)
            $rollback.Count | Should Be 2
            $rollback[0] | Should Be 'no vlan 100'
        }

        It 'Invokes rollback and updates status' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin'
            Update-ChangeRequest -ChangeID $change.ChangeID -Status 'Approved'
            Start-Change -ChangeID $change.ChangeID -ImplementedBy 'engineer1'

            Invoke-ChangeRollback -ChangeID $change.ChangeID -RollbackReason 'Testing rollback'

            $updated = Get-ChangeRequest -ChangeID $change.ChangeID
            $updated.Status | Should Be 'RolledBack'
        }
    }

    Context 'Maintenance Windows' {

        It 'Creates a maintenance window' {
            $start = (Get-Date).AddDays(1)
            $end = $start.AddHours(4)

            $window = New-MaintenanceWindow -Title 'Weekly Maintenance' -StartTime $start -EndTime $end -CreatedBy 'admin'
            $window | Should Not BeNullOrEmpty
            $window.Title | Should Be 'Weekly Maintenance'
            $window.WindowID | Should Not BeNullOrEmpty
        }

        It 'Gets maintenance windows by date range' {
            $start1 = (Get-Date).AddDays(1)
            $end1 = $start1.AddHours(4)
            $start2 = (Get-Date).AddDays(7)
            $end2 = $start2.AddHours(4)

            New-MaintenanceWindow -Title 'Window 1' -StartTime $start1 -EndTime $end1 -CreatedBy 'admin'
            New-MaintenanceWindow -Title 'Window 2' -StartTime $start2 -EndTime $end2 -CreatedBy 'admin'

            $windows = @(Get-MaintenanceWindow -StartDate (Get-Date) -EndDate (Get-Date).AddDays(5))
            $windows.Count | Should Be 1
            $windows[0].Title | Should Be 'Window 1'
        }

        It 'Detects maintenance window conflicts' {
            $start1 = (Get-Date).AddDays(1)
            $end1 = $start1.AddHours(4)

            New-MaintenanceWindow -Title 'Existing Window' -StartTime $start1 -EndTime $end1 -CreatedBy 'admin'

            # Overlapping window
            $start2 = $start1.AddHours(2)
            $end2 = $start2.AddHours(4)

            $conflicts = @(Test-MaintenanceWindowConflict -StartTime $start2 -EndTime $end2)
            $conflicts.Count | Should BeGreaterThan 0
        }

        It 'Supports recurring maintenance windows' {
            $start = (Get-Date).AddDays(1)
            $end = $start.AddHours(4)

            $window = New-MaintenanceWindow -Title 'Weekly' -StartTime $start -EndTime $end -CreatedBy 'admin' -IsRecurring -RecurrencePattern 'Weekly'
            $window.IsRecurring | Should Be $true
            $window.RecurrencePattern | Should Be 'Weekly'
        }

        It 'Removes maintenance window' {
            $start = (Get-Date).AddDays(1)
            $end = $start.AddHours(4)
            $window = New-MaintenanceWindow -Title 'To Remove' -StartTime $start -EndTime $end -CreatedBy 'admin'

            Remove-MaintenanceWindow -WindowID $window.WindowID

            $windows = @(Get-MaintenanceWindow)
            $windows.Count | Should Be 0
        }
    }

    Context 'Blackout Periods' {

        It 'Detects blackout period violations' {
            # Add a blackout period
            $start = (Get-Date).AddHours(-1)
            $end = (Get-Date).AddDays(5)
            New-MaintenanceWindow -Title 'Quarter End Freeze' -StartTime $start -EndTime $end -CreatedBy 'admin' -IsBlackout

            $result = Test-BlackoutViolation -PlannedStart (Get-Date)
            $result.IsViolation | Should Be $true
        }

        It 'Allows changes outside blackout periods' {
            $start = (Get-Date).AddDays(10)
            $end = (Get-Date).AddDays(20)
            New-MaintenanceWindow -Title 'Holiday Freeze' -StartTime $start -EndTime $end -CreatedBy 'admin' -IsBlackout

            $result = Test-BlackoutViolation -PlannedStart (Get-Date)
            $result.IsViolation | Should Be $false
        }

        It 'Gets blackout windows only' {
            $start = (Get-Date).AddDays(1)
            $end = $start.AddHours(4)
            New-MaintenanceWindow -Title 'Regular Window' -StartTime $start -EndTime $end -CreatedBy 'admin'
            New-MaintenanceWindow -Title 'Blackout Window' -StartTime $start.AddDays(1) -EndTime $end.AddDays(1) -CreatedBy 'admin' -IsBlackout

            $blackouts = @(Get-MaintenanceWindow -BlackoutsOnly)
            $blackouts.Count | Should Be 1
            $blackouts[0].Title | Should Be 'Blackout Window'
        }
    }

    Context 'Device Change Capture' {

        It 'Adds a device to change request' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin'
            Add-ChangeDevice -ChangeID $change.ChangeID -DeviceID 'SW-CORE-01' -PreConfigSnapshot 'interface Gi1/0/1\n no shutdown'

            $devices = @(Get-ChangeDevice -ChangeID $change.ChangeID)
            $devices.Count | Should Be 1
            $devices[0].DeviceID | Should Be 'SW-CORE-01'
        }

        It 'Captures post-change configuration' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin'
            Add-ChangeDevice -ChangeID $change.ChangeID -DeviceID 'SW-CORE-01' -PreConfigSnapshot 'interface Gi1/0/1\n shutdown'
            Set-ChangeDevicePostState -ChangeID $change.ChangeID -DeviceID 'SW-CORE-01' -PostConfigSnapshot 'interface Gi1/0/1\n no shutdown'

            $devices = @(Get-ChangeDevice -ChangeID $change.ChangeID)
            $devices[0].PostConfigSnapshot | Should Not BeNullOrEmpty
        }

        It 'Compares pre and post configurations' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin'
            Add-ChangeDevice -ChangeID $change.ChangeID -DeviceID 'SW-CORE-01' -PreConfigSnapshot "interface Gi1/0/1`n shutdown"
            Set-ChangeDevicePostState -ChangeID $change.ChangeID -DeviceID 'SW-CORE-01' -PostConfigSnapshot "interface Gi1/0/1`n no shutdown"

            $diff = @(Compare-ChangeConfigurations -ChangeID $change.ChangeID)
            $diff.Count | Should BeGreaterThan 0
            $diff[0].HasChanges | Should Be $true
        }
    }

    Context 'Impact Analysis' {

        It 'Calculates change impact' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin' -ChangeType 'Emergency' -RiskLevel 'Critical' -AffectedDevices @('SW-CORE-01', 'SW-CORE-02')

            $impact = Get-ChangeImpact -ChangeID $change.ChangeID
            $impact | Should Not BeNullOrEmpty
            $impact.DevicesAffected | Should Be 2
            $impact.ImpactLevel | Should Be 'Critical'
        }

        It 'Calculates estimated duration from steps' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin'
            Add-ChangeStep -ChangeID $change.ChangeID -StepNumber 1 -Description 'Step 1' -EstimatedMinutes 10
            Add-ChangeStep -ChangeID $change.ChangeID -StepNumber 2 -Description 'Step 2' -EstimatedMinutes 15

            $duration = Get-ChangeEstimatedDuration -ChangeID $change.ChangeID
            $duration | Should Be 25
        }
    }

    Context 'Templates' {

        It 'Gets available templates' {
            $templates = @(Get-ChangeTemplate)
            $templates.Count | Should BeGreaterThan 0
        }

        It 'Gets specific template by ID' {
            $template = Get-ChangeTemplate -TemplateID 'VLAN-Addition'
            $template | Should Not BeNullOrEmpty
            $template.TemplateID | Should Be 'VLAN-Addition'
            @($template.Steps).Count | Should BeGreaterThan 0
        }

        It 'Creates change from template with all steps' {
            $change = New-ChangeRequest -Title 'VLAN Test' -Description 'Test' -RequestedBy 'admin' -Template 'VLAN-Addition'
            $steps = @(Get-ChangeStep -ChangeID $change.ChangeID)
            $steps.Count | Should BeGreaterThan 0
        }

        It 'Has built-in templates for common changes' {
            $vlan = Get-ChangeTemplate -TemplateID 'VLAN-Addition'
            $port = Get-ChangeTemplate -TemplateID 'Port-Configuration'
            $firmware = Get-ChangeTemplate -TemplateID 'Firmware-Upgrade'
            $acl = Get-ChangeTemplate -TemplateID 'ACL-Modification'
            $routing = Get-ChangeTemplate -TemplateID 'Routing-Change'
            $emergency = Get-ChangeTemplate -TemplateID 'Emergency-Fix'

            $vlan | Should Not BeNullOrEmpty
            $port | Should Not BeNullOrEmpty
            $firmware | Should Not BeNullOrEmpty
            $acl | Should Not BeNullOrEmpty
            $routing | Should Not BeNullOrEmpty
            $emergency | Should Not BeNullOrEmpty
        }
    }

    Context 'Statistics and Reporting' {

        It 'Gets change statistics' {
            New-ChangeRequest -Title 'Change 1' -Description 'Test' -RequestedBy 'admin'
            $change2 = New-ChangeRequest -Title 'Change 2' -Description 'Test' -RequestedBy 'admin'
            Start-Change -ChangeID $change2.ChangeID -ImplementedBy 'engineer'
            Complete-Change -ChangeID $change2.ChangeID

            $stats = Get-ChangeStatistics
            $stats | Should Not BeNullOrEmpty
            $stats.TotalChanges | Should Be 2
            $stats.Completed | Should Be 1
        }

        It 'Gets statistics by period' {
            New-ChangeRequest -Title 'Change' -Description 'Test' -RequestedBy 'admin'

            $weekStats = Get-ChangeStatistics -Period 'LastWeek'
            $monthStats = Get-ChangeStatistics -Period 'LastMonth'

            $weekStats | Should Not BeNullOrEmpty
            $monthStats | Should Not BeNullOrEmpty
        }
    }

    Context 'Checklists' {

        It 'Gets change checklist' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin'

            $checklist = Get-ChangeChecklist -ChangeID $change.ChangeID
            $checklist | Should Not BeNullOrEmpty
            $checklist.PreChecks.Count | Should BeGreaterThan 0
            $checklist.PostChecks.Count | Should BeGreaterThan 0
        }

        It 'Checklist includes steps from change' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin'
            Add-ChangeStep -ChangeID $change.ChangeID -StepNumber 1 -Description 'Step 1' -Commands 'cmd1'
            Add-ChangeStep -ChangeID $change.ChangeID -StepNumber 2 -Description 'Step 2' -Commands 'cmd2'

            $checklist = Get-ChangeChecklist -ChangeID $change.ChangeID
            $checklist.Steps.Count | Should Be 2
        }
    }

    Context 'Import/Export' {

        It 'Exports database to JSON' {
            New-ChangeRequest -Title 'Export Test' -Description 'Test' -RequestedBy 'admin'
            $start = (Get-Date).AddDays(1)
            $end = $start.AddHours(4)
            New-MaintenanceWindow -Title 'Test Window' -StartTime $start -EndTime $end -CreatedBy 'admin'

            $tempPath = Join-Path $env:TEMP 'ChangeManagement_Test.json'
            $result = Export-ChangeManagementDatabase -Path $tempPath

            $result | Should Not BeNullOrEmpty
            $result.ChangeCount | Should Be 1
            $result.WindowCount | Should Be 1
            Test-Path $tempPath | Should Be $true

            Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        }

        It 'Imports database from JSON' {
            New-ChangeRequest -Title 'Original' -Description 'Test' -RequestedBy 'admin'
            $tempPath = Join-Path $env:TEMP 'ChangeManagement_Test2.json'
            Export-ChangeManagementDatabase -Path $tempPath

            Remove-TestChangeData
            $empty = @(Get-ChangeRequest)
            $empty.Count | Should Be 0

            Import-ChangeManagementDatabase -Path $tempPath
            $imported = @(Get-ChangeRequest)
            $imported.Count | Should Be 1
            $imported[0].Title | Should Be 'Original'

            Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'History and Audit' {

        It 'Records change history on create' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin'

            $history = @(Get-ChangeHistory -ChangeID $change.ChangeID)
            $history.Count | Should BeGreaterThan 0
            $history[0].Action | Should Be 'Created'
        }

        It 'Records change history on update' {
            $change = New-ChangeRequest -Title 'Test' -Description 'Test' -RequestedBy 'admin'
            Update-ChangeRequest -ChangeID $change.ChangeID -Status 'Approved'

            $history = @(Get-ChangeHistory -ChangeID $change.ChangeID)
            $history.Count | Should BeGreaterThan 1
        }

        It 'Gets all history entries' {
            $change1 = New-ChangeRequest -Title 'Test 1' -Description 'Test' -RequestedBy 'admin'
            $change2 = New-ChangeRequest -Title 'Test 2' -Description 'Test' -RequestedBy 'admin'

            $allHistory = @(Get-ChangeHistory)
            $allHistory.Count | Should BeGreaterThan 1
        }
    }
}
