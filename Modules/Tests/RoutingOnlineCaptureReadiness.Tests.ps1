Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$toolPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Test-RoutingOnlineCaptureReadiness.ps1'
$fixtureSessionPath = Join-Path -Path $repoRoot -ChildPath 'Tests/Fixtures/Routing/CliCaptureSession/CiscoIOSXE/Session.json'

Describe 'Routing online capture readiness' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $toolPath)) {
            throw "Readiness tool not found at $toolPath"
        }
        if (-not (Test-Path -LiteralPath $fixtureSessionPath)) {
            throw "Session fixture not found at $fixtureSessionPath"
        }
    }

    It 'valid session yields pass or warning' {
        # LANDMARK: Online capture readiness tests - structural, path safety, and ssh gating checks
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'readiness.json'
        $result = & $toolPath -SessionPath $fixtureSessionPath -OutputPath $outputPath -PassThru

        $result.Status | Should Not Be 'Fail'
        (Test-Path -LiteralPath $outputPath) | Should Be $true
    }

    It 'fails when required fields are missing' {
        $session = Get-Content -LiteralPath $fixtureSessionPath -Raw | ConvertFrom-Json
        $session.PSObject.Properties.Remove('Hosts')
        $sessionPath = Join-Path -Path $TestDrive -ChildPath 'Session-missing.json'
        $session | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $sessionPath -Encoding utf8
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'missing-fields.json'

        $threw = $false
        try {
            & $toolPath -SessionPath $sessionPath -OutputPath $outputPath -PassThru
        } catch {
            $threw = $true
        }

        $threw | Should Be $true
        $summary = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
        $summary.Status | Should Be 'Fail'
    }

    It 'fails when transcript path is unsafe' {
        $session = Get-Content -LiteralPath $fixtureSessionPath -Raw | ConvertFrom-Json
        $session.Hosts[0].Artifacts[0].TranscriptPath = '..\\..\\evil.txt'
        $sessionPath = Join-Path -Path $TestDrive -ChildPath 'Session-unsafe.json'
        $session | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $sessionPath -Encoding utf8
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'unsafe.json'

        $threw = $false
        try {
            & $toolPath -SessionPath $sessionPath -OutputPath $outputPath -PassThru
        } catch {
            $threw = $true
        }

        $threw | Should Be $true
        $summary = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
        $summary.Status | Should Be 'Fail'
    }

    It 'fails when RequireSsh is set and ssh is missing' {
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'missing-ssh.json'
        $missingSsh = Join-Path -Path $TestDrive -ChildPath 'missing-ssh.exe'

        $threw = $false
        try {
            & $toolPath -SessionPath $fixtureSessionPath -OutputPath $outputPath -RequireSsh -SshExePath $missingSsh -PassThru
        } catch {
            $threw = $true
        }

        $threw | Should Be $true
        $summary = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
        $summary.Status | Should Be 'Fail'
    }

    It 'fails when identity file is missing' {
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'missing-key.json'
        $missingKey = Join-Path -Path $TestDrive -ChildPath 'missing.key'

        $threw = $false
        try {
            & $toolPath -SessionPath $fixtureSessionPath -OutputPath $outputPath -SshIdentityFile $missingKey -PassThru
        } catch {
            $threw = $true
        }

        $threw | Should Be $true
        $summary = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
        $summary.Status | Should Be 'Fail'
    }
}
