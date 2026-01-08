# BulkOperationsModule.Tests.ps1
# Pester tests for bulk operations, device selection, and runbook execution

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\BulkOperationsModule.psm1'
    Import-Module $modulePath -Force
}

Describe 'Device Selection' {
    BeforeAll {
        $testDevices = @(
            [PSCustomObject]@{ Name = 'Device1'; Site = 'WLLS'; Status = 'Up'; Type = 'Switch' }
            [PSCustomObject]@{ Name = 'Device2'; Site = 'WLLS'; Status = 'Up'; Type = 'Router' }
            [PSCustomObject]@{ Name = 'Device3'; Site = 'BOYO'; Status = 'Down'; Type = 'Switch' }
            [PSCustomObject]@{ Name = 'Device4'; Site = 'BOYO'; Status = 'Up'; Type = 'Switch' }
            [PSCustomObject]@{ Name = 'TestRouter1'; Site = 'WLLS'; Status = 'Warning'; Type = 'Router' }
        )
    }

    It 'Should filter by site' {
        $selected = Select-DevicesByFilter -Devices $testDevices -Site 'WLLS'

        $selected.Count | Should -Be 3
        $selected | ForEach-Object { $_.Site | Should -Be 'WLLS' }
    }

    It 'Should filter by status' {
        $selected = Select-DevicesByFilter -Devices $testDevices -Status 'Up'

        $selected.Count | Should -Be 3
        $selected | ForEach-Object { $_.Status | Should -Be 'Up' }
    }

    It 'Should filter by type' {
        $selected = Select-DevicesByFilter -Devices $testDevices -Type 'Switch'

        $selected.Count | Should -Be 3
        $selected | ForEach-Object { $_.Type | Should -Be 'Switch' }
    }

    It 'Should filter by name pattern' {
        $selected = Select-DevicesByFilter -Devices $testDevices -NamePattern 'Router'

        $selected.Count | Should -Be 2
    }

    It 'Should apply multiple filters' {
        $selected = Select-DevicesByFilter -Devices $testDevices -Site 'WLLS' -Status 'Up'

        $selected.Count | Should -Be 2
    }

    It 'Should respect limit' {
        $selected = Select-DevicesByFilter -Devices $testDevices -Limit 2

        $selected.Count | Should -Be 2
    }

    It 'Should apply custom filter' {
        $selected = Select-DevicesByFilter -Devices $testDevices -CustomFilter { $_.Name -like '*1' }

        $selected.Count | Should -Be 2
    }
}

Describe 'Device Selection Summary' {
    BeforeAll {
        $testDevices = @(
            [PSCustomObject]@{ Name = 'Device1'; Site = 'WLLS'; Status = 'Up'; Type = 'Switch' }
            [PSCustomObject]@{ Name = 'Device2'; Site = 'WLLS'; Status = 'Up'; Type = 'Router' }
            [PSCustomObject]@{ Name = 'Device3'; Site = 'BOYO'; Status = 'Down'; Type = 'Switch' }
        )
    }

    It 'Should return summary with counts' {
        $summary = Get-DeviceSelectionSummary -Devices $testDevices

        $summary.TotalDevices | Should -Be 3
    }

    It 'Should break down by site' {
        $summary = Get-DeviceSelectionSummary -Devices $testDevices

        $summary.BySite['WLLS'] | Should -Be 2
        $summary.BySite['BOYO'] | Should -Be 1
    }

    It 'Should break down by status' {
        $summary = Get-DeviceSelectionSummary -Devices $testDevices

        $summary.ByStatus['Up'] | Should -Be 2
        $summary.ByStatus['Down'] | Should -Be 1
    }
}

