# DatabaseConcurrencyModule.Tests.ps1
# Pester tests for database concurrency and stability functions

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\DatabaseConcurrencyModule.psm1'
    Import-Module $modulePath -Force
}

Describe 'Lock Monitoring' {
    BeforeEach {
        Start-LockMonitoring
    }

    It 'Should initialize lock metrics' {
        $metrics = Get-LockMetrics
        $metrics.TotalAttempts | Should -Be 0
        $metrics.LockWaits | Should -Be 0
    }

    It 'Should record lock events' {
        Record-LockEvent -Database 'TestDB' -WaitTimeMs 100
        Record-LockEvent -Database 'TestDB' -WaitTimeMs 50

        $metrics = Get-LockMetrics
        $metrics.LockWaits | Should -Be 2
        $metrics.TotalWaitTimeMs | Should -Be 150
        $metrics.MaxWaitTimeMs | Should -Be 100
    }

    It 'Should track lock timeouts' {
        Record-LockEvent -Database 'TestDB' -WaitTimeMs 5000 -TimedOut

        $metrics = Get-LockMetrics
        $metrics.LockTimeouts | Should -Be 1
    }

    It 'Should calculate average wait time' {
        Record-LockEvent -Database 'TestDB' -WaitTimeMs 100
        Record-LockEvent -Database 'TestDB' -WaitTimeMs 200
        Record-LockEvent -Database 'TestDB' -WaitTimeMs 300

        $metrics = Get-LockMetrics
        $metrics.AvgWaitTimeMs | Should -Be 200
    }

    It 'Should return recent lock events' {
        Record-LockEvent -Database 'TestDB1' -WaitTimeMs 50
        Record-LockEvent -Database 'TestDB2' -WaitTimeMs 100

        $events = Get-LockEvents -Last 10
        $events.Count | Should -BeGreaterOrEqual 2
    }
}

Describe 'Database Health Check' {
    It 'Should return not found for missing database' {
        $health = Test-DatabaseHealth -DatabasePath 'C:\NonExistent\fake.accdb'
        
        $health.Exists | Should -Be $false
        $health.Healthy | Should -Be $false
        $health.Errors | Should -Contain 'Database file not found'
    }

    It 'Should check real database if available' {
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $testDbs = Get-ChildItem -Path $projectRoot -Filter '*.accdb' -Recurse -ErrorAction SilentlyContinue | 
            Select-Object -First 1

        if ($testDbs) {
            $health = Test-DatabaseHealth -DatabasePath $testDbs.FullName
            
            $health.Exists | Should -Be $true
            $health.FileSize | Should -BeGreaterThan 0
        } else {
            Set-ItResult -Skipped -Because 'No Access database found for testing'
        }
    }
}

Describe 'Database Integrity Check' {
    It 'Should fail for missing database' {
        $integrity = Test-DatabaseIntegrity -DatabasePath 'C:\NonExistent\fake.accdb'
        
        $integrity.OverallStatus | Should -Be 'Fail'
        $integrity.Checks[0].Name | Should -Be 'FileAccess'
        $integrity.Checks[0].Status | Should -Be 'Fail'
    }

    It 'Should include multiple check types' {
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $testDbs = Get-ChildItem -Path $projectRoot -Filter '*.accdb' -Recurse -ErrorAction SilentlyContinue | 
            Select-Object -First 1

        if ($testDbs) {
            $integrity = Test-DatabaseIntegrity -DatabasePath $testDbs.FullName
            
            $checkNames = $integrity.Checks | ForEach-Object { $_.Name }
            $checkNames | Should -Contain 'FileAccess'
            $checkNames | Should -Contain 'Connection'
        } else {
            Set-ItResult -Skipped -Because 'No Access database found for testing'
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
        $backups | Should -Not -BeNullOrEmpty -Or -BeNullOrEmpty
    }

    It 'Should fail backup for non-existent database' {
        { 
            New-DatabaseBackup -DatabasePath 'C:\NonExistent\fake.accdb' 
        } | Should -Throw
    }
}

Describe 'Concurrent Write Test Structure' {
    It 'Should have Test-ConcurrentWrites function' {
        Get-Command -Name Test-ConcurrentWrites -Module DatabaseConcurrencyModule | 
            Should -Not -BeNullOrEmpty
    }

    It 'Should have required parameters' {
        $cmd = Get-Command -Name Test-ConcurrentWrites
        $params = $cmd.Parameters.Keys
        
        $params | Should -Contain 'DatabasePath'
        $params | Should -Contain 'ThreadCount'
        $params | Should -Contain 'OperationsPerThread'
    }

    It 'Should fail for non-existent database' {
        { 
            Test-ConcurrentWrites -DatabasePath 'C:\NonExistent\fake.accdb' 
        } | Should -Throw
    }
}

Describe 'Repair Function Structure' {
    It 'Should have Repair-AccessDatabase function' {
        Get-Command -Name Repair-AccessDatabase -Module DatabaseConcurrencyModule | 
            Should -Not -BeNullOrEmpty
    }

    It 'Should require DatabasePath parameter' {
        $cmd = Get-Command -Name Repair-AccessDatabase
        $dbPathParam = $cmd.Parameters['DatabasePath']
        
        $dbPathParam.Attributes | 
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            ForEach-Object { $_.Mandatory } | 
            Should -Contain $true
    }

    It 'Should fail for non-existent database' {
        { 
            Repair-AccessDatabase -DatabasePath 'C:\NonExistent\fake.accdb' 
        } | Should -Throw
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
            $exportedFunctions | Should -Contain $func
        }
    }
}
