Set-StrictMode -Version Latest

<#
.SYNOPSIS
    IP Address Management (IPAM) and VLAN Planning module.

.DESCRIPTION
    Provides lightweight IPAM functionality for tracking VLANs, subnets, and IP addresses.
    Includes conflict detection, subnet planning, and address space visualization.
    Part of Plan V - IP Address & VLAN Planning.
#>

#region Data Structures

<#
.SYNOPSIS
    Creates a new VLAN object.
#>
function New-VLAN {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 4094)]
        [int]$VlanNumber,

        [Parameter(Mandatory = $true)]
        [string]$VlanName,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [ValidateSet('Data', 'Voice', 'Management', 'Infrastructure', 'Guest', 'IoT', 'Server', 'Other')]
        [string]$Purpose = 'Data',

        [Parameter()]
        [string]$Site,

        [Parameter()]
        [ValidateSet('Active', 'Reserved', 'Deprecated', 'Planned')]
        [string]$Status = 'Active',

        [Parameter()]
        [string]$SVIAddress,

        [Parameter()]
        [string]$SVIMask,

        [Parameter()]
        [string]$Notes
    )

    $now = Get-Date

    [PSCustomObject]@{
        VlanID       = [guid]::NewGuid().ToString()
        VlanNumber   = $VlanNumber
        VlanName     = $VlanName
        Description  = $Description
        Purpose      = $Purpose
        Site         = $Site
        Status       = $Status
        SVIAddress   = $SVIAddress
        SVIMask      = $SVIMask
        Notes        = $Notes
        CreatedDate  = $now
        ModifiedDate = $now
    }
}

<#
.SYNOPSIS
    Creates a new subnet object.
#>
function New-Subnet {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NetworkAddress,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 32)]
        [int]$PrefixLength,

        [Parameter()]
        [int]$VlanNumber,

        [Parameter()]
        [string]$Site,

        [Parameter()]
        [ValidateSet('Data', 'Voice', 'Management', 'Infrastructure', 'Guest', 'IoT', 'Server', 'Other')]
        [string]$Purpose = 'Data',

        [Parameter()]
        [string]$GatewayAddress,

        [Parameter()]
        [string]$DHCPStart,

        [Parameter()]
        [string]$DHCPEnd,

        [Parameter()]
        [ValidateSet('Active', 'Reserved', 'Available', 'Deprecated')]
        [string]$Status = 'Active',

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string]$Notes
    )

    $now = Get-Date

    # Calculate subnet details
    $details = Get-SubnetDetails -NetworkAddress $NetworkAddress -PrefixLength $PrefixLength

    [PSCustomObject]@{
        SubnetID       = [guid]::NewGuid().ToString()
        NetworkAddress = $NetworkAddress
        PrefixLength   = $PrefixLength
        SubnetMask     = $details.SubnetMask
        BroadcastAddress = $details.BroadcastAddress
        FirstUsable    = $details.FirstUsable
        LastUsable     = $details.LastUsable
        TotalHosts     = $details.TotalHosts
        VlanNumber     = $VlanNumber
        Site           = $Site
        Purpose        = $Purpose
        GatewayAddress = $GatewayAddress
        DHCPStart      = $DHCPStart
        DHCPEnd        = $DHCPEnd
        Status         = $Status
        Description    = $Description
        Notes          = $Notes
        CreatedDate    = $now
        ModifiedDate   = $now
    }
}

<#
.SYNOPSIS
    Creates a new IP address record.
