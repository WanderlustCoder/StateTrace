#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Network topology discovery and visualization module.

.DESCRIPTION
    Provides topology discovery from interface descriptions and CDP/LLDP data,
    graph modeling, layout algorithms, and diagram export capabilities.

.NOTES
    Plan W - Network Topology Visualization
#>

#region Module State

# Topology nodes (devices)
if (-not (Get-Variable -Scope Script -Name TopologyNodes -ErrorAction SilentlyContinue)) {
    $script:TopologyNodes = [System.Collections.ArrayList]::new()
}

# Topology links (connections)
if (-not (Get-Variable -Scope Script -Name TopologyLinks -ErrorAction SilentlyContinue)) {
    $script:TopologyLinks = [System.Collections.ArrayList]::new()
}

# Saved layouts
if (-not (Get-Variable -Scope Script -Name TopologyLayouts -ErrorAction SilentlyContinue)) {
    $script:TopologyLayouts = [System.Collections.ArrayList]::new()
}

# Link discovery patterns
$script:LinkPatterns = @(
    # "To DEVICE-NAME PortType" pattern
    @{
        Name = 'ToDevice'
        Pattern = '^[Tt]o\s+([A-Za-z0-9_-]+)\s*(?:([A-Za-z]{2}\d+/\d+(?:/\d+)?))?\s*$'
        DeviceGroup = 1
        PortGroup = 2
    },
    # "Uplink to DEVICE" pattern
    @{
        Name = 'UplinkTo'
        Pattern = '^[Uu]plink\s+(?:to\s+)?([A-Za-z0-9_-]+)\s*(?:([A-Za-z]{2}\d+/\d+(?:/\d+)?))?\s*$'
        DeviceGroup = 1
        PortGroup = 2
    },
    # "DEVICE PortType" simple pattern
    @{
        Name = 'DevicePort'
        Pattern = '^([A-Za-z]{2,4}-[A-Za-z0-9-]+)\s+([A-Za-z]{2}\d+/\d+(?:/\d+)?)\s*$'
        DeviceGroup = 1
        PortGroup = 2
    },
    # "Po# - DEVICE" port-channel pattern
    @{
        Name = 'PortChannel'
        Pattern = '^[Pp]o(\d+)\s*[-:]\s*([A-Za-z0-9_-]+)'
        PortChannelGroup = 1
        DeviceGroup = 2
    },
    # "WAN to DEVICE" pattern
    @{
        Name = 'WANLink'
        Pattern = '^[Ww][Aa][Nn]\s+(?:to\s+)?([A-Za-z0-9_-]+)'
        DeviceGroup = 1
        IsWAN = $true
    },
    # "Link to DEVICE" pattern
    @{
        Name = 'LinkTo'
        Pattern = '^[Ll]ink\s+(?:to\s+)?([A-Za-z0-9_-]+)\s*(?:([A-Za-z]{2}\d+/\d+(?:/\d+)?))?\s*$'
        DeviceGroup = 1
        PortGroup = 2
    }
)

#endregion

#region Node Management

function New-TopologyNode {
    <#
    .SYNOPSIS
        Creates a new topology node (device).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DeviceID,

        [string]$DisplayName,
        [string]$NodeType = 'Switch',
        [string]$Role,
        [string]$SiteID,
        [string]$BuildingID,
        [double]$XPosition = 0,
        [double]$YPosition = 0,
        [string]$IconType,
        [hashtable]$Properties = @{}
    )

    $nodeID = [guid]::NewGuid().ToString()

    # Auto-detect role from device name if not provided
    if (-not $Role) {
        $Role = Get-DeviceRole -DeviceName $DeviceID
    }

    # Auto-detect icon type
    if (-not $IconType) {
        $IconType = Get-DeviceIconType -Role $Role -NodeType $NodeType
    }

    $node = [PSCustomObject]@{
        NodeID      = $nodeID
        DeviceID    = $DeviceID
        DisplayName = if ($DisplayName) { $DisplayName } else { $DeviceID }
        NodeType    = $NodeType
        Role        = $Role
        SiteID      = $SiteID
        BuildingID  = $BuildingID
        XPosition   = $XPosition
        YPosition   = $YPosition
        IconType    = $IconType
        Properties  = $Properties
        CreatedDate = Get-Date
    }

    [void]$script:TopologyNodes.Add($node)
    return $node
}

function Get-TopologyNode {
    <#
    .SYNOPSIS
        Gets topology nodes with optional filtering.
    #>
    [CmdletBinding()]
    param(
        [string]$NodeID,
        [string]$DeviceID,
        [string]$Role,
        [string]$SiteID,
        [string]$NodeType
    )

    $nodes = @($script:TopologyNodes)

    if ($NodeID) {
        $nodes = $nodes | Where-Object { $_.NodeID -eq $NodeID }
    }
    if ($DeviceID) {
        $nodes = $nodes | Where-Object { $_.DeviceID -eq $DeviceID }
    }
    if ($Role) {
        $nodes = $nodes | Where-Object { $_.Role -eq $Role }
    }
    if ($SiteID) {
        $nodes = $nodes | Where-Object { $_.SiteID -eq $SiteID }
    }
    if ($NodeType) {
        $nodes = $nodes | Where-Object { $_.NodeType -eq $NodeType }
    }

    return $nodes
}

function Remove-TopologyNode {
    <#
    .SYNOPSIS
        Removes a topology node and its associated links.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$NodeID
    )

    # Remove associated links first
    $linksToRemove = @($script:TopologyLinks | Where-Object {
        $_.SourceNodeID -eq $NodeID -or $_.DestNodeID -eq $NodeID
    })

    foreach ($link in $linksToRemove) {
        [void]$script:TopologyLinks.Remove($link)
    }

    # Remove the node
    $node = $script:TopologyNodes | Where-Object { $_.NodeID -eq $NodeID }
    if ($node) {
        [void]$script:TopologyNodes.Remove($node)
        return $true
    }
    return $false
}

function Get-DeviceRole {
    <#
    .SYNOPSIS
        Infers device role from naming convention.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DeviceName
    )

    $name = $DeviceName.ToUpper()

    # Core devices
    if ($name -match 'CORE|CR-|^CR\d') {
        return 'Core'
    }

    # Distribution devices
    if ($name -match 'DIST|DS-|^DS\d|DISTRIB') {
        return 'Distribution'
    }

    # Access devices
    if ($name -match 'ACCESS|AS-|^AS\d|^SW-|^SW\d') {
        return 'Access'
    }

    # Routers
    if ($name -match '^R-|^RTR|ROUTER|^GW-') {
        return 'Router'
    }

    # Firewalls
    if ($name -match 'FW-|FIREWALL|ASA|PALO|FORTI') {
        return 'Firewall'
    }

    # Wireless controllers
    if ($name -match 'WLC|WIRELESS|WIFI|^AP-') {
        return 'Wireless'
    }

    # Default to Access
    return 'Access'
}

function Get-DeviceIconType {
    <#
    .SYNOPSIS
        Gets the icon type for a device based on role and type.
    #>
    [CmdletBinding()]
    param(
        [string]$Role,
        [string]$NodeType
    )

    switch ($Role) {
        'Core' { return 'CoreSwitch' }
        'Distribution' { return 'DistributionSwitch' }
        'Access' { return 'AccessSwitch' }
        'Router' { return 'Router' }
        'Firewall' { return 'Firewall' }
        'Wireless' { return 'WirelessController' }
        default { return 'GenericSwitch' }
    }
}

#endregion

#region Link Management

function New-TopologyLink {
    <#
    .SYNOPSIS
        Creates a new topology link between nodes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceNodeID,

        [string]$SourcePort,

        [Parameter(Mandatory)]
        [string]$DestNodeID,

        [string]$DestPort,
        [string]$LinkType = 'Ethernet',
        [string]$Speed,
        [string[]]$VLANs,
        [bool]$IsAggregate = $false,
        [string]$DiscoveryMethod = 'Manual',
        [string]$Status = 'Active',
        [string]$CableID,
        [hashtable]$Properties = @{}
    )

    # Verify source and dest nodes exist
    $sourceNode = Get-TopologyNode -NodeID $SourceNodeID
    $destNode = Get-TopologyNode -NodeID $DestNodeID

    if (-not $sourceNode) {
        Write-Warning "Source node $SourceNodeID not found"
        return $null
    }
    if (-not $destNode) {
        Write-Warning "Destination node $DestNodeID not found"
        return $null
    }

    # Check for duplicate link
    $existing = $script:TopologyLinks | Where-Object {
        ($_.SourceNodeID -eq $SourceNodeID -and $_.DestNodeID -eq $DestNodeID) -or
        ($_.SourceNodeID -eq $DestNodeID -and $_.DestNodeID -eq $SourceNodeID)
    }

    if ($existing) {
        Write-Warning "Link between $SourceNodeID and $DestNodeID already exists"
        return $existing
    }

    $linkID = [guid]::NewGuid().ToString()

    $link = [PSCustomObject]@{
        LinkID          = $linkID
        SourceNodeID    = $SourceNodeID
        SourcePort      = $SourcePort
        DestNodeID      = $DestNodeID
        DestPort        = $DestPort
        LinkType        = $LinkType
        Speed           = $Speed
        VLANs           = $VLANs
        IsAggregate     = $IsAggregate
        DiscoveryMethod = $DiscoveryMethod
        Status          = $Status
        CableID         = $CableID
        Properties      = $Properties
        CreatedDate     = Get-Date
    }

    [void]$script:TopologyLinks.Add($link)
    return $link
}

function Get-TopologyLink {
    <#
    .SYNOPSIS
        Gets topology links with optional filtering.
    #>
    [CmdletBinding()]
    param(
        [string]$LinkID,
        [string]$NodeID,
        [string]$LinkType,
        [string]$Status
    )

    $links = @($script:TopologyLinks)

    if ($LinkID) {
        $links = $links | Where-Object { $_.LinkID -eq $LinkID }
    }
    if ($NodeID) {
        $links = $links | Where-Object {
            $_.SourceNodeID -eq $NodeID -or $_.DestNodeID -eq $NodeID
        }
    }
    if ($LinkType) {
        $links = $links | Where-Object { $_.LinkType -eq $LinkType }
    }
    if ($Status) {
        $links = $links | Where-Object { $_.Status -eq $Status }
    }

    return $links
}

function Remove-TopologyLink {
    <#
    .SYNOPSIS
        Removes a topology link.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LinkID
    )

    $link = $script:TopologyLinks | Where-Object { $_.LinkID -eq $LinkID }
    if ($link) {
        [void]$script:TopologyLinks.Remove($link)
        return $true
    }
    return $false
}

#endregion

#region Link Discovery

function Find-LinksFromDescription {
    <#
    .SYNOPSIS
        Discovers links from interface descriptions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceDevice,

        [Parameter(Mandatory)]
        [string]$SourcePort,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($Description)) {
        return $null
    }

    foreach ($pattern in $script:LinkPatterns) {
        if ($Description -match $pattern['Pattern']) {
            $destDevice = $null
            $destPort = $null
            $isWAN = $false
            $portChannel = $null

            # Use hashtable key access for StrictMode compatibility
            if ($pattern.ContainsKey('DeviceGroup') -and $pattern['DeviceGroup'] -and $Matches[$pattern['DeviceGroup']]) {
                $destDevice = $Matches[$pattern['DeviceGroup']]
            }
            if ($pattern.ContainsKey('PortGroup') -and $pattern['PortGroup'] -and $Matches[$pattern['PortGroup']]) {
                $destPort = $Matches[$pattern['PortGroup']]
            }
            if ($pattern.ContainsKey('IsWAN') -and $pattern['IsWAN']) {
                $isWAN = $true
            }
            if ($pattern.ContainsKey('PortChannelGroup') -and $pattern['PortChannelGroup'] -and $Matches[$pattern['PortChannelGroup']]) {
                $portChannel = "Po$($Matches[$pattern['PortChannelGroup']])"
            }

            if ($destDevice) {
                return [PSCustomObject]@{
                    SourceDevice = $SourceDevice
                    SourcePort   = $SourcePort
                    DestDevice   = $destDevice
                    DestPort     = $destPort
                    IsWAN        = $isWAN
                    PortChannel  = $portChannel
                    Pattern      = $pattern['Name']
                }
            }
        }
    }

    return $null
}

function New-TopologyFromInterfaces {
    <#
    .SYNOPSIS
        Builds topology graph from interface data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Interfaces,

        [string]$SiteID,
        [switch]$ClearExisting
    )

    if ($ClearExisting) {
        Clear-Topology
    }

    $discoveredLinks = @()
    $devicesFound = @{}

    foreach ($iface in $Interfaces) {
        $hostname = $iface.Hostname
        if (-not $hostname) { continue }

        # Track device
        if (-not $devicesFound.ContainsKey($hostname)) {
            $devicesFound[$hostname] = $true

            # Create node if not exists
            $existingNode = Get-TopologyNode -DeviceID $hostname
            if (-not $existingNode) {
                New-TopologyNode -DeviceID $hostname -SiteID $SiteID | Out-Null
            }
        }

        # Check for link in description
        $description = $iface.Description
        $portName = $iface.PortName
        if (-not $portName) { $portName = $iface.InterfaceName }

        if ($description) {
            $linkInfo = Find-LinksFromDescription -SourceDevice $hostname -SourcePort $portName -Description $description
            if ($linkInfo) {
                $discoveredLinks += $linkInfo
            }
        }
    }

    # Create nodes for discovered destination devices
    foreach ($link in $discoveredLinks) {
        if (-not $devicesFound.ContainsKey($link.DestDevice)) {
            $existingNode = Get-TopologyNode -DeviceID $link.DestDevice
            if (-not $existingNode) {
                New-TopologyNode -DeviceID $link.DestDevice -SiteID $SiteID | Out-Null
            }
            $devicesFound[$link.DestDevice] = $true
        }
    }

    # Create links
    $linksCreated = 0
    foreach ($link in $discoveredLinks) {
        $sourceNode = Get-TopologyNode -DeviceID $link.SourceDevice
        $destNode = Get-TopologyNode -DeviceID $link.DestDevice

        if ($sourceNode -and $destNode) {
            $linkType = if ($link.IsWAN) { 'WAN' } else { 'Ethernet' }

            $newLink = New-TopologyLink `
                -SourceNodeID $sourceNode.NodeID `
                -SourcePort $link.SourcePort `
                -DestNodeID $destNode.NodeID `
                -DestPort $link.DestPort `
                -LinkType $linkType `
                -DiscoveryMethod 'InterfaceDescription' `
                -IsAggregate ($null -ne $link.PortChannel)

            if ($newLink) {
                $linksCreated++
            }
        }
    }

    return [PSCustomObject]@{
        NodesCreated = $devicesFound.Count
        LinksDiscovered = $discoveredLinks.Count
        LinksCreated = $linksCreated
    }
}

function Clear-Topology {
    <#
    .SYNOPSIS
        Clears all topology data.
    #>
    [CmdletBinding()]
    param()

    $script:TopologyNodes.Clear()
    $script:TopologyLinks.Clear()
}

#endregion

#region Layout Algorithms

function Set-HierarchicalLayout {
    <#
    .SYNOPSIS
        Applies hierarchical layout to topology nodes.
    #>
    [CmdletBinding()]
    param(
        [double]$Width = 800,
        [double]$Height = 600,
        [double]$VerticalSpacing = 150,
        [double]$HorizontalSpacing = 120
    )

    $nodes = @(Get-TopologyNode)
    if ($nodes.Count -eq 0) { return }

    # Group nodes by role/tier
    $tiers = @{
        0 = @()  # Core
        1 = @()  # Distribution
        2 = @()  # Access/Other
    }

    foreach ($node in $nodes) {
        switch ($node.Role) {
            'Core' { $tiers[0] += $node }
            'Distribution' { $tiers[1] += $node }
            'Router' { $tiers[0] += $node }
            'Firewall' { $tiers[0] += $node }
            default { $tiers[2] += $node }
        }
    }

    # Position each tier
    $yOffset = 50
    foreach ($tierIndex in 0..2) {
        $tierNodes = $tiers[$tierIndex]
        if ($tierNodes.Count -eq 0) { continue }

        $totalWidth = ($tierNodes.Count - 1) * $HorizontalSpacing
        $startX = ($Width - $totalWidth) / 2

        for ($i = 0; $i -lt $tierNodes.Count; $i++) {
            $tierNodes[$i].XPosition = $startX + ($i * $HorizontalSpacing)
            $tierNodes[$i].YPosition = $yOffset
        }

        $yOffset += $VerticalSpacing
    }
}

function Set-ForceDirectedLayout {
    <#
    .SYNOPSIS
        Applies force-directed layout to topology nodes.
    #>
    [CmdletBinding()]
    param(
        [double]$Width = 800,
        [double]$Height = 600,
        [int]$Iterations = 100,
        [double]$RepulsionForce = 5000,
        [double]$AttractionForce = 0.1,
        [double]$Damping = 0.85
    )

    $nodes = @(Get-TopologyNode)
    $links = @(Get-TopologyLink)

    if ($nodes.Count -eq 0) { return }

    # Initialize random positions if not set
    $random = [System.Random]::new()
    foreach ($node in $nodes) {
        if ($node.XPosition -eq 0 -and $node.YPosition -eq 0) {
            $node.XPosition = $random.NextDouble() * $Width
            $node.YPosition = $random.NextDouble() * $Height
        }
    }

    # Create velocity array
    $velocities = @{}
    foreach ($node in $nodes) {
        $velocities[$node.NodeID] = @{ X = 0; Y = 0 }
    }

    # Iterate
    for ($iter = 0; $iter -lt $Iterations; $iter++) {
        # Calculate repulsion between all node pairs
        for ($i = 0; $i -lt $nodes.Count; $i++) {
            for ($j = $i + 1; $j -lt $nodes.Count; $j++) {
                $nodeA = $nodes[$i]
                $nodeB = $nodes[$j]

                $dx = $nodeB.XPosition - $nodeA.XPosition
                $dy = $nodeB.YPosition - $nodeA.YPosition
                $distance = [math]::Sqrt($dx * $dx + $dy * $dy)

                if ($distance -lt 1) { $distance = 1 }

                $force = $RepulsionForce / ($distance * $distance)
                $fx = ($dx / $distance) * $force
                $fy = ($dy / $distance) * $force

                $velocities[$nodeA.NodeID].X -= $fx
                $velocities[$nodeA.NodeID].Y -= $fy
                $velocities[$nodeB.NodeID].X += $fx
                $velocities[$nodeB.NodeID].Y += $fy
            }
        }

        # Calculate attraction along links
        foreach ($link in $links) {
            $nodeA = $nodes | Where-Object { $_.NodeID -eq $link.SourceNodeID }
            $nodeB = $nodes | Where-Object { $_.NodeID -eq $link.DestNodeID }

            if (-not $nodeA -or -not $nodeB) { continue }

            $dx = $nodeB.XPosition - $nodeA.XPosition
            $dy = $nodeB.YPosition - $nodeA.YPosition
            $distance = [math]::Sqrt($dx * $dx + $dy * $dy)

            if ($distance -lt 1) { $distance = 1 }

            $force = $distance * $AttractionForce
            $fx = ($dx / $distance) * $force
            $fy = ($dy / $distance) * $force

            $velocities[$nodeA.NodeID].X += $fx
            $velocities[$nodeA.NodeID].Y += $fy
            $velocities[$nodeB.NodeID].X -= $fx
            $velocities[$nodeB.NodeID].Y -= $fy
        }

        # Apply velocities with damping
        foreach ($node in $nodes) {
            $vel = $velocities[$node.NodeID]
            $node.XPosition += $vel.X * $Damping
            $node.YPosition += $vel.Y * $Damping

            # Keep within bounds
            $node.XPosition = [math]::Max(50, [math]::Min($Width - 50, $node.XPosition))
            $node.YPosition = [math]::Max(50, [math]::Min($Height - 50, $node.YPosition))

            # Decay velocity
            $vel.X *= $Damping
            $vel.Y *= $Damping
        }
    }
}

function Set-CircularLayout {
    <#
    .SYNOPSIS
        Applies circular layout to topology nodes.
    #>
    [CmdletBinding()]
    param(
        [double]$CenterX = 400,
        [double]$CenterY = 300,
        [double]$Radius = 250
    )

    $nodes = @(Get-TopologyNode)
    if ($nodes.Count -eq 0) { return }

    $angleStep = (2 * [math]::PI) / $nodes.Count

    for ($i = 0; $i -lt $nodes.Count; $i++) {
        $angle = $i * $angleStep - ([math]::PI / 2)  # Start at top
        $nodes[$i].XPosition = $CenterX + ($Radius * [math]::Cos($angle))
        $nodes[$i].YPosition = $CenterY + ($Radius * [math]::Sin($angle))
    }
}

function Set-GridLayout {
    <#
    .SYNOPSIS
        Applies grid layout to topology nodes.
    #>
    [CmdletBinding()]
    param(
        [double]$StartX = 50,
        [double]$StartY = 50,
        [double]$SpacingX = 150,
        [double]$SpacingY = 120,
        [int]$Columns = 5
    )

    $nodes = @(Get-TopologyNode)
    if ($nodes.Count -eq 0) { return }

    for ($i = 0; $i -lt $nodes.Count; $i++) {
        $col = $i % $Columns
        $row = [math]::Floor($i / $Columns)

        $nodes[$i].XPosition = $StartX + ($col * $SpacingX)
        $nodes[$i].YPosition = $StartY + ($row * $SpacingY)
    }
}

#endregion

#region Impact Analysis

function Get-ImpactAnalysis {
    <#
    .SYNOPSIS
        Analyzes the impact of a device or link failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$NodeID
    )

    $node = Get-TopologyNode -NodeID $NodeID
    if (-not $node) {
        Write-Warning "Node $NodeID not found"
        return $null
    }

    # Find directly connected nodes
    $directLinks = Get-TopologyLink -NodeID $NodeID
    $directlyAffected = @()

    foreach ($link in $directLinks) {
        $affectedNodeID = if ($link.SourceNodeID -eq $NodeID) {
            $link.DestNodeID
        } else {
            $link.SourceNodeID
        }

        $affectedNode = Get-TopologyNode -NodeID $affectedNodeID
        if ($affectedNode) {
            # Check redundancy - does affected node have other uplinks?
            $otherLinks = @(Get-TopologyLink -NodeID $affectedNodeID | Where-Object {
                $_.SourceNodeID -ne $NodeID -and $_.DestNodeID -ne $NodeID
            })

            $directlyAffected += [PSCustomObject]@{
                Node            = $affectedNode
                HasRedundancy   = ($otherLinks.Count -gt 0)
                RedundantLinks  = $otherLinks.Count
                IsCritical      = ($otherLinks.Count -eq 0)
            }
        }
    }

    # Calculate total impact
    $criticalCount = @($directlyAffected | Where-Object { $_.IsCritical }).Count

    return [PSCustomObject]@{
        AffectedNode       = $node
        DirectLinks        = @($directLinks).Count
        DirectlyAffected   = $directlyAffected
        CriticalDevices    = $criticalCount
        HasFullRedundancy  = ($criticalCount -eq 0)
        Summary            = if ($criticalCount -eq 0) {
            "All connected devices have redundant paths"
        } else {
            "$criticalCount device(s) will lose connectivity"
        }
    }
}

function Get-ConnectedNodes {
    <#
    .SYNOPSIS
        Gets all nodes connected to a given node (direct and indirect).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$NodeID,

        [int]$MaxDepth = 10
    )

    $visited = @{}
    $queue = [System.Collections.Queue]::new()
    $queue.Enqueue(@{ NodeID = $NodeID; Depth = 0 })
    $visited[$NodeID] = 0

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if ($current.Depth -ge $MaxDepth) { continue }

        $links = Get-TopologyLink -NodeID $current.NodeID
        foreach ($link in $links) {
            $neighborID = if ($link.SourceNodeID -eq $current.NodeID) {
                $link.DestNodeID
            } else {
                $link.SourceNodeID
            }

            if (-not $visited.ContainsKey($neighborID)) {
                $visited[$neighborID] = $current.Depth + 1
                $queue.Enqueue(@{ NodeID = $neighborID; Depth = $current.Depth + 1 })
            }
        }
    }

    $results = @()
    foreach ($kvp in $visited.GetEnumerator()) {
        if ($kvp.Key -ne $NodeID) {
            $node = Get-TopologyNode -NodeID $kvp.Key
            if ($node) {
                $results += [PSCustomObject]@{
                    Node  = $node
                    Depth = $kvp.Value
                }
            }
        }
    }

    return $results | Sort-Object Depth
}

#endregion

#region Export Functions

function Export-TopologyToSVG {
    <#
    .SYNOPSIS
        Exports topology to SVG format.
    #>
    [CmdletBinding()]
    param(
        [string]$OutputPath,
        [double]$Width = 800,
        [double]$Height = 600,
        [string]$Title = 'Network Topology'
    )

    $nodes = @(Get-TopologyNode)
    $links = @(Get-TopologyLink)

    $svg = @"
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="$Width" height="$Height" viewBox="0 0 $Width $Height">
  <style>
    .node { fill: #4a90d9; stroke: #2d5a87; stroke-width: 2; }
    .node-core { fill: #e74c3c; }
    .node-distribution { fill: #f39c12; }
    .node-access { fill: #27ae60; }
    .node-router { fill: #9b59b6; }
    .node-firewall { fill: #c0392b; }
    .link { stroke: #666; stroke-width: 2; fill: none; }
    .link-wan { stroke: #e74c3c; stroke-dasharray: 5,5; }
    .label { font-family: Arial, sans-serif; font-size: 12px; fill: #333; text-anchor: middle; }
    .title { font-family: Arial, sans-serif; font-size: 16px; font-weight: bold; fill: #333; }
  </style>
  <text x="$($Width/2)" y="25" class="title" text-anchor="middle">$Title</text>

"@

    # Draw links first (behind nodes)
    foreach ($link in $links) {
        $sourceNode = $nodes | Where-Object { $_.NodeID -eq $link.SourceNodeID }
        $destNode = $nodes | Where-Object { $_.NodeID -eq $link.DestNodeID }

        if ($sourceNode -and $destNode) {
            $linkClass = if ($link.LinkType -eq 'WAN') { 'link link-wan' } else { 'link' }
            $svg += "  <line x1=`"$($sourceNode.XPosition)`" y1=`"$($sourceNode.YPosition)`" x2=`"$($destNode.XPosition)`" y2=`"$($destNode.YPosition)`" class=`"$linkClass`"/>`n"
        }
    }

    # Draw nodes
    foreach ($node in $nodes) {
        $roleClass = switch ($node.Role) {
            'Core' { 'node node-core' }
            'Distribution' { 'node node-distribution' }
            'Access' { 'node node-access' }
            'Router' { 'node node-router' }
            'Firewall' { 'node node-firewall' }
            default { 'node' }
        }

        $svg += "  <circle cx=`"$($node.XPosition)`" cy=`"$($node.YPosition)`" r=`"25`" class=`"$roleClass`"/>`n"
        $svg += "  <text x=`"$($node.XPosition)`" y=`"$($node.YPosition + 40)`" class=`"label`">$($node.DisplayName)</text>`n"
    }

    $svg += "</svg>"

    if ($OutputPath) {
        $svg | Out-File -FilePath $OutputPath -Encoding UTF8
        return $OutputPath
    }

    return $svg
}

function Export-TopologyToJSON {
    <#
    .SYNOPSIS
        Exports topology to JSON format for external tools.
    #>
    [CmdletBinding()]
    param(
        [string]$OutputPath
    )

    $nodes = @(Get-TopologyNode)
    $links = @(Get-TopologyLink)

    $export = @{
        nodes = $nodes | ForEach-Object {
            @{
                id         = $_.NodeID
                deviceId   = $_.DeviceID
                name       = $_.DisplayName
                role       = $_.Role
                type       = $_.NodeType
                x          = $_.XPosition
                y          = $_.YPosition
                site       = $_.SiteID
            }
        }
        links = $links | ForEach-Object {
            @{
                id         = $_.LinkID
                source     = $_.SourceNodeID
                sourcePort = $_.SourcePort
                target     = $_.DestNodeID
                targetPort = $_.DestPort
                type       = $_.LinkType
                speed      = $_.Speed
                status     = $_.Status
            }
        }
        metadata = @{
            exportDate = (Get-Date).ToString('o')
            nodeCount  = $nodes.Count
            linkCount  = $links.Count
        }
    }

    $json = $export | ConvertTo-Json -Depth 5

    if ($OutputPath) {
        $json | Out-File -FilePath $OutputPath -Encoding UTF8
        return $OutputPath
    }

    return $json
}

function Export-TopologyToDrawIO {
    <#
    .SYNOPSIS
        Exports topology to Draw.io compatible XML format.
    #>
    [CmdletBinding()]
    param(
        [string]$OutputPath
    )

    $nodes = @(Get-TopologyNode)
    $links = @(Get-TopologyLink)

    # Generate Draw.io XML
    $cellId = 2  # Start after root cells

    $xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="app.diagrams.net">
  <diagram name="Network Topology" id="topology">
    <mxGraphModel dx="1000" dy="600" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="827" pageHeight="1169">
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>

"@

    # Add nodes
    $nodeIdMap = @{}
    foreach ($node in $nodes) {
        $nodeIdMap[$node.NodeID] = $cellId

        $style = switch ($node.Role) {
            'Core' { 'shape=mxgraph.cisco.switches.layer_3_switch;fillColor=#FF6666;' }
            'Distribution' { 'shape=mxgraph.cisco.switches.workgroup_switch;fillColor=#FFB366;' }
            'Router' { 'shape=mxgraph.cisco.routers.router;fillColor=#B366FF;' }
            'Firewall' { 'shape=mxgraph.cisco.security.firewall;fillColor=#FF3333;' }
            default { 'shape=mxgraph.cisco.switches.workgroup_switch;fillColor=#66B366;' }
        }

        $xml += @"
        <mxCell id="$cellId" value="$($node.DisplayName)" style="$style" vertex="1" parent="1">
          <mxGeometry x="$($node.XPosition)" y="$($node.YPosition)" width="50" height="50" as="geometry"/>
        </mxCell>

"@
        $cellId++
    }

    # Add links
    foreach ($link in $links) {
        $sourceId = $nodeIdMap[$link.SourceNodeID]
        $destId = $nodeIdMap[$link.DestNodeID]

        if ($sourceId -and $destId) {
            $style = if ($link.LinkType -eq 'WAN') {
                'strokeColor=#FF0000;dashed=1;'
            } else {
                'strokeColor=#666666;'
            }

            $xml += @"
        <mxCell id="$cellId" style="edgeStyle=orthogonalEdgeStyle;$style" edge="1" parent="1" source="$sourceId" target="$destId">
          <mxGeometry relative="1" as="geometry"/>
        </mxCell>

"@
            $cellId++
        }
    }

    $xml += @"
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
"@

    if ($OutputPath) {
        $xml | Out-File -FilePath $OutputPath -Encoding UTF8
        return $OutputPath
    }

    return $xml
}

#endregion

#region Layout Persistence

function Save-TopologyLayout {
    <#
    .SYNOPSIS
        Saves the current topology layout.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LayoutName,

        [string]$Scope = 'Default'
    )

    $nodes = @(Get-TopologyNode)

    $layoutData = $nodes | ForEach-Object {
        @{
            NodeID    = $_.NodeID
            DeviceID  = $_.DeviceID
            XPosition = $_.XPosition
            YPosition = $_.YPosition
        }
    }

    # Check for existing layout
    $existing = $script:TopologyLayouts | Where-Object { $_.LayoutName -eq $LayoutName }
    if ($existing) {
        $existing.LayoutData = $layoutData
        $existing.ModifiedDate = Get-Date
    } else {
        $layout = [PSCustomObject]@{
            LayoutID     = [guid]::NewGuid().ToString()
            LayoutName   = $LayoutName
            Scope        = $Scope
            CreatedDate  = Get-Date
            ModifiedDate = Get-Date
            LayoutData   = $layoutData
        }
        [void]$script:TopologyLayouts.Add($layout)
    }

    return $true
}

function Get-TopologyLayout {
    <#
    .SYNOPSIS
        Gets saved topology layouts.
    #>
    [CmdletBinding()]
    param(
        [string]$LayoutName
    )

    if ($LayoutName) {
        return $script:TopologyLayouts | Where-Object { $_.LayoutName -eq $LayoutName }
    }
    return @($script:TopologyLayouts)
}

function Restore-TopologyLayout {
    <#
    .SYNOPSIS
        Restores a saved topology layout.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LayoutName
    )

    $layout = Get-TopologyLayout -LayoutName $LayoutName
    if (-not $layout) {
        Write-Warning "Layout '$LayoutName' not found"
        return $false
    }

    foreach ($pos in $layout.LayoutData) {
        $node = Get-TopologyNode -DeviceID $pos.DeviceID
        if ($node) {
            $node.XPosition = $pos.XPosition
            $node.YPosition = $pos.YPosition
        }
    }

    return $true
}

#endregion

#region L3 Topology Functions

function Add-L3Interface {
    <#
    .SYNOPSIS
        Adds L3 interface data to a topology node.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$NodeID,

        [Parameter(Mandatory)]
        [string]$InterfaceName,

        [Parameter(Mandatory)]
        [string]$IPAddress,

        [string]$SubnetMask = '255.255.255.0',
        [int]$PrefixLength,
        [string]$VRF = 'default',
        [string]$Description,
        [string]$RoutingProtocol,
        [string]$OSPFArea,
        [string]$EIGRPAS,
        [bool]$IsGateway = $false
    )

    $node = Get-TopologyNode -NodeID $NodeID
    if (-not $node) {
        Write-Warning "Node $NodeID not found"
        return $null
    }

    # Calculate prefix if not provided
    if (-not $PrefixLength) {
        $PrefixLength = ConvertTo-PrefixLength -SubnetMask $SubnetMask
    }

    # Calculate network address
    $networkAddress = Get-NetworkAddress -IPAddress $IPAddress -PrefixLength $PrefixLength

    # Initialize L3Interfaces if not exists
    if (-not $node.Properties.ContainsKey('L3Interfaces')) {
        $node.Properties['L3Interfaces'] = [System.Collections.ArrayList]::new()
    }

    $l3Interface = [PSCustomObject]@{
        InterfaceName   = $InterfaceName
        IPAddress       = $IPAddress
        SubnetMask      = $SubnetMask
        PrefixLength    = $PrefixLength
        NetworkAddress  = $networkAddress
        CIDR            = "$networkAddress/$PrefixLength"
        VRF             = $VRF
        Description     = $Description
        RoutingProtocol = $RoutingProtocol
        OSPFArea        = $OSPFArea
        EIGRPAS         = $EIGRPAS
        IsGateway       = $IsGateway
    }

    [void]$node.Properties['L3Interfaces'].Add($l3Interface)
    return $l3Interface
}

function Get-L3Interfaces {
    <#
    .SYNOPSIS
        Gets L3 interfaces for a node.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$NodeID
    )

    $node = Get-TopologyNode -NodeID $NodeID
    if (-not $node) { return @() }

    if ($node.Properties.ContainsKey('L3Interfaces')) {
        return @($node.Properties['L3Interfaces'])
    }
    return @()
}

function ConvertTo-PrefixLength {
    <#
    .SYNOPSIS
        Converts subnet mask to prefix length.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SubnetMask
    )

    $octets = $SubnetMask.Split('.')
    $binary = ''
    foreach ($octet in $octets) {
        $binary += [Convert]::ToString([int]$octet, 2).PadLeft(8, '0')
    }
    return ($binary.ToCharArray() | Where-Object { $_ -eq '1' }).Count
}

function Get-NetworkAddress {
    <#
    .SYNOPSIS
        Calculates network address from IP and prefix.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IPAddress,

        [Parameter(Mandatory)]
        [int]$PrefixLength
    )

    $ipBytes = [System.Net.IPAddress]::Parse($IPAddress).GetAddressBytes()
    $maskBits = ('1' * $PrefixLength).PadRight(32, '0')
    $maskBytes = @()
    for ($i = 0; $i -lt 4; $i++) {
        $maskBytes += [Convert]::ToByte($maskBits.Substring($i * 8, 8), 2)
    }

    $networkBytes = @()
    for ($i = 0; $i -lt 4; $i++) {
        $networkBytes += ($ipBytes[$i] -band $maskBytes[$i])
    }

    return ($networkBytes -join '.')
}

function Get-SubnetGroups {
    <#
    .SYNOPSIS
        Groups nodes by their subnet membership for L3 view.
    #>
    [CmdletBinding()]
    param(
        [string]$VRF = 'default'
    )

    $nodes = @(Get-TopologyNode)
    $subnetGroups = @{}

    foreach ($node in $nodes) {
        $l3Interfaces = Get-L3Interfaces -NodeID $node.NodeID
        foreach ($iface in $l3Interfaces) {
            if ($iface.VRF -ne $VRF -and $VRF -ne '*') { continue }

            $subnet = $iface.CIDR
            if (-not $subnetGroups.ContainsKey($subnet)) {
                $subnetGroups[$subnet] = @{
                    CIDR           = $subnet
                    NetworkAddress = $iface.NetworkAddress
                    PrefixLength   = $iface.PrefixLength
                    VRF            = $iface.VRF
                    Nodes          = [System.Collections.ArrayList]::new()
                    Gateways       = [System.Collections.ArrayList]::new()
                }
            }

            [void]$subnetGroups[$subnet].Nodes.Add(@{
                Node      = $node
                Interface = $iface
            })

            if ($iface.IsGateway) {
                [void]$subnetGroups[$subnet].Gateways.Add($node)
            }
        }
    }

    return $subnetGroups
}

function Get-L3Links {
    <#
    .SYNOPSIS
        Gets L3 routing links between nodes (through shared subnets).
    #>
    [CmdletBinding()]
    param()

    $subnetGroups = Get-SubnetGroups -VRF '*'
    $l3Links = [System.Collections.ArrayList]::new()

    foreach ($subnet in $subnetGroups.Values) {
        $nodesInSubnet = @($subnet.Nodes)

        # Create links between all nodes in same subnet
        for ($i = 0; $i -lt $nodesInSubnet.Count; $i++) {
            for ($j = $i + 1; $j -lt $nodesInSubnet.Count; $j++) {
                $nodeA = $nodesInSubnet[$i]
                $nodeB = $nodesInSubnet[$j]

                [void]$l3Links.Add([PSCustomObject]@{
                    SourceNodeID  = $nodeA.Node.NodeID
                    SourceIP      = $nodeA.Interface.IPAddress
                    DestNodeID    = $nodeB.Node.NodeID
                    DestIP        = $nodeB.Interface.IPAddress
                    Subnet        = $subnet.CIDR
                    VRF           = $subnet.VRF
                })
            }
        }
    }

    return $l3Links
}

function Set-SubnetGroupLayout {
    <#
    .SYNOPSIS
        Applies layout that groups nodes by subnet.
    #>
    [CmdletBinding()]
    param(
        [double]$Width = 800,
        [double]$Height = 600,
        [double]$SubnetSpacing = 200,
        [double]$NodeSpacing = 80
    )

    $subnetGroups = Get-SubnetGroups -VRF '*'
    if ($subnetGroups.Count -eq 0) { return }

    $subnets = @($subnetGroups.Values)
    $cols = [math]::Ceiling([math]::Sqrt($subnets.Count))

    $subnetIndex = 0
    foreach ($subnet in $subnets) {
        $col = $subnetIndex % $cols
        $row = [math]::Floor($subnetIndex / $cols)

        $baseX = 100 + ($col * $SubnetSpacing)
        $baseY = 100 + ($row * $SubnetSpacing)

        # Position nodes within subnet group
        $nodeIndex = 0
        foreach ($entry in $subnet.Nodes) {
            $node = $entry.Node
            $localCol = $nodeIndex % 3
            $localRow = [math]::Floor($nodeIndex / 3)

            $node.XPosition = $baseX + ($localCol * $NodeSpacing)
            $node.YPosition = $baseY + ($localRow * $NodeSpacing)
            $nodeIndex++
        }

        $subnetIndex++
    }
}

function Get-RoutingProtocolTopology {
    <#
    .SYNOPSIS
        Gets nodes grouped by routing protocol (OSPF areas, EIGRP AS).
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('OSPF', 'EIGRP', 'BGP', 'All')]
        [string]$Protocol = 'All'
    )

    $nodes = @(Get-TopologyNode)
    $protocolGroups = @{}

    foreach ($node in $nodes) {
        $l3Interfaces = Get-L3Interfaces -NodeID $node.NodeID

        foreach ($iface in $l3Interfaces) {
            $key = $null

            if (($Protocol -eq 'All' -or $Protocol -eq 'OSPF') -and $iface.OSPFArea) {
                $key = "OSPF-Area-$($iface.OSPFArea)"
            }
            elseif (($Protocol -eq 'All' -or $Protocol -eq 'EIGRP') -and $iface.EIGRPAS) {
                $key = "EIGRP-AS-$($iface.EIGRPAS)"
            }

            if ($key) {
                if (-not $protocolGroups.ContainsKey($key)) {
                    $protocolGroups[$key] = [System.Collections.ArrayList]::new()
                }
                if ($protocolGroups[$key] -notcontains $node) {
                    [void]$protocolGroups[$key].Add($node)
                }
            }
        }
    }

    return $protocolGroups
}

function Get-L3TopologyStatistics {
    <#
    .SYNOPSIS
        Gets L3 topology statistics.
    #>
    [CmdletBinding()]
    param()

    $nodes = @(Get-TopologyNode)
    $subnetGroups = Get-SubnetGroups -VRF '*'
    $l3Links = @(Get-L3Links)

    $nodesWithL3 = 0
    $totalInterfaces = 0
    $gatewayCount = 0
    $vrfs = @{}

    foreach ($node in $nodes) {
        $interfaces = @(Get-L3Interfaces -NodeID $node.NodeID)
        if ($interfaces.Count -gt 0) {
            $nodesWithL3++
            $totalInterfaces += $interfaces.Count
            foreach ($iface in $interfaces) {
                if ($iface.IsGateway) { $gatewayCount++ }
                if (-not $vrfs.ContainsKey($iface.VRF)) {
                    $vrfs[$iface.VRF] = 0
                }
                $vrfs[$iface.VRF]++
            }
        }
    }

    return [PSCustomObject]@{
        TotalNodes       = $nodes.Count
        NodesWithL3      = $nodesWithL3
        TotalSubnets     = $subnetGroups.Count
        TotalL3Links     = $l3Links.Count
        TotalInterfaces  = $totalInterfaces
        GatewayCount     = $gatewayCount
        VRFCount         = $vrfs.Count
        VRFBreakdown     = $vrfs
    }
}

#endregion

#region Visio Export

