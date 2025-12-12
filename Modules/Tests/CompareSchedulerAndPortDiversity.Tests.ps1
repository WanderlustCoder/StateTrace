Set-StrictMode -Version Latest

Describe 'Compare-SchedulerAndPortDiversity' {
    It 'handles empty SiteStreaks without throwing' {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath '..\..'))
        $scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Compare-SchedulerAndPortDiversity.ps1'

        $schedulerPath = Join-Path -Path $TestDrive -ChildPath ("ParserSchedulerLaunch-{0}.json" -f ([System.Guid]::NewGuid().ToString('N')))
        $portPath = Join-Path -Path $TestDrive -ChildPath ("PortBatchSiteDiversity-{0}.json" -f ([System.Guid]::NewGuid().ToString('N')))

        [pscustomobject]@{
            SiteSummaries = @(
                [pscustomobject]@{
                    Site = 'SITE1'
                    MaxConsecutive = 2
                }
            )
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $schedulerPath -Encoding utf8

        [pscustomobject]@{
            SiteStreaks = @()
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $portPath -Encoding utf8

        $summary = & $scriptPath -SchedulerReportPath $schedulerPath -PortDiversityReportPath $portPath

        $summary | Should Not BeNullOrEmpty
        $summary.MismatchCount | Should Be 0
        $summary.MaxSchedulerStreak | Should Be 2
        $summary.MaxPortBatchStreak | Should Be 0
    }

    It 'throws when SiteStreaks are missing from the port diversity report' {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath '..\..'))
        $scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Compare-SchedulerAndPortDiversity.ps1'

        $schedulerPath = Join-Path -Path $TestDrive -ChildPath ("ParserSchedulerLaunch-{0}.json" -f ([System.Guid]::NewGuid().ToString('N')))
        $portPath = Join-Path -Path $TestDrive -ChildPath ("PortBatchSiteDiversity-{0}.json" -f ([System.Guid]::NewGuid().ToString('N')))

        [pscustomobject]@{
            SiteSummaries = @(
                [pscustomobject]@{
                    Site = 'SITE1'
                    MaxConsecutive = 2
                }
            )
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $schedulerPath -Encoding utf8

        [pscustomobject]@{
            MetricsFile = 'dummy'
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $portPath -Encoding utf8

        $thrownMessage = $null
        try {
            & $scriptPath -SchedulerReportPath $schedulerPath -PortDiversityReportPath $portPath | Out-Null
        } catch {
            $thrownMessage = $_.Exception.Message
        }

        $thrownMessage | Should Not BeNullOrEmpty
        $thrownMessage | Should Match 'does not contain SiteStreaks'
    }
}