#>
function New-IPAddressRecord {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$IPAddress,

        [Parameter()]
        [string]$SubnetID,

        [Parameter()]
        [string]$DeviceName,

        [Parameter()]
        [string]$InterfaceName,

        [Parameter()]
        [ValidateSet('Static', 'DHCP', 'HSRP', 'VRRP', 'Loopback', 'Management', 'Other')]
        [string]$AddressType = 'Static',

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [ValidateSet('Active', 'Reserved', 'Available', 'Conflict')]
        [string]$Status = 'Active',

        [Parameter()]
        [string]$Notes
    )

    $now = Get-Date

    [PSCustomObject]@{
        AddressID     = [guid]::NewGuid().ToString()
        IPAddress     = $IPAddress
        SubnetID      = $SubnetID
        DeviceName    = $DeviceName
        InterfaceName = $InterfaceName
        AddressType   = $AddressType
        Description   = $Description
        Status        = $Status
        Notes         = $Notes
        LastSeen      = $now
        CreatedDate   = $now
        ModifiedDate  = $now
    }
}

#endregion

#region Subnet Calculations

<#
.SYNOPSIS
    Calculates subnet details from network address and prefix length.
#>
function Get-SubnetDetails {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NetworkAddress,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 32)]
        [int]$PrefixLength
    )

    try {
        $ip = [System.Net.IPAddress]::Parse($NetworkAddress)
        $ipBytes = $ip.GetAddressBytes()
        $ipInt = [BitConverter]::ToUInt32($ipBytes[3..0], 0)

        # Calculate subnet mask
        $maskInt = [uint32]([Math]::Pow(2, 32) - [Math]::Pow(2, 32 - $PrefixLength))
        $maskBytes = [BitConverter]::GetBytes($maskInt)[3..0]
        $subnetMask = ($maskBytes -join '.')

        # Calculate network address (ensure it's the actual network)
        $networkInt = $ipInt -band $maskInt
        $networkBytes = [BitConverter]::GetBytes($networkInt)[3..0]
        $network = ($networkBytes -join '.')

        # Calculate broadcast
        $wildcardInt = -bnot $maskInt
        $broadcastInt = $networkInt -bor ($wildcardInt -band 0xFFFFFFFF)
        $broadcastBytes = [BitConverter]::GetBytes($broadcastInt)[3..0]
        $broadcast = ($broadcastBytes -join '.')

        # Calculate usable range
        $totalHosts = [Math]::Pow(2, 32 - $PrefixLength) - 2
        if ($totalHosts -lt 0) { $totalHosts = 0 }

        $firstUsableInt = $networkInt + 1
        $lastUsableInt = $broadcastInt - 1

        if ($PrefixLength -ge 31) {
            # /31 and /32 are special cases
            $firstUsable = $network
            $lastUsable = $broadcast
            $totalHosts = [Math]::Pow(2, 32 - $PrefixLength)
        } else {
            $firstUsableBytes = [BitConverter]::GetBytes($firstUsableInt)[3..0]
            $firstUsable = ($firstUsableBytes -join '.')
            $lastUsableBytes = [BitConverter]::GetBytes($lastUsableInt)[3..0]
            $lastUsable = ($lastUsableBytes -join '.')
        }

        [PSCustomObject]@{
            NetworkAddress   = $network
            PrefixLength     = $PrefixLength
            SubnetMask       = $subnetMask
            BroadcastAddress = $broadcast
            FirstUsable      = $firstUsable
            LastUsable       = $lastUsable
            TotalHosts       = [int]$totalHosts
            CIDR             = "$network/$PrefixLength"
        }
    }
    catch {
        Write-Warning "Invalid IP address or prefix: $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
    Converts an IP address string to integer.
#>
function ConvertTo-IPInt {
    [CmdletBinding()]
    param([string]$IPAddress)

    $ip = [System.Net.IPAddress]::Parse($IPAddress)
    $bytes = $ip.GetAddressBytes()
    [BitConverter]::ToUInt32($bytes[3..0], 0)
}

<#
.SYNOPSIS
    Converts an integer to IP address string.
#>
function ConvertFrom-IPInt {
    [CmdletBinding()]
    param([uint32]$IPInt)

    $bytes = [BitConverter]::GetBytes($IPInt)[3..0]
    $bytes -join '.'
}

<#
.SYNOPSIS
    Tests if an IP address is within a subnet.
#>
function Test-IPInSubnet {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$IPAddress,

        [Parameter(Mandatory = $true)]
        [string]$NetworkAddress,

        [Parameter(Mandatory = $true)]
        [int]$PrefixLength
    )

    try {
        $ipInt = ConvertTo-IPInt -IPAddress $IPAddress
        $networkInt = ConvertTo-IPInt -IPAddress $NetworkAddress
        $maskInt = [uint32]([Math]::Pow(2, 32) - [Math]::Pow(2, 32 - $PrefixLength))

        ($ipInt -band $maskInt) -eq ($networkInt -band $maskInt)
    }
    catch {
        $false
    }
}

<#
.SYNOPSIS
    Splits a subnet into smaller subnets.
#>
function Split-Subnet {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NetworkAddress,

        [Parameter(Mandatory = $true)]
        [int]$PrefixLength,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 32)]
        [int]$NewPrefixLength
    )

    if ($NewPrefixLength -le $PrefixLength) {
        Write-Warning "New prefix length must be greater than current prefix length"
        return @()
    }

    $numSubnets = [Math]::Pow(2, $NewPrefixLength - $PrefixLength)
    $subnetSize = [Math]::Pow(2, 32 - $NewPrefixLength)

    $networkInt = ConvertTo-IPInt -IPAddress $NetworkAddress
    $maskInt = [uint32]([Math]::Pow(2, 32) - [Math]::Pow(2, 32 - $PrefixLength))
    $networkInt = $networkInt -band $maskInt

    $results = @()
    for ($i = 0; $i -lt $numSubnets; $i++) {
        $subnetInt = $networkInt + ($i * $subnetSize)
        $subnetAddr = ConvertFrom-IPInt -IPInt $subnetInt
        $results += Get-SubnetDetails -NetworkAddress $subnetAddr -PrefixLength $NewPrefixLength
    }

    $results
}

#endregion

#region IPAM Database Operations

# Module-level storage
$script:IPAMDatabase = @{
    VLANs    = New-Object System.Collections.ArrayList
    Subnets  = New-Object System.Collections.ArrayList
    IPAddresses = New-Object System.Collections.ArrayList
}

<#
.SYNOPSIS
    Initializes a new IPAM database.
#>
function New-IPAMDatabase {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        VLANs       = New-Object System.Collections.ArrayList
        Subnets     = New-Object System.Collections.ArrayList
        IPAddresses = New-Object System.Collections.ArrayList
    }
}

<#
.SYNOPSIS
    Adds a VLAN to the database.
#>
function Add-VLAN {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject]$VLAN,

        [Parameter()]
        [hashtable]$Database
    )

    process {
        $db = if ($Database) { $Database } else { $script:IPAMDatabase }

        # Check for duplicate VLAN number at same site
        $existing = $db.VLANs | Where-Object {
            $_.VlanNumber -eq $VLAN.VlanNumber -and $_.Site -eq $VLAN.Site
        }
        if ($existing) {
            Write-Warning "VLAN $($VLAN.VlanNumber) already exists at site '$($VLAN.Site)'"
            return $null
        }

        $db.VLANs.Add($VLAN) | Out-Null
        $VLAN
    }
}

<#
.SYNOPSIS
    Gets VLANs from the database.
#>
function Get-VLANRecord {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$VlanNumber,

        [Parameter()]
        [string]$Site,

        [Parameter()]
        [string]$Purpose,

        [Parameter()]
        [string]$Status,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:IPAMDatabase }
    $results = @($db.VLANs)

    if ($VlanNumber) {
        $results = @($results | Where-Object { $_.VlanNumber -eq $VlanNumber })
    }
    if ($Site) {
        $results = @($results | Where-Object { $_.Site -like "*$Site*" })
    }
    if ($Purpose) {
        $results = @($results | Where-Object { $_.Purpose -eq $Purpose })
    }
    if ($Status) {
        $results = @($results | Where-Object { $_.Status -eq $Status })
    }

    $results
}

