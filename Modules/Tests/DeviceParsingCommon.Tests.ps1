Set-StrictMode -Version Latest

Describe "DeviceParsingCommon Invoke-RegexTableParser" {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSCommandPath) "..\DeviceParsingCommon.psm1"
        Import-Module (Resolve-Path $modulePath) -Force
    }

    AfterAll {
        Remove-Module DeviceParsingCommon -Force
    }

    It "parses interface status tables with trimming" {
        $lines = @(
            "random intro line",
            " Port   Name            Status      Vlan   Duplex   Speed    Type",
            " Et1    Uplink-To-Core  connected   10     full     1G       10G-SR   ",
            " Et2    Edge Switch     notconnect  20     auto     1G       1000BaseT",
            "",
            "ignored footer"
        )

        $propertyMap = [ordered]@{
            Port   = 1
            Name   = { param($match) $match.Groups[2].Value.Trim() }
            Status = 3
            VLAN   = 4
            Duplex = 5
            Speed  = 6
            Type   = { param($match) $match.Groups[7].Value.Trim() }
        }

        $result = DeviceParsingCommon\Invoke-RegexTableParser -Lines $lines -HeaderPattern '^\s*Port\s+Name\s+Status\s+Vlan\s+Duplex\s+Speed\s+Type' -RowPattern '^\s*(Et\d+(?:/\d+)*|Po\d+|Ma\d*)\s+(.*?)\s+(connected|notconnect|errdisabled|disabled)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+.*)$' -PropertyMap $propertyMap

        $result.Count | Should Be 2
        $result[0].Port | Should Be "Et1"
        $result[0].Name | Should Be "Uplink-To-Core"
        $result[0].Type | Should Be "10G-SR"
        $result[1].Status | Should Be "notconnect"
        $result[1].Type | Should Be "1000BaseT"
    }

    It "parses MAC table rows into strongly typed objects" {
        $lines = @(
            "garbage",
            " Vlan   Mac Address       Type      Ports",
            "   10   0011.2233.4455    dynamic   Et1",
            "   20   a0b1.c2d3.e4f5    static    Po1",
            "",
            "post"
        )

        $propertyMap = [ordered]@{
            VLAN = 1
            MAC  = 2
            Type = 3
            Port = 4
        }

        $result = DeviceParsingCommon\Invoke-RegexTableParser -Lines $lines -HeaderPattern '^\s*Vlan\s+Mac\s+Address\s+Type\s+Ports' -RowPattern '^\s*(\d+)\s+([0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4})\s+(\S+)\s+(\S+)\b' -PropertyMap $propertyMap

        $result.Count | Should Be 2
        $result[0].VLAN | Should Be "10"
        $result[0].MAC | Should Be "0011.2233.4455"
        $result[1].Type | Should Be "static"
        $result[1].Port | Should Be "Po1"
    }

    It "returns empty values when optional MAC or VLAN groups are missing" {
        $lines = @(
            "heading",
            " Port   Authorized   Mode   MAC Address       Vlan",
            " Et1    Yes          Single  aabb.ccdd.eeff   10",
            " Et2    No           Multi",
            " Et3    Yes          Multi    bbaa.1122.3344",
            "",
            "suffix"
        )

        $propertyMap = [ordered]@{
            Port = 1
            State = 2
            Mode  = 3
            MAC   = { param($match) if ($match.Groups[4].Success) { $match.Groups[4].Value.Trim() } else { '' } }
            VLAN  = { param($match) if ($match.Groups[5].Success) { $match.Groups[5].Value.Trim() } else { '' } }
        }

        $result = DeviceParsingCommon\Invoke-RegexTableParser -Lines $lines -HeaderPattern '^\s*Port\s+Authorized\s+Mode\s+MAC\s+Address\s+Vlan' -RowPattern '^\s*(Et\d+(?:/\d+)*|Po\d+|Ma\d*)\s+(\S+)\s+(\S+)(?:\s+([0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}))?(?:\s+(\d+))?' -PropertyMap $propertyMap

        $result.Count | Should Be 3
        $result[0].MAC | Should Be "aabb.ccdd.eeff"
        $result[0].VLAN | Should Be "10"
        $result[1].MAC | Should Be ""
        $result[1].VLAN | Should Be ""
        $result[2].MAC | Should Be "bbaa.1122.3344"
        $result[2].VLAN | Should Be ""
    }

    Context "ConvertFrom-MacTableRegex" {
        It "parses standard VLAN/MAC/port rows with port normalization" {
            $lines = @(
                "header",
                " Vlan Mac Address       Type Ports",
                " 10   0011.2233.4455    dynamic Et1",
                " 20   a0b1.c2d3.e4f5    static  Ethernet2/1/1"
            )

            $portTransform = { param($p) DeviceParsingCommon\ConvertTo-ShortPortName -Port $p }
            $parsed = DeviceParsingCommon\ConvertFrom-MacTableRegex -Lines $lines -HeaderPattern '^\s*Vlan\s+Mac\s+Address\s+Type\s+Ports' -RowPattern '^\s*(\d+)\s+([0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4})\s+\S+\s+(\S+)\b' -VlanGroup 1 -MacGroup 2 -PortGroup 3 -PortTransform $portTransform

            $parsed.Count | Should Be 2
            $parsed[0].VLAN | Should Be "10"
            $parsed[0].MAC  | Should Be "0011.2233.4455"
            $parsed[0].Port | Should Be "Et1"
            $parsed[1].Port | Should Be "Et2/1/1"
        }
    }

    Context "Get-HostnameFromPrompt" {
        It "extracts hostname from prompts with config context" {
            $lines = @(
                "core-switch(config)# show version"
            )

            DeviceParsingCommon\Get-HostnameFromPrompt -Lines $lines | Should Be "core-switch"
        }

        It "strips SSH prefixes and falls back to running-config entries" {
            $lines = @(
                "SSH@edge-sw1#",
                "hostname branch-01-sw"
            )

            $result = DeviceParsingCommon\Get-HostnameFromPrompt -Lines $lines -RunningConfigPattern '^(?i)\s*hostname\s+(.+)$'
            $result | Should Be "edge-sw1"
        }

        It "returns null when no hostname tokens are present" {
            $lines = @("random line", "other output")
            $result = DeviceParsingCommon\Get-HostnameFromPrompt -Lines $lines
            $result | Should BeNullOrEmpty
        }
    }

    Context "Get-UptimeFromLines" {
        It "parses Cisco-style uptime lines" {
            $lines = @(
                "router uptime is 5 weeks, 2 days, 3 hours, 1 minute"
            )

            $result = DeviceParsingCommon\Get-UptimeFromLines -Lines $lines
            $result | Should Be "5 weeks, 2 days, 3 hours, 1 minute"
        }

        It "parses Arista-style uptime lines" {
            $lines = @(
                "Something else",
                "Uptime: 12 days, 1 hour"
            )

            $result = DeviceParsingCommon\Get-UptimeFromLines -Lines $lines
            $result | Should Be "12 days, 1 hour"
        }

        It "returns null when no uptime tokens are present" {
            $lines = @("foo", "bar")
            $result = DeviceParsingCommon\Get-UptimeFromLines -Lines $lines
            $result | Should BeNullOrEmpty
        }
    }
}
