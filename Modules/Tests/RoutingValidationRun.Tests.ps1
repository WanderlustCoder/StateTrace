Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$orchestratorPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Invoke-RoutingValidationRun.ps1'
$sessionPath = Join-Path -Path $repoRoot -ChildPath 'Tests/Fixtures/Routing/CliCaptureSession/CiscoIOSXE/Session.json'
$fixtureTranscript = Join-Path -Path $repoRoot -ChildPath 'Tests/Fixtures/Routing/CliCaptureSession/CiscoIOSXE/WLLS-A01-AS-01_show_ip_route.txt'

Describe 'Routing validation orchestrator' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $orchestratorPath)) {
            throw "Orchestrator not found at $orchestratorPath"
        }
        if (-not (Test-Path -LiteralPath $sessionPath)) {
            throw "Fixture session not found at $sessionPath"
        }
    }

    It 'runs offline end-to-end and updates latest pointer' {
        # LANDMARK: Routing validation run tests - offline pass; online gating; simulated online pass
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'offline'
        $timestamp = '20251229-140000'

        $result = & $orchestratorPath -SessionPath $sessionPath -Mode Offline -OutputRoot $outputRoot `
            -Timestamp $timestamp -UpdateLatest -PassThru -MaxHosts 1

        $result.Status | Should Be 'Pass'
        (Test-Path -LiteralPath (Join-Path -Path $outputRoot -ChildPath 'RoutingValidationRunSummary-latest.json')) | Should Be $true
        (Test-Path -LiteralPath $result.HostSummaries[0].PipelineSummaryPath) | Should Be $true
    }

    It 'fails online mode when gating is not enabled' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'online-blocked'
        $timestamp = '20251229-140010'
        $priorEnv = $env:STATETRACE_ALLOW_NETWORK_CAPTURE
        $env:STATETRACE_ALLOW_NETWORK_CAPTURE = $null

        $threw = $false
        try {
            & $orchestratorPath -SessionPath $sessionPath -Mode Online -SshUser 'test' `
                -OutputRoot $outputRoot -Timestamp $timestamp -PassThru
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'Online capture is disabled'
        } finally {
            $env:STATETRACE_ALLOW_NETWORK_CAPTURE = $priorEnv
        }

        $threw | Should Be $true
    }

    It 'runs online mode with simulated transcript capture' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'online'
        $timestamp = '20251229-140020'
        $priorEnv = $env:STATETRACE_ALLOW_NETWORK_CAPTURE

        try {
            $env:STATETRACE_ALLOW_NETWORK_CAPTURE = '1'
            $scriptBlock = {
                param([string]$Hostname, [string]$Vendor, [string]$Command, [string]$OutputPath)
                Copy-Item -LiteralPath $fixtureTranscript -Destination $OutputPath -Force
            }

            $result = & $orchestratorPath -SessionPath $sessionPath -Mode Online -AllowNetworkCapture -SshUser 'test' `
                -OutputRoot $outputRoot -Timestamp $timestamp -UpdateLatest -PassThru -MaxHosts 1 `
                -TranscriptCaptureScriptBlock $scriptBlock

            $result.Status | Should Be 'Pass'
            $result.NetworkCaptureAllowed | Should Be $true
            (Test-Path -LiteralPath (Join-Path -Path $outputRoot -ChildPath 'RoutingValidationRunSummary-latest.json')) | Should Be $true
            (Test-Path -LiteralPath $result.HostSummaries[0].PipelineSummaryPath) | Should Be $true
        } finally {
            $env:STATETRACE_ALLOW_NETWORK_CAPTURE = $priorEnv
        }
    }
}
