Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$converterPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Convert-RouteRecordsToHealthSnapshot.ps1'
$schemaValidatorPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Test-RoutingSchemas.ps1'
$fixtureRoot = Join-Path -Path $repoRoot -ChildPath 'Tests/Fixtures/Routing'
$schemaRoot = Join-Path -Path $repoRoot -ChildPath 'docs/schemas/routing'

Describe 'Route health snapshot generator' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $converterPath)) {
            throw "Route health generator not found at $converterPath"
        }
        if (-not (Test-Path -LiteralPath $schemaValidatorPath)) {
            throw "Schema validator not found at $schemaValidatorPath"
        }
    }

    It 'generates a schema-valid snapshot from fixture RouteRecords' {
        # LANDMARK: Route health snapshot tests - fixture pass; missing fields; degraded rule
        $recordsPath = Join-Path -Path $fixtureRoot -ChildPath 'RouteRecords.sample.json'
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'snapshot.json'
        $summaryPath = Join-Path -Path $TestDrive -ChildPath 'summary.json'

        $result = & $converterPath -RouteRecordsPath $recordsPath -Site 'WLLS' -Hostname 'WLLS-A01-AS-01' -Vrf 'default' -OutputPath $outputPath -SummaryPath $summaryPath -PassThru

        $result.Status | Should Be 'Pass'
        (Test-Path -LiteralPath $outputPath) | Should Be $true

        $schemaSummaryPath = Join-Path -Path $TestDrive -ChildPath 'schema-summary.json'
        $schemaResult = & $schemaValidatorPath -RouteHealthSnapshotPath $outputPath -FixtureRoot $fixtureRoot -SchemaRoot $schemaRoot -OutputPath $schemaSummaryPath -PassThru
        $schemaResult.RouteHealthSnapshot.Status | Should Be 'Pass'

        $expectedPath = Join-Path -Path $fixtureRoot -ChildPath 'RouteHealthSnapshot.expected.json'
        $expected = Get-Content -LiteralPath $expectedPath -Raw | ConvertFrom-Json
        $actual = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
        $actual.SnapshotId | Should Be $expected.SnapshotId
        $actual.PrimaryRouteStatus | Should Be $expected.PrimaryRouteStatus
        $actual.SecondaryRouteStatus | Should Be $expected.SecondaryRouteStatus
        $actual.HealthState | Should Be $expected.HealthState
        $actual.DetectionLatencyMs | Should Be $expected.DetectionLatencyMs
        ($actual.RouteRecordIds -join ',') | Should Be ($expected.RouteRecordIds -join ',')
    }

    It 'fails when a required RouteRecord field is missing' {
        $records = Get-Content -LiteralPath (Join-Path $fixtureRoot 'RouteRecords.sample.json') -Raw | ConvertFrom-Json
        $records[0].PSObject.Properties.Remove('RouteState')
        $recordsPath = Join-Path -Path $TestDrive -ChildPath 'records-missing.json'
        $records | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $recordsPath -Encoding utf8

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'snapshot-missing.json'
        $summaryPath = Join-Path -Path $TestDrive -ChildPath 'summary-missing.json'
        $threw = $false
        try {
            & $converterPath -RouteRecordsPath $recordsPath -Site 'WLLS' -Hostname 'WLLS-A01-AS-01' -Vrf 'default' -OutputPath $outputPath -SummaryPath $summaryPath
        } catch {
            $threw = $true
        }

        $threw | Should Be $true
        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        ($summary.Errors -join ';') | Should Match 'MissingRequiredField:Record\[0\].RouteState'
    }

    It 'marks primary down + secondary up as Warning/Degraded' {
        $records = Get-Content -LiteralPath (Join-Path $fixtureRoot 'RouteRecords.sample.json') -Raw | ConvertFrom-Json
        $records[0].RouteState = 'Inactive'
        $records[1].RouteState = 'Active'
        $recordsPath = Join-Path -Path $TestDrive -ChildPath 'records-degraded.json'
        $records | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $recordsPath -Encoding utf8

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'snapshot-degraded.json'
        $summaryPath = Join-Path -Path $TestDrive -ChildPath 'summary-degraded.json'
        $result = & $converterPath -RouteRecordsPath $recordsPath -Site 'WLLS' -Hostname 'WLLS-A01-AS-01' -Vrf 'default' -OutputPath $outputPath -SummaryPath $summaryPath -PassThru

        $result.HealthState | Should Be 'Warning'
        $result.PrimaryRouteStatus | Should Be 'Degraded'
        $result.SecondaryRouteStatus | Should Be 'Up'
    }
}
