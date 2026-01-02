Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$publishScript = Join-Path -Path $repoRoot -ChildPath 'Tools/Publish-TelemetryBundle.ps1'
$readinessScript = Join-Path -Path $repoRoot -ChildPath 'Tools/Test-TelemetryBundleReadiness.ps1'

Describe 'Publish telemetry bundle readiness structure' {
    It 'publishes a telemetry bundle that passes readiness checks' {
        # LANDMARK: Publish telemetry bundle tests - readiness-compliant structure
        if (-not (Test-Path -LiteralPath $publishScript)) {
            throw "Publish script not found at $publishScript"
        }
        if (-not (Test-Path -LiteralPath $readinessScript)) {
            throw "Readiness script not found at $readinessScript"
        }

        $artifactRoot = Join-Path -Path $TestDrive -ChildPath 'Artifacts'
        New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null

        $cold = Join-Path -Path $artifactRoot -ChildPath '2026-01-01.json'
        $warm = Join-Path -Path $artifactRoot -ChildPath 'WarmRunTelemetry-20260101.json'
        $sharedCache = Join-Path -Path $artifactRoot -ChildPath 'SharedCacheStoreState-20260101.json'
        $providerReasons = Join-Path -Path $artifactRoot -ChildPath 'SiteCacheProviderReasons-20260101.json'
        $diffHotspots = Join-Path -Path $artifactRoot -ChildPath 'WarmRunDiffHotspots-20260101.csv'
        $rollup = Join-Path -Path $artifactRoot -ChildPath 'IngestionMetricsSummary-20260101.csv'
        $docSync = Join-Path -Path $artifactRoot -ChildPath '2026-01-01_session-0000.md'

        Set-Content -LiteralPath $cold -Value '{}' -Encoding utf8
        Set-Content -LiteralPath $warm -Value '{}' -Encoding utf8
        Set-Content -LiteralPath $sharedCache -Value '{}' -Encoding utf8
        Set-Content -LiteralPath $providerReasons -Value '{}' -Encoding utf8
        Set-Content -LiteralPath $diffHotspots -Value 'Site,TotalDiffComparisonMs' -Encoding utf8
        Set-Content -LiteralPath $rollup -Value 'Metric,Value' -Encoding utf8
        Set-Content -LiteralPath $docSync -Value '# Session Log' -Encoding utf8

        $bundleName = 'PublishTest-Ready'
        $bundleResult = & $publishScript `
            -BundleName $bundleName `
            -OutputRoot $TestDrive `
            -AllowCustomOutputRoot `
            -ColdTelemetryPath $cold `
            -WarmTelemetryPath $warm `
            -AnalyzerPath @($sharedCache, $providerReasons) `
            -DiffHotspotsPath $diffHotspots `
            -RollupPath $rollup `
            -DocSyncPath $docSync `
            -PassThru

        $bundleResult | Should Not BeNullOrEmpty
        $bundleResult.AreaName | Should Be 'Telemetry'

        $bundleRoot = Join-Path -Path $TestDrive -ChildPath $bundleName
        $telemetryPath = Join-Path -Path $bundleRoot -ChildPath 'Telemetry'
        Test-Path -LiteralPath $telemetryPath | Should Be $true

        Test-Path -LiteralPath (Join-Path -Path $telemetryPath -ChildPath 'TelemetryBundle.json') | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $telemetryPath -ChildPath 'README.md') | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $telemetryPath -ChildPath (Split-Path -Leaf $sharedCache)) | Should Be $true
        Test-Path -LiteralPath (Join-Path -Path $telemetryPath -ChildPath (Split-Path -Leaf $providerReasons)) | Should Be $true

        $summaryPath = Join-Path -Path $TestDrive -ChildPath 'summary.json'
        & $readinessScript -BundlePath $bundleRoot -Area Telemetry -IncludeReadmeHash -SummaryPath $summaryPath | Out-Null

        Test-Path -LiteralPath $summaryPath | Should Be $true
        $summaryData = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        $telemetrySummary = $summaryData | Where-Object { $_.Area -eq 'Telemetry' } | Select-Object -First 1

        $telemetrySummary | Should Not BeNullOrEmpty
        $telemetrySummary.ReadmeHash | Should Not BeNullOrEmpty
        $missing = @($telemetrySummary.RequirementState | Where-Object { $_.Status -eq 'Missing' })
        $missing.Count | Should Be 0
    }
}
