Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$converterPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Convert-RoutingDiscoveryCapture.ps1'
$schemaValidatorPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Test-RoutingSchemas.ps1'
$fixtureRoot = Join-Path -Path $repoRoot -ChildPath 'Tests/Fixtures/Routing'
$schemaRoot = Join-Path -Path $repoRoot -ChildPath 'docs/schemas/routing'

Describe 'Routing discovery capture conversion' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $converterPath)) {
            throw "Conversion script not found at $converterPath"
        }
        if (-not (Test-Path -LiteralPath $schemaValidatorPath)) {
            throw "Schema validator not found at $schemaValidatorPath"
        }
    }

    It 'converts the fixture capture and passes schema validation' {
        # LANDMARK: Routing discovery conversion tests - fixture pass; missing fields fail
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'RouteRecords.json'
        $summaryPath = Join-Path -Path $TestDrive -ChildPath 'summary.json'
        $capturePath = Join-Path -Path $fixtureRoot -ChildPath 'RoutingDiscoveryCapture.sample.json'

        $result = & $converterPath -CapturePath $capturePath -RouteRecordOutputPath $outputPath -SummaryPath $summaryPath -PassThru

        $result.Status | Should Be 'Pass'
        (Test-Path -LiteralPath $outputPath) | Should Be $true

        $schemaOutput = Join-Path -Path $TestDrive -ChildPath 'schema-summary.json'
        $schemaResult = & $schemaValidatorPath -RouteRecordPath $outputPath -FixtureRoot $fixtureRoot -SchemaRoot $schemaRoot -OutputPath $schemaOutput -PassThru
        $schemaResult.RouteRecord.Status | Should Be 'Pass'
    }

    It 'fails when a required capture field is missing' {
        $capture = Get-Content -LiteralPath (Join-Path $fixtureRoot 'RoutingDiscoveryCapture.sample.json') -Raw | ConvertFrom-Json
        $capture.PSObject.Properties.Remove('Hostname')
        $capturePath = Join-Path -Path $TestDrive -ChildPath 'capture-missing.json'
        $capture | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $capturePath -Encoding utf8

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'records-missing.json'
        $summaryPath = Join-Path -Path $TestDrive -ChildPath 'summary-missing.json'
        $threw = $false
        try {
            & $converterPath -CapturePath $capturePath -RouteRecordOutputPath $outputPath -SummaryPath $summaryPath
        } catch {
            $threw = $true
        }

        $threw | Should Be $true
        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        ($summary.Errors -join ';') | Should Match 'MissingRequiredField:Hostname'
    }

    It 'fails when a required route field is missing' {
        $capture = Get-Content -LiteralPath (Join-Path $fixtureRoot 'RoutingDiscoveryCapture.sample.json') -Raw | ConvertFrom-Json
        $capture.Routes[0].PSObject.Properties.Remove('PrefixLength')
        $capturePath = Join-Path -Path $TestDrive -ChildPath 'capture-route-missing.json'
        $capture | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $capturePath -Encoding utf8

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'records-route-missing.json'
        $summaryPath = Join-Path -Path $TestDrive -ChildPath 'summary-route-missing.json'
        $threw = $false
        try {
            & $converterPath -CapturePath $capturePath -RouteRecordOutputPath $outputPath -SummaryPath $summaryPath
        } catch {
            $threw = $true
        }

        $threw | Should Be $true
        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        ($summary.Errors -contains 'MissingRequiredField:Route[0].PrefixLength') | Should Be $true
    }
}
