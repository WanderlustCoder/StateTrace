Set-StrictMode -Version Latest

Describe "ParserRunspaceModule" {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSCommandPath) "..\\ParserRunspaceModule.psm1"
        Import-Module (Resolve-Path $modulePath) -Force
    }

    AfterAll {
        Remove-Module ParserRunspaceModule -Force -ErrorAction SilentlyContinue
    }

    It "invokes the worker once per file when running synchronously" {
        Mock -ModuleName ParserRunspaceModule -CommandName Invoke-DeviceParseWorker -MockWith {}

        $files = @('C:\logs\device1.log', 'C:\logs\device2.log')
        ParserRunspaceModule\Invoke-DeviceParsingJobs -DeviceFiles $files -ModulesPath 'C:\modules' -ArchiveRoot 'C:\archives' -DatabasePath $null -Synchronous

        Assert-MockCalled -ModuleName ParserRunspaceModule -CommandName Invoke-DeviceParseWorker -Times 2
        Assert-MockCalled -ModuleName ParserRunspaceModule -CommandName Invoke-DeviceParseWorker -ParameterFilter { $FilePath -eq 'C:\logs\device1.log' -and -not $EnableVerbose } -Times 1
        Assert-MockCalled -ModuleName ParserRunspaceModule -CommandName Invoke-DeviceParseWorker -ParameterFilter { $FilePath -eq 'C:\logs\device2.log' -and -not $EnableVerbose } -Times 1
    }

    It "falls back to synchronous execution when MaxThreads is 1" {
        Mock -ModuleName ParserRunspaceModule -CommandName Invoke-DeviceParseWorker -MockWith {}

        ParserRunspaceModule\Invoke-DeviceParsingJobs -DeviceFiles @('C:\logs\single.log') -ModulesPath 'C:\modules' -ArchiveRoot 'C:\archives' -DatabasePath 'C:\db.accdb' -MaxThreads 1

        Assert-MockCalled -ModuleName ParserRunspaceModule -CommandName Invoke-DeviceParseWorker -ParameterFilter { $FilePath -eq 'C:\logs\single.log' } -Times 1
    }

    Context "Scheduler metrics helpers" {
        It "initializes metrics context" {
            InModuleScope -ModuleName ParserRunspaceModule {
                $projectRoot = Join-Path $TestDrive 'MetricsProject'
                $modulesDir = Join-Path $projectRoot 'Modules'
                New-Item -ItemType Directory -Path $modulesDir -Force | Out-Null

                $context = Initialize-SchedulerMetricsContext -ModulesPath $modulesDir -DeviceCount 5 -MaxThreads 3 -MaxWorkersPerSite 2 -MaxActiveSites 1
                $context | Should Not Be $null

                $metricsDir = Join-Path $projectRoot 'Logs\IngestionMetrics'
                Test-Path $metricsDir | Should Be $true
                (Split-Path -Parent $context.FilePath) | Should Be ([System.IO.Path]::GetFullPath($metricsDir))
                $context.TotalDevices | Should Be 5
                $context.MaxThreads | Should Be 3
                $context.MinThreads | Should Be 1
                $context.JobsPerThread | Should Be 2
                $context.AdaptiveEnabled | Should Be $false
                ($context.CpuCount -ge 1) | Should Be $true
            }
        }

        It "records snapshots when counts change" {
            InModuleScope -ModuleName ParserRunspaceModule {
                $projectRoot = Join-Path $TestDrive 'MetricsSnapshots'
                $modulesDir = Join-Path $projectRoot 'Modules'
                New-Item -ItemType Directory -Path $modulesDir -Force | Out-Null

                $context = Initialize-SchedulerMetricsContext -ModulesPath $modulesDir -DeviceCount 2 -MaxThreads 4 -MaxWorkersPerSite 1 -MaxActiveSites 2 -MinIntervalSeconds 0 -AdaptiveThreads
                $context.MinIntervalSeconds = 0

                Write-ParserSchedulerMetricSnapshot -Context $context -ActiveWorkers 0 -ActiveSites 0 -QueuedJobs 2 -QueuedSites 2 -ThreadBudget 2 -Force
                Write-ParserSchedulerMetricSnapshot -Context $context -ActiveWorkers 0 -ActiveSites 0 -QueuedJobs 2 -QueuedSites 2 -ThreadBudget 2
                Write-ParserSchedulerMetricSnapshot -Context $context -ActiveWorkers 1 -ActiveSites 1 -QueuedJobs 1 -QueuedSites 2 -ThreadBudget 3
                Finalize-SchedulerMetricsContext -Context $context

                $entries = Get-Content -Path $context.FilePath -Raw | ConvertFrom-Json
                $entries.Count | Should Be 2
                $entries[0].ThreadBudget | Should Be 2
                $entries[0].QueuedJobs | Should Be 2
                $entries[1].ActiveWorkers | Should Be 1
                $entries[1].QueuedJobs | Should Be 1
                $entries[1].ThreadBudget | Should Be 3
            }
        }
    }

    Context "Adaptive thread budgeting" {
        It "scales with queue depth" {
            InModuleScope -ModuleName ParserRunspaceModule {
                $budget = Get-AdaptiveThreadBudget -ActiveWorkers 0 -QueuedJobs 10 -CpuCount 4 -MinThreads 1 -MaxThreads 8 -JobsPerThread 2
                $budget | Should Be 5
            }
        }

        It "does not drop below active workers" {
            InModuleScope -ModuleName ParserRunspaceModule {
                $budget = Get-AdaptiveThreadBudget -ActiveWorkers 3 -QueuedJobs 0 -CpuCount 4 -MinThreads 2 -MaxThreads 6 -JobsPerThread 2
                $budget | Should Be 3
            }
        }

        It "honors the ceiling" {
            InModuleScope -ModuleName ParserRunspaceModule {
                $budget = Get-AdaptiveThreadBudget -ActiveWorkers 1 -QueuedJobs 50 -CpuCount 2 -MinThreads 1 -MaxThreads 4 -JobsPerThread 1
                $budget | Should Be 4
            }
        }
    }
}
