Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$toolPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Compare-RouteHealthSnapshots.ps1'
$fixtureRoot = Join-Path -Path $repoRoot -ChildPath 'Tests/Fixtures/Routing/RouteDiff'
$oldSnapshot = Join-Path -Path $fixtureRoot -ChildPath 'RouteHealthSnapshot.old.json'
$newSnapshot = Join-Path -Path $fixtureRoot -ChildPath 'RouteHealthSnapshot.new.json'
$oldRecords = Join-Path -Path $fixtureRoot -ChildPath 'RouteRecords.old.json'
$newRecords = Join-Path -Path $fixtureRoot -ChildPath 'RouteRecords.new.json'

Describe 'Route health snapshot diff' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $toolPath)) {
            throw "Route health diff tool not found at $toolPath"
        }
        if (-not (Test-Path -LiteralPath $oldSnapshot)) {
            throw "Old snapshot fixture not found at $oldSnapshot"
        }
        if (-not (Test-Path -LiteralPath $newSnapshot)) {
            throw "New snapshot fixture not found at $newSnapshot"
        }
        if (-not (Test-Path -LiteralPath $oldRecords)) {
            throw "Old route records fixture not found at $oldRecords"
        }
        if (-not (Test-Path -LiteralPath $newRecords)) {
            throw "New route records fixture not found at $newRecords"
        }
    }

    It 'diffs snapshots with enrichment' {
        # LANDMARK: Routing diff tests - enriched changes, unenriched fallback, and mismatch failures
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'RoutingDiff.json'
        $result = & $toolPath `
            -OldSnapshotPath $oldSnapshot `
            -NewSnapshotPath $newSnapshot `
            -OldRouteRecordsPath $oldRecords `
            -NewRouteRecordsPath $newRecords `
            -OutputPath $outputPath `
            -PassThru

        $result.Status | Should Be 'Pass'
        $result.Counts.Added | Should Be 1
        $result.Counts.Removed | Should Be 1
        $result.Counts.ChangedRoutes | Should BeGreaterThan 0
    }

    It 'diffs snapshots without enrichment' {
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'RoutingDiff-NoEnrich.json'
        $result = & $toolPath `
            -OldSnapshotPath $oldSnapshot `
            -NewSnapshotPath $newSnapshot `
            -OutputPath $outputPath `
            -PassThru

        $result.Status | Should Be 'Pass'
        $result.Counts.Added | Should Be 1
        $result.Counts.Removed | Should Be 1
        $result.Counts.ChangedRoutes | Should Be 0
        @($result.Changes.AddedRouteRecordIds).Count | Should Be 1
        @($result.Changes.RemovedRouteRecordIds).Count | Should Be 1
    }

    It 'fails when targets do not match without override' {
        $mismatchPath = Join-Path -Path $TestDrive -ChildPath 'RouteHealthSnapshot-mismatch.json'
        $payload = Get-Content -LiteralPath $newSnapshot -Raw | ConvertFrom-Json
        $payload.Site = 'MISMATCH'
        $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $mismatchPath -Encoding UTF8

        $threw = $false
        try {
            & $toolPath -OldSnapshotPath $oldSnapshot -NewSnapshotPath $mismatchPath -OutputPath (Join-Path $TestDrive 'RoutingDiff-mismatch.json') | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'targets do not match'
            $_.Exception.Message | Should Match 'AllowDifferentTargets'
        }
        $threw | Should Be $true
    }

    It 'writes the latest pointer when requested' {
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'RoutingDiff-latest.json'
        $latestPointerPath = Join-Path -Path $repoRoot -ChildPath 'Logs/Reports/RoutingDiff/RoutingDiff-latest.json'

        & $toolPath `
            -OldSnapshotPath $oldSnapshot `
            -NewSnapshotPath $newSnapshot `
            -OutputPath $outputPath `
            -UpdateLatest `
            -PassThru | Out-Null

        (Test-Path -LiteralPath $latestPointerPath) | Should Be $true
    }
}
