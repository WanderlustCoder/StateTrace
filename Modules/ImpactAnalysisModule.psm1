# ImpactAnalysisModule.psm1
# Network change impact analysis with dependency graphing

Set-StrictMode -Version Latest

$script:DependencyGraph = $null
$script:ServiceDefinitions = @{}
$script:LastGraphBuild = $null

#region Dependency Graph

function Build-DependencyGraph {
    <#
    .SYNOPSIS
    Builds a dependency graph from device inventory.
    .PARAMETER Devices
    Device objects to build graph from. If not provided, uses all loaded devices.
    .PARAMETER IncludeL3
    Include Layer 3 (routing) dependencies.
    .PARAMETER IncludeVLAN
    Include VLAN membership dependencies.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Devices,
        [switch]$IncludeL3,
        [switch]$IncludeVLAN
    )

    $projectRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $projectRoot 'Modules\DeviceRepositoryModule.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue

    if (-not $Devices) {
        try {
            $Devices = Get-AllDevices -ErrorAction SilentlyContinue
        } catch {
            $Devices = @()
        }
    }

    $graph = @{
        Nodes = @{}
        Edges = [System.Collections.Generic.List[object]]::new()
        VLANs = @{}
        Subnets = @{}
        BuildTime = [datetime]::UtcNow
        DeviceCount = @($Devices).Count
    }

    # Build nodes for each device
    foreach ($device in $Devices) {
        $nodeId = "device:$($device.Hostname)"
        
        $graph.Nodes[$nodeId] = @{
            Id = $nodeId
            Type = 'Device'
            Hostname = $device.Hostname
            Site = $device.Site
            Make = $device.Make
            Model = $device.Model
            Role = Get-DeviceRole -Device $device
            Interfaces = @{}
            Criticality = 'Normal'
        }

        # Add interface nodes
        foreach ($iface in $device.InterfacesCombined) {
            $ifaceId = "interface:$($device.Hostname):$($iface.Port)"
            
            $graph.Nodes[$nodeId].Interfaces[$iface.Port] = @{
                Id = $ifaceId
                Port = $iface.Port
                Name = $iface.Name
                Status = $iface.Status
                VLAN = $iface.VLAN
                Speed = $iface.Speed
                Type = $iface.Type
                Description = $iface.Description
            }

            # Track VLAN membership
            if ($IncludeVLAN -and $iface.VLAN -and $iface.VLAN -ne 'trunk') {
                $vlanId = "vlan:$($iface.VLAN)"
                if (-not $graph.VLANs.ContainsKey($vlanId)) {
                    $graph.VLANs[$vlanId] = @{
                        Id = $vlanId
                        VLANNumber = $iface.VLAN
                        Members = [System.Collections.Generic.List[string]]::new()
                    }
                }
                [void]$graph.VLANs[$vlanId].Members.Add($ifaceId)
            }
        }
    }

    # Build edges based on connections
    # Look for matching interface descriptions, CDP/LLDP neighbors, trunk links
    foreach ($device in $Devices) {
        $sourceNode = "device:$($device.Hostname)"

        foreach ($iface in $device.InterfacesCombined) {
            # Check for neighbor information in description
            if ($iface.Description) {
                $neighborMatch = Find-NeighborFromDescription -Description $iface.Description -Devices $Devices
                if ($neighborMatch) {
                    $edge = @{
                        Source = $sourceNode
                        Target = "device:$($neighborMatch.Hostname)"
                        SourceInterface = $iface.Port
                        TargetInterface = $neighborMatch.Interface
                        Type = 'Physical'
                        Status = $iface.Status
                    }
                    [void]$graph.Edges.Add($edge)
                }
            }

            # Check for uplink patterns
            if ($iface.Port -match 'uplink|trunk|port-channel|lag' -or $iface.Name -match 'uplink|trunk') {
                $graph.Nodes[$sourceNode].Interfaces[$iface.Port].IsUplink = $true
            }
        }

        # Add L3 dependencies from routing table
        if ($IncludeL3 -and $device.RoutingTable) {
            foreach ($route in $device.RoutingTable) {
                if ($route.NextHop -and $route.NextHop -ne 'directly connected') {
                    $nextHopDevice = Find-DeviceByIP -IP $route.NextHop -Devices $Devices
                    if ($nextHopDevice) {
                        $edge = @{
                            Source = $sourceNode
                            Target = "device:$($nextHopDevice.Hostname)"
                            Type = 'L3Route'
                            Subnet = $route.Network
                            NextHop = $route.NextHop
                        }
                        [void]$graph.Edges.Add($edge)

                        # Track subnet
                        $subnetId = "subnet:$($route.Network)"
                        if (-not $graph.Subnets.ContainsKey($subnetId)) {
                            $graph.Subnets[$subnetId] = @{
                                Id = $subnetId
                                Network = $route.Network
                                Devices = [System.Collections.Generic.List[string]]::new()
                            }
                        }
                        if ($graph.Subnets[$subnetId].Devices -notcontains $sourceNode) {
                            [void]$graph.Subnets[$subnetId].Devices.Add($sourceNode)
                        }
                    }
                }
            }
        }
    }

    # Identify critical nodes (high connectivity)
    foreach ($nodeId in $graph.Nodes.Keys) {
        $node = $graph.Nodes[$nodeId]
        $edgeCount = @($graph.Edges | Where-Object { $_.Source -eq $nodeId -or $_.Target -eq $nodeId }).Count
        
        if ($edgeCount -ge 10) {
            $node.Criticality = 'Critical'
        } elseif ($edgeCount -ge 5) {
            $node.Criticality = 'High'
        } elseif ($edgeCount -ge 2) {
            $node.Criticality = 'Medium'
        }
    }

    $script:DependencyGraph = $graph
    $script:LastGraphBuild = [datetime]::UtcNow

    Write-Verbose "[ImpactAnalysis] Built graph: $($graph.Nodes.Count) nodes, $($graph.Edges.Count) edges"

    return $graph
}

