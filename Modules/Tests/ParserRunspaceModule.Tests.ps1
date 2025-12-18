Set-StrictMode -Version Latest

function Get-AutoScaleConcurrencyProfile { }

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
        Mock -ModuleName ParserRunspaceModule -CommandName Publish-SchedulerLaunchTelemetry -MockWith {}

        $files = @('C:\logs\device1.log', 'C:\logs\device2.log')
        ParserRunspaceModule\Invoke-DeviceParsingJobs -DeviceFiles $files -ModulesPath 'C:\modules' -ArchiveRoot 'C:\archives' -DatabasePath $null -Synchronous

        Assert-MockCalled -ModuleName ParserRunspaceModule -CommandName Invoke-DeviceParseWorker -Times 2
        Assert-MockCalled -ModuleName ParserRunspaceModule -CommandName Invoke-DeviceParseWorker -ParameterFilter { $FilePath -eq 'C:\logs\device1.log' -and -not $EnableVerbose -and $SiteKey -eq 'device1' } -Times 1
        Assert-MockCalled -ModuleName ParserRunspaceModule -CommandName Invoke-DeviceParseWorker -ParameterFilter { $FilePath -eq 'C:\logs\device2.log' -and -not $EnableVerbose -and $SiteKey -eq 'device2' } -Times 1
        Assert-MockCalled -ModuleName ParserRunspaceModule -CommandName Publish-SchedulerLaunchTelemetry -Times 2
    }

    It "falls back to synchronous execution when MaxThreads is 1" {
        Mock -ModuleName ParserRunspaceModule -CommandName Invoke-DeviceParseWorker -MockWith {}

        ParserRunspaceModule\Invoke-DeviceParsingJobs -DeviceFiles @('C:\logs\single.log') -ModulesPath 'C:\modules' -ArchiveRoot 'C:\archives' -DatabasePath 'C:\db.accdb' -MaxThreads 1

        Assert-MockCalled -ModuleName ParserRunspaceModule -CommandName Invoke-DeviceParseWorker -ParameterFilter { $FilePath -eq 'C:\logs\single.log' -and $SiteKey -eq 'single' } -Times 1
    }

    It "creates a preserved runspace pool even when MaxThreads is 1" {
        $stubProjectRoot = Join-Path $TestDrive 'PreservePoolProject'
        $stubModulesPath = Join-Path $stubProjectRoot 'Modules'
        $stubArchiveRoot = Join-Path $stubProjectRoot 'Archives'
        New-Item -ItemType Directory -Path $stubModulesPath -Force | Out-Null
        New-Item -ItemType Directory -Path $stubArchiveRoot -Force | Out-Null

        $callLogPath = Join-Path $stubArchiveRoot 'StubWorkerCalls.txt'
        $stubModulePath = Join-Path $stubModulesPath 'ParserRunspaceModule.psm1'
        Set-Content -LiteralPath $stubModulePath -Encoding UTF8 -Value @'
function Invoke-DeviceParseWorker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string]$ModulesPath,
        [Parameter(Mandatory=$true)][string]$ArchiveRoot,
        [string]$DatabasePath,
        [string]$SiteKey,
        [bool]$EnableVerbose = $false
    )

    try {
        Add-Content -LiteralPath (Join-Path $ArchiveRoot 'StubWorkerCalls.txt') -Value $FilePath -Encoding UTF8
    } catch { }
}

