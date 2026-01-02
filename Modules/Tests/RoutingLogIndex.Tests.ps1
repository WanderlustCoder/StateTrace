Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$toolPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Build-RoutingLogIndex.ps1'
$fixtureRoot = Join-Path -Path $repoRoot -ChildPath 'Tests/Fixtures/Routing'
$validationFixture = Join-Path -Path $fixtureRoot -ChildPath 'RealDeviceEvidence/RoutingValidationRunSummary.sample.json'
$pipelineFixture = Join-Path -Path $fixtureRoot -ChildPath 'LogViewer/RoutingDiscoveryPipelineSummary.sample.json'
$diffFixture = Join-Path -Path $fixtureRoot -ChildPath 'RouteDiff/RoutingDiff.sample.json'
$latestPointerPath = Join-Path -Path $repoRoot -ChildPath 'Logs/Reports/RoutingLogIndex/RoutingLogIndex-latest.json'

Describe 'Routing log index' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $toolPath)) {
            throw "Routing log index tool not found at $toolPath"
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

    It 'builds an index with validation, pipeline, and diff entries' {
        # LANDMARK: RoutingDiff support tests - index + render + bundle review diff render
        $rootPath = Join-Path -Path $TestDrive -ChildPath 'logs'
        New-Item -ItemType Directory -Path $rootPath -Force | Out-Null
        Copy-Item -LiteralPath $validationFixture -Destination (Join-Path -Path $rootPath -ChildPath 'RoutingValidationRunSummary-20251229-120000.json') -Force
        Copy-Item -LiteralPath $pipelineFixture -Destination (Join-Path -Path $rootPath -ChildPath 'RoutingDiscoveryPipelineSummary-20251229-120000.json') -Force
        Copy-Item -LiteralPath $diffFixture -Destination (Join-Path -Path $rootPath -ChildPath 'RoutingDiff-20251230-090000.json') -Force

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'index.json'
        $result = & $toolPath -RootPath $rootPath -OutputPath $outputPath -Recurse -PassThru

        $result.Counts.Total | Should Be 3
        $result.Counts.ValidationRuns | Should Be 1
        $result.Counts.Pipelines | Should Be 1
        $result.Counts.Diffs | Should Be 1
        ($result.Entries | Where-Object { $_.Type -eq 'RoutingValidationRunSummary' }).Count | Should Be 1
        ($result.Entries | Where-Object { $_.Type -eq 'RoutingDiscoveryPipelineSummary' }).Count | Should Be 1
        ($result.Entries | Where-Object { $_.Type -eq 'RoutingDiff' }).Count | Should Be 1
    }

    It 'fails when no summary files are found' {
        $rootPath = Join-Path -Path $TestDrive -ChildPath 'empty'
        New-Item -ItemType Directory -Path $rootPath -Force | Out-Null
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'empty-index.json'

        $threw = $false
        try {
            & $toolPath -RootPath $rootPath -OutputPath $outputPath -Recurse | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'No routing summary JSON files'
        }
        $threw | Should Be $true
    }

    It 'writes a latest pointer when requested' {
        $rootPath = Join-Path -Path $TestDrive -ChildPath 'latest'
        New-Item -ItemType Directory -Path $rootPath -Force | Out-Null
        Copy-Item -LiteralPath $validationFixture -Destination (Join-Path -Path $rootPath -ChildPath 'RoutingValidationRunSummary-20251229-120000.json') -Force
        Copy-Item -LiteralPath $pipelineFixture -Destination (Join-Path -Path $rootPath -ChildPath 'RoutingDiscoveryPipelineSummary-20251229-120000.json') -Force

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'latest-index.json'
        & $toolPath -RootPath $rootPath -OutputPath $outputPath -Recurse -UpdateLatest | Out-Null

        Test-Path -LiteralPath $latestPointerPath | Should Be $true
        (Get-Content -LiteralPath $latestPointerPath -Raw) | Should Be (Get-Content -LiteralPath $outputPath -Raw)
    }
}
