Set-StrictMode -Version Latest

Describe 'Rollup-IngestionMetrics.ps1' {
    BeforeAll {
        $testMetricsDir = Join-Path -Path $TestDrive -ChildPath 'metrics'
        $null = New-Item -Path $testMetricsDir -ItemType Directory

        $sampleEvents = @(
            '{"EventName":"ParseDuration","DurationSeconds":1.5,"Success":true,"Site":"BOYO","Hostname":"BOYO-A01"}'
            '{"EventName":"ParseDuration","DurationSeconds":2.5,"Success":false,"Site":"WLLS","Hostname":"WLLS-A01"}'
            '{"EventName":"DatabaseWriteLatency","LatencyMs":300,"Site":"BOYO","Hostname":"BOYO-A01"}'
            '{"EventName":"DatabaseWriteLatency","LatencyMs":700,"Site":"WLLS","Hostname":"WLLS-A01"}'
            '{"EventName":"RowsWritten","Rows":96,"DeletedRows":0,"Site":"BOYO","Hostname":"BOYO-A01"}'
            '{"EventName":"RowsWritten","Rows":48,"DeletedRows":2,"Site":"WLLS","Hostname":"WLLS-A01"}'
            '{"EventName":"SkippedDuplicate","Site":"BOYO","Hostname":"BOYO-A01"}'
            '{"EventName":"SkippedDuplicate","Site":"WLLS","Hostname":"WLLS-A02"}'
            '{"EventName":"InterfaceSyncTiming","Site":"BOYO","Hostname":"BOYO-A01","SiteCacheFetchDurationMs":200.0,"SiteCacheFetchStatus":"Hydrated","SiteCacheProvider":"Refresh"}'
            '{"EventName":"InterfaceSyncTiming","Site":"WLLS","Hostname":"WLLS-A02","SiteCacheFetchDurationMs":0.0,"SiteCacheFetchStatus":"Hit","SiteCacheProvider":"Cache"}'
            # LANDMARK: Rollup ingestion metrics tests - diff telemetry fixtures
            '{"EventName":"DiffUsageRate","UsageNumerator":1,"UsageDenominator":1,"Status":"Executed","Site":"BOYO","Hostname":"BOYO-A01"}'
            '{"EventName":"DiffUsageRate","UsageNumerator":1,"UsageDenominator":2,"Status":"Executed","Site":"WLLS","Hostname":"WLLS-A01"}'
            '{"EventName":"DriftDetectionTime","DurationMinutes":12.5,"Site":"BOYO","Hostname":"BOYO-A01"}'
            '{"EventName":"DriftDetectionTime","DurationMinutes":7.5,"Site":"WLLS","Hostname":"WLLS-A01"}'
        )

        $samplePath = Join-Path -Path $testMetricsDir -ChildPath '2025-10-03.json'
        Set-Content -Path $samplePath -Value $sampleEvents -Encoding UTF8

        $toolsRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
        $scriptPath = Join-Path -Path $toolsRoot -ChildPath 'Tools\Rollup-IngestionMetrics.ps1'
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'summary.csv'

        $scriptResults = & $scriptPath -MetricsDirectory $testMetricsDir -OutputPath $outputPath -IncludePerSite -IncludeSiteCache -PassThru

        $script:ScriptResults = $scriptResults
        $script:OutputPath = $outputPath
        $script:RollupScriptPath = $scriptPath
        $script:TestMetricsDirectory = $testMetricsDir
        $script:SampleMetricPath = $samplePath
    }

    It 'writes a CSV summary file' {
        (Test-Path -LiteralPath $OutputPath) | Should Be $true
    }

    It 'produces aggregate parse duration statistics' {
        $parseRow = $ScriptResults | Where-Object { $_.Metric -eq 'ParseDurationSeconds' -and $_.Scope -eq 'All' }
        $parseRow | Should Not BeNullOrEmpty
        $parseRow.Count | Should Be 2
        $parseRow.Average | Should Be 2.0
        ([Math]::Abs($parseRow.P95 - 2.5) -lt 0.1) | Should Be $true
        $parseRow.Notes | Should Be 'Failures=1'
    }

    It 'produces per-site parse statistics when requested' {
        $siteRow = $ScriptResults | Where-Object { $_.Metric -eq 'ParseDurationSeconds' -and $_.Scope -eq 'BOYO' }
        $siteRow | Should Not BeNullOrEmpty
        $siteRow.Count | Should Be 1
        $siteRow.Average | Should Be 1.5
    }

    It 'summarises database write latency metrics' {
        $latencyRow = $ScriptResults | Where-Object { $_.Metric -eq 'DatabaseWriteLatencyMs' -and $_.Scope -eq 'All' }
        $latencyRow | Should Not BeNullOrEmpty
        $latencyRow.Count | Should Be 2
        ([Math]::Abs($latencyRow.P95 - 700) -lt 50) | Should Be $true
        $latencyRow.Max | Should Be 700
    }

    It 'rolls up rows written totals' {
        $rowsRow = $ScriptResults | Where-Object { $_.Metric -eq 'RowsWritten' -and $_.Scope -eq 'All' }
        $rowsRow | Should Not BeNullOrEmpty
        $rowsRow.Total | Should Be 144
        $rowsRow.SecondaryTotal | Should Be 2
        $rowsRow.Notes | Should Be 'UniqueHosts=2'
    }

    It 'counts skipped duplicate events' {
        $duplicateRow = $ScriptResults | Where-Object { $_.Metric -eq 'SkippedDuplicate' -and $_.Scope -eq 'All' }
        $duplicateRow | Should Not BeNullOrEmpty
        $duplicateRow.Count | Should Be 2
        $duplicateRow.Total | Should Be 2
    }

    It 'summarises site cache fetch metrics' {
        $fetchRow = $ScriptResults | Where-Object { $_.Metric -eq 'SiteCacheFetchDurationMs' -and $_.Scope -eq 'All' }
        $fetchRow | Should Not BeNullOrEmpty
        $fetchRow.Count | Should Be 1
        $fetchRow.Average | Should Be 200
        $fetchRow.P95 | Should Be 200
        $fetchRow.Total | Should Be 200
        $fetchRow.Notes | Should Be 'Statuses=Hit=1,Hydrated=1; Providers=Cache=1,Refresh=1; ZeroCount=1'
    }

    It 'includes site-level site cache summaries' {
        $boYoFetch = $ScriptResults | Where-Object { $_.Metric -eq 'SiteCacheFetchDurationMs' -and $_.Scope -eq 'BOYO' }
        @($boYoFetch).Count | Should Be 1
        $boYoFetch.Count | Should Be 1
        $boYoFetch.Average | Should Be 200

        $wllsFetch = $ScriptResults | Where-Object { $_.Metric -eq 'SiteCacheFetchDurationMs' -and $_.Scope -eq 'WLLS' }
        @($wllsFetch).Count | Should Be 1
        $wllsFetch.Count | Should Be 0
        $wllsFetch.Notes | Should Be 'Statuses=Hit=1; Providers=Cache=1; ZeroCount=1'
    }

    # LANDMARK: Rollup ingestion metrics tests - diff telemetry coverage
    It 'summarises diff usage rate events' {
        $usageRow = $ScriptResults | Where-Object { $_.Metric -eq 'DiffUsageRate' -and $_.Scope -eq 'All' }
        $usageRow | Should Not BeNullOrEmpty
        $usageRow.Count | Should Be 2
        $usageRow.Total | Should Be 2
        $usageRow.SecondaryTotal | Should Be 3
        ([Math]::Abs($usageRow.Average - 0.667) -lt 0.01) | Should Be $true
        $usageRow.Notes | Should Be 'Statuses=Executed=2'
    }

    It 'summarises drift detection time events' {
        $driftRow = $ScriptResults | Where-Object { $_.Metric -eq 'DriftDetectionTimeMinutes' -and $_.Scope -eq 'All' }
        $driftRow | Should Not BeNullOrEmpty
        $driftRow.Count | Should Be 2
        $driftRow.Average | Should Be 10
        $driftRow.Max | Should Be 12.5
        $driftRow.Total | Should Be 20
    }

    # LANDMARK: Rollup ingestion metrics tests - diff/compare telemetry fixture coverage
    Context 'Diff/compare telemetry fixture coverage' {
        It 'rolls up diff/compare telemetry from the DiffPrototype fixture' {
            $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
            $fixturePath = Join-Path -Path $repoRoot -ChildPath 'Data\Samples\DiffPrototype\TelemetrySample.json'
            $outputPath = Join-Path -Path $TestDrive -ChildPath 'fixture-summary.csv'
            $rows = & $script:RollupScriptPath -MetricFile $fixturePath -OutputPath $outputPath -IncludePerSite -PassThru

            $usageRow = $rows | Where-Object { $_.Metric -eq 'DiffUsageRate' -and $_.Scope -eq 'All' }
            $usageRow | Should Not BeNullOrEmpty
            $usageRow.Count | Should Be 2
            $usageRow.Total | Should Be 2
            $usageRow.SecondaryTotal | Should Be 3
            $usageRow.Notes | Should Be 'Statuses=Executed=2'

            $durationRow = $rows | Where-Object { $_.Metric -eq 'DiffCompareDurationMs' -and $_.Scope -eq 'All' }
            $durationRow | Should Not BeNullOrEmpty
            $durationRow.Count | Should Be 1
            $durationRow.Average | Should Be 150
            $durationRow.P95 | Should Be 150
            $durationRow.Max | Should Be 150
            $durationRow.Total | Should Be 150
            $durationRow.Notes | Should Be 'Statuses=Executed=1'

            $countsRow = $rows | Where-Object { $_.Metric -eq 'DiffCompareResultCounts' -and $_.Scope -eq 'All' }
            $countsRow | Should Not BeNullOrEmpty
            $countsRow.Count | Should Be 1
            $countsRow.Average | Should Be 4
            $countsRow.P95 | Should Be 4
            $countsRow.Max | Should Be 4
            $countsRow.Total | Should Be 4
            $countsRow.Notes | Should Match 'Added=1'
            $countsRow.Notes | Should Match 'Removed=1'
            $countsRow.Notes | Should Match 'Changed=0'
            $countsRow.Notes | Should Match 'Unchanged=2'
            $countsRow.Notes | Should Match 'Statuses=Executed=1'

            $driftRow = $rows | Where-Object { $_.Metric -eq 'DriftDetectionTimeMinutes' -and $_.Scope -eq 'All' }
            $driftRow | Should Not BeNullOrEmpty
            $driftRow.Count | Should Be 2
            $driftRow.Average | Should Be 10
            $driftRow.Max | Should Be 12.5
        }
    }

    Context 'Filtering switches' {
        It 'accepts explicit MetricFile paths' {
        $rows = & $script:RollupScriptPath -MetricFile $script:SampleMetricPath -IncludePerSite -IncludeSiteCache -PassThru
        $dates = @($rows | Select-Object -ExpandProperty Date -Unique)
        $dates.Count | Should Be 1
        $dates[0] | Should Be '2025-10-03'
        }

        It 'filters metric files by name pattern' {
            $filteredEvents = @(
                '{"EventName":"ParseDuration","DurationSeconds":4.0,"Success":true,"Site":"TEST","Hostname":"TEST-A01"}'
            )
            $filteredPath = Join-Path -Path $TestMetricsDirectory -ChildPath '2025-10-04-extra.json'
            Set-Content -Path $filteredPath -Value $filteredEvents -Encoding UTF8

            $rows = & $script:RollupScriptPath -MetricsDirectory $script:TestMetricsDirectory -MetricFileNameFilter '2025-10-04*.json' -PassThru
            $dates = @($rows | Select-Object -ExpandProperty Date -Unique)
            $dates.Count | Should Be 1
            $dates[0] | Should Be '2025-10-04-extra'
            $parseRow = $rows | Where-Object { $_.Metric -eq 'ParseDurationSeconds' -and $_.Scope -eq 'All' }
            $parseRow.Count | Should Be 1
            $parseRow.Average | Should Be 4.0
        }

        It 'limits processing to the latest N files' {
            $olderEvents = @('{"EventName":"ParseDuration","DurationSeconds":5.0,"Success":true}')
            $olderPath = Join-Path -Path $script:TestMetricsDirectory -ChildPath '2025-10-05.json'
            Set-Content -Path $olderPath -Value $olderEvents -Encoding UTF8
            (Get-Item -LiteralPath $olderPath).LastWriteTimeUtc = (Get-Date).AddMinutes(-5)

            $latestEvents = @('{"EventName":"ParseDuration","DurationSeconds":7.5,"Success":true}')
            $latestPath = Join-Path -Path $script:TestMetricsDirectory -ChildPath '2025-10-06.json'
            Set-Content -Path $latestPath -Value $latestEvents -Encoding UTF8
            (Get-Item -LiteralPath $latestPath).LastWriteTimeUtc = Get-Date

            $rows = & $script:RollupScriptPath -MetricsDirectory $script:TestMetricsDirectory -Latest 1 -PassThru
            $dates = @($rows | Select-Object -ExpandProperty Date -Unique)
            $dates.Count | Should Be 1
            $dates[0] | Should Be '2025-10-06'
            $parseRow = $rows | Where-Object { $_.Metric -eq 'ParseDurationSeconds' -and $_.Scope -eq 'All' }
            $parseRow.Average | Should Be 7.5
        }
    }
}