Export-ModuleMember -Function Invoke-DeviceParseWorker
'@

        InModuleScope -ModuleName ParserRunspaceModule {
            Reset-DeviceParseRunspacePool
            $script:PreservedRunspacePool | Should Be $null
        }

        ParserRunspaceModule\Invoke-DeviceParsingJobs -DeviceFiles @('C:\logs\preserved.log') -ModulesPath $stubModulesPath -ArchiveRoot $stubArchiveRoot -PreserveRunspacePool

        (Test-Path -LiteralPath $callLogPath) | Should Be $true
        $calls = @(Get-Content -LiteralPath $callLogPath)
        $calls.Count | Should Be 1
        $calls[0] | Should Be 'C:\logs\preserved.log'

        InModuleScope -ModuleName ParserRunspaceModule {
            $script:PreservedRunspacePool | Should Not Be $null
            ('' + $script:PreservedRunspacePool.RunspacePoolStateInfo.State) | Should Be 'Opened'
            Reset-DeviceParseRunspacePool
        }
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

    Context "Active worker management" {
        It "cleans up completed workers without ArgumentException" {
            InModuleScope -ModuleName ParserRunspaceModule {
                $active = [System.Collections.Generic.List[object]]::new()
                $pipe = [pscustomobject]@{}
                Add-Member -InputObject $pipe -MemberType ScriptMethod -Name EndInvoke -Value { param($async) } | Out-Null
                Add-Member -InputObject $pipe -MemberType ScriptMethod -Name Dispose -Value { } | Out-Null
                $async = [pscustomobject]@{ IsCompleted = $true }
                $entry = [pscustomobject]@{ Pipe = $pipe; AsyncResult = $async; Site = 'SITE' }
                $active.Add($entry) | Out-Null

                { foreach ($worker in $active.ToArray()) {
                        if ($worker.AsyncResult.IsCompleted) {
                            $worker.Pipe.EndInvoke($worker.AsyncResult)
                            $worker.Pipe.Dispose()
                        }
                    }
                } | Should Not Throw
            }
        }
    }

    Context "Auto-scale profile reuse" {
        It "wraps ParserWorker auto-scale profile lookup" {
            Mock -ModuleName ParserRunspaceModule -CommandName 'Get-AutoScaleConcurrencyProfile' -MockWith {
                return [pscustomobject]@{
                    ThreadCeiling     = 5
                    MaxWorkersPerSite = 2
                    MaxActiveSites    = 3
                    JobsPerThread     = 4
                    MinRunspaces      = 2
                }
            }

            InModuleScope -ModuleName ParserRunspaceModule {
                $result = Get-ParserAutoScaleProfile -DeviceFiles @('dev1.log','dev2.log') -CpuCount 4
                $result | Should Not Be $null
                $result.ThreadCeiling | Should Be 5
                $result.MaxWorkersPerSite | Should Be 2
                $result.MaxActiveSites | Should Be 3
                $result.JobsPerThread | Should Be 4
                $result.MinRunspaces | Should Be 2
            }

            Assert-MockCalled -ModuleName ParserRunspaceModule -CommandName 'Get-AutoScaleConcurrencyProfile' -Times 1
        }

        It "applies auto-scale profile when requested" {
            Mock -ModuleName ParserRunspaceModule -CommandName Initialize-SchedulerMetricsContext -MockWith {
                param(
                    [string]$ModulesPath,
                    [int]$DeviceCount,
                    [int]$MaxThreads,
                    [int]$MaxWorkersPerSite,
                    [int]$MaxActiveSites,
                    [int]$MinThreads,
                    [int]$JobsPerThread,
                    [int]$CpuCount,
                    [switch]$AdaptiveThreads,
                    [int]$MinIntervalSeconds
                )
                return [pscustomobject]@{
                    FilePath         = ''
                    Buffer           = [System.Collections.Generic.List[object]]::new()
                    TotalDevices     = $DeviceCount
                    MaxThreads       = $MaxThreads
                    MaxWorkersPerSite= $MaxWorkersPerSite
                    MaxActiveSites   = $MaxActiveSites
                    MinThreads       = $MinThreads
                    JobsPerThread    = $JobsPerThread
                    AdaptiveEnabled  = $AdaptiveThreads.IsPresent
                    CpuCount         = $CpuCount
                    CurrentThreadBudget = $null
                    LastSnapshot     = $null
                    LastSnapshotTime = [DateTime]::MinValue
                }
            }
            Mock -ModuleName ParserRunspaceModule -CommandName 'Get-AutoScaleConcurrencyProfile' -MockWith {
                return [pscustomobject]@{
                    ThreadCeiling     = 3
                    MaxWorkersPerSite = 2
                    MaxActiveSites    = 2
                    JobsPerThread     = 4
                    MinRunspaces      = 2
                }
            }
            Mock -ModuleName ParserRunspaceModule -CommandName Invoke-DeviceParseWorker -MockWith {}
            Mock -ModuleName ParserRunspaceModule -CommandName Publish-SchedulerLaunchTelemetry -MockWith {}

            ParserRunspaceModule\Invoke-DeviceParsingJobs -DeviceFiles @('C:\logs\a.log') -ModulesPath 'C:\modules' -ArchiveRoot 'C:\archives' -UseAutoScaleProfile

            Assert-MockCalled -ModuleName ParserRunspaceModule -CommandName Initialize-SchedulerMetricsContext -ParameterFilter {
                $MaxThreads -eq 3 -and $MaxWorkersPerSite -eq 2 -and $MaxActiveSites -eq 2 -and $MinThreads -eq 2 -and $JobsPerThread -eq 4
            } -Times 1
        }

        It "defaults to auto-scale when no concurrency hints are provided" {
            Mock -ModuleName ParserRunspaceModule -CommandName Initialize-SchedulerMetricsContext -MockWith {
                param(
                    [string]$ModulesPath,
                    [int]$DeviceCount,
                    [int]$MaxThreads,
                    [int]$MaxWorkersPerSite,
                    [int]$MaxActiveSites,
                    [int]$MinThreads,
                    [int]$JobsPerThread,
                    [int]$CpuCount,
                    [switch]$AdaptiveThreads,
                    [int]$MinIntervalSeconds
                )
                return [pscustomobject]@{
                    FilePath         = ''
                    Buffer           = [System.Collections.Generic.List[object]]::new()
                    TotalDevices     = $DeviceCount
                    MaxThreads       = $MaxThreads
                    MaxWorkersPerSite= $MaxWorkersPerSite
                    MaxActiveSites   = $MaxActiveSites
                    MinThreads       = $MinThreads
                    JobsPerThread    = $JobsPerThread
                    AdaptiveEnabled  = $AdaptiveThreads.IsPresent
                    CpuCount         = $CpuCount
                    CurrentThreadBudget = $null
                    LastSnapshot     = $null
                    LastSnapshotTime = [DateTime]::MinValue
                }
            }
            Mock -ModuleName ParserRunspaceModule -CommandName 'Get-AutoScaleConcurrencyProfile' -MockWith {
                return [pscustomobject]@{
                    ThreadCeiling     = 6
                    MaxWorkersPerSite = 3
                    MaxActiveSites    = 2
                    JobsPerThread     = 5
                    MinRunspaces      = 2
                }
            }
            Mock -ModuleName ParserRunspaceModule -CommandName Invoke-DeviceParseWorker -MockWith {}
            Mock -ModuleName ParserRunspaceModule -CommandName Publish-SchedulerLaunchTelemetry -MockWith {}

            ParserRunspaceModule\Invoke-DeviceParsingJobs -DeviceFiles @('C:\logs\a.log') -ModulesPath 'C:\modules' -ArchiveRoot 'C:\archives'

            Assert-MockCalled -ModuleName ParserRunspaceModule -CommandName Initialize-SchedulerMetricsContext -ParameterFilter {
                $MaxThreads -eq 6 -and $MaxWorkersPerSite -eq 3 -and $MaxActiveSites -eq 2 -and $MinThreads -eq 2 -and $JobsPerThread -eq 5
            } -Times 1
            Assert-MockCalled -ModuleName ParserRunspaceModule -CommandName 'Get-AutoScaleConcurrencyProfile' -Times 1
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

        It "caps the budget by active site and worker limits" {
            InModuleScope -ModuleName ParserRunspaceModule {
                $budget = Get-AdaptiveThreadBudget -ActiveWorkers 0 -QueuedJobs 8 -CpuCount 8 -MinThreads 1 -MaxThreads 6 -JobsPerThread 2 -MaxWorkersPerSite 1 -MaxActiveSites 1
                $budget | Should Be 1
            }
        }

        It "treats MaxActiveSites=0 as uncapped across sites" {
            InModuleScope -ModuleName ParserRunspaceModule {
                $budget = Get-AdaptiveThreadBudget -ActiveWorkers 0 -QueuedJobs 2 -SiteCount 2 -CpuCount 8 -MinThreads 1 -MaxThreads 2 -JobsPerThread 1 -MaxWorkersPerSite 1 -MaxActiveSites 0
                $budget | Should Be 2
            }
        }

        It "honors the ceiling" {
            InModuleScope -ModuleName ParserRunspaceModule {
                $budget = Get-AdaptiveThreadBudget -ActiveWorkers 1 -QueuedJobs 50 -CpuCount 2 -MinThreads 1 -MaxThreads 4 -JobsPerThread 1
                $budget | Should Be 4
            }
        }
    }

   Context "Site rotation scheduling" {
        It "rotates between sites while work remains" {
            InModuleScope -ModuleName ParserRunspaceModule {
                $queues = [ordered]@{}
                $queueA = [System.Collections.Generic.Queue[string]]::new()
                $queueA.Enqueue('A1')
                $queueA.Enqueue('A2')
                $queueB = [System.Collections.Generic.Queue[string]]::new()
                $queueB.Enqueue('B1')
                $queueB.Enqueue('B2')
                $queues['A'] = $queueA
                $queues['B'] = $queueB

                $rotation = [System.Collections.Generic.Queue[string]]::new()
                $rotation.Enqueue('A')
                $rotation.Enqueue('B')

                $activeEntries = [System.Collections.Generic.List[object]]::new()
                $activeSites = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

                $first = Get-NextSiteQueueJob -SiteQueues $queues -RotationQueue $rotation -ActiveEntries $activeEntries -ActiveSiteSet $activeSites -MaxWorkersPerSite 1 -MaxActiveSites 0
                $first.Site | Should Be 'A'
                $second = Get-NextSiteQueueJob -SiteQueues $queues -RotationQueue $rotation -ActiveEntries $activeEntries -ActiveSiteSet $activeSites -MaxWorkersPerSite 1 -MaxActiveSites 0
                $second.Site | Should Be 'B'
                $third = Get-NextSiteQueueJob -SiteQueues $queues -RotationQueue $rotation -ActiveEntries $activeEntries -ActiveSiteSet $activeSites -MaxWorkersPerSite 1 -MaxActiveSites 0
                $third.Site | Should Be 'A'
            }
        }

        It "respects worker limits but preserves rotation order" {
            InModuleScope -ModuleName ParserRunspaceModule {
                $queues = [ordered]@{}
                $queueA = [System.Collections.Generic.Queue[string]]::new()
                $queueA.Enqueue('A1')
                $queues['A'] = $queueA
                $queueB = [System.Collections.Generic.Queue[string]]::new()
                $queueB.Enqueue('B1')
                $queues['B'] = $queueB

                $rotation = [System.Collections.Generic.Queue[string]]::new()
                $rotation.Enqueue('A')
                $rotation.Enqueue('B')

                $activeEntries = [System.Collections.Generic.List[object]]::new()
                $activeSites = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
                [void]$activeEntries.Add([pscustomobject]@{ Site = 'A' })
                $null = $activeSites.Add('A')

                $blocked = Get-NextSiteQueueJob -SiteQueues $queues -RotationQueue $rotation -ActiveEntries $activeEntries -ActiveSiteSet $activeSites -MaxWorkersPerSite 1 -MaxActiveSites 1
                $blocked | Should Be $null

                $activeEntries.Clear()
                $activeSites.Clear()

                $next = Get-NextSiteQueueJob -SiteQueues $queues -RotationQueue $rotation -ActiveEntries $activeEntries -ActiveSiteSet $activeSites -MaxWorkersPerSite 1 -MaxActiveSites 1
                $next.Site | Should Be 'B'
            }
        }

        It "skips sites that exceed the consecutive launch limit when alternates exist" {
            InModuleScope -ModuleName ParserRunspaceModule {
                $queues = [ordered]@{}
                $queueA = [System.Collections.Generic.Queue[string]]::new()
                $queueA.Enqueue('A1')
                $queues['A'] = $queueA
                $queueB = [System.Collections.Generic.Queue[string]]::new()
                $queueB.Enqueue('B1')
                $queues['B'] = $queueB

                $rotation = [System.Collections.Generic.Queue[string]]::new()
                $rotation.Enqueue('A')
                $rotation.Enqueue('B')

                $activeEntries = [System.Collections.Generic.List[object]]::new()
                $activeSites = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

                $next = Get-NextSiteQueueJob -SiteQueues $queues -RotationQueue $rotation -ActiveEntries $activeEntries -ActiveSiteSet $activeSites -MaxWorkersPerSite 1 -MaxActiveSites 1 -LastLaunchedSite 'A' -LastSiteConsecutive 3 -MaxConsecutivePerSite 3
                $next.Site | Should Be 'B'
            }
        }

        It "falls back to the same site when it is the only remaining option" {
            InModuleScope -ModuleName ParserRunspaceModule {
                $queues = [ordered]@{}
                $queueA = [System.Collections.Generic.Queue[string]]::new()
                $queueA.Enqueue('A1')
                $queues['A'] = $queueA

                $rotation = [System.Collections.Generic.Queue[string]]::new()
                $rotation.Enqueue('A')

                $activeEntries = [System.Collections.Generic.List[object]]::new()
                $activeSites = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

                $next = Get-NextSiteQueueJob -SiteQueues $queues -RotationQueue $rotation -ActiveEntries $activeEntries -ActiveSiteSet $activeSites -MaxWorkersPerSite 1 -MaxActiveSites 1 -LastLaunchedSite 'A' -LastSiteConsecutive 5 -MaxConsecutivePerSite 4
                $next.Site | Should Be 'A'
                $next.FairnessBypassUsed | Should Be $true
            }
        }
    }

    Context "Scheduler telemetry" {
        It "allows overriding the scheduler telemetry writer" {
            InModuleScope -ModuleName ParserRunspaceModule {
                $writer = {
                    param([string]$Name, $Payload)
                    Set-Variable -Scope Script -Name SchedulerTelemetryTestPayload -Value $Payload -Force
                }
                Set-SchedulerTelemetryWriter $writer
                $resolved = Get-Variable -Scope Script -Name SchedulerTelemetryWriter -ValueOnly
                $resolved | Should Be $writer
                { Publish-SchedulerLaunchTelemetry -Site 'WLLS' -ActiveWorkers 2 -ActiveSites 1 -ThreadBudget 4 -QueuedJobs 10 -QueuedSites 2 } | Should Not Throw
                Set-SchedulerTelemetryWriter
            }
        }

        It "swallows telemetry errors" {
            InModuleScope -ModuleName ParserRunspaceModule {
                Set-SchedulerTelemetryWriter { throw 'fail' }
                { Publish-SchedulerLaunchTelemetry -Site 'BOYO' -ActiveWorkers 1 -ActiveSites 1 -ThreadBudget 1 -QueuedJobs 0 -QueuedSites 0 } | Should Not Throw
                Set-SchedulerTelemetryWriter
            }
        }
    }
}
