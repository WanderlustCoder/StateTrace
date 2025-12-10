Set-StrictMode -Version Latest

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

Describe "ParserWorker auto-scaling" {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSCommandPath) "..\\ParserWorker.psm1"
        Import-Module (Resolve-Path $modulePath) -Force
    }

    AfterAll {
        Remove-Module ParserWorker -Force -ErrorAction SilentlyContinue
    }

    It "scales concurrency based on CPU and available logs" {
        InModuleScope -ModuleName ParserWorker {
            $files = @(
                'C:\\data\\WLLS-A01-AS-01.log',
                'C:\\data\\WLLS-A01-AS-11.log',
                'C:\\data\\WLLS-A02-AS-02.log',
                'C:\\data\\WLLS-A02-AS-12.log',
                'C:\\data\\WLLS-A03-AS-03.log',
                'C:\\data\\WLLS-A03-AS-13.log'
            )
            $profile = Get-AutoScaleConcurrencyProfile -DeviceFiles $files -CpuCount 8
            $profile.ThreadCeiling | Should Be 6
            $profile.MaxWorkersPerSite | Should Be 4
            $profile.MaxActiveSites | Should Be 1
            $profile.JobsPerThread | Should Be 1
            $profile.DeviceCount | Should Be 6
            $profile.SiteCount | Should Be 1
            $profile.MinRunspaces | Should BeGreaterThan 0
        }
    }

    It "respects explicit caps when auto scaling" {
        InModuleScope -ModuleName ParserWorker {
            $files = foreach ($i in 1..20) {
                $suffix = ('{0:D2}' -f $i)
                if ($i % 2 -eq 0) {
                    "C:\\data\\SITEB-A05-AS-$suffix.log"
                } else {
                    "C:\\data\\SITEA-A05-AS-$suffix.log"
                }
            }
            $profile = Get-AutoScaleConcurrencyProfile -DeviceFiles $files -CpuCount 16 -ThreadCeiling 12 -MaxWorkersPerSite 2 -MaxActiveSites 0 -JobsPerThread 3 -MinRunspaces 2
            $profile.ThreadCeiling | Should Be 12
            $profile.MaxWorkersPerSite | Should Be 2
            $profile.MaxActiveSites | Should Be 0
            $profile.JobsPerThread | Should Be 3
            $profile.DeviceCount | Should Be 20
            $profile.SiteCount | Should Be 2
            $profile.MinRunspaces | Should Be 2
        }
    }

    It "summarizes device and site counts" {
        InModuleScope -ModuleName ParserWorker {
            $stats = Get-DeviceLogSetStatistics -DeviceFiles @('C:\logs\ALPHA-A01-01.log','C:\logs\BETA-A02-01.log','C:\logs\BETA-A02-02.log')
            $stats.DeviceCount | Should Be 3
            $stats.SiteCount | Should Be 2
        }
    }

    It "hydrates site existing row cache snapshots and primes device repository caches" {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $parserModulePath = Join-Path $repoRoot 'Modules\ParserPersistenceModule.psm1'
        $repoModulePath = Join-Path $repoRoot 'Modules\DeviceRepositoryModule.psm1'
        Import-Module (Resolve-Path $parserModulePath) -Force
        Import-Module (Resolve-Path $repoModulePath) -Force
        InModuleScope -ModuleName ParserWorker {
            $snapshot = @(
                [pscustomobject]@{
                    Site     = 'WLLS'
                    Hostname = 'WLLS-A01-AS-01'
                    Rows     = @{ 'Gi1/0/1' = @{ Signature = 'sig-a' } }
                },
                [pscustomobject]@{
                    Site     = 'BOYO'
                    Hostname = 'BOYO-A05-AS-02'
                    Rows     = @{ 'Gi1/0/2' = @{ Signature = 'sig-b' } }
                }
            )
            $path = Join-Path $TestDrive 'SiteExistingRowCacheSnapshot-test.clixml'
            $snapshot | Export-Clixml -Path $path

            $script:hydrated = @()
            $script:primedHosts = @()
            Mock -ModuleName ParserWorker -CommandName 'ParserPersistenceModule\Set-SiteExistingRowCacheSnapshot' -MockWith {
                param($Snapshot)
                $script:hydrated = @($Snapshot)
            }
            Mock -ModuleName ParserWorker -CommandName 'DeviceRepositoryModule\Set-InterfaceSiteCacheHost' -MockWith {
                param($Site, $Hostname, $RowsByPort)
                $script:primedHosts += [pscustomobject]@{
                    Site = $Site
                    Host = $Hostname
                    RowCount = if ($RowsByPort) { $RowsByPort.Count } else { 0 }
                }
            }

            $summary = Initialize-SiteExistingRowCacheSnapshot -SnapshotPath $path -PrimeDeviceRepository
            $summary | Should Not BeNullOrEmpty
            $summary.EntryCount | Should Be 2
            $summary.SnapshotPath | Should Be $path
            $summary.SiteSummaries.Length | Should Be 2
            ($summary.SiteSummaries | Where-Object { $_.Site -eq 'WLLS' }).HostCount | Should Be 1
            $script:hydrated.Count | Should Be 2
            $script:primedHosts.Count | Should Be 2
            ($script:primedHosts | Where-Object { $_.Site -eq 'BOYO' }).RowCount | Should Be 1
        }
        Remove-Module ParserPersistenceModule -ErrorAction SilentlyContinue
        Remove-Module DeviceRepositoryModule -ErrorAction SilentlyContinue
    }

    It "emits telemetry for concurrency decisions" {
        InModuleScope -ModuleName ParserWorker {
            $projectRoot = (Get-Location).ProviderPath
            $extractedPath = Join-Path $projectRoot 'Logs\Extracted'
            New-Item -ItemType Directory -Path $extractedPath -Force | Out-Null
            Get-ChildItem -Path $extractedPath -File -ErrorAction SilentlyContinue | Remove-Item -Force
            $fileNames = @('TESTA-A01-AS-01.log','TESTA-A01-AS-02.log','TESTB-A02-AS-01.log','_unknown.log')
            $fileInfos = @()
            foreach ($name in $fileNames) {
                $full = Join-Path $extractedPath $name
                Set-Content -Path $full -Value '' -Encoding ASCII
                $fileInfos += Get-Item -LiteralPath $full
            }
            $unknownFullPath = Join-Path $extractedPath '_unknown.log'
            Import-Module (Join-Path $projectRoot 'Modules\LogIngestionModule.psm1') -Force
            Import-Module (Join-Path $projectRoot 'Modules\ParserRunspaceModule.psm1') -Force
            Import-Module (Join-Path $projectRoot 'Modules\TelemetryModule.psm1') -Force

            $splitCommand = Get-Command -Name Split-RawLogs -Module LogIngestionModule
            $invokeCommand = Get-Command -Name Invoke-DeviceParsingJobs -Module ParserRunspaceModule
            $clearCommand = Get-Command -Name Clear-ExtractedLogs -Module LogIngestionModule

            $script:capturedCalls = @()
            $script:telemetryEvents = @()
            $existingTelemetry = Get-Command -Name Write-StTelemetryEvent -Module TelemetryModule -ErrorAction SilentlyContinue
            $originalTelemetry = $null
            if ($existingTelemetry) { $originalTelemetry = $existingTelemetry.ScriptBlock }

            try {
                $script:lastChunkSize = $null
                $originalChunkSetter = Get-Command -Name Set-InterfaceBulkChunkSize -Module ParserPersistenceModule -ErrorAction SilentlyContinue
                Mock Get-Content -ModuleName ParserWorker -ParameterFilter { $LiteralPath -eq $settingsPath -and $Raw } { $customSettings }
                Set-Item -Path Function:LogIngestionModule\Split-RawLogs -Value { param($LogPath, $ExtractedPath) }
                Set-Item -Path Function:ParserRunspaceModule\Invoke-DeviceParsingJobs -Value {
                    param(
                        [string[]]$DeviceFiles,
                        [string]$ModulesPath,
                        [string]$ArchiveRoot,
                        [string]$DatabasePath,
                        [int]$MaxThreads,
                        [int]$MinThreads,
                        [int]$JobsPerThread,
                        [int]$MaxWorkersPerSite,
                        [int]$MaxActiveSites,
                        [int]$MaxConsecutiveSiteLaunches,
                        [switch]$AdaptiveThreads,
                        [switch]$Synchronous,
                        [switch]$UseAutoScaleProfile
                    )
                    $script:capturedCalls += [PSCustomObject]@{
                        DeviceFiles       = $DeviceFiles
                        MaxThreads        = $MaxThreads
                        MinThreads        = $MinThreads
                        JobsPerThread     = $JobsPerThread
                        MaxWorkersPerSite = $MaxWorkersPerSite
                        MaxActiveSites    = $MaxActiveSites
                        MaxConsecutiveSiteLaunches = $MaxConsecutiveSiteLaunches
                        UseAutoScaleProfile = $UseAutoScaleProfile.IsPresent
                    }
                }
                Set-Item -Path Function:LogIngestionModule\Clear-ExtractedLogs -Value { param($ExtractedPath) }
                Set-Item -Path Function:TelemetryModule\Write-StTelemetryEvent -Value { param($Name, $Payload) $script:telemetryEvents += [PSCustomObject]@{ Name = $Name; Payload = $Payload } }
                Set-Item -Path Function:ParserPersistenceModule\Set-InterfaceBulkChunkSize -Value { param([int]$ChunkSize, [switch]$Reset) if ($Reset) { $script:lastChunkSize = 24; return 24 } else { $script:lastChunkSize = $ChunkSize; return $ChunkSize } }

                Invoke-StateTraceParsing -Synchronous

                $capturedCall = $script:capturedCalls | Select-Object -Last 1
                $capturedCall | Should Not Be $null
                $capturedCall.DeviceFiles.Count | Should Be 3
                ($capturedCall.DeviceFiles -contains $unknownFullPath) | Should Be $false
                $capturedCall.MaxConsecutiveSiteLaunches | Should Be 8
                $capturedCall.UseAutoScaleProfile | Should Be $true

                $event = $script:telemetryEvents | Where-Object { $_.Name -eq 'ConcurrencyProfileResolved' } | Select-Object -Last 1
                $event | Should Not Be $null
                $event.Payload.DeviceCount | Should Be 3
                $event.Payload.SiteCount | Should Be 2
                $event.Payload.AutoScaleProfileRequested | Should Be $true
                $event.Payload.AutoScaleProfileDisabled | Should Be $false
                $script:lastChunkSize | Should Be 24
                $event.Payload.InterfaceBulkChunkSize | Should Be 24
                $event.Payload.HintInterfaceBulkChunkSize | Should BeNullOrEmpty
            } finally {
                foreach ($info in $fileInfos) {
                    Remove-Item -LiteralPath $info.FullName -ErrorAction SilentlyContinue
                }
                if ($splitCommand) { Set-Item -Path Function:LogIngestionModule\Split-RawLogs -Value $splitCommand.ScriptBlock }
                if ($invokeCommand) { Set-Item -Path Function:ParserRunspaceModule\Invoke-DeviceParsingJobs -Value $invokeCommand.ScriptBlock }
                if ($clearCommand) { Set-Item -Path Function:LogIngestionModule\Clear-ExtractedLogs -Value $clearCommand.ScriptBlock }
                if ($originalChunkSetter) {
                    Set-Item -Path Function:ParserPersistenceModule\Set-InterfaceBulkChunkSize -Value $originalChunkSetter.ScriptBlock
                } else {
                    Remove-Item Function:ParserPersistenceModule\Set-InterfaceBulkChunkSize -ErrorAction SilentlyContinue
                }
                if ($originalTelemetry) {
                    Set-Item -Path Function:TelemetryModule\Write-StTelemetryEvent -Value $originalTelemetry
                } else {
                    Remove-Item Function:TelemetryModule\Write-StTelemetryEvent -ErrorAction SilentlyContinue
                }
            }
        }
    }

    It "applies InterfaceBulkChunkSize from settings" {
        InModuleScope -ModuleName ParserWorker {
            $projectRoot = (Get-Location).ProviderPath
            $extractedPath = Join-Path $projectRoot 'Logs\Extracted'
            New-Item -ItemType Directory -Path $extractedPath -Force | Out-Null
            Get-ChildItem -Path $extractedPath -File -ErrorAction SilentlyContinue | Remove-Item -Force
            $fileNames = @('ALPHA-A01-AS-01.log','ALPHA-A01-AS-02.log')
            $fileInfos = @()
            foreach ($name in $fileNames) {
                $full = Join-Path $extractedPath $name
                Set-Content -Path $full -Value '' -Encoding ASCII
                $fileInfos += Get-Item -LiteralPath $full
            }
            Import-Module (Join-Path $projectRoot 'Modules\LogIngestionModule.psm1') -Force
            Import-Module (Join-Path $projectRoot 'Modules\ParserRunspaceModule.psm1') -Force
            Import-Module (Join-Path $projectRoot 'Modules\TelemetryModule.psm1') -Force

            $splitCommand = Get-Command -Name Split-RawLogs -Module LogIngestionModule
            $invokeCommand = Get-Command -Name Invoke-DeviceParsingJobs -Module ParserRunspaceModule
            $clearCommand = Get-Command -Name Clear-ExtractedLogs -Module LogIngestionModule

            $settingsPath = Join-Path $projectRoot 'Data\StateTraceSettings.json'
            $customSettings = '{"ParserSettings":{"AutoScaleConcurrency":true,"InterfaceBulkChunkSize":12}}'

            $script:capturedCalls = @()
            $script:telemetryEvents = @()
            $existingTelemetry = Get-Command -Name Write-StTelemetryEvent -Module TelemetryModule -ErrorAction SilentlyContinue
            $originalTelemetry = $null
            if ($existingTelemetry) { $originalTelemetry = $existingTelemetry.ScriptBlock }

            try {
                $script:lastChunkSize = $null
                $originalChunkSetter = Get-Command -Name Set-InterfaceBulkChunkSize -Module ParserPersistenceModule -ErrorAction SilentlyContinue
                Set-Item -Path Function:LogIngestionModule\Split-RawLogs -Value { param($LogPath, $ExtractedPath) }
                Set-Item -Path Function:ParserRunspaceModule\Invoke-DeviceParsingJobs -Value {
                    param(
                        [string[]]$DeviceFiles,
                        [string]$ModulesPath,
                        [string]$ArchiveRoot,
                        [string]$DatabasePath,
                        [int]$MaxThreads,
                        [int]$MinThreads,
                        [int]$JobsPerThread,
                        [int]$MaxWorkersPerSite,
                        [int]$MaxActiveSites,
                        [int]$MaxConsecutiveSiteLaunches,
                        [switch]$AdaptiveThreads,
                        [switch]$Synchronous,
                        [switch]$UseAutoScaleProfile
                    )
                    $script:capturedCalls += [PSCustomObject]@{
                        DeviceFiles       = $DeviceFiles
                        MaxThreads        = $MaxThreads
                        MinThreads        = $MinThreads
                        JobsPerThread     = $JobsPerThread
                        MaxWorkersPerSite = $MaxWorkersPerSite
                        MaxActiveSites    = $MaxActiveSites
                        MaxConsecutiveSiteLaunches = $MaxConsecutiveSiteLaunches
                        UseAutoScaleProfile = $UseAutoScaleProfile.IsPresent
                    }
                }
                Set-Item -Path Function:LogIngestionModule\Clear-ExtractedLogs -Value { param($ExtractedPath) }
                Set-Item -Path Function:TelemetryModule\Write-StTelemetryEvent -Value { param($Name, $Payload) $script:telemetryEvents += [PSCustomObject]@{ Name = $Name; Payload = $Payload } }
                Set-Item -Path Function:ParserPersistenceModule\Set-InterfaceBulkChunkSize -Value { param([int]$ChunkSize, [switch]$Reset) if ($Reset) { $script:lastChunkSize = 24; return 24 } else { $script:lastChunkSize = $ChunkSize; return $ChunkSize } }

                Invoke-StateTraceParsing -Synchronous

                $capturedCall = $script:capturedCalls | Select-Object -Last 1
                $capturedCall | Should Not Be $null
                $capturedCall.UseAutoScaleProfile | Should Be $true

                $event = $script:telemetryEvents | Where-Object { $_.Name -eq 'ConcurrencyProfileResolved' } | Select-Object -Last 1
                $event | Should Not Be $null
                $event.Payload.AutoScaleRequested | Should Be $true
                $event.Payload.AutoScaleEnabled | Should Be $true
                $event.Payload.AutoScaleProfileRequested | Should Be $true
                $event.Payload.AutoScaleProfileDisabled | Should Be $false
                $script:lastChunkSize | Should Be 12
                $event.Payload.InterfaceBulkChunkSize | Should Be 12
                $event.Payload.HintInterfaceBulkChunkSize | Should Be '12'
            } finally {
                foreach ($info in $fileInfos) {
                    Remove-Item -LiteralPath $info.FullName -ErrorAction SilentlyContinue
                }
                if ($splitCommand) { Set-Item -Path Function:LogIngestionModule\Split-RawLogs -Value $splitCommand.ScriptBlock }
                if ($invokeCommand) { Set-Item -Path Function:ParserRunspaceModule\Invoke-DeviceParsingJobs -Value $invokeCommand.ScriptBlock }
                if ($clearCommand) { Set-Item -Path Function:LogIngestionModule\Clear-ExtractedLogs -Value $clearCommand.ScriptBlock }
                if ($originalChunkSetter) {
                    Set-Item -Path Function:ParserPersistenceModule\Set-InterfaceBulkChunkSize -Value $originalChunkSetter.ScriptBlock
                } else {
                    Remove-Item Function:ParserPersistenceModule\Set-InterfaceBulkChunkSize -ErrorAction SilentlyContinue
                }
                if ($originalTelemetry) {
                    Set-Item -Path Function:TelemetryModule\Write-StTelemetryEvent -Value $originalTelemetry
                } else {
                    Remove-Item Function:TelemetryModule\Write-StTelemetryEvent -ErrorAction SilentlyContinue
                }
            }
        }

    }



    It "disables auto-scale profile when requested" {
        InModuleScope -ModuleName ParserWorker {
            $projectRoot = (Get-Location).ProviderPath
            $extractedPath = Join-Path $projectRoot 'Logs\Extracted'
            New-Item -ItemType Directory -Path $extractedPath -Force | Out-Null
            Get-ChildItem -Path $extractedPath -File -ErrorAction SilentlyContinue | Remove-Item -Force
            $fileNames = @('DELTA-A01-AS-01.log','DELTA-A01-AS-02.log')
            $fileInfos = @()
            foreach ($name in $fileNames) {
                $full = Join-Path $extractedPath $name
                Set-Content -Path $full -Value '' -Encoding ASCII
                $fileInfos += Get-Item -LiteralPath $full
            }
            Import-Module (Join-Path $projectRoot 'Modules\LogIngestionModule.psm1') -Force
            Import-Module (Join-Path $projectRoot 'Modules\ParserRunspaceModule.psm1') -Force
            Import-Module (Join-Path $projectRoot 'Modules\TelemetryModule.psm1') -Force

            $splitCommand = Get-Command -Name Split-RawLogs -Module LogIngestionModule
            $invokeCommand = Get-Command -Name Invoke-DeviceParsingJobs -Module ParserRunspaceModule
            $clearCommand = Get-Command -Name Clear-ExtractedLogs -Module LogIngestionModule

            $script:capturedCalls = @()
            $script:telemetryEvents = @()
            $existingTelemetry = Get-Command -Name Write-StTelemetryEvent -Module TelemetryModule -ErrorAction SilentlyContinue
            $originalTelemetry = $null
            if ($existingTelemetry) { $originalTelemetry = $existingTelemetry.ScriptBlock }

            try {
                Set-Item -Path Function:LogIngestionModule\Split-RawLogs -Value { param($LogPath, $ExtractedPath) }
                Set-Item -Path Function:ParserRunspaceModule\Invoke-DeviceParsingJobs -Value {
                    param(
                        [string[]]$DeviceFiles,
                        [string]$ModulesPath,
                        [string]$ArchiveRoot,
                        [string]$DatabasePath,
                        [int]$MaxThreads,
                        [int]$MinThreads,
                        [int]$JobsPerThread,
                        [int]$MaxWorkersPerSite,
                        [int]$MaxActiveSites,
                        [int]$MaxConsecutiveSiteLaunches,
                        [switch]$AdaptiveThreads,
                        [switch]$Synchronous,
                        [switch]$UseAutoScaleProfile
                    )
                    $script:capturedCalls += [PSCustomObject]@{
                        DeviceFiles       = $DeviceFiles
                        MaxThreads        = $MaxThreads
                        MinThreads        = $MinThreads
                        JobsPerThread     = $JobsPerThread
                        MaxWorkersPerSite = $MaxWorkersPerSite
                        MaxActiveSites    = $MaxActiveSites
                        MaxConsecutiveSiteLaunches = $MaxConsecutiveSiteLaunches
                        UseAutoScaleProfile = $UseAutoScaleProfile.IsPresent
                    }
                }
                Set-Item -Path Function:LogIngestionModule\Clear-ExtractedLogs -Value { param($ExtractedPath) }
                Set-Item -Path Function:TelemetryModule\Write-StTelemetryEvent -Value { param($Name, $Payload) $script:telemetryEvents += [PSCustomObject]@{ Name = $Name; Payload = $Payload } }

                Invoke-StateTraceParsing -Synchronous -DisableAutoScaleProfile

                $capturedCall = $script:capturedCalls | Select-Object -Last 1
                $capturedCall | Should Not Be $null
                $capturedCall.DeviceFiles.Count | Should Be 2
                $capturedCall.UseAutoScaleProfile | Should Be $false

                $event = $script:telemetryEvents | Where-Object { $_.Name -eq 'ConcurrencyProfileResolved' } | Select-Object -Last 1
                $event | Should Not Be $null
                $event.Payload.AutoScaleProfileRequested | Should Be $false
                $event.Payload.AutoScaleProfileDisabled | Should Be $true
            } finally {
                foreach ($info in $fileInfos) {
                    Remove-Item -LiteralPath $info.FullName -ErrorAction SilentlyContinue
                }
                if ($splitCommand) { Set-Item -Path Function:LogIngestionModule\Split-RawLogs -Value $splitCommand.ScriptBlock }
                if ($invokeCommand) { Set-Item -Path Function:ParserRunspaceModule\Invoke-DeviceParsingJobs -Value $invokeCommand.ScriptBlock }
                if ($clearCommand) { Set-Item -Path Function:LogIngestionModule\Clear-ExtractedLogs -Value $clearCommand.ScriptBlock }
                if ($originalTelemetry) {
                    Set-Item -Path Function:TelemetryModule\Write-StTelemetryEvent -Value $originalTelemetry
                } else {
                    Remove-Item Function:TelemetryModule\Write-StTelemetryEvent -ErrorAction SilentlyContinue
                }
            }
        }
    }




    It "honors manual concurrency overrides" {
        InModuleScope -ModuleName ParserWorker {
            $projectRoot = (Get-Location).ProviderPath
            $extractedPath = Join-Path $projectRoot 'Logs\Extracted'
            New-Item -ItemType Directory -Path $extractedPath -Force | Out-Null
            Get-ChildItem -Path $extractedPath -File -ErrorAction SilentlyContinue | Remove-Item -Force
            $fileNames = @('SITEA-A01-AS-01.log','SITEA-A01-AS-02.log','SITEA-A01-AS-03.log','SITEB-A02-AS-01.log','SITEB-A02-AS-02.log','SITEB-A02-AS-03.log')
            $fileInfos = @()
            foreach ($name in $fileNames) {
                $full = Join-Path $extractedPath $name
                Set-Content -Path $full -Value '' -Encoding ASCII
                $fileInfos += Get-Item -LiteralPath $full
            }
            Import-Module (Join-Path $projectRoot 'Modules\LogIngestionModule.psm1') -Force
            Import-Module (Join-Path $projectRoot 'Modules\ParserRunspaceModule.psm1') -Force
            Import-Module (Join-Path $projectRoot 'Modules\TelemetryModule.psm1') -Force

            $splitCommand = Get-Command -Name Split-RawLogs -Module LogIngestionModule
            $invokeCommand = Get-Command -Name Invoke-DeviceParsingJobs -Module ParserRunspaceModule
            $clearCommand = Get-Command -Name Clear-ExtractedLogs -Module LogIngestionModule

            $script:capturedCalls = @()
            $script:telemetryEvents = @()
            $existingTelemetry = Get-Command -Name Write-StTelemetryEvent -Module TelemetryModule -ErrorAction SilentlyContinue
            $originalTelemetry = $null
            if ($existingTelemetry) { $originalTelemetry = $existingTelemetry.ScriptBlock }

            try {
                Set-Item -Path Function:LogIngestionModule\Split-RawLogs -Value { param($LogPath, $ExtractedPath) }
                Set-Item -Path Function:ParserRunspaceModule\Invoke-DeviceParsingJobs -Value {
                    param(
                        [string[]]$DeviceFiles,
                        [string]$ModulesPath,
                        [string]$ArchiveRoot,
                        [string]$DatabasePath,
                        [int]$MaxThreads,
                        [int]$MinThreads,
                        [int]$JobsPerThread,
                        [int]$MaxWorkersPerSite,
                        [int]$MaxActiveSites,
                        [int]$MaxConsecutiveSiteLaunches,
                        [switch]$AdaptiveThreads,
                        [switch]$Synchronous,
                        [switch]$UseAutoScaleProfile
                    )
                    $script:capturedCalls += [PSCustomObject]@{
                        DeviceFiles       = $DeviceFiles
                        MaxThreads        = $MaxThreads
                        MinThreads        = $MinThreads
                        JobsPerThread     = $JobsPerThread
                        MaxWorkersPerSite = $MaxWorkersPerSite
                        MaxActiveSites    = $MaxActiveSites
                        MaxConsecutiveSiteLaunches = $MaxConsecutiveSiteLaunches
                        UseAutoScaleProfile = $UseAutoScaleProfile.IsPresent
                    }
                }
                Set-Item -Path Function:LogIngestionModule\Clear-ExtractedLogs -Value { param($ExtractedPath) }
                Set-Item -Path Function:TelemetryModule\Write-StTelemetryEvent -Value { param($Name, $Payload) $script:telemetryEvents += [PSCustomObject]@{ Name = $Name; Payload = $Payload } }

                Invoke-StateTraceParsing -Synchronous -ThreadCeilingOverride 4 -MaxWorkersPerSiteOverride 2 -MaxActiveSitesOverride 2 -MaxConsecutiveSiteLaunchesOverride 5 -JobsPerThreadOverride 1 -MinRunspacesOverride 2

                $capturedCall = $script:capturedCalls | Select-Object -Last 1
                $capturedCall | Should Not Be $null
                $capturedCall.DeviceFiles.Count | Should Be 6
                $capturedCall.MaxThreads | Should Be 4
                $capturedCall.MinThreads | Should Be 2
                $capturedCall.MaxWorkersPerSite | Should Be 2
                $capturedCall.MaxActiveSites | Should Be 2
                $capturedCall.JobsPerThread | Should Be 1
                $capturedCall.MaxConsecutiveSiteLaunches | Should Be 5
                $capturedCall.UseAutoScaleProfile | Should Be $false

                $event = $script:telemetryEvents | Where-Object { $_.Name -eq 'ConcurrencyProfileResolved' } | Select-Object -Last 1
                $event | Should Not Be $null
                $event.Payload.ManualOverrides | Should Be $true
                $event.Payload.ThreadCeiling | Should Be 4
                $event.Payload.OverrideMaxConsecutiveSiteLaunches | Should Be 5
                $event.Payload.ResolvedMaxConsecutiveSiteLaunches | Should Be 5
                $event.Payload.AutoScaleProfileRequested | Should Be $false
                $event.Payload.AutoScaleProfileDisabled | Should Be $false
            } finally {
                foreach ($info in $fileInfos) {
                    Remove-Item -LiteralPath $info.FullName -ErrorAction SilentlyContinue
                }
                if ($splitCommand) { Set-Item -Path Function:LogIngestionModule\Split-RawLogs -Value $splitCommand.ScriptBlock }
                if ($invokeCommand) { Set-Item -Path Function:ParserRunspaceModule\Invoke-DeviceParsingJobs -Value $invokeCommand.ScriptBlock }
                if ($clearCommand) { Set-Item -Path Function:LogIngestionModule\Clear-ExtractedLogs -Value $clearCommand.ScriptBlock }
                if ($originalChunkSetter) {
                    Set-Item -Path Function:ParserPersistenceModule\Set-InterfaceBulkChunkSize -Value $originalChunkSetter.ScriptBlock
                } else {
                    Remove-Item Function:ParserPersistenceModule\Set-InterfaceBulkChunkSize -ErrorAction SilentlyContinue
                }
                if ($originalTelemetry) {
                    Set-Item -Path Function:TelemetryModule\Write-StTelemetryEvent -Value $originalTelemetry
                } else {
                    Remove-Item Function:TelemetryModule\Write-StTelemetryEvent -ErrorAction SilentlyContinue
                }
            }
        }
    }

}

