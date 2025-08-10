# Brocade Device Parsing Module
function Get-BrocadeDeviceFacts {
    param (
        [string[]]$Lines
    )

    #
    # NOTE: The legacy Get-ShowCommandBlocks helper has been removed. A shared helper
    # Get-ShowCommandBlocks (defined in ParserWorker.psm1) now provides this functionality.
    # It extracts each 'show' command section into a dictionary keyed by the normalized command.

    #
    # Extract the output of a specific show command anywhere in the log.
    #
    # Parameters:
    #   -Lines: the entire contents of the log file as an array of strings.
    #   -CommandRegex: a regex pattern that matches the desired command line.
    #
    # This helper searches for the first occurrence of the command in the
    # provided lines.  Once found, it captures the following lines until the
    # next device prompt (identified by `<something>#`) or end of file.  The
    # captured lines are returned as an array.  If the command cannot be
    # located, an empty array is returned.  Matching is case-insensitive.
    function Get-CommandBlock {
        param(
            [string[]]$Lines,
            [string]$CommandRegex
        )
        $startIndex = -1
        # Locate the command line.  Escape any regex meta characters in the
        # hostname portion of the prompt to avoid spurious matches.  A device
        # prompt typically ends with a `#` character.  We include a wildcard
        # match prior to the command to allow for variations like `SSH@` or
        # additional whitespace.  Example pattern: `(?i)#\s*show version`.
        $pattern = "(?i)$CommandRegex"
        for ($i = 0; $i -lt $Lines.Count; $i++) {
            if ($Lines[$i] -match $pattern) {
                $startIndex = $i
                break
            }
        }
        if ($startIndex -lt 0) { return @() }
        $buffer = @()
        # Capture lines after the command until the next prompt or end of file
        for ($j = $startIndex + 1; $j -lt $Lines.Count; $j++) {
            $nl = $Lines[$j]
            if ($nl -match '^[^\s]*#') {
                break
            }
            $buffer += $nl
        }
        return $buffer
    }

    # Convert a raw port identifier into the canonical Brocade Ethernet port name.
    # The raw input may or may not include the 'Et' prefix.  If the prefix is
    # absent, prepend it.  If the prefix is already present, return the value
    # unchanged.  This ensures that port names are not inadvertently
    # double-prefixed (e.g. 'EtEt1/1/3').
    function ConvertTo-StandardPortName {
        param ($raw)
        if (-not $raw) { return $null }
        if ($raw -is [string]) {
            if ($raw -match '^(?i)Et\d+/\d+/\d+$') {
                return $raw
            } else {
                return "Et$raw"
            }
        }
        return $null
    }

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

    # Retrieve all show command blocks using the shared helper. This returns a hashtable
    # mapping command names to arrays of output lines.
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
                    RawPort = $matches[1]; Port = ConvertTo-StandardPortName $matches[1]; Status = $matches[2]
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
                    MAC = $matches[1]; Port = ConvertTo-StandardPortName $matches[2]; VLAN = $matches[3]
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
                $port = ConvertTo-StandardPortName $rawPort
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
                $current = ConvertTo-StandardPortName $matches[1]; $buffer = @()
            }
            elseif ($line -match 'port-name (.+)') {
                $names[$current] = $matches[1].Trim()
            }
            if ($current) { $buffer += $line }
        }
        if ($current) { $configs[$current] = ($buffer -join "`n") }
        return @($configs, $names)
    }

    # The spanning-tree parsing helper has been moved to ParserWorker.psm1.
    # Use the shared ConvertFrom-SpanningTree function provided by ParserWorker instead of a local copy.

    #
    # Extract command outputs individually using the flexible helper defined above.
    # Each extraction locates the first occurrence of the command and captures
    # lines until the next prompt.  If a command is not present, the
    # corresponding block will be an empty array which downstream functions
    # tolerate by returning default values.
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
        # Convert dot1x/macauth port lists to standard names (Et...).  This ensures
        # comparisons against interface Port names succeed.  Expand-PortRange
        # returns raw port numbers without the 'Et' prefix.
        $dot1xPorts = @($dot1xPorts | ForEach-Object {
            try { ConvertTo-StandardPortName $_ } catch { $_ }
        })
        $macauthPorts = @($macauthPorts | ForEach-Object {
            try { ConvertTo-StandardPortName $_ } catch { $_ }
        })
        
        # Build explicit lists of ports that are enabled for dot1x port-control auto
        # and mac-authentication enable.  These lists are derived from the global
        # Authentication block rather than the per-port configurations.  To
        # improve accuracy on releases like 08.0.95, we track whether any range
        # patterns are present for mac-authentication enable commands and defer
        # adding a blanket set of ports until after the interface list has been
        # built.  Dot1x detection uses only the 'port-control auto' form;
        # plain 'dot1x enable' lines simply enable 802.1X globally and do not
        # affect port-level templates.
        $dot1xAutoPorts     = @()
        $macControlPorts    = @()
        $macRangesFound     = $false
        $hasGlobalMacEnable = $false
        foreach ($line in $authBlockRaw) {
            $trim = $line.Trim()
            # Process dot1x port-control auto ranges.  Starting with 08.0.95,
            # multiple ranges may be provided without commas, separated by
            # additional 'ethe' keywords.  Search the entire line for every
            # "<port> to <port>" pattern and expand each range.
            if ($trim -match '(?i)^dot1x\s+port-control\s+auto') {
                try {
                    $matchesRange = [regex]::Matches($trim, '(\d+/\d+/\d+)\s+to\s+(\d+/\d+/\d+)')
                    foreach ($m in $matchesRange) {
                        $start = $m.Groups[1].Value
                        $end   = $m.Groups[2].Value
                        $rawRange = Expand-PortRange $start $end
                        foreach ($rp in $rawRange) {
                            try {
                                $std = ConvertTo-StandardPortName $rp
                                if ($std) { $dot1xAutoPorts += $std }
                            } catch { }
                        }
                    }
                } catch {
                    # If regex fails, skip parsing
                }
            }
            # Process mac-authentication enable lines.  If the line specifies
            # ranges, extract all ranges.  If a line contains no range
            # patterns and no additional tokens after 'enable', record that a
            # blanket enable was seen.  Blanket enables are applied only if no
            # ranged mac-authentication enable lines are present in the block.
            if ($trim -match '(?i)^mac-authentication\s+enable') {
                $lineMatches = @()
                try {
                    $lineMatches = [regex]::Matches($trim, '(\d+/\d+/\d+)\s+to\s+(\d+/\d+/\d+)')
                } catch { }
                if ($lineMatches.Count -gt 0) {
                    $macRangesFound = $true
                    foreach ($m in $lineMatches) {
                        $start = $m.Groups[1].Value
                        $end   = $m.Groups[2].Value
                        $rawRange = Expand-PortRange $start $end
                        foreach ($rp in $rawRange) {
                            try {
                                $std = ConvertTo-StandardPortName $rp
                                if ($std) { $macControlPorts += $std }
                            } catch { }
                        }
                    }
                } else {
                    # No range patterns on this line; if it has no additional
                    # arguments, note a potential blanket enable.
                    if ($trim -match '(?i)^mac-authentication\s+enable\s*$') {
                        $hasGlobalMacEnable = $true
                    }
                }
            }
        }
        # Remove duplicates from the dot1x auto list
        $dot1xAutoPorts = $dot1xAutoPorts | Sort-Object -Unique
        # Note: do not finalise $macControlPorts here.  If no ranges were
        # encountered but a blanket enable was seen, we will expand $macControlPorts
        # after $interfaces has been built below.
    # Determine which authentication session output is available.  Starting in
    # FastIron 08.0.90, the separate "show dot1x sessions all" and
    # "show mac-authentication sessions all" commands were deprecated in favour
    # of a unified "show authentication sessions" command.  If the unified
    # command is present we parse it using a specialised helper; otherwise we
    # fall back to the legacy separate commands.
    $auth = @()
    if ($authSessionsAll.Count -gt 0) {
        $auth = Get-AuthStatusUnified $authSessionsAll
    } else {
        $auth = Get-AuthStatus $dot1xSessions $macAuthSessions
    }
    $cfgResults = Get-InterfaceConfigsAndNames $configBlock
    $configs  = $cfgResults[0]; $namesMap = $cfgResults[1]
    $interfaces = Get-InterfacesBrief $interfacesBlock
        # Now that we have the list of interfaces, finalise MAC control ports.  If
        # no mac-authentication enable ranges were encountered but a blanket
        # enable command was present in the authentication block, treat all
        # interfaces as mac-enabled.  Otherwise use only the range-derived
        # $macControlPorts.  This logic avoids incorrectly applying a blanket
        # enable when the configuration includes specific ranges (as is common
        # in FastIron 08.0.95 and later).
        # If no mac-authentication enable ranges were found but a blanket
        # mac-authentication enable command was seen, do not add all
        # interfaces to the mac control list for template classification.
        # Blanket global MAC authentication should not force ports into the
        # macauth or flexible templates, as some FastIron versions (e.g.
        # 08.0.30) require per-port or ranged commands to enable MAC
        # authentication on individual ports.  We still honour explicit
        # ranged mac‑authentication enable commands above.
        if (-not $macRangesFound -and $hasGlobalMacEnable) {
            # Do not expand $macControlPorts here.  Leave it empty so that
            # per-port classification only considers explicit ranges or
            # per-port commands.  The $macauthPorts list (used for session
            # state) will still reflect global enablement via Get-AuthModes.
            $macControlPorts = @()
        }
        # Remove duplicates and sort the mac control list.  This must be done
        # after any blanket enable expansion to avoid duplicating ports.
        $macControlPorts = $macControlPorts | Sort-Object -Unique
    $macs       = Get-MacTable $macTableBlock

    $combined = foreach ($iface in $interfaces) {
        $port = $iface.Port
        $interfaceMAC = $iface.MAC
        $macList = ($macs | Where-Object { $_.Port -eq $port } | ForEach-Object { $_.MAC }) -join ','
        $authRow = $auth | Where-Object { $_.Port -eq $port }
        $cfgText = if ($configs.ContainsKey($port)) { $configs[$port] } else { "" }
        $desc = if ($namesMap.ContainsKey($port)) { $namesMap[$port] } else { $iface.Name }
        # Determine the authentication mode for session reporting.  This uses
        # the authentication sessions parsed above.  If no session is active,
        # assign a mode based on the ranged port lists returned from
        # Get‑AuthModes.  Note: this does not affect the template classification
        # below; it is used only for displaying the current state (dot1x,
        # macauth or open) when a session is present or inferred from the
        # configuration.
        $authMode = if ($authRow) {
            $authRow.Mode
        } elseif ($dot1xPorts -contains $port) {
            "dot1x"
        } elseif ($macauthPorts -contains $port) {
            "macauth"
        } else {
            "open"
        }
        $authState = if ($authRow) { $authRow.State } elseif ($authMode -eq "open") { "Open" } else { "Unknown" }
        # Determine the authentication template for the port by combining
        # per‑port configuration lines with global enablement ranges.  Only
        # 'dot1x port-control auto' directives (not plain 'dot1x enable') are
        # considered sufficient to classify a port as dot1x in the template
        # sense.  For MAC authentication, only ranged or per‑port
        # 'mac-authentication enable' directives are considered; a blanket
        # 'mac-authentication enable' line is only honoured when no ranges
        # appear in the auth block.  We do not use the $dot1xPorts or
        # $macauthPorts lists for template classification.
        $authTemplate = 'open'
        # Normalize and lower-case per-port config lines for matching
        $lcLines = @()
        if ($cfgText -and $cfgText.Length -gt 0) {
            try {
                $lcLines = ($cfgText -split "`r?`n") | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ }
            } catch {
                $lcLines = @()
            }
        }
        $hasDot1x = $false
        $hasMac   = $false
        # Check per-port config lines for dot1x port-control auto and
        # mac‑authentication enable statements.  We intentionally ignore
        # plain 'dot1x enable' here because it does not enforce port-level
        # authentication and should not classify the port as dot1x for
        # template purposes.
        foreach ($ln in $lcLines) {
            if (-not $hasDot1x) {
                if ($ln -like 'dot1x port-control auto*') {
                    $hasDot1x = $true
                }
            }
            if (-not $hasMac) {
                if ($ln -like 'mac-authentication enable*') {
                    $hasMac = $true
                }
            }
            if ($hasDot1x -and $hasMac) { break }
        }
        # If neither directive is found in the interface config, consult the
        # global enablement lists.  Ports present in the dot1x port-control
        # auto list are considered dot1x; ports present in the MAC control
        # list are considered macauth.  Note: we do not consult $dot1xPorts
        # or $macauthPorts here so that plain 'dot1x enable' ranges do not
        # classify a port as dot1x for template purposes.
        if (-not $hasDot1x) {
            if ($dot1xAutoPorts -contains $port) {
                $hasDot1x = $true
            }
        }
        if (-not $hasMac) {
            # A port is considered MAB-enabled if it appears in the explicit
            # mac-authentication enable ranges ($macControlPorts) or, in
            # releases prior to 08.0.90, when a blanket 'mac-authentication
            # enable' is present without any ranges in the auth block.  On
            # earlier firmware (e.g. 08.0.30) a global enable applies to
            # all ports.  For later releases (08.0.95 and beyond) we only
            # honour per-port or ranged MAC authentication commands.  We
            # detect the blanket case by checking the $macRangesFound and
            # $hasGlobalMacEnable flags.  When no ranges were found and
            # a global enable was seen, treat the port as MAB-enabled.
            if ($macControlPorts -contains $port) {
                $hasMac = $true
            } elseif (-not $macRangesFound -and $hasGlobalMacEnable) {
                $hasMac = $true
            }
        }
        # Assign the template alias based on detected authentication methods.
        if ($hasDot1x -and $hasMac) {
            $authTemplate = 'flexible'
        } elseif ($hasDot1x) {
            $authTemplate = 'dot1x'
        } elseif ($hasMac) {
            $authTemplate = 'macauth'
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
    # spanning-tree or span command using the flexible command extractor.
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