<#
.SYNOPSIS
    Updates a VLAN record.
#>
function Update-VLAN {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VlanID,

        [Parameter(Mandatory = $true)]
        [hashtable]$Properties,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:IPAMDatabase }
    $vlan = $db.VLANs | Where-Object { $_.VlanID -eq $VlanID } | Select-Object -First 1

    if (-not $vlan) {
        Write-Warning "VLAN with ID '$VlanID' not found"
        return $null
    }

    foreach ($key in $Properties.Keys) {
        if ($vlan.PSObject.Properties[$key]) {
            $vlan.$key = $Properties[$key]
        }
    }
    $vlan.ModifiedDate = Get-Date
    $vlan
}

<#
.SYNOPSIS
    Removes a VLAN from the database.
#>
function Remove-VLAN {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VlanID,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:IPAMDatabase }
    $vlan = $db.VLANs | Where-Object { $_.VlanID -eq $VlanID } | Select-Object -First 1

    if (-not $vlan) {
        Write-Warning "VLAN with ID '$VlanID' not found"
        return $false
    }

    $db.VLANs.Remove($vlan)
    $true
}

<#
.SYNOPSIS
    Adds a subnet to the database.
#>
function Add-Subnet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject]$Subnet,

        [Parameter()]
        [hashtable]$Database
    )

    process {
        $db = if ($Database) { $Database } else { $script:IPAMDatabase }

        # Check for overlapping subnets
        foreach ($existing in $db.Subnets) {
            if (Test-SubnetOverlap -Subnet1Network $Subnet.NetworkAddress -Subnet1Prefix $Subnet.PrefixLength `
                    -Subnet2Network $existing.NetworkAddress -Subnet2Prefix $existing.PrefixLength) {
                Write-Warning "Subnet $($Subnet.NetworkAddress)/$($Subnet.PrefixLength) overlaps with existing subnet $($existing.NetworkAddress)/$($existing.PrefixLength)"
            }
        }

        $db.Subnets.Add($Subnet) | Out-Null
        $Subnet
    }
}

<#
.SYNOPSIS
    Gets subnets from the database.
#>
function Get-SubnetRecord {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$NetworkAddress,

        [Parameter()]
        [int]$VlanNumber,

        [Parameter()]
        [string]$Site,

        [Parameter()]
        [string]$Purpose,

        [Parameter()]
        [string]$Status,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:IPAMDatabase }
    $results = @($db.Subnets)

    if ($NetworkAddress) {
        $results = @($results | Where-Object { $_.NetworkAddress -eq $NetworkAddress })
    }
    if ($VlanNumber) {
        $results = @($results | Where-Object { $_.VlanNumber -eq $VlanNumber })
    }
    if ($Site) {
        $results = @($results | Where-Object { $_.Site -like "*$Site*" })
    }
    if ($Purpose) {
        $results = @($results | Where-Object { $_.Purpose -eq $Purpose })
    }
    if ($Status) {
        $results = @($results | Where-Object { $_.Status -eq $Status })
    }

    $results
}

<#
.SYNOPSIS
    Removes a subnet from the database.
#>
function Remove-Subnet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SubnetID,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:IPAMDatabase }
    $subnet = $db.Subnets | Where-Object { $_.SubnetID -eq $SubnetID } | Select-Object -First 1

    if (-not $subnet) {
        Write-Warning "Subnet with ID '$SubnetID' not found"
        return $false
    }

    $db.Subnets.Remove($subnet)
    $true
}

<#
.SYNOPSIS
    Adds an IP address record to the database.
#>
function Add-IPAddressRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject]$IPRecord,

        [Parameter()]
        [hashtable]$Database
    )

    process {
        $db = if ($Database) { $Database } else { $script:IPAMDatabase }

        # Check for duplicate IP
        $existing = $db.IPAddresses | Where-Object { $_.IPAddress -eq $IPRecord.IPAddress }
        if ($existing) {
            Write-Warning "IP address $($IPRecord.IPAddress) already exists (assigned to $($existing.DeviceName))"
        }

        $db.IPAddresses.Add($IPRecord) | Out-Null
        $IPRecord
    }
}

<#
.SYNOPSIS
    Gets IP address records from the database.
#>
function Get-IPAddressRecord {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$IPAddress,

        [Parameter()]
        [string]$DeviceName,

        [Parameter()]
        [string]$SubnetID,

        [Parameter()]
        [string]$AddressType,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:IPAMDatabase }
    $results = @($db.IPAddresses)

    if ($IPAddress) {
        $results = @($results | Where-Object { $_.IPAddress -eq $IPAddress })
    }
    if ($DeviceName) {
        $results = @($results | Where-Object { $_.DeviceName -like "*$DeviceName*" })
    }
    if ($SubnetID) {
        $results = @($results | Where-Object { $_.SubnetID -eq $SubnetID })
    }
    if ($AddressType) {
        $results = @($results | Where-Object { $_.AddressType -eq $AddressType })
    }

    $results
}

<#
.SYNOPSIS
    Removes an IP address record from the database.
#>
function Remove-IPAddressRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AddressID,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:IPAMDatabase }
    $record = $db.IPAddresses | Where-Object { $_.AddressID -eq $AddressID } | Select-Object -First 1

    if (-not $record) {
        Write-Warning "IP address record with ID '$AddressID' not found"
        return $false
    }

    $db.IPAddresses.Remove($record)
    $true
}

#endregion

#region Conflict Detection

<#
.SYNOPSIS
    Tests if two subnets overlap.
#>
function Test-SubnetOverlap {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Subnet1Network,

        [Parameter(Mandatory = $true)]
        [int]$Subnet1Prefix,

        [Parameter(Mandatory = $true)]
        [string]$Subnet2Network,

        [Parameter(Mandatory = $true)]
        [int]$Subnet2Prefix
    )

    $s1Start = ConvertTo-IPInt -IPAddress $Subnet1Network
    $s1End = $s1Start + [Math]::Pow(2, 32 - $Subnet1Prefix) - 1

    $s2Start = ConvertTo-IPInt -IPAddress $Subnet2Network
    $s2End = $s2Start + [Math]::Pow(2, 32 - $Subnet2Prefix) - 1

    -not ($s1End -lt $s2Start -or $s2End -lt $s1Start)
}

<#
.SYNOPSIS
    Finds VLAN conflicts in the database.
#>
function Find-VLANConflicts {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:IPAMDatabase }
    $conflicts = @()

    # Group VLANs by number
    $vlanGroups = $db.VLANs | Group-Object -Property VlanNumber

    foreach ($group in $vlanGroups) {
        if ($group.Count -gt 1) {
            $names = $group.Group | Select-Object -ExpandProperty VlanName -Unique
            if ($names.Count -gt 1) {
                $conflicts += [PSCustomObject]@{
                    Type        = 'VLANNameMismatch'
                    Severity    = 'Warning'
                    VlanNumber  = $group.Name
                    Details     = "VLAN $($group.Name) has different names: $($names -join ', ')"
                    Sites       = ($group.Group | Select-Object -ExpandProperty Site -Unique) -join ', '
                    Entries     = $group.Group
                }
            }
        }
    }

    $conflicts
}

<#
.SYNOPSIS
    Finds IP address conflicts in the database.
#>
function Find-IPConflicts {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:IPAMDatabase }
    $conflicts = @()

    # Group by IP address
    $ipGroups = $db.IPAddresses | Group-Object -Property IPAddress

    foreach ($group in $ipGroups) {
        if ($group.Count -gt 1) {
            $devices = $group.Group | ForEach-Object { "$($_.DeviceName):$($_.InterfaceName)" }
            $conflicts += [PSCustomObject]@{
                Type      = 'DuplicateIP'
                Severity  = 'Critical'
                IPAddress = $group.Name
                Details   = "IP $($group.Name) assigned to multiple devices: $($devices -join ', ')"
                Entries   = $group.Group
            }
        }
    }

    $conflicts
}

<#
.SYNOPSIS
    Finds all conflicts in the IPAM database.
#>
function Find-IPAMConflicts {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:IPAMDatabase }

    $conflicts = @()
    $conflicts += Find-VLANConflicts -Database $db
    $conflicts += Find-IPConflicts -Database $db

    # Check for subnet overlaps
    $subnets = @($db.Subnets)
    for ($i = 0; $i -lt $subnets.Count; $i++) {
        for ($j = $i + 1; $j -lt $subnets.Count; $j++) {
            if (Test-SubnetOverlap -Subnet1Network $subnets[$i].NetworkAddress -Subnet1Prefix $subnets[$i].PrefixLength `
                    -Subnet2Network $subnets[$j].NetworkAddress -Subnet2Prefix $subnets[$j].PrefixLength) {
                $conflicts += [PSCustomObject]@{
                    Type     = 'SubnetOverlap'
                    Severity = 'Critical'
                    Details  = "Subnet $($subnets[$i].NetworkAddress)/$($subnets[$i].PrefixLength) overlaps with $($subnets[$j].NetworkAddress)/$($subnets[$j].PrefixLength)"
                    Entries  = @($subnets[$i], $subnets[$j])
                }
            }
        }
    }

    $conflicts
}

