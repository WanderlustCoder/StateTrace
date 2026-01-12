# FleetHealthModule.Tests.ps1
# Pester tests for fleet health monitoring, anomaly detection, and forecasting

$modulePath = Join-Path $PSScriptRoot '..\FleetHealthModule.psm1'
Import-Module $modulePath -Force
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')

Describe 'Configuration' {
    It 'Should return default config' {
        $config = Get-FleetHealthConfig

        $config.AnomalyThresholdStdDev | Should Be 2.0
        $config.TrendWindowDays | Should Be 30
        $config.ForecastHorizonDays | Should Be 90
    }

    It 'Should update config values' {
        $result = Set-FleetHealthConfig -AnomalyThresholdStdDev 3.0 -TrendWindowDays 14

        $result.AnomalyThresholdStdDev | Should Be 3.0
        $result.TrendWindowDays | Should Be 14

        # Reset
        Set-FleetHealthConfig -AnomalyThresholdStdDev 2.0 -TrendWindowDays 30
    }

    It 'Should have health check thresholds' {
        $config = Get-FleetHealthConfig

        $config.HealthCheckThresholds.PortUtilizationWarning | Should BeGreaterThan 0
        $config.HealthCheckThresholds.PortUtilizationCritical | Should BeGreaterThan 0
    }
}

Describe 'Fleet Health Summary' {
    It 'Should return health summary structure' {
        $summary = Get-FleetHealthSummary

        $summary.Timestamp | Should Not BeNullOrEmpty
        $summary.TotalDevices | Should BeGreaterThan -1
        $summary.HealthScore | Should BeGreaterThan -1
        $summary.HealthScore | Should BeLessThan 101
    }

    It 'Should include device status breakdown' {
        $summary = Get-FleetHealthSummary

        ($summary.DevicesByStatus -is [hashtable]) | Should Be $true
    }
}

Describe 'Status Distribution' {
    It 'Should calculate distribution from items' {
        $items = @(
            [PSCustomObject]@{ Name = 'A'; Status = 'Up' }
            [PSCustomObject]@{ Name = 'B'; Status = 'Up' }
            [PSCustomObject]@{ Name = 'C'; Status = 'Down' }
            [PSCustomObject]@{ Name = 'D'; Status = 'Warning' }
        )

        $result = Get-FleetStatusDistribution -Items $items -StatusProperty 'Status'

        $result.Total | Should Be 4
        $result.Distribution['Up'].Count | Should Be 2
        $result.Distribution['Up'].Percent | Should Be 50
        $result.Distribution['Down'].Count | Should Be 1
    }

    It 'Should handle empty items' {
        $result = Get-FleetStatusDistribution -Items @() -StatusProperty 'Status'

        $result.Total | Should Be 0
    }

    It 'Should handle missing status property' {
        $items = @(
            [PSCustomObject]@{ Name = 'A' }
            [PSCustomObject]@{ Name = 'B' }
        )

        $result = Get-FleetStatusDistribution -Items $items -StatusProperty 'Status'

        $result.Distribution['Unknown'].Count | Should Be 2
    }
}

Describe 'Report Templates' {
    It 'Should register a report template' {
        $result = Register-FleetReportTemplate `
            -Name 'TestReport' `
            -Title 'Test Report' `
            -Description 'A test report' `
            -Generator { param($Parameters) return @{ Test = 'Data' } }

        $result.Name | Should Be 'TestReport'
        $result.Title | Should Be 'Test Report'
    }

    It 'Should retrieve registered templates' {
        $templates = Get-FleetReportTemplates

        $templates.Count | Should BeGreaterThan 0
    }

    It 'Should retrieve specific template' {
        $template = Get-FleetReportTemplates -Name 'DailyHealthSummary'

        $template | Should Not BeNullOrEmpty
        $template.Title | Should Be 'Daily Fleet Health Summary'
    }

    It 'Should return null for unknown template' {
        $template = Get-FleetReportTemplates -Name 'NonExistentTemplate12345'

        $template | Should BeNullOrEmpty
    }
}

