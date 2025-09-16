
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
        # Prefer prompt-derived hostname (supports "SSH@host#", "host#", or "host>")
        foreach ($l in $Lines) {
            if ($l -match '^(?:SSH@)?(\S+?)[#>]') {
                return ($matches[1])
            }
        }
        # Fallback to running-config 'hostname <name>'
        foreach ($l in $Lines) {
            if ($l -match '^(?i)\s*hostname\s+(.+)$') {
                return $matches[1]
            }
        }
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
    function Get-Uptime        { param([string[]]$Lines) foreach ($l in $Lines) { if ($l -match 'uptime is (.+)$') { return $matches[1].Trim() } }; return 'Unknown' }
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
                $block    = New-Object 'System.Collections.Generic.List[string]'
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
        $blk = New-Object 'System.Collections.Generic.List[string]'
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
        # Use a strongly typed list instead of repeatedly using += on a PowerShell
        $res = New-Object 'System.Collections.Generic.List[object]'
        $parsing=$false

        # Precompile patterns used repeatedly in the loop to avoid recompiling
        # regular expressions on each iteration.  Splitting on whitespace uses a
        # Regex with a specified maximum count for efficiency.
        $reHeader = [regex]::new('^Port\s+Name\s+Status')
        $reBlank  = [regex]::new('^\s*$')
        # Note: compiled option is implied when using .new() with no options.  This regex
        # matches one or more whitespace characters and is used to split each line
        # into individual tokens.  Splitting rather than matching columns allows
        # us to reconstruct the Name field even when it contains spaces.
        $reWs     = [regex]::new('\s+')

        foreach ($l in $Lines) {
            if ($reHeader.IsMatch($l)) { $parsing = $true; continue }
            if ($parsing) {
                # Stop when we hit a blank line which denotes the end of the status table
                if ($reBlank.IsMatch($l)) { break }
                # Split the line on whitespace.  The interface status output has
                # seven logical columns: Port, Name, Status, Vlan, Duplex, Speed, Type.
                # However, both the Name and Type columns can contain spaces or hyphens.
                # To robustly parse the line, identify the Status field by scanning
                # for a known status token and treat everything between Port and Status
                # as the Name.
                $tokens = $reWs.Split($l)
                if ($tokens.Length -lt 2) { continue }
                $raw        = $tokens[0]
                $statusIdx  = -1
                # Define a list of known status values.  These values are taken from
                # typical 'show interface status' output and may need to be extended
                # for other IOS versions.  Matching is case-insensitive.
                $knownStatuses = @('connected','notconnect','disabled','err-disabled','inactive','suspended','sfp-config-mismatch','sfp-mismatch','sfp-not-present','routed','trunk','monitoring')
                # Search for the first occurrence of a status token after the port.
                for ($i = 1; $i -lt $tokens.Length; $i++) {
                    $tok = $tokens[$i]
                    if ($knownStatuses -contains $tok) {
                        $statusIdx = $i
                        break
                    }
                }
                if ($statusIdx -eq -1) {
                    # If we didn't find a known status, fall back to assuming the
                    # status field begins five tokens from the end (the legacy logic).
                    if ($tokens.Length -ge 7) {
                        $statusIdx = $tokens.Length - 5
                    } else {
                        continue
                    }
                }
                # Name consists of all tokens between the port and the status.
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
                # Extract Status and subsequent columns if they exist
                if ($statusIdx -ge 0 -and $statusIdx -lt $tokens.Length) {
                    $status = $tokens[$statusIdx]
                    # VLAN, Duplex, Speed follow sequentially if available
                    if ($statusIdx + 1 -lt $tokens.Length) { $vlan   = $tokens[$statusIdx + 1] }
                    if ($statusIdx + 2 -lt $tokens.Length) { $duplex = $tokens[$statusIdx + 2] }
                    if ($statusIdx + 3 -lt $tokens.Length) { $speed  = $tokens[$statusIdx + 3] }
                    # Type may consist of one or more remaining tokens
                    if ($statusIdx + 4 -lt $tokens.Length) {
                        $typeTokens = $tokens[($statusIdx + 4)..($tokens.Length - 1)]
                        $type = ($typeTokens -join ' ').Trim()
                    }
                }
                [void]$res.Add([PSCustomObject]@{
                    RawPort = $raw
                    Port    = $raw
                    Name    = $name
                    Status  = $status
                    VLAN    = $vlan
                    Duplex  = $duplex
                    Speed   = $speed
                    Type    = $type
                })
            }
        }
        return $res
    }

    function Get-MacTable {
        param([string[]]$Lines)
        # Parse the MAC address table from "show mac address-table" output.  The previous
        # implementation only captured dynamic entries with a strict three-column
        # pattern (VLAN, MAC, DYNAMIC, Port), which missed static or extended
        # formats.  This revised parser handles any MAC table line that begins
        # with a VLAN number and MAC address, regardless of the Type column and
        # intermediate columns.  It collects the VLAN, MAC and final port
        # column.  Ports like "CPU" or other non-interface values are still
        # captured; callers can filter them out if needed.
        $results = New-Object 'System.Collections.Generic.List[object]'
        foreach ($line in $Lines) {
            $t = ($line -as [string]).Trim()
            if (-not $t) { continue }
            # Skip obvious headers or separators
            if ($t -match '^(Vlan|----|Mac\s+Address|Total)') { continue }
            $parts = $t -split '\s+'
            # Require at least 4 columns: VLAN, MAC, Type, Port
            if ($parts.Length -ge 4) {
                $vlan = $parts[0]
                $mac  = $parts[1]
                $port = $parts[-1]
                # Validate VLAN and MAC patterns before adding.  Accept only
                # numeric VLANs and MAC addresses in xxxx.xxxx.xxxx format.
                if ($vlan -match '^\d+$' -and $mac -match '^(?:[0-9A-Fa-f]{4}\.){2}[0-9A-Fa-f]{4}$') {
                    [void]$results.Add([PSCustomObject]@{ VLAN=$vlan; MAC=$mac; Port=$port })
                }
            }
        }
        return $results
    }

    function Get-Dot1xStatus {
        param([string[]]$Lines)
        # Parse the output of "show authentication sessions".  Cisco switches may
        # format this table with varying numbers of columns.  The original
        # implementation assumed a fixed six-column format and skipped any
        # entries that did not exactly match, causing valid session data to be
        # ignored.  This revised parser accepts any line with at least four
        # columns and extracts the interface, MAC address, authentication
        # method, status text and optional session ID.  It uses more
        # permissive matching to handle lines where some fields are omitted.

        $results = New-Object 'System.Collections.Generic.List[object]'
        $inTable = $false
        # Precompiled regexes for performance
        $reHeader = [regex]::new('^Interface\s+MAC', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        # Match a separator line composed of three or more hyphens.  Some
        # platforms, such as Cisco Catalyst 9300, insert a line of dashes
        # after the table headers.  We should skip this line rather than
        # terminating the parse.
        $reSep    = [regex]::new('^\s*-{3,}$')
        $reMac    = [regex]::new('^(?:[0-9A-Fa-f]{4}\.){2}[0-9A-Fa-f]{4}$')
        $reMode   = [regex]::new('dot1x|mab', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $reAuth   = [regex]::new('auth', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $reUnauth = [regex]::new('unauth|fail', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

        foreach ($line in $Lines) {
            $t = ($line -as [string]).Trim()
            if (-not $t) { continue }
            if (-not $inTable) {
                if ($reHeader.IsMatch($t)) { $inTable = $true; continue }
                else { continue }
            }
            # Skip dashed separator lines, but break on a blank line which
            # denotes the end of the table.  Cisco 9300 outputs a line of
            # hyphens after the column headers; we ignore it and continue
            # parsing subsequent rows.
            if ($reSep.IsMatch($t)) { continue }
            if ($t -match '^\s*$') { break }
            $parts = $t -split '\s+'
            # Require at least four columns: Interface, MAC, Method, Status or SessionID
            if ($parts.Length -ge 4) {
                $iface = $parts[0]
                $mac   = ''
                # Find the first token that looks like a MAC address
                for ($i=1; $i -lt $parts.Length; $i++) {
                    if ($reMac.IsMatch($parts[$i])) { $mac = $parts[$i]; break }
                }
                # Determine the authentication method by searching tokens after the MAC
                $method = ''
                for ($i=1; $i -lt $parts.Length; $i++) {
                    if ($reMode.IsMatch($parts[$i])) { $method = $parts[$i]; break }
                }
                # Compute the status string.  If exactly four tokens, treat the fourth
                # token as the status.  Otherwise, join all tokens between the method
                # column and the last column (session ID).  If the method cannot be
                # located, join tokens starting at index 3 up to the second last.
                $status = ''
                $sessionId = ''
                if ($parts.Length -eq 4) {
                    $status    = $parts[3]
                    $sessionId = ''
                } else {
                    # The last token is assumed to be a Session ID when more than four columns
                    $sessionId = $parts[-1]
                    $startIdx = 3
                    if ($method) {
                        $mIdx = [Array]::IndexOf($parts, $method)
                        if ($mIdx -ge 0) { $startIdx = $mIdx + 1 }
                    }
                    if ($startIdx -le $parts.Length - 2) {
                        $status = ($parts[$startIdx..($parts.Length-2)] -join ' ').Trim()
                    } else {
                        $status = ''
                    }
                }
                # Derive AuthState from the status text
                $authState = 'Unknown'
                if ($status -ne '') {
                    if ($reAuth.IsMatch($status) -and -not $reUnauth.IsMatch($status)) { $authState = 'Authorized' }
                    elseif ($reUnauth.IsMatch($status)) { $authState = 'Unauthorized' }
                }
                # Normalise method to lower-case; if not found, use 'unknown'
                $authMode  = if ($method) { $method } else { 'unknown' }
                [void]$results.Add([PSCustomObject]@{
                    Interface = $iface
                    MAC       = $mac
                    Status    = $status
                    AuthState = $authState
                    AuthMode  = $authMode
                    SessionID = $sessionId
                })
            }
        }
        return $results
    }

    # Parse show spanning-tree output into a collection of summary rows.  Each

    #
    function Get-PortAuthTemplates {
        param([hashtable]$Configs)

        $result   = @{}
        # list of commands considered part of dual-auth (for compliance).  Use
        # a strongly typed list to avoid array reallocations when appending.
        $required = New-Object 'System.Collections.Generic.List[string]'
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
            $lines = $Configs[$key].Config -split "`r?`n" | ForEach-Object { $_.Trim().ToLower() }

            # Was originally only checking the 'authentication order ... mab' line:
            $hasDot1x = $lines -contains 'dot1x pae authenticator'
            $hasMab   = $lines -contains 'mab'

            if ($hasDot1x -and $hasMab) {
                # dual (flexible) auth.  Accumulate missing commands using a
                # strongly typed list to avoid array reallocation.  Convert
                # the list to an array when storing in the result.
                $missing = New-Object 'System.Collections.Generic.List[string]'
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
    $blocks    = Get-ShowCommandBlocks -Lines $Lines
    # Retrieve show command blocks with graceful fallbacks when the exact
    # command name is not present.  Some devices emit singular variants (e.g.
    # "show authentication session") or omit hyphens.  We search for the
    # desired block and, if not found, scan for keys that begin with the
    # expected prefix.  This prevents missing data when commands are spelled
    # differently in the logs.
    $runCfg = if ($blocks.ContainsKey('show running-config')) {
        $blocks['show running-config']
    } else { @() }
    $verBlk = if ($blocks.ContainsKey('show version')) {
        $blocks['show version']
    } else { @() }
    # Interface status may appear in a variety of forms such as
    # "show interface status", "show interfaces status", or with additional
    # qualifiers (e.g. "show interfaces status port-channel").  Check the
    # common exact keys first, then fall back to the first block whose key
    # matches the pattern "^show\s+interfaces?\s+status".  This regex
    # tolerates both singular and plural forms of "interface".
    if ($blocks.ContainsKey('show interface status')) {
        $intStat = $blocks['show interface status']
    } elseif ($blocks.ContainsKey('show interfaces status')) {
        $intStat = $blocks['show interfaces status']
    } else {
        $intStat = @()
        foreach ($k in $blocks.Keys) {
            if ($k -match '^show\s+interfaces?\s+status') { $intStat = $blocks[$k]; break }
        }
    }
    # MAC address table commands vary across platforms.  In addition to
    # "show mac address-table" and "show mac address table", some older
    # devices (e.g. C880/888) use "show mac-address-table".  Check for
    # common exact keys first, then search for patterns that match hyphen
    # or space separated versions.  This captures variants like
    # "show mac address-table dynamic" and "show mac-address-table".
    if ($blocks.ContainsKey('show mac address-table')) {
        $macTbl = $blocks['show mac address-table']
    } elseif ($blocks.ContainsKey('show mac-address-table')) {
        $macTbl = $blocks['show mac-address-table']
    } else {
        $macTbl = @()
        foreach ($k in $blocks.Keys) {
            if ($k -match '^show\s+mac[- ]address[- ]table') { $macTbl = $blocks[$k]; break }
        }
    }
    # Authentication sessions may be singular ("show authentication session")
    # or plural ("show authentication sessions"), and devices may append
    # additional qualifiers such as "interface" or "summary".  Try exact
    # matches for the plural and singular forms first, then fall back to
    # any key that begins with "show authentication session" or
    # "show authentication sessions".  The regex
    # "^show\s+authentication\s+sessions?" matches both forms and will
    # capture extended commands like "show authentication sessions interface".
    if ($blocks.ContainsKey('show authentication sessions')) {
        $authSes = $blocks['show authentication sessions']
    } elseif ($blocks.ContainsKey('show authentication session')) {
        $authSes = $blocks['show authentication session']
    } else {
        $authSes = @()
        # First attempt to match keys that begin with "show authentication session[s]" (plural or singular)
        foreach ($k in $blocks.Keys) {
            if ($k -match '^show\s+authentication\s+sessions?') { $authSes = $blocks[$k]; break }
        }
        # If still not found, attempt to match abbreviated commands such as "show auth ses".
        if (-not $authSes -or $authSes.Count -eq 0) {
            foreach ($k in $blocks.Keys) {
                # This regex matches commands like "show auth ses", "show auth sess", "show auth se"
                # by looking for 'show', then any word starting with 'auth', then any word starting with 'se'.
                if ($k -match '^show\s+auth\w*\s+ses\w*') { $authSes = $blocks[$k]; break }
            }
        }
    }

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
            $macsByPort[$p]     = New-Object 'System.Collections.Generic.List[string]'
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
    $combinedList = New-Object 'System.Collections.Generic.List[object]'
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