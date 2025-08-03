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
            if ($line -match "^(\S+)[>#]") {
                $rawHost = $matches[1]
                # Strip any SSH@ prefix.  Logs captured via SSH often include
                # the username followed by '@' (e.g. SSH@hostname).  Only the
                # hostname should be used for identification.
                if ($rawHost -like 'SSH@*') {
                    return $rawHost.Substring(4)
                }
                return $rawHost
            }
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
            # Capture ranges for dot1x enable lines.  These specify stacks/slots/ports.
            if ($line -match 'dot1x enable ethe (\d+/\d+/\d+) to (\d+/\d+/\d+)') {
                $dot1x += Expand-PortRange $matches[1] $matches[2]
            }
            # Capture ranges for MAC authentication enable lines.
            if ($line -match 'mac-authentication enable ethe (\d+/\d+/\d+) to (\d+/\d+/\d+)') {
                $macauth += Expand-PortRange $matches[1] $matches[2]
            }
            # Beginning with FastIron 08.0.90, per‑port 802.1X enablement is achieved via
            # `dot1x port-control auto ethe <start> to <end>[, <start> to <end>]`.  Multiple
            # comma‑separated ranges may be present on a single line.  Treat these ranges
            # as dot1x enabled so the port will be considered dot1x for AuthMode purposes.
            if ($line -match 'dot1x port-control auto ethe (.+)$') {
                $rangesPart = $matches[1]
                # Split on commas to handle multiple ranges.  Trim each segment and
                # extract the start/end if the "to" keyword is present.
                $ranges = $rangesPart -split ',' | ForEach-Object { $_.Trim() }
                foreach ($range in $ranges) {
                    $m = [regex]::Match($range, '(\d+/\d+/\d+) to (\d+/\d+/\d+)')
                    if ($m.Success) {
                        $start = $m.Groups[1].Value
                        $end   = $m.Groups[2].Value
                        $dot1x += Expand-PortRange $start $end
                    }
                }
            }
        }
        return @($dot1x, $macauth)
    }

    function Get-InterfacesBrief {
        param ($Block)
        $results = @()
        foreach ($line in $Block) {
            # Brocade "show interfaces brief" output can vary by release.  Some versions
            # include separate columns for Trunk, Tag, PVID, PRI and Age, while others
            # include only Tag, PVID and PRI.  To be resilient, capture the
            # essential fields (port, link, state, duplex, speed, MAC and name) and
            # tolerate 3–6 intermediate columns between the speed and MAC.  Allow
            # the "State" column to be any non‑whitespace token (e.g. Forward, None).
            if ($line -match '^(\d+/\d+/\d+)\s+(Up|Down)\s+(\S+)\s+(Full|Half)\s+(\S+)\s+(?:\S+\s+){3,6}([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4,6})\s+(.*?)\s*$') {
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

    # Parse unified authentication session output.  In 08.0.90 and later the
    # "show authentication sessions all" command displays both 802.1X and MAC
    # authentication sessions in a single table.  Each entry includes the
    # port, MAC address, IP addresses, username, VLAN, method (MAUTH or
    # 8021.X), authorization state, ACL applied, session age and PAE state.
    # We capture the port, MAC, mode and derive an authorization state.  The
    # regex below tolerates optional IPv4/IPv6 fields and interprets the
    # method column to distinguish dot1x versus macauth.  PAE states such as
    # AUTHENTICATED/UNAUTHENTICATED are mapped to Authorized/Unauthorized.
    function Get-AuthStatusUnified {
        param([string[]]$Block)
        $results = @()
        foreach ($line in $Block) {
            $trimmed = $line.Trim()
            # Skip headers or separators
            if ($trimmed -match '^-+$' -or $trimmed -match '^Port\s+MAC') { continue }
            if ($trimmed -match '^(\d+/\d+/\d+)\s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})\s+\S+\s+\S+\s+\d+\s+(MAUTH|8021\.X)\s+\S+\s+(Yes|No)\s+\d+\s+\S+\s+(AUTHENTICATED|AUTHENTICATING|UNAUTHENTICATED|N/A)') {
                $rawPort = $matches[1]
                $port = Normalize-PortName $rawPort
                $mac  = $matches[2]
                $method = $matches[3]
                $auth = $matches[4]
                $pae  = $matches[5]
                $mode = if ($method -eq 'MAUTH') { 'macauth' } else { 'dot1x' }
                $state = if ($pae -match 'AUTHENTICATED') { 'Authorized' } elseif ($auth -eq 'Yes') { 'Authorized' } else { 'Unauthorized' }
                $results += [PSCustomObject]@{ Port = $port; MAC = $mac; State = $state; Mode = $mode }
            }
        }
        return $results
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

    # Parse spanning tree output for Brocade switches.  Brocade MST output
    # resembles Cisco, with sections such as "MST0".  We reuse the same
    # parsing logic as Cisco for simplicity.  Extract the root switch
    # identifier (Address) and root port.  Additional fields can be added
    # later.
    function Parse-SpanningTree {
        param([string[]]$SpanLines)
        $entries = @()
        $current = ''
        $rootSwitch = ''
        $rootPort = ''
        foreach ($ln in $SpanLines) {
            $line = $ln.Trim()
            if ($line -match '^(MST\d+|VLAN\d+)') {
                if ($current -ne '') {
                    $entries += [PSCustomObject]@{
                        VLAN       = $current
                        RootSwitch = $rootSwitch
                        RootPort   = $rootPort
                        Role       = ''
                        Upstream   = ''
                    }
                }
                $current = $matches[1]
                $rootSwitch = ''
                $rootPort = ''
                continue
            }
            if (-not $rootSwitch -and $line -match 'Address\s+(\S+)') {
                $rootSwitch = $matches[1]
                continue
            }
            if (-not $rootPort -and $line -match 'Root port\s+(\S+),') {
                $rootPort = $matches[1]
                continue
            }
        }
        if ($current -ne '') {
            $entries += [PSCustomObject]@{
                VLAN       = $current
                RootSwitch = $rootSwitch
                RootPort   = $rootPort
                Role       = ''
                Upstream   = ''
            }
        }
        return $entries
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
    # Determine which authentication session output is available.  Starting in
    # FastIron 08.0.90, the separate "show dot1x sessions all" and
    # "show mac-authentication sessions all" commands were deprecated in favour
    # of a unified "show authentication sessions" command.  If the unified
    # command is present we parse it using a specialised helper; otherwise we
    # fall back to the legacy separate commands.  This ensures the parser
    # continues to work across different software releases.
    $auth = @()
    if ($blocks.ContainsKey('show authentication sessions all')) {
        $auth = Get-AuthStatusUnified $blocks['show authentication sessions all']
    } else {
        $auth = Get-AuthStatus $blocks['show dot1x sessions all'] $blocks['show mac-authentication sessions all']
    }
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

    # Attempt to parse spanning-tree information if present.  Use either
    # 'show spanning-tree' or 'show span'.  Empty list if not found.
    $spanLines = @()
    if ($blocks.ContainsKey('show spanning-tree')) {
        $spanLines = $blocks['show spanning-tree']
    } elseif ($blocks.ContainsKey('show span')) {
        $spanLines = $blocks['show span']
    }
    $spanInfo = if ($spanLines.Count -gt 0) { Parse-SpanningTree -SpanLines $spanLines } else { @() }

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
        SpanInfo = $spanInfo
    }
}

Export-ModuleMember -Function Get-BrocadeDeviceFacts
