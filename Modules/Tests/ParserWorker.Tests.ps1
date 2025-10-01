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
            try {
                Mock -CommandName 'LogIngestionModule\Split-RawLogs' -ModuleName ParserWorker { }
                Mock -CommandName 'ParserRunspaceModule\Invoke-DeviceParsingJobs' -ModuleName ParserWorker -MockWith {
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
                }
                Mock -CommandName 'LogIngestionModule\Clear-ExtractedLogs' -ModuleName ParserWorker { }
                Mock -CommandName Get-ChildItem -ModuleName ParserWorker -MockWith { $fileInfos }
                $script:telemetryEvents = @()
                $originalTelemetry = $null
                $existingTelemetry = Get-Command -Name Write-StTelemetryEvent -Module TelemetryModule -ErrorAction SilentlyContinue
                if ($existingTelemetry) { $originalTelemetry = $existingTelemetry.ScriptBlock }
                Set-Item -Path Function:TelemetryModule\Write-StTelemetryEvent -Value { param($Name, $Payload) $script:telemetryEvents += [PSCustomObject]@{ Name = $Name; Payload = $Payload } }
                Invoke-StateTraceParsing -Synchronous
                Assert-MockCalled -CommandName 'ParserRunspaceModule\Invoke-DeviceParsingJobs' -ModuleName ParserWorker -Times 1 -ParameterFilter { $DeviceFiles.Count -eq 3 }
                Assert-MockCalled -CommandName 'ParserRunspaceModule\Invoke-DeviceParsingJobs' -ModuleName ParserWorker -Times 0 -ParameterFilter { $DeviceFiles -contains $unknownFullPath }
                $event = $script:telemetryEvents | Where-Object { $_.Name -eq 'ConcurrencyProfileResolved' } | Select-Object -Last 1
                $event | Should Not Be $null
                $event.Payload.DeviceCount | Should Be 3
                $event.Payload.SiteCount | Should Be 2
                $event.Payload.ThreadCeiling | Should BeGreaterThan 0
            } finally {
                foreach ($info in $fileInfos) {
                    Remove-Item -LiteralPath $info.FullName -ErrorAction SilentlyContinue
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

