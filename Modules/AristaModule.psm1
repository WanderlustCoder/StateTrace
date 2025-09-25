function Get-AristaDeviceFacts {
    param (
        [string[]]$Lines,
        [hashtable]$Blocks
    )

    #

    function Get-Hostname {
        foreach ($line in $Lines) {
            if ($line -match "^([^(]+?)(?:\([^)]*\))?#") {
                return $matches[1]
            }
        }
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
        foreach ($line in $Lines) {
            if ($line -match "Uptime:\s*(.+)$") {
                return $matches[1].Trim()
            }
        }
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
        $propertyMap = [ordered]@{
            VLAN = 1
            MAC  = 2
            Type = 3
            Port = 4
        }
        return DeviceParsingCommon\Invoke-RegexTableParser -Lines $Lines -HeaderPattern '^\s*Vlan\s+Mac\s+Address\s+Type\s+Ports' -RowPattern '^\s*(\d+)\s+([0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4})\s+(\S+)\s+(\S+)\b' -PropertyMap $propertyMap
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
            $configLines = New-Object 'System.Collections.Generic.List[string]'
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
            $Blocks = Get-ShowCommandBlocks -Lines $Lines
        } catch {
            $Blocks = @{}
        }
    }
    # Determine targeted blocks for each category of information.  Fallback to the full
    $versionLines = if ($Blocks.ContainsKey('show version')) { $Blocks['show version'] } else { $Lines }
    $runCfgLines  = if ($Blocks.ContainsKey('show running-config')) { $Blocks['show running-config'] } else { $Lines }
    $intStatusLines = $null
    foreach ($key in 'show interfaces status','show interface status','show interfaces brief','show interfaces') {
        if (-not $intStatusLines -and $Blocks.ContainsKey($key)) {
            $intStatusLines = $Blocks[$key]
        }
    }
    # If no exact key matched, search for any key that begins with
    # "show interfaces status" or "show interface status" to support
    # extended variants such as "show interfaces status port-channel".
    if (-not $intStatusLines) {
        foreach ($k in $Blocks.Keys) {
            if ($k -match '^show\s+interfaces?\s+status') { $intStatusLines = $Blocks[$k]; break }
        }
    }
    if (-not $intStatusLines) { $intStatusLines = $Lines }
    # Retrieve the MAC address table.  Accept variants of the command when
    # the exact "show mac address-table" or "show mac-address-table" key is
    # not present.  Search for keys beginning with the expected prefix.
    # Hyphens and spaces between "mac" and "address" as well as "address" and
    # "table" are tolerated in the pattern.
    if ($Blocks.ContainsKey('show mac address-table')) {
        $macLines = $Blocks['show mac address-table']
    } elseif ($Blocks.ContainsKey('show mac-address-table')) {
        $macLines = $Blocks['show mac-address-table']
    } else {
        $macLines = @()
        foreach ($k in $Blocks.Keys) {
            if ($k -match '^show\s+mac[- ]address[- ]table') { $macLines = $Blocks[$k]; break }
        }
    }
    # Retrieve authentication session lines.  Handle singular ("show authentication session")
    # and plural ("show authentication sessions") forms, and scan for any key
    # beginning with those prefixes.  The regex "^show\s+authentication\s+sessions?"
    # matches both singular and plural and captures extended forms such as
    # "show authentication sessions interface".  This ensures that data is
    # captured even when the command string differs from the canonical form.
    if ($Blocks.ContainsKey('show authentication sessions')) {
        $authLines = $Blocks['show authentication sessions']
    } elseif ($Blocks.ContainsKey('show authentication session')) {
        $authLines = $Blocks['show authentication session']
    } else {
        $authLines = @()
        # First attempt to match keys that begin with "show authentication session[s]" (plural or singular)
        foreach ($k in $Blocks.Keys) {
            if ($k -match '^show\s+authentication\s+sessions?') { $authLines = $Blocks[$k]; break }
        }
        # If still not found, attempt to match abbreviated commands such as "show auth ses".
        if (-not $authLines -or $authLines.Count -eq 0) {
            foreach ($k in $Blocks.Keys) {
                # Match commands like "show auth ses", "show auth sess", or other abbreviations.
                if ($k -match '^show\s+auth\w*\s+ses\w*') { $authLines = $Blocks[$k]; break }
            }
        }
    }

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
            $macsByPort[$m.Port] = New-Object 'System.Collections.Generic.List[string]'
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
    $combinedInterfaces = New-Object 'System.Collections.Generic.List[object]'
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
