# DatabaseConcurrencyModule.Tests.ps1
# Pester tests for database concurrency and stability functions

$modulePath = Join-Path $PSScriptRoot '..\DatabaseConcurrencyModule.psm1'
Import-Module $modulePath -Force
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')

Describe 'Lock Monitoring' {
    BeforeEach {
        Start-LockMonitoring
    }

    It 'Should initialize lock metrics' {
        $metrics = Get-LockMetrics
        $metrics.TotalAttempts | Should Be 0
        $metrics.LockWaits | Should Be 0
    }

    It 'Should record lock events' {
        Record-LockEvent -Database 'TestDB' -WaitTimeMs 100
        Record-LockEvent -Database 'TestDB' -WaitTimeMs 50

        $metrics = Get-LockMetrics
        $metrics.LockWaits | Should Be 2
        $metrics.TotalWaitTimeMs | Should Be 150
        $metrics.MaxWaitTimeMs | Should Be 100
    }

    It 'Should track lock timeouts' {
        Record-LockEvent -Database 'TestDB' -WaitTimeMs 5000 -TimedOut

        $metrics = Get-LockMetrics
        $metrics.LockTimeouts | Should Be 1
    }

    It 'Should calculate average wait time' {
        Record-LockEvent -Database 'TestDB' -WaitTimeMs 100
        Record-LockEvent -Database 'TestDB' -WaitTimeMs 200
        Record-LockEvent -Database 'TestDB' -WaitTimeMs 300

        $metrics = Get-LockMetrics
        $metrics.AvgWaitTimeMs | Should Be 200
    }

    It 'Should return recent lock events' {
        Record-LockEvent -Database 'TestDB1' -WaitTimeMs 50
        Record-LockEvent -Database 'TestDB2' -WaitTimeMs 100

        $events = Get-LockEvents -Last 10
        $events.Count | Should BeGreaterThan 1
    }
}

Describe 'Database Health Check' {
    It 'Should return not found for missing database' {
        $health = Test-DatabaseHealth -DatabasePath 'C:\NonExistent\fake.accdb'
        
        $health.Exists | Should Be $false
        $health.Healthy | Should Be $false
        ($health.Errors -contains 'Database file not found') | Should Be $true
    }

    It 'Should check real database if available' {
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $testDbs = Get-ChildItem -Path $projectRoot -Filter '*.accdb' -Recurse -ErrorAction SilentlyContinue | 
            Select-Object -First 1

        if ($testDbs) {
            $health = Test-DatabaseHealth -DatabasePath $testDbs.FullName
            
            $health.Exists | Should Be $true
            $health.FileSize | Should BeGreaterThan 0
        } else {
            Set-TestInconclusive -Message 'No Access database found for testing'
        }
    }
}

Describe 'Database Integrity Check' {
    It 'Should fail for missing database' {
        $integrity = Test-DatabaseIntegrity -DatabasePath 'C:\NonExistent\fake.accdb'
        
        $integrity.OverallStatus | Should Be 'Fail'
        $integrity.Checks[0].Name | Should Be 'FileAccess'
        $integrity.Checks[0].Status | Should Be 'Fail'
    }

    It 'Should include multiple check types' {
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $testDbs = Get-ChildItem -Path $projectRoot -Filter '*.accdb' -Recurse -ErrorAction SilentlyContinue | 
            Select-Object -First 1

        if ($testDbs) {
            $integrity = Test-DatabaseIntegrity -DatabasePath $testDbs.FullName
            
            $checkNames = $integrity.Checks | ForEach-Object { $_.Name }
            ($checkNames -contains 'FileAccess') | Should Be $true
            ($checkNames -contains 'Connection') | Should Be $true
        } else {
            Set-TestInconclusive -Message 'No Access database found for testing'
        }
    }
}

Describe 'Backup Functions' {
    BeforeAll {
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $testBackupFolder = Join-Path $projectRoot 'Data\Backups\Test'
        
        if (-not (Test-Path $testBackupFolder)) {
            New-Item -Path $testBackupFolder -ItemType Directory -Force | Out-Null
        }
    }

    AfterAll {
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $testBackupFolder = Join-Path $projectRoot 'Data\Backups\Test'
        
        if (Test-Path $testBackupFolder) {
            Remove-Item -Path $testBackupFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Should list backups from folder' {
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $backupFolder = Join-Path $projectRoot 'Data\Backups'
        
        # This just tests the function runs without error
        $backups = Get-DatabaseBackups -BackupFolder $backupFolder
        
        # May or may not have backups, but function should work
        ($null -eq $backups -or $backups.Count -ge 0) | Should Be $true
    }

    It 'Should fail backup for non-existent database' {
        Assert-Throws {
            New-DatabaseBackup -DatabasePath 'C:\NonExistent\fake.accdb'
        }
    }
}

Describe 'Concurrent Write Test Structure' {
    It 'Should have Test-ConcurrentWrites function' {
        Get-Command -Name Test-ConcurrentWrites -Module DatabaseConcurrencyModule | 
            Should Not BeNullOrEmpty
    }

    It 'Should have required parameters' {
        $cmd = Get-Command -Name Test-ConcurrentWrites
        $params = $cmd.Parameters.Keys
        
        ($params -contains 'DatabasePath') | Should Be $true
        ($params -contains 'ThreadCount') | Should Be $true
        ($params -contains 'OperationsPerThread') | Should Be $true
    }

    It 'Should fail for non-existent database' {
        Assert-Throws {
            Test-ConcurrentWrites -DatabasePath 'C:\NonExistent\fake.accdb'
        }
    }
}

Describe 'Repair Function Structure' {
    It 'Should have Repair-AccessDatabase function' {
        Get-Command -Name Repair-AccessDatabase -Module DatabaseConcurrencyModule | 
            Should Not BeNullOrEmpty
    }

    It 'Should require DatabasePath parameter' {
        $cmd = Get-Command -Name Repair-AccessDatabase
        $dbPathParam = $cmd.Parameters['DatabasePath']
        
        (
            $dbPathParam.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory }
        ) -contains $true | Should Be $true
    }

    It 'Should fail for non-existent database' {
        Assert-Throws {
            Repair-AccessDatabase -DatabasePath 'C:\NonExistent\fake.accdb'
        }
    }
}

Describe 'Module Exports' {
    It 'Should export all required functions' {
        $exportedFunctions = (Get-Module DatabaseConcurrencyModule).ExportedFunctions.Keys
        
        $requiredFunctions = @(
            'Test-ConcurrentWrites',
            'Start-LockMonitoring',
            'Record-LockEvent',
            'Get-LockMetrics',
            'Get-LockEvents',
            'Repair-AccessDatabase',
            'Test-DatabaseHealth',
            'New-DatabaseBackup',
            'Get-DatabaseBackups',
            'Restore-DatabaseBackup',
            'Test-DatabaseIntegrity'
        )
        
        foreach ($func in $requiredFunctions) {
            ($exportedFunctions -contains $func) | Should Be $true
        }
    }
}
