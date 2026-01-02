Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$converterPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Convert-RoutingCliCaptureToDiscoveryCapture.ps1'
$discoveryConverterPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Convert-RoutingDiscoveryCapture.ps1'
$fixtureRoot = Join-Path -Path $repoRoot -ChildPath 'Tests/Fixtures/Routing/CliCapture/CiscoIOSXE'
$fixtureRootArista = Join-Path -Path $repoRoot -ChildPath 'Tests/Fixtures/Routing/CliCapture/AristaEOS'

Describe 'Routing CLI capture ingestion' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $converterPath)) {
            throw "CLI ingestion tool not found at $converterPath"
        }
        if (-not (Test-Path -LiteralPath $discoveryConverterPath)) {
            throw "Discovery conversion tool not found at $discoveryConverterPath"
        }
    }

    It 'converts the CLI capture fixture and produces RouteRecords' {
        # LANDMARK: CLI ingestion tests - fixture converts; missing artifact/vendor fails
        $capturePath = Join-Path -Path $fixtureRoot -ChildPath 'Capture.json'
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'RoutingDiscoveryCapture.json'
        $summaryPath = Join-Path -Path $TestDrive -ChildPath 'summary.json'

        $result = & $converterPath -CapturePath $capturePath -OutputPath $outputPath -SummaryPath $summaryPath -PassThru

        $result.Status | Should Be 'Pass'
        (Test-Path -LiteralPath $outputPath) | Should Be $true

        $routeRecordsPath = Join-Path -Path $TestDrive -ChildPath 'RouteRecords.json'
        $routeSummaryPath = Join-Path -Path $TestDrive -ChildPath 'route-summary.json'
        $routeResult = & $discoveryConverterPath -CapturePath $outputPath -RouteRecordOutputPath $routeRecordsPath -SummaryPath $routeSummaryPath -PassThru
        $routeResult.Status | Should Be 'Pass'
        (Test-Path -LiteralPath $routeRecordsPath) | Should Be $true
    }

    It 'converts the AristaEOS fixture and produces RouteRecords' {
        # LANDMARK: Arista ingestion tests - fixture converts; missing artifact and unsupported vendor fail
        $capturePath = Join-Path -Path $fixtureRootArista -ChildPath 'Capture.json'
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'RoutingDiscoveryCapture-Arista.json'
        $summaryPath = Join-Path -Path $TestDrive -ChildPath 'summary-arista.json'

        $result = & $converterPath -CapturePath $capturePath -OutputPath $outputPath -SummaryPath $summaryPath -PassThru

        $result.Status | Should Be 'Pass'
        (Test-Path -LiteralPath $outputPath) | Should Be $true

        $routeRecordsPath = Join-Path -Path $TestDrive -ChildPath 'RouteRecords-Arista.json'
        $routeSummaryPath = Join-Path -Path $TestDrive -ChildPath 'route-summary-arista.json'
        $routeResult = & $discoveryConverterPath -CapturePath $outputPath -RouteRecordOutputPath $routeRecordsPath -SummaryPath $routeSummaryPath -PassThru
        $routeResult.Status | Should Be 'Pass'
        (Test-Path -LiteralPath $routeRecordsPath) | Should Be $true
    }

    It 'fails when the CLI artifact is missing' {
        $capture = Get-Content -LiteralPath (Join-Path $fixtureRoot 'Capture.json') -Raw | ConvertFrom-Json
        $capture.Artifacts[0].Path = 'missing.txt'
        $capturePath = Join-Path -Path $TestDrive -ChildPath 'missing-capture.json'
        $capture | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $capturePath -Encoding utf8

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'missing-output.json'
        $summaryPath = Join-Path -Path $TestDrive -ChildPath 'missing-summary.json'
        $threw = $false

        try {
            & $converterPath -CapturePath $capturePath -OutputPath $outputPath -SummaryPath $summaryPath
        } catch {
            $threw = $true
        }

        $threw | Should Be $true
        (Test-Path -LiteralPath $summaryPath) | Should Be $true
        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        $summary.Status | Should Be 'Fail'
        ($summary.Errors -join ';') | Should Match 'MissingArtifactFile'
    }

    It 'fails when vendor is unsupported' {
        $capture = Get-Content -LiteralPath (Join-Path $fixtureRoot 'Capture.json') -Raw | ConvertFrom-Json
        $capture.Vendor = 'UnknownVendor'
        $capturePath = Join-Path -Path $TestDrive -ChildPath 'unsupported-capture.json'
        $capture | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $capturePath -Encoding utf8

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'unsupported-output.json'
        $summaryPath = Join-Path -Path $TestDrive -ChildPath 'unsupported-summary.json'
        $threw = $false

        try {
            & $converterPath -CapturePath $capturePath -OutputPath $outputPath -SummaryPath $summaryPath
        } catch {
            $threw = $true
        }

        $threw | Should Be $true
        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        $summary.Status | Should Be 'Fail'
        ($summary.Errors -join ';') | Should Match 'UnsupportedVendor'
        ($summary.Errors -join ';') | Should Match 'CiscoIOSXE,AristaEOS'
    }
}
