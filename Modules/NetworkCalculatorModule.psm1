Set-StrictMode -Version Latest

#region IP Address Conversion Functions

<#
.SYNOPSIS
    Converts an IP address string to a 32-bit unsigned integer.
#>
function Convert-IPToUInt32 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$IP
    )

    $octets = $IP.Split('.')
    if ($octets.Count -ne 4) {
        throw "Invalid IP address format: $IP"
    }

    [uint32]$result = 0
    for ($i = 0; $i -lt 4; $i++) {
        $octet = [int]$octets[$i]
        if ($octet -lt 0 -or $octet -gt 255) {
            throw "Invalid octet value in IP address: $IP"
        }
        $result = $result -bor ([uint32]$octet -shl (24 - ($i * 8)))
    }

    return $result
}

<#
.SYNOPSIS
    Converts a 32-bit unsigned integer to an IP address string.
#>
function Convert-UInt32ToIP {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [uint32]$Value
    )

    $o1 = [int](($Value -shr 24) -band 255)
    $o2 = [int](($Value -shr 16) -band 255)
    $o3 = [int](($Value -shr 8) -band 255)
    $o4 = [int]($Value -band 255)

    return "$o1.$o2.$o3.$o4"
}

<#
.SYNOPSIS
    Converts a CIDR prefix length to a subnet mask.
#>
function Convert-CIDRToMask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$CIDR
    )

    if ($CIDR -lt 0 -or $CIDR -gt 32) {
        throw "CIDR must be between 0 and 32. Got: $CIDR"
    }

    if ($CIDR -eq 0) {
        return '0.0.0.0'
    }

    [uint32]$mask = [uint32]::MaxValue -shl (32 - $CIDR)
    return Convert-UInt32ToIP $mask
}

<#
.SYNOPSIS
    Converts a subnet mask to a CIDR prefix length.
#>
function Convert-MaskToCIDR {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Mask
    )

    $maskInt = Convert-IPToUInt32 $Mask

    # Validate it's a valid subnet mask (contiguous 1s followed by 0s)
    $foundZero = $false
    $cidr = 0

    for ($i = 31; $i -ge 0; $i--) {
        $bit = ($maskInt -shr $i) -band 1
        if ($bit -eq 1) {
            if ($foundZero) {
                throw "Invalid subnet mask: $Mask (non-contiguous bits)"
            }
            $cidr++
        } else {
            $foundZero = $true
        }
    }

    return $cidr
}

<#
.SYNOPSIS
    Converts an IP address to binary notation with dots.
#>
function Convert-IPToBinary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$IP
    )

    $octets = $IP.Split('.')
    $binaryOctets = @()

    foreach ($octet in $octets) {
        $value = [int]$octet
        $binary = [Convert]::ToString($value, 2).PadLeft(8, '0')
        $binaryOctets += $binary
    }

    return $binaryOctets -join '.'
}

<#
.SYNOPSIS
    Converts a binary IP notation to dotted decimal.
#>
function Convert-BinaryToIP {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Binary
    )

    $binaryOctets = $Binary.Split('.')
    $octets = @()

    foreach ($binOctet in $binaryOctets) {
        $octets += [Convert]::ToInt32($binOctet, 2)
    }

    return $octets -join '.'
}

<#
.SYNOPSIS
    Converts an IP address to its decimal representation.
#>
function Convert-IPToDecimal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$IP
    )

    return Convert-IPToUInt32 $IP
}

<#
.SYNOPSIS
    Converts a decimal value to an IP address.
#>
function Convert-DecimalToIP {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [uint32]$Decimal
    )

    return Convert-UInt32ToIP $Decimal
}

#endregion

#region IP Address Validation Functions

<#
.SYNOPSIS
    Validates an IPv4 address.
#>
function Test-IPv4Address {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$IP
    )

    if ([string]::IsNullOrWhiteSpace($IP)) {
        return $false
    }

    $octets = $IP.Split('.')
    if ($octets.Count -ne 4) {
        return $false
    }

    foreach ($octet in $octets) {
        $value = 0
        if (-not [int]::TryParse($octet, [ref]$value)) {
            return $false
        }
        if ($value -lt 0 -or $value -gt 255) {
            return $false
        }
    }

    return $true
}

<#
.SYNOPSIS
    Tests if an IP address is in RFC1918 private address space.
#>
function Test-PrivateIP {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$IP
    )

    if (-not (Test-IPv4Address $IP)) {
        return $false
    }

    $ipInt = Convert-IPToUInt32 $IP

    # 10.0.0.0/8
    $net10 = Convert-IPToUInt32 '10.0.0.0'
    $mask10 = Convert-IPToUInt32 '255.0.0.0'
    if (($ipInt -band $mask10) -eq $net10) {
        return $true
    }

    # 172.16.0.0/12
    $net172 = Convert-IPToUInt32 '172.16.0.0'
    $mask172 = Convert-IPToUInt32 '255.240.0.0'
    if (($ipInt -band $mask172) -eq $net172) {
        return $true
    }

    # 192.168.0.0/16
    $net192 = Convert-IPToUInt32 '192.168.0.0'
    $mask192 = Convert-IPToUInt32 '255.255.0.0'
    if (($ipInt -band $mask192) -eq $net192) {
        return $true
    }

    return $false
}