function Get-DeviceRole {
    param([object]$Device)

    $hostname = $Device.Hostname.ToLower()
    $model = if ($Device.Model) { $Device.Model.ToLower() } else { '' }

    if ($hostname -match 'core|spine|dc-') { return 'Core' }
    if ($hostname -match 'dist|aggregation|agg') { return 'Distribution' }
    if ($hostname -match 'access|edge|sw-') { return 'Access' }
    if ($hostname -match 'fw|firewall|asa|palo') { return 'Firewall' }
    if ($hostname -match 'rtr|router|rt-') { return 'Router' }
    if ($hostname -match 'wlc|wifi|ap-') { return 'Wireless' }
    if ($model -match 'nexus 9|catalyst 9[56]') { return 'Core' }
    if ($model -match 'nexus 5|catalyst 38|catalyst 29') { return 'Access' }

    return 'Unknown'
}

function Find-NeighborFromDescription {
    param(
        [string]$Description,
        [object[]]$Devices
    )

    # Look for hostname patterns in description
    foreach ($device in $Devices) {
        if ($Description -match $device.Hostname) {
            # Try to find interface reference
            if ($Description -match '(Gi|Te|Eth|Po|Fa)\d+(/\d+)*') {
                return @{
                    Hostname = $device.Hostname
                    Interface = $Matches[0]
                }
            }
            return @{
                Hostname = $device.Hostname
                Interface = $null
            }
        }
    }

    return $null
}

function Find-DeviceByIP {
    param(
        [string]$IP,
        [object[]]$Devices
    )

    foreach ($device in $Devices) {
        foreach ($iface in $device.InterfacesCombined) {
            if ($iface.IPAddress -eq $IP) {
                return $device
            }
        }
    }

    return $null
}

function Get-DependencyGraph {
    <#
    .SYNOPSIS
    Returns the current dependency graph.
    #>
    if (-not $script:DependencyGraph) {
        Build-DependencyGraph -IncludeL3 -IncludeVLAN | Out-Null
    }
    return $script:DependencyGraph
}

#endregion

#region Impact Analysis

