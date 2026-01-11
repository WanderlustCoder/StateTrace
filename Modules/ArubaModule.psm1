# ArubaModule.psm1
# Parser for Aruba network devices (ArubaOS-CX and AOS-Switch)
# Parses: show interfaces, show vlan, show running-config, show version

Set-StrictMode -Version Latest

function Get-ArubaDeviceFacts {
    <#
    .SYNOPSIS
    Parses Aruba device output to extract device facts and interface information.
    .DESCRIPTION
    Supports both ArubaOS-CX (modern) and AOS-Switch (legacy ProCurve) platforms.
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
            # ArubaOS-CX prompt: switch# or switch# show version
            if ($line -match '^(\S+)[#>]\s*') {
                return $matches[1]
            }
            # hostname in config
            if ($line -match '^\s*hostname\s+"?([^"]+)"?') {
                return $matches[1].Trim()
            }
            # ProCurve: Hostname: SWITCH-01
            if ($line -match '(?i)Hostname\s*:\s*(\S+)') {
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
            # ArubaOS-CX: Product Name: Aruba 6300M 48G CL6 PoE 4SFP56 Swch
            if ($line -match '(?i)Product\s+Name:\s*(.+)$') {
                $model = $matches[1].Trim()
            }
            # AOS-Switch: J9772A Switch 2530-48G-PoE+
            if ($model -eq 'Unknown' -and $line -match '^\s*([A-Z]\d{4}[A-Z]?)\s+(.+)$') {
                $model = "$($matches[1]) $($matches[2])".Trim()
            }
            # Software Version: FL.10.10.1010 or ArubaOS-CX ML.10.08.0001
            if ($line -match '(?i)Software\s+(?:Version|Image)\s*:\s*(\S+)') {
                $version = $matches[1]
            }
            # Version: WC.16.10.0003
            if ($version -eq 'Unknown' -and $line -match '(?i)Version\s*:\s*(\S+)') {
                $version = $matches[1]
            }
        }

        return @($model, $version)
    }

    function Get-Uptime {
        param([string[]]$Lines)
        foreach ($line in $Lines) {
            # Up Time: 45 days, 12:30:45
            if ($line -match '(?i)Up\s*Time\s*:\s*(.+)$') {
                return $matches[1].Trim()
            }
            # System has been up for 45 days
            if ($line -match '(?i)been\s+up\s+(?:for\s+)?(.+)$') {
                return $matches[1].Trim()
            }
        }
        return 'Unknown'
    }

    function Get-Location {
        param([string[]]$Lines)
        foreach ($line in $Lines) {
            # snmp-server location "Building A"
            if ($line -match '(?i)snmp-server\s+location\s+"?([^"]+)"?') {
                return $matches[1].Trim()
            }
            # Location: Building A
            if ($line -match '(?i)Location\s*:\s*(.+)$') {
                return $matches[1].Trim()
            }
        }
        return ''
    }

    function Get-Interfaces {
        param([string[]]$Lines)
        $interfaces = [System.Collections.Generic.List[object]]::new()
        $inTable = $false

        foreach ($line in $Lines) {
            # ArubaOS-CX: Interface ...  Status
            if ($line -match '^\s*Port\s+.*Status' -or $line -match '^\s*Interface\s+.*Admin') {
                $inTable = $true
                continue
            }

            # Skip header separators
            if ($line -match '^[-=\s]+$') {
                continue
            }

            # AOS-Switch format: 1     Half   10     No   Down    Down
            if ($inTable -and $line -match '^\s*(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)') {
                $iface = [PSCustomObject]@{
                    Port = $matches[1]
                    Name = ''
                    Status = if ([string]::Equals($matches[6], 'Up', [System.StringComparison]::OrdinalIgnoreCase)) { 'connected' } else { 'notconnect' }
                    AdminStatus = $matches[5]
                    VLAN = ''
                    Duplex = $matches[2]
                    Speed = $matches[3]
                    Type = ''
                    Config = ''
                }
                [void]$interfaces.Add($iface)
                continue
            }

            # ArubaOS-CX format: 1/1/1  up  up  --  1G  1G  native  vlan1
            if ($inTable -and $line -match '^\s*([\d/]+)\s+(up|down)\s+(up|down)\s+') {
                # Use regex captures for Port/Admin/Status; filter empty strings from split for remaining fields
                $parts = @($line.Trim() -split '\s+' | Where-Object { $_ -ne '' })
                $iface = [PSCustomObject]@{
                    Port = $matches[1]
                    Name = ''
                    Status = if ([string]::Equals($matches[3], 'up', [System.StringComparison]::OrdinalIgnoreCase)) { 'connected' } else { 'notconnect' }
                    AdminStatus = $matches[2]
                    VLAN = if ($parts.Length -gt 7) { $parts[7] } else { '' }
                    Duplex = ''
                    Speed = if ($parts.Length -gt 4) { $parts[4] } else { '' }
                    Type = if ($parts.Length -gt 5) { $parts[5] } else { '' }
                    Config = ''
                }
                [void]$interfaces.Add($iface)
                continue
            }

            # Detailed interface output
            if ($line -match '^\s*interface\s+(\S+)') {
                $iface = [PSCustomObject]@{
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
                [void]$interfaces.Add($iface)
            }
        }

        return $interfaces
    }

    function Get-VLANs {
        param([string[]]$Lines)
        $vlans = [System.Collections.Generic.List[object]]::new()

        foreach ($line in $Lines) {
            # VLAN ID format: 100  Production   up  ok  static
            if ($line -match '(?i)^\s*(\d+)\s+(.+?)\s+(up|down)\s+\S+\s+(Port-based|Static|Dynamic)\b') {
                $vlan = [PSCustomObject]@{
                    ID = $matches[1]
                    Name = $matches[2].Trim()
                    Type = $matches[4]
                }
                [void]$vlans.Add($vlan)
            }
            # Simple format: vlan 100 name Production
            if ($line -match '^\s*vlan\s+(\d+)\s+name\s+(.+)$') {
                $vlan = [PSCustomObject]@{
                    ID = $matches[1]
                    Name = $matches[2].Trim()
                    Type = 'Static'
                }
                [void]$vlans.Add($vlan)
            }
        }

        return $vlans
    }

    function Get-InterfaceConfigs {
        param([string[]]$Lines)
        $configs = @{}
        $currentIface = $null
        $configLines = [System.Collections.Generic.List[string]]::new()

        foreach ($line in $Lines) {
            if ($line -match '^\s*interface\s+(\S+)') {
                if ($currentIface -and $configLines.Count -gt 0) {
                    $configs[$currentIface] = [string]::Join("`r`n", $configLines)
                }
                $currentIface = $matches[1]
                $configLines = [System.Collections.Generic.List[string]]::new()
                [void]$configLines.Add($line)
                continue
            }

            if ($currentIface) {
                # End of interface block
                if ($line -match '^\s*exit\s*$' -or ($line -match '^\S' -and $line -notmatch '^\s')) {
                    $configs[$currentIface] = [string]::Join("`r`n", $configLines)
                    $currentIface = $null
                    $configLines = [System.Collections.Generic.List[string]]::new()
                    continue
                }
                [void]$configLines.Add($line)
            }
        }

        if ($currentIface -and $configLines.Count -gt 0) {
            $configs[$currentIface] = [string]::Join("`r`n", $configLines)
        }

        return $configs
    }

    function Get-MacTable {
        param([string[]]$Lines)
        $macs = [System.Collections.Generic.List[object]]::new()

        foreach ($line in $Lines) {
            # Format: xxxx-xxxx-xxxx  1  1/1/1  dynamic
            if ($line -match '([0-9A-Fa-f]{4}[\-\.][0-9A-Fa-f]{4}[\-\.][0-9A-Fa-f]{4})\s+(\d+)\s+(\S+)\s+(\S+)') {
                $mac = [PSCustomObject]@{
                    MAC = $matches[1]
                    VLAN = $matches[2]
                    Port = $matches[3]
                    Type = $matches[4]
                }
                [void]$macs.Add($mac)
            }
        }

        return $macs
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
        -PreferredKeys @('show version', 'show system') `
        -CommandRegexes @('^\S+[#>]\s*show\s+version', '^\S+[#>]\s*show\s+system') `
        -DefaultValue $Lines

    $intLines = DeviceLogParserModule\Get-ShowBlock -Blocks $Blocks -Lines $Lines `
        -PreferredKeys @('show interface brief', 'show interfaces brief', 'show interface') `
        -CommandRegexes @('^\S+[#>]\s*show\s+interface') `
        -DefaultValue $Lines

    $configLines = DeviceLogParserModule\Get-ShowBlock -Blocks $Blocks -Lines $Lines `
        -PreferredKeys @('show running-config', 'show run') `
        -CommandRegexes @('^\S+[#>]\s*show\s+running-config') `
        -DefaultValue $Lines

    $vlanLines = DeviceLogParserModule\Get-ShowBlock -Blocks $Blocks -Lines $Lines `
        -PreferredKeys @('show vlan', 'show vlans') `
        -CommandRegexes @('^\S+[#>]\s*show\s+vlans?') `
        -DefaultValue @()

    $macLines = DeviceLogParserModule\Get-ShowBlock -Blocks $Blocks -Lines $Lines `
        -PreferredKeys @('show mac-address-table', 'show mac address-table') `
        -CommandRegexes @('^\S+[#>]\s*show\s+mac') `
        -DefaultValue @()

    $hostname = Get-Hostname -Lines $Lines
    $modelInfo = Get-ModelAndVersion -Lines $versionLines
    $uptime = Get-Uptime -Lines $versionLines
    $location = Get-Location -Lines $configLines
    $interfaces = Get-Interfaces -Lines $intLines
    $vlans = Get-VLANs -Lines $vlanLines
    $configs = Get-InterfaceConfigs -Lines $configLines
    $macs = Get-MacTable -Lines $macLines

    # Build MAC lookup
    $macsByPort = @{}
    foreach ($m in $macs) {
        if (-not $macsByPort.ContainsKey($m.Port)) {
            $macsByPort[$m.Port] = [System.Collections.Generic.List[string]]::new()
        }
        [void]$macsByPort[$m.Port].Add($m.MAC)
    }

    # Combine interface data
    $combinedInterfaces = [System.Collections.Generic.List[object]]::new()
    foreach ($iface in $interfaces) {
        $cfgText = if ($configs.ContainsKey($iface.Port)) { $configs[$iface.Port] } else { '' }
        $portMacs = if ($macsByPort.ContainsKey($iface.Port)) { $macsByPort[$iface.Port] } else { @() }

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
            LearnedMACs = if ($portMacs.Count -gt 0) { $portMacs[0] } else { '' }
            LearnedMACsFull = [string]::Join(',', $portMacs)
            AuthState = ''
            AuthMode = ''
            AuthClientMAC = ''
            AuthVLAN = ''
        }
        [void]$combinedInterfaces.Add($combined)
    }

    return [PSCustomObject]@{
        Hostname = $hostname
        Make = 'Aruba'
        Model = $modelInfo[0]
        Version = $modelInfo[1]
        Uptime = $uptime
        Location = $location
        InterfaceCount = $combinedInterfaces.Count
        InterfacesCombined = $combinedInterfaces
        VLANs = $vlans
    }
}

Export-ModuleMember -Function Get-ArubaDeviceFacts