<#
.SYNOPSIS
    Tests if an IP address is a link-local address (169.254.0.0/16).
#>
function Test-LinkLocalIP {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$IP
    )

    if (-not (Test-IPv4Address $IP)) {
        return $false
    }

    $ipInt = Convert-IPToUInt32 $IP
    $netLL = Convert-IPToUInt32 '169.254.0.0'
    $maskLL = Convert-IPToUInt32 '255.255.0.0'

    return (($ipInt -band $maskLL) -eq $netLL)
}

<#
.SYNOPSIS
    Tests if an IP address is a loopback address (127.0.0.0/8).
#>
function Test-LoopbackIP {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$IP
    )

    if (-not (Test-IPv4Address $IP)) {
        return $false
    }

    $ipInt = Convert-IPToUInt32 $IP
    $netLo = Convert-IPToUInt32 '127.0.0.0'
    $maskLo = Convert-IPToUInt32 '255.0.0.0'

    return (($ipInt -band $maskLo) -eq $netLo)
}

#endregion

#region Subnet Calculator Functions

<#
.SYNOPSIS
    Calculates comprehensive subnet information.

.DESCRIPTION
    Returns network address, broadcast address, subnet mask, wildcard mask,
    usable range, and host count for a given network.

.PARAMETER Network
    The network address or any IP within the network.

.PARAMETER CIDR
    The CIDR prefix length (0-32).

.OUTPUTS
    PSCustomObject with subnet details.
#>
function Get-SubnetInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Network,

        [Parameter(Mandatory=$true)]
        [int]$CIDR
    )

    if ($CIDR -lt 0 -or $CIDR -gt 32) {
        throw "CIDR must be between 0 and 32"
    }

    $ipInt = Convert-IPToUInt32 $Network

    # Calculate mask
    [uint32]$maskInt = if ($CIDR -eq 0) { 0 } else { [uint32]::MaxValue -shl (32 - $CIDR) }
    [uint32]$wildcardInt = -bnot $maskInt

    # Calculate network and broadcast
    [uint32]$networkInt = $ipInt -band $maskInt
    [uint32]$broadcastInt = $networkInt -bor $wildcardInt

    # Calculate usable range
    $totalAddresses = [Math]::Pow(2, (32 - $CIDR))

    if ($CIDR -eq 32) {
        # /32 - single host
        $firstUsable = $networkInt
        $lastUsable = $networkInt
        $totalHosts = 1
    } elseif ($CIDR -eq 31) {
        # /31 - point-to-point (RFC 3021)
        $firstUsable = $networkInt
        $lastUsable = $broadcastInt
        $totalHosts = 2
    } else {
        # Standard subnet
        $firstUsable = $networkInt + 1
        $lastUsable = $broadcastInt - 1
        $totalHosts = [int]$totalAddresses - 2
    }

    return [PSCustomObject]@{
        NetworkAddress = Convert-UInt32ToIP $networkInt
        BroadcastAddress = Convert-UInt32ToIP $broadcastInt
        SubnetMask = Convert-CIDRToMask $CIDR
        WildcardMask = Convert-UInt32ToIP $wildcardInt
        CIDR = $CIDR
        FirstUsable = Convert-UInt32ToIP $firstUsable
        LastUsable = Convert-UInt32ToIP $lastUsable
        TotalHosts = $totalHosts
        TotalAddresses = [int]$totalAddresses
    }
}

<#
.SYNOPSIS
    Tests if an IP address is within a subnet.
#>
function Test-IPInSubnet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$IP,

        [Parameter(Mandatory=$true)]
        [string]$Network
    )

    # Parse network/CIDR
    if ($Network -match '^(.+)/(\d+)$') {
        $netAddr = $Matches[1]
        $cidr = [int]$Matches[2]
    } else {
        throw "Network must be in CIDR notation (e.g., 192.168.1.0/24)"
    }

    $ipInt = Convert-IPToUInt32 $IP
    $netInt = Convert-IPToUInt32 $netAddr

    [uint32]$maskInt = if ($cidr -eq 0) { 0 } else { [uint32]::MaxValue -shl (32 - $cidr) }

    $networkAddr = $netInt -band $maskInt
    $ipNetwork = $ipInt -band $maskInt

    return ($ipNetwork -eq $networkAddr)
}

<#
.SYNOPSIS
    Splits a subnet into smaller subnets.
#>
function Split-Subnet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Network,

        [Parameter(Mandatory=$true)]
        [int]$NewPrefix
    )

    # Parse network/CIDR
    if ($Network -match '^(.+)/(\d+)$') {
        $netAddr = $Matches[1]
        $currentPrefix = [int]$Matches[2]
    } else {
        throw "Network must be in CIDR notation (e.g., 192.168.1.0/24)"
    }

    if ($NewPrefix -le $currentPrefix) {
        throw "New prefix ($NewPrefix) must be larger than current prefix ($currentPrefix)"
    }

    if ($NewPrefix -gt 32) {
        throw "New prefix cannot exceed 32"
    }

    $numSubnets = [Math]::Pow(2, ($NewPrefix - $currentPrefix))
    $subnetSize = [Math]::Pow(2, (32 - $NewPrefix))

    $baseInfo = Get-SubnetInfo -Network $netAddr -CIDR $currentPrefix
    $baseInt = Convert-IPToUInt32 $baseInfo.NetworkAddress

    $results = @()
    for ($i = 0; $i -lt $numSubnets; $i++) {
        $subnetInt = $baseInt + ($i * $subnetSize)
        $results += Get-SubnetInfo -Network (Convert-UInt32ToIP $subnetInt) -CIDR $NewPrefix
    }

    return $results
}

<#
.SYNOPSIS
    Merges contiguous subnets into a supernet.
#>
function Merge-Subnets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Subnets
    )

    if ($Subnets.Count -lt 2) {
        throw "At least two subnets required for merging"
    }

    # Parse all subnets
    $parsed = @()
    foreach ($subnet in $Subnets) {
        if ($subnet -match '^(.+)/(\d+)$') {
            $info = Get-SubnetInfo -Network $Matches[1] -CIDR ([int]$Matches[2])
            $parsed += [PSCustomObject]@{
                NetworkInt = Convert-IPToUInt32 $info.NetworkAddress
                CIDR = [int]$Matches[2]
                Info = $info
            }
        } else {
            throw "Invalid subnet format: $subnet"
        }
    }

    # Check all have same prefix
    $prefix = $parsed[0].CIDR
    $differentPrefix = @($parsed | Where-Object { $_.CIDR -ne $prefix })
    if ($differentPrefix.Count -gt 0) {
        throw "All subnets must have the same prefix length for merging"
    }

    # Sort by network address
    $sorted = @($parsed | Sort-Object NetworkInt)

    # Check contiguity
    $subnetSize = [Math]::Pow(2, (32 - $prefix))
    for ($i = 1; $i -lt $sorted.Count; $i++) {
        $expectedNext = $sorted[$i-1].NetworkInt + $subnetSize
        if ($sorted[$i].NetworkInt -ne $expectedNext) {
            throw "Subnets are not contiguous"
        }
    }

    # Calculate new prefix
    $numSubnets = $sorted.Count
    $bitsNeeded = [Math]::Ceiling([Math]::Log($numSubnets, 2))
    $newPrefix = $prefix - $bitsNeeded

    # Verify it's a power of 2 count
    if ([Math]::Pow(2, $bitsNeeded) -ne $numSubnets) {
        throw "Number of subnets ($numSubnets) must be a power of 2"
    }

    return Get-SubnetInfo -Network (Convert-UInt32ToIP $sorted[0].NetworkInt) -CIDR $newPrefix
}

#endregion

#region VLAN Calculator Functions

<#
.SYNOPSIS
    Expands a VLAN range string into an array of VLAN IDs.
#>
function Expand-VLANRange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Range
    )

    $vlans = [System.Collections.Generic.List[int]]::new()
    $parts = $Range -split ','

    foreach ($part in $parts) {
        $part = $part.Trim()

        if ($part -match '^(\d+)-(\d+)$') {
            $start = [int]$Matches[1]
            $end = [int]$Matches[2]

            if ($start -lt 1 -or $end -gt 4094) {
                throw "VLAN ID must be between 1 and 4094"
            }
            if ($start -gt $end) {
                throw "Invalid range: start ($start) > end ($end)"
            }

            for ($v = $start; $v -le $end; $v++) {
                if (-not $vlans.Contains($v)) {
                    $vlans.Add($v)
                }
            }
        } elseif ($part -match '^\d+$') {
            $vlan = [int]$part
            if ($vlan -lt 1 -or $vlan -gt 4094) {
                throw "VLAN ID must be between 1 and 4094"
            }
            if (-not $vlans.Contains($vlan)) {
                $vlans.Add($vlan)
            }
        } else {
            throw "Invalid VLAN range format: $part"
        }
    }

    return ($vlans | Sort-Object)
}

<#
.SYNOPSIS
    Compresses a list of VLANs into a compact range notation.
#>
function Compress-VLANRange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int[]]$VLANs
    )

    if ($VLANs.Count -eq 0) {
        return ''
    }

    $sorted = @($VLANs | Sort-Object -Unique)
    $ranges = [System.Collections.Generic.List[string]]::new()

    $rangeStart = $sorted[0]
    $rangeEnd = $sorted[0]

    for ($i = 1; $i -lt $sorted.Count; $i++) {
        if ($sorted[$i] -eq $rangeEnd + 1) {
            $rangeEnd = $sorted[$i]
        } else {
            if ($rangeStart -eq $rangeEnd) {
                $ranges.Add("$rangeStart")
            } else {
                $ranges.Add("$rangeStart-$rangeEnd")
            }
            $rangeStart = $sorted[$i]
            $rangeEnd = $sorted[$i]
        }
    }

    # Add final range
    if ($rangeStart -eq $rangeEnd) {
        $ranges.Add("$rangeStart")
    } else {
        $ranges.Add("$rangeStart-$rangeEnd")
    }

    return $ranges -join ','
}