function Get-ChangeImpact {
    <#
    .SYNOPSIS
    Analyzes the impact of a proposed change.
    .PARAMETER ChangeType
    Type of change: DeviceDown, InterfaceDown, VLANChange, MaintenanceWindow
    .PARAMETER Target
    Target of the change (hostname, interface, VLAN)
    .PARAMETER Duration
    Expected duration in minutes
    .PARAMETER IncludeServices
    Include service impact analysis
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DeviceDown', 'InterfaceDown', 'VLANChange', 'MaintenanceWindow', 'ConfigChange')]
        [string]$ChangeType,

        [Parameter(Mandatory)]
        [string]$Target,

        [string]$TargetInterface,

        [int]$Duration = 60,

        [switch]$IncludeServices
    )

    $graph = Get-DependencyGraph

    $impact = @{
        ChangeId = [guid]::NewGuid().ToString('N').Substring(0, 8)
        ChangeType = $ChangeType
        Target = $Target
        TargetInterface = $TargetInterface
        Duration = $Duration
        AnalyzedAt = [datetime]::UtcNow.ToString('o')
        DirectlyAffected = [System.Collections.Generic.List[object]]::new()
        IndirectlyAffected = [System.Collections.Generic.List[object]]::new()
        AffectedVLANs = [System.Collections.Generic.List[object]]::new()
        AffectedSubnets = [System.Collections.Generic.List[object]]::new()
        AffectedServices = [System.Collections.Generic.List[object]]::new()
        RiskLevel = 'Low'
        RiskScore = 0
        Recommendations = [System.Collections.Generic.List[string]]::new()
    }

    switch ($ChangeType) {
        'DeviceDown' {
            $nodeId = "device:$Target"
            if ($graph.Nodes.ContainsKey($nodeId)) {
                $node = $graph.Nodes[$nodeId]

                # Direct impact - the device itself
                [void]$impact.DirectlyAffected.Add(@{
                    Type = 'Device'
                    Name = $Target
                    Role = $node.Role
                    Criticality = $node.Criticality
                    InterfaceCount = $node.Interfaces.Count
                })

                # Find all connected devices (indirect impact)
                $connectedEdges = $graph.Edges | Where-Object { 
                    $_.Source -eq $nodeId -or $_.Target -eq $nodeId 
                }

                foreach ($edge in $connectedEdges) {
                    $connectedNodeId = if ($edge.Source -eq $nodeId) { $edge.Target } else { $edge.Source }
                    if ($graph.Nodes.ContainsKey($connectedNodeId)) {
                        $connectedNode = $graph.Nodes[$connectedNodeId]
                        [void]$impact.IndirectlyAffected.Add(@{
                            Type = 'Device'
                            Name = $connectedNode.Hostname
                            Role = $connectedNode.Role
                            ConnectionType = $edge.Type
                            Interface = if ($edge.Source -eq $nodeId) { $edge.TargetInterface } else { $edge.SourceInterface }
                        })
                    }
                }

                # Find affected VLANs
                foreach ($ifaceKey in $node.Interfaces.Keys) {
                    $iface = $node.Interfaces[$ifaceKey]
                    if ($iface.VLAN) {
                        $vlanId = "vlan:$($iface.VLAN)"
                        if ($graph.VLANs.ContainsKey($vlanId)) {
                            $vlan = $graph.VLANs[$vlanId]
                            $otherMembers = $vlan.Members | Where-Object { $_ -notlike "*:${Target}:*" }
                            [void]$impact.AffectedVLANs.Add(@{
                                VLAN = $iface.VLAN
                                TotalMembers = $vlan.Members.Count
                                RemainingMembers = @($otherMembers).Count
                            })
                        }
                    }
                }

                # Calculate risk based on role and connections
                $impact.RiskScore = Calculate-RiskScore -Node $node -ConnectedCount $connectedEdges.Count
            }
        }

        'InterfaceDown' {
            $nodeId = "device:$Target"
            if ($graph.Nodes.ContainsKey($nodeId)) {
                $node = $graph.Nodes[$nodeId]

                if ($node.Interfaces.ContainsKey($TargetInterface)) {
                    $iface = $node.Interfaces[$TargetInterface]

                    [void]$impact.DirectlyAffected.Add(@{
                        Type = 'Interface'
                        Device = $Target
                        Port = $TargetInterface
                        Name = $iface.Name
                        Status = $iface.Status
                        VLAN = $iface.VLAN
                        IsUplink = $iface.IsUplink
                    })

                    # Check if this is an uplink
                    if ($iface.IsUplink) {
                        $impact.RiskScore += 30
                        [void]$impact.Recommendations.Add("WARNING: This interface appears to be an uplink. Consider redundancy before proceeding.")
                    }

                    # Find connected device via this interface
                    $connectedEdge = $graph.Edges | Where-Object {
                        ($_.Source -eq $nodeId -and $_.SourceInterface -eq $TargetInterface) -or
                        ($_.Target -eq $nodeId -and $_.TargetInterface -eq $TargetInterface)
                    } | Select-Object -First 1

                    if ($connectedEdge) {
                        $connectedNodeId = if ($connectedEdge.Source -eq $nodeId) { $connectedEdge.Target } else { $connectedEdge.Source }
                        if ($graph.Nodes.ContainsKey($connectedNodeId)) {
                            $connectedNode = $graph.Nodes[$connectedNodeId]
                            [void]$impact.IndirectlyAffected.Add(@{
                                Type = 'Device'
                                Name = $connectedNode.Hostname
                                Role = $connectedNode.Role
                                ImpactType = 'Loss of connectivity via this link'
                            })
                        }
                    }

                    $impact.RiskScore = Calculate-RiskScore -Node $node -ConnectedCount 1 -IsInterface $true
                }
            }
        }

        'VLANChange' {
            $vlanId = "vlan:$Target"
            if ($graph.VLANs.ContainsKey($vlanId)) {
                $vlan = $graph.VLANs[$vlanId]

                [void]$impact.DirectlyAffected.Add(@{
                    Type = 'VLAN'
                    VLANNumber = $Target
                    MemberCount = $vlan.Members.Count
                })

                # All interfaces in this VLAN are affected
                foreach ($memberId in $vlan.Members) {
                    if ($memberId -match 'interface:([^:]+):(.+)') {
                        $hostname = $Matches[1]
                        $port = $Matches[2]
                        [void]$impact.IndirectlyAffected.Add(@{
                            Type = 'Interface'
                            Device = $hostname
                            Port = $port
                        })
                    }
                }

                $impact.RiskScore = [math]::Min($vlan.Members.Count * 5, 100)
            }
        }

        'MaintenanceWindow' {
            # Analyze multiple devices in maintenance window
            $targetDevices = $Target -split ','
            foreach ($deviceName in $targetDevices) {
                $deviceName = $deviceName.Trim()
                $subImpact = Get-ChangeImpact -ChangeType 'DeviceDown' -Target $deviceName -Duration $Duration
                
                foreach ($item in $subImpact.DirectlyAffected) {
                    [void]$impact.DirectlyAffected.Add($item)
                }
                foreach ($item in $subImpact.IndirectlyAffected) {
                    [void]$impact.IndirectlyAffected.Add($item)
                }
                $impact.RiskScore = [math]::Max($impact.RiskScore, $subImpact.RiskScore)
            }
        }
    }

    # Add service impact if requested
    if ($IncludeServices) {
        $serviceImpact = Get-ServiceImpact -AffectedDevices $impact.DirectlyAffected -AffectedInterfaces $impact.IndirectlyAffected
        $impact.AffectedServices = $serviceImpact
        
        foreach ($svc in $serviceImpact) {
            if ($svc.Criticality -eq 'Critical') {
                $impact.RiskScore += 25
            } elseif ($svc.Criticality -eq 'High') {
                $impact.RiskScore += 15
            }
        }
    }

    # Determine risk level
    $impact.RiskLevel = switch ($impact.RiskScore) {
        { $_ -ge 80 } { 'Critical' }
        { $_ -ge 60 } { 'High' }
        { $_ -ge 40 } { 'Medium' }
        { $_ -ge 20 } { 'Low' }
        default { 'Minimal' }
    }

    # Add recommendations
    Add-ImpactRecommendations -Impact $impact

    return [PSCustomObject]$impact
}

