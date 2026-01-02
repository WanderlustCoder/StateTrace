# LANDMARK: Warm-run history backups - validate warmrun snapshot creation
Set-StrictMode -Version Latest

Describe 'Warm-run ingestion history backups' {
    BeforeAll {
        $toolsPath = Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath '..\..\Tools\Invoke-WarmRunTelemetry.ps1'
        $script:WarmTelemetryPreviousSkip = $null
        if (Test-Path -LiteralPath 'variable:global:WarmRunTelemetrySkipMain') {
            $script:WarmTelemetryPreviousSkip = Get-Variable -Name 'WarmRunTelemetrySkipMain' -Scope Global -ValueOnly
        }
        Set-Variable -Name 'WarmRunTelemetrySkipMain' -Scope Global -Value $true
        . (Resolve-Path $toolsPath)
        if ($null -ne $script:WarmTelemetryPreviousSkip) {
            Set-Variable -Name 'WarmRunTelemetrySkipMain' -Scope Global -Value $script:WarmTelemetryPreviousSkip
        } else {
            Remove-Variable -Name 'WarmRunTelemetrySkipMain' -Scope Global -ErrorAction SilentlyContinue
        }
    }

    AfterAll {
        Remove-Variable -Name 'WarmTelemetryPreviousSkip' -Scope Script -ErrorAction SilentlyContinue
    }

    It 'writes warm-run backup files and uses them for warm snapshot' {
        $historyDir = Join-Path -Path $TestDrive -ChildPath 'History'
        $null = New-Item -ItemType Directory -Path $historyDir -Force

        $fileA = Join-Path -Path $historyDir -ChildPath 'SITEA.json'
        $fileB = Join-Path -Path $historyDir -ChildPath 'SITEB.json'
        $contentA = '[{"Site":"SITEA"}]'
        $contentB = '[{"Site":"SITEB"}]'
        Set-Content -LiteralPath $fileA -Value $contentA -Encoding utf8
        Set-Content -LiteralPath $fileB -Value $contentB -Encoding utf8

        $snapshot = @(
            [pscustomobject]@{ Path = $fileA; Content = $contentA },
            [pscustomobject]@{ Path = $fileB; Content = $contentB }
        )

        $written = Write-IngestionHistoryWarmRunBackups -DirectoryPath $historyDir -Snapshot $snapshot -Label 'Test'
        $written | Should Be 2

        $backupFiles = Get-ChildItem -Path $historyDir -Filter '*.warmrun.*.bak' -File
        $backupFiles.Count | Should Be 2

        $warningPreferenceOriginal = $WarningPreference
        try {
            $WarningPreference = 'Stop'
            $warmSnapshot = Get-IngestionHistoryWarmRunSnapshot -DirectoryPath $historyDir -FallbackSnapshot $snapshot
        } finally {
            $WarningPreference = $warningPreferenceOriginal
        }

        $warmSnapshot.Count | Should Be 2
    }

    It 'selects the latest warm-run backup and records the backup path' {
        $historyDir = Join-Path -Path $TestDrive -ChildPath 'HistoryLatest'
        $null = New-Item -ItemType Directory -Path $historyDir -Force

        $fileA = Join-Path -Path $historyDir -ChildPath 'SITEA.json'
        $contentA = '[{"Site":"SITEA"}]'
        Set-Content -LiteralPath $fileA -Value $contentA -Encoding utf8

        $snapshot = @([pscustomobject]@{ Path = $fileA; Content = $contentA })

        $backupOld = Join-Path -Path $historyDir -ChildPath 'SITEA.json.warmrun.20240101-000000.bak'
        $backupNew = Join-Path -Path $historyDir -ChildPath 'SITEA.json.warmrun.20240102-000000.bak'
        Set-Content -LiteralPath $backupOld -Value '[{"Site":"OLD"}]' -Encoding utf8
        Set-Content -LiteralPath $backupNew -Value '[{"Site":"NEW"}]' -Encoding utf8
        (Get-Item -LiteralPath $backupOld).LastWriteTime = (Get-Date).AddMinutes(-10)
        (Get-Item -LiteralPath $backupNew).LastWriteTime = (Get-Date).AddMinutes(-5)

        $warningPreferenceOriginal = $WarningPreference
        try {
            $WarningPreference = 'Stop'
            $warmSnapshot = Get-IngestionHistoryWarmRunSnapshot -DirectoryPath $historyDir -FallbackSnapshot $snapshot
        } finally {
            $WarningPreference = $warningPreferenceOriginal
        }

        $entry = $warmSnapshot | Where-Object { $_.Path -eq $fileA } | Select-Object -First 1
        $entry.BackupPath | Should Be $backupNew
        $entry.BackupStatus | Should Be 'Selected'
    }
}

Describe 'Warm-run telemetry metric status' {
    # LANDMARK: Warm-pass telemetry status tests - validate optional missing metrics
    It 'marks duplicate-only warm passes as NotApplicable when seeded' {
        $events = @([pscustomobject]@{ EventName = 'SkippedDuplicate' })
        $missing = @('DatabaseWriteBreakdown','InterfaceSyncTiming')

        $status = Resolve-PassTelemetryMetricStatus -Label 'WarmPass' -Events $events -MissingEventNames $missing -HistorySeedMode 'WarmBackup'
        $status.OptionalMissing.Contains('DatabaseWriteBreakdown') | Should Be $true
        $status.OptionalMissing.Contains('InterfaceSyncTiming') | Should Be $true

        $dbStatus = $status.Statuses | Where-Object { $_.MetricName -eq 'DatabaseWriteBreakdown' } | Select-Object -First 1
        $dbStatus.MetricStatus | Should Be 'NotApplicable'
        $dbStatus.MetricStatusReason | Should Be 'SkippedDuplicateOnly'
    }

    It 'does not mark missing metrics as optional when warm history is empty' {
        $events = @([pscustomobject]@{ EventName = 'SkippedDuplicate' })
        $missing = @('DatabaseWriteBreakdown','InterfaceSyncTiming')

        $status = Resolve-PassTelemetryMetricStatus -Label 'WarmPass' -Events $events -MissingEventNames $missing -HistorySeedMode 'Empty'
        $status.OptionalMissing.Count | Should Be 0
    }

    It 'filters optional missing metrics from warm-pass warnings' {
        $missing = @('DatabaseWriteBreakdown','InterfaceSyncTiming')
        $optional = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        [void]$optional.Add('DatabaseWriteBreakdown')
        [void]$optional.Add('InterfaceSyncTiming')

        $warnMissing = Get-TelemetryWarningMissingNames -MissingEventNames $missing -OptionalMissing $optional
        $warnMissing.Count | Should Be 0
    }
}
