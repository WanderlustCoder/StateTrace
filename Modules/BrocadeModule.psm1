# Brocade Device Parsing Module
function Get-BrocadeDeviceFacts {
    param (
        [string[]]$Lines,
        [hashtable]$Blocks
    )

    #

    #
    function Get-CommandBlock {
        param(
            [string[]]$Lines,
            [string]$CommandRegex
        )
        $startIndex = -1
        # Locate the command line.  Escape any regex meta characters in the
        $pattern = "(?i)$CommandRegex"
        for ($i = 0; $i -lt $Lines.Count; $i++) {
            if ($Lines[$i] -match $pattern) {
                $startIndex = $i
                break
            }
        }
        if ($startIndex -lt 0) { return @() }
        # Use a typed List[string] instead of a PowerShell array.  Using '+=' on an array
        $buffer = New-Object 'System.Collections.Generic.List[string]'
        # Capture lines after the command until the next prompt or end of file
        for ($j = $startIndex + 1; $j -lt $Lines.Count; $j++) {
            $nl = $Lines[$j]
            if ($nl -match '^[^\s]*#') {
                break
            }
            [void]$buffer.Add($nl)
        }
        return $buffer.ToArray()
    }

    function ConvertTo-StandardPortName { param ($raw) return "Et$raw" }

    function Expand-PortRange {
        param ($start, $end)
        $startParts = $start -split '/'
        $endParts = $end -split '/'
        $stack = $startParts[0]; $slot = $startParts[1]
        $startPort = [int]$startParts[2]; $endPort = [int]$endParts[2]
        # Use a typed list to avoid repeated array copying when expanding large port ranges.
        $ports = New-Object 'System.Collections.Generic.List[string]'
        for ($i = $startPort; $i -le $endPort; $i++) {
            [void]$ports.Add("Et$stack/$slot/$i")
        }
        # Return an array for compatibility with callers expecting enumerable strings
        return $ports.ToArray()
    }

    # Retrieve all show command blocks using the shared helper.  If a Blocks
    if ($Blocks -and $Blocks.Count -gt 0) {
        $blocks = $Blocks
    } else {
        $blocks = Get-ShowCommandBlocks -Lines $Lines
    }

    function Get-Hostname {
        foreach ($line in $Lines) {
            if ($line -match "^(\S+)[>#]") {
                $rawHost = $matches[1]
                # Strip any SSH@ prefix.  Logs captured via SSH often include
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
        # Delegate to the shared helper that handles vendor-specific keywords
        return Get-SnmpLocationFromLines -Lines $Block
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
        # Use typed lists for port collections to avoid O(n^2) growth when expanding port ranges
        $dot1x = New-Object 'System.Collections.Generic.List[string]'
        $macauth = New-Object 'System.Collections.Generic.List[string]'
        foreach ($line in $Block) {
            # Capture ranges for dot1x enable lines.  These specify stacks/slots/ports.
            if ($line -match 'dot1x enable ethe (\d+/\d+/\d+) to (\d+/\d+/\d+)') {
                [void]$dot1x.AddRange([string[]](Expand-PortRange $matches[1] $matches[2]))
            }
            # Capture ranges for MAC authentication enable lines.
            if ($line -match 'mac-authentication enable ethe (\d+/\d+/\d+) to (\d+/\d+/\d+)') {
                [void]$macauth.AddRange([string[]](Expand-PortRange $matches[1] $matches[2]))
            }
            # Beginning with FastIron 08.0.90, per‑port 802.1X enablement is achieved via
            if ($line -match 'dot1x port-control auto ethe (.+)$') {
                $rangesPart = $matches[1]
                # Split on commas using the .NET Split method rather than piping
                $rangesArr = $rangesPart.Split(',')  # returns an array of strings
                foreach ($r in $rangesArr) {
                    $range = $r.Trim()
                    $m = [regex]::Match($range, '(\d+/\d+/\d+) to (\d+/\d+/\d+)')
                    if ($m.Success) {
                        $start = $m.Groups[1].Value
                        $end   = $m.Groups[2].Value
                        [void]$dot1x.AddRange([string[]](Expand-PortRange $start $end))
                    }
                }
            }
        }
        return @($dot1x.ToArray(), $macauth.ToArray())
    }

    function Get-InterfacesBrief {
        param ($Block)
        # Use a typed list for interface summaries to avoid repeated array resizing.
        $results = New-Object 'System.Collections.Generic.List[psobject]'
        foreach ($line in $Block) {
            # Brocade "show interfaces brief" output can vary by release.  Some versions
            # Updated regex to allow "None" in the duplex column.  When a port is disabled or down,
            # the device outputs "None" for duplex and speed fields.  Without "None" in the
            # enumerated values, those lines would not match and therefore be skipped.
            if ($line -match '^(\d+/\d+/\d+)\s+(Up|Down|Disable(?:d)?|Admin-?Down|None)\s+(\S+)\s+(Full|Half|Auto(?:/Full)?|N/A|None)\s+(\S+)\s+(?:\S+\s+){3,6}([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4,6})\s+(.*?)\s*$') {
                $rawPort   = $matches[1]
                $linkToken = $matches[2]
                $stateTok  = $matches[3]
                $duplexTok = $matches[4]
                $speedTok  = $matches[5]
                # Keep "None" values as literal strings rather than converting to $null.  This preserves
                # the original device output (e.g., "None") for duplex and speed fields.
                $macTok    = $matches[6]
                $nameTok   = $matches[7].Trim()

                # Normalize the Status: treat anything other than 'Up' as 'Down'

                [void]$results.Add([PSCustomObject]@{
                    RawPort = $rawPort
                    Port    = ConvertTo-StandardPortName $rawPort
                    Status  = $linkToken
                    #Link    = $linkToken
                    State   = $stateTok
                    Duplex  = $duplexTok
                    Speed   = $speedTok
                    MAC     = $macTok
                    Name    = $nameTok
                })
            }
        }
        return $results
    }

    function Get-MacTable {
        param ($Block)
        # Use a typed list to accumulate MAC table entries.  This avoids array duplication
        $results = New-Object 'System.Collections.Generic.List[psobject]'
        foreach ($line in $Block) {
            if ($line -match '^([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})\s+(\d+/\d+/\d+)\s+\S+\s+(\d+)') {
                [void]$results.Add([PSCustomObject]@{
                    MAC  = $matches[1]
                    Port = ConvertTo-StandardPortName $matches[2]
                    VLAN = $matches[3]
                })
            }
        }
        return $results
    }

    function Get-AuthStatus {
        param ($Dot1xBlock, $MacAuthBlock)
        $dot1x = @{}; $macauth = @{}

        foreach ($line in $Dot1xBlock) {
            if ($line -match '^(\d+/\d+/\d+)\s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4}).*(AUTHENTICATED|AUTHENTICATING)$') {
                $port = ConvertTo-StandardPortName $matches[1]
                $mac = $matches[2]
                $state = if ($matches[3] -eq 'AUTHENTICATED') { 'Authorized' } else { 'Authenticating' }
                $dot1x[$port] = [PSCustomObject]@{ Port = $port; MAC = $mac; State = $state; Mode = 'dot1x' }
            }
        }

        foreach ($line in $MacAuthBlock) {
            if ($line -match '^(\d+/\d+/\d+)\s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})\s+\S+\s+\d+\s+(Yes|No)') {
                $port = ConvertTo-StandardPortName $matches[1]
                $mac = $matches[2]
                $auth = $matches[3]
                $state = if ($auth -eq 'Yes') { 'Authorized' } else { 'Unauthorized' }
                $macauth[$port] = [PSCustomObject]@{ Port = $port; MAC = $mac; State = $state; Mode = 'macauth' }
            }
        }

        # Build a unique sorted list of ports without piping through Sort-Object -Unique.  HashSet
        $portSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($p in $dot1x.Keys) { [void]$portSet.Add($p) }
        foreach ($p in $macauth.Keys) { [void]$portSet.Add($p) }
        $ports = [System.Collections.Generic.List[string]]::new($portSet)
        $ports.Sort([System.StringComparer]::OrdinalIgnoreCase)
        $result = foreach ($p in $ports) {
            if ($dot1x.ContainsKey($p)) { $dot1x[$p] }
            elseif ($macauth.ContainsKey($p)) { $macauth[$p] }
        }
        return $result
    }

    # "show authentication sessions all" command displays both 802.1X and MAC
    function Get-AuthStatusUnified {
        param([string[]]$Block)
        # Use a typed list to avoid repeated array copying when aggregating auth status entries.
        $results = New-Object 'System.Collections.Generic.List[psobject]'
        foreach ($line in $Block) {
            $trimmed = $line.Trim()
            # Skip headers or separators
            if ($trimmed -match '^-+$' -or $trimmed -match '^Port\s+MAC') { continue }
            if ($trimmed -match '^(\d+/\d+/\d+)\s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})\s+\S+\s+\S+\s+\d+\s+(MAUTH|8021\.X)\s+\S+\s+(Yes|No)\s+\d+\s+\S+\s+(AUTHENTICATED|AUTHENTICATING|UNAUTHENTICATED|N/A)') {
                $rawPort = $matches[1]
                $port = ConvertTo-StandardPortName $rawPort
                $mac  = $matches[2]
                $method = $matches[3]
                $auth = $matches[4]
                $pae  = $matches[5]
                $mode = if ($method -eq 'MAUTH') { 'macauth' } else { 'dot1x' }
                $state = if ($pae -match 'AUTHENTICATED') { 'Authorized' } elseif ($auth -eq 'Yes') { 'Authorized' } else { 'Unauthorized' }
                [void]$results.Add([PSCustomObject]@{
                    Port  = $port
                    MAC   = $mac
                    State = $state
                    Mode  = $mode
                })
            }
        }
        return $results
    }

    function Get-AuthenticationBlock {
        param ([string[]]$ConfigBlock)
        # Use a typed list for the auth config buffer to avoid array copying.
        $buffer = New-Object 'System.Collections.Generic.List[string]'
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
                [void]$buffer.Add($line.Trim())
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
        # Build per-interface configuration text using a typed list rather than
        $configs = @{}; $names = @{}; $current = ""
        $bufferList = New-Object 'System.Collections.Generic.List[string]'
        foreach ($line in $Block) {
            if ($line -match '^interface ethernet (\d+/\d+/\d+)$') {
                if ($current) {
                    $configs[$current] = [string]::Join("`n", $bufferList)
                }
                $current = ConvertTo-StandardPortName $matches[1]
                $bufferList.Clear()
                continue
            } elseif ($line -match 'port-name (.+)') {
                $names[$current] = $matches[1].Trim()
            }
            if ($current) {
                [void]$bufferList.Add($line)
            }
        }
        if ($current) {
            $configs[$current] = [string]::Join("`n", $bufferList)
        }
        return @($configs, $names)
    }

    # The spanning-tree parsing helper has been moved to ParserWorker.psm1.

    #
    $versionBlock    = Get-CommandBlock -Lines $Lines -CommandRegex '#\s*show\s+version'
    $configBlock     = Get-CommandBlock -Lines $Lines -CommandRegex '#\s*show\s+config'
    $interfacesBlock = Get-CommandBlock -Lines $Lines -CommandRegex '#\s*show\s+interfaces\s+brief'
    $macTableBlock   = Get-CommandBlock -Lines $Lines -CommandRegex '#\s*show\s+mac\s*-?address'
    $dot1xSessions   = Get-CommandBlock -Lines $Lines -CommandRegex '#\s*show\s+dot1x\s+sessions\s+all'
    $macAuthSessions = Get-CommandBlock -Lines $Lines -CommandRegex '#\s*show\s+mac\s*-?authentication\s+sessions\s+all'
    $authSessionsAll = Get-CommandBlock -Lines $Lines -CommandRegex '#\s*show\s+authentication\s+sessions'

    $hostname   = Get-Hostname
    $modelVer   = Get-ModelAndVersion $versionBlock
    $uptime     = Get-Uptime $versionBlock
    $location   = Get-Location $configBlock
    $vlanMap    = Get-VlanMap $configBlock
    $authBlockRaw   = Get-AuthenticationBlock $configBlock
    $authDefaultVlan = Get-AuthDefaultVlan $authBlockRaw
    $authModes  = Get-AuthModes $configBlock
    $dot1xPorts = $authModes[0]; $macauthPorts = $authModes[1]
    # Determine which authentication session output is available.  Starting in
    $auth = @()
    if ($authSessionsAll.Count -gt 0) {
        $auth = Get-AuthStatusUnified $authSessionsAll
    } else {
        $auth = Get-AuthStatus $dot1xSessions $macAuthSessions
    }
    $cfgResults = Get-InterfaceConfigsAndNames $configBlock
    $configs  = $cfgResults[0]; $namesMap = $cfgResults[1]
    $interfaces = Get-InterfacesBrief $interfacesBlock
    $macs       = Get-MacTable $macTableBlock

    # Pre-index the MAC table and authentication rows by port to avoid pipeline
    $macsByPort = @{}
    foreach ($m in $macs) {
        $p = $m.Port
        if (-not $macsByPort.ContainsKey($p)) {
            $macsByPort[$p] = New-Object 'System.Collections.Generic.List[string]'
        }
        [void]$macsByPort[$p].Add([string]$m.MAC)
    }
    $authByPort = @{}
    foreach ($a in $auth) {
        # In case multiple auth rows are present for a port, prefer the first
        if (-not $authByPort.ContainsKey($a.Port)) {
            $authByPort[$a.Port] = $a
        }
    }

    $combined = foreach ($iface in $interfaces) {
        $port = $iface.Port
        $interfaceMAC = $iface.MAC
        # Use the precomputed lookup to retrieve the list of MAC addresses for this port.
        $macList = if ($macsByPort.ContainsKey($port)) {
            [string]::Join(',', $macsByPort[$port])
        } else {
            ''
        }
        # Retrieve the auth row for this port, if present, via the pre-indexed dictionary.
        $authRow = if ($authByPort.ContainsKey($port)) { $authByPort[$port] } else { $null }
        # Lookup the configuration text for this port or default to an empty string.
        $cfgText = if ($configs.ContainsKey($port)) { $configs[$port] } else { '' }
        # Prefer the alias/name from the brief output when present; fall back to the
        $desc = if ($iface.Name -and $iface.Name -ne '') {
            $iface.Name
        } elseif ($namesMap.ContainsKey($port)) {
            $namesMap[$port]
        } else {
            $port
        }
        $authMode = if ($authRow) { $authRow.Mode } elseif ($dot1xPorts -contains $port) { "dot1x" } elseif ($macauthPorts -contains $port) { "macauth" } else { "open" }
        $authState = if ($authRow) { $authRow.State } elseif ($authMode -eq "open") { "Open" } else { "Unknown" }
        # Determine the authentication template for the port.  Beginning with
        $dot1xEnabled   = $dot1xPorts -contains $port
        $macauthEnabled = $macauthPorts -contains $port
        $authTemplate = switch ($true) {
            ($dot1xEnabled -and $macauthEnabled) { "flexible"; break }
            ($dot1xEnabled)                      { "dot1x";    break }
            ($macauthEnabled)                    { "macauth";  break }
            default                              { "open" }
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

    # Attempt to parse spanning-tree information if present.  Locate the
    $spanBlock = Get-CommandBlock -Lines $Lines -CommandRegex '#\s*show\s+spanning-tree'
    if ($spanBlock.Count -eq 0) {
        $spanBlock = Get-CommandBlock -Lines $Lines -CommandRegex '#\s*show\s+span'
    }
    # Parse spanning tree information using the shared ConvertFrom‑SpanningTree helper
    $spanInfo = if ($spanBlock.Count -gt 0) { ConvertFrom-SpanningTree -SpanLines $spanBlock } else { @() }

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