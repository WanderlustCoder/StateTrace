Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools/New-TelemetryBundle.ps1'

Describe 'Telemetry bundle risk register references' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            throw "Telemetry bundle script not found at $scriptPath"
        }
    }

    It 'writes risk register entries to README and manifest' {
        # LANDMARK: Telemetry bundle risk register tests - README + manifest entries
        $artifact = Join-Path -Path $TestDrive -ChildPath 'artifact.json'
        Set-Content -LiteralPath $artifact -Value '{}' -Encoding utf8

        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'Bundles'
        $bundleName = "RiskRegisterTest-$([Guid]::NewGuid().ToString('N'))"
        $riskEntries = @('RR-001', 'RR-002')

        $result = & $scriptPath -BundleName $bundleName -OutputRoot $outputRoot -AllowCustomOutputRoot -AdditionalPath $artifact -RiskRegisterEntries $riskEntries -PassThru

        $readmePath = Join-Path -Path $result.Path -ChildPath 'README.md'
        $readme = Get-Content -LiteralPath $readmePath -Raw
        $readme | Should Match 'Risk Register: RR-001, RR-002'

        $manifest = Get-Content -LiteralPath $result.Manifest -Raw | ConvertFrom-Json
        $manifest.RiskRegisterEntries.Count | Should Be 2
        ($manifest.RiskRegisterEntries -contains 'RR-001') | Should Be $true
    }
}
