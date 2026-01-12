Set-StrictMode -Version Latest

Describe 'DiffPrototype fixtures' {
    BeforeAll {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
        $fixturesRoot = Join-Path -Path $repoRoot -ChildPath 'Data\Samples\DiffPrototype'
        $metricsTemplate = Join-Path -Path $repoRoot -ChildPath 'Logs\Research\DiffPrototype\metrics.csv'
        $telemetryFixture = Join-Path -Path $fixturesRoot -ChildPath 'TelemetrySample.json'
        $rollupScript = Join-Path -Path $repoRoot -ChildPath 'Tools\Rollup-IngestionMetrics.ps1'

        $script:FixtureRoot = $fixturesRoot
        $script:MetricsTemplate = $metricsTemplate
        $script:TelemetryFixture = $telemetryFixture
        $script:RollupScript = $rollupScript
    }

    # LANDMARK: DiffPrototype fixtures tests - presence and rollup compatibility
    It 'includes capture bundles per device' {
        if (-not (Test-Path -LiteralPath $FixtureRoot)) {
            Set-TestInconclusive -Message "DiffPrototype fixture root not found at $FixtureRoot"
            return
        }
        (Test-Path -LiteralPath $FixtureRoot) | Should Be $true
        foreach ($device in @('BOYO-A01', 'WLLS-A01')) {
            $devicePath = Join-Path -Path $FixtureRoot -ChildPath $device       
            (Test-Path -LiteralPath $devicePath) | Should Be $true
            $captures = Get-ChildItem -Path $devicePath -Filter 'capture-*.txt' -File
            (@($captures).Count -ge 3) | Should Be $true
        }
    }

    It 'includes the diff prototype metrics template' {
        if (-not (Test-Path -LiteralPath $MetricsTemplate)) {
            Set-TestInconclusive -Message "DiffPrototype metrics template not found at $MetricsTemplate"
            return
        }
        (Test-Path -LiteralPath $MetricsTemplate) | Should Be $true
        $header = Get-Content -Path $MetricsTemplate -TotalCount 1
        $header | Should Be 'CaptureId,DeviceCount,RunTimeSeconds,DbSizeMB,Notes'
    }

    # LANDMARK: DiffPrototype fixtures tests - schema alignment and rollup assertions
    It 'includes real-schema telemetry events' {
        if (-not (Test-Path -LiteralPath $TelemetryFixture)) {
            Set-TestInconclusive -Message "DiffPrototype telemetry fixture not found at $TelemetryFixture"
            return
        }
        (Test-Path -LiteralPath $TelemetryFixture) | Should Be $true
        $events = Get-Content -Path $TelemetryFixture | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json }       

        $usageEvent = $events | Where-Object { $_.EventName -eq 'DiffUsageRate' } | Select-Object -First 1
        $usageEvent | Should Not BeNullOrEmpty
        ($usageEvent.PSObject.Properties.Name -contains 'UsageNumerator') | Should Be $true
        ($usageEvent.PSObject.Properties.Name -contains 'UsageDenominator') | Should Be $true
        ($usageEvent.PSObject.Properties.Name -contains 'Timestamp') | Should Be $true

        $durationEvent = $events | Where-Object { $_.EventName -eq 'DiffCompareDurationMs' } | Select-Object -First 1
        $durationEvent | Should Not BeNullOrEmpty
        # LANDMARK: DiffPrototype fixtures tests - telemetry schema alignment
        ($durationEvent.PSObject.Properties.Name -contains 'DurationMs') | Should Be $true
        ($durationEvent.PSObject.Properties.Name -contains 'TimestampUtc') | Should Be $true
        ($durationEvent.PSObject.Properties.Name -contains 'Timestamp') | Should Be $false

        $countsEvent = $events | Where-Object { $_.EventName -eq 'DiffCompareResultCounts' } | Select-Object -First 1
        $countsEvent | Should Not BeNullOrEmpty
        ($countsEvent.PSObject.Properties.Name -contains 'AddedCount') | Should Be $true
        ($countsEvent.PSObject.Properties.Name -contains 'RemovedCount') | Should Be $true
        ($countsEvent.PSObject.Properties.Name -contains 'UnchangedCount') | Should Be $true
        ($countsEvent.PSObject.Properties.Name -contains 'TimestampUtc') | Should Be $true
        ($countsEvent.PSObject.Properties.Name -contains 'Timestamp') | Should Be $false

        $driftEvent = $events | Where-Object { $_.EventName -eq 'DriftDetectionTime' } | Select-Object -First 1
        $driftEvent | Should Not BeNullOrEmpty
        ($driftEvent.PSObject.Properties.Name -contains 'DurationMinutes') | Should Be $true
    }

    It 'rolls up diff telemetry from the fixture metrics file' {
        if (-not (Test-Path -LiteralPath $TelemetryFixture)) {
            Set-TestInconclusive -Message "DiffPrototype telemetry fixture not found at $TelemetryFixture"
            return
        }
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'summary.csv'       
        $rows = & $RollupScript -MetricFile $TelemetryFixture -OutputPath $outputPath -IncludePerSite -PassThru

        $usageRow = $rows | Where-Object { $_.Metric -eq 'DiffUsageRate' -and $_.Scope -eq 'All' }
        @($usageRow).Count | Should Be 1
        $usageRow.Count | Should Be 2
        $usageRow.Total | Should Be 2
        $usageRow.SecondaryTotal | Should Be 3

        $driftRow = $rows | Where-Object { $_.Metric -eq 'DriftDetectionTimeMinutes' -and $_.Scope -eq 'All' }
        @($driftRow).Count | Should Be 1
        $driftRow.Count | Should Be 2
        $driftRow.Average | Should Be 10
        $driftRow.Max | Should Be 12.5

        # LANDMARK: DiffPrototype fixtures tests - compare rollup coverage
        $durationRow = $rows | Where-Object { $_.Metric -eq 'DiffCompareDurationMs' -and $_.Scope -eq 'All' }
        @($durationRow).Count | Should Be 1
        $durationRow.Count | Should Be 1
        $durationRow.Average | Should Be 150
        $durationRow.Total | Should Be 150

        $countsRow = $rows | Where-Object { $_.Metric -eq 'DiffCompareResultCounts' -and $_.Scope -eq 'All' }
        @($countsRow).Count | Should Be 1
        $countsRow.Count | Should Be 1
        $countsRow.Total | Should Be 4
        $countsRow.Notes | Should Match 'Added=1'
        $countsRow.Notes | Should Match 'Removed=1'
        $countsRow.Notes | Should Match 'Unchanged=2'
    }
}
