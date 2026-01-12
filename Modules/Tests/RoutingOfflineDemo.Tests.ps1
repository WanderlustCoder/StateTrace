Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$toolPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Invoke-RoutingOfflineDemo.ps1'

Describe 'Routing offline demo' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $toolPath)) {
            throw "Routing offline demo tool not found at $toolPath"
        }
    }

    It 'runs the offline demo with deterministic outputs' {
        # LANDMARK: Offline demo tests - deterministic outputs, overwrite semantics, and required artifacts
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'demo'
        $timestamp = '20251231-150000'

        & $toolPath -OutputRoot $outputRoot -Timestamp $timestamp -PassThru | Out-Null

        $runRoot = Join-Path -Path $outputRoot -ChildPath ("Run-{0}" -f $timestamp)
        $summaryPath = Join-Path -Path $runRoot -ChildPath ("RoutingOfflineDemoSummary-{0}.json" -f $timestamp)
        (Test-Path -LiteralPath $summaryPath) | Should Be $true

        $bundleZipPath = Join-Path -Path $runRoot -ChildPath ("Bundles\RoutingBundle-Diff-{0}.zip" -f $timestamp)
        (Test-Path -LiteralPath $bundleZipPath) | Should Be $true

        $reviewExplorerPath = Join-Path -Path $runRoot -ChildPath 'Review\Workspace\Outputs\RoutingLogExplorer-latest.md'
        (Test-Path -LiteralPath $reviewExplorerPath) | Should Be $true

        $outputsRoot = Join-Path -Path $runRoot -ChildPath 'Outputs'
        (Test-Path -LiteralPath (Join-Path -Path $outputsRoot -ChildPath ("RoutingDiff-{0}.md" -f $timestamp))) | Should Be $true
        (Test-Path -LiteralPath (Join-Path -Path $outputsRoot -ChildPath ("RoutingBundleReview-{0}.json" -f $timestamp))) | Should Be $true
        (Test-Path -LiteralPath (Join-Path -Path $outputsRoot -ChildPath 'RoutingLogExplorer-latest.md')) | Should Be $true
    }

    It 'requires -Overwrite when reusing a timestamp' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'overwrite'
        $timestamp = '20251231-160000'

        & $toolPath -OutputRoot $outputRoot -Timestamp $timestamp | Out-Null

        $threw = $false
        try {
            & $toolPath -OutputRoot $outputRoot -Timestamp $timestamp | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'Overwrite'
        }
        $threw | Should Be $true

        & $toolPath -OutputRoot $outputRoot -Timestamp $timestamp -Overwrite | Out-Null
    }
}