function Calculate-RiskScore {
    param(
        [object]$Node,
        [int]$ConnectedCount,
        [switch]$IsInterface
    )

    $score = 0

    # Base score from criticality
    $score += switch ($Node.Criticality) {
        'Critical' { 40 }
        'High' { 25 }
        'Medium' { 15 }
        default { 5 }
    }

    # Role-based scoring
    $score += switch ($Node.Role) {
        'Core' { 30 }
        'Distribution' { 20 }
        'Firewall' { 25 }
        'Router' { 15 }
        'Access' { 5 }
        default { 5 }
    }

    # Connection count impact
    $score += [math]::Min($ConnectedCount * 3, 30)

    # Interface changes are generally lower risk
    if ($IsInterface) {
        $score = [math]::Round($score * 0.4)
    }

    return [math]::Min($score, 100)
}

function Add-ImpactRecommendations {
    param([object]$Impact)

    if ($Impact.RiskLevel -eq 'Critical') {
        [void]$Impact.Recommendations.Add("CRITICAL: This change affects core infrastructure. Schedule during maintenance window with full team.")
        [void]$Impact.Recommendations.Add("Ensure rollback plan is documented and tested.")
        [void]$Impact.Recommendations.Add("Notify all stakeholders before proceeding.")
    }

    if ($Impact.RiskLevel -eq 'High') {
        [void]$Impact.Recommendations.Add("HIGH RISK: Consider scheduling during low-traffic period.")
        [void]$Impact.Recommendations.Add("Have rollback plan ready.")
    }

    if ($Impact.AffectedServices.Count -gt 0) {
        [void]$Impact.Recommendations.Add("Services will be impacted. Coordinate with application teams.")
    }

    if ($Impact.IndirectlyAffected.Count -gt 5) {
        [void]$Impact.Recommendations.Add("Multiple downstream devices affected. Consider phased approach.")
    }

    if ($Impact.Duration -gt 120) {
        [void]$Impact.Recommendations.Add("Extended outage window. Consider customer communication.")
    }
}

