Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$runnerPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Invoke-RoutingCliCaptureSession.ps1'
$cliConverterPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Convert-RoutingCliCaptureToDiscoveryCapture.ps1'
$fixtureRoot = Join-Path -Path $repoRoot -ChildPath 'Tests/Fixtures/Routing/CliCaptureSession/CiscoIOSXE'

Describe 'Routing CLI capture session runner' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $runnerPath)) {
            throw "Session runner not found at $runnerPath"
        }
        if (-not (Test-Path -LiteralPath $cliConverterPath)) {
            throw "CLI converter not found at $cliConverterPath"
        }
    }

    It 'builds per-host RoutingCliCapture bundles and downstream conversion succeeds' {
        # LANDMARK: Routing CLI capture session tests - fixture pass; missing transcript fails; downstream ingestion works
        $sessionPath = Join-Path -Path $fixtureRoot -ChildPath 'Session.json'
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'session'
        $timestamp = '20251229-120000'

        $result = & $runnerPath -SessionPath $sessionPath -OutputRoot $outputRoot -Timestamp $timestamp -UpdateLatest -PassThru

        $result.Status | Should Be 'Pass'
        (Test-Path -LiteralPath (Join-Path -Path $outputRoot -ChildPath 'RoutingCliCaptureSessionSummary-latest.json')) | Should Be $true

        $capturePath = $result.HostSummaries[0].CaptureJsonPath
        (Test-Path -LiteralPath $capturePath) | Should Be $true

        $discoveryOutput = Join-Path -Path $TestDrive -ChildPath 'RoutingDiscoveryCapture.json'
        $discoverySummary = Join-Path -Path $TestDrive -ChildPath 'RoutingCliIngestionSummary.json'
        $discoveryResult = & $cliConverterPath -CapturePath $capturePath -OutputPath $discoveryOutput -SummaryPath $discoverySummary -PassThru

        $discoveryResult.Status | Should Be 'Pass'
        $discoveryResult.RoutesParsedCount | Should BeGreaterThan 0
    }

    It 'simulates online mode capture with explicit gating' {
        # LANDMARK: Online capture tests - gating required; simulated transcript capture; downstream ingestion proof
        $sessionPath = Join-Path -Path $fixtureRoot -ChildPath 'Session.json'
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'online'
        $timestamp = '20251229-120010'
        $fixtureTranscript = Join-Path -Path $fixtureRoot -ChildPath 'WLLS-A01-AS-01_show_ip_route.txt'

        $priorEnv = $env:STATETRACE_ALLOW_NETWORK_CAPTURE
        try {
            $env:STATETRACE_ALLOW_NETWORK_CAPTURE = '1'
            $scriptBlock = {
                param([string]$Hostname, [string]$Vendor, [string]$Command, [string]$OutputPath)
                Copy-Item -LiteralPath $fixtureTranscript -Destination $OutputPath -Force
            }
            $result = & $runnerPath -SessionPath $sessionPath -Mode Online -AllowNetworkCapture -SshUser 'test' `
                -OutputRoot $outputRoot -Timestamp $timestamp -UpdateLatest -PassThru `
                -TranscriptCaptureScriptBlock $scriptBlock
        } finally {
            $env:STATETRACE_ALLOW_NETWORK_CAPTURE = $priorEnv
        }

        $result.Status | Should Be 'Pass'
        $result.Mode | Should Be 'Online'
        $result.NetworkCaptureAllowed | Should Be $true
        (Test-Path -LiteralPath (Join-Path -Path $outputRoot -ChildPath 'RoutingCliCaptureSessionSummary-latest.json')) | Should Be $true

        $capturePath = $result.HostSummaries[0].CaptureJsonPath
        (Test-Path -LiteralPath $capturePath) | Should Be $true

        $discoveryOutput = Join-Path -Path $TestDrive -ChildPath 'RoutingDiscoveryCapture-online.json'
        $discoverySummary = Join-Path -Path $TestDrive -ChildPath 'RoutingCliIngestionSummary-online.json'
        $discoveryResult = & $cliConverterPath -CapturePath $capturePath -OutputPath $discoveryOutput -SummaryPath $discoverySummary -PassThru

        $discoveryResult.Status | Should Be 'Pass'
        $discoveryResult.RoutesParsedCount | Should BeGreaterThan 0
    }

    It 'fails online mode when gating is not enabled' {
        $sessionPath = Join-Path -Path $fixtureRoot -ChildPath 'Session.json'
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'online-blocked'
        $timestamp = '20251229-120020'
        $priorEnv = $env:STATETRACE_ALLOW_NETWORK_CAPTURE
        $env:STATETRACE_ALLOW_NETWORK_CAPTURE = $null

        $threw = $false
        try {
            & $runnerPath -SessionPath $sessionPath -Mode Online -AllowNetworkCapture -SshUser 'test' `
                -OutputRoot $outputRoot -Timestamp $timestamp -PassThru
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'Online capture is disabled'
        } finally {
            $env:STATETRACE_ALLOW_NETWORK_CAPTURE = $priorEnv
        }

        $threw | Should Be $true
    }

    It 'fails when transcript capture throws in online mode' {
        $sessionPath = Join-Path -Path $fixtureRoot -ChildPath 'Session.json'
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'online-fail'
        $timestamp = '20251229-120030'
        $priorEnv = $env:STATETRACE_ALLOW_NETWORK_CAPTURE

        try {
            $env:STATETRACE_ALLOW_NETWORK_CAPTURE = '1'
            $scriptBlock = {
                param([string]$Hostname, [string]$Vendor, [string]$Command, [string]$OutputPath)
                throw 'SimulatedCaptureFailure'
            }
            $summaryPath = Join-Path -Path $outputRoot -ChildPath ("RoutingCliCaptureSessionSummary-{0}.json" -f $timestamp)

            $threw = $false
            try {
                & $runnerPath -SessionPath $sessionPath -Mode Online -AllowNetworkCapture -SshUser 'test' `
                    -OutputRoot $outputRoot -Timestamp $timestamp -PassThru `
                    -TranscriptCaptureScriptBlock $scriptBlock
            } catch {
                $threw = $true
            }

            $threw | Should Be $true
            (Test-Path -LiteralPath $summaryPath) | Should Be $true
            $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
            $summary.Status | Should Be 'Fail'
            ($summary.Errors -join ';') | Should Match 'TranscriptCaptureFailed'
        } finally {
            $env:STATETRACE_ALLOW_NETWORK_CAPTURE = $priorEnv
        }
    }

    It 'fails when a transcript file is missing' {
        $session = Get-Content -LiteralPath (Join-Path $fixtureRoot 'Session.json') -Raw | ConvertFrom-Json
        $session.Hosts[0].Artifacts[0].TranscriptPath = 'missing.txt'
        $sessionPath = Join-Path -Path $TestDrive -ChildPath 'Session-missing.json'
        $session | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $sessionPath -Encoding utf8

        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'missing'
        $timestamp = '20251229-120001'
        $summaryPath = Join-Path -Path $outputRoot -ChildPath ("RoutingCliCaptureSessionSummary-{0}.json" -f $timestamp)
        $threw = $false

        try {
            & $runnerPath -SessionPath $sessionPath -OutputRoot $outputRoot -Timestamp $timestamp -PassThru
        } catch {
            $threw = $true
        }

        $threw | Should Be $true
        (Test-Path -LiteralPath $summaryPath) | Should Be $true
        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        $summary.Status | Should Be 'Fail'
        ($summary.Errors -join ';') | Should Match 'MissingTranscript'
    }
}
