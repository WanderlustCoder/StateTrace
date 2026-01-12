Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Test-RoutingDiscoveryBaseline.ps1'

Describe 'Routing discovery baseline' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            throw "Routing discovery baseline script not found at $scriptPath"
        }
    }

    It 'passes with matching host lists' {
        # LANDMARK: Routing discovery baseline tests - valid host lists pass
        $hostList = Join-Path -Path $TestDrive -ChildPath 'hosts.txt'
        $balancedList = Join-Path -Path $TestDrive -ChildPath 'hosts-balanced.txt'
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'summary.json'

        Set-Content -LiteralPath $hostList -Value @('BOYO-A01-AS-01', 'WLLS-A01-AS-01') -Encoding utf8
        Set-Content -LiteralPath $balancedList -Value @('WLLS-A01-AS-01', 'BOYO-A01-AS-01') -Encoding utf8

        $result = & $scriptPath -HostListPath $hostList -BalancedHostListPath $balancedList -OutputPath $outputPath -PassThru

        $result.Passed | Should Be $true
        $result.HostList.Count | Should Be 2
        $result.BalancedHostList.MissingHosts.Count | Should Be 0
    }

    It 'fails when duplicate hosts exist' {
        $hostList = Join-Path -Path $TestDrive -ChildPath 'hosts-dup.txt'
        $balancedList = Join-Path -Path $TestDrive -ChildPath 'hosts-balanced.txt'
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'summary-dup.json'

        Set-Content -LiteralPath $hostList -Value @('BOYO-A01-AS-01', 'BOYO-A01-AS-01') -Encoding utf8
        Set-Content -LiteralPath $balancedList -Value @('BOYO-A01-AS-01') -Encoding utf8

        $threw = $false
        try {
            & $scriptPath -HostListPath $hostList -BalancedHostListPath $balancedList -OutputPath $outputPath
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'HostListDuplicates'
        }

        $threw | Should Be $true
    }

    It 'fails when the balanced list is missing' {
        $hostList = Join-Path -Path $TestDrive -ChildPath 'hosts.txt'
        $balancedList = Join-Path -Path $TestDrive -ChildPath 'missing-balanced.txt'
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'summary-missing.json'

        Set-Content -LiteralPath $hostList -Value @('BOYO-A01-AS-01') -Encoding utf8

        $threw = $false
        try {
            & $scriptPath -HostListPath $hostList -BalancedHostListPath $balancedList -OutputPath $outputPath
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'BalancedHostListMissing'
        }

        $threw | Should Be $true
    }
}
