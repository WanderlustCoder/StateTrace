# PaloAltoModule.psm1
# Parser for Palo Alto Networks PAN-OS firewalls
# Parses: show interface all, show routing route, show system info

Set-StrictMode -Version Latest

function Get-PaloAltoDeviceFacts {
    <#
    .SYNOPSIS
    Parses Palo Alto PAN-OS device output to extract device facts and interface information.
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
        foreach ($line in $Lines) {
            # hostname: PA-3220
            if ($line -match '(?i)hostname:\s*(\S+)') {
                return $matches[1]
            }
            # Prompt: admin@PA-3220>
            if ($line -match '^(\S+)@(\S+)[>#]') {
                return $matches[2]
            }
        }
        return 'Unknown'
    }

    function Get-ModelAndVersion {
        param([string[]]$Lines)
        $model = 'Unknown'
        $version = 'Unknown'

        foreach ($line in $Lines) {
            # model: PA-3220
            if ($line -match '(?i)^\s*model:\s*(\S+)') {
                $model = $matches[1]
            }
            # sw-version: 10.2.3
            if ($line -match '(?i)sw-version:\s*(\S+)') {
                $version = $matches[1]
            }
            # Alternative: PAN-OS Version
            if ($version -eq 'Unknown' -and $line -match '(?i)PAN-OS\s+(?:Version\s+)?(\S+)') {
                $version = $matches[1]
            }
        }

        return @($model, $version)
    }

    function Get-Uptime {
        param([string[]]$Lines)
        foreach ($line in $Lines) {
            # uptime: 45 days, 12:30:45
            if ($line -match '(?i)^\s*uptime:\s*(.+)$') {
                return $matches[1].Trim()
            }
        }
        return 'Unknown'
    }

    function Get-Location {
        param([string[]]$Lines)
        # Palo Alto uses device-group and location in Panorama
        foreach ($line in $Lines) {
            if ($line -match '(?i)^\s*device-location:\s*(.+)$') {
                return $matches[1].Trim()
            }
        }
        return ''
    }

    function Get-SerialNumber {
        param([string[]]$Lines)
        foreach ($line in $Lines) {
            if ($line -match '(?i)^\s*serial:\s*(\S+)') {
                return $matches[1]
            }
        }
        return ''
    }

    function Get-Interfaces {
        param([string[]]$Lines)
        $interfaces = [System.Collections.Generic.List[object]]::new()
        $currentInterface = $null

        foreach ($line in $Lines) {
            # Interface line: ethernet1/1  192.168.1.1/24  up  10000
            if ($line -match '^\s*(ethernet\d+/\d+|ae\d+|loopback\.\d+|tunnel\.\d+|vlan\.\d+)\s+') {
                # Use regex capture for Port; filter empty strings from split for remaining fields
                $parts = @($line.Trim() -split '\s+' | Where-Object { $_ -ne '' })
                $iface = [PSCustomObject]@{
                    Port = $matches[1]
                    Name = ''
                    IPAddress = ''
                    Status = 'Unknown'
                    VLAN = ''
                    Zone = ''
                    Speed = ''
                    Type = ''
                    Config = ''
                }

                # Parse remaining columns (start from index 1 since Port is at 0)
                for ($i = 1; $i -lt $parts.Length; $i++) {
                    $p = $parts[$i]
                    if ($p -match '^\d+\.\d+\.\d+\.\d+') {
                        $iface.IPAddress = $p
                    }
                    if ($p -match '^(up|down)$') {
                        $iface.Status = if ([string]::Equals($p, 'up', [System.StringComparison]::OrdinalIgnoreCase)) { 'connected' } else { 'notconnect' }
                    }
                    if ($p -match '^\d+$' -and [int]$p -gt 100) {
                        $iface.Speed = $p
                    }
                }

                [void]$interfaces.Add($iface)
                continue
            }

            # Detailed format: Name: ethernet1/1
            if ($line -match '^\s*Name:\s*(\S+)') {
                if ($currentInterface) {
                    [void]$interfaces.Add($currentInterface)
                }
                $currentInterface = [PSCustomObject]@{
                    Port = $matches[1]
                    Name = ''
                    IPAddress = ''
                    Status = 'Unknown'
                    VLAN = ''
                    Zone = ''
                    Speed = ''
                    Type = ''
                    Config = ''
                }
                continue
            }

            if ($currentInterface) {
                if ($line -match '^\s*Comment:\s*(.+)$') {
                    $currentInterface.Name = $matches[1].Trim()
                }
                if ($line -match '(?i)Link status:\s*(up|down)') {
                    $currentInterface.Status = if ([string]::Equals($matches[1], 'up', [System.StringComparison]::OrdinalIgnoreCase)) { 'connected' } else { 'notconnect' }
                }
                if ($line -match '(?i)Zone:\s*(\S+)') {
                    $currentInterface.Zone = $matches[1]
                }
                if ($line -match '(?i)Speed:\s*(\S+)') {
                    $currentInterface.Speed = $matches[1]
                }
                if ($line -match '(?i)Type:\s*(\S+)') {
                    $currentInterface.Type = $matches[1]
                }
                if ($line -match '(?i)IP Address:\s*(\S+)') {
                    $currentInterface.IPAddress = $matches[1]
                }
                if ($line -match '(?i)Tag:\s*(\d+)') {
                    $currentInterface.VLAN = $matches[1]
                }
                # End of interface block
                if ($line -match '^\s*$' -or $line -match '^-+$') {
                    [void]$interfaces.Add($currentInterface)
                    $currentInterface = $null
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
            # Format: 0.0.0.0/0  ethernet1/1  10.0.0.1  S  10
            if ($line -match '^\s*([\d\.]+/\d+)\s+(\S+)\s+([\d\.]+)\s+(\S+)\s+(\d+)') {
                $route = [PSCustomObject]@{
                    Prefix = $matches[1]
                    Interface = $matches[2]
                    NextHop = $matches[3]
                    Protocol = $matches[4]
                    Metric = $matches[5]
                }
                [void]$routes.Add($route)
            }
            # Alternative: destination, nexthop, metric, flags, interface
            if ($line -match '^\s*([\d\.]+/\d+)\s+via\s+([\d\.]+)\s+dev\s+(\S+)') {
                $route = [PSCustomObject]@{
                    Prefix = $matches[1]
                    Interface = $matches[3]
                    NextHop = $matches[2]
                    Protocol = 'Connected'
                    Metric = '0'
                }
                [void]$routes.Add($route)
            }
        }

        return $routes
    }

    function Get-Zones {
        param([string[]]$Lines)
        $zones = [System.Collections.Generic.List[object]]::new()

        foreach ($line in $Lines) {
            # Zone: trust  Interfaces: ethernet1/1, ethernet1/2
            if ($line -match '^\s*(\S+)\s+(trust|untrust|dmz|internal|external|\S+)\s+(.*)$') {
                # Check if this looks like a zone entry
                if ($line -match '^\s*Name:\s*(\S+)') {
                    $zone = [PSCustomObject]@{
                        Name = $matches[1]
                        Type = ''
                        Interfaces = @()
                    }
                    [void]$zones.Add($zone)
                }
            }
        }

        return $zones
    }

    function Get-HAPeerStatus {
        param([string[]]$Lines)
        $haInfo = @{
            Enabled = $false
            State = ''
            PeerState = ''
            PeerIP = ''
        }

        foreach ($line in $Lines) {
            if ($line -match '(?i)HA\s+mode:\s*(active|passive|disabled)') {
                $haInfo.Enabled = $matches[1] -ne 'disabled'
                $haInfo.State = $matches[1]
            }
            if ($line -match '(?i)peer:\s*(active|passive|suspended|tentative)') {
                $haInfo.PeerState = $matches[1]
            }
            if ($line -match '(?i)peer\s+HA\d*\s+IP:\s*([\d\.]+)') {
                $haInfo.PeerIP = $matches[1]
            }
        }

        return [PSCustomObject]$haInfo
    }

    # Main parsing logic
    if (-not $Blocks) {
        try {
            $Blocks = DeviceLogParserModule\Get-ShowCommandBlocks -Lines $Lines
        } catch {
            $Blocks = @{}
        }
    }

    $sysInfoLines = DeviceLogParserModule\Get-ShowBlock -Blocks $Blocks -Lines $Lines `
        -PreferredKeys @('show system info') `
        -CommandRegexes @('^\S+@\S+[>#]\s*show\s+system\s+info') `
        -DefaultValue $Lines

    $intLines = DeviceLogParserModule\Get-ShowBlock -Blocks $Blocks -Lines $Lines `
        -PreferredKeys @('show interface all', 'show interface') `
        -CommandRegexes @('^\S+@\S+[>#]\s*show\s+interface') `
        -DefaultValue $Lines

    $routeLines = DeviceLogParserModule\Get-ShowBlock -Blocks $Blocks -Lines $Lines `
        -PreferredKeys @('show routing route', 'show routing') `
        -CommandRegexes @('^\S+@\S+[>#]\s*show\s+routing') `
        -DefaultValue @()

    $haLines = DeviceLogParserModule\Get-ShowBlock -Blocks $Blocks -Lines $Lines `
        -PreferredKeys @('show high-availability state', 'show high-availability all') `
        -CommandRegexes @('^\S+@\S+[>#]\s*show\s+high-availability') `
        -DefaultValue @()

    $hostname = Get-Hostname -Lines $sysInfoLines
    $modelInfo = Get-ModelAndVersion -Lines $sysInfoLines
    $uptime = Get-Uptime -Lines $sysInfoLines
    $location = Get-Location -Lines $sysInfoLines
    $serial = Get-SerialNumber -Lines $sysInfoLines
    $interfaces = Get-Interfaces -Lines $intLines
    $routes = Get-Routes -Lines $routeLines
    $haStatus = Get-HAPeerStatus -Lines $haLines

    # Combine interface data
    $combinedInterfaces = [System.Collections.Generic.List[object]]::new()
    foreach ($iface in $interfaces) {
        $combined = [PSCustomObject]@{
            Port = $iface.Port
            Name = $iface.Name
            Status = $iface.Status
            IPAddress = $iface.IPAddress
            VLAN = $iface.VLAN
            Zone = $iface.Zone
            Speed = $iface.Speed
            Type = $iface.Type
            Config = $iface.Config
            # Standard fields for compatibility
            Duplex = ''
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
        Make = 'PaloAlto'
        Model = $modelInfo[0]
        Version = $modelInfo[1]
        Uptime = $uptime
        Location = $location
        SerialNumber = $serial
        InterfaceCount = $combinedInterfaces.Count
        InterfacesCombined = $combinedInterfaces
        Routes = $routes
        HAStatus = $haStatus
    }
}

Export-ModuleMember -Function Get-PaloAltoDeviceFacts
