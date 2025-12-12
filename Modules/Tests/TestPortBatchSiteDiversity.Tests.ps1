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
}
