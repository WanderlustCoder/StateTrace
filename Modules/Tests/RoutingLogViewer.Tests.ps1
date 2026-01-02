Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$viewerPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Show-RoutingLogSummary.ps1'
$fixtureRoot = Join-Path -Path $repoRoot -ChildPath 'Tests/Fixtures/Routing'
$validationFixture = Join-Path -Path $fixtureRoot -ChildPath 'RealDeviceEvidence/RoutingValidationRunSummary.sample.json'
$pipelineFixture = Join-Path -Path $fixtureRoot -ChildPath 'LogViewer/RoutingDiscoveryPipelineSummary.sample.json'
$diffFixture = Join-Path -Path $fixtureRoot -ChildPath 'RouteDiff/RoutingDiff.sample.json'

Describe 'Routing log viewer' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $viewerPath)) {
            throw "Viewer tool not found at $viewerPath"
        }
        if (-not (Test-Path -LiteralPath $validationFixture)) {
            throw "Validation summary fixture not found at $validationFixture"
        }
        if (-not (Test-Path -LiteralPath $pipelineFixture)) {
            throw "Pipeline summary fixture not found at $pipelineFixture"
        }
        if (-not (Test-Path -LiteralPath $diffFixture)) {
            throw "Routing diff fixture not found at $diffFixture"
        }
    }

    It 'renders routing validation run summaries' {
        # LANDMARK: Offline routing log viewer tests - summary detection, rendering, and output formats
        $result = & $viewerPath -Path $validationFixture -PassThru
        $result.SummaryType | Should Be 'RoutingValidationRunSummary'
        $result.Status | Should Be 'Pass'
        $result.HostCount | Should Be 1
    }

    It 'renders routing discovery pipeline summaries' {
        $result = & $viewerPath -Path $pipelineFixture -PassThru
        $result.SummaryType | Should Be 'RoutingDiscoveryPipelineSummary'
        $result.Status | Should Be 'Pass'
        $result.HostCount | Should Be 1
    }

    It 'writes markdown output with a host table' {
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'summary.md'
        & $viewerPath -Path $validationFixture -Format Markdown -OutputPath $outputPath | Out-Null
        $content = Get-Content -LiteralPath $outputPath -Raw
        $content | Should Match '\\| Hostname \\| Status \\|'
    }

    It 'renders routing diff summaries to markdown' {
        # LANDMARK: RoutingDiff support tests - index + render + bundle review diff render
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'diff.md'
        $result = & $viewerPath -Path $diffFixture -Format Markdown -OutputPath $outputPath -PassThru
        $result.SummaryType | Should Be 'RoutingDiff'
        $content = Get-Content -LiteralPath $outputPath -Raw
        $content | Should Match 'Routing Diff'
    }

    It 'fails on unsupported summary JSON' {
        $unknownPath = Join-Path -Path $TestDrive -ChildPath 'unknown.json'
        Set-Content -LiteralPath $unknownPath -Value '{}' -Encoding UTF8

        $threw = $false
        try {
            & $viewerPath -Path $unknownPath -PassThru | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'Unsupported summary format'
        }
        $threw | Should Be $true
    }
}