#endregion

#region Bandwidth Calculator Functions

<#
.SYNOPSIS
    Parses a size string (e.g., "1GB", "500MB") to bytes.
#>
function ConvertTo-Bytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Size
    )

    if ($Size -match '^([\d.]+)\s*(B|KB|MB|GB|TB)$') {
        $value = [double]$Matches[1]
        $unit = $Matches[2]

        switch ($unit) {
            'B'  { return [long]$value }
            'KB' { return [long]($value * 1024) }
            'MB' { return [long]($value * 1024 * 1024) }
            'GB' { return [long]($value * 1024 * 1024 * 1024) }
            'TB' { return [long]($value * 1024 * 1024 * 1024 * 1024) }
        }
    }

    throw "Invalid size format: $Size (use B, KB, MB, GB, or TB)"
}

<#
.SYNOPSIS
    Parses a bandwidth string (e.g., "1Gbps", "100Mbps") to bits per second.
#>
function ConvertTo-BitsPerSecond {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Bandwidth
    )

    if ($Bandwidth -match '^([\d.]+)\s*(bps|Kbps|Mbps|Gbps|Tbps)$') {
        $value = [double]$Matches[1]
        $unit = $Matches[2]

        switch ($unit) {
            'bps'  { return [long]$value }
            'Kbps' { return [long]($value * 1000) }
            'Mbps' { return [long]($value * 1000000) }
            'Gbps' { return [long]($value * 1000000000) }
            'Tbps' { return [long]($value * 1000000000000) }
        }
    }

    throw "Invalid bandwidth format: $Bandwidth (use bps, Kbps, Mbps, Gbps, or Tbps)"
}

<#
.SYNOPSIS
    Calculates transfer time for a given data size and bandwidth.
#>
function Get-TransferTime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Size,

        [Parameter(Mandatory=$true)]
        [string]$Bandwidth,

        [int]$Utilization = 100
    )

    if ($Utilization -le 0 -or $Utilization -gt 100) {
        throw "Utilization must be between 1 and 100"
    }

    $bytes = ConvertTo-Bytes $Size
    $bits = $bytes * 8
    $bps = ConvertTo-BitsPerSecond $Bandwidth
    $effectiveBps = $bps * ($Utilization / 100)

    $seconds = $bits / $effectiveBps

    return [PSCustomObject]@{
        Seconds = [Math]::Round($seconds, 2)
        Minutes = [Math]::Round($seconds / 60, 2)
        Hours = [Math]::Round($seconds / 3600, 2)
        Formatted = if ($seconds -lt 60) { "{0:N2} seconds" -f $seconds }
                    elseif ($seconds -lt 3600) { "{0:N2} minutes" -f ($seconds / 60) }
                    else { "{0:N2} hours" -f ($seconds / 3600) }
    }
}

<#
.SYNOPSIS
    Calculates required bandwidth to transfer data in a given time.
#>
function Get-RequiredBandwidth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Size,

        [Parameter(Mandatory=$true)]
        [double]$TimeSeconds
    )

    if ($TimeSeconds -le 0) {
        throw "Time must be greater than 0"
    }

    $bytes = ConvertTo-Bytes $Size
    $bits = $bytes * 8
    $bps = $bits / $TimeSeconds

    return [PSCustomObject]@{
        Bps = [long]$bps
        Kbps = [Math]::Round($bps / 1000, 2)
        Mbps = [Math]::Round($bps / 1000000, 2)
        Gbps = [Math]::Round($bps / 1000000000, 4)
    }
}

<#
.SYNOPSIS
    Converts bandwidth between different units.
#>
function Convert-Bandwidth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [double]$Value,

        [Parameter(Mandatory=$true)]
        [ValidateSet('bps', 'Kbps', 'Mbps', 'Gbps', 'Bps', 'KBps', 'MBps', 'GBps')]
        [string]$FromUnit,

        [Parameter(Mandatory=$true)]
        [ValidateSet('bps', 'Kbps', 'Mbps', 'Gbps', 'Bps', 'KBps', 'MBps', 'GBps')]
        [string]$ToUnit
    )

    # Convert to bps first (use -casesensitive to distinguish Mbps from MBps)
    [double]$bps = 0
    switch -casesensitive ($FromUnit) {
        'bps'  { $bps = $Value }
        'Kbps' { $bps = $Value * 1000 }
        'Mbps' { $bps = $Value * 1000000 }
        'Gbps' { $bps = $Value * 1000000000 }
        'Bps'  { $bps = $Value * 8 }
        'KBps' { $bps = $Value * 8 * 1024 }
        'MBps' { $bps = $Value * 8 * 1024 * 1024 }
        'GBps' { $bps = $Value * 8 * 1024 * 1024 * 1024 }
    }

    # Convert from bps to target
    [double]$result = 0
    switch -casesensitive ($ToUnit) {
        'bps'  { $result = $bps }
        'Kbps' { $result = $bps / 1000 }
        'Mbps' { $result = $bps / 1000000 }
        'Gbps' { $result = $bps / 1000000000 }
        'Bps'  { $result = $bps / 8 }
        'KBps' { $result = $bps / 8 / 1024 }
        'MBps' { $result = $bps / 8 / 1024 / 1024 }
        'GBps' { $result = $bps / 8 / 1024 / 1024 / 1024 }
    }

    return $result
}

