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
                        [switch]$AdaptiveThreads,
                        [switch]$Synchronous
                    )
                    $script:capturedCalls += [PSCustomObject]@{
                        DeviceFiles       = $DeviceFiles
                        MaxThreads        = $MaxThreads
                        MinThreads        = $MinThreads
                        JobsPerThread     = $JobsPerThread
                        MaxWorkersPerSite = $MaxWorkersPerSite
                        MaxActiveSites    = $MaxActiveSites
                    }
                }
                Set-Item -Path Function:LogIngestionModule\Clear-ExtractedLogs -Value { param($ExtractedPath) }
                Set-Item -Path Function:TelemetryModule\Write-StTelemetryEvent -Value { param($Name, $Payload) $script:telemetryEvents += [PSCustomObject]@{ Name = $Name; Payload = $Payload } }

                Invoke-StateTraceParsing -Synchronous

                $capturedCall = $script:capturedCalls | Select-Object -Last 1
                $capturedCall | Should Not Be $null
                $capturedCall.DeviceFiles.Count | Should Be 3
                ($capturedCall.DeviceFiles -contains $unknownFullPath) | Should Be $false

                $event = $script:telemetryEvents | Where-Object { $_.Name -eq 'ConcurrencyProfileResolved' } | Select-Object -Last 1
                $event | Should Not Be $null
                $event.Payload.DeviceCount | Should Be 3
                $event.Payload.SiteCount | Should Be 2
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
                        [switch]$AdaptiveThreads,
                        [switch]$Synchronous
                    )
                    $script:capturedCalls += [PSCustomObject]@{
                        DeviceFiles       = $DeviceFiles
                        MaxThreads        = $MaxThreads
                        MinThreads        = $MinThreads
                        JobsPerThread     = $JobsPerThread
                        MaxWorkersPerSite = $MaxWorkersPerSite
                        MaxActiveSites    = $MaxActiveSites
                    }
                }
                Set-Item -Path Function:LogIngestionModule\Clear-ExtractedLogs -Value { param($ExtractedPath) }
                Set-Item -Path Function:TelemetryModule\Write-StTelemetryEvent -Value { param($Name, $Payload) $script:telemetryEvents += [PSCustomObject]@{ Name = $Name; Payload = $Payload } }

                Invoke-StateTraceParsing -Synchronous -ThreadCeilingOverride 4 -MaxWorkersPerSiteOverride 2 -MaxActiveSitesOverride 2 -JobsPerThreadOverride 1 -MinRunspacesOverride 2

                $capturedCall = $script:capturedCalls | Select-Object -Last 1
                $capturedCall | Should Not Be $null
                $capturedCall.DeviceFiles.Count | Should Be 6
                $capturedCall.MaxThreads | Should Be 4
                $capturedCall.MinThreads | Should Be 2
                $capturedCall.MaxWorkersPerSite | Should Be 2
                $capturedCall.MaxActiveSites | Should Be 2
                $capturedCall.JobsPerThread | Should Be 1

                $event = $script:telemetryEvents | Where-Object { $_.Name -eq 'ConcurrencyProfileResolved' } | Select-Object -Last 1
                $event | Should Not Be $null
                $event.Payload.ManualOverrides | Should Be $true
                $event.Payload.ThreadCeiling | Should Be 4
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

}

