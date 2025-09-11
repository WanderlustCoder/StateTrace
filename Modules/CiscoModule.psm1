
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
            if ($l -match 'Model Number\s+:\s+(\S+)')    { $model   = $matches[1] }
            elseif ($l -match 'Version\s+([\d\.]+)')     { $version = $matches[1] }
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
        # Note: compiled option is implied when using .new() with no options; passing
        # RegexOptions.Compiled explicitly would require different .NET versions.
        $reWs     = [regex]::new('\s+')

        foreach ($l in $Lines) {
            if ($reHeader.IsMatch($l)) { $parsing = $true; continue }
            if ($parsing) {
                if ($reBlank.IsMatch($l)) { break }
                # Split the line into at most 7 columns on whitespace.  Regex.Split
                # returns an array with a maximum length specified; the final
                # element contains the remainder of the string.
                $cols = $reWs.Split($l, 7)
                if ($cols.Count -ge 7) {
                    $raw = $cols[0]
                    [void]$res.Add([PSCustomObject]@{
                        RawPort = $raw
                        Port    = $raw
                        Name    = $cols[1]
                        Status  = $cols[2]
                        VLAN    = $cols[3]
                        Duplex  = $cols[4]
                        Speed   = $cols[5]
                        Type    = $cols[6]
                    })
                }
            }
        }
        return $res
    }

    function Get-MacTable {
        param([string[]]$Lines)
        # Use a strongly typed list to avoid O(n^2) growth when appending items.
        $list = New-Object 'System.Collections.Generic.List[object]'
        foreach ($l in $Lines) {
            if ($l -match '^\s*(\d+)\s+([0-9a-fA-F\.]+)\s+DYNAMIC\s+(\S+)$') {
                [void]$list.Add([PSCustomObject]@{ VLAN=$matches[1]; MAC=$matches[2]; Port=$matches[3] })
            }
        }
        return $list
    }

    function Get-Dot1xStatus {
        param([string[]]$Lines)
        # Accumulate dot1x status entries in a strongly typed list rather than
        $list = New-Object 'System.Collections.Generic.List[object]'
        $inSection=$false

        # Precompile patterns used repeatedly in the loop.  Precompiling
        # improves performance when processing large numbers of lines.
        $reHeader = [regex]::new('^Interface\s+MAC Address')
        $reBlank  = [regex]::new('^\s*$')
        $reWs     = [regex]::new('\s+')
        $reMac    = [regex]::new('^[0-9a-fA-F\.]+$')
        $reAuth   = [regex]::new('auth', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $reUnauth = [regex]::new('unauth|fail', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $reMode   = [regex]::new('dot1x|mab', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

        foreach ($l in $Lines) {
            if ($reHeader.IsMatch($l)) { $inSection=$true; continue }
            if (-not $inSection) { continue }
            if ($reBlank.IsMatch($l)) { break }
            $cols = $reWs.Split($l)
            if ($cols.Count -ge 6) {
                $iface  = $cols[0]
                $mac    = if ($reMac.IsMatch($cols[1])) { $cols[1] } else { '' }
                $method = $cols[2]
                # Join columns 4 through (Count-2) to reconstruct the status field.  Splitting on
                # whitespace may break phrases containing spaces (e.g., "auth-fail").  We preserve
                # the original semantics by joining these columns and trimming.
                $status = ($cols[4..($cols.Count-2)] -join ' ').Trim()
                # Determine authorization state based on the presence of keywords in the status.
                if ($reAuth.IsMatch($status) -and -not $reUnauth.IsMatch($status)) {
                    $authState = 'Authorized'
                } elseif ($reUnauth.IsMatch($status)) {
                    $authState = 'Unauthorized'
                } else {
                    $authState = 'Unknown'
                }
                # Determine the authentication mode based on the method column.
                $authMode  = if ($reMode.IsMatch($method)) { $method } else { 'unknown' }
                [void]$list.Add([PSCustomObject]@{ Interface=$iface; MAC=$mac; Status=$status; AuthState=$authState; AuthMode=$authMode; SessionID=$cols[-1] })
            }
        }
        return $list
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
    $runCfg    = $blocks['show running-config']
    $verBlk    = $blocks['show version']
    $intStat   = $blocks['show interface status']
    $macTbl    = $blocks['show mac address-table']
    $authSes   = $blocks['show authentication sessions']

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
        $name     = if ($cfgEntry -and $cfgEntry.Description) { $cfgEntry.Description } else { $raw }

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