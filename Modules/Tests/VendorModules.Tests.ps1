# VendorModules.Tests.ps1
# Tests for multi-vendor parser modules and vendor detection

# Import modules at file scope for Pester 3.x compatibility
$script:modulesRoot = Split-Path -Parent $PSScriptRoot
$script:fixturesRoot = Join-Path (Split-Path -Parent $script:modulesRoot) 'Tests\Fixtures\Vendors'

Import-Module (Join-Path $script:modulesRoot 'DeviceLogParserModule.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue
Import-Module (Join-Path $script:modulesRoot 'DeviceParsingCommon.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue
Import-Module (Join-Path $script:modulesRoot 'JuniperModule.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $script:modulesRoot 'ArubaModule.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $script:modulesRoot 'PaloAltoModule.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $script:modulesRoot 'VendorDetectionModule.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $script:modulesRoot 'VendorCommandTemplates.psm1') -Force -DisableNameChecking

Describe 'VendorDetectionModule' {
    Context 'Get-VendorFromContent' {
        It 'Detects Juniper from JunOS output' {
            $lines = @(
                'user@EX4300-CORE> show version'
                'Hostname: EX4300-CORE'
                'Model: EX4300-48T'
                'Junos: 21.4R3-S2.3'
            )
            $result = Get-VendorFromContent -Lines $lines
            $result.Vendor | Should Be 'Juniper'
            $result.Confidence | Should BeGreaterThan 80
        }

        It 'Detects Aruba from ArubaOS output' {
            $lines = @(
                'ARUBA-6300# show version'
                'ArubaOS-CX'
                'Product Name:      Aruba 6300M 48G'
            )
            $result = Get-VendorFromContent -Lines $lines
            $result.Vendor | Should Be 'Aruba'
            $result.Confidence | Should BeGreaterThan 80
        }

        It 'Detects Palo Alto from PAN-OS output' {
            $lines = @(
                'admin@PA-3220> show system info'
                'hostname: PA-3220'
                'model: PA-3220'
                'sw-version: 10.2.3'
            )
            $result = Get-VendorFromContent -Lines $lines
            $result.Vendor | Should Be 'PaloAlto'
            $result.Confidence | Should BeGreaterThan 80
        }

        It 'Detects Cisco from IOS output' {
            $lines = @(
                'Switch#show version'
                'Cisco IOS Software, Version 15.2(4)E7'
                'Model Number: WS-C3850-48P'
            )
            $result = Get-VendorFromContent -Lines $lines
            $result.Vendor | Should Be 'Cisco'
            $result.Confidence | Should BeGreaterThan 80
        }

        It 'Returns Unknown for empty input' {
            $result = Get-VendorFromContent -Lines @()
            $result.Vendor | Should Be 'Unknown'
            $result.Confidence | Should Be 0
        }
    }

    Context 'Get-SupportedVendors' {
        It 'Returns list of supported vendors' {
            $vendors = Get-SupportedVendors
            ($vendors -contains 'Cisco') | Should Be $true
            ($vendors -contains 'Juniper') | Should Be $true
            ($vendors -contains 'Aruba') | Should Be $true
            ($vendors -contains 'PaloAlto') | Should Be $true
            ($vendors -contains 'Arista') | Should Be $true
            ($vendors -contains 'Brocade') | Should Be $true
        }
    }
}

Describe 'JuniperModule' {
    Context 'Get-JuniperDeviceFacts' {
        BeforeAll {
            $fixtureDir = Join-Path $script:fixturesRoot 'Juniper'
            if (Test-Path $fixtureDir) {
                $versionFile = Join-Path $fixtureDir 'show_version.txt'
                $intFile = Join-Path $fixtureDir 'show_interfaces_terse.txt'
                $routeFile = Join-Path $fixtureDir 'show_route.txt'

                $allLines = @()
                if (Test-Path $versionFile) { $allLines += Get-Content $versionFile }
                if (Test-Path $intFile) { $allLines += Get-Content $intFile }
                if (Test-Path $routeFile) { $allLines += Get-Content $routeFile }

                $script:juniperResult = Get-JuniperDeviceFacts -Lines $allLines
            }
        }

        It 'Parses hostname correctly' -Skip:(-not $script:juniperResult) {
            $script:juniperResult.Hostname | Should Be 'EX4300-CORE'
        }

        It 'Identifies vendor as Juniper' -Skip:(-not $script:juniperResult) {
            $script:juniperResult.Make | Should Be 'Juniper'
        }

        It 'Parses model correctly' -Skip:(-not $script:juniperResult) {
            $script:juniperResult.Model | Should Be 'EX4300-48T'
        }

        It 'Parses version correctly' -Skip:(-not $script:juniperResult) {
            $script:juniperResult.Version | Should Match '21\.4R3'
        }

        It 'Parses interfaces' -Skip:(-not $script:juniperResult) {
            $script:juniperResult.InterfacesCombined.Count | Should BeGreaterThan 0
        }
    }
}

Describe 'ArubaModule' {
    Context 'Get-ArubaDeviceFacts' {
        BeforeAll {
            $fixtureDir = Join-Path $script:fixturesRoot 'Aruba'
            if (Test-Path $fixtureDir) {
                $versionFile = Join-Path $fixtureDir 'show_version.txt'
                $intFile = Join-Path $fixtureDir 'show_interface_brief.txt'
                $vlanFile = Join-Path $fixtureDir 'show_vlan.txt'

                $allLines = @()
                if (Test-Path $versionFile) { $allLines += Get-Content $versionFile }
                if (Test-Path $intFile) { $allLines += Get-Content $intFile }
                if (Test-Path $vlanFile) { $allLines += Get-Content $vlanFile }

                $script:arubaResult = Get-ArubaDeviceFacts -Lines $allLines
            }
        }

        It 'Parses hostname correctly' -Skip:(-not $script:arubaResult) {
            $script:arubaResult.Hostname | Should Be 'ARUBA-6300'
        }

        It 'Identifies vendor as Aruba' -Skip:(-not $script:arubaResult) {
            $script:arubaResult.Make | Should Be 'Aruba'
        }

        It 'Parses model correctly' -Skip:(-not $script:arubaResult) {
            $script:arubaResult.Model | Should Match 'Aruba 6300'
        }

        It 'Parses VLANs' -Skip:(-not $script:arubaResult) {
            $script:arubaResult.VLANs.Count | Should BeGreaterThan 0
        }
    }
}

Describe 'PaloAltoModule' {
    Context 'Get-PaloAltoDeviceFacts' {
        BeforeAll {
            $fixtureDir = Join-Path $script:fixturesRoot 'PaloAlto'
            if (Test-Path $fixtureDir) {
                $sysFile = Join-Path $fixtureDir 'show_system_info.txt'
                $intFile = Join-Path $fixtureDir 'show_interface_all.txt'
                $routeFile = Join-Path $fixtureDir 'show_routing_route.txt'

                $allLines = @()
                if (Test-Path $sysFile) { $allLines += Get-Content $sysFile }
                if (Test-Path $intFile) { $allLines += Get-Content $intFile }
                if (Test-Path $routeFile) { $allLines += Get-Content $routeFile }

                $script:paloResult = Get-PaloAltoDeviceFacts -Lines $allLines
            }
        }

        It 'Parses hostname correctly' -Skip:(-not $script:paloResult) {
            $script:paloResult.Hostname | Should Be 'PA-3220'
        }

        It 'Identifies vendor as PaloAlto' -Skip:(-not $script:paloResult) {
            $script:paloResult.Make | Should Be 'PaloAlto'
        }

        It 'Parses model correctly' -Skip:(-not $script:paloResult) {
            $script:paloResult.Model | Should Be 'PA-3220'
        }

        It 'Parses version correctly' -Skip:(-not $script:paloResult) {
            $script:paloResult.Version | Should Be '10.2.3'
        }

        It 'Parses serial number' -Skip:(-not $script:paloResult) {
            $script:paloResult.SerialNumber | Should Not BeNullOrEmpty
        }

        It 'Parses routes' -Skip:(-not $script:paloResult) {
            $script:paloResult.Routes.Count | Should BeGreaterThan 0
        }
    }
}

Describe 'VendorCommandTemplates' {
    Context 'Get-VendorCommands' {
        It 'Returns commands for Cisco' {
            $cmds = Get-VendorCommands -Vendor Cisco -Category BasicInfo
            ($cmds -contains 'show version') | Should Be $true
            ($cmds -contains 'show running-config') | Should Be $true
        }

        It 'Returns commands for Juniper' {
            $cmds = Get-VendorCommands -Vendor Juniper -Category BasicInfo
            ($cmds -contains 'show version') | Should Be $true
            ($cmds -contains 'show configuration | display set') | Should Be $true
        }

        It 'Returns commands for Aruba' {
            $cmds = Get-VendorCommands -Vendor Aruba -Category Layer2
            ($cmds -contains 'show mac-address-table') | Should Be $true
            ($cmds -contains 'show vlans') | Should Be $true
        }

        It 'Returns commands for PaloAlto' {
            $cmds = Get-VendorCommands -Vendor PaloAlto -Category Security
            ($cmds -contains 'show session all') | Should Be $true
            ($cmds -contains 'show zone') | Should Be $true
        }
    }

    Context 'Get-VendorFullCapture' {
        It 'Returns full capture script for each vendor' {
            foreach ($vendor in @('Cisco', 'Juniper', 'Aruba', 'PaloAlto', 'Brocade')) {
                $script = Get-VendorFullCapture -Vendor $vendor -AsScript
                $script | Should Not BeNullOrEmpty
            }
        }
    }

    Context 'Compare-VendorCommands' {
        It 'Returns comparison table for Layer2 commands' {
            $comparison = Compare-VendorCommands -Category Layer2
            $comparison.Count | Should BeGreaterThan 0
            ($comparison[0].PSObject.Properties.Name -contains 'Cisco') | Should Be $true
            ($comparison[0].PSObject.Properties.Name -contains 'Juniper') | Should Be $true
        }
    }

    Context 'New-CaptureScript' {
        It 'Generates capture script with comments' {
            $script = New-CaptureScript -Vendor Cisco -Categories 'BasicInfo','Layer2' -IncludeComments
            $script | Should Match '# === BasicInfo ==='
            $script | Should Match 'show version'
        }
    }
}
