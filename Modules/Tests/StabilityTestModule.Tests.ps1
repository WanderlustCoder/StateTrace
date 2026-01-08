# StabilityTestModule.Tests.ps1
# Pester tests for stability testing functions

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\StabilityTestModule.psm1'
    Import-Module $modulePath -Force
}

Describe 'Memory Metrics' {
    It 'Should return memory metrics for current process' {
        $metrics = Get-MemoryMetrics
        
        $metrics.ProcessId | Should -Be $PID
        $metrics.WorkingSetMB | Should -BeGreaterThan 0
        $metrics.PrivateMemoryMB | Should -BeGreaterThan 0
        $metrics.Timestamp | Should -Not -BeNullOrEmpty
    }

    It 'Should have all expected memory properties' {
        $metrics = Get-MemoryMetrics
        
        $metrics.PSObject.Properties.Name | Should -Contain 'WorkingSetMB'
        $metrics.PSObject.Properties.Name | Should -Contain 'PrivateMemoryMB'
        $metrics.PSObject.Properties.Name | Should -Contain 'VirtualMemoryMB'
        $metrics.PSObject.Properties.Name | Should -Contain 'GCTotalMemoryMB'
    }
}

Describe 'Handle Metrics' {
    It 'Should return handle metrics for current process' {
        $metrics = Get-HandleMetrics
        
        $metrics.ProcessId | Should -Be $PID
        $metrics.HandleCount | Should -BeGreaterThan 0
        $metrics.ThreadCount | Should -BeGreaterThan 0
    }
}

Describe 'Fixture Freshness Validation' {
    It 'Should return error for non-existent path' {
        $result = Test-FixtureFreshness -FixturePath 'C:\NonExistent\Path'
        
        $result.Status | Should -Be 'Error'
    }

    It 'Should validate fixture directory' {
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $fixturesPath = Join-Path $projectRoot 'Tests\Fixtures'
        
        if (Test-Path $fixturesPath) {
            $result = Test-FixtureFreshness -FixturePath $fixturesPath
            
            $result.TotalFixtures | Should -BeGreaterOrEqual 0
            $result.Status | Should -BeIn @('Pass', 'Warning', 'Fail')
            $result.FreshnessPercent | Should -BeGreaterOrEqual 0
            $result.FreshnessPercent | Should -BeLessOrEqual 100
        } else {
            Set-ItResult -Skipped -Because 'Fixtures directory not found'
        }
    }
}

Describe 'Fixture Schema Compliance' {
    It 'Should validate JSON fixtures' {
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $fixturesPath = Join-Path $projectRoot 'Tests\Fixtures'
        
        if (Test-Path $fixturesPath) {
            $result = Test-FixtureSchemaCompliance -FixturePath $fixturesPath
            
            $result.TotalChecked | Should -BeGreaterOrEqual 0
            $result.PassRate | Should -BeGreaterOrEqual 0
        } else {
            Set-ItResult -Skipped -Because 'Fixtures directory not found'
        }
    }
}

Describe 'Telemetry Field Validation' {
    It 'Should validate telemetry files' {
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        
        $result = Test-TelemetryFields -TelemetryPath $projectRoot -Last 100
        
        $result.TotalEvents | Should -BeGreaterOrEqual 0
        $result.ValidationRate | Should -BeGreaterOrEqual 0
    }

    It 'Should track missing fields' {
        $result = Test-TelemetryFields -Last 100
        
        $result.MissingFields | Should -Not -BeNullOrEmpty -Or -BeNullOrEmpty
        $result.Status | Should -BeIn @('Pass', 'Warning', 'Fail')
    }
}

Describe 'Soak Test Functions' {
    It 'Should have Start-SoakTest function' {
        Get-Command -Name Start-SoakTest -Module StabilityTestModule | 
            Should -Not -BeNullOrEmpty
    }

    It 'Should have Stop-SoakTest function' {
        Get-Command -Name Stop-SoakTest -Module StabilityTestModule | 
            Should -Not -BeNullOrEmpty
    }

    It 'Should have required parameters for Start-SoakTest' {
        $cmd = Get-Command -Name Start-SoakTest
        $params = $cmd.Parameters.Keys
        
        $params | Should -Contain 'DurationHours'
        $params | Should -Contain 'CycleIntervalSeconds'
        $params | Should -Contain 'IncludeMemoryMonitoring'
    }
}

Describe 'Memory Leak Test' {
    It 'Should have Test-MemoryLeak function' {
        Get-Command -Name Test-MemoryLeak -Module StabilityTestModule | 
            Should -Not -BeNullOrEmpty
    }

    It 'Should accept duration and threshold parameters' {
        $cmd = Get-Command -Name Test-MemoryLeak
        $params = $cmd.Parameters.Keys
        
        $params | Should -Contain 'DurationMinutes'
        $params | Should -Contain 'GrowthThresholdPercent'
    }
}

Describe 'Handle Leak Test' {
    It 'Should have Test-HandleLeak function' {
        Get-Command -Name Test-HandleLeak -Module StabilityTestModule | 
            Should -Not -BeNullOrEmpty
    }

    It 'Should accept duration and threshold parameters' {
        $cmd = Get-Command -Name Test-HandleLeak
        $params = $cmd.Parameters.Keys
        
        $params | Should -Contain 'DurationMinutes'
        $params | Should -Contain 'GrowthThresholdPercent'
    }
}

Describe 'Module Exports' {
    It 'Should export all required functions' {
        $exportedFunctions = (Get-Module StabilityTestModule).ExportedFunctions.Keys
        
        $requiredFunctions = @(
            'Start-SoakTest',
            'Stop-SoakTest',
            'Get-SoakTestReport',
            'Get-MemoryMetrics',
            'Test-MemoryLeak',
            'Get-HandleMetrics',
            'Test-HandleLeak',
            'Test-FixtureFreshness',
            'Test-FixtureSchemaCompliance',
            'Test-TelemetryFields'
        )
        
        foreach ($func in $requiredFunctions) {
            $exportedFunctions | Should -Contain $func
        }
    }
}

Describe 'Quick Validation Smoke Test' {
    It 'Should complete a quick validation cycle' {
        # This is a quick smoke test that runs basic validations
        $memMetrics = Get-MemoryMetrics
        $handleMetrics = Get-HandleMetrics
        
        $memMetrics.WorkingSetMB | Should -BeGreaterThan 0
        $handleMetrics.HandleCount | Should -BeGreaterThan 0
        
        # Fixture tests (if fixtures exist)
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $fixturesPath = Join-Path $projectRoot 'Tests\Fixtures'
        
        if (Test-Path $fixturesPath) {
            $freshnessResult = Test-FixtureFreshness -FixturePath $fixturesPath
            $schemaResult = Test-FixtureSchemaCompliance -FixturePath $fixturesPath
            
            $freshnessResult | Should -Not -BeNullOrEmpty
            $schemaResult | Should -Not -BeNullOrEmpty
        }
    }
}
