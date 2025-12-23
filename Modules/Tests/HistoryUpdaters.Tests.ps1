Set-StrictMode -Version Latest

Describe 'Telemetry history updater scripts' {
    BeforeAll {
        $repoRoot = Split-Path -Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) -Parent
        $script:PortHistoryScript = Join-Path -Path $repoRoot -ChildPath 'Tools\Update-PortBatchHistory.ps1'
        $script:InterfaceHistoryScript = Join-Path -Path $repoRoot -ChildPath 'Tools\Update-InterfaceSyncHistory.ps1'
        $script:TempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("HistoryUpdaterTests-{0}" -f ([System.Guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:TempRoot) {
            Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'appends port batch reports without using deprecated ConvertFrom-Json depth' {
        $report = [pscustomobject]@{
            GeneratedAtUtc     = (Get-Date).ToUniversalTime().ToString('o')
            FilesAnalyzed      = 'dummy-metrics.json'
            PortBatchSummary   = [pscustomobject]@{
                EventCount        = 1
                UniqueHosts       = 1
                TotalPorts        = 10
                PortsPerMinute    = 60
                AveragePortsBatch = 10
                BatchIntervalMs   = [pscustomobject]@{ P95 = 123 }
            }
            InterfaceSyncSummary = [pscustomobject]@{
                UiClone        = [pscustomobject]@{ P95 = 10 }
                StreamDispatch = [pscustomobject]@{ P95 = 20 }
                DiffDuration   = [pscustomobject]@{ P95 = 30 }
            }
        }

        $reportPath = Join-Path -Path $script:TempRoot -ChildPath 'PortBatchReady.json'
        $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8
        $historyPath = Join-Path -Path $script:TempRoot -ChildPath 'PortBatchHistory.csv'

        $result = & $script:PortHistoryScript -ReportPaths $reportPath -HistoryPath $historyPath -PassThru
        @($result).Count | Should Be 1
        $history = Import-Csv -LiteralPath $historyPath
        @($history).Count | Should Be 1
        [int]$history[0].PortsPerMinute | Should Be 60
        [int]$history[0].BatchIntervalP95 | Should Be 123

        $second = & $script:PortHistoryScript -ReportPaths $reportPath -HistoryPath $historyPath -PassThru
        @($second).Count | Should Be 0
        @((Import-Csv -LiteralPath $historyPath)).Count | Should Be 1
    }

    It 'appends interface sync reports without using deprecated ConvertFrom-Json depth' {
        $report = [pscustomobject]@{
            GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            FilesAnalyzed  = @('metrics.json')
            EventCount     = 5
            GlobalStats    = [pscustomobject]@{
                UiClone        = [pscustomobject]@{ P95 = 15 }
                StreamDispatch = [pscustomobject]@{ P95 = 25 }
                DiffDuration   = [pscustomobject]@{ P95 = 35 }
                SiteCacheUpdate = [pscustomobject]@{ P95 = 45 }
            }
            SiteBreakdown = @(
                [pscustomobject]@{ Site = 'TEST1'; UiCloneP95 = 50 },
                [pscustomobject]@{ Site = 'TEST2'; UiCloneP95 = 40 }
            )
            HostBreakdownTop = @(
                [pscustomobject]@{ Host = 'TEST-HOST'; UiCloneP95 = 55 }
            )
        }

        $reportPath = Join-Path -Path $script:TempRoot -ChildPath 'InterfaceSyncTiming.json'
        $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8
        $historyPath = Join-Path -Path $script:TempRoot -ChildPath 'InterfaceSyncHistory.csv'

        $result = & $script:InterfaceHistoryScript -ReportPaths $reportPath -HistoryPath $historyPath -PassThru
        @($result).Count | Should Be 1
        $history = Import-Csv -LiteralPath $historyPath
        @($history).Count | Should Be 1
        [int]$history[0].UiCloneP95 | Should Be 15
        $history[0].HottestSite | Should Be 'TEST1'
        $history[0].HottestHost | Should Be 'TEST-HOST'

        $second = & $script:InterfaceHistoryScript -ReportPaths $reportPath -HistoryPath $historyPath -PassThru
        @($second).Count | Should Be 0
        @((Import-Csv -LiteralPath $historyPath)).Count | Should Be 1
}
}
