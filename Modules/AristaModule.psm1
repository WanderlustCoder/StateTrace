function Get-AristaDeviceFacts {
    param (
        [string[]]$Lines,
        [hashtable]$Blocks
    )

    #

    function Get-Hostname {
        $hostname = DeviceParsingCommon\Get-HostnameFromPrompt -Lines $Lines
        if ($hostname) { return $hostname }
        return "Unknown"
    }

    function Get-ModelAndVersion {
        $model   = "Unknown"
        $version = "Unknown"
        foreach ($line in $Lines) {
            if ($line -match "^Arista\s+(\S+)") {
                $model = $matches[1]
                continue
            }
            elseif (($model -eq "Unknown") -and $line -match "^\s*Model(?:\s+number)?:\s*(.+)$") {
                $model = $matches[1].Trim()
                continue
            }
            elseif ($line -match "Software image version:\s*(\S+)") {
                $version = $matches[1]
            }
        }
        return @($model, $version)
    }

    function Get-Uptime {
        $uptime = DeviceParsingCommon\Get-UptimeFromLines -Lines $Lines -Patterns @('(?i)uptime:\s*(.+)$', '(?i)uptime\s+is\s+(.+)$')
        if ($uptime) { return $uptime }
        return "Unknown"
    }

    function Get-SnmpLocation {
        param([string[]]$Lines)
        # Delegate to the shared helper that handles vendor-specific keywords
        return Get-SnmpLocationFromLines -Lines $Lines
    }

    function Get-Interfaces {
        $propertyMap = [ordered]@{
            Port   = 1
            Name   = { param($match) $match.Groups[2].Value.Trim() }
            Status = 3
            VLAN   = 4
            Duplex = 5
            Speed  = 6
            Type   = { param($match) $match.Groups[7].Value.Trim() }
        }
        return DeviceParsingCommon\Invoke-RegexTableParser -Lines $Lines -HeaderPattern '^\s*Port\s+Name\s+Status\s+Vlan\s+Duplex\s+Speed\s+Type' -RowPattern '^\s*(Et\d+(?:/\d+)*|Po\d+|Ma\d*)\s+(.*?)\s+(connected|notconnect|errdisabled|disabled)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+.*)$' -PropertyMap $propertyMap
    }

    function Get-MacTable {
        $portTransform = { param($p) DeviceParsingCommon\ConvertTo-ShortPortName -Port $p }
        return DeviceParsingCommon\ConvertFrom-MacTableRegex -Lines $Lines -HeaderPattern '^\s*Vlan\s+Mac\s+Address\s+Type\s+Ports' -RowPattern '^\s*(\d+)\s+([0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4})\s+(\S+)\s+(\S+)\b' -VlanGroup 1 -MacGroup 2 -PortGroup 4 -PortTransform $portTransform
    }

    function Get-Dot1xStatus {
        $propertyMap = [ordered]@{
            Port = 1
            State = 2
            Mode  = 3
            MAC   = { param($match) if ($match.Groups[4].Success) { $match.Groups[4].Value.Trim() } else { '' } }
            VLAN  = { param($match) if ($match.Groups[5].Success) { $match.Groups[5].Value.Trim() } else { '' } }
        }
        return DeviceParsingCommon\Invoke-RegexTableParser -Lines $Lines -HeaderPattern '^\s*Port\s+Authorized\s+Mode\s+MAC\s+Address\s+Vlan' -RowPattern '^\s*(Et\d+(?:/\d+)*|Po\d+|Ma\d*)\s+(\S+)\s+(\S+)(?:\s+([0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}))?(?:\s+(\d+))?' -PropertyMap $propertyMap
    }

    #
    function Get-InterfaceConfigs {
    $ht = @{}
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -imatch "^\s*interface\s+(?:Et|Ethernet)(\d+(?:/\d+)*)\b") {
            $portName    = "Et" + $matches[1]
            # Accumulate config lines in a typed List[string] for efficiency
            $configLines = [System.Collections.Generic.List[string]]::new()
            [void]$configLines.Add($line)
            $j           = $i + 1
            while ($j -lt $Lines.Count) {
                $next = $Lines[$j]
                if ($next -match "^\s*$" -or $next -imatch "^\s*interface\s+") {
                    break
                }
                [void]$configLines.Add($next)
                $j++
            }
            $ht[$portName] = $configLines -join "`r`n"
            $i              = $j - 1
        }
    }
    return $ht
}

    #
    if (-not $Blocks) {
        try {
            $Blocks = DeviceLogParserModule\Get-ShowCommandBlocks -Lines $Lines
        } catch {
            $Blocks = @{}
        }
    }
    # Determine targeted blocks for each category of information.  Fallback to the full
    $versionLines   = DeviceLogParserModule\Get-ShowBlock -Blocks $Blocks -Lines $Lines -PreferredKeys @('show version') -CommandRegexes @('^[^\s]+[>#]\s*(?:do\s+)?show\s+version') -DefaultValue $Lines
    $runCfgLines    = DeviceLogParserModule\Get-ShowBlock -Blocks $Blocks -Lines $Lines -PreferredKeys @('show running-config') -CommandRegexes @('^[^\s]+[>#]\s*(?:do\s+)?show\s+running-config') -DefaultValue $Lines
    $intStatusLines = DeviceLogParserModule\Get-ShowBlock -Blocks $Blocks -Lines $Lines -PreferredKeys @('show interfaces status','show interface status','show interfaces brief','show interfaces') -RegexPatterns @('^show\s+interfaces?\s+status') -CommandRegexes @('^[^\s]+[>#]\s*(?:do\s+)?show\s+interfaces?\s+status') -DefaultValue $Lines
    $macLines       = DeviceLogParserModule\Get-ShowBlock -Blocks $Blocks -Lines $Lines -PreferredKeys @('show mac address-table','show mac-address-table') -RegexPatterns @('^show\s+mac[- ]address[- ]table') -CommandRegexes @('^[^\s]+[>#]\s*(?:do\s+)?show\s+mac[- ]address[- ]table') -DefaultValue @()
    $authLines      = DeviceLogParserModule\Get-ShowBlock -Blocks $Blocks -Lines $Lines -PreferredKeys @('show authentication sessions','show authentication session') -RegexPatterns @('^show\s+authentication\s+sessions?','^show\s+auth\w*\s+ses\w*') -CommandRegexes @('^[^\s]+[>#]\s*(?:do\s+)?show\s+authentication\s+sessions?') -DefaultValue @()

    # Preserve the original Lines value so it can be restored after targeted parsing.
    $origLines = $Lines

    # Hostname may appear in prompts or config; search the full lines for it.
    $hostname = Get-Hostname

    # Use the version block for model, version and uptime parsing.
    $Lines = $versionLines
    $modelInfo = Get-ModelAndVersion
    $uptime    = Get-Uptime

    # Use the running-config block for SNMP location and interface configs
    $Lines = $runCfgLines
    $location = Get-SnmpLocation -Lines $runCfgLines

    # Use the interface status block for interface properties such as Status, VLAN, Duplex, Speed
    $Lines = $intStatusLines
    $interfaces = Get-Interfaces

    # Parse the MAC table only when the corresponding block is present
    $Lines = $macLines
    $macs = if ($macLines.Count -gt 0) { Get-MacTable } else { @() }

    # Parse dot1x status only when that section exists
    $Lines = $authLines
    $auth = if ($authLines.Count -gt 0) { Get-Dot1xStatus } else { @() }

    # Build per-port lookup tables for MAC addresses and dot1x status
    $macsByPort = @{}
    foreach ($m in $macs) {
        if (-not $macsByPort.ContainsKey($m.Port)) {
            $macsByPort[$m.Port] = [System.Collections.Generic.List[string]]::new()
        }
        [void]$macsByPort[$m.Port].Add([string]$m.MAC)
    }
    $authByPort = @{}
    foreach ($a in $auth) {
        if (-not $authByPort.ContainsKey($a.Port)) {
            $authByPort[$a.Port] = $a
        }
    }

    # Interface configuration blocks come from the running-config
    $Lines = $runCfgLines
    $configs = Get-InterfaceConfigs

    # Restore the original Lines array for any remaining operations.
    $Lines = $origLines

    #
    $combinedInterfaces = [System.Collections.Generic.List[object]]::new()
    foreach ($iface in $interfaces) {
        # a) All learned MACs for this port using the precomputed lookup.  Display only
        # the first MAC in the grid to avoid excessively wide columns; store the full
        # list separately for downstream use.
        $learnedMACs = if ($macsByPort.ContainsKey($iface.Port)) { $macsByPort[$iface.Port] } else { @() }
        if ($learnedMACs.Count -gt 0) {
            # $learnedMACs is already a list of strings
            $macList     = $learnedMACs[0]
            $macListFull = [string]::Join(',', $learnedMACs)
        } else {
            $macList     = ""
            $macListFull = ""
        }

        # b) 802.1X details using the pre-indexed lookup
        $dot1xRow = if ($authByPort.ContainsKey($iface.Port)) { $authByPort[$iface.Port] } else { $null }
        if ($dot1xRow) {
            $authState     = $dot1xRow.State
            $authMode      = $dot1xRow.Mode
            $authClientMAC = $dot1xRow.MAC
            $authVlan      = $dot1xRow.VLAN
        }
        else {
            $authState     = ""
            $authMode      = ""
            $authClientMAC = ""
            $authVlan      = ""
        }

        # c) Configuration text for this port
        $cfgText = if ($configs.ContainsKey($iface.Port)) { $configs[$iface.Port] } else { "" }

        # d) Combine into one PSCustomObject
        $ciObj = [PSCustomObject]@{
            Port          = $iface.Port
            Name          = $iface.Name
            Status        = $iface.Status
            VLAN          = $iface.VLAN
            Duplex        = $iface.Duplex
            Speed         = $iface.Speed
            Type          = $iface.Type

            LearnedMACs   = $macList
            LearnedMACsFull = $macListFull
            AuthState     = $authState
            AuthMode      = $authMode
            AuthClientMAC = $authClientMAC
            AuthVLAN      = $authVlan

            Config        = $cfgText

            # (Optional) Template property can be added here if you parse it from the log:
        }
        [void]$combinedInterfaces.Add($ciObj)
    }

    #
    return [PSCustomObject]@{
        Hostname           = $hostname
        Make               = "Arista"
        Model              = $modelInfo[0]
        Version            = $modelInfo[1]
        Uptime             = $uptime
        Location           = $location
        InterfaceCount     = $interfaces.Count
        InterfacesCombined = $combinedInterfaces
    }
}
