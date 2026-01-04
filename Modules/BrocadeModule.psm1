# Brocade Device Parsing Module

Set-StrictMode -Version Latest

# Precompile frequently reused regexes to avoid repeated allocations.
if (-not (Get-Variable -Name BrocadeAuthPortRangeRegex -Scope Script -ErrorAction SilentlyContinue)) {
    $script:BrocadeAuthPortRangeRegex = [regex]::new('(?i)eth(?:e)?\s+(\d+/\d+/\d+)(?:\s+to\s+(\d+/\d+/\d+))?')
}
if (-not (Get-Variable -Name BrocadeTypeTrunkRegex -Scope Script -ErrorAction SilentlyContinue)) {
    $script:BrocadeTypeTrunkRegex = [regex]::new('uplink|trunk', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}
if (-not (Get-Variable -Name BrocadeTypeAccessRegex -Scope Script -ErrorAction SilentlyContinue)) {
    $script:BrocadeTypeAccessRegex = [regex]::new('access|user|staff|voice|endpoint|printer', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

# (Debug code removed)
function Get-BrocadeDeviceFacts {
    [CmdletBinding()]
    param (
        [string[]]$Lines,
        [hashtable]$Blocks
    )

    #

    #
    function ConvertTo-StandardPortName { param ($raw) return "Et$raw" }

    # Normalize a port key by stripping any leading 'Et', 'Eth' or 'Ethernet' prefixes.
    # Some Brocade outputs may omit the 'Et' prefix (e.g. '1/1/1') while others include
    # longer forms such as 'Ethernet1/1/1'.  Use this helper to produce a canonical
    # representation for dictionary lookups.  The returned string preserves the
    # underlying numeric stack/slot/port but removes vendor-specific prefixes.
    # Convert a port key to a canonical form by stripping any vendor-specific
    # prefixes (e.g. 'Ethernet1/1/1' ? '1/1/1').  Using the approved verb
    # 'ConvertTo' conveys that this helper transforms the input to a new
    # representation.  The previous name 'Normalize-PortKey' used the
    # unapproved verb 'Normalize'.  Callers have been updated accordingly.
    function ConvertTo-PortKey {
        param([string]$p)
        if (-not $p) { return $p }
        # Remove any leading 'Et', 'Eth' or 'Ethernet' (case-insensitive).  The
        # replacement operates only on the prefix to avoid altering the numeric
        # portions of the port identifier.  Trim any resulting whitespace.
        $normalized = $p -replace '^(?i)eth(?:ernet)?', ''
        return $normalized.Trim()
    }

    function Expand-PortRange {
        param ($start, $end)
        $startParts = $start -split '/'
        $endParts = $end -split '/'
        if ($startParts.Count -lt 3 -or $endParts.Count -lt 3) {
            return @()
        }
        $stack = $startParts[0]; $slot = $startParts[1]
        $startPort = [int]$startParts[2]; $endPort = [int]$endParts[2]
        # Use a typed list to avoid repeated array copying when expanding large port ranges.
        $ports = [System.Collections.Generic.List[string]]::new()
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
        $blocks = DeviceLogParserModule\Get-ShowCommandBlocks -Lines $Lines
    }

    function Get-Hostname {
        $hostname = DeviceParsingCommon\Get-HostnameFromPrompt -Lines $Lines -RunningConfigPattern '^(?i)\s*hostname\s+(.+)$'
        if ($hostname) { return $hostname }
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
        $uptime = DeviceParsingCommon\Get-UptimeFromLines -Lines $Block -Patterns @('(?i)uptime is (.+)$', '(?i)uptime:\s*(.+)$')
        if ($uptime) { return $uptime }
        return "Unknown"
    }

    function Get-Location {
        param ($Block)
        # Delegate to the shared helper that handles vendor-specific keywords
        return DeviceLogParserModule\Get-SnmpLocationFromLines -Lines $Block
    }

    function Get-AuthModes {
        param ($Block, $Configs)
        # Build typed lists for port collections to avoid O(n^2) growth when expanding port ranges
        # Separate dot1x "port-control auto" and global "dot1x enable" directives.  Only the
        # port-control auto list is used for authentication template classification; the
        # enable list is informational and may be surfaced in the UI if needed.
        $dot1xAuto   = [System.Collections.Generic.List[string]]::new()
        $dot1xEnable = [System.Collections.Generic.List[string]]::new()
        $macauth     = [System.Collections.Generic.List[string]]::new()

        foreach ($line in $Block) {
            # Normalize case and trim for easier matching
            $l = $line.Trim()

            # MAC authentication enable lines may specify multiple ranges or single ports.
            if ($l -match '(?i)^\s*mac-authentication\s+enable') {
                $mAll = $script:BrocadeAuthPortRangeRegex.Matches($l)
                foreach ($m in $mAll) {
                    $start = $m.Groups[1].Value
                    $end   = $m.Groups[2].Value
                    if ($end -and $end -ne '') {
                        [void]$macauth.AddRange([string[]](Expand-PortRange $start $end))
                    } else {
                        [void]$macauth.AddRange([string[]](Expand-PortRange $start $start))
                    }
                }
            }

            # Only "dot1x port-control auto" lines contribute to the per-port dot1x set used
            # for classification.  "dot1x enable" lines are treated as global enablement and
            # stored separately in $dot1xEnable for optional informational use.
            if ($l -match '(?i)^\s*dot1x\s+port-control\s+auto') {
                $mAll = $script:BrocadeAuthPortRangeRegex.Matches($l)
                foreach ($m in $mAll) {
                    $start = $m.Groups[1].Value
                    $end   = $m.Groups[2].Value
                    if ($end -and $end -ne '') {
                        [void]$dot1xAuto.AddRange([string[]](Expand-PortRange $start $end))
                    } else {
                        [void]$dot1xAuto.AddRange([string[]](Expand-PortRange $start $start))
                    }
                }
            } elseif ($l -match '(?i)^\s*dot1x\s+enable') {
                $mAll = $script:BrocadeAuthPortRangeRegex.Matches($l)
                foreach ($m in $mAll) {
                    $start = $m.Groups[1].Value
                    $end   = $m.Groups[2].Value
                    if ($end -and $end -ne '') {
                        [void]$dot1xEnable.AddRange([string[]](Expand-PortRange $start $end))
                    } else {
                        [void]$dot1xEnable.AddRange([string[]](Expand-PortRange $start $start))
                    }
                }
            }
        }

        # Also parse per-interface configurations: each entry in $Configs is the config text for
        # a single interface.  If the config contains "mac-authentication enable", add that
        # interface to the macauth set.  If it contains "dot1x port-control auto", add it to
        # the dot1x set.  Note that configs may include newline-separated commands.
        if ($Configs) {
            foreach ($kvp in $Configs.GetEnumerator()) {
                $portName = $kvp.Key
                $cfgText  = $kvp.Value
                if ($cfgText -and $cfgText -match '(?i)mac-authentication\s+enable') {
                    # Add the specific port (EtX/Y/Z) directly
                    [void]$macauth.Add($portName)
                }
                if ($cfgText -and $cfgText -match '(?i)dot1x\s+port-control\s+auto') {
                    [void]$dot1xAuto.Add($portName)
                }
            }
        }

        # Dedupe while preserving order.  Use hashtables as sets.
        $dotSeen = @{}
        $dotUniq = [System.Collections.Generic.List[string]]::new()
        foreach ($p in $dot1xAuto) {
            if (-not $dotSeen.ContainsKey($p)) {
                $dotSeen[$p] = $true
                [void]$dotUniq.Add($p)
            }
        }
        $macSeen = @{}
        $macUniq = [System.Collections.Generic.List[string]]::new()
        foreach ($p in $macauth) {
            if (-not $macSeen.ContainsKey($p)) {
                $macSeen[$p] = $true
                [void]$macUniq.Add($p)
            }
        }
        return @($dotUniq.ToArray(), $macUniq.ToArray())
    }

    function Get-InterfacesBrief {
        param ($Block)
        $propertyMap = [ordered]@{
            RawPort = 1
            Status  = 2
            State   = 3
            Duplex  = 4
            Speed   = 5
            MAC     = 6
            Name    = { param($match) $match.Groups[7].Value.Trim() }
        }
        $postProcess = {
            param($obj, $match)
            $raw = $obj.RawPort
            $obj | Add-Member -NotePropertyName Port -NotePropertyValue (ConvertTo-StandardPortName $raw) -Force
            return $obj
        }
        return DeviceParsingCommon\Invoke-RegexTableParser -Lines $Block -HeaderPattern '^' -RowPattern '^(\d+/\d+/\d+)\s+(Up|Down|Disable(?:d)?|Admin-?Down|None)\s+(\S+)\s+(Full|Half|Auto(?:/Full)?|N/A|None)\s+(\S+)\s+(?:\S+\s+){3,6}([0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4,6})\s+(.*?)\s*$' -PropertyMap $propertyMap -TerminatorPattern '' -PostProcess $postProcess
    }

    function Get-MacTable {
        param ($Block)
        $portTransform = {
            param($p)
            $standard = ConvertTo-StandardPortName $p
            return DeviceParsingCommon\ConvertTo-ShortPortName -Port $standard
        }
        return DeviceParsingCommon\ConvertFrom-MacTableRegex -Lines $Block -HeaderPattern '^\s*MAC\s+Address' -RowPattern '^(?<mac>(?:[0-9A-Fa-f]{4}\.){2}[0-9A-Fa-f]{4,6})\s+(?<port>\d+/\d+/\d+)\s+.*?\s+(?<vlan>\d+)(?:\s+\S+)?\s*$' -VlanGroup 3 -MacGroup 1 -PortGroup 2 -PortTransform $portTransform
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
        $results = [System.Collections.Generic.List[psobject]]::new()
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
        $buffer = [System.Collections.Generic.List[string]]::new()
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
        $bufferList = [System.Collections.Generic.List[string]]::new()
        foreach ($line in $Block) {
            # End of an interface configuration is typically indicated by a standalone
            # exclamation mark.  When we encounter such a line and are currently
            # collecting a block, flush the accumulated lines and reset the state.
            if ($line -match '(?i)^\s*!') {
                if ($current) {
                    $configs[$current] = [string]::Join("`n", $bufferList)
                    $current = ""
                    $bufferList.Clear()
                }
                # Always skip processing the '!' line itself.
                continue
            }
            # Detect the start of an interface block.  Allow leading whitespace and trailing whitespace,
            # and be case-insensitive on the keyword.  Use a word boundary after the port to avoid
            # matching additional text on the same line.  If we were collecting a previous block,
            # flush it before starting a new one.
            if ($line -match '(?i)^\s*interface\s+ethernet\s+(\d+/\d+/\d+)\b') {
                if ($current) {
                    $configs[$current] = [string]::Join("`n", $bufferList)
                    $bufferList.Clear()
                }
                $current = ConvertTo-StandardPortName $matches[1]
                continue
            }
            # Capture the friendly port name, if present, for the current interface.  Trim trailing whitespace.
            if ($line -match '(?i)^\s*port-name\s+(.+)') {
                $names[$current] = $matches[1].Trim()
            }
            # Accumulate all lines within the current interface block for later parsing.
            if ($current) {
                [void]$bufferList.Add($line)
            }
        }
        # Flush any remaining buffered block at the end of the config.
        if ($current) {
            $configs[$current] = [string]::Join("`n", $bufferList)
        }
        return @($configs, $names)
    }

    # Spanning-tree parsing is delegated to DeviceLogParserModule\ConvertFrom-SpanningTree.

    #
    $versionBlock    = DeviceLogParserModule\Get-ShowBlock -Blocks $blocks -Lines $Lines -PreferredKeys @('show version') -CommandRegexes @('#\s*show\s+version') -DefaultValue @()
    $configBlock     = DeviceLogParserModule\Get-ShowBlock -Blocks $blocks -Lines $Lines -PreferredKeys @('show config') -CommandRegexes @('#\s*show\s+config') -DefaultValue @()
    $interfacesBlock = DeviceLogParserModule\Get-ShowBlock -Blocks $blocks -Lines $Lines -PreferredKeys @('show interfaces brief','show interface brief') -RegexPatterns @('^show\s+interfaces?\s+brief') -CommandRegexes @('#\s*show\s+interfaces?\s+brief') -DefaultValue @()
    $macTableBlock   = DeviceLogParserModule\Get-ShowBlock -Blocks $blocks -Lines $Lines -PreferredKeys @('show mac address-table','show mac-address-table','show mac address','show mac-address') -RegexPatterns @('^show\s+mac[- ]address') -CommandRegexes @('#\s*show\s+mac\s*-?address') -DefaultValue @()
    $dot1xSessions   = DeviceLogParserModule\Get-ShowBlock -Blocks $blocks -Lines $Lines -PreferredKeys @('show dot1x sessions all') -CommandRegexes @('#\s*show\s+dot1x\s+sessions\s+all') -DefaultValue @()
    $macAuthSessions = DeviceLogParserModule\Get-ShowBlock -Blocks $blocks -Lines $Lines -PreferredKeys @('show mac authentication sessions all','show mac-authentication sessions all') -RegexPatterns @('^show\s+mac[- ]authentication\s+sessions') -CommandRegexes @('#\s*show\s+mac\s*-?authentication\s+sessions\s+all') -DefaultValue @()
    # Retrieve the unified authentication session command if present.  This newer
    # command reports both 802.1X and MAC authentication state in one table.  When
    # available it supersedes the separate dot1x/mac-auth session commands.
    $authSessionsAll = DeviceLogParserModule\Get-ShowBlock -Blocks $blocks -Lines $Lines -PreferredKeys @('show authentication sessions') -CommandRegexes @('#\s*show\s+authentication\s+sessions') -DefaultValue @()

    # On older Brocade FCX software (e.g. 7.3.x) the session commands differ from
    # modern releases.  In lieu of "show dot1x sessions all" the command
    # "show dot1x mac-sessions" is used.  MAC authentication sessions are
    # retrieved via two commands which separately list authorized and unauthorized
    # MAC addresses.  Capture these alternate command blocks here so they may be
    # used as fallbacks later when the standard commands return no output.
    $dot1xMacSessions    = DeviceLogParserModule\Get-ShowBlock -Blocks $blocks -Lines $Lines -PreferredKeys @('show dot1x mac-sessions') -CommandRegexes @('#\s*show\s+dot1x\s+mac-?sessions') -DefaultValue @()
    $authMacAuthorized   = DeviceLogParserModule\Get-ShowBlock -Blocks $blocks -Lines $Lines -PreferredKeys @('show auth-mac-addresses authorized-mac','show auth mac addresses authorized-mac') -RegexPatterns @('^show\s+auth-?mac-?addresses\s+authorized-mac') -CommandRegexes @('#\s*show\s+auth-?mac-?addresses\s+authorized-mac') -DefaultValue @()
    $authMacUnauthorized = DeviceLogParserModule\Get-ShowBlock -Blocks $blocks -Lines $Lines -PreferredKeys @('show auth-mac-addresses unauthorized-mac','show auth mac addresses unauthorized-mac') -RegexPatterns @('^show\s+auth-?mac-?addresses\s+unauthorized-mac') -CommandRegexes @('#\s*show\s+auth-?mac-?addresses\s+unauthorized-mac') -DefaultValue @()

    $hostname   = Get-Hostname
    $modelVer   = Get-ModelAndVersion $versionBlock
    $uptime     = Get-Uptime $versionBlock
    $location   = Get-Location $configBlock
    $authBlockRaw   = Get-AuthenticationBlock $configBlock
    $authDefaultVlan = Get-AuthDefaultVlan $authBlockRaw
    # Retrieve interface configs and names before determining auth modes.  The per-interface
    # config text is required to detect dot1x/mac-auth enable lines on older software.
    $cfgResults = Get-InterfaceConfigsAndNames $configBlock
    $configs    = $cfgResults[0]; $namesMap = $cfgResults[1]
    # Compute authentication modes using both the run-config block and per-interface configs.
    $authModes  = Get-AuthModes $configBlock $configs
    $dot1xPorts = $authModes[0]; $macauthPorts = $authModes[1]

    # Precompute membership sets for authentication port lists to avoid repeated `-contains` scans.
    # Normalize each port key so that ports listed with different prefixes collide into the same set.
    $dot1xSet = @{}
    foreach ($p in $dot1xPorts) {
        $norm = ConvertTo-PortKey $p
        # Directly assign the key to `$true`; duplicates simply overwrite the value
        $dot1xSet[$norm] = $true
    }
    $macauthSet = @{}
    foreach ($p in $macauthPorts) {
        $norm = ConvertTo-PortKey $p
        $macauthSet[$norm] = $true
    }
    # Determine which authentication session output is available.  Starting in
    # newer software releases the unified "show authentication sessions" command
    # should be preferred.  When that is not present, fall back to the separate
    # dot1x/mac-auth session commands.  On legacy software (e.g. 7.3.x) the
    # commands differ; a dot1x MAC session table is produced by
    # "show dot1x mac-sessions" and MAC authentication state is split between
    # "show auth-mac-addresses authorized-mac" and "show auth-mac-addresses
    # unauthorized-mac".  Combine these legacy outputs into a format that the
    # existing parsing logic understands.
    $auth = @()
    if ($authSessionsAll.Count -gt 0) {
        # Unified table output
        $auth = Get-AuthStatusUnified $authSessionsAll
    } else {
        # Choose appropriate dot1x session block.  Prefer the modern command when
        # available, otherwise fall back to the legacy "mac-sessions" command.
        $dot1xBlockToUse = @()
        if ($dot1xSessions -and $dot1xSessions.Count -gt 0) {
            $dot1xBlockToUse = $dot1xSessions
        } elseif ($dot1xMacSessions -and $dot1xMacSessions.Count -gt 0) {
            $dot1xBlockToUse = $dot1xMacSessions
        }
        # Choose appropriate MAC authentication block.  Prefer the modern session
        # command when present; otherwise construct a combined list from the
        # authorized and unauthorized legacy lists.  Append a trailing "Yes" or
        # "No" token to each line from the legacy lists so that it matches the
        # regex used by Get-AuthStatus.  The regex expects a final field of
        # "Yes"/"No" indicating authorization status.
        $macAuthBlockToUse = @()
        if ($macAuthSessions -and $macAuthSessions.Count -gt 0) {
            $macAuthBlockToUse = $macAuthSessions
        } elseif (($authMacAuthorized -and $authMacAuthorized.Count -gt 0) -or ($authMacUnauthorized -and $authMacUnauthorized.Count -gt 0)) {
            $combined = [System.Collections.Generic.List[string]]::new()
            # Append authorized entries.  When lines originate from the legacy
            # "show auth-mac-addresses authorized-mac" command, the format is
            # "MAC Port Vlan Yes ...".  Normalize each line by reordering
            # fields to match the expected "Port MAC dynamic Vlan Yes" pattern.
            if ($authMacAuthorized) {
                foreach ($ln in $authMacAuthorized) {
                    $trimmed = $ln.Trim()
                    if ($trimmed -eq '') { continue }
                    # Skip header or separator lines
                    if ($trimmed -match '^-+$' -or $trimmed -match '^(?i)mac\s+addresses' -or $trimmed -match '^(?i)port\s+vlan') { continue }
                    if ($trimmed -match '([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})\s+(\d+/\d+/\d+)\s+(\d+)\s+(Yes|No)') {
                        $mac = $matches[1]; $port = $matches[2]; $vlan = $matches[3]; $authState = $matches[4]
                        $outLine = "$port $mac dynamic $vlan $authState"
                        [void]$combined.Add($outLine)
                    } else {
                        # If the line doesn't match the MAC-first format, append
                        # "Yes" if not already present.
                        $parts = $trimmed -split '\s+'
                        $lastField = $parts[-1]
                        if ($lastField -notmatch '^(?i)yes|no$') {
                            [void]$combined.Add(($trimmed + ' Yes'))
                        } else {
                            [void]$combined.Add($trimmed)
                        }
                    }
                }
            }
            # Append unauthorized entries with similar normalization.  For lines
            # produced by "show auth-mac-addresses unauthorized-mac", the MAC
            # address appears before the port.  Rearrange such entries and
            # append a trailing "No" to indicate unauthorized state.
            if ($authMacUnauthorized) {
                foreach ($ln in $authMacUnauthorized) {
                    $trimmed = $ln.Trim()
                    if ($trimmed -eq '') { continue }
                    if ($trimmed -match '^-+$' -or $trimmed -match '^(?i)mac\s+addresses' -or $trimmed -match '^(?i)port\s+vlan') { continue }
                    if ($trimmed -match '([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})\s+(\d+/\d+/\d+)\s+(\d+)\s+(Yes|No)') {
                        $mac = $matches[1]; $port = $matches[2]; $vlan = $matches[3]; $authState = $matches[4]
                        # Even if the line says "Yes", treat it as unauthorized (No)
                        $outLine = "$port $mac dynamic $vlan No"
                        [void]$combined.Add($outLine)
                    } else {
                        $parts = $trimmed -split '\s+'
                        $lastField = $parts[-1]
                        if ($lastField -notmatch '^(?i)yes|no$') {
                            [void]$combined.Add(($trimmed + ' No'))
                        } else {
                            [void]$combined.Add($trimmed)
                        }
                    }
                }
            }
            $macAuthBlockToUse = $combined.ToArray()
        }
        $auth = Get-AuthStatus $dot1xBlockToUse $macAuthBlockToUse
    }
    # $cfgResults and $configs are now computed above prior to calling Get-AuthModes.
    # NamesMap was also derived above; reuse here instead of recomputing.
    $interfaces = Get-InterfacesBrief $interfacesBlock
    $macs       = Get-MacTable $macTableBlock

    # Pre-index the MAC table and authentication rows by port to avoid pipeline
    # scans in the per-interface loop.  Normalize each port key to ensure that
    # ports specified with different prefixes (e.g. "Ethernet1/1/1" vs "Et1/1/1")
    # collide into the same entry.
    $macsByPort = @{}
    foreach ($m in $macs) {
        $p    = $m.Port
        $norm = ConvertTo-PortKey $p
        if (-not $macsByPort.ContainsKey($norm)) {
            $macsByPort[$norm] = [System.Collections.Generic.List[string]]::new()
        }
        [void]$macsByPort[$norm].Add([string]$m.MAC)
    }
    $authByPort = @{}
    foreach ($a in $auth) {
        # In case multiple auth rows are present for a port, prefer the first
        $norm = ConvertTo-PortKey $a.Port
        if (-not $authByPort.ContainsKey($norm)) {
            $authByPort[$norm] = $a
        }
    }

    # Build a per-port MAC row lookup to retrieve VLANs without scanning.  Use
    # normalized keys here as well so that a port is represented consistently
    # regardless of how its name appears in different command outputs.
    $macRowByPort = @{}
    foreach ($m in $macs) {
        $norm = ConvertTo-PortKey $m.Port
        # Keep the first MAC table row per port; later rows are ignored
        if (-not $macRowByPort.ContainsKey($norm)) {
            $macRowByPort[$norm] = $m
        }
    }

    $combined = foreach ($iface in $interfaces) {
        $port = $iface.Port
        $interfaceMAC = $iface.MAC
        # Use the precomputed lookup to retrieve the list of MAC addresses for this port.
        # Show only the first MAC in the grid to prevent excessively wide columns.  Keep
        # the full comma-separated list in a separate variable for downstream use
        # (e.g., tooltips or exports).
        # Look up the list of MAC addresses learned on this port.  Use a normalized
        # key for dictionary access to handle minor variations in port prefixes.
        $normPort = ConvertTo-PortKey $port
        $macArr = @()
        if ($macsByPort.ContainsKey($normPort)) {
            $macArr = $macsByPort[$normPort]
        }
        # Capture the number of learned MAC addresses so that the UI can display a
        # count instead of interpreting a MAC string as a numeric value.  When
        # no MACs are present, the count defaults to 0.
        $macCount = $macArr.Count
        if ($macCount -gt 0) {
            $macList     = $macArr[0]                 # display just the first MAC
            $macListFull = [string]::Join(',', $macArr)  # full comma-separated list
        } else {
            $macList     = ''
            $macListFull = ''
        }
        # Retrieve the auth row for this port, if present, via the pre-indexed dictionary.
        # Use the normalized key so that ports with or without an 'Et' prefix resolve the same.
        $authRow = if ($authByPort.ContainsKey($normPort)) { $authByPort[$normPort] } else { $null }
        # Lookup the configuration text for this port or default to an empty string.
        $cfgText = if ($configs.ContainsKey($port)) { $configs[$port] } elseif ($configs.ContainsKey($normPort)) { $configs[$normPort] } else { '' }
        # Prefer the alias/name from the brief output when present; fall back to the
        $desc = if ($iface.Name -and $iface.Name -ne '') {
            $iface.Name
        } elseif ($namesMap.ContainsKey($port)) {
            $namesMap[$port]
        } else {
            $port
        }
        $authMode = if ($authRow) {
            $authRow.Mode
        } elseif ($dot1xSet.ContainsKey($normPort)) {
            "dot1x"
        } elseif ($macauthSet.ContainsKey($normPort)) {
            "macauth"
        } else {
            "open"
        }
        $authState = if ($authRow) { $authRow.State } elseif ($authMode -eq "open") { "Open" } else { "Unknown" }
        # Determine the authentication template for the port.  Beginning with
        $dot1xEnabled   = $dot1xSet.ContainsKey($normPort)
        $macauthEnabled = $macauthSet.ContainsKey($normPort)
        # Determine the recommended authentication template for this port.  When both
        # MAC authentication and 802.1X are enabled on the same port, classify it
        # as "flexible".  The global "mac-authentication dot1x override" command
        # changes the order of attempts (MAC first) but does not alter the fact
        # that both modes are enabled.  Therefore we ignore the override when
        # determining the template.
        $authTemplate = switch ($true) {
            ($dot1xEnabled -and $macauthEnabled) { "flexible"; break }
            ($dot1xEnabled)                      { "dot1x";    break }
            ($macauthEnabled)                    { "macauth";  break }
            default                              { "open" }
        }
        # Use the precomputed MAC row lookup to retrieve the VLAN without scanning
        $vlan = if ($macRowByPort.ContainsKey($normPort)) {
            $macRowByPort[$normPort].VLAN
        } else {
            ''
        }
        # Determine port type via precompiled regular expressions rather than
        # matching inline patterns each time.  Use IsMatch() for efficiency.
        $type = if ($script:BrocadeTypeTrunkRegex.IsMatch($desc)) {
            "Trunk"
        } elseif ($script:BrocadeTypeAccessRegex.IsMatch($desc)) {
            "Access"
        } else {
            ""
        }

        [PSCustomObject]@{
            Port = $port; Name = $desc; Status = $iface.Status; VLAN = $vlan; Duplex = $iface.Duplex;
            Speed = $iface.Speed; Type = $type; InterfaceMAC = $interfaceMAC;
            LearnedMACs = $macList; LearnedMACsFull = $macListFull; LearnedMACCount = $macCount;
            AuthState = $authState;
            AuthMode = $authMode; AuthClientMAC = if ($authRow) { $authRow.MAC } else { "" };
            Config = $cfgText; AuthTemplate = $authTemplate
        }
    }

    # Attempt to parse spanning-tree information if present.  Locate the
    $spanBlock = DeviceLogParserModule\Get-ShowBlock -Blocks $blocks -Lines $Lines -PreferredKeys @('show spanning-tree') -RegexPatterns @('^show\s+span(\b|$)') -CommandRegexes @('#\s*show\s+span(?:ning-tree)?') -DefaultValue @()
    # Parse spanning tree information using the shared DeviceLogParserModule\ConvertFrom-SpanningTree helper
    $spanInfo = if ($spanBlock.Count -gt 0) { DeviceLogParserModule\ConvertFrom-SpanningTree -SpanLines $spanBlock } else { @() }

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
        AuthenticationBlock = @($authBlockRaw)
        SpanInfo = $spanInfo
    }
}

Export-ModuleMember -Function Get-BrocadeDeviceFacts
