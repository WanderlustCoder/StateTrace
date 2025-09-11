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
        # Use a typed List[object] for accumulating interface records.  Avoid
        $results = New-Object 'System.Collections.Generic.List[object]'
        $parsing = $false
        foreach ($line in $Lines) {
            if ($line -match "^\s*Port\s+Name\s+Status\s+Vlan\s+Duplex\s+Speed\s+Type") {
                $parsing = $true
                continue
            }
            if ($parsing -and $line -match "^\s*(Et\d+(?:/\d+)*|Po\d+|Ma\d*)\s+(.*?)\s+(connected|notconnect|errdisabled|disabled)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+.*)$") {
                $ifaceObj = [PSCustomObject]@{
                    Port   = $matches[1]
                    Name   = $matches[2].Trim()
                    Status = $matches[3]
                    VLAN   = $matches[4]
                    Duplex = $matches[5]
                    Speed  = $matches[6]
                    Type   = $matches[7]
                }
                [void]$results.Add($ifaceObj)
            }
            if ($parsing -and $line -match "^\s*$") {
                break
            }
        }
        return $results
    }

    function Get-MacTable {
        # Use a typed List[object] to accumulate MAC table entries efficiently.
        $results      = New-Object 'System.Collections.Generic.List[object]'
        $inMacSection = $false
        foreach ($line in $Lines) {
            if ($line -match "^\s*Vlan\s+Mac\s+Address\s+Type\s+Ports") {
                $inMacSection = $true
                continue
            }
            if ($inMacSection -and $line -match "^\s*$") {
                break
            }
            if ($inMacSection -and $line -match "^\s*(\d+)\s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})\s+(\S+)\s+(\S+)\b") {
                $entry = [PSCustomObject]@{
                    VLAN = $matches[1]
                    MAC  = $matches[2]
                    Type = $matches[3]
                    Port = $matches[4]
                }
                [void]$results.Add($entry)
            }
        }
        return $results
    }

    function Get-Dot1xStatus {
        # Use a typed List[object] to accumulate dot1x status entries.
        $results = New-Object 'System.Collections.Generic.List[object]'
        $parsing = $false
        foreach ($line in $Lines) {
            if ($line -match "^\s*Port\s+Authorized\s+Mode\s+MAC\s+Address\s+Vlan") {
                $parsing = $true
                continue
            }
            if ($parsing -and $line -match "^\s*$") {
                break
            }
            if ($parsing -and $line -match "^\s*(Et\d+(?:/\d+)*|Po\d+|Ma\d*)\s+(\S+)\s+(\S+)(?:\s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4}))?(?:\s+(\d+))?") {
                $entry = [PSCustomObject]@{
                    Port  = $matches[1]
                    State = $matches[2]
                    Mode  = $matches[3]
                    MAC   = if ($matches[4]) { $matches[4] } else { "" }
                    VLAN  = if ($matches[5]) { $matches[5] } else { "" }
                }
                [void]$results.Add($entry)
            }
        }
        return $results
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
    if (-not $intStatusLines) { $intStatusLines = $Lines }
    $macLines  = if ($Blocks.ContainsKey('show mac address-table')) { $Blocks['show mac address-table'] } else { @() }
    $authLines = if ($Blocks.ContainsKey('show authentication sessions')) { $Blocks['show authentication sessions'] } else { @() }

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
        # a) All learned MACs for this port using the precomputed lookup
        $learnedMACs = if ($macsByPort.ContainsKey($iface.Port)) { $macsByPort[$iface.Port] } else { @() }
        # Convert to array when joining to avoid joining individual characters of the string list
        $macList = if ($learnedMACs.Count -gt 0) { @($learnedMACs) -join "," } else { "" }

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