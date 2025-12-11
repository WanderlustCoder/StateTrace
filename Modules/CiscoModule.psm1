
if (-not (Get-Variable -Name CiscoDot1xMacRegex -Scope Script -ErrorAction SilentlyContinue)) {
    $script:CiscoDot1xMacRegex = [regex]::new('^(?:[0-9A-Fa-f]{4}\.){2}[0-9A-Fa-f]{4}$')
}
if (-not (Get-Variable -Name CiscoDot1xModeRegex -Scope Script -ErrorAction SilentlyContinue)) {
    $script:CiscoDot1xModeRegex = [regex]::new('dot1x|mab', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}
if (-not (Get-Variable -Name CiscoDot1xAuthRegex -Scope Script -ErrorAction SilentlyContinue)) {
    $script:CiscoDot1xAuthRegex = [regex]::new('auth', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}
if (-not (Get-Variable -Name CiscoDot1xUnauthRegex -Scope Script -ErrorAction SilentlyContinue)) {
    $script:CiscoDot1xUnauthRegex = [regex]::new('unauth|fail', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Get-CiscoDeviceFacts {
    [CmdletBinding()]
    param (
        [string[]]$Lines,
        [hashtable]$Blocks
    )

    #-----------------------------------------

    #-----------------------------------------
    function Get-Hostname      {
        param([string[]]$Lines)
        $hostname = DeviceParsingCommon\Get-HostnameFromPrompt -Lines $Lines -RunningConfigPattern '^(?i)\s*hostname\s+(.+)$'
        if ($hostname) { return $hostname }
        return 'Unknown'
    }
    function Get-ModelAndVersion { param([string[]]$Lines)
        $model='Unknown'; $version='Unknown'
        foreach ($l in $Lines) {
            # Capture model number in a case-insensitive way.  Look for
            # "Model Number" or "Model number" followed by a colon and a value.
            if ($l -match '(?i)Model\s+Number\s*:\s*(\S+)') {
                $model = $matches[1]
                continue
            }
            # Many older routers do not print a "Model Number" line.  They
            # instead include the model in a line like "Cisco 881 (MPC) processor".
            # Capture the first word after "Cisco" up to a space or parenthesis.
            if ($model -eq 'Unknown' -and $l -match '(?i)^Cisco\s+([\w\-]+)\s*\(') {
                $model = $matches[1]
                continue
            }
            # Capture software version (e.g. "Version 15.1(4)M4").  Accept
            # alphanumeric versions with parentheses and dots.
            if ($l -match '(?i)Version\s+([\w\.\(\)-]+)') {
                $version = $matches[1]
                continue
            }
        }
        return @($model,$version)
    }
    function Get-Uptime        {
        param([string[]]$Lines)
        $uptime = DeviceParsingCommon\Get-UptimeFromLines -Lines $Lines
        if ($uptime) { return $uptime }
        return 'Unknown'
    }
    function Get-Location {
        param([string[]]$Lines)
        # Delegate to the shared helper that handles vendor-specific keywords
        return Get-SnmpLocationFromLines -Lines $Lines
    }

    function Get-InterfaceConfigs {
        param([string[]]$Lines)
        $ht = @{}
        for ($i=0; $i -lt $Lines.Count; $i++) {
            $l = $Lines[$i]
            if ($l -match '^interface\s+(\S+)') {
                $fullName = $matches[1]
                # Use a strongly typed List[string] instead of a PowerShell array.  Using
                $block    = [System.Collections.Generic.List[string]]::new()
                [void]$block.Add($l)
                $desc     = ''
                $j        = $i+1
                while ($j -lt $Lines.Count -and $Lines[$j] -notmatch '^interface' -and $Lines[$j] -notmatch '^!') {
                    [void]$block.Add($Lines[$j])
                    if ($Lines[$j] -match '^\s*description\s+(.+)$') { $desc=$matches[1].Trim() }
                    $j++
                }
                # Convert the typed list to a single string using Join instead of array -join
                $cfgObj = @{ Config=[string]::Join("`r`n", $block); Description=$desc }
                $ht[$fullName] = $cfgObj
                if ($fullName -match '^(GigabitEthernet|FastEthernet|TenGigabitEthernet)(\S+)$') {
                    $shortType = switch ($matches[1]) {
                        'GigabitEthernet'    {'Gi'}
                        'FastEthernet'       {'Fa'}
                        'TenGigabitEthernet' {'Te'}
                        Default              {$matches[1]}
                    }
                    $alias = $shortType + $matches[2]
                    if (-not $ht.ContainsKey($alias)) { $ht[$alias]=$cfgObj }
                }
                $i = $j - 1
            }
        }
        return $ht
    }

    function Get-AuthDefaultVLAN {
        param([string[]]$Lines)
        foreach ($line in $Lines) {
            if ($line -match 'auth-default-vlan\s+(\d+)') { return $matches[1] }
            elseif ($line -match '\bguest-vlan\s+(\d+)')  { return $matches[1] }
        }
        return ''
    }

    function Get-AuthBlock {
        param([string[]]$Lines)
        # Use a typed List[string] to avoid O(n^2) behaviour from array '+='
        $blk = [System.Collections.Generic.List[string]]::new()
        foreach ($line in $Lines) {
            $trim = $line.Trim()
            if ($trim -match '^(authentication|dot1x|mab|reauthentication)\b') {
                [void]$blk.Add($trim)
            }
        }
        return [string]::Join("`r`n", $blk)
    }

    function Get-InterfacesStatus {
        param([string[]]$Lines)
        $reWs = New-Object System.Text.RegularExpressions.Regex('\s+')
        $statusTokens = @('connected','notconnect','disabled','err-disabled','inactive','suspended','sfp-config-mismatch','sfp-mismatch','sfp-not-present','routed','trunk','monitoring')
        $propertyMap = [ordered]@{
            Row = { param($match) $match.Groups['line'].Value.TrimEnd() }
        }
        $postProcess = {
            param($obj, $match)
            $line = $obj.Row
            if ([string]::IsNullOrWhiteSpace($line)) { return $null }
            $tokens = $reWs.Split($line)
            if ($tokens.Length -lt 2) { return $null }

            $raw = $tokens[0]
            $statusIdx = -1
            $inMarker = $false
            $candidateIdxList = [System.Collections.Generic.List[int]]::new()
            for ($i = 1; $i -lt $tokens.Length; $i++) {
                $tok = $tokens[$i]
                if ($tok -match '<' -and -not $tok -match '>') { $inMarker = $true }
                if ($tok -match '>' -and -not $tok -match '<') { $inMarker = $false; continue }
                if ($inMarker) { continue }
                $tokLower = $tok.ToLowerInvariant()
                if ($statusTokens -contains $tokLower) {
                    [void]$candidateIdxList.Add($i)
                }
            }
            if ($candidateIdxList.Count -gt 0) {
                $statusIdx = $candidateIdxList[$candidateIdxList.Count - 1]
            }
            if ($statusIdx -eq -1) {
                if ($tokens.Length -ge 7) {
                    $statusIdx = $tokens.Length - 5
                } else {
                    return $null
                }
            }

            $nameTokens = @()
            if ($statusIdx -gt 1) {
                $nameTokens = $tokens[1..($statusIdx - 1)]
            }
            $name   = ($nameTokens -join ' ').Trim()

            $status = ''
            $vlan   = ''
            $duplex = ''
            $speed  = ''
            $type   = ''
            if ($statusIdx -ge 0 -and $statusIdx -lt $tokens.Length) {
                $status = $tokens[$statusIdx]
                if ($statusIdx + 1 -lt $tokens.Length) { $vlan   = $tokens[$statusIdx + 1] }
                if ($statusIdx + 2 -lt $tokens.Length) { $duplex = $tokens[$statusIdx + 2] }
                if ($statusIdx + 3 -lt $tokens.Length) { $speed  = $tokens[$statusIdx + 3] }
                if ($statusIdx + 4 -lt $tokens.Length) {
                    $typeTokens = $tokens[($statusIdx + 4)..($tokens.Length - 1)]
                    $type = ($typeTokens -join ' ').Trim()
                }
            }

            return [PSCustomObject]@{
                RawPort = $raw
                Port    = $raw
                Name    = $name
                Status  = $status
                VLAN    = $vlan
                Duplex  = $duplex
                Speed   = $speed
                Type    = $type
            }
        }

        return DeviceParsingCommon\Invoke-RegexTableParser -Lines $Lines -HeaderPattern '^Port\s+Name\s+Status' -RowPattern '^(?<line>.+)$' -PropertyMap $propertyMap -PostProcess $postProcess
    }

    # Normalize a full interface name into its short form.  Cisco devices may
    # report ports in the MAC address table using long prefixes such as
    # "GigabitEthernet" or "FastEthernet", potentially with or without a space
    # before the numeric designator (e.g. "GigabitEthernet1/0/1" or
    # "GigabitEthernet 1/0/1").  The status table, however, uses short
    # abbreviations like "Gi" or "Fa".  To ensure MAC entries map back to
    # interface rows, convert long-form names to their abbreviated form.
    # Convert a full interface name (e.g. "GigabitEthernet1/0/1")
    # into its short alias (e.g. "Gi1/0/1").  Using the approved
    # verb 'ConvertTo' clarifies that this helper transforms one
    # representation into another.  The previous name 'Normalize-PortName'
    # used the unapproved verb 'Normalize', which triggered import
    # warnings.  Calls to the old name have been updated accordingly.
    function Get-MacTable {
        param([string[]]$Lines)
        $portTransform = {
            param($port)
            $text = if ($null -ne $port) { ('' + $port).Trim() } else { '' }
            if (-not $text) { return $text }
            # Collapse whitespace inside the port column before shortening prefixes.
            $text = $text -replace '\s+', ''
            return DeviceParsingCommon\ConvertTo-ShortPortName -Port $text
        }
        return DeviceParsingCommon\ConvertFrom-MacTableRegex -Lines $Lines -HeaderPattern '^(?i)\s*Vlan\s+Mac\s+Address' -RowPattern '^(\\d+)\\s+((?:[0-9A-Fa-f]{4}\\.){2}[0-9A-Fa-f]{4})\\s+\\S+\\s+(.+)$' -VlanGroup 1 -MacGroup 2 -PortGroup 3 -PortTransform $portTransform
    }

    function Get-Dot1xStatus {
        param([string[]]$Lines)
        $propertyMap = [ordered]@{
            Row = { param($match) $match.Groups[0].Value.Trim() }
        }
        $postProcess = {
            param($obj, $match)
            $text = $obj.Row
            if (-not $text) { return $null }
            if ($text -match '^-+$') { return $null }
            $parts = $text -split '\s+'
            if ($parts.Length -lt 4) { return $null }

            $iface = $parts[0]
            $mac   = ''
            for ($i = 1; $i -lt $parts.Length; $i++) {
                if ($script:CiscoDot1xMacRegex.IsMatch($parts[$i])) { $mac = $parts[$i]; break }
            }

            $method = ''
            for ($i = 1; $i -lt $parts.Length; $i++) {
                if ($script:CiscoDot1xModeRegex.IsMatch($parts[$i])) { $method = $parts[$i]; break }
            }

            $status = ''
            $sessionId = ''
            if ($parts.Length -eq 4) {
                $status = $parts[3]
            } else {
                $sessionId = $parts[$parts.Length - 1]
                $startIdx = 3
                if ($method) {
                    $mIdx = [Array]::IndexOf($parts, $method)
                    if ($mIdx -ge 0) { $startIdx = $mIdx + 1 }
                }
                if ($startIdx -le $parts.Length - 2) {
                    $status = ($parts[$startIdx..($parts.Length - 2)] -join ' ').Trim()
                }
            }

            $authState = 'Unknown'
            if ($status) {
                if ($script:CiscoDot1xAuthRegex.IsMatch($status) -and -not $script:CiscoDot1xUnauthRegex.IsMatch($status)) { $authState = 'Authorized' }
                elseif ($script:CiscoDot1xUnauthRegex.IsMatch($status)) { $authState = 'Unauthorized' }
            }

            $authMode = if ($method) { $method } else { 'unknown' }

            return [PSCustomObject]@{
                Interface = $iface
                MAC       = $mac
                Status    = $status
                AuthState = $authState
                AuthMode  = $authMode
                SessionID = $sessionId
            }
        }

        return DeviceParsingCommon\Invoke-RegexTableParser -Lines $Lines -HeaderPattern '(?i)^Interface\s+MAC' -RowPattern '^(?<line>.+)$' -PropertyMap $propertyMap -PostProcess $postProcess
    }

    # Parse show spanning-tree output into a collection of summary rows.  Each

    #
    function Get-PortAuthTemplates {
        param([hashtable]$Configs)

        $result   = @{}
        # list of commands considered part of dual-auth (for compliance).  Use
        # a strongly typed list to avoid array reallocations when appending.
        $required = [System.Collections.Generic.List[string]]::new()
        foreach ($r in @(
            'authentication event fail action next-method',
            'authentication order mab dot1x',
            'authentication priority dot1x mab',
            'authentication port-control auto',
            'dot1x timeout quiet-period 90',
            'dot1x timeout tx-period 5'
        )) {
            [void]$required.Add($r)
        }

        foreach ($key in $Configs.Keys) {
            # normalize to lower-case trimmed lines
            $lines = $Configs[$key].Config -split "`r?`n" | ForEach-Object { $_.Trim().ToLowerInvariant() }

            # Was originally only checking the 'authentication order ... mab' line:
            $hasDot1x = $lines -contains 'dot1x pae authenticator'
            $hasMab   = $lines -contains 'mab'

            if ($hasDot1x -and $hasMab) {
                # dual (flexible) auth.  Accumulate missing commands using a
                # strongly typed list to avoid array reallocation.  Convert
                # the list to an array when storing in the result.
                $missing = [System.Collections.Generic.List[string]]::new()
                foreach ($cmd in $required) {
                    if (-not ($lines -contains $cmd)) { [void]$missing.Add($cmd) }
                }
                $result[$key] = @{ Template='flexible'; MissingCommands = $missing.ToArray() }
            }
            elseif ($hasDot1x) {
                $result[$key] = @{ Template='dot1x'; MissingCommands=@() }
            }
            elseif ($hasMab) {
                $result[$key] = @{ Template='macauth'; MissingCommands=@() }
            }
            else {
                $result[$key] = @{ Template='open'; MissingCommands=@() }
            }
        }

        return $result
    }

    #-----------------------------------------
    if (-not $Blocks) {
        try { $Blocks = DeviceLogParserModule\Get-ShowCommandBlocks -Lines $Lines } catch { $Blocks = @{} }
    }
    $blocks = $Blocks
    # Retrieve show command blocks with graceful fallbacks when the exact
    # command name is not present.  Some devices emit singular variants (e.g.
    # "show authentication session") or omit hyphens.  We search for the
    # desired block and, if not found, scan for keys that begin with the
    # expected prefix.  This prevents missing data when commands are spelled
    # differently in the logs.
    $runCfg = DeviceLogParserModule\Get-ShowBlock -Blocks $blocks -Lines $Lines -PreferredKeys @('show running-config') -CommandRegexes @('^[^\s]+[>#]\s*(?:do\s+)?show\s+running-config') -DefaultValue @()
    $verBlk = DeviceLogParserModule\Get-ShowBlock -Blocks $blocks -Lines $Lines -PreferredKeys @('show version') -CommandRegexes @('^[^\s]+[>#]\s*(?:do\s+)?show\s+version') -DefaultValue @()
    $intStat = DeviceLogParserModule\Get-ShowBlock -Blocks $blocks -Lines $Lines -PreferredKeys @('show interface status','show interfaces status') -RegexPatterns @('^show\s+interfaces?\s+status') -CommandRegexes @('^[^\s]+[>#]\s*(?:do\s+)?show\s+interfaces?\s+status') -DefaultValue @()
    $macTbl = DeviceLogParserModule\Get-ShowBlock -Blocks $blocks -Lines $Lines -PreferredKeys @('show mac address-table','show mac-address-table') -RegexPatterns @('^show\s+mac[- ]address[- ]table') -CommandRegexes @('^[^\s]+[>#]\s*(?:do\s+)?show\s+mac[- ]address[- ]table') -DefaultValue @()
    $authSes = DeviceLogParserModule\Get-ShowBlock -Blocks $blocks -Lines $Lines -PreferredKeys @('show authentication sessions','show authentication session') -RegexPatterns @('^show\s+authentication\s+sessions?','^show\s+auth\w*\s+ses\w*') -CommandRegexes @('^[^\s]+[>#]\s*(?:do\s+)?show\s+authentication\s+sessions?') -DefaultValue @()

    # Use the full original lines to derive the hostname rather than just the running-config
    $hostname  = Get-Hostname      -Lines $Lines
    $modelVer  = Get-ModelAndVersion -Lines $verBlk
    $uptime    = Get-Uptime        -Lines $verBlk
    $location  = Get-Location      -Lines $runCfg
    $configs   = Get-InterfaceConfigs -Lines $runCfg
    $status    = Get-InterfacesStatus  -Lines $intStat
    $macs      = Get-MacTable         -Lines $macTbl
    $auth      = Get-Dot1xStatus      -Lines $authSes
    $authTemplates = Get-PortAuthTemplates -Configs $configs

    # Only compute auth-related values when the running config contains relevant keywords.
    $authDefaultVLAN = ''
    if ($runCfg -match '(?i)auth-default-vlan|guest-vlan') {
        $authDefaultVLAN = Get-AuthDefaultVLAN -Lines $runCfg
    }
    $authBlock = ''
    if ($runCfg -match '(?i)(authentication|dot1x|mab|reauthentication)') {
        $authBlock = Get-AuthBlock -Lines $runCfg
    }

    # ----------------------------------------------------------------------

    # Build a lookup of port -> list of MAC addresses (strings) and a
    $macsByPort      = @{}
    $firstMacByPort  = @{}
    foreach ($entry in $macs) {
        $p = $entry.Port
        if (-not $macsByPort.ContainsKey($p)) {
            $macsByPort[$p]     = [System.Collections.Generic.List[string]]::new()
            # also record the first MAC row for this port
            $firstMacByPort[$p] = $entry
        }
        [void]$macsByPort[$p].Add([string]$entry.MAC)
    }

    # Build a lookup of interface -> first authentication session row.  Using
    $authByPort = @{}
    foreach ($session in $auth) {
        $p = $session.Interface
        if (-not $authByPort.ContainsKey($p)) {
            $authByPort[$p] = $session
        }
    }

    # Use a typed list to accumulate interface summary objects.  Using
    $combinedList = [System.Collections.Generic.List[object]]::new()
    foreach ($iface in $status) {
        $raw      = $iface.RawPort
        $cfgEntry = $configs[$raw]
        $cfgText  = if ($cfgEntry) { $cfgEntry.Config } else { '' }
        # Prefer the configured description when available.  Otherwise, fall back to
        # the parsed Name from the interface status output, and finally to the raw
        # port identifier if both are missing.  This preserves user-specified
        # descriptions (including those with spaces or hyphens) and avoids
        # empty names when a description is not configured.
        $name     = if ($cfgEntry -and $cfgEntry.Description) {
            $cfgEntry.Description
        } elseif ($iface.Name -and $iface.Name.Trim().Length -gt 0) {
            $iface.Name.Trim()
        } else {
            $raw
        }

        # Retrieve MACs and first MAC row via lookup.  If no entry exists,
        $macListRef = $null
        $macEntry   = $null
        if ($macsByPort.ContainsKey($raw)) {
            $macListRef = $macsByPort[$raw]
            $macEntry   = $firstMacByPort[$raw]
        }
        # Join MAC addresses into a comma-separated string and capture the first MAC
        # separately.  Display only the first MAC in the grid to prevent column bloat,
        # while preserving the full list for downstream use.
        $macListDisplay = ''
        $macListFull    = ''
        if ($macListRef) {
            $macListFull = [string]::Join(',', $macListRef)
            if ($macListRef.Count -gt 0) {
                $macListDisplay = $macListRef[0]
            }
        }

        # Retrieve the first authentication row via the lookup.  If none
        $authRow = if ($authByPort.ContainsKey($raw)) { $authByPort[$raw] } else { $null }

        # Determine interface MAC and VLAN information from the first MAC
        $interfaceMac = if ($macEntry) { $macEntry.MAC } else { '' }
        $authVlan     = if ($macEntry) { $macEntry.VLAN } else { '' }

        # Retrieve the precomputed authentication template information.
        $templateInfo = $authTemplates[$raw]

        # Build the summary object and add to the typed list.  All
        $obj = [PSCustomObject]@{
            Port            = $raw
            Name            = $name
            Status          = $iface.Status
            VLAN            = $iface.VLAN
            Duplex          = $iface.Duplex
            Speed           = $iface.Speed
            Type            = $iface.Type
            InterfaceMAC    = $interfaceMac
            LearnedMACs     = $macListDisplay
            LearnedMACsFull = $macListFull
            AuthState       = if ($authRow) { $authRow.AuthState } else { 'Unknown' }
            AuthMode        = if ($authRow) { $authRow.AuthMode }  else { 'unknown' }
            AuthClientMAC   = if ($authRow) { $authRow.MAC }       else { '' }
            AuthVLAN        = $authVlan
            Config          = $cfgText
            AuthTemplate    = $templateInfo.Template
            MissingAuthCmds = $templateInfo.MissingCommands -join ','
        }
        [void]$combinedList.Add($obj)
    }
    # Assign the combined list to a variable with the original name for
    $combined = $combinedList

    # Gather spanning tree information if the log included a 'show spanning-tree'
    $spanLines = @()
    if ($blocks.ContainsKey('show spanning-tree')) {
        $spanLines = $blocks['show spanning-tree']
    } elseif ($blocks.ContainsKey('show span')) {
        $spanLines = $blocks['show span']
    } else {
        foreach ($k in $blocks.Keys) {
            if ($k -match '^show\s+spanning-tree') {
                $spanLines = $blocks[$k]
                break
            }
        }
        if (-not $spanLines -or $spanLines.Count -eq 0) {
            foreach ($k in $blocks.Keys) {
                if ($k -match '^show\s+span(\b|$)') {
                    $spanLines = $blocks[$k]
                    break
                }
            }
        }
    }
    # Parse spanning tree information using the shared ConvertFrom-SpanningTree helper
    $spanInfo = if ($spanLines.Count -gt 0) { ConvertFrom-SpanningTree -SpanLines $spanLines } else { @() }

    return [PSCustomObject]@{
        Hostname           = $hostname
        Make               = 'Cisco'
        Model              = $modelVer[0]
        Version            = $modelVer[1]
        Uptime             = $uptime
        Location           = $location
        InterfaceCount     = $combined.Count
        AuthDefaultVLAN    = $authDefaultVLAN
        AuthBlock          = $authBlock
        InterfacesCombined = $combined
        SpanInfo           = $spanInfo
    }
}