#endregion

#region Protocol Timer Functions

<#
.SYNOPSIS
    Validates STP timer relationships.
#>
function Test-STPTimers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$Hello,

        [Parameter(Mandatory=$true)]
        [int]$Forward,

        [Parameter(Mandatory=$true)]
        [int]$MaxAge
    )

    $issues = @()

    # Rule: MaxAge >= 2 * (Hello + 1)
    $minMaxAge = 2 * ($Hello + 1)
    if ($MaxAge -lt $minMaxAge) {
        $issues += "MaxAge ($MaxAge) must be >= 2*(Hello+1) = $minMaxAge"
    }

    # Rule: MaxAge <= 2 * (Forward - 1)
    $maxMaxAge = 2 * ($Forward - 1)
    if ($MaxAge -gt $maxMaxAge) {
        $issues += "MaxAge ($MaxAge) must be <= 2*(Forward-1) = $maxMaxAge"
    }

    return [PSCustomObject]@{
        Valid = ($issues.Count -eq 0)
        Reason = if ($issues.Count -gt 0) { $issues -join '; ' } else { $null }
        Hello = $Hello
        Forward = $Forward
        MaxAge = $MaxAge
    }
}

<#
.SYNOPSIS
    Calculates STP convergence time.
#>
function Get-STPConvergenceTime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$Forward,

        [Parameter(Mandatory=$true)]
        [int]$MaxAge
    )

    # Worst case: MaxAge + 2*Forward (listening + learning)
    $worstCase = $MaxAge + (2 * $Forward)

    return [PSCustomObject]@{
        WorstCase = $worstCase
        Description = "MaxAge ($MaxAge) + 2*Forward ($($Forward*2)) = $worstCase seconds"
    }
}

<#
.SYNOPSIS
    Validates OSPF timer relationships.
#>
function Test-OSPFTimers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$Hello,

        [Parameter(Mandatory=$true)]
        [int]$Dead
    )

    $warning = $null

    # Standard relationship is Dead = 4 * Hello
    $expectedDead = 4 * $Hello
    if ($Dead -ne $expectedDead) {
        $warning = "Non-standard Dead interval: expected $expectedDead (4*Hello), got $Dead"
    }

    # Dead must be > Hello
    $valid = $Dead -gt $Hello

    return [PSCustomObject]@{
        Valid = $valid
        Warning = $warning
        Hello = $Hello
        Dead = $Dead
        Reason = if (-not $valid) { "Dead interval must be greater than Hello interval" } else { $null }
    }
}

#endregion

#region Well-Known Ports Reference

<#
.SYNOPSIS
    Returns well-known port information.
#>
function Get-WellKnownPorts {
    [CmdletBinding()]
    param(
        [string]$Search
    )

    $ports = @(
        [PSCustomObject]@{ Port = 20; Protocol = 'TCP'; Service = 'FTP Data' }
        [PSCustomObject]@{ Port = 21; Protocol = 'TCP'; Service = 'FTP Control' }
        [PSCustomObject]@{ Port = 22; Protocol = 'TCP'; Service = 'SSH' }
        [PSCustomObject]@{ Port = 23; Protocol = 'TCP'; Service = 'Telnet' }
        [PSCustomObject]@{ Port = 25; Protocol = 'TCP'; Service = 'SMTP' }
        [PSCustomObject]@{ Port = 53; Protocol = 'TCP/UDP'; Service = 'DNS' }
        [PSCustomObject]@{ Port = 67; Protocol = 'UDP'; Service = 'DHCP Server' }
        [PSCustomObject]@{ Port = 68; Protocol = 'UDP'; Service = 'DHCP Client' }
        [PSCustomObject]@{ Port = 69; Protocol = 'UDP'; Service = 'TFTP' }
        [PSCustomObject]@{ Port = 80; Protocol = 'TCP'; Service = 'HTTP' }
        [PSCustomObject]@{ Port = 110; Protocol = 'TCP'; Service = 'POP3' }
        [PSCustomObject]@{ Port = 123; Protocol = 'UDP'; Service = 'NTP' }
        [PSCustomObject]@{ Port = 143; Protocol = 'TCP'; Service = 'IMAP' }
        [PSCustomObject]@{ Port = 161; Protocol = 'UDP'; Service = 'SNMP' }
        [PSCustomObject]@{ Port = 162; Protocol = 'UDP'; Service = 'SNMP Trap' }
        [PSCustomObject]@{ Port = 179; Protocol = 'TCP'; Service = 'BGP' }
        [PSCustomObject]@{ Port = 389; Protocol = 'TCP'; Service = 'LDAP' }
        [PSCustomObject]@{ Port = 443; Protocol = 'TCP'; Service = 'HTTPS' }
        [PSCustomObject]@{ Port = 445; Protocol = 'TCP'; Service = 'SMB' }
        [PSCustomObject]@{ Port = 514; Protocol = 'UDP'; Service = 'Syslog' }
        [PSCustomObject]@{ Port = 636; Protocol = 'TCP'; Service = 'LDAPS' }
        [PSCustomObject]@{ Port = 993; Protocol = 'TCP'; Service = 'IMAPS' }
        [PSCustomObject]@{ Port = 995; Protocol = 'TCP'; Service = 'POP3S' }
        [PSCustomObject]@{ Port = 1433; Protocol = 'TCP'; Service = 'SQL Server' }
        [PSCustomObject]@{ Port = 1521; Protocol = 'TCP'; Service = 'Oracle' }
        [PSCustomObject]@{ Port = 3306; Protocol = 'TCP'; Service = 'MySQL' }
        [PSCustomObject]@{ Port = 3389; Protocol = 'TCP'; Service = 'RDP' }
        [PSCustomObject]@{ Port = 5432; Protocol = 'TCP'; Service = 'PostgreSQL' }
        [PSCustomObject]@{ Port = 8080; Protocol = 'TCP'; Service = 'HTTP Alt' }
    )

    if ($Search) {
        $searchLower = $Search.ToLower()
        return $ports | Where-Object {
            $_.Service.ToLower().Contains($searchLower) -or
            $_.Port.ToString().Contains($Search) -or
            $_.Protocol.ToLower().Contains($searchLower)
        }
    }

    return $ports
}

#endregion

#region ACL Builder Functions

<#
.SYNOPSIS
    Creates a new ACL entry object.

.PARAMETER Action
    The action (permit or deny).

.PARAMETER Protocol
    The protocol (ip, tcp, udp, icmp).

.PARAMETER SourceNetwork
    The source network in CIDR notation or 'any'.

.PARAMETER DestinationNetwork
    The destination network in CIDR notation or 'any'.

.PARAMETER SourcePort
    Optional source port or port range for TCP/UDP.

.PARAMETER DestinationPort
    Optional destination port or port range for TCP/UDP.

.PARAMETER Sequence
    Optional sequence number for the entry.

.PARAMETER Remark
    Optional remark/comment for the entry.
#>
function New-ACLEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('permit', 'deny')]
        [string]$Action,

        [Parameter(Mandatory=$true)]
        [ValidateSet('ip', 'tcp', 'udp', 'icmp')]
        [string]$Protocol,

        [Parameter(Mandatory=$true)]
        [string]$SourceNetwork,

        [Parameter(Mandatory=$true)]
        [string]$DestinationNetwork,

        [string]$SourcePort,

        [string]$DestinationPort,

        [int]$Sequence = 0,

        [string]$Remark
    )

    # Validate source network
    $sourceWildcard = 'any'
    if ($SourceNetwork -ne 'any') {
        if ($SourceNetwork -match '^(.+)/(\d+)$') {
            $srcNet = $Matches[1]
            $srcCidr = [int]$Matches[2]
            if (-not (Test-IPv4Address $srcNet)) {
                throw "Invalid source IP address: $srcNet"
            }
            $srcInfo = Get-SubnetInfo -Network $srcNet -CIDR $srcCidr
            $sourceWildcard = @{
                Network = $srcInfo.NetworkAddress
                Wildcard = $srcInfo.WildcardMask
            }
        } elseif ($SourceNetwork -eq 'host') {
            throw "Use CIDR notation (e.g., 10.0.0.1/32) for host entries"
        } else {
            throw "Source network must be 'any' or in CIDR notation (e.g., 10.0.0.0/24)"
        }
    }

    # Validate destination network
    $destWildcard = 'any'
    if ($DestinationNetwork -ne 'any') {
        if ($DestinationNetwork -match '^(.+)/(\d+)$') {
            $dstNet = $Matches[1]
            $dstCidr = [int]$Matches[2]
            if (-not (Test-IPv4Address $dstNet)) {
                throw "Invalid destination IP address: $dstNet"
            }
            $dstInfo = Get-SubnetInfo -Network $dstNet -CIDR $dstCidr
            $destWildcard = @{
                Network = $dstInfo.NetworkAddress
                Wildcard = $dstInfo.WildcardMask
            }
        } elseif ($DestinationNetwork -eq 'host') {
            throw "Use CIDR notation (e.g., 10.0.0.1/32) for host entries"
        } else {
            throw "Destination network must be 'any' or in CIDR notation (e.g., 10.0.0.0/24)"
        }
    }

    # Validate ports for TCP/UDP only
    if ($Protocol -notin @('tcp', 'udp')) {
        if ($SourcePort -or $DestinationPort) {
            throw "Port specifications are only valid for TCP or UDP protocols"
        }
    }

    return [PSCustomObject]@{
        Sequence = $Sequence
        Action = $Action
        Protocol = $Protocol
        Source = $SourceNetwork
        SourceWildcard = $sourceWildcard
        SourcePort = $SourcePort
        Destination = $DestinationNetwork
        DestWildcard = $destWildcard
        DestinationPort = $DestinationPort
        Remark = $Remark
    }
}

