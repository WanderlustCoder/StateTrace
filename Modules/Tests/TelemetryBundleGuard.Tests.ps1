Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools/New-TelemetryBundle.ps1'

Describe 'New-TelemetryBundle output root guard' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            throw "Telemetry bundle script not found at $scriptPath"
        }
    }

    It 'blocks output roots outside Logs/TelemetryBundles unless override is set' {
        # LANDMARK: Telemetry bundle output guard tests - reject non-canonical root
        $artifact = Join-Path -Path $TestDrive -ChildPath 'artifact.json'
        Set-Content -LiteralPath $artifact -Value '{}' -Encoding utf8

        $customRoot = Join-Path -Path $TestDrive -ChildPath 'Bundles'
        $bundleName = 'GuardTest-Outside'

        $threw = $false
        try {
            & $scriptPath -BundleName $bundleName -OutputRoot $customRoot -AdditionalPath $artifact
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'OutputRoot'
        }

        $threw | Should Be $true
    }

    It 'allows custom output roots when explicitly opted in' {
        $artifact = Join-Path -Path $TestDrive -ChildPath 'artifact-allowed.json'
        Set-Content -LiteralPath $artifact -Value '{}' -Encoding utf8

        $customRoot = Join-Path -Path $TestDrive -ChildPath 'BundlesAllowed'
        $bundleName = 'GuardTest-Allowed'
        $bundlePath = Join-Path -Path $customRoot -ChildPath $bundleName

        & $scriptPath -BundleName $bundleName -OutputRoot $customRoot -AllowCustomOutputRoot -AdditionalPath $artifact

        Test-Path -LiteralPath $bundlePath | Should Be $true
        Remove-Item -LiteralPath $bundlePath -Recurse -Force
    }

    It 'allows canonical output root without override' {
        $artifact = Join-Path -Path $TestDrive -ChildPath 'artifact-canonical.json'
        Set-Content -LiteralPath $artifact -Value '{}' -Encoding utf8

        $canonicalRoot = Join-Path -Path $repoRoot -ChildPath 'Logs/TelemetryBundles'
        $bundleName = "GuardTest-$([Guid]::NewGuid().ToString('N'))"
        $bundlePath = Join-Path -Path $canonicalRoot -ChildPath $bundleName

        & $scriptPath -BundleName $bundleName -OutputRoot $canonicalRoot -AdditionalPath $artifact

        Test-Path -LiteralPath $bundlePath | Should Be $true
        Remove-Item -LiteralPath $bundlePath -Recurse -Force
    }
}