Describe 'Report Generation' {
    It 'Should generate report from template' {
        $report = New-FleetReport -TemplateName 'DailyHealthSummary' -Format 'Json'

        $report | Should Not BeNullOrEmpty
        $parsed = $report | ConvertFrom-Json
        $parsed.Title | Should Be 'Daily Fleet Health Summary'
    }

    It 'Should generate markdown report' {
        $report = New-FleetReport -TemplateName 'DailyHealthSummary' -Format 'Markdown'

        $report | Should Match '# Daily Fleet Health Summary'
    }

    It 'Should fail for unknown template' {
        { New-FleetReport -TemplateName 'NonExistentTemplate12345' } |
            Assert-Throws -Message 'Report template not found'
    }
}

Describe 'Rolling Baseline' {
    It 'Should calculate baseline statistics' {
        $values = @(10, 12, 11, 13, 10, 12, 14, 11, 10, 13)
        $baseline = Get-RollingBaseline -Values $values

        $baseline.Mean | Should BeGreaterThan 10
        $baseline.Mean | Should BeLessThan 14
        $baseline.StdDev | Should BeGreaterThan 0
        $baseline.Count | Should Be 10
    }

    It 'Should respect window size' {
        $values = @(1, 2, 3, 4, 5, 100, 101, 102, 103, 104)
        $baseline = Get-RollingBaseline -Values $values -WindowSize 5

        # Should only use last 5 values (100-104)
        $baseline.Mean | Should BeGreaterThan 90
        $baseline.Count | Should Be 5
    }

    It 'Should handle empty values' {
        $baseline = Get-RollingBaseline -Values @()

        $baseline.Mean | Should Be 0
        $baseline.StdDev | Should Be 0
        $baseline.Count | Should Be 0
    }

    It 'Should handle single value' {
        $baseline = Get-RollingBaseline -Values @(42)

        $baseline.Mean | Should Be 42
        $baseline.StdDev | Should Be 0
        $baseline.Count | Should Be 1
    }
}

Describe 'Anomaly Detection' {
    It 'Should detect high anomaly' {
        $result = Test-AnomalyDetection -Value 100 -BaselineMean 50 -BaselineStdDev 10

        $result.IsAnomaly | Should Be $true
        $result.Direction | Should Be 'High'
        $result.DeviationStdDev | Should Be 5
    }

    It 'Should detect low anomaly' {
        $result = Test-AnomalyDetection -Value 10 -BaselineMean 50 -BaselineStdDev 10

        $result.IsAnomaly | Should Be $true
        $result.Direction | Should Be 'Low'
    }

    It 'Should not flag normal values' {
        $result = Test-AnomalyDetection -Value 52 -BaselineMean 50 -BaselineStdDev 10

        $result.IsAnomaly | Should Be $false
        $result.Direction | Should Be 'Normal'
    }

    It 'Should respect custom threshold' {
        $result = Test-AnomalyDetection -Value 70 -BaselineMean 50 -BaselineStdDev 10 -ThresholdStdDev 3

        # 2 std dev, threshold is 3, so not anomaly
        $result.IsAnomaly | Should Be $false
    }

    It 'Should assign severity levels' {
        $result = Test-AnomalyDetection -Value 150 -BaselineMean 50 -BaselineStdDev 10

        $result.IsAnomaly | Should Be $true
        (@('Warning', 'Critical') -contains $result.Severity) | Should Be $true
    }
}