#endregion

#region Planning Tools

<#
.SYNOPSIS
    Finds available VLAN numbers in a range.
#>
function Find-AvailableVLANs {
    [CmdletBinding()]
    [OutputType([int[]])]
    param(
        [Parameter()]
        [int]$StartVlan = 1,

        [Parameter()]
        [int]$EndVlan = 4094,

        [Parameter()]
        [string]$Site,

        [Parameter()]
        [int]$Count = 10,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:IPAMDatabase }

    $usedVlans = @($db.VLANs | Where-Object {
        (-not $Site) -or ($_.Site -eq $Site)
    } | Select-Object -ExpandProperty VlanNumber)

    $available = @()
    for ($i = $StartVlan; $i -le $EndVlan -and $available.Count -lt $Count; $i++) {
        if ($i -notin $usedVlans) {
            $available += $i
        }
    }

    $available
}

<#
.SYNOPSIS
    Finds available address space within a supernet.
#>
function Find-AvailableSubnets {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SupernetAddress,

        [Parameter(Mandatory = $true)]
        [int]$SupernetPrefix,

        [Parameter(Mandatory = $true)]
        [int]$DesiredPrefix,

        [Parameter()]
        [int]$Count = 5,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:IPAMDatabase }

    # Get all possible subnets of desired size within supernet
    $possibleSubnets = Split-Subnet -NetworkAddress $SupernetAddress -PrefixLength $SupernetPrefix -NewPrefixLength $DesiredPrefix

    # Filter out those that overlap with existing allocations
    $available = @()
    foreach ($possible in $possibleSubnets) {
        $overlaps = $false
        foreach ($existing in $db.Subnets) {
            if (Test-SubnetOverlap -Subnet1Network $possible.NetworkAddress -Subnet1Prefix $possible.PrefixLength `
                    -Subnet2Network $existing.NetworkAddress -Subnet2Prefix $existing.PrefixLength) {
                $overlaps = $true
                break
            }
        }
        if (-not $overlaps) {
            $available += $possible
            if ($available.Count -ge $Count) { break }
        }
    }

    $available
}

<#
.SYNOPSIS
    Generates a site address plan based on requirements.
#>
function New-SiteAddressPlan {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteName,

        [Parameter(Mandatory = $true)]
        [string]$SupernetAddress,

        [Parameter(Mandatory = $true)]
        [int]$SupernetPrefix,

        [Parameter()]
        [hashtable]$VLANRequirements,

        [Parameter()]
        [double]$GrowthFactor = 0.25,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:IPAMDatabase }

    # Default VLAN requirements if not specified
    if (-not $VLANRequirements) {
        $VLANRequirements = @{
            Data       = @{ Hosts = 100; VlanNumber = 10 }
            Voice      = @{ Hosts = 50; VlanNumber = 20 }
            Management = @{ Hosts = 20; VlanNumber = 100 }
        }
    }

    $allocations = @()
    $usedSpace = @()

    foreach ($vlanType in $VLANRequirements.Keys) {
        $req = $VLANRequirements[$vlanType]
        $hosts = $req.Hosts
        $vlanNum = $req.VlanNumber

        # Apply growth factor
        $totalHosts = [Math]::Ceiling($hosts * (1 + $GrowthFactor))

        # Calculate required prefix length
        $prefixLength = 32 - [Math]::Ceiling([Math]::Log($totalHosts + 2, 2))
        if ($prefixLength -lt $SupernetPrefix) { $prefixLength = $SupernetPrefix + 1 }
        if ($prefixLength -gt 30) { $prefixLength = 30 }

        # Find available subnet
        $available = Find-AvailableSubnets -SupernetAddress $SupernetAddress -SupernetPrefix $SupernetPrefix `
            -DesiredPrefix $prefixLength -Count 1 -Database $db

        # Also exclude already planned subnets
        $available = @($available | Where-Object {
            $net = $_
            $overlaps = $false
            foreach ($used in $usedSpace) {
                if (Test-SubnetOverlap -Subnet1Network $net.NetworkAddress -Subnet1Prefix $net.PrefixLength `
                        -Subnet2Network $used.NetworkAddress -Subnet2Prefix $used.PrefixLength) {
                    $overlaps = $true
                    break
                }
            }
            -not $overlaps
        })

        if ($available.Count -gt 0) {
            $subnet = $available[0]
            $usedSpace += $subnet

            $allocations += [PSCustomObject]@{
                VLANType      = $vlanType
                VlanNumber    = $vlanNum
                NetworkAddress = $subnet.NetworkAddress
                PrefixLength  = $subnet.PrefixLength
                SubnetMask    = $subnet.SubnetMask
                TotalHosts    = $subnet.TotalHosts
                RequestedHosts = $hosts
                GatewayAddress = $subnet.FirstUsable
            }
        }
    }

    [PSCustomObject]@{
        SiteName    = $SiteName
        Supernet    = "$SupernetAddress/$SupernetPrefix"
        GrowthFactor = $GrowthFactor
        Allocations = $allocations
        GeneratedDate = Get-Date
    }
}

#endregion

#region Import/Export

<#
.SYNOPSIS
    Exports the IPAM database to JSON.
#>
function Export-IPAMDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:IPAMDatabase }

    $export = @{
        ExportDate  = (Get-Date).ToString('o')
        Version     = '1.0'
        VLANs       = @($db.VLANs)
        Subnets     = @($db.Subnets)
        IPAddresses = @($db.IPAddresses)
    }

    $export | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
}

<#
.SYNOPSIS
    Imports an IPAM database from JSON.
#>
function Import-IPAMDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [switch]$Merge,

        [Parameter()]
        [hashtable]$Database
    )

    if (-not (Test-Path $Path)) {
        Write-Warning "File not found: $Path"
        return $null
    }

    $db = if ($Database) { $Database } else { $script:IPAMDatabase }
    $content = Get-Content -Path $Path -Raw | ConvertFrom-Json

    if (-not $Merge) {
        $db.VLANs.Clear()
        $db.Subnets.Clear()
        $db.IPAddresses.Clear()
    }

    $vlansAdded = 0
    $subnetsAdded = 0
    $ipsAdded = 0

    foreach ($vlan in $content.VLANs) {
        $existing = $db.VLANs | Where-Object { $_.VlanID -eq $vlan.VlanID }
        if (-not $existing) {
            $db.VLANs.Add($vlan) | Out-Null
            $vlansAdded++
        }
    }

    foreach ($subnet in $content.Subnets) {
        $existing = $db.Subnets | Where-Object { $_.SubnetID -eq $subnet.SubnetID }
        if (-not $existing) {
            $db.Subnets.Add($subnet) | Out-Null
            $subnetsAdded++
        }
    }

    foreach ($ip in $content.IPAddresses) {
        $existing = $db.IPAddresses | Where-Object { $_.AddressID -eq $ip.AddressID }
        if (-not $existing) {
            $db.IPAddresses.Add($ip) | Out-Null
            $ipsAdded++
        }
    }

    [PSCustomObject]@{
        VLANsImported     = $vlansAdded
        SubnetsImported   = $subnetsAdded
        IPAddressesImported = $ipsAdded
    }
}

<#
.SYNOPSIS
    Gets IPAM database statistics.
#>
function Get-IPAMStats {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:IPAMDatabase }

    $vlansByPurpose = @{}
    foreach ($vlan in $db.VLANs) {
        $purpose = $vlan.Purpose
        if (-not $vlansByPurpose[$purpose]) { $vlansByPurpose[$purpose] = 0 }
        $vlansByPurpose[$purpose]++
    }

    $subnetsByPurpose = @{}
    $totalAllocatedHosts = 0
    foreach ($subnet in $db.Subnets) {
        $purpose = $subnet.Purpose
        if (-not $subnetsByPurpose[$purpose]) { $subnetsByPurpose[$purpose] = 0 }
        $subnetsByPurpose[$purpose]++
        $totalAllocatedHosts += $subnet.TotalHosts
    }

    $sites = @($db.VLANs | Select-Object -ExpandProperty Site -Unique | Where-Object { $_ })
    $sites += @($db.Subnets | Select-Object -ExpandProperty Site -Unique | Where-Object { $_ })
    $sites = $sites | Select-Object -Unique

    [PSCustomObject]@{
        TotalVLANs          = $db.VLANs.Count
        TotalSubnets        = $db.Subnets.Count
        TotalIPAddresses    = $db.IPAddresses.Count
        TotalAllocatedHosts = $totalAllocatedHosts
        VLANsByPurpose      = $vlansByPurpose
        SubnetsByPurpose    = $subnetsByPurpose
        Sites               = $sites
    }
}

<#
.SYNOPSIS
    Clears the IPAM database.
#>
function Clear-IPAMDatabase {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:IPAMDatabase }
    $db.VLANs.Clear()
    $db.Subnets.Clear()
    $db.IPAddresses.Clear()
}

#endregion

Export-ModuleMember -Function @(
    'New-VLAN'
    'New-Subnet'
    'New-IPAddressRecord'
    'Get-SubnetDetails'
    'ConvertTo-IPInt'
    'ConvertFrom-IPInt'
    'Test-IPInSubnet'
    'Split-Subnet'
    'New-IPAMDatabase'
    'Add-VLAN'
    'Get-VLANRecord'
    'Update-VLAN'
    'Remove-VLAN'
    'Add-Subnet'
    'Get-SubnetRecord'
    'Remove-Subnet'
    'Add-IPAddressRecord'
    'Get-IPAddressRecord'
    'Remove-IPAddressRecord'
    'Test-SubnetOverlap'
    'Find-VLANConflicts'
    'Find-IPConflicts'
    'Find-IPAMConflicts'
    'Find-AvailableVLANs'
    'Find-AvailableSubnets'
    'New-SiteAddressPlan'
    'Export-IPAMDatabase'
    'Import-IPAMDatabase'
    'Get-IPAMStats'
    'Clear-IPAMDatabase'
)
