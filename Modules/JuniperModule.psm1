# JuniperModule.psm1
# Parser for Juniper JunOS network devices
# Parses: show interfaces, show route, show configuration, show version

Set-StrictMode -Version Latest

function Get-JuniperDeviceFacts {
    <#
    .SYNOPSIS
    Parses Juniper JunOS device output to extract device facts and interface information.
    .PARAMETER Lines
    Array of text lines from device output.
    .PARAMETER Blocks
    Optional hashtable of pre-parsed show command blocks.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Lines,
        [hashtable]$Blocks
    )

    function Get-Hostname {
        param([string[]]$Lines)
        # JunOS hostname from prompt (user@hostname>) or configuration
        foreach ($line in $Lines) {
            if ($line -match '^(\S+)@(\S+)[>#]') {
                return $matches[2]
            }
            if ($line -match '^\s*host-name\s+(\S+);') {
                return $matches[1]
            }
            if ($line -match '^\s*Hostname:\s*(\S+)') {
                return $matches[1]
            }
        }
        return 'Unknown'
    }

    function Get-ModelAndVersion {
        param([string[]]$Lines)
        $model = 'Unknown'
        $version = 'Unknown'

        foreach ($line in $Lines) {
            # Model: EX4300-48T, SRX340, MX480, etc.
            if ($line -match '(?i)Model:\s*(\S+)') {
                $model = $matches[1]
            }
            # Junos: 21.4R3-S2.3
            if ($line -match '(?i)Junos:\s*(\S+)') {
                $version = $matches[1]
            }
            # Alternative: JUNOS Software Release
            if ($version -eq 'Unknown' -and $line -match '(?i)JUNOS\s+\S+\s+\[(\S+)\]') {
                $version = $matches[1]
            }
        }

        return @($model, $version)
    }

    function Get-Uptime {
        param([string[]]$Lines)
        foreach ($line in $Lines) {
            # System booted: 2024-01-15 10:30:00 UTC (45 days ago)
            if ($line -match '(?i)System\s+booted.*\((.+?)\s*ago\)') {
                return $matches[1] + ' ago'
            }
            # Current time: ... System booted: ...
            if ($line -match '(?i)uptime:\s*(.+)$') {
                return $matches[1].Trim()
            }
        }
        return 'Unknown'
    }

    function Get-Location {
        param([string[]]$Lines)
        foreach ($line in $Lines) {
            # snmp { location "Building A, Floor 2"; }
            if ($line -match '(?i)location\s+"([^"]+)"') {
                return $matches[1]
            }
            if ($line -match '(?i)location\s+(\S+);') {
                return $matches[1]
            }
        }
        return ''
    }

    function Get-Interfaces {
        param([string[]]$Lines)
        $interfaces = [System.Collections.Generic.List[object]]::new()
        $currentInterface = $null
        $inTerse = $false

        foreach ($line in $Lines) {
            # Terse format: Interface  Admin Link Proto Local  Remote
            if ($line -match '^\s*Interface\s+Admin\s+Link') {
                $inTerse = $true
                continue
            }

            # Terse format row: ge-0/0/0  up  up
            if ($inTerse -and $line -match '^\s*([\w\-/\.]+)\s+(up|down)\s+(up|down)') {
                $iface = [PSCustomObject]@{
                    Port = $matches[1]
                    Name = ''
                    Status = if ([string]::Equals($matches[3], 'up', [System.StringComparison]::OrdinalIgnoreCase)) { 'connected' } else { 'notconnect' }
                    AdminStatus = $matches[2]
                    VLAN = ''
                    Duplex = ''
                    Speed = ''
                    Type = ''
                    Config = ''
                }
                [void]$interfaces.Add($iface)
                continue
            }

            # Detailed format: Physical interface: ge-0/0/0
            if ($line -match '^\s*Physical interface:\s*(\S+)') {
                if ($currentInterface) {
                    [void]$interfaces.Add($currentInterface)
                }
                $currentInterface = [PSCustomObject]@{
                    Port = $matches[1]
                    Name = ''
                    Status = 'Unknown'
                    AdminStatus = ''
                    VLAN = ''
                    Duplex = ''
                    Speed = ''
                    Type = ''
                    Config = ''
                }
                continue
            }

            if ($currentInterface) {
                # Description: uplink-to-core
                if ($line -match '^\s*Description:\s*(.+)$') {
                    $currentInterface.Name = $matches[1].Trim()
                }
                # Link-level type: Ethernet
                if ($line -match '^\s*Link-level type:\s*(\S+)') {
                    $currentInterface.Type = $matches[1]
                }
                # Speed: 1000mbps, Link-mode: Full-duplex
                if ($line -match '(?i)Speed:\s*(\S+)') {
                    $currentInterface.Speed = $matches[1]
                }
                if ($line -match '(?i)Link-mode:\s*(\S+)') {
                    $currentInterface.Duplex = $matches[1]
                }
                # Physical link is Up/Down
                if ($line -match '(?i)Physical link is\s+(Up|Down)') {
                    $currentInterface.Status = if ([string]::Equals($matches[1], 'Up', [System.StringComparison]::OrdinalIgnoreCase)) { 'connected' } else { 'notconnect' }
                }
                # Enabled/Disabled
                if ($line -match '(?i)(Enabled|Disabled),') {
                    $currentInterface.AdminStatus = $matches[1].ToLower()
                }
            }
        }

        if ($currentInterface) {
            [void]$interfaces.Add($currentInterface)
        }

        return $interfaces
    }

    function Get-Routes {
        param([string[]]$Lines)
        $routes = [System.Collections.Generic.List[object]]::new()

        foreach ($line in $Lines) {
            # 0.0.0.0/0  *[Static/5] 10:30:00  > to 10.0.0.1 via ge-0/0/0.0
            if ($line -match '^\s*([\d\.]+/\d+)\s+\*?\[(\w+)/(\d+)\].*?(?:via|to)\s+(\S+)') {
                $route = [PSCustomObject]@{
                    Prefix = $matches[1]
                    Protocol = $matches[2]
                    Preference = $matches[3]
                    NextHop = $matches[4]
                }
                [void]$routes.Add($route)
            }
        }

        return $routes
    }

    function Get-InterfaceConfigs {
        param([string[]]$Lines)
        $configs = @{}
        $currentIface = $null
        $configLines = [System.Collections.Generic.List[string]]::new()
        $braceDepth = 0

        foreach ($line in $Lines) {
            # interfaces { ge-0/0/0 { ... } }
            if ($line -match '^\s*(?:interface\s+)?(\S+)\s*\{') {
                if ($currentIface -and $configLines.Count -gt 0) {
                    $configs[$currentIface] = [string]::Join("`r`n", $configLines)
                }
                $currentIface = $matches[1]
                $configLines = [System.Collections.Generic.List[string]]::new()
                $braceDepth = 1
                [void]$configLines.Add($line)
                continue
            }

            if ($currentIface) {
                [void]$configLines.Add($line)
                $braceDepth += ([regex]::Matches($line, '\{')).Count
                $braceDepth -= ([regex]::Matches($line, '\}')).Count
                if ($braceDepth -le 0) {
                    $configs[$currentIface] = [string]::Join("`r`n", $configLines)
                    $currentIface = $null
                    $configLines = [System.Collections.Generic.List[string]]::new()
                }
            }
        }

        return $configs
    }

    # Main parsing logic
    if (-not $Blocks) {
        try {
            $Blocks = DeviceLogParserModule\Get-ShowCommandBlocks -Lines $Lines
        } catch {
            $Blocks = @{}
        }
    }

    $versionLines = DeviceLogParserModule\Get-ShowBlock -Blocks $Blocks -Lines $Lines `
        -PreferredKeys @('show version') `
        -CommandRegexes @('^[\w@\-]+[>#]\s*show\s+version') `
        -DefaultValue $Lines

    $intLines = DeviceLogParserModule\Get-ShowBlock -Blocks $Blocks -Lines $Lines `
        -PreferredKeys @('show interfaces terse', 'show interfaces') `
        -CommandRegexes @('^[\w@\-]+[>#]\s*show\s+interfaces') `
        -DefaultValue $Lines

    $configLines = DeviceLogParserModule\Get-ShowBlock -Blocks $Blocks -Lines $Lines `
        -PreferredKeys @('show configuration', 'show config') `
        -CommandRegexes @('^[\w@\-]+[>#]\s*show\s+configuration') `
        -DefaultValue $Lines

    $routeLines = DeviceLogParserModule\Get-ShowBlock -Blocks $Blocks -Lines $Lines `
        -PreferredKeys @('show route', 'show route table') `
        -CommandRegexes @('^[\w@\-]+[>#]\s*show\s+route') `
        -DefaultValue @()

    $hostname = Get-Hostname -Lines $Lines
    $modelInfo = Get-ModelAndVersion -Lines $versionLines
    $uptime = Get-Uptime -Lines $versionLines
    $location = Get-Location -Lines $configLines
    $interfaces = Get-Interfaces -Lines $intLines
    $routes = Get-Routes -Lines $routeLines
    $configs = Get-InterfaceConfigs -Lines $configLines

    # Combine interface data with configs
    $combinedInterfaces = [System.Collections.Generic.List[object]]::new()
    foreach ($iface in $interfaces) {
        $cfgText = if ($configs.ContainsKey($iface.Port)) { $configs[$iface.Port] } else { '' }
        $combined = [PSCustomObject]@{
            Port = $iface.Port
            Name = $iface.Name
            Status = $iface.Status
            AdminStatus = $iface.AdminStatus
            VLAN = $iface.VLAN
            Duplex = $iface.Duplex
            Speed = $iface.Speed
            Type = $iface.Type
            Config = $cfgText
            LearnedMACs = ''
            LearnedMACsFull = ''
            AuthState = ''
            AuthMode = ''
            AuthClientMAC = ''
            AuthVLAN = ''
        }
        [void]$combinedInterfaces.Add($combined)
    }

    return [PSCustomObject]@{
        Hostname = $hostname
        Make = 'Juniper'
        Model = $modelInfo[0]
        Version = $modelInfo[1]
        Uptime = $uptime
        Location = $location
        InterfaceCount = $combinedInterfaces.Count
        InterfacesCombined = $combinedInterfaces
        Routes = $routes
    }
}

Export-ModuleMember -Function Get-JuniperDeviceFacts
