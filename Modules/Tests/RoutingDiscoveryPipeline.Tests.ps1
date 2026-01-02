Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$pipelinePath = Join-Path -Path $repoRoot -ChildPath 'Tools/Invoke-RoutingDiscoveryPipeline.ps1'
$schemaValidatorPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Test-RoutingSchemas.ps1'
$fixtureRoot = Join-Path -Path $repoRoot -ChildPath 'Tests/Fixtures/Routing'
$schemaRoot = Join-Path -Path $repoRoot -ChildPath 'docs/schemas/routing'

Describe 'Routing discovery pipeline runner' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $pipelinePath)) {
            throw "Pipeline runner not found at $pipelinePath"
        }
        if (-not (Test-Path -LiteralPath $schemaValidatorPath)) {
            throw "Schema validator not found at $schemaValidatorPath"
        }
    }

    It 'runs end-to-end on the capture fixture and updates latest pointer' {
        # LANDMARK: Routing discovery pipeline tests - fixture pass; missing capture fails; latest pointer updates
        $capturePath = Join-Path -Path $fixtureRoot -ChildPath 'RoutingDiscoveryCapture.sample.json'
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'pipeline'
        $result = & $pipelinePath -CapturePath $capturePath -OutputRoot $outputRoot -UpdateLatest -PassThru

        $result.Status | Should Be 'Pass'
        (Test-Path -LiteralPath $result.ArtifactPaths.RouteRecordsPath) | Should Be $true
        (Test-Path -LiteralPath $result.ArtifactPaths.RouteHealthSnapshotPath) | Should Be $true
        (Test-Path -LiteralPath $result.ArtifactPaths.PipelineSummaryLatestPath) | Should Be $true

        $schemaSummaryPath = Join-Path -Path $TestDrive -ChildPath 'schema-summary.json'
        $schemaResult = & $schemaValidatorPath -RouteRecordPath $result.ArtifactPaths.RouteRecordsPath -RouteHealthSnapshotPath $result.ArtifactPaths.RouteHealthSnapshotPath -FixtureRoot $fixtureRoot -SchemaRoot $schemaRoot -OutputPath $schemaSummaryPath -PassThru
        $schemaResult.Status | Should Be 'Pass'
    }

    It 'fails with a clear summary when the capture input is missing' {
        $missingPath = Join-Path -Path $TestDrive -ChildPath 'missing.json'
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'missing-output'
        $timestamp = '20000101-000000'
        $summaryPath = Join-Path -Path $outputRoot -ChildPath ("RoutingDiscoveryPipelineSummary-{0}.json" -f $timestamp)
        $threw = $false

        try {
            & $pipelinePath -CapturePath $missingPath -OutputRoot $outputRoot -Timestamp $timestamp
        } catch {
            $threw = $true
        }

        $threw | Should Be $true
        (Test-Path -LiteralPath $summaryPath) | Should Be $true
        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        $summary.Status | Should Be 'Fail'
        ($summary.Errors -join ';') | Should Match 'MissingCapturePath'
    }
}
