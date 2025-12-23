Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$guardModulePath = Join-Path -Path $repoRoot -ChildPath 'Tools\SkipSiteCacheUpdateGuard.psm1'

Describe 'SkipSiteCacheUpdateGuard' {
    $envVarName = 'STATETRACE_SKIP_SITECACHE_UPDATE'
    $originalEnvValue = $null
    $envWasSet = $false

    BeforeAll {
        if (-not (Test-Path -LiteralPath $guardModulePath)) {
            throw "Guard module not found at $guardModulePath"
        }
        Import-Module -Name $guardModulePath -Force
    }

    BeforeEach {
        $envWasSet = $false
        $originalEnvValue = $null
        $envPath = "Env:{0}" -f $envVarName
        if (Test-Path -LiteralPath $envPath) {
            $envWasSet = $true
            $originalEnvValue = (Get-Item -LiteralPath $envPath).Value
        }
    }

    AfterEach {
        $envPath = "Env:{0}" -f $envVarName
        if ($envWasSet) {
            Set-Item -LiteralPath $envPath -Value $originalEnvValue
        } else {
            Remove-Item -LiteralPath $envPath -ErrorAction SilentlyContinue
        }
    }

    It 'disables and restores when SkipSiteCacheUpdate is true' {
        $settingsPath = Join-Path -Path $TestDrive -ChildPath 'StateTraceSettings.json'
        Set-Content -LiteralPath $settingsPath -Value '{ "SkipSiteCacheUpdate": true, "Other": 1 }' -Encoding utf8
        Set-Item -LiteralPath $envPath -Value '1'

        $guard = Disable-SkipSiteCacheUpdateSetting -SettingsPath $settingsPath -Label 'Test'
        $guard | Should Not BeNullOrEmpty
        $guard.Changed | Should Be $true
        $guard.EnvVarChanged | Should Be $true
        (Get-Content -LiteralPath $settingsPath -Raw) | Should Match '"SkipSiteCacheUpdate"\s*:\s*false'
        (Get-Item -LiteralPath $envPath).Value | Should Be '0'

        Restore-SkipSiteCacheUpdateSetting -Guard $guard
        (Get-Content -LiteralPath $settingsPath -Raw) | Should Match '"SkipSiteCacheUpdate"\s*:\s*true'
        (Get-Item -LiteralPath $envPath).Value | Should Be '1'
    }

    It 'no-ops when SkipSiteCacheUpdate is already false' {
        $settingsPath = Join-Path -Path $TestDrive -ChildPath 'StateTraceSettings.json'
        Set-Content -LiteralPath $settingsPath -Value '{ "SkipSiteCacheUpdate": false }' -Encoding utf8
        Set-Item -LiteralPath $envPath -Value '1'

        $guard = Disable-SkipSiteCacheUpdateSetting -SettingsPath $settingsPath -Label 'Test'
        $guard | Should Not BeNullOrEmpty
        $guard.Changed | Should Be $false
        $guard.EnvVarChanged | Should Be $true
        (Get-Content -LiteralPath $settingsPath -Raw) | Should Match '"SkipSiteCacheUpdate"\s*:\s*false'
        (Get-Item -LiteralPath $envPath).Value | Should Be '0'

        { Restore-SkipSiteCacheUpdateSetting -Guard $guard } | Should Not Throw
        (Get-Content -LiteralPath $settingsPath -Raw) | Should Match '"SkipSiteCacheUpdate"\s*:\s*false'
        (Get-Item -LiteralPath $envPath).Value | Should Be '1'
    }
}
