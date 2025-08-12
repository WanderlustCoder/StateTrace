function Get-AristaDeviceFacts {
    param (
        [string[]]$Lines,
        [hashtable]$Blocks
    )

    #
    # 1) Extract Hostname, Model/Version, Uptime, Location, Interfaces, MacTable, Dot1xStatus
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
        $results = @()
        $parsing = $false
        foreach ($line in $Lines) {
            if ($line -match "^\s*Port\s+Name\s+Status\s+Vlan\s+Duplex\s+Speed\s+Type") {
                $parsing = $true
                continue
            }
            if ($parsing -and $line -match "^\s*(Et\d+(?:/\d+)*|Po\d+|Ma\d*)\s+(.*?)\s+(connected|notconnect|errdisabled|disabled)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+.*)$") {
                $results += [PSCustomObject]@{
                    Port   = $matches[1]
                    Name   = $matches[2].Trim()
                    Status = $matches[3]
                    VLAN   = $matches[4]
                    Duplex = $matches[5]
                    Speed  = $matches[6]
                    Type   = $matches[7]
                }
            }
            if ($parsing -and $line -match "^\s*$") {
                break
            }
        }
        return $results
    }

    function Get-MacTable {
        $results      = @()
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
                $results += [PSCustomObject]@{
                    VLAN = $matches[1]
                    MAC  = $matches[2]
                    Type = $matches[3]
                    Port = $matches[4]
                }
            }
        }
        return $results
    }

    function Get-Dot1xStatus {
        $results = @()
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
                $results += [PSCustomObject]@{
                    Port = $matches[1]
                    State = $matches[2]
                    Mode  = $matches[3]
                    MAC   = if ($matches[4]) { $matches[4] } else { "" }
                    VLAN  = if ($matches[5]) { $matches[5] } else { "" }
                }
            }
        }
        return $results
    }

    #
    # 2) New helper: extract each interface's full config block
    #
    function Get-InterfaceConfigs {
    $ht = @{}
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -imatch "^\s*interface\s+(?:Et|Ethernet)(\d+(?:/\d+)*)\b") {
            $portName    = "Et" + $matches[1]
            $configLines = @($line)
            $j           = $i + 1
            while ($j -lt $Lines.Count) {
                $next = $Lines[$j]
                if ($next -match "^\s*$" -or $next -imatch "^\s*interface\s+") {
                    break
                }
                $configLines += $next
                $j++
            }
            $ht[$portName] = $configLines -join "`r`n"
            $i              = $j - 1
        }
    }
    return $ht
}

    #
    # 3) Gather all pieces
    #
    $hostname   = Get-Hostname
    $modelInfo  = Get-ModelAndVersion
    $uptime     = Get-Uptime
    $location   = Get-SnmpLocation -Lines $Lines

    $interfaces = Get-Interfaces
    $macs       = Get-MacTable
    $auth       = Get-Dot1xStatus
    $configs    = Get-InterfaceConfigs

    #
    # 4) Build CombinedInterfaces array with an extra Config property
    #
    $combinedInterfaces = @()
    foreach ($iface in $interfaces) {
        # a) All learned MACs for this port
        $learnedMACs = $macs | Where-Object { $_.Port -eq $iface.Port } | ForEach-Object { $_.MAC }
        $macList = if ($learnedMACs.Count -gt 0) { $learnedMACs -join "," } else { "" }

        # b) 802.1X details
        $dot1xRow = $auth | Where-Object { $_.Port -eq $iface.Port }
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
        $combinedInterfaces += [PSCustomObject]@{
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
            # Template     = $someLookupFunction($iface.Port)
        }
    }

    #
    # 5) Return the summary object
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
