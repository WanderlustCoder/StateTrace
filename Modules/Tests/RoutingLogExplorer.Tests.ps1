Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$toolPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Invoke-RoutingLogExplorer.ps1'
$fixtureRoot = Join-Path -Path $repoRoot -ChildPath 'Tests/Fixtures/Routing/LogExplorer'
$compareFixtureRoot = Join-Path -Path $fixtureRoot -ChildPath 'Compare'
$latestCompareFixtureRoot = Join-Path -Path $fixtureRoot -ChildPath 'LatestCompare'
$indexFixture = Join-Path -Path $fixtureRoot -ChildPath 'Index.sample.json'
$latestCompareIndexFixture = Join-Path -Path $latestCompareFixtureRoot -ChildPath 'Index.latestcompare.sample.json'
$validationFixture = Join-Path -Path $fixtureRoot -ChildPath 'RoutingValidationRunSummary.sample.json'
$pipelineFixture = Join-Path -Path $fixtureRoot -ChildPath 'RoutingDiscoveryPipelineSummary.sample.json'
$compareNewSummary = Join-Path -Path $compareFixtureRoot -ChildPath 'RoutingDiscoveryPipelineSummary.new.json'
$compareOldSummary = Join-Path -Path $compareFixtureRoot -ChildPath 'RoutingDiscoveryPipelineSummary.old.json'
$compareMissingSummary = Join-Path -Path $compareFixtureRoot -ChildPath 'RoutingDiscoveryPipelineSummary.missingSnapshot.json'
$latestCompareNewSummary = Join-Path -Path $latestCompareFixtureRoot -ChildPath 'RoutingDiscoveryPipelineSummary.latest.json'
$latestCompareOldSummary = Join-Path -Path $latestCompareFixtureRoot -ChildPath 'RoutingDiscoveryPipelineSummary.previous.json'

