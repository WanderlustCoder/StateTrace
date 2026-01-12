Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Test-RoutingSchemas.ps1'
$fixtureRoot = Join-Path -Path $repoRoot -ChildPath 'Tests/Fixtures/Routing'
$schemaRoot = Join-Path -Path $repoRoot -ChildPath 'docs/schemas/routing'

Describe 'Routing schema validator' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            throw "Routing schema validator not found at $scriptPath"
        }
    }

    It 'passes with valid fixtures' {
        # LANDMARK: Routing schemas tests - fixtures pass; missing fields/version fail
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'summary.json'

        $result = & $scriptPath -FixtureRoot $fixtureRoot -SchemaRoot $schemaRoot -OutputPath $outputPath -PassThru

        $result.Status | Should Be 'Pass'
        $result.RouteRecord.Status | Should Be 'Pass'
        $result.RouteHealthSnapshot.Status | Should Be 'Pass'
    }

    It 'fails when a required field is missing' {
        $record = Get-Content -LiteralPath (Join-Path $fixtureRoot 'RouteRecord.sample.json') -Raw | ConvertFrom-Json
        $record.PSObject.Properties.Remove('NextHop')
        $recordPath = Join-Path -Path $TestDrive -ChildPath 'RouteRecord-missing.json'
        $record | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $recordPath -Encoding utf8

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'summary-missing.json'
        $threw = $false
        try {
            & $scriptPath -RouteRecordPath $recordPath -FixtureRoot $fixtureRoot -SchemaRoot $schemaRoot -OutputPath $outputPath
        } catch {
            $threw = $true
        }

        $threw | Should Be $true
        $summary = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
        ($summary.RouteRecord.Errors -join ';') | Should Match 'MissingRequiredField:NextHop'
    }

    It 'fails when schema versions do not match' {
        $snapshot = Get-Content -LiteralPath (Join-Path $fixtureRoot 'RouteHealthSnapshot.sample.json') -Raw | ConvertFrom-Json
        $snapshot.SchemaVersion = '2.0'
        $snapshotPath = Join-Path -Path $TestDrive -ChildPath 'RouteHealthSnapshot-mismatch.json'
        $snapshot | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $snapshotPath -Encoding utf8

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'summary-mismatch.json'
        $threw = $false
        try {
            & $scriptPath -RouteHealthSnapshotPath $snapshotPath -FixtureRoot $fixtureRoot -SchemaRoot $schemaRoot -OutputPath $outputPath
        } catch {
            $threw = $true
        }

        $threw | Should Be $true
        $summary = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
        ($summary.RouteHealthSnapshot.Errors -join ';') | Should Match 'SchemaVersionMismatch'
    }
}