function Export-TopologyToVisio {
    <#
    .SYNOPSIS
        Exports topology to Visio-compatible VSDX format.
    .DESCRIPTION
        Generates a .vsdx file using Open Packaging Convention.
        The file can be opened in Microsoft Visio.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,

        [string]$Title = 'Network Topology',
        [double]$PageWidth = 11,
        [double]$PageHeight = 8.5
    )

    $nodes = @(Get-TopologyNode)
    $links = @(Get-TopologyLink)

    if ($nodes.Count -eq 0) {
        Write-Warning "No nodes to export"
        return $null
    }

    # Create temp directory for VSDX contents
    $tempDir = Join-Path $env:TEMP "visio_$([guid]::NewGuid().ToString('N'))"
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

    try {
        # Create required directories
        $visioDir = Join-Path $tempDir 'visio'
        $pagesDir = Join-Path $visioDir 'pages'
        $relsDir = Join-Path $tempDir '_rels'
        $visioRelsDir = Join-Path $visioDir '_rels'
        $pagesRelsDir = Join-Path $pagesDir '_rels'

        New-Item -Path $visioDir -ItemType Directory -Force | Out-Null
        New-Item -Path $pagesDir -ItemType Directory -Force | Out-Null
        New-Item -Path $relsDir -ItemType Directory -Force | Out-Null
        New-Item -Path $visioRelsDir -ItemType Directory -Force | Out-Null
        New-Item -Path $pagesRelsDir -ItemType Directory -Force | Out-Null

        # [Content_Types].xml
        $contentTypes = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/visio/document.xml" ContentType="application/vnd.ms-visio.drawing.main+xml"/>
  <Override PartName="/visio/pages/pages.xml" ContentType="application/vnd.ms-visio.pages+xml"/>
  <Override PartName="/visio/pages/page1.xml" ContentType="application/vnd.ms-visio.page+xml"/>
</Types>
"@
        $contentTypesPath = Join-Path $tempDir '[Content_Types].xml'
        $contentTypes | Out-File -LiteralPath $contentTypesPath -Encoding UTF8

        # _rels/.rels
        $rootRels = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.microsoft.com/visio/2010/relationships/document" Target="visio/document.xml"/>
</Relationships>
"@
        $rootRels | Out-File -FilePath (Join-Path $relsDir '.rels') -Encoding UTF8

        # visio/_rels/document.xml.rels
        $docRels = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.microsoft.com/visio/2010/relationships/pages" Target="pages/pages.xml"/>
</Relationships>
"@
        $docRels | Out-File -FilePath (Join-Path $visioRelsDir 'document.xml.rels') -Encoding UTF8

        # visio/document.xml
        $docXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<VisioDocument xmlns="http://schemas.microsoft.com/office/visio/2012/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <DocumentProperties>
    <Title>$Title</Title>
    <Creator>StateTrace</Creator>
    <Created>$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')</Created>
  </DocumentProperties>
</VisioDocument>
"@
        $docXml | Out-File -FilePath (Join-Path $visioDir 'document.xml') -Encoding UTF8

        # visio/pages/_rels/pages.xml.rels
        $pagesRels = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.microsoft.com/visio/2010/relationships/page" Target="page1.xml"/>
</Relationships>
"@
        $pagesRels | Out-File -FilePath (Join-Path $pagesRelsDir 'pages.xml.rels') -Encoding UTF8

        # visio/pages/pages.xml
        $pagesXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Pages xmlns="http://schemas.microsoft.com/office/visio/2012/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <Page ID="0" Name="Network Topology" NameU="Network Topology">
    <Rel r:id="rId1"/>
  </Page>
</Pages>
"@
        $pagesXml | Out-File -FilePath (Join-Path $pagesDir 'pages.xml') -Encoding UTF8

        # Build shapes XML
        $shapeId = 1
        $shapesXml = [System.Text.StringBuilder]::new()

        # Scale factor (convert from pixels to inches)
        $scale = 0.01

        # Add node shapes
        foreach ($node in $nodes) {
            $x = $node.XPosition * $scale
            $y = ($PageHeight - ($node.YPosition * $scale))  # Flip Y axis

            $fillColor = switch ($node.Role) {
                'Core' { '#FF6666' }
                'Distribution' { '#FFB366' }
                'Access' { '#66B366' }
                'Router' { '#B366FF' }
                'Firewall' { '#FF3333' }
                default { '#4A90D9' }
            }

            [void]$shapesXml.AppendLine(@"
    <Shape ID="$shapeId" Type="Shape" Name="$($node.DisplayName)">
      <Cell N="PinX" V="$x"/>
      <Cell N="PinY" V="$y"/>
      <Cell N="Width" V="0.75"/>
      <Cell N="Height" V="0.5"/>
      <Cell N="FillForegnd" V="$fillColor"/>
      <Text>$($node.DisplayName)</Text>
    </Shape>
"@)
            $shapeId++
        }

        # Add link connectors
        $nodeIndex = @{}
        $idx = 1
        foreach ($node in $nodes) {
            $nodeIndex[$node.NodeID] = $idx
            $idx++
        }

        foreach ($link in $links) {
            $sourceIdx = $nodeIndex[$link.SourceNodeID]
            $destIdx = $nodeIndex[$link.DestNodeID]

            if ($sourceIdx -and $destIdx) {
                $strokeColor = if ($link.LinkType -eq 'WAN') { '#FF0000' } else { '#666666' }
                $strokePattern = if ($link.LinkType -eq 'WAN') { '2' } else { '0' }

                [void]$shapesXml.AppendLine(@"
    <Shape ID="$shapeId" Type="Shape" Name="Connector">
      <Cell N="BeginX" V="0"/>
      <Cell N="BeginY" V="0"/>
      <Cell N="EndX" V="1"/>
      <Cell N="EndY" V="1"/>
      <Cell N="LineColor" V="$strokeColor"/>
      <Cell N="LinePattern" V="$strokePattern"/>
      <Connect FromSheet="$shapeId" FromCell="BeginX" ToSheet="$sourceIdx" ToCell="PinX"/>
      <Connect FromSheet="$shapeId" FromCell="EndX" ToSheet="$destIdx" ToCell="PinX"/>
    </Shape>
"@)
                $shapeId++
            }
        }

        # visio/pages/page1.xml
        $pageXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<PageContents xmlns="http://schemas.microsoft.com/office/visio/2012/main">
  <Shapes>
$($shapesXml.ToString())
  </Shapes>
</PageContents>
"@
        $pageXml | Out-File -FilePath (Join-Path $pagesDir 'page1.xml') -Encoding UTF8

        # Create ZIP archive as VSDX
        $zipPath = $OutputPath
        if (-not $zipPath.EndsWith('.vsdx')) {
            $zipPath = "$OutputPath.vsdx"
        }

        # Remove existing file
        if (Test-Path $zipPath) {
            Remove-Item $zipPath -Force
        }

        # Create ZIP
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $zipPath)

        return $zipPath
    }
    finally {
        # Cleanup temp directory
        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force
        }
    }
}

#endregion

#region Statistics

function Get-TopologyStatistics {
    <#
    .SYNOPSIS
        Gets topology statistics and metrics.
    #>
    [CmdletBinding()]
    param()

    $nodes = @(Get-TopologyNode)
    $links = @(Get-TopologyLink)

    # Count by role
    $roleBreakdown = $nodes | Group-Object -Property Role | ForEach-Object {
        [PSCustomObject]@{
            Role  = $_.Name
            Count = $_.Count
        }
    }

    # Count by type
    $linkTypeBreakdown = $links | Group-Object -Property LinkType | ForEach-Object {
        [PSCustomObject]@{
            LinkType = $_.Name
            Count    = $_.Count
        }
    }

    # Find nodes with no links (isolated)
    $isolatedNodes = @()
    foreach ($node in $nodes) {
        $nodeLinks = @(Get-TopologyLink -NodeID $node.NodeID)
        if ($nodeLinks.Count -eq 0) {
            $isolatedNodes += $node
        }
    }

    return [PSCustomObject]@{
        TotalNodes       = $nodes.Count
        TotalLinks       = $links.Count
        RoleBreakdown    = $roleBreakdown
        LinkTypeBreakdown = $linkTypeBreakdown
        IsolatedNodes    = $isolatedNodes.Count
        AverageLinks     = if ($nodes.Count -gt 0) { [math]::Round($links.Count * 2 / $nodes.Count, 2) } else { 0 }
    }
}

#endregion

# Export module members
Export-ModuleMember -Function @(
    # Node management
    'New-TopologyNode',
    'Get-TopologyNode',
    'Remove-TopologyNode',
    'Get-DeviceRole',

    # Link management
    'New-TopologyLink',
    'Get-TopologyLink',
    'Remove-TopologyLink',

    # Discovery
    'Find-LinksFromDescription',
    'New-TopologyFromInterfaces',
    'Clear-Topology',

    # Layout
    'Set-HierarchicalLayout',
    'Set-ForceDirectedLayout',
    'Set-CircularLayout',
    'Set-GridLayout',
    'Set-SubnetGroupLayout',

    # Impact analysis
    'Get-ImpactAnalysis',
    'Get-ConnectedNodes',

    # Export
    'Export-TopologyToSVG',
    'Export-TopologyToJSON',
    'Export-TopologyToDrawIO',
    'Export-TopologyToVisio',

    # Layout persistence
    'Save-TopologyLayout',
    'Get-TopologyLayout',
    'Restore-TopologyLayout',

    # Statistics
    'Get-TopologyStatistics',

    # L3 Topology
    'Add-L3Interface',
    'Get-L3Interfaces',
    'Get-SubnetGroups',
    'Get-L3Links',
    'Get-RoutingProtocolTopology',
    'Get-L3TopologyStatistics',
    'ConvertTo-PrefixLength',
    'Get-NetworkAddress'
)