Describe 'Routing log explorer' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $toolPath)) {
            throw "Routing log explorer tool not found at $toolPath"
        }
        if (-not (Test-Path -LiteralPath $indexFixture)) {
            throw "Index fixture not found at $indexFixture"
        }
        if (-not (Test-Path -LiteralPath $latestCompareIndexFixture)) {
            throw "Latest compare index fixture not found at $latestCompareIndexFixture"
        }
        if (-not (Test-Path -LiteralPath $validationFixture)) {
            throw "Validation summary fixture not found at $validationFixture"  
        }
        if (-not (Test-Path -LiteralPath $pipelineFixture)) {
            throw "Pipeline summary fixture not found at $pipelineFixture"
        }
        if (-not (Test-Path -LiteralPath $compareNewSummary)) {
            throw "Compare new summary fixture not found at $compareNewSummary"
        }
        if (-not (Test-Path -LiteralPath $compareOldSummary)) {
            throw "Compare old summary fixture not found at $compareOldSummary"
        }
        if (-not (Test-Path -LiteralPath $compareMissingSummary)) {
            throw "Compare missing snapshot fixture not found at $compareMissingSummary"
        }
        if (-not (Test-Path -LiteralPath $latestCompareNewSummary)) {
            throw "Latest compare new summary fixture not found at $latestCompareNewSummary"
        }
        if (-not (Test-Path -LiteralPath $latestCompareOldSummary)) {
            throw "Latest compare old summary fixture not found at $latestCompareOldSummary"
        }
    }

    It 'lists matching entries when ListOnly is set' {
        # LANDMARK: Routing log explorer tests - filter/list/select semantics and error paths
        $indexPath = Join-Path -Path $TestDrive -ChildPath 'RoutingLogIndex.json'
        $entries = @(
            [pscustomobject]@{
                Type      = 'RoutingValidationRunSummary'
                Timestamp = '2025-12-30T10:00:00Z'
                Status    = 'Pass'
                Site      = 'LAB'
                Vendor    = 'CiscoIOSXE'
                Vrf       = 'default'
                Path      = $validationFixture
            },
            [pscustomobject]@{
                Type      = 'RoutingDiscoveryPipelineSummary'
                Timestamp = '2025-12-30T09:00:00Z'
                Status    = 'Fail'
                Site      = 'LAB'
                Vendor    = 'AristaEOS'
                Vrf       = 'default'
                Path      = $pipelineFixture
            },
            [pscustomobject]@{
                Type      = 'RoutingValidationRunSummary'
                Timestamp = '2025-12-30T08:00:00Z'
                Status    = 'Fail'
                Site      = 'LAB'
                Vendor    = 'CiscoIOSXE'
                Vrf       = 'default'
                Path      = $validationFixture
            }
        )
        $indexPayload = [pscustomobject]@{
            SchemaVersion = '1.0'
            GeneratedAt   = '2025-12-30T10:30:00Z'
            Entries       = $entries
        }
        $indexPayload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $indexPath -Encoding UTF8

        $result = & $toolPath -IndexPath $indexPath -ListOnly -PassThru
        @($result).Count | Should Be 3
    }

    It 'filters by type and status' {
        $result = & $toolPath -IndexPath $indexFixture -Type RoutingValidationRun -Status Pass -ListOnly -PassThru
        @($result).Count | Should Be 1
        $result.Type | Should Be 'RoutingValidationRun'
        $result.Status | Should Be 'Pass'
    }

    It 'selects an entry and renders a summary' {
        $result = & $toolPath -IndexPath $indexFixture -Select 1 -PassThru
        $result.SummaryType | Should Be 'RoutingDiscoveryPipelineSummary'
        $result.Status | Should Be 'Pass'
    }

    It 'fails on an out-of-range selection' {
        $threw = $false
        try {
            & $toolPath -IndexPath $indexFixture -Select 5 | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'Valid range'
        }
        $threw | Should Be $true
    }

    It 'compares with the previous entry and writes a diff report' {
        # LANDMARK: Explorer compare mode tests - previous selection, artifact extraction, and failure paths
        $indexPath = Join-Path -Path $TestDrive -ChildPath 'RoutingLogIndex.json'
        $diffJson = Join-Path -Path $TestDrive -ChildPath 'RoutingDiff.json'
        $diffMarkdown = Join-Path -Path $TestDrive -ChildPath 'RoutingDiff.md'
        $entries = @(
            [pscustomobject]@{
                Type      = 'RoutingDiscoveryPipelineSummary'
                Timestamp = '2025-12-30T11:00:00Z'
                Status    = 'Pass'
                Site      = 'WLLS'
                Hostname  = 'WLLS-A01-AS-01'
                Vendor    = 'CiscoIOSXE'
                Vrf       = 'default'
                Path      = $compareNewSummary
            },
            [pscustomobject]@{
                Type      = 'RoutingDiscoveryPipelineSummary'
                Timestamp = '2025-12-30T10:30:00Z'
                Status    = 'Pass'
                Site      = 'WLLS'
                Hostname  = 'WLLS-A01-AS-01'
                Vendor    = 'CiscoIOSXE'
                Vrf       = 'default'
                Path      = $compareOldSummary
            }
        )
        $indexPayload = [pscustomobject]@{
            SchemaVersion = '1.0'
            GeneratedAt   = '2025-12-30T11:30:00Z'
            Entries       = $entries
        }
        $indexPayload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $indexPath -Encoding UTF8

        & $toolPath -IndexPath $indexPath -Select 0 -CompareWithPrevious -DiffOutputPath $diffJson -DiffMarkdownPath $diffMarkdown -PassThru | Out-Null
        (Test-Path -LiteralPath $diffJson) | Should Be $true
        (Test-Path -LiteralPath $diffMarkdown) | Should Be $true
        $diffPayload = Get-Content -LiteralPath $diffJson -Raw | ConvertFrom-Json
        $diffPayload.Changes.Health | Should Not Be $null
        $diffPayload.Counts | Should Not Be $null
    }

    It 'fails when no previous entry exists for compare' {
        $indexPath = Join-Path -Path $TestDrive -ChildPath 'RoutingLogIndex-no-prev.json'
        $entries = @(
            [pscustomobject]@{
                Type      = 'RoutingDiscoveryPipelineSummary'
                Timestamp = '2025-12-30T11:00:00Z'
                Status    = 'Pass'
                Site      = 'WLLS'
                Hostname  = 'WLLS-A01-AS-01'
                Vendor    = 'CiscoIOSXE'
                Vrf       = 'default'
                Path      = $compareNewSummary
            }
        )
        $indexPayload = [pscustomobject]@{
            SchemaVersion = '1.0'
            GeneratedAt   = '2025-12-30T11:30:00Z'
            Entries       = $entries
        }
        $indexPayload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $indexPath -Encoding UTF8

        $threw = $false
        try {
            & $toolPath -IndexPath $indexPath -Select 0 -CompareWithPrevious | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'No previous entry'
        }
        $threw | Should Be $true
    }

    It 'fails when the summary is missing RouteHealthSnapshotPath' {
        $indexPath = Join-Path -Path $TestDrive -ChildPath 'RoutingLogIndex-missing.json'
        $entries = @(
            [pscustomobject]@{
                Type      = 'RoutingDiscoveryPipelineSummary'
                Timestamp = '2025-12-30T11:00:00Z'
                Status    = 'Pass'
                Site      = 'WLLS'
                Hostname  = 'WLLS-A01-AS-01'
                Vendor    = 'CiscoIOSXE'
                Vrf       = 'default'
                Path      = $compareMissingSummary
            },
            [pscustomobject]@{
                Type      = 'RoutingDiscoveryPipelineSummary'
                Timestamp = '2025-12-30T10:30:00Z'
                Status    = 'Pass'
                Site      = 'WLLS'
                Hostname  = 'WLLS-A01-AS-01'
                Vendor    = 'CiscoIOSXE'
                Vrf       = 'default'
                Path      = $compareOldSummary
            }
        )
        $indexPayload = [pscustomobject]@{
            SchemaVersion = '1.0'
            GeneratedAt   = '2025-12-30T11:30:00Z'
            Entries       = $entries
        }
        $indexPayload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $indexPath -Encoding UTF8

        $threw = $false
        try {
            & $toolPath -IndexPath $indexPath -Select 0 -CompareWithPrevious | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'RouteHealthSnapshotPath'
        }
        $threw | Should Be $true
    }

    It 'filters by Hostname with case-insensitive matching' {
        # LANDMARK: Explorer ergonomics tests - Hostname filtering, Latest selection, CompareLatestTwo, and mutual exclusivity
        $indexPath = Join-Path -Path $TestDrive -ChildPath 'RoutingLogIndex-hostname.json'
        $entries = @(
            [pscustomobject]@{
                Type      = 'RoutingValidationRunSummary'
                Timestamp = '2025-12-30T12:00:00Z'
                Status    = 'Pass'
                Site      = 'LAB'
                Hostname  = 'LAB-HOST-01'
                Vendor    = 'CiscoIOSXE'
                Vrf       = 'default'
                Path      = $validationFixture
            },
            [pscustomobject]@{
                Type      = 'RoutingDiscoveryPipelineSummary'
                Timestamp = '2025-12-30T11:00:00Z'
                Status    = 'Pass'
                Site      = 'LAB'
                Hostname  = 'LAB-HOST-02'
                Vendor    = 'CiscoIOSXE'
                Vrf       = 'default'
                Path      = $pipelineFixture
            }
        )
        $indexPayload = [pscustomobject]@{
            SchemaVersion = '1.0'
            GeneratedAt   = '2025-12-30T12:05:00Z'
            Entries       = $entries
        }
        $indexPayload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $indexPath -Encoding UTF8

        $result = & $toolPath -IndexPath $indexPath -Hostname 'lab-host-01' -ListOnly -PassThru
        @($result).Count | Should Be 1
        $result.Path | Should Be $validationFixture
    }

    It 'selects the newest entry when Latest is set' {
        $summary = & $toolPath -IndexPath $latestCompareIndexFixture -Latest -PassThru
        $expectedPath = (Resolve-Path -LiteralPath $latestCompareNewSummary).Path
        $summary.SourcePath | Should Be $expectedPath
    }

    It 'compares the latest two entries without Select' {
        $diffJson = Join-Path -Path $TestDrive -ChildPath 'RoutingDiff-latest.json'
        $diffMarkdown = Join-Path -Path $TestDrive -ChildPath 'RoutingDiff-latest.md'
        & $toolPath -IndexPath $latestCompareIndexFixture -Hostname 'WLLS-A01-AS-01' -CompareLatestTwo -DiffOutputPath $diffJson -DiffMarkdownPath $diffMarkdown -PassThru | Out-Null
        (Test-Path -LiteralPath $diffJson) | Should Be $true
        (Test-Path -LiteralPath $diffMarkdown) | Should Be $true
        $diffPayload = Get-Content -LiteralPath $diffJson -Raw | ConvertFrom-Json
        $diffPayload.Changes.Health | Should Not Be $null
        $diffPayload.Counts | Should Not Be $null
    }

    It 'fails when Select is combined with Latest or CompareLatestTwo' {
        $threw = $false
        try {
            & $toolPath -IndexPath $indexFixture -Select 0 -Latest | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'Select cannot be combined'
        }
        $threw | Should Be $true

        $threw = $false
        try {
            & $toolPath -IndexPath $indexFixture -Select 0 -CompareLatestTwo | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'Select cannot be combined'
        }
        $threw | Should Be $true
    }

    It 'exports a bundle for a direct Path selection' {
        # LANDMARK: Explorer bundle export tests - selected summary bundle, diff bundle, and invalid combinations
        $root = Join-Path -Path $TestDrive -ChildPath 'bundle'
        $null = New-Item -ItemType Directory -Path $root -Force
        $artifactOne = Join-Path -Path $root -ChildPath 'pipeline.json'
        $artifactTwo = Join-Path -Path $root -ChildPath 'records.json'
        Set-Content -LiteralPath $artifactOne -Value '{}' -Encoding UTF8
        Set-Content -LiteralPath $artifactTwo -Value '{}' -Encoding UTF8

        $summaryPath = Join-Path -Path $root -ChildPath 'RoutingDiscoveryPipelineSummary.sample.json'
        $payload = [ordered]@{
            Status          = 'Pass'
            CaptureMetadata = [ordered]@{
                Site     = 'LAB'
                Hostname = 'LAB-01'
                Vrf      = 'default'
            }
            ArtifactPaths   = [ordered]@{
                PipelineSummaryPath     = 'pipeline.json'
                RouteRecordsSummaryPath = 'records.json'
            }
        }
        $payload | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

        $bundleZip = Join-Path -Path $TestDrive -ChildPath 'summary-bundle.zip'
        & $toolPath -Path $summaryPath -ExportBundle -BundleZipPath $bundleZip -PassThru | Out-Null
        (Test-Path -LiteralPath $bundleZip) | Should Be $true
    }

    It 'blocks ExportBundle when ListOnly is set' {
        $threw = $false
        try {
            & $toolPath -IndexPath $indexFixture -ListOnly -ExportBundle | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'ExportBundle cannot be used'
        }
        $threw | Should Be $true
    }

    It 'exports a diff bundle when CompareLatestTwo is used' {
        $diffJson = Join-Path -Path $TestDrive -ChildPath 'RoutingDiff-latest.json'
        $diffMarkdown = Join-Path -Path $TestDrive -ChildPath 'RoutingDiff-latest.md'
        $diffBundle = Join-Path -Path $TestDrive -ChildPath 'RoutingBundle-diff.zip'
        & $toolPath -IndexPath $latestCompareIndexFixture -Hostname 'WLLS-A01-AS-01' -CompareLatestTwo -DiffOutputPath $diffJson -DiffMarkdownPath $diffMarkdown -ExportDiffBundle -DiffBundleZipPath $diffBundle -PassThru | Out-Null
        (Test-Path -LiteralPath $diffBundle) | Should Be $true
    }

    It 'fails when ExportDiffBundle is set without compare mode' {
        $threw = $false
        try {
            & $toolPath -IndexPath $indexFixture -Select 0 -ExportDiffBundle | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'ExportDiffBundle requires compare mode'
        }
        $threw | Should Be $true
    }
}
