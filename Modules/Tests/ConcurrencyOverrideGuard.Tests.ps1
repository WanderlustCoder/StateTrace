Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$guardModulePath = Join-Path -Path $repoRoot -ChildPath 'Tools\ConcurrencyOverrideGuard.psm1'

Describe 'ConcurrencyOverrideGuard' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $guardModulePath)) {
            throw "Guard module not found at $guardModulePath"
        }
        Import-Module -Name $guardModulePath -Force
    }

    It 'resets non-baseline overrides' {
        $settingsPath = Join-Path -Path $TestDrive -ChildPath 'StateTraceSettings.json'
        Set-Content -LiteralPath $settingsPath -Value '{ "ParserSettings": { "MaxRunspaceCeiling": 4, "MaxWorkersPerSite": 2, "MaxActiveSites": 3, "JobsPerThread": 5, "MinRunspaceCount": 2 } }' -Encoding utf8

        $result = Reset-ConcurrencyOverrideSettings -SettingsPath $settingsPath -Label 'Test'

        $result | Should Not BeNullOrEmpty
        $result.Changed | Should Be $true
        $result.Overrides.MaxRunspaceCeiling | Should Be 4
        $result.Overrides.MaxWorkersPerSite | Should Be 2
        $result.Overrides.MaxActiveSites | Should Be 3
        $result.Overrides.JobsPerThread | Should Be 5
        $result.Overrides.MinRunspaceCount | Should Be 2

        $text = Get-Content -LiteralPath $settingsPath -Raw
        $text | Should Match '"MaxRunspaceCeiling"\s*:\s*0'
        $text | Should Match '"MaxWorkersPerSite"\s*:\s*0'
        $text | Should Match '"MaxActiveSites"\s*:\s*0'
        $text | Should Match '"JobsPerThread"\s*:\s*0'
        $text | Should Match '"MinRunspaceCount"\s*:\s*1'
    }

    # LANDMARK: Raw diversity auto concurrency tests - snapshot restore
    It 'restores settings from a snapshot' {
        $settingsPath = Join-Path -Path $TestDrive -ChildPath 'StateTraceSettings.json'
        $original = '{ "ParserSettings": { "MaxRunspaceCeiling": 4, "MaxWorkersPerSite": 2, "MaxActiveSites": 3, "JobsPerThread": 5, "MinRunspaceCount": 2 } }'
        Set-Content -LiteralPath $settingsPath -Value $original -Encoding utf8
        $originalBytes = [System.IO.File]::ReadAllBytes($settingsPath)

        $snapshot = Get-ConcurrencyOverrideSnapshot -SettingsPath $settingsPath
        $snapshot.Exists | Should Be $true
        $snapshot.OriginalText | Should Match '"MaxRunspaceCeiling"\s*:\s*4'

        Set-Content -LiteralPath $settingsPath -Value '{ "ParserSettings": { "MaxRunspaceCeiling": 0, "MaxWorkersPerSite": 0, "MaxActiveSites": 0, "JobsPerThread": 0, "MinRunspaceCount": 1 } }' -Encoding utf8

        $restored = Set-ConcurrencyOverrideSnapshot -Snapshot $snapshot
        $restored | Should Be $true

        $text = Get-Content -LiteralPath $settingsPath -Raw
        $text | Should Match '"MaxRunspaceCeiling"\s*:\s*4'
        $text | Should Match '"MaxWorkersPerSite"\s*:\s*2'
        $text | Should Match '"MaxActiveSites"\s*:\s*3'
        $text | Should Match '"JobsPerThread"\s*:\s*5'
        $text | Should Match '"MinRunspaceCount"\s*:\s*2'
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($settingsPath)) | Should Be ([Convert]::ToBase64String($originalBytes))
    }

    # LANDMARK: Raw auto restore safety tests - restore after failure
    It 'restores settings after a failure' {
        $settingsPath = Join-Path -Path $TestDrive -ChildPath 'StateTraceSettings.json'
        $original = '{ "ParserSettings": { "MaxRunspaceCeiling": 9, "MaxWorkersPerSite": 1, "MaxActiveSites": 2, "JobsPerThread": 3, "MinRunspaceCount": 4 } }'
        Set-Content -LiteralPath $settingsPath -Value $original -Encoding utf8
        $originalBytes = [System.IO.File]::ReadAllBytes($settingsPath)

        $snapshot = Get-ConcurrencyOverrideSnapshot -SettingsPath $settingsPath
        try {
            Set-Content -LiteralPath $settingsPath -Value '{ "ParserSettings": { "MaxRunspaceCeiling": 0, "MaxWorkersPerSite": 0, "MaxActiveSites": 0, "JobsPerThread": 0, "MinRunspaceCount": 1 } }' -Encoding utf8
            throw 'Simulated failure'
        } catch {
            $_.Exception.Message | Should Be 'Simulated failure'
        } finally {
            Set-ConcurrencyOverrideSnapshot -Snapshot $snapshot | Out-Null
        }

        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($settingsPath)) | Should Be ([Convert]::ToBase64String($originalBytes))
    }

    It 'no-ops when settings are already baseline' {
        $settingsPath = Join-Path -Path $TestDrive -ChildPath 'StateTraceSettings.json'
        Set-Content -LiteralPath $settingsPath -Value '{ "ParserSettings": { "MaxRunspaceCeiling": 0, "MaxWorkersPerSite": 0, "MaxActiveSites": 0, "JobsPerThread": 0, "MinRunspaceCount": 1 } }' -Encoding utf8

        $result = Reset-ConcurrencyOverrideSettings -SettingsPath $settingsPath -Label 'Test'

        $result | Should Not BeNullOrEmpty
        $result.Changed | Should Be $false
        $result.Overrides.Count | Should Be 0

        $text = Get-Content -LiteralPath $settingsPath -Raw
        $text | Should Match '"MaxRunspaceCeiling"\s*:\s*0'
        $text | Should Match '"MaxWorkersPerSite"\s*:\s*0'
        $text | Should Match '"MaxActiveSites"\s*:\s*0'
        $text | Should Match '"JobsPerThread"\s*:\s*0'
        $text | Should Match '"MinRunspaceCount"\s*:\s*1'
    }
}