<#
.SYNOPSIS
    Generates ACL configuration from a list of entries.

.PARAMETER ACLName
    The name of the ACL.

.PARAMETER Entries
    Array of ACL entry objects from New-ACLEntry.

.PARAMETER Vendor
    The vendor format to generate (Cisco, Arista).

.PARAMETER ACLType
    The ACL type (extended or standard).
#>
function Get-ACLConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ACLName,

        [Parameter(Mandatory=$true)]
        [array]$Entries,

        [ValidateSet('Cisco', 'Arista')]
        [string]$Vendor = 'Cisco',

        [ValidateSet('extended', 'standard')]
        [string]$ACLType = 'extended'
    )

    $lines = [System.Collections.Generic.List[string]]::new()

    # ACL header
    switch ($Vendor) {
        'Cisco' {
            $lines.Add("ip access-list $ACLType $ACLName")
        }
        'Arista' {
            $lines.Add("ip access-list $ACLName")
        }
    }

    # Sort entries by sequence if specified
    $sortedEntries = @($Entries | Sort-Object { if ($_.Sequence -gt 0) { $_.Sequence } else { [int]::MaxValue } })

    $seq = 10
    foreach ($entry in $sortedEntries) {
        $entrySeq = if ($entry.Sequence -gt 0) { $entry.Sequence } else { $seq; $seq += 10 }

        # Add remark if present
        if ($entry.Remark) {
            $lines.Add(" $entrySeq remark $($entry.Remark)")
            $entrySeq += 1
        }

        # Build the ACE line
        $ace = " $entrySeq $($entry.Action) $($entry.Protocol)"

        # Source
        if ($entry.SourceWildcard -eq 'any') {
            $ace += " any"
        } else {
            $ace += " $($entry.SourceWildcard.Network) $($entry.SourceWildcard.Wildcard)"
        }

        # Source port
        if ($entry.SourcePort) {
            if ($entry.SourcePort -match '^\d+$') {
                $ace += " eq $($entry.SourcePort)"
            } elseif ($entry.SourcePort -match '^(\d+)-(\d+)$') {
                $ace += " range $($Matches[1]) $($Matches[2])"
            } else {
                $ace += " eq $($entry.SourcePort)"
            }
        }

        # Destination
        if ($entry.DestWildcard -eq 'any') {
            $ace += " any"
        } else {
            $ace += " $($entry.DestWildcard.Network) $($entry.DestWildcard.Wildcard)"
        }

        # Destination port
        if ($entry.DestinationPort) {
            if ($entry.DestinationPort -match '^\d+$') {
                $ace += " eq $($entry.DestinationPort)"
            } elseif ($entry.DestinationPort -match '^(\d+)-(\d+)$') {
                $ace += " range $($Matches[1]) $($Matches[2])"
            } else {
                $ace += " eq $($entry.DestinationPort)"
            }
        }

        $lines.Add($ace)
    }

    return $lines -join "`n"
}

<#
.SYNOPSIS
    Validates an ACL entry for correctness.

.PARAMETER Entry
    The ACL entry object to validate.
#>
function Test-ACLEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Entry
    )

    $issues = @()

    # Check action
    if ($Entry.Action -notin @('permit', 'deny')) {
        $issues += "Invalid action: $($Entry.Action)"
    }

    # Check protocol
    if ($Entry.Protocol -notin @('ip', 'tcp', 'udp', 'icmp')) {
        $issues += "Invalid protocol: $($Entry.Protocol)"
    }

    # Check source
    if ($Entry.Source -ne 'any') {
        if ($Entry.Source -notmatch '^[\d.]+/\d+$') {
            $issues += "Invalid source format: $($Entry.Source)"
        }
    }

    # Check destination
    if ($Entry.Destination -ne 'any') {
        if ($Entry.Destination -notmatch '^[\d.]+/\d+$') {
            $issues += "Invalid destination format: $($Entry.Destination)"
        }
    }

    # Check ports only valid for TCP/UDP
    if ($Entry.Protocol -notin @('tcp', 'udp')) {
        if ($Entry.SourcePort -or $Entry.DestinationPort) {
            $issues += "Ports only valid for TCP/UDP"
        }
    }

    # Validate port format
    if ($Entry.SourcePort) {
        if ($Entry.SourcePort -notmatch '^\d+$' -and $Entry.SourcePort -notmatch '^\d+-\d+$' -and $Entry.SourcePort -notmatch '^[a-z]+$') {
            $issues += "Invalid source port format: $($Entry.SourcePort)"
        }
    }

    if ($Entry.DestinationPort) {
        if ($Entry.DestinationPort -notmatch '^\d+$' -and $Entry.DestinationPort -notmatch '^\d+-\d+$' -and $Entry.DestinationPort -notmatch '^[a-z]+$') {
            $issues += "Invalid destination port format: $($Entry.DestinationPort)"
        }
    }

    return [PSCustomObject]@{
        Valid = ($issues.Count -eq 0)
        Issues = $issues
    }
}

