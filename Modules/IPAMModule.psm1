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

#region VLAN Discovery/Import (ST-V-003)

<#
.SYNOPSIS
    Parses VLANs from device configuration text.
.DESCRIPTION
    Extracts VLAN definitions from Cisco IOS/IOS-XE or Arista EOS configuration text.
    Returns VLAN objects that can be added to the IPAM database.
#>
function Import-VLANsFromConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigText,

        [Parameter()]
        [ValidateSet('Cisco_IOS', 'Arista_EOS', 'Auto')]
        [string]$Vendor = 'Auto',

        [Parameter()]
        [string]$Site,

        [Parameter()]
        [string]$DeviceName
    )

    $vlans = [System.Collections.ArrayList]::new()

    # Auto-detect vendor
    if ($Vendor -eq 'Auto') {
        if ($ConfigText -match 'Arista|EOS') {
            $Vendor = 'Arista_EOS'
        }
        else {
            $Vendor = 'Cisco_IOS'
        }
    }

    # Parse VLAN definitions: "vlan 100" followed by " name VlanName"
    $lines = $ConfigText -split "`r?`n"
    $currentVlan = $null

    foreach ($line in $lines) {
        # Match VLAN definition line
        if ($line -match '^\s*vlan\s+(\d+)\s*$') {
            # Save previous VLAN
            if ($currentVlan) {
                [void]$vlans.Add($currentVlan)
            }

            $vlanNum = [int]$Matches[1]
            if ($vlanNum -ge 1 -and $vlanNum -le 4094) {
                $currentVlan = [PSCustomObject]@{
                    VlanNumber   = $vlanNum
                    VlanName     = "VLAN$vlanNum"
                    Description  = $null
                    Purpose      = 'Data'
                    Site         = $Site
                    DeviceName   = $DeviceName
                    Status       = 'Active'
                    SVIAddress   = $null
                    SVIMask      = $null
                }
            }
        }
        # Match VLAN name line
        elseif ($currentVlan -and $line -match '^\s+name\s+(.+?)\s*$') {
            $currentVlan.VlanName = $Matches[1].Trim()

            # Guess purpose from name
            $nameLower = $currentVlan.VlanName.ToLower()
            if ($nameLower -match 'voice|phone|voip') {
                $currentVlan.Purpose = 'Voice'
            }
            elseif ($nameLower -match 'mgmt|management|oob') {
                $currentVlan.Purpose = 'Management'
            }
            elseif ($nameLower -match 'guest|visitor') {
                $currentVlan.Purpose = 'Guest'
            }
            elseif ($nameLower -match 'server|dc|datacenter') {
                $currentVlan.Purpose = 'Server'
            }
            elseif ($nameLower -match 'infra|infrastructure|transit') {
                $currentVlan.Purpose = 'Infrastructure'
            }
            elseif ($nameLower -match 'iot|sensor|camera') {
                $currentVlan.Purpose = 'IoT'
            }
        }
        # End of VLAN block
        elseif ($currentVlan -and $line -match '^[^\s]' -and $line -notmatch '^\s*!') {
            [void]$vlans.Add($currentVlan)
            $currentVlan = $null
        }
    }

    # Add final VLAN
    if ($currentVlan) {
        [void]$vlans.Add($currentVlan)
    }

    return @($vlans)
}

<#
.SYNOPSIS
    Parses SVI (VLAN interface) IP addresses from configuration.
.DESCRIPTION
    Extracts interface VLAN definitions with IP addresses to populate SVI info.
#>
function Import-SVIsFromConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigText,

        [Parameter()]
        [string]$Site,

        [Parameter()]
        [string]$DeviceName
    )

    $svis = [System.Collections.ArrayList]::new()
    $lines = $ConfigText -split "`r?`n"
    $currentSVI = $null

    foreach ($line in $lines) {
        # Match interface Vlan definition
        if ($line -match '^\s*interface\s+[Vv]lan\s*(\d+)\s*$') {
            # Save previous SVI
            if ($currentSVI -and $currentSVI.IPAddress) {
                [void]$svis.Add($currentSVI)
            }

            $vlanNum = [int]$Matches[1]
            $currentSVI = [PSCustomObject]@{
                VlanNumber  = $vlanNum
                IPAddress   = $null
                SubnetMask  = $null
                Description = $null
                Site        = $Site
                DeviceName  = $DeviceName
                IsSecondary = $false
                HSRPAddress = $null
                VRRPAddress = $null
            }
        }
        # Match IP address line
        elseif ($currentSVI -and $line -match '^\s+ip\s+address\s+(\d+\.\d+\.\d+\.\d+)\s+(\d+\.\d+\.\d+\.\d+)') {
            if (-not $currentSVI.IPAddress) {
                $currentSVI.IPAddress = $Matches[1]
                $currentSVI.SubnetMask = $Matches[2]
            }
            if ($line -match 'secondary') {
                $currentSVI.IsSecondary = $true
            }
        }
        # Match description line
        elseif ($currentSVI -and $line -match '^\s+description\s+(.+?)\s*$') {
            $currentSVI.Description = $Matches[1].Trim()
        }
        # Match HSRP/VRRP
        elseif ($currentSVI -and $line -match '^\s+standby\s+\d+\s+ip\s+(\d+\.\d+\.\d+\.\d+)') {
            $currentSVI.HSRPAddress = $Matches[1]
        }
        elseif ($currentSVI -and $line -match '^\s+vrrp\s+\d+\s+ip\s+(\d+\.\d+\.\d+\.\d+)') {
            $currentSVI.VRRPAddress = $Matches[1]
        }
        # End of interface block
        elseif ($currentSVI -and $line -match '^[^\s!]') {
            if ($currentSVI.IPAddress) {
                [void]$svis.Add($currentSVI)
            }
            $currentSVI = $null
        }
    }

    # Add final SVI
    if ($currentSVI -and $currentSVI.IPAddress) {
        [void]$svis.Add($currentSVI)
    }

    return @($svis)
}

<#
.SYNOPSIS
    Imports VLANs and SVIs from config text into the IPAM database.
.DESCRIPTION
    Parses configuration text, creates VLAN objects with SVI information,
    and adds them to the IPAM database. Skips duplicates by VLAN number.
#>
function Import-VLANsToDatabase {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigText,

        [Parameter()]
        [ValidateSet('Cisco_IOS', 'Arista_EOS', 'Auto')]
        [string]$Vendor = 'Auto',

        [Parameter()]
        [string]$Site,

        [Parameter()]
        [string]$DeviceName,

        [Parameter()]
        [hashtable]$Database,

        [Parameter()]
        [switch]$SkipDuplicates,

        [Parameter()]
        [switch]$UpdateExisting
    )

    $db = if ($Database) { $Database } else { $script:IPAMDatabase }

    # Parse VLANs and SVIs
    $vlans = @(Import-VLANsFromConfig -ConfigText $ConfigText -Vendor $Vendor -Site $Site -DeviceName $DeviceName)
    $svis = @(Import-SVIsFromConfig -ConfigText $ConfigText -Site $Site -DeviceName $DeviceName)

    # Index SVIs by VLAN number
    $sviIndex = @{}
    foreach ($svi in $svis) {
        $sviIndex[$svi.VlanNumber] = $svi
    }

    $imported = 0
    $skipped = 0
    $updated = 0
    $errors = [System.Collections.ArrayList]::new()

    foreach ($vlanInfo in $vlans) {
        # Check for existing
        $existing = $db.VLANs | Where-Object { $_.VlanNumber -eq $vlanInfo.VlanNumber }

        if ($existing) {
            if ($UpdateExisting) {
                # Update existing VLAN
                $existing.VlanName = $vlanInfo.VlanName
                $existing.Purpose = $vlanInfo.Purpose
                if ($vlanInfo.Site) { $existing.Site = $vlanInfo.Site }
                $existing.ModifiedDate = Get-Date

                # Add SVI info if available
                $svi = $sviIndex[$vlanInfo.VlanNumber]
                if ($svi) {
                    $existing.SVIAddress = $svi.IPAddress
                    $existing.SVIMask = $svi.SubnetMask
                }

                $updated++
            }
            elseif ($SkipDuplicates) {
                $skipped++
            }
            else {
                [void]$errors.Add("VLAN $($vlanInfo.VlanNumber) already exists")
            }
        }
        else {
            # Create new VLAN
            $svi = $sviIndex[$vlanInfo.VlanNumber]
            $newVlan = New-VLAN -VlanNumber $vlanInfo.VlanNumber `
                -VlanName $vlanInfo.VlanName `
                -Purpose $vlanInfo.Purpose `
                -Site $vlanInfo.Site `
                -Status 'Active' `
                -SVIAddress $(if ($svi) { $svi.IPAddress } else { $null }) `
                -SVIMask $(if ($svi) { $svi.SubnetMask } else { $null })

            [void]$db.VLANs.Add($newVlan)
            $imported++
        }
    }

    [PSCustomObject]@{
        Imported = $imported
        Skipped  = $skipped
        Updated  = $updated
        Errors   = @($errors)
        TotalParsed = $vlans.Count
        SVIsParsed = $svis.Count
    }
}

<#
.SYNOPSIS
    Merges VLANs from multiple sources, detecting conflicts.
.DESCRIPTION
    Combines VLANs from multiple device configs, identifying where the same
    VLAN number has different names across devices.
#>
function Merge-VLANDiscovery {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$DeviceConfigs,

        [Parameter()]
        [string]$Site
    )

    $allVlans = [System.Collections.ArrayList]::new()
    $conflicts = [System.Collections.ArrayList]::new()

    # Index for tracking VLAN numbers and their names
    $vlanNameIndex = @{}

    foreach ($device in $DeviceConfigs.Keys) {
        $config = $DeviceConfigs[$device]
        $vlans = @(Import-VLANsFromConfig -ConfigText $config -Site $Site -DeviceName $device)
        $svis = @(Import-SVIsFromConfig -ConfigText $config -Site $Site -DeviceName $device)

        # Index SVIs
        $sviIndex = @{}
        foreach ($svi in $svis) {
            $sviIndex[$svi.VlanNumber] = $svi
        }

        foreach ($vlan in $vlans) {
            $vlanNum = $vlan.VlanNumber

            if ($vlanNameIndex.ContainsKey($vlanNum)) {
                $existing = $vlanNameIndex[$vlanNum]

                # Check for name conflict
                if ($existing.VlanName -ne $vlan.VlanName) {
                    [void]$conflicts.Add([PSCustomObject]@{
                        VlanNumber = $vlanNum
                        Name1      = $existing.VlanName
                        Device1    = $existing.DeviceName
                        Name2      = $vlan.VlanName
                        Device2    = $device
                        Type       = 'NameMismatch'
                    })
                }

                # Add device to sources
                if (-not $existing.Sources) {
                    $existing | Add-Member -NotePropertyName 'Sources' -NotePropertyValue @($existing.DeviceName) -Force
                }
                $existing.Sources += $device
            }
            else {
                # Add SVI info
                $svi = $sviIndex[$vlanNum]
                if ($svi) {
                    $vlan | Add-Member -NotePropertyName 'SVIAddress' -NotePropertyValue $svi.IPAddress -Force
                    $vlan | Add-Member -NotePropertyName 'SVIMask' -NotePropertyValue $svi.SubnetMask -Force
                }
                $vlan | Add-Member -NotePropertyName 'Sources' -NotePropertyValue @($device) -Force

                $vlanNameIndex[$vlanNum] = $vlan
                [void]$allVlans.Add($vlan)
            }
        }
    }

    [PSCustomObject]@{
        VLANs        = @($allVlans | Sort-Object VlanNumber)
        Conflicts    = @($conflicts)
        DeviceCount  = $DeviceConfigs.Count
        TotalVLANs   = $allVlans.Count
        ConflictCount = $conflicts.Count
    }
}

<#
.SYNOPSIS
    Generates a VLAN discovery report.
.DESCRIPTION
    Creates a summary report of discovered VLANs from device configurations.
#>
function New-VLANDiscoveryReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DiscoveryResult,

        [Parameter()]
        [ValidateSet('Text', 'Markdown', 'CSV')]
        [string]$Format = 'Text'
    )

    switch ($Format) {
        'CSV' {
            $csv = @()
            $csv += 'VlanNumber,VlanName,Purpose,Site,SVIAddress,SVIMask,Sources'
            foreach ($vlan in $DiscoveryResult.VLANs) {
                $sources = if ($vlan.Sources) { $vlan.Sources -join ';' } else { '' }
                $csv += "$($vlan.VlanNumber),`"$($vlan.VlanName)`",$($vlan.Purpose),$($vlan.Site),$($vlan.SVIAddress),$($vlan.SVIMask),`"$sources`""
            }
            $csv -join "`n"
        }

        'Markdown' {
            $md = @()
            $md += "# VLAN Discovery Report"
            $md += ""
            $md += "**Generated:** $(Get-Date)"
            $md += "**Devices Scanned:** $($DiscoveryResult.DeviceCount)"
            $md += "**Total VLANs:** $($DiscoveryResult.TotalVLANs)"
            $md += "**Conflicts:** $($DiscoveryResult.ConflictCount)"
            $md += ""
            $md += "## VLANs Discovered"
            $md += ""
            $md += "| VLAN | Name | Purpose | SVI Address | Sources |"
            $md += "|------|------|---------|-------------|---------|"

            foreach ($vlan in $DiscoveryResult.VLANs) {
                $sources = if ($vlan.Sources) { $vlan.Sources -join ', ' } else { '-' }
                $svi = if ($vlan.SVIAddress) { "$($vlan.SVIAddress)/$($vlan.SVIMask)" } else { '-' }
                $md += "| $($vlan.VlanNumber) | $($vlan.VlanName) | $($vlan.Purpose) | $svi | $sources |"
            }

            if ($DiscoveryResult.Conflicts.Count -gt 0) {
                $md += ""
                $md += "## Conflicts Detected"
                $md += ""
                $md += "| VLAN | Device 1 | Name 1 | Device 2 | Name 2 |"
                $md += "|------|----------|--------|----------|--------|"
                foreach ($conflict in $DiscoveryResult.Conflicts) {
                    $md += "| $($conflict.VlanNumber) | $($conflict.Device1) | $($conflict.Name1) | $($conflict.Device2) | $($conflict.Name2) |"
                }
            }

            $md -join "`n"
        }

        default {
            $txt = @()
            $txt += "=" * 60
            $txt += "VLAN DISCOVERY REPORT"
            $txt += "=" * 60
            $txt += "Generated: $(Get-Date)"
            $txt += "Devices Scanned: $($DiscoveryResult.DeviceCount)"
            $txt += "Total VLANs: $($DiscoveryResult.TotalVLANs)"
            $txt += "Conflicts: $($DiscoveryResult.ConflictCount)"
            $txt += "-" * 60
            $txt += ""
            $txt += "VLANS DISCOVERED:"
            $txt += "-" * 60

            foreach ($vlan in $DiscoveryResult.VLANs) {
                $sources = if ($vlan.Sources) { $vlan.Sources -join ', ' } else { 'Unknown' }
                $txt += "VLAN $($vlan.VlanNumber): $($vlan.VlanName)"
                $txt += "  Purpose: $($vlan.Purpose)"
                if ($vlan.SVIAddress) {
                    $txt += "  SVI: $($vlan.SVIAddress) / $($vlan.SVIMask)"
                }
                $txt += "  Sources: $sources"
                $txt += ""
            }

            if ($DiscoveryResult.Conflicts.Count -gt 0) {
                $txt += "-" * 60
                $txt += "CONFLICTS:"
                foreach ($conflict in $DiscoveryResult.Conflicts) {
                    $txt += "  VLAN $($conflict.VlanNumber): '$($conflict.Name1)' ($($conflict.Device1)) vs '$($conflict.Name2)' ($($conflict.Device2))"
                }
            }

            $txt += "=" * 60
            $txt -join "`n"
        }
    }
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
    'Import-VLANsFromConfig'
    'Import-SVIsFromConfig'
    'Import-VLANsToDatabase'
    'Merge-VLANDiscovery'
    'New-VLANDiscoveryReport'
)