#endregion

#region Route Path Tracing

function Trace-RoutePath {
    <#
    .SYNOPSIS
    Traces the Layer 3 path between two endpoints.
    .PARAMETER SourceIP
    Source IP address or hostname.
    .PARAMETER DestinationIP
    Destination IP address or hostname.
    .PARAMETER MaxHops
    Maximum hops to trace.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceIP,

        [Parameter(Mandatory)]
        [string]$DestinationIP,

        [int]$MaxHops = 15
    )

    $graph = Get-DependencyGraph

    $projectRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $projectRoot 'Modules\DeviceRepositoryModule.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue

    $trace = @{
        TraceId = [guid]::NewGuid().ToString('N').Substring(0, 8)
        Source = $SourceIP
        Destination = $DestinationIP
        StartTime = [datetime]::UtcNow.ToString('o')
        Hops = [System.Collections.Generic.List[object]]::new()
        Status = 'Unknown'
        PathComplete = $false
    }

    try {
        $devices = Get-AllDevices -ErrorAction SilentlyContinue

        # Find source device
        $currentDevice = $null
        $currentIP = $SourceIP

        foreach ($device in $devices) {
            foreach ($iface in $device.InterfacesCombined) {
                if ($iface.IPAddress -eq $SourceIP) {
                    $currentDevice = $device
                    break
                }
            }
            if ($currentDevice) { break }
        }

        if (-not $currentDevice) {
            # Try to find device by hostname
            $currentDevice = $devices | Where-Object { $_.Hostname -eq $SourceIP } | Select-Object -First 1
        }

        $hopCount = 0
        $visited = @{}

        while ($currentDevice -and $hopCount -lt $MaxHops) {
            $hopCount++

            # Check if we've reached destination
            $atDestination = $false
            foreach ($iface in $currentDevice.InterfacesCombined) {
                if ($iface.IPAddress -eq $DestinationIP) {
                    $atDestination = $true
                    break
                }
            }

            $hop = @{
                Hop = $hopCount
                Device = $currentDevice.Hostname
                Site = $currentDevice.Site
                Make = $currentDevice.Make
                Role = Get-DeviceRole -Device $currentDevice
                IngressInterface = $null
                EgressInterface = $null
                NextHop = $null
            }

            if ($atDestination) {
                $hop.Status = 'Destination'
                [void]$trace.Hops.Add($hop)
                $trace.Status = 'Complete'
                $trace.PathComplete = $true
                break
            }

            # Prevent loops
            if ($visited.ContainsKey($currentDevice.Hostname)) {
                $hop.Status = 'Loop Detected'
                [void]$trace.Hops.Add($hop)
                $trace.Status = 'Loop'
                break
            }
            $visited[$currentDevice.Hostname] = $true

            # Find route to destination
            $nextHop = $null
            $egressInterface = $null

            if ($currentDevice.RoutingTable) {
                foreach ($route in $currentDevice.RoutingTable) {
                    if (Test-IPInSubnet -IP $DestinationIP -Subnet $route.Network) {
                        if ($route.NextHop -and $route.NextHop -ne 'directly connected') {
                            $nextHop = $route.NextHop
                            $egressInterface = $route.Interface
                            break
                        }
                    }
                }
            }

            $hop.EgressInterface = $egressInterface
            $hop.NextHop = $nextHop
            $hop.Status = 'Transit'

            [void]$trace.Hops.Add($hop)

            if (-not $nextHop) {
                $trace.Status = 'NoRoute'
                break
            }

            # Find next hop device
            $nextDevice = Find-DeviceByIP -IP $nextHop -Devices $devices
            if (-not $nextDevice) {
                $trace.Status = 'NextHopUnreachable'
                break
            }

            $currentDevice = $nextDevice
        }

        if ($hopCount -ge $MaxHops -and -not $trace.PathComplete) {
            $trace.Status = 'MaxHopsExceeded'
        }

    } catch {
        $trace.Status = 'Error'
        $trace.Error = $_.Exception.Message
    }

    $trace.EndTime = [datetime]::UtcNow.ToString('o')
    $trace.HopCount = $trace.Hops.Count

    return [PSCustomObject]$trace
}

function Test-IPInSubnet {
    param(
        [string]$IP,
        [string]$Subnet
    )

    try {
        if ($Subnet -match '^(\d+\.\d+\.\d+\.\d+)/(\d+)$') {
            $networkIP = $Matches[1]
            $prefix = [int]$Matches[2]
            
            $ipBytes = [System.Net.IPAddress]::Parse($IP).GetAddressBytes()
            $netBytes = [System.Net.IPAddress]::Parse($networkIP).GetAddressBytes()
            
            [Array]::Reverse($ipBytes)
            [Array]::Reverse($netBytes)
            
            $ipInt = [BitConverter]::ToUInt32($ipBytes, 0)
            $netInt = [BitConverter]::ToUInt32($netBytes, 0)
            $mask = [uint32]::MaxValue -shl (32 - $prefix)
            
            return ($ipInt -band $mask) -eq ($netInt -band $mask)
        }
    } catch {
        return $false
    }

    return $false
}

#endregion

#region Service Dependencies

function New-ServiceDefinition {
    <#
    .SYNOPSIS
    Creates a new service definition with critical dependencies.
    .PARAMETER Name
    Service name.
    .PARAMETER Description
    Service description.
    .PARAMETER Criticality
    Service criticality: Critical, High, Medium, Low
    .PARAMETER Dependencies
    Array of dependency objects with Type (Device/Interface/VLAN) and Target
    .PARAMETER Owner
    Service owner/team
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Description,

        [ValidateSet('Critical', 'High', 'Medium', 'Low')]
        [string]$Criticality = 'Medium',

        [object[]]$Dependencies,

        [string]$Owner
    )

    $serviceId = $Name.ToLower() -replace '\s+', '-'

    $service = @{
        Id = $serviceId
        Name = $Name
        Description = $Description
        Criticality = $Criticality
        Dependencies = $Dependencies
        Owner = $Owner
        CreatedAt = [datetime]::UtcNow.ToString('o')
    }

    $script:ServiceDefinitions[$serviceId] = $service

    # Persist to file
    Save-ServiceDefinitions

    return [PSCustomObject]$service
}

function Get-ServiceDefinition {
    <#
    .SYNOPSIS
    Gets service definitions.
    .PARAMETER Name
    Optional service name filter.
    #>
    [CmdletBinding()]
    param(
        [string]$Name
    )

    Load-ServiceDefinitions

    if ($Name) {
        $serviceId = $Name.ToLower() -replace '\s+', '-'
        if ($script:ServiceDefinitions.ContainsKey($serviceId)) {
            return [PSCustomObject]$script:ServiceDefinitions[$serviceId]
        }
        return $null
    }

    return $script:ServiceDefinitions.Values | ForEach-Object { [PSCustomObject]$_ }
}

function Remove-ServiceDefinition {
    <#
    .SYNOPSIS
    Removes a service definition.
    .PARAMETER Name
    Service name to remove.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $serviceId = $Name.ToLower() -replace '\s+', '-'
    
    if ($script:ServiceDefinitions.ContainsKey($serviceId)) {
        $script:ServiceDefinitions.Remove($serviceId)
        Save-ServiceDefinitions
        return $true
    }

    return $false
}

