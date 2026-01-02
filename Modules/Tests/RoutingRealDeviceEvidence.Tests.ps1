Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$toolPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Test-RoutingRealDeviceEvidence.ps1'
$fixtureEvidence = Join-Path -Path $repoRoot -ChildPath 'Tests/Fixtures/Routing/RealDeviceEvidence/OperatorEvidence.sample.md'

Describe 'Routing real device evidence validation' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $toolPath)) {
            throw "Evidence validator not found at $toolPath"
        }
        if (-not (Test-Path -LiteralPath $fixtureEvidence)) {
            throw "Fixture evidence not found at $fixtureEvidence"
        }
    }

    It 'valid evidence passes validation' {
        # LANDMARK: Online evidence validation tests - valid evidence passes
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'evidence.json'
        $result = & $toolPath -EvidencePath $fixtureEvidence -OutputPath $outputPath -PassThru

        $result.Status | Should Be 'Pass'
        (Test-Path -LiteralPath $outputPath) | Should Be $true
    }

    It 'missing artifact path fails validation' {
        # LANDMARK: Online evidence validation tests - missing artifact fails
        $brokenEvidence = Join-Path -Path $TestDrive -ChildPath 'evidence-missing.md'
        $content = Get-Content -LiteralPath $fixtureEvidence
        $content = $content -replace 'OperatorRun.sample.log', 'MissingOperatorRun.log'
        $content | Set-Content -LiteralPath $brokenEvidence -Encoding utf8

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'missing-artifact.json'
        $threw = $false
        try {
            & $toolPath -EvidencePath $brokenEvidence -OutputPath $outputPath -PassThru
        } catch {
            $threw = $true
        }

        $threw | Should Be $true
        $summary = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
        $summary.Status | Should Be 'Fail'
    }

    It 'missing required sections fails validation' {
        # LANDMARK: Online evidence validation tests - missing sections fail
        $brokenEvidence = Join-Path -Path $TestDrive -ChildPath 'evidence-no-artifacts.md'
        @(
            '# Evidence',
            '',
            '## Metadata',
            '- Date/time (local): 2025-12-29',
            '- Operator: Test',
            '- Site(s): WLLS',
            '- Vendor(s): CiscoIOSXE',
            '- VRF(s): default',
            '',
            '## Commands Executed',
            '- `pwsh -NoProfile -File Tools/Test-RoutingOnlineCaptureReadiness.ps1`'
        ) | Set-Content -LiteralPath $brokenEvidence -Encoding utf8

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'missing-section.json'
        $threw = $false
        try {
            & $toolPath -EvidencePath $brokenEvidence -OutputPath $outputPath -PassThru
        } catch {
            $threw = $true
        }

        $threw | Should Be $true
        $summary = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
        $summary.Status | Should Be 'Fail'
    }
}
