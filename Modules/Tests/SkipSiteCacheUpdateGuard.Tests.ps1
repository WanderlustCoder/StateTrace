Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$guardModulePath = Join-Path -Path $repoRoot -ChildPath 'Tools\SkipSiteCacheUpdateGuard.psm1'

Describe 'SkipSiteCacheUpdateGuard' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $guardModulePath)) {
            throw "Guard module not found at $guardModulePath"
        }
        Import-Module -Name $guardModulePath -Force
    }

    It 'disables and restores when SkipSiteCacheUpdate is true' {
        $settingsPath = Join-Path -Path $TestDrive -ChildPath 'StateTraceSettings.json'
        Set-Content -LiteralPath $settingsPath -Value '{ "SkipSiteCacheUpdate": true, "Other": 1 }' -Encoding utf8

        $guard = Disable-SkipSiteCacheUpdateSetting -SettingsPath $settingsPath -Label 'Test'
        $guard | Should Not BeNullOrEmpty
        $guard.Changed | Should Be $true
        (Get-Content -LiteralPath $settingsPath -Raw) | Should Match '"SkipSiteCacheUpdate"\s*:\s*false'

        Restore-SkipSiteCacheUpdateSetting -Guard $guard
        (Get-Content -LiteralPath $settingsPath -Raw) | Should Match '"SkipSiteCacheUpdate"\s*:\s*true'
    }

    It 'no-ops when SkipSiteCacheUpdate is already false' {
        $settingsPath = Join-Path -Path $TestDrive -ChildPath 'StateTraceSettings.json'
        Set-Content -LiteralPath $settingsPath -Value '{ "SkipSiteCacheUpdate": false }' -Encoding utf8

        $guard = Disable-SkipSiteCacheUpdateSetting -SettingsPath $settingsPath -Label 'Test'
        $guard | Should Not BeNullOrEmpty
        $guard.Changed | Should Be $false
        (Get-Content -LiteralPath $settingsPath -Raw) | Should Match '"SkipSiteCacheUpdate"\s*:\s*false'

        { Restore-SkipSiteCacheUpdateSetting -Guard $guard } | Should Not Throw
        (Get-Content -LiteralPath $settingsPath -Raw) | Should Match '"SkipSiteCacheUpdate"\s*:\s*false'
    }
}