function Get-ServiceImpact {
    <#
    .SYNOPSIS
    Determines which services are impacted by affected devices/interfaces.
    #>
    param(
        [object[]]$AffectedDevices,
        [object[]]$AffectedInterfaces
    )

    Load-ServiceDefinitions

    $impactedServices = [System.Collections.Generic.List[object]]::new()

    foreach ($serviceId in $script:ServiceDefinitions.Keys) {
        $service = $script:ServiceDefinitions[$serviceId]
        $isImpacted = $false
        $impactedDeps = @()

        foreach ($dep in $service.Dependencies) {
            switch ($dep.Type) {
                'Device' {
                    $affected = $AffectedDevices | Where-Object { $_.Name -eq $dep.Target }
                    if ($affected) {
                        $isImpacted = $true
                        $impactedDeps += $dep
                    }
                }
                'Interface' {
                    $affected = $AffectedInterfaces | Where-Object { 
                        $_.Device -eq $dep.Target -or 
                        ("$($_.Device):$($_.Port)" -eq $dep.Target)
                    }
                    if ($affected) {
                        $isImpacted = $true
                        $impactedDeps += $dep
                    }
                }
            }
        }

        if ($isImpacted) {
            [void]$impactedServices.Add(@{
                ServiceId = $serviceId
                ServiceName = $service.Name
                Criticality = $service.Criticality
                Owner = $service.Owner
                ImpactedDependencies = $impactedDeps
            })
        }
    }

    return $impactedServices
}

function Save-ServiceDefinitions {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $configPath = Join-Path $projectRoot 'Data\ServiceDefinitions.json'

    $script:ServiceDefinitions | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Encoding UTF8
}

function Load-ServiceDefinitions {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $configPath = Join-Path $projectRoot 'Data\ServiceDefinitions.json'

    if (Test-Path $configPath) {
        try {
            $loaded = Get-Content -Path $configPath -Raw | ConvertFrom-Json -AsHashtable
            if ($loaded) {
                $script:ServiceDefinitions = $loaded
            }
        } catch {
            Write-Verbose "[ImpactAnalysis] Failed to load service definitions: $_"
        }
    }
}

#endregion

#region Pre-Change Verification

function New-ChangeRequest {
    <#
    .SYNOPSIS
    Creates a new change request with impact analysis.
    .PARAMETER Title
    Change request title.
    .PARAMETER Description
    Change description.
    .PARAMETER ChangeType
    Type of change.
    .PARAMETER Target
    Target device/interface/VLAN.
    .PARAMETER ScheduledStart
    Scheduled start time.
    .PARAMETER Duration
    Expected duration in minutes.
    .PARAMETER Requestor
    Person requesting the change.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [string]$Description,

        [Parameter(Mandatory)]
        [ValidateSet('DeviceDown', 'InterfaceDown', 'VLANChange', 'MaintenanceWindow', 'ConfigChange')]
        [string]$ChangeType,

        [Parameter(Mandatory)]
        [string]$Target,

        [string]$TargetInterface,

        [datetime]$ScheduledStart,

        [int]$Duration = 60,

        [string]$Requestor
    )

    # Run impact analysis
    $impactParams = @{
        ChangeType = $ChangeType
        Target = $Target
        Duration = $Duration
        IncludeServices = $true
    }
    if ($TargetInterface) {
        $impactParams.TargetInterface = $TargetInterface
    }

    $impact = Get-ChangeImpact @impactParams

    $changeRequest = @{
        Id = "CR-$(Get-Date -Format 'yyyyMMdd')-$([guid]::NewGuid().ToString('N').Substring(0, 4).ToUpper())"
        Title = $Title
        Description = $Description
        ChangeType = $ChangeType
        Target = $Target
        TargetInterface = $TargetInterface
        ScheduledStart = if ($ScheduledStart) { $ScheduledStart.ToString('o') } else { $null }
        Duration = $Duration
        Requestor = $Requestor
        CreatedAt = [datetime]::UtcNow.ToString('o')
        Status = 'PendingApproval'
        Impact = $impact
        Approvals = @()
        RequiresApproval = $impact.RiskLevel -in @('High', 'Critical')
    }

    # Save change request
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $crPath = Join-Path $projectRoot 'Data\ChangeRequests'
    if (-not (Test-Path $crPath)) {
        New-Item -Path $crPath -ItemType Directory -Force | Out-Null
    }

    $crFile = Join-Path $crPath "$($changeRequest.Id).json"
    $changeRequest | ConvertTo-Json -Depth 10 | Set-Content -Path $crFile -Encoding UTF8

    # Log audit event
    try {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $projectRoot 'Modules\AuditTrailModule.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue
        Write-AuditEvent -EventType 'ConfigChange' -Category 'System' -Action 'Create' `
            -Target $changeRequest.Id -Details "Change request: $Title" -Result 'Success'
    } catch { }

    return [PSCustomObject]$changeRequest
}

function Get-ChangeRequest {
    <#
    .SYNOPSIS
    Gets change requests.
    .PARAMETER Id
    Optional change request ID.
    .PARAMETER Status
    Filter by status.
    #>
    [CmdletBinding()]
    param(
        [string]$Id,
        [string]$Status
    )

    $projectRoot = Split-Path -Parent $PSScriptRoot
    $crPath = Join-Path $projectRoot 'Data\ChangeRequests'

    if (-not (Test-Path $crPath)) {
        return @()
    }

    $requests = @()

    if ($Id) {
        $crFile = Join-Path $crPath "$Id.json"
        if (Test-Path $crFile) {
            $requests = @(Get-Content -Path $crFile -Raw | ConvertFrom-Json)
        }
    } else {
        $crFiles = Get-ChildItem -Path $crPath -Filter '*.json' -ErrorAction SilentlyContinue
        foreach ($file in $crFiles) {
            $cr = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
            $requests += $cr
        }
    }

    if ($Status) {
        $requests = $requests | Where-Object { $_.Status -eq $Status }
    }

    return $requests | Sort-Object CreatedAt -Descending
}

function Approve-ChangeRequest {
    <#
    .SYNOPSIS
    Approves a change request.
    .PARAMETER Id
    Change request ID.
    .PARAMETER Approver
    Person approving the change.
    .PARAMETER Comments
    Approval comments.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [string]$Approver,

        [string]$Comments
    )

    $projectRoot = Split-Path -Parent $PSScriptRoot
    $crFile = Join-Path $projectRoot "Data\ChangeRequests\$Id.json"

    if (-not (Test-Path $crFile)) {
        throw "Change request not found: $Id"
    }

    $cr = Get-Content -Path $crFile -Raw | ConvertFrom-Json

    $approval = @{
        Approver = $Approver
        ApprovedAt = [datetime]::UtcNow.ToString('o')
        Comments = $Comments
    }

    $cr.Approvals += $approval
    $cr.Status = 'Approved'

    $cr | ConvertTo-Json -Depth 10 | Set-Content -Path $crFile -Encoding UTF8

    # Log audit event
    try {
        Import-Module (Join-Path $projectRoot 'Modules\AuditTrailModule.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue
        Write-AuditEvent -EventType 'ConfigChange' -Category 'System' -Action 'Update' `
            -Target $Id -Details "Approved by $Approver" -Result 'Success'
    } catch { }

    return $cr
}

function Complete-ChangeRequest {
    <#
    .SYNOPSIS
    Marks a change request as completed.
    .PARAMETER Id
    Change request ID.
    .PARAMETER Outcome
    Outcome: Success, PartialSuccess, Failed, RolledBack
    .PARAMETER Notes
    Completion notes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [ValidateSet('Success', 'PartialSuccess', 'Failed', 'RolledBack')]
        [string]$Outcome = 'Success',

        [string]$Notes
    )

    $projectRoot = Split-Path -Parent $PSScriptRoot
    $crFile = Join-Path $projectRoot "Data\ChangeRequests\$Id.json"

    if (-not (Test-Path $crFile)) {
        throw "Change request not found: $Id"
    }

    $cr = Get-Content -Path $crFile -Raw | ConvertFrom-Json

    $cr.Status = 'Completed'
    $cr | Add-Member -NotePropertyName 'CompletedAt' -NotePropertyValue ([datetime]::UtcNow.ToString('o')) -Force
    $cr | Add-Member -NotePropertyName 'Outcome' -NotePropertyValue $Outcome -Force
    $cr | Add-Member -NotePropertyName 'CompletionNotes' -NotePropertyValue $Notes -Force

    $cr | ConvertTo-Json -Depth 10 | Set-Content -Path $crFile -Encoding UTF8

    return $cr
}

#endregion

Export-ModuleMember -Function @(
    # Dependency Graph
    'Build-DependencyGraph',
    'Get-DependencyGraph',
    # Impact Analysis
    'Get-ChangeImpact',
    # Route Tracing
    'Trace-RoutePath',
    # Service Dependencies
    'New-ServiceDefinition',
    'Get-ServiceDefinition',
    'Remove-ServiceDefinition',
    'Get-ServiceImpact',
    # Change Requests
    'New-ChangeRequest',
    'Get-ChangeRequest',
    'Approve-ChangeRequest',
    'Complete-ChangeRequest'
)
