Set-StrictMode -Version Latest

Describe 'Test-PortBatchSiteDiversity' {
    It 'throws when PortBatchReady events are missing by default' {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath '..\..'))
        $scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Test-PortBatchSiteDiversity.ps1'
        $metricsPath = Join-Path -Path $TestDrive -ChildPath ("IngestionMetrics-{0}.json" -f ([System.Guid]::NewGuid().ToString('N')))

        $record = [pscustomobject]@{
            EventName = 'SomeOtherEvent'
            Timestamp = (Get-Date).ToString('o')
        }
        ($record | ConvertTo-Json -Compress) | Set-Content -LiteralPath $metricsPath -Encoding utf8

        $thrownMessage = $null
        try {
            & $scriptPath -MetricsPath $metricsPath -MaxAllowedConsecutive 8 | Out-Null
        } catch {
            $thrownMessage = $_.Exception.Message
        }

        $thrownMessage | Should Not BeNullOrEmpty
        $thrownMessage | Should Match 'No PortBatchReady events found'
    }

    It 'returns a skipped result when AllowEmpty is set' {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath '..\..'))
        $scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Test-PortBatchSiteDiversity.ps1'
        $metricsPath = Join-Path -Path $TestDrive -ChildPath ("IngestionMetrics-{0}.json" -f ([System.Guid]::NewGuid().ToString('N')))
        $outputPath = Join-Path -Path $TestDrive -ChildPath ("PortBatchSiteDiversity-{0}.json" -f ([System.Guid]::NewGuid().ToString('N')))

        $record = [pscustomobject]@{
            EventName = 'SomeOtherEvent'
            Timestamp = (Get-Date).ToString('o')
        }
        ($record | ConvertTo-Json -Compress) | Set-Content -LiteralPath $metricsPath -Encoding utf8

        $result = & $scriptPath -MetricsPath $metricsPath -MaxAllowedConsecutive 8 -AllowEmpty -OutputPath $outputPath

        $result | Should Not BeNullOrEmpty
        $result.Skipped | Should Be $true
        $result.SkipReason | Should Be 'NoPortBatchReadyEvents'
        $result.PortBatchReadyCount | Should Be 0
        $result.SiteStreaks | Should BeNullOrEmpty
        (Test-Path -LiteralPath $outputPath) | Should Be $true

        $saved = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -ErrorAction Stop
        $saved.Skipped | Should Be $true
        $saved.SkipReason | Should Be 'NoPortBatchReadyEvents'
    }

    It 'ignores synthesized events when requested' {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath '..\..'))
        $scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Test-PortBatchSiteDiversity.ps1'
        $metricsPath = Join-Path -Path $TestDrive -ChildPath ("IngestionMetrics-{0}.json" -f ([System.Guid]::NewGuid().ToString('N')))
        $outputPath = Join-Path -Path $TestDrive -ChildPath ("PortBatchSiteDiversity-{0}.json" -f ([System.Guid]::NewGuid().ToString('N')))

        $base = Get-Date
        $events = @(
            [pscustomobject]@{ EventName = 'PortBatchReady'; Timestamp = $base.ToString('o'); Hostname = 'BOYO-A05-AS-01' },
            [pscustomobject]@{ EventName = 'PortBatchReady'; Timestamp = $base.AddSeconds(1).ToString('o'); Hostname = 'WLLS-A01-AS-01' },
            [pscustomobject]@{ EventName = 'PortBatchReady'; Timestamp = $base.AddSeconds(2).ToString('o'); Hostname = 'WLLS-A01-AS-02'; Synthesized = $true }
        )
        $events | ForEach-Object { $_ | ConvertTo-Json -Compress } | Set-Content -LiteralPath $metricsPath -Encoding utf8

        $result = & $scriptPath -MetricsPath $metricsPath -MaxAllowedConsecutive 8 -IgnoreSynthesizedEvents -OutputPath $outputPath

        $result | Should Not BeNullOrEmpty
        $result.UsedSynthesizedEvents | Should Be $false
        $result.IgnoredSynthesizedEvents | Should Be $true
        $result.ObservedPortBatchReadyCount | Should Be 2
        $result.SynthesizedPortBatchReadyCount | Should Be 1
        $result.EvaluatedPortBatchReadyCount | Should Be 2
        $result.MaxStreakSegment | Should Not BeNullOrEmpty
        (Test-Path -LiteralPath $outputPath) | Should Be $true
    }

    It 'prefers synthesized events by default when present' {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath '..\..'))
        $scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Test-PortBatchSiteDiversity.ps1'
        $metricsPath = Join-Path -Path $TestDrive -ChildPath ("IngestionMetrics-{0}.json" -f ([System.Guid]::NewGuid().ToString('N')))

        $base = Get-Date
        $events = @(
            [pscustomobject]@{ EventName = 'PortBatchReady'; Timestamp = $base.ToString('o'); Hostname = 'BOYO-A05-AS-01' },
            [pscustomobject]@{ EventName = 'PortBatchReady'; Timestamp = $base.AddSeconds(1).ToString('o'); Hostname = 'WLLS-A01-AS-01' },
            [pscustomobject]@{ EventName = 'PortBatchReady'; Timestamp = $base.AddSeconds(2).ToString('o'); Hostname = 'WLLS-A01-AS-02'; Synthesized = $true }
        )
        $events | ForEach-Object { $_ | ConvertTo-Json -Compress } | Set-Content -LiteralPath $metricsPath -Encoding utf8

        $result = & $scriptPath -MetricsPath $metricsPath -MaxAllowedConsecutive 8

        $result | Should Not BeNullOrEmpty
        $result.UsedSynthesizedEvents | Should Be $true
        $result.EvaluatedPortBatchReadyCount | Should Be 1
    }

    # LANDMARK: Raw diversity metadata - record concurrency fields in reports
    It 'records manual override metadata when provided' {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath '..\..'))
        $scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Test-PortBatchSiteDiversity.ps1'
        $metricsPath = Join-Path -Path $TestDrive -ChildPath ("IngestionMetrics-{0}.json" -f ([System.Guid]::NewGuid().ToString('N')))
        $outputPath = Join-Path -Path $TestDrive -ChildPath ("PortBatchSiteDiversity-{0}.json" -f ([System.Guid]::NewGuid().ToString('N')))

        $base = Get-Date
        $events = @(
            [pscustomobject]@{ EventName = 'PortBatchReady'; Timestamp = $base.ToString('o'); Hostname = 'BOYO-A05-AS-01' },
            [pscustomobject]@{ EventName = 'PortBatchReady'; Timestamp = $base.AddSeconds(1).ToString('o'); Hostname = 'WLLS-A01-AS-01' }
        )
        $events | ForEach-Object { $_ | ConvertTo-Json -Compress } | Set-Content -LiteralPath $metricsPath -Encoding utf8

        $profile = [pscustomobject]@{
            ManualOverrides = $false
            ThreadCeiling   = 4
            MaxActiveSites  = 2
        }
        $result = & $scriptPath -MetricsPath $metricsPath -MaxAllowedConsecutive 8 `
            -ManualOverridesApplied:$false -ConcurrencyProfile $profile -OutputPath $outputPath

        $result | Should Not BeNullOrEmpty
        $result.ManualOverridesApplied | Should Be $false
        $result.UsedSynthesizedEvents | Should Be $false
        $result.ConcurrencyProfile.ThreadCeiling | Should Be 4
        $result.ConcurrencyProfile.MaxActiveSites | Should Be 2

        $saved = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -ErrorAction Stop
        $saved.ManualOverridesApplied | Should Be $false
        $saved.ConcurrencyProfile.ThreadCeiling | Should Be 4
        $saved.ConcurrencyProfile.MaxActiveSites | Should Be 2
    }

    # LANDMARK: Port diversity window - verify upper-bound filtering
    It 'respects UntilTimestamp when evaluating streaks' {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath '..\..'))
        $scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Test-PortBatchSiteDiversity.ps1'
        $metricsPath = Join-Path -Path $TestDrive -ChildPath ("IngestionMetrics-{0}.json" -f ([System.Guid]::NewGuid().ToString('N')))

        $base = Get-Date
        $until = $base.AddSeconds(1)
        $events = @(
            [pscustomobject]@{ EventName = 'PortBatchReady'; Timestamp = $base.ToString('o'); Hostname = 'BOYO-A05-AS-01' },
            [pscustomobject]@{ EventName = 'PortBatchReady'; Timestamp = $base.AddSeconds(1).ToString('o'); Hostname = 'WLLS-A01-AS-01' },
            [pscustomobject]@{ EventName = 'PortBatchReady'; Timestamp = $base.AddSeconds(2).ToString('o'); Hostname = 'WLLS-A01-AS-02' }
        )
        $events | ForEach-Object { $_ | ConvertTo-Json -Compress } | Set-Content -LiteralPath $metricsPath -Encoding utf8

        $result = & $scriptPath -MetricsPath $metricsPath -MaxAllowedConsecutive 8 -UntilTimestamp $until

        $result | Should Not BeNullOrEmpty
        $result.EvaluatedPortBatchReadyCount | Should Be 2
        $result.EvaluationWindowEndUtc.ToUniversalTime().ToString('o') | Should Be $until.ToUniversalTime().ToString('o')
    }
}
