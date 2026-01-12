Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$generatorPath = Join-Path -Path $repoRoot -ChildPath 'Tools/New-RoutingCliCaptureSession.ps1'
$fixtureRoot = Join-Path -Path $repoRoot -ChildPath 'Tests/Fixtures/Routing/CliCaptureSession'
$schemaPath = Join-Path -Path $repoRoot -ChildPath 'docs/schemas/routing/routing_cli_capture_session.schema.json'

Describe 'Routing CLI capture session manifest generator' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $generatorPath)) {
            throw "Manifest generator not found at $generatorPath"
        }
        if (-not (Test-Path -LiteralPath $schemaPath)) {
            throw "Routing session schema not found at $schemaPath"
        }
    }

    It 'generates a schema-valid manifest with deterministic host ordering' {
        # LANDMARK: Session manifest generator tests - determinism, duplicates, and empty host list failures
        $hostsPath = Join-Path -Path $fixtureRoot -ChildPath 'Hosts.sample.txt'
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'Session.json'
        $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json

        $result = & $generatorPath -HostsPath $hostsPath -Site 'WLLS' -Vendor 'CiscoIOSXE' `
            -Vrf 'default' -OutputPath $outputPath -CapturedAt '2025-12-29T00:00:00Z' -PassThru

        $result.SchemaVersion | Should Be $schema.SchemaVersion
        $result.Hosts.Count | Should Be 2
        $result.Hosts[0].Hostname | Should Be 'WLLS-A01-AS-01'
        $result.Hosts[0].Artifacts[0].Name | Should Be 'show_ip_route'
        $result.Hosts[0].Artifacts[0].Command | Should Be 'show ip route'
        $result.Hosts[0].Artifacts[0].TranscriptPath | Should Be 'WLLS-A01-AS-01_show_ip_route.txt'

        $parsed = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
        $parsed.Hosts.Count | Should Be 2
    }

    It 'emits identical JSON when inputs and CapturedAt are fixed' {
        $hostsPath = Join-Path -Path $fixtureRoot -ChildPath 'Hosts.sample.txt'
        $outputA = Join-Path -Path $TestDrive -ChildPath 'SessionA.json'
        $outputB = Join-Path -Path $TestDrive -ChildPath 'SessionB.json'

        & $generatorPath -HostsPath $hostsPath -Site 'WLLS' -Vendor 'CiscoIOSXE' `
            -Vrf 'default' -OutputPath $outputA -CapturedAt '2025-12-29T00:00:00Z'
        & $generatorPath -HostsPath $hostsPath -Site 'WLLS' -Vendor 'CiscoIOSXE' `
            -Vrf 'default' -OutputPath $outputB -CapturedAt '2025-12-29T00:00:00Z'

        (Get-Content -LiteralPath $outputA -Raw) | Should Be (Get-Content -LiteralPath $outputB -Raw)
    }

    It 'fails when host list is empty after filtering' {
        $hostsPath = Join-Path -Path $TestDrive -ChildPath 'empty.txt'
        Set-Content -LiteralPath $hostsPath -Value @('', '# comment') -Encoding UTF8

        $threw = $false
        try {
            & $generatorPath -HostsPath $hostsPath -Site 'WLLS' -Vendor 'CiscoIOSXE' -Vrf 'default' `
                -OutputPath (Join-Path -Path $TestDrive -ChildPath 'Session.json')
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'Hosts list is empty'
        }
        $threw | Should Be $true
    }

    It 'fails when host list contains duplicate hostnames' {
        $hostsPath = Join-Path -Path $TestDrive -ChildPath 'dups.txt'
        Set-Content -LiteralPath $hostsPath -Value @('WLLS-A01-AS-01', 'wlls-a01-as-01') -Encoding UTF8

        $threw = $false
        try {
            & $generatorPath -HostsPath $hostsPath -Site 'WLLS' -Vendor 'CiscoIOSXE' -Vrf 'default' `
                -OutputPath (Join-Path -Path $TestDrive -ChildPath 'Session.json')
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'Duplicate hostnames'
        }
        $threw | Should Be $true
    }
}
