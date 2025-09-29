Set-StrictMode -Version Latest

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
            $profile.MinRunspaces | Should Be 2
        }
    }
}

