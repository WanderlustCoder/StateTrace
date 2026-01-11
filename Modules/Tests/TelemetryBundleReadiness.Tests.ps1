Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Test-TelemetryBundleReadiness.ps1'
$sampleBundle = Join-Path -Path $repoRoot -ChildPath 'Data/Samples/TelemetryBundles/Sample-ReleaseBundle'

Describe 'Telemetry bundle readiness sample bundle' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            throw "Telemetry bundle readiness script not found at $scriptPath"
        }
        $script:SampleBundleAvailable = Test-Path -LiteralPath $sampleBundle
    }

    It 'validates the sample bundle and emits README hashes' {
        if (-not $script:SampleBundleAvailable) {
            Set-TestInconclusive -Message "Sample bundle fixture not found at $sampleBundle"
            return
        }
        # LANDMARK: Telemetry bundle readiness tests - sample bundle pass/fail
        $summary = Join-Path -Path $TestDrive -ChildPath 'summary.json'

        & $scriptPath -BundlePath $sampleBundle -Area Telemetry,Routing -IncludeReadmeHash -SummaryPath $summary | Out-Null

        Test-Path -LiteralPath $summary | Should Be $true
        $summaryData = Get-Content -LiteralPath $summary -Raw | ConvertFrom-Json

        $areas = @($summaryData | Select-Object -ExpandProperty Area)
        ($areas -contains 'Telemetry') | Should Be $true
        ($areas -contains 'Routing') | Should Be $true

        foreach ($area in $summaryData) {
            $area.ReadmeHash | Should Not BeNullOrEmpty
            $area.HashAlgorithm | Should Be 'SHA256'
            $missing = @($area.RequirementState | Where-Object { $_.Status -eq 'Missing' })
            $missing.Count | Should Be 0
        }
    }

    It 'reports missing required routing artifacts' {
        if (-not $script:SampleBundleAvailable) {
            Set-TestInconclusive -Message "Sample bundle fixture not found at $sampleBundle"
            return
        }
        # LANDMARK: Telemetry bundle readiness tests - missing required routing artifacts
        $bundleCopy = Join-Path -Path $TestDrive -ChildPath 'Sample-ReleaseBundle'
        Copy-Item -LiteralPath $sampleBundle -Destination $bundleCopy -Recurse

        $missingPaths = @(
            Join-Path -Path $bundleCopy -ChildPath 'Routing\QueueDelaySummary-20250101.json'
            Join-Path -Path $bundleCopy -ChildPath 'Routing\QueueDelaySummary-latest.json'
        )
        Remove-Item -LiteralPath $missingPaths -Force

        $summary = Join-Path -Path $TestDrive -ChildPath 'summary-missing.json'
        $threw = $false

        try {
            & $scriptPath -BundlePath $bundleCopy -Area Telemetry,Routing -IncludeReadmeHash -SummaryPath $summary | Out-Null
        } catch {
            $threw = $true
        }

        $threw | Should Be $true
        Test-Path -LiteralPath $summary | Should Be $true

        $summaryData = Get-Content -LiteralPath $summary -Raw | ConvertFrom-Json
        $routing = $summaryData | Where-Object { $_.Area -eq 'Routing' } | Select-Object -First 1
        $queueDelay = $routing.RequirementState | Where-Object { $_.Requirement -eq 'Queue delay summary' } | Select-Object -First 1

        $queueDelay | Should Not BeNullOrEmpty
        $queueDelay.Status | Should Be 'Missing'
    }
}
