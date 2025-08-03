<#
.SYNOPSIS
    Parses Cisco show command outputs into structured data.
#>
function Get-CiscoDeviceFacts {
    [CmdletBinding()]
    param (
        [string[]]$Lines
    )

    #-----------------------------------------
    # Extract each "show ..." output as a separate block
    function Get-ShowCommandBlocks {
        param([string[]]$Lines)
        $blocks     = @{}
        $currentCmd = ''
        $buffer     = @()
        $recording  = $false

        foreach ($line in $Lines) {
            if ($line -match '^\S+#\s*(show .+)$') {
                if ($recording -and $currentCmd) { $blocks[$currentCmd] = $buffer }
                $currentCmd = $matches[1].Trim().ToLower()
                $buffer     = @()
                $recording  = $true
                continue
            }
            if ($recording -and $line -match '^\S+#') {
                $blocks[$currentCmd] = $buffer
                $currentCmd = ''; $buffer = @(); $recording = $false
                continue
            }
            if ($recording) { $buffer += $line }
        }
        if ($recording -and $currentCmd) { $blocks[$currentCmd] = $buffer }
        return $blocks
    }

    #-----------------------------------------
    function Get-Hostname      { param([string[]]$Lines) foreach ($l in $Lines) { if ($l -match '^hostname\s+(.+)$') { return $matches[1] } }; return 'Unknown' }
    function Get-ModelAndVersion { param([string[]]$Lines)
        $model='Unknown'; $version='Unknown'
        foreach ($l in $Lines) {
            if ($l -match 'Model Number\s+:\s+(\S+)')    { $model   = $matches[1] }
            elseif ($l -match 'Version\s+([\d\.]+)')     { $version = $matches[1] }
        }
        return @($model,$version)
    }
    function Get-Uptime        { param([string[]]$Lines) foreach ($l in $Lines) { if ($l -match 'uptime is (.+)$') { return $matches[1].Trim() } }; return 'Unknown' }
    function Get-Location      { param([string[]]$Lines) foreach ($l in $Lines) { if ($l -match 'snmp-server location\s+(.+)$') { return $matches[1].Trim() } }; return 'Unspecified' }

    function Get-InterfaceConfigs {
        param([string[]]$Lines)
        $ht = @{}
        for ($i=0; $i -lt $Lines.Count; $i++) {
            $l = $Lines[$i]
            if ($l -match '^interface\s+(\S+)') {
                $fullName = $matches[1]
                $block    = @($l)
                $desc     = ''
                $j        = $i+1
                while ($j -lt $Lines.Count -and $Lines[$j] -notmatch '^interface' -and $Lines[$j] -notmatch '^!') {
                    $block += $Lines[$j]
                    if ($Lines[$j] -match '^\s*description\s+(.+)$') { $desc=$matches[1].Trim() }
                    $j++
                }
                $cfgObj = @{ Config=$block -join "`r`n"; Description=$desc }
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
        $blk=@()
        foreach ($line in $Lines) {
            $trim = $line.Trim()
            if ($trim -match '^(authentication|dot1x|mab|reauthentication)\b') {
                $blk += $trim
            }
        }
        return $blk -join "`r`n"
    }

    function Get-InterfacesStatus {
        param([string[]]$Lines)
        $res=@(); $parsing=$false
        foreach ($l in $Lines) {
            if ($l -match '^Port\s+Name\s+Status') { $parsing=$true; continue }
            if ($parsing) {
                if ($l -match '^\s*$') { break }
                $cols = $l -split '\s+',7
                if ($cols.Count -ge 7) {
                    $raw = $cols[0]
                    $res += [PSCustomObject]@{
                        RawPort=$raw; Port=$raw; Name=$cols[1]; Status=$cols[2];
                        VLAN=$cols[3]; Duplex=$cols[4]; Speed=$cols[5]; Type=$cols[6]
                    }
                }
            }
        }
        return $res
    }

    function Get-MacTable {
        param([string[]]$Lines)
        $list=@()
        foreach ($l in $Lines) {
            if ($l -match '^\s*(\d+)\s+([0-9a-fA-F\.]+)\s+DYNAMIC\s+(\S+)$') {
                $list += [PSCustomObject]@{ VLAN=$matches[1]; MAC=$matches[2]; Port=$matches[3] }
            }
        }
        return $list
    }

    function Get-Dot1xStatus {
        param([string[]]$Lines)
        $list=@(); $inSection=$false
        foreach ($l in $Lines) {
            if ($l -match '^Interface\s+MAC Address') { $inSection=$true; continue }
            if (-not $inSection) { continue }
            if ($l -match '^\s*$') { break }
            $cols = $l -split '\s+'
            if ($cols.Count -ge 6) {
                $iface  = $cols[0]
                $mac    = if ($cols[1] -match '^[0-9a-f\.]+$') { $cols[1] } else { '' }
                $method = $cols[2]
                $status = ($cols[4..($cols.Count-2)] -join ' ').Trim()
                $authState = if ($status -match 'success') {'Authorized'} elseif ($status -match 'failed') {'Unauthorized'} else {'Unknown'}
                $authMode  = if ($method -match 'dot1x|mab') { $method } else { 'unknown' }
                $list += [PSCustomObject]@{ Interface=$iface; MAC=$mac; Status=$status; AuthState=$authState; AuthMode=$authMode; SessionID=$cols[-1] }
            }
        }
        return $list
    }

    # Parse show spanning-tree output into a collection of summary rows.  Each
    # row corresponds to a VLAN or MST instance and captures the root switch
    # MAC address and the local port used to reach the root.  This is a
    # simplistic parser that looks for headers like "VLANxxxx" or
    # "MST<number>" to identify the section, then grabs the first "Address"
    # line (for root switch) and "Root port" line (for root port) that
    # follows.  Additional fields (such as role or upstream device) can be
    # added later.
    function Parse-SpanningTree {
        param([string[]]$SpanLines)
        $entries = @()
        $current = ''
        $rootSwitch = ''
        $rootPort = ''
        foreach ($ln in $SpanLines) {
            $line = $ln.Trim()
            # Identify new section headers.  Cisco typically prints
            # "VLAN0001" or "MST0".  Use a case-insensitive match.
            if ($line -match '^(VLAN\d+|MST\d+)') {
                # If we have an existing context, flush it before starting a
                # new one.
                if ($current -ne '') {
                    $entries += [PSCustomObject]@{
                        VLAN      = $current
                        RootSwitch= $rootSwitch
                        RootPort  = $rootPort
                        Role      = ''
                        Upstream  = ''
                    }
                }
                $current = $matches[1]
                $rootSwitch = ''
                $rootPort = ''
                continue
            }
            # Capture root switch MAC from "Address" line (under Root ID)
            if (-not $rootSwitch -and $line -match 'Address\s+(\S+)') {
                $rootSwitch = $matches[1]
                continue
            }
            # Capture root port from a line like "Root port Fa0/1, cost 4".
            if (-not $rootPort -and $line -match 'Root port\s+(\S+),') {
                $rootPort = $matches[1]
                continue
            }
        }
        # Flush last entry
        if ($current -ne '') {
            $entries += [PSCustomObject]@{
                VLAN      = $current
                RootSwitch= $rootSwitch
                RootPort  = $rootPort
                Role      = ''
                Upstream  = ''
            }
        }
        return $entries
    }

    #
    # === Updated helper: Detect MAB via the standalone 'mab' line ===
    #
    function Get-PortAuthTemplates {
        param([hashtable]$Configs)

        $result   = @{}
        # list of commands considered part of dual-auth (for compliance)
        $required = @(
            'authentication event fail action next-method',
            'authentication order mab dot1x',
            'authentication priority dot1x mab',
            'authentication port-control auto',
            'dot1x timeout quiet-period 90',
            'dot1x timeout tx-period 5'
        )

        foreach ($key in $Configs.Keys) {
            # normalize to lower-case trimmed lines
            $lines = $Configs[$key].Config -split "`r?`n" | ForEach-Object { $_.Trim().ToLower() }

            # Was originally only checking the 'authentication order ... mab' line:
            # now detect any standalone 'mab'
            $hasDot1x = $lines -contains 'dot1x pae authenticator'
            $hasMab   = $lines -contains 'mab'

            if ($hasDot1x -and $hasMab) {
                # dual (flexible) auth
                $missing = @()
                foreach ($cmd in $required) {
                    if (-not ($lines -contains $cmd)) { $missing += $cmd }
                }
                $result[$key] = @{ Template='flexible'; MissingCommands=$missing }
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

    $hostname  = Get-Hostname      -Lines $runCfg
    $modelVer  = Get-ModelAndVersion -Lines $verBlk
    $uptime    = Get-Uptime        -Lines $verBlk
    $location  = Get-Location      -Lines $runCfg
    $configs   = Get-InterfaceConfigs -Lines $runCfg
    $status    = Get-InterfacesStatus  -Lines $intStat
    $macs      = Get-MacTable         -Lines $macTbl
    $auth      = Get-Dot1xStatus      -Lines $authSes
    $authTemplates = Get-PortAuthTemplates -Configs $configs

    $authDefaultVLAN = Get-AuthDefaultVLAN -Lines $runCfg
    $authBlock       = Get-AuthBlock       -Lines $runCfg

    $combined = @()
    foreach ($iface in $status) {
        $raw     = $iface.RawPort
        $cfgEntry= $configs[$raw]
        $cfgText = if ($cfgEntry) { $cfgEntry.Config } else { '' }
        $name    = if ($cfgEntry -and $cfgEntry.Description) { $cfgEntry.Description } else { $raw }
        $macList = ($macs | Where-Object Port -eq $raw | ForEach-Object MAC) -join ','
        $authRow = $auth | Where-Object Interface -ieq $raw | Select-Object -First 1
        $macRow  = $macs | Where-Object Port -eq $raw | Select-Object -First 1

        $interfaceMac = if ($macRow) { $macRow.MAC } else { '' }
        $templateInfo = $authTemplates[$raw]

        $combined += [PSCustomObject]@{
            Port            = $raw
            Name            = $name
            Status          = $iface.Status
            VLAN            = $iface.VLAN
            Duplex          = $iface.Duplex
            Speed           = $iface.Speed
            Type            = $iface.Type
            InterfaceMAC    = $interfaceMac
            LearnedMACs     = $macList
            AuthState       = if ($authRow) { $authRow.AuthState } else { 'Unknown' }
            AuthMode        = if ($authRow) { $authRow.AuthMode }  else { 'unknown' }
            AuthClientMAC   = if ($authRow) { $authRow.MAC }       else { '' }
            AuthVLAN        = if ($macRow)   { $macRow.VLAN }      else { '' }
            Config          = $cfgText
            AuthTemplate    = $templateInfo.Template
            MissingAuthCmds = $templateInfo.MissingCommands -join ','
        }
    }

    # Gather spanning tree information if the log included a 'show spanning-tree'
    # section.  Some devices may use the abbreviated command 'show span'; try
    # both keys.  If no output is found, the SpanInfo collection will be
    # empty.  When present, parse the output into a list of records.
    $spanLines = @()
    if ($blocks.ContainsKey('show spanning-tree')) {
        $spanLines = $blocks['show spanning-tree']
    } elseif ($blocks.ContainsKey('show span')) {
        $spanLines = $blocks['show span']
    }
    $spanInfo = if ($spanLines.Count -gt 0) { Parse-SpanningTree -SpanLines $spanLines } else { @() }

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