Describe 'Pre-Deploy Validation' {
    BeforeAll {
        $testDevices = @(
            [PSCustomObject]@{ Hostname = 'device1.local'; Site = 'WLLS' }
            [PSCustomObject]@{ Hostname = 'device2.local'; Site = 'BOYO' }
        )
    }

    It 'Should validate configuration structure' {
        $config = @{ Setting1 = 'Value1' }
        $result = Test-DeploymentPrerequisites -TargetDevices $testDevices -Configuration $config

        $result.Valid | Should -Be $true
        $result.Checks | Where-Object { $_.Name -eq 'ConfigurationStructure' } |
            Select-Object -ExpandProperty Status | Should -Be 'Pass'
    }

    It 'Should fail for null configuration' {
        $result = Test-DeploymentPrerequisites -TargetDevices $testDevices -Configuration $null

        $result.Valid | Should -Be $false
        $result.Errors | Should -Contain 'Configuration is null or empty'
    }

    It 'Should fail for empty target devices' {
        $config = @{ Setting1 = 'Value1' }
        $result = Test-DeploymentPrerequisites -TargetDevices @() -Configuration $config

        $result.Valid | Should -Be $false
        $result.Errors | Should -Contain 'No target devices specified'
    }

    It 'Should validate template placeholders' {
        $config = @{
            Template = 'hostname {{Hostname}} site {{Site}}'
            Variables = @{}
        }
        $result = Test-DeploymentPrerequisites -TargetDevices $testDevices -Configuration $config

        $result.Checks | Where-Object { $_.Name -eq 'TemplateValidation' } | Should -Not -BeNullOrEmpty
    }
}

Describe 'Configuration Template Validation' {
    It 'Should identify placeholders' {
        $template = 'interface {{InterfaceName}} ip address {{IPAddress}}'
        $result = Test-ConfigurationTemplate -Template $template

        $result.Placeholders | Should -Contain 'InterfaceName'
        $result.Placeholders | Should -Contain 'IPAddress'
    }

    It 'Should render with variables' {
        $template = 'hostname {{Hostname}}'
        $result = Test-ConfigurationTemplate -Template $template -Variables @{ Hostname = 'router1' }

        $result.Valid | Should -Be $true
        $result.RenderedSample | Should -Be 'hostname router1'
    }

    It 'Should render with device properties' {
        $template = 'site {{Site}}'
        $device = [PSCustomObject]@{ Site = 'WLLS' }
        $result = Test-ConfigurationTemplate -Template $template -SampleDevice $device

        $result.Valid | Should -Be $true
        $result.RenderedSample | Should -Be 'site WLLS'
    }

    It 'Should report unresolved placeholders' {
        $template = 'hostname {{Hostname}} secret {{Password}}'
        $result = Test-ConfigurationTemplate -Template $template -Variables @{ Hostname = 'router1' }

        $result.Valid | Should -Be $false
        $result.UnresolvedPlaceholders | Should -Contain 'Password'
    }
}

Describe 'Bulk Operation Execution' {
    BeforeAll {
        $testDevices = @(
            [PSCustomObject]@{ Id = 'D1'; Name = 'Device1' }
            [PSCustomObject]@{ Id = 'D2'; Name = 'Device2' }
            [PSCustomObject]@{ Id = 'D3'; Name = 'Device3' }
        )
    }

    It 'Should execute operation on all devices' {
        $action = { param($Device) return "Processed $($Device.Name)" }

        $result = Start-BulkOperation -Name 'TestOp' -TargetDevices $testDevices -Action $action

        $result.Status | Should -BeIn @('Completed', 'CompletedWithErrors')
        $result.TargetCount | Should -Be 3
        $result.CompletedCount | Should -Be 3
    }

    It 'Should track success and failure counts' {
        $counter = 0
        $action = {
            param($Device)
            $script:counter++
            if ($Device.Id -eq 'D2') { throw 'Simulated failure' }
            return "OK"
        }

        $result = Start-BulkOperation -Name 'TestOp' -TargetDevices $testDevices -Action $action

        $result.SuccessCount | Should -Be 2
        $result.FailedCount | Should -Be 1
    }

    It 'Should stop on first error when requested' {
        $action = {
            param($Device)
            if ($Device.Id -eq 'D1') { throw 'Simulated failure' }
            return "OK"
        }

        $result = Start-BulkOperation -Name 'TestOp' -TargetDevices $testDevices -Action $action -StopOnFirstError

        $result.Status | Should -Be 'Stopped'
        $result.SkippedCount | Should -BeGreaterThan 0
    }

    It 'Should create backup when requested' {
        $action = { param($Device) return "OK" }

        $result = Start-BulkOperation -Name 'TestOp' -TargetDevices $testDevices -Action $action -CreateBackup

        $result.CanRollback | Should -Be $true
        $result.BackupId | Should -Not -BeNullOrEmpty
    }
}

Describe 'Operation Status and History' {
    BeforeAll {
        $testDevices = @([PSCustomObject]@{ Id = 'D1'; Name = 'Device1' })
        $action = { param($Device) return "OK" }
        $script:testOp = Start-BulkOperation -Name 'HistoryTest' -TargetDevices $testDevices -Action $action
    }

    It 'Should retrieve operation status' {
        $status = Get-BulkOperationStatus -OperationId $script:testOp.Id

        $status | Should -Not -BeNullOrEmpty
        $status.Id | Should -Be $script:testOp.Id
    }

    It 'Should retrieve operation history' {
        $history = Get-BulkOperationHistory -Last 5

        $history | Should -Not -BeNullOrEmpty
    }

    It 'Should filter history by name' {
        $history = Get-BulkOperationHistory -Name 'HistoryTest'

        $history | Where-Object { $_.Name -eq 'HistoryTest' } | Should -Not -BeNullOrEmpty
    }
}

Describe 'Progress Tracking' {
    BeforeAll {
        $testDevices = @(
            [PSCustomObject]@{ Id = 'D1' }
            [PSCustomObject]@{ Id = 'D2' }
        )
        $action = { param($Device) Start-Sleep -Milliseconds 10; return "OK" }
        $script:progressOp = Start-BulkOperation -Name 'ProgressTest' -TargetDevices $testDevices -Action $action
    }

    It 'Should return progress information' {
        $progress = Get-OperationProgress -OperationId $script:progressOp.Id

        $progress | Should -Not -BeNullOrEmpty
        $progress.PercentComplete | Should -BeGreaterOrEqual 0
        $progress.Total | Should -Be 2
    }

    It 'Should calculate percent complete' {
        $progress = Get-OperationProgress -OperationId $script:progressOp.Id

        $progress.PercentComplete | Should -BeGreaterOrEqual 0
        $progress.PercentComplete | Should -BeLessOrEqual 100
    }

    It 'Should track elapsed time' {
        $progress = Get-OperationProgress -OperationId $script:progressOp.Id

        $progress.ElapsedTime | Should -Not -BeNullOrEmpty
    }
}

Describe 'Rollback' {
    It 'Should check rollback capability' {
        $testDevices = @([PSCustomObject]@{ Id = 'D1' })
        $action = { param($Device) return "OK" }
        $op = Start-BulkOperation -Name 'RollbackTest' -TargetDevices $testDevices -Action $action -CreateBackup

        $capability = Get-RollbackCapability -OperationId $op.Id

        $capability.CanRollback | Should -Be $true
        $capability.BackupDeviceCount | Should -Be 1
    }

    It 'Should report no rollback for operations without backup' {
        $testDevices = @([PSCustomObject]@{ Id = 'D1' })
        $action = { param($Device) return "OK" }
        $op = Start-BulkOperation -Name 'NoBackupTest' -TargetDevices $testDevices -Action $action

        $capability = Get-RollbackCapability -OperationId $op.Id

        $capability.CanRollback | Should -Be $false
    }

    It 'Should execute rollback' {
        $testDevices = @([PSCustomObject]@{ Id = 'D1' })
        $action = { param($Device) return "OK" }
        $op = Start-BulkOperation -Name 'RollbackExecTest' -TargetDevices $testDevices -Action $action -CreateBackup

        $rollbackAction = { param($DeviceId, $OriginalState) return "Restored" }
        $result = Invoke-OperationRollback -OperationId $op.Id -RollbackAction $rollbackAction

        $result.Status | Should -BeIn @('Completed', 'CompletedWithErrors')
    }
}

Describe 'Runbook Registration' {
    It 'Should register a runbook' {
        $steps = @(
            (New-RunbookStep -Name 'Step1' -Action { return "Step1 done" })
        )

        $runbook = Register-Runbook -Name 'TestRunbook' -Description 'Test runbook' -Steps $steps

        $runbook.Name | Should -Be 'TestRunbook'
        $runbook.Steps.Count | Should -Be 1
    }

    It 'Should retrieve registered runbook' {
        $runbook = Get-Runbook -Name 'TestRunbook'

        $runbook | Should -Not -BeNullOrEmpty
        $runbook.Name | Should -Be 'TestRunbook'
    }

    It 'Should list all runbooks' {
        $runbooks = Get-Runbook

        $runbooks.Count | Should -BeGreaterThan 0
    }

    It 'Should filter runbooks by category' {
        $runbooks = Get-Runbook -Category 'Maintenance'

        $runbooks | ForEach-Object { $_.Category | Should -Be 'Maintenance' }
    }
}

Describe 'Runbook Step Creation' {
    It 'Should create step with action' {
        $step = New-RunbookStep -Name 'TestStep' -Action { return "Done" }

        $step.Name | Should -Be 'TestStep'
        $step.Action | Should -Not -BeNullOrEmpty
    }

    It 'Should create step with command' {
        $step = New-RunbookStep -Name 'CommandStep' -Command 'ping localhost'

        $step.Command | Should -Be 'ping localhost'
    }

    It 'Should set timeout' {
        $step = New-RunbookStep -Name 'TimeoutStep' -TimeoutSeconds 60 -Action { }

        $step.TimeoutSeconds | Should -Be 60
    }

    It 'Should set continue on error' {
        $step = New-RunbookStep -Name 'ContinueStep' -ContinueOnError -Action { }

        $step.ContinueOnError | Should -Be $true
    }
}

Describe 'Runbook Execution' {
    BeforeAll {
        $steps = @(
            (New-RunbookStep -Name 'Step1' -Action { param($Devices, $Parameters) return @{ Step = 1 } }),
            (New-RunbookStep -Name 'Step2' -Action { param($Devices, $Parameters) return @{ Step = 2 } })
        )
        Register-Runbook -Name 'ExecutionTest' -Description 'Test' -Steps $steps
    }

    It 'Should execute runbook' {
        $devices = @([PSCustomObject]@{ Id = 'D1' })
        $result = Invoke-Runbook -Name 'ExecutionTest' -TargetDevices $devices

        $result.Status | Should -BeIn @('Completed', 'CompletedWithErrors')
        $result.StepResults.Count | Should -Be 2
    }

    It 'Should support WhatIf mode' {
        $devices = @([PSCustomObject]@{ Id = 'D1' })
        $result = Invoke-Runbook -Name 'ExecutionTest' -TargetDevices $devices -WhatIf

        $result.WhatIf | Should -Be $true
        $result.StepResults | ForEach-Object { $_.Status | Should -Be 'WhatIf' }
    }

    It 'Should stop on error when requested' {
        $steps = @(
            (New-RunbookStep -Name 'FailStep' -Action { throw 'Failure' }),
            (New-RunbookStep -Name 'Step2' -Action { return 'OK' })
        )
        Register-Runbook -Name 'StopOnErrorTest' -Description 'Test' -Steps $steps

        $result = Invoke-Runbook -Name 'StopOnErrorTest' -TargetDevices @() -StopOnError

        $result.Status | Should -Be 'Stopped'
    }

    It 'Should fail for missing required parameters' {
        $steps = @((New-RunbookStep -Name 'Step1' -Action { }))
        Register-Runbook -Name 'RequiredParamTest' -Description 'Test' -Steps $steps -RequiredParameters @('RequiredParam')

        { Invoke-Runbook -Name 'RequiredParamTest' -TargetDevices @() } |
            Should -Throw '*Missing required parameter*'
    }

    It 'Should fail for unknown runbook' {
        { Invoke-Runbook -Name 'NonExistentRunbook12345' -TargetDevices @() } |
            Should -Throw '*Runbook not found*'
    }
}

Describe 'Built-in Runbooks' {
    It 'Should have HealthCheck runbook' {
        $runbook = Get-Runbook -Name 'HealthCheck'

        $runbook | Should -Not -BeNullOrEmpty
        $runbook.Steps.Count | Should -BeGreaterThan 0
    }

    It 'Should have ConfigBackup runbook' {
        $runbook = Get-Runbook -Name 'ConfigBackup'

        $runbook | Should -Not -BeNullOrEmpty
    }
}

Describe 'Module Exports' {
    It 'Should export all required functions' {
        $exportedFunctions = (Get-Module BulkOperationsModule).ExportedFunctions.Keys

        $requiredFunctions = @(
            'Select-DevicesByFilter',
            'Get-DeviceSelectionSummary',
            'Test-DeploymentPrerequisites',
            'Test-ConfigurationTemplate',
            'Start-BulkOperation',
            'Get-BulkOperationStatus',
            'Get-BulkOperationHistory',
            'Stop-BulkOperation',
            'Get-OperationProgress',
            'Write-OperationProgress',
            'Invoke-OperationRollback',
            'Get-RollbackCapability',
            'Register-Runbook',
            'Get-Runbook',
            'Invoke-Runbook',
            'New-RunbookStep'
        )

        foreach ($func in $requiredFunctions) {
            $exportedFunctions | Should -Contain $func
        }
    }
}
