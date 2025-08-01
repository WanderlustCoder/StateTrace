# Brocade Device Parsing Module
function Get-BrocadeDeviceFacts {
    param (
        [string[]]$Lines
    )

    function Get-ShowCommandBlocks {
        param([string[]]$Lines)
        $blocks = @{}
        $currentCmd = ''
        $buffer = @()
        $recording = $false

        foreach ($line in $Lines) {
            if ($line -match '^[^\s]+#\s*(show .+)$') {
                if ($recording -and $currentCmd) { $blocks[$currentCmd] = $buffer }
                $currentCmd = $matches[1].Trim().ToLower()
                $buffer = @(); $recording = $true; continue
            }
            if ($recording -and $line -match '^[^\s]+#') {
                $blocks[$currentCmd] = $buffer
                $currentCmd = ''; $buffer = @(); $recording = $false; continue
            }
            if ($recording) { $buffer += $line }
        }
        if ($recording -and $currentCmd) { $blocks[$currentCmd] = $buffer }
        return $blocks
    }

    function Normalize-PortName { param ($raw) return "Et$raw" }

    function Expand-PortRange {
        param ($start, $end)
        $startParts = $start -split '/'
        $endParts = $end -split '/'
        $stack = $startParts[0]; $slot = $startParts[1]
        $startPort = [int]$startParts[2]; $endPort = [int]$endParts[2]
        $ports = @()
        for ($i = $startPort; $i -le $endPort; $i++) {
            $ports += "Et$stack/$slot/$i"
        }
        return $ports
    }

    $blocks = Get-ShowCommandBlocks -Lines $Lines

    function Get-Hostname {
        foreach ($line in $Lines) {
            if ($line -match "^(\S+)[>#]") { return $matches[1] }
        }
        return "Unknown"
    }

    function Get-ModelAndVersion {
        param ($Block)
        $model = "Unknown"; $version = "Unknown"
        foreach ($line in $Block) {
            if ($line -match "HW:\s+(Stackable .+)") { $model = $matches[1] }
            elseif ($line -match "SW:\s+Version\s+(\S+)") { $version = $matches[1] }
        }
        return @($model, $version)
    }

    function Get-Uptime {
        param ($Block)
        foreach ($line in $Block) {
            if ($line -match "uptime is (.+)$") { return $matches[1].Trim() }
        }
        return "Unknown"
    }

    function Get-Location {
        param ($Block)
        foreach ($line in $Block) {
            if ($line -match "snmp-server location (.+)$") { return $matches[1].Trim() }
        }
        return "Unspecified"
    }

    function Get-VlanMap {
        param ($Block)
        $vlanMap = @{}
        foreach ($line in $Block) {
            if ($line -match "^vlan (\d+) name (.+?) by port") {
                $vlanMap[$matches[1]] = $matches[2].Trim()
            }
        }
        return $vlanMap
    }

    function Get-AuthModes {
        param ($Block)
        $dot1x = @(); $macauth = @()
        foreach ($line in $Block) {
            if ($line -match "dot1x enable ethe (\d+/\d+/\d+) to (\d+/\d+/\d+)") {
                $dot1x += Expand-PortRange $matches[1] $matches[2]
            } elseif ($line -match "mac-authentication enable ethe (\d+/\d+/\d+) to (\d+/\d+/\d+)") {
                $macauth += Expand-PortRange $matches[1] $matches[2]
            }
        }
        return @($dot1x, $macauth)
    }

    function Get-InterfacesBrief {
        param ($Block)
        $results = @()
        foreach ($line in $Block) {
            if ($line -match '^(\d+/\d+/\d+)\s+(Up|Down)\s+(Forward|Disabled)\s+(Full|Half)\s+(\S+)\s+\S+\s+\S+\s+\d+\s+\d+\s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})\s+(.*?)\s*$') {
                $results += [PSCustomObject]@{
                    RawPort = $matches[1]; Port = Normalize-PortName $matches[1]; Status = $matches[2]
                    State = $matches[3]; Duplex = $matches[4]; Speed = $matches[5]
                    MAC = $matches[6]; Name = $matches[7].Trim()
                }
            }
        }
        return $results
    }

    function Get-MacTable {
        param ($Block)
        $results = @()
        foreach ($line in $Block) {
            if ($line -match '^([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})\s+(\d+/\d+/\d+)\s+\S+\s+(\d+)') {
                $results += [PSCustomObject]@{
                    MAC = $matches[1]; Port = Normalize-PortName $matches[2]; VLAN = $matches[3]
                }
            }
        }
        return $results
    }

    function Get-AuthStatus {
        param ($Dot1xBlock, $MacAuthBlock)
        $dot1x = @{}; $macauth = @{}

        foreach ($line in $Dot1xBlock) {
            if ($line -match '^(\d+/\d+/\d+)\s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4}).*(AUTHENTICATED|AUTHENTICATING)$') {
                $port = Normalize-PortName $matches[1]
                $mac = $matches[2]
                $state = if ($matches[3] -eq 'AUTHENTICATED') { 'Authorized' } else { 'Authenticating' }
                $dot1x[$port] = [PSCustomObject]@{ Port = $port; MAC = $mac; State = $state; Mode = 'dot1x' }
            }
        }

        foreach ($line in $MacAuthBlock) {
            if ($line -match '^(\d+/\d+/\d+)\s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})\s+\S+\s+\d+\s+(Yes|No)') {
                $port = Normalize-PortName $matches[1]
                $mac = $matches[2]
                $auth = $matches[3]
                $state = if ($auth -eq 'Yes') { 'Authorized' } else { 'Unauthorized' }
                $macauth[$port] = [PSCustomObject]@{ Port = $port; MAC = $mac; State = $state; Mode = 'macauth' }
            }
        }

        $ports = $dot1x.Keys + $macauth.Keys | Sort-Object -Unique
        $result = foreach ($p in $ports) {
            if ($dot1x.ContainsKey($p)) { $dot1x[$p] }
            elseif ($macauth.ContainsKey($p)) { $macauth[$p] }
        }
        return $result
    }

    function Get-AuthenticationBlock {
        param ([string[]]$ConfigBlock)
        $buffer = @()
        $inside = $false
        foreach ($line in $ConfigBlock) {
            if ($line -match '^Authentication\s*$') {
                $inside = $true
                continue
            }
            elseif ($inside -and $line -match '^!') {
                break
            }
            elseif ($inside) {
                $buffer += $line.Trim()
            }
        }
        return $buffer
    }

    function Get-AuthDefaultVlan {
        param([string[]]$AuthConfig)
        foreach ($line in $AuthConfig) {
            if ($line -match 'auth-default-vlan\s+(\d+)') {
                return [int]$matches[1]
            }
        }
        return $null
    }


    function Get-InterfaceConfigsAndNames {
        param ($Block)
        $configs = @{}; $names = @{}; $current = ""; $buffer = @()
        foreach ($line in $Block) {
            if ($line -match '^interface ethernet (\d+/\d+/\d+)$') {
                if ($current) { $configs[$current] = ($buffer -join "`n") }
                $current = Normalize-PortName $matches[1]; $buffer = @()
            }
            elseif ($line -match 'port-name (.+)') {
                $names[$current] = $matches[1].Trim()
            }
            if ($current) { $buffer += $line }
        }
        if ($current) { $configs[$current] = ($buffer -join "`n") }
        return @($configs, $names)
    }

    $hostname = Get-Hostname
    $modelVer = Get-ModelAndVersion $blocks['show version']
    $uptime = Get-Uptime $blocks['show version']
    $location = Get-Location $blocks['show config']
    $vlanMap = Get-VlanMap $blocks['show config']
    $authBlockRaw = Get-AuthenticationBlock $blocks['show config']
    $authDefaultVlan = Get-AuthDefaultVlan $authBlockRaw
    $authModes = Get-AuthModes $blocks['show config']
    $dot1xPorts = $authModes[0]; $macauthPorts = $authModes[1]
    $auth = Get-AuthStatus $blocks['show dot1x sessions all'] $blocks['show mac-authentication sessions all']
    $cfgResults = Get-InterfaceConfigsAndNames $blocks['show config']
    $configs = $cfgResults[0]; $namesMap = $cfgResults[1]
    $interfaces = Get-InterfacesBrief $blocks['show interfaces brief']
    $macs = Get-MacTable $blocks['show mac-address']

    $combined = foreach ($iface in $interfaces) {
        $port = $iface.Port
        $interfaceMAC = $iface.MAC
        $macList = ($macs | Where-Object { $_.Port -eq $port } | ForEach-Object { $_.MAC }) -join ','
        $authRow = $auth | Where-Object { $_.Port -eq $port }
        $cfgText = if ($configs.ContainsKey($port)) { $configs[$port] } else { "" }
        $desc = if ($namesMap.ContainsKey($port)) { $namesMap[$port] } else { $iface.Name }
        $authMode = if ($authRow) { $authRow.Mode } elseif ($dot1xPorts -contains $port) { "dot1x" } elseif ($macauthPorts -contains $port) { "macauth" } else { "open" }
        $authState = if ($authRow) { $authRow.State } elseif ($authMode -eq "open") { "Open" } else { "Unknown" }
        # Determine the authentication template for the port.  Only ports that
        # explicitly have dot1x port-control auto configured are considered
        # "dot1x".  Ports merely covered by a global "dot1x enable" range are
        # treated as open unless they also appear in the mac-authentication range.
        $dot1xEnabled      = $dot1xPorts -contains $port
        $macauthEnabled    = $macauthPorts -contains $port
        $portHasDot1xAuto  = $cfgText -match '(?i)dot1x\s+port-control\s+auto'
        $authTemplate = switch ($true) {
            ($dot1xEnabled -and $macauthEnabled) { "flexible"; break }
            ($portHasDot1xAuto)               { "dot1x";    break }
            ($macauthEnabled)                 { "macauth"; break }
            default                           { "open" }
        }
        $vlan = ($macs | Where-Object { $_.Port -eq $port } | Select-Object -First 1).VLAN
        $type = if ($desc -match "uplink|trunk") { "Trunk" } elseif ($desc -match "access|user|staff|voice|endpoint|printer") { "Access" } else { "" }

        [PSCustomObject]@{
            Port = $port; Name = $desc; Status = $iface.Status; VLAN = $vlan; Duplex = $iface.Duplex;
            Speed = $iface.Speed; Type = $type; InterfaceMAC = $interfaceMAC; LearnedMACs = $macList;
            AuthState = $authState;
            AuthMode = $authMode; AuthClientMAC = if ($authRow) { $authRow.MAC } else { "" };
            Config = $cfgText; AuthTemplate = $authTemplate
        }
    }

    return [PSCustomObject]@{
        Hostname = $hostname; 
        Make = "Brocade";
        Model = $modelVer[0]; 
        Version = $modelVer[1];
        Uptime = $uptime; 
        Location = $location;
        AuthDefaultVLAN  = $authDefaultVlan;
        InterfaceCount = $combined.Count;
        InterfacesCombined = $combined
        AuthenticationBlock = ($authBlockRaw -join "`n")
    }
}

Export-ModuleMember -Function Get-BrocadeDeviceFacts