Describe 'Find Metric Anomalies' {
    It 'Should find anomalies in time series' {
        $dataPoints = @()
        # Normal values
        for ($i = 0; $i -lt 20; $i++) {
            $dataPoints += [PSCustomObject]@{
                Timestamp = [datetime]::UtcNow.AddDays(-20 + $i)
                Value = 50 + (Get-Random -Minimum -5 -Maximum 5)
            }
        }
        # Add anomaly
        $dataPoints += [PSCustomObject]@{
            Timestamp = [datetime]::UtcNow
            Value = 150
        }

        $result = Find-MetricAnomalies -DataPoints $dataPoints -ValueProperty 'Value' -BaselineWindowSize 10

        $result.TotalPoints | Should Be 21
        $result.AnomaliesFound | Should BeGreaterThan 0
    }

    It 'Should return empty for insufficient data' {
        $dataPoints = @(
            [PSCustomObject]@{ Timestamp = [datetime]::UtcNow; Value = 50 }
        )

        $result = Find-MetricAnomalies -DataPoints $dataPoints -ValueProperty 'Value' -BaselineWindowSize 14

        $result.AnomaliesFound | Should Be 0
    }
}

Describe 'Trend Analysis' {
    It 'Should detect increasing trend' {
        $dataPoints = @()
        for ($i = 0; $i -lt 30; $i++) {
            $dataPoints += [PSCustomObject]@{
                Timestamp = [datetime]::UtcNow.AddDays(-30 + $i)
                Value = 10 + ($i * 2)  # Steady increase
            }
        }

        $trend = Get-MetricTrend -DataPoints $dataPoints -ValueProperty 'Value'

        $trend.Trend | Should Be 'Increasing'
        $trend.Slope | Should BeGreaterThan 0
        $trend.ChangePercent | Should BeGreaterThan 0
    }

    It 'Should detect decreasing trend' {
        $dataPoints = @()
        for ($i = 0; $i -lt 30; $i++) {
            $dataPoints += [PSCustomObject]@{
                Timestamp = [datetime]::UtcNow.AddDays(-30 + $i)
                Value = 100 - ($i * 2)  # Steady decrease
            }
        }

        $trend = Get-MetricTrend -DataPoints $dataPoints -ValueProperty 'Value'

        $trend.Trend | Should Be 'Decreasing'
        $trend.Slope | Should BeLessThan 0
    }

    It 'Should detect stable trend' {
        $dataPoints = @()
        for ($i = 0; $i -lt 30; $i++) {
            $dataPoints += [PSCustomObject]@{
                Timestamp = [datetime]::UtcNow.AddDays(-30 + $i)
                Value = 50  # Constant
            }
        }

        $trend = Get-MetricTrend -DataPoints $dataPoints -ValueProperty 'Value'

        $trend.Trend | Should Be 'Stable'
    }

    It 'Should handle insufficient data' {
        $dataPoints = @(
            [PSCustomObject]@{ Timestamp = [datetime]::UtcNow; Value = 50 }
        )

        $trend = Get-MetricTrend -DataPoints $dataPoints -ValueProperty 'Value'

        $trend.Trend | Should Be 'Insufficient Data'
    }
}

Describe 'Trend Analysis Report' {
    It 'Should analyze multiple metrics' {
        $dataPoints = @()
        for ($i = 0; $i -lt 30; $i++) {
            $dataPoints += [PSCustomObject]@{
                Timestamp = [datetime]::UtcNow.AddDays(-30 + $i)
                CPU = 50 + ($i * 0.5)
                Memory = 60 - ($i * 0.3)
            }
        }

        $report = Get-TrendAnalysisReport -DataPoints $dataPoints -MetricProperties @('CPU', 'Memory')

        $report.Metrics.CPU | Should Not BeNullOrEmpty
        $report.Metrics.Memory | Should Not BeNullOrEmpty
        $report.TotalDataPoints | Should Be 30
    }
}

Describe 'Capacity Forecasting' {
    It 'Should forecast future values' {
        $dataPoints = @()
        for ($i = 0; $i -lt 30; $i++) {
            $dataPoints += [PSCustomObject]@{
                Timestamp = [datetime]::UtcNow.AddDays(-30 + $i)
                Utilization = 40 + ($i * 1)  # Increasing 1% per day
            }
        }

        $forecast = Get-CapacityForecast -DataPoints $dataPoints -ValueProperty 'Utilization' -ForecastDays 30

        $forecast.CurrentValue | Should BeGreaterThan 60
        $forecast.ForecastedValue | Should BeGreaterThan $forecast.CurrentValue
        $forecast.Projections.Count | Should Be 30
    }

    It 'Should calculate days to capacity' {
        $dataPoints = @()
        for ($i = 0; $i -lt 30; $i++) {
            $dataPoints += [PSCustomObject]@{
                Timestamp = [datetime]::UtcNow.AddDays(-30 + $i)
                Utilization = 70 + ($i * 1)  # Starting at 70%, increasing
            }
        }

        $forecast = Get-CapacityForecast `
            -DataPoints $dataPoints `
            -ValueProperty 'Utilization' `
            -ForecastDays 60 `
            -CapacityLimit 100

        $forecast.DaysToCapacity | Should Not BeNullOrEmpty
        $forecast.CapacityReachedDate | Should Not BeNullOrEmpty
    }
}

Describe 'Port Utilization Forecast' {
    It 'Should forecast port utilization' {
        $dataPoints = @()
        for ($i = 0; $i -lt 30; $i++) {
            $dataPoints += [PSCustomObject]@{
                Timestamp = [datetime]::UtcNow.AddDays(-30 + $i)
                UtilizationPercent = 50 + ($i * 0.5)
            }
        }

        $forecast = Get-PortUtilizationForecast -UtilizationData $dataPoints -ForecastDays 60

        $forecast.WarningThreshold | Should Be 70
        $forecast.CriticalThreshold | Should Be 90
        $forecast.Projections.Count | Should Be 60
    }
}

Describe 'Health Check' {
    It 'Should run health check' {
        $result = Invoke-FleetHealthCheck

        $result.Timestamp | Should Not BeNullOrEmpty
        (@('Healthy', 'Warning', 'Critical') -contains $result.OverallStatus) | Should Be $true
        $result.Checks.Count | Should BeGreaterThan 0
    }

    It 'Should include check details when requested' {
        $result = Invoke-FleetHealthCheck -IncludeDetails

        $result.Checks | Where-Object { $_.Details -ne $null } | Should Not BeNullOrEmpty
    }
}

Describe 'Scheduled Health Checks' {
    BeforeAll {
        $configPath = Join-Path $PSScriptRoot '..\..\Data\HealthCheckSchedules'
        if (-not (Test-Path $configPath)) {
            New-Item -Path $configPath -ItemType Directory -Force | Out-Null
        }
    }

    It 'Should create scheduled health check' {
        $result = New-ScheduledHealthCheck -Name 'TestCheck' -Schedule 'Daily'

        $result.Name | Should Be 'TestCheck'
        $result.Schedule | Should Be 'Daily'
    }

    It 'Should list scheduled health checks' {
        $checks = Get-ScheduledHealthChecks

        # May or may not have checks
        $checks | Should Not Be $null
    }
}

Describe 'Module Exports' {
    It 'Should export all required functions' {
        $exportedFunctions = (Get-Module FleetHealthModule).ExportedFunctions.Keys

        $requiredFunctions = @(
            'Set-FleetHealthConfig',
            'Get-FleetHealthConfig',
            'Get-FleetHealthSummary',
            'Get-FleetStatusDistribution',
            'Register-FleetReportTemplate',
            'Get-FleetReportTemplates',
            'New-FleetReport',
            'Get-RollingBaseline',
            'Test-AnomalyDetection',
            'Find-MetricAnomalies',
            'Get-MetricTrend',
            'Get-TrendAnalysisReport',
            'Get-CapacityForecast',
            'Get-PortUtilizationForecast',
            'Invoke-FleetHealthCheck',
            'New-ScheduledHealthCheck',
            'Get-ScheduledHealthChecks'
        )

        foreach ($func in $requiredFunctions) {
            ($exportedFunctions -contains $func) | Should Be $true
        }
    }
}