<#
.SYNOPSIS
    Returns common ACL templates.
#>
function Get-ACLTemplates {
    [CmdletBinding()]
    param()

    return @(
        [PSCustomObject]@{
            Name = 'Block RFC1918 Inbound'
            Description = 'Blocks private IP addresses from entering the network'
            Entries = @(
                @{ Action = 'deny'; Protocol = 'ip'; Source = '10.0.0.0/8'; Destination = 'any'; Remark = 'Block 10.0.0.0/8' }
                @{ Action = 'deny'; Protocol = 'ip'; Source = '172.16.0.0/12'; Destination = 'any'; Remark = 'Block 172.16.0.0/12' }
                @{ Action = 'deny'; Protocol = 'ip'; Source = '192.168.0.0/16'; Destination = 'any'; Remark = 'Block 192.168.0.0/16' }
                @{ Action = 'permit'; Protocol = 'ip'; Source = 'any'; Destination = 'any' }
            )
        }
        [PSCustomObject]@{
            Name = 'Allow Web Traffic Only'
            Description = 'Permits only HTTP and HTTPS traffic'
            Entries = @(
                @{ Action = 'permit'; Protocol = 'tcp'; Source = 'any'; Destination = 'any'; DestinationPort = '80'; Remark = 'Allow HTTP' }
                @{ Action = 'permit'; Protocol = 'tcp'; Source = 'any'; Destination = 'any'; DestinationPort = '443'; Remark = 'Allow HTTPS' }
                @{ Action = 'deny'; Protocol = 'ip'; Source = 'any'; Destination = 'any'; Remark = 'Deny all other' }
            )
        }
        [PSCustomObject]@{
            Name = 'Block Guest to Servers'
            Description = 'Prevents guest VLAN from accessing server networks'
            Entries = @(
                @{ Action = 'deny'; Protocol = 'ip'; Source = '10.1.50.0/24'; Destination = '10.1.10.0/24'; Remark = 'Block guest to servers' }
                @{ Action = 'permit'; Protocol = 'ip'; Source = 'any'; Destination = 'any' }
            )
        }
        [PSCustomObject]@{
            Name = 'Allow Management'
            Description = 'Permits SSH and SNMP from management network'
            Entries = @(
                @{ Action = 'permit'; Protocol = 'tcp'; Source = '10.0.0.0/24'; Destination = 'any'; DestinationPort = '22'; Remark = 'Allow SSH' }
                @{ Action = 'permit'; Protocol = 'udp'; Source = '10.0.0.0/24'; Destination = 'any'; DestinationPort = '161'; Remark = 'Allow SNMP' }
                @{ Action = 'deny'; Protocol = 'tcp'; Source = 'any'; Destination = 'any'; DestinationPort = '22'; Remark = 'Deny other SSH' }
                @{ Action = 'deny'; Protocol = 'udp'; Source = 'any'; Destination = 'any'; DestinationPort = '161'; Remark = 'Deny other SNMP' }
                @{ Action = 'permit'; Protocol = 'ip'; Source = 'any'; Destination = 'any' }
            )
        }
    )
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    # IP Conversion
    'Convert-IPToUInt32',
    'Convert-UInt32ToIP',
    'Convert-CIDRToMask',
    'Convert-MaskToCIDR',
    'Convert-IPToBinary',
    'Convert-BinaryToIP',
    'Convert-IPToDecimal',
    'Convert-DecimalToIP',
    # IP Validation
    'Test-IPv4Address',
    'Test-PrivateIP',
    'Test-LinkLocalIP',
    'Test-LoopbackIP',
    # Subnet Calculator
    'Get-SubnetInfo',
    'Test-IPInSubnet',
    'Split-Subnet',
    'Merge-Subnets',
    # VLAN Calculator
    'Expand-VLANRange',
    'Compress-VLANRange',
    # Bandwidth Calculator
    'Get-TransferTime',
    'Get-RequiredBandwidth',
    'Convert-Bandwidth',
    # Protocol Timers
    'Test-STPTimers',
    'Get-STPConvergenceTime',
    'Test-OSPFTimers',
    # Reference
    'Get-WellKnownPorts',
    # ACL Builder
    'New-ACLEntry',
    'Get-ACLConfig',
    'Test-ACLEntry',
    'Get-ACLTemplates'
)
