#Requires -Version 5.1
# Pester 3.x tests for TopologyModule

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$moduleRoot = Split-Path -Parent $here
Import-Module (Join-Path $moduleRoot 'TopologyModule.psm1') -Force

Describe 'TopologyModule' -Tag 'Topology' {

    BeforeEach {
        # Clear topology before each test
        Clear-Topology
    }

    Context 'Node Management' {

        It 'creates a new topology node' {
            $node = New-TopologyNode -DeviceID 'SW-01'

            $node | Should Not BeNullOrEmpty
            $node.DeviceID | Should Be 'SW-01'
            $node.NodeID | Should Not BeNullOrEmpty
        }

        It 'auto-assigns display name from device ID' {
            $node = New-TopologyNode -DeviceID 'CORE-01'

            $node.DisplayName | Should Be 'CORE-01'
        }

        It 'allows custom display name' {
            $node = New-TopologyNode -DeviceID 'SW-01' -DisplayName 'Main Switch'

            $node.DisplayName | Should Be 'Main Switch'
        }

        It 'auto-detects Core role from device name' {
            $node = New-TopologyNode -DeviceID 'CORE-01'

            $node.Role | Should Be 'Core'
        }

        It 'auto-detects Distribution role from device name' {
            $node = New-TopologyNode -DeviceID 'DS-01'

            $node.Role | Should Be 'Distribution'
        }

        It 'auto-detects Access role from device name' {
            $node = New-TopologyNode -DeviceID 'SW-ACCESS-01'

            $node.Role | Should Be 'Access'
        }

        It 'auto-detects Router role from device name' {
            $node = New-TopologyNode -DeviceID 'RTR-01'

            $node.Role | Should Be 'Router'
        }

        It 'auto-detects Firewall role from device name' {
            $node = New-TopologyNode -DeviceID 'FW-EDGE-01'

            $node.Role | Should Be 'Firewall'
        }

        It 'retrieves nodes by DeviceID' {
            New-TopologyNode -DeviceID 'SW-01' | Out-Null
            New-TopologyNode -DeviceID 'SW-02' | Out-Null

            $node = Get-TopologyNode -DeviceID 'SW-01'

            $node.DeviceID | Should Be 'SW-01'
        }

        It 'retrieves nodes by Role' {
            New-TopologyNode -DeviceID 'CORE-01' | Out-Null
            New-TopologyNode -DeviceID 'SW-01' | Out-Null

            $cores = @(Get-TopologyNode -Role 'Core')

            $cores.Count | Should Be 1
            $cores[0].DeviceID | Should Be 'CORE-01'
        }

        It 'removes a node and its links' {
            $node1 = New-TopologyNode -DeviceID 'SW-01'
            $node2 = New-TopologyNode -DeviceID 'SW-02'
            New-TopologyLink -SourceNodeID $node1.NodeID -DestNodeID $node2.NodeID | Out-Null

            $result = Remove-TopologyNode -NodeID $node1.NodeID

            $result | Should Be $true
            $remaining = @(Get-TopologyNode)
            $remaining.Count | Should Be 1
            $links = @(Get-TopologyLink)
            $links.Count | Should Be 0
        }
    }

    Context 'Link Management' {

        It 'creates a link between two nodes' {
            $node1 = New-TopologyNode -DeviceID 'SW-01'
            $node2 = New-TopologyNode -DeviceID 'SW-02'

            $link = New-TopologyLink -SourceNodeID $node1.NodeID -DestNodeID $node2.NodeID

            $link | Should Not BeNullOrEmpty
            $link.SourceNodeID | Should Be $node1.NodeID
            $link.DestNodeID | Should Be $node2.NodeID
        }

        It 'includes port information in links' {
            $node1 = New-TopologyNode -DeviceID 'SW-01'
            $node2 = New-TopologyNode -DeviceID 'SW-02'

            $link = New-TopologyLink -SourceNodeID $node1.NodeID -SourcePort 'Gi1/0/1' `
                -DestNodeID $node2.NodeID -DestPort 'Gi1/0/48'

            $link.SourcePort | Should Be 'Gi1/0/1'
            $link.DestPort | Should Be 'Gi1/0/48'
        }

        It 'prevents duplicate links' {
            $node1 = New-TopologyNode -DeviceID 'SW-01'
            $node2 = New-TopologyNode -DeviceID 'SW-02'
            New-TopologyLink -SourceNodeID $node1.NodeID -DestNodeID $node2.NodeID | Out-Null

            $duplicate = New-TopologyLink -SourceNodeID $node1.NodeID -DestNodeID $node2.NodeID

            $allLinks = @(Get-TopologyLink)
            $allLinks.Count | Should Be 1
        }

        It 'retrieves links by node ID' {
            $node1 = New-TopologyNode -DeviceID 'SW-01'
            $node2 = New-TopologyNode -DeviceID 'SW-02'
            $node3 = New-TopologyNode -DeviceID 'SW-03'
            New-TopologyLink -SourceNodeID $node1.NodeID -DestNodeID $node2.NodeID | Out-Null
            New-TopologyLink -SourceNodeID $node1.NodeID -DestNodeID $node3.NodeID | Out-Null

            $links = Get-TopologyLink -NodeID $node1.NodeID

            $links.Count | Should Be 2
        }

        It 'removes a link by ID' {
            $node1 = New-TopologyNode -DeviceID 'SW-01'
            $node2 = New-TopologyNode -DeviceID 'SW-02'
            $link = New-TopologyLink -SourceNodeID $node1.NodeID -DestNodeID $node2.NodeID

            $result = Remove-TopologyLink -LinkID $link.LinkID

            $result | Should Be $true
            $remaining = Get-TopologyLink
            $remaining.Count | Should Be 0
        }

        It 'supports WAN link type' {
            $node1 = New-TopologyNode -DeviceID 'RTR-01'
            $node2 = New-TopologyNode -DeviceID 'BRANCH-01'

            $link = New-TopologyLink -SourceNodeID $node1.NodeID -DestNodeID $node2.NodeID -LinkType 'WAN'

            $link.LinkType | Should Be 'WAN'
        }

        It 'supports aggregate links' {
            $node1 = New-TopologyNode -DeviceID 'SW-01'
            $node2 = New-TopologyNode -DeviceID 'SW-02'

            $link = New-TopologyLink -SourceNodeID $node1.NodeID -DestNodeID $node2.NodeID -IsAggregate $true

            $link.IsAggregate | Should Be $true
        }
    }

    Context 'Link Discovery' {

        It 'discovers link from "To DEVICE Port" description' {
            $result = Find-LinksFromDescription -SourceDevice 'SW-01' -SourcePort 'Gi1/0/1' `
                -Description 'To CORE-01 Gi1/0/48'

            $result | Should Not BeNullOrEmpty
            $result.DestDevice | Should Be 'CORE-01'
            $result.DestPort | Should Be 'Gi1/0/48'
        }

        It 'discovers link from "Uplink to DEVICE" description' {
            $result = Find-LinksFromDescription -SourceDevice 'SW-01' -SourcePort 'Te1/0/1' `
                -Description 'Uplink to DS-01'

            $result | Should Not BeNullOrEmpty
            $result.DestDevice | Should Be 'DS-01'
        }

        It 'discovers link from "Link to DEVICE" description' {
            $result = Find-LinksFromDescription -SourceDevice 'SW-01' -SourcePort 'Gi1/0/24' `
                -Description 'Link to SW-02 Gi1/0/24'

            $result | Should Not BeNullOrEmpty
            $result.DestDevice | Should Be 'SW-02'
            $result.DestPort | Should Be 'Gi1/0/24'
        }

        It 'discovers WAN link from description' {
            $result = Find-LinksFromDescription -SourceDevice 'RTR-01' -SourcePort 'Gi0/0' `
                -Description 'WAN to BRANCH-01'

            $result | Should Not BeNullOrEmpty
            $result.DestDevice | Should Be 'BRANCH-01'
            $result.IsWAN | Should Be $true
        }

        It 'discovers port-channel link from description' {
            $result = Find-LinksFromDescription -SourceDevice 'SW-01' -SourcePort 'Po1' `
                -Description 'Po1 - CORE-01'

            $result | Should Not BeNullOrEmpty
            $result.DestDevice | Should Be 'CORE-01'
            $result.PortChannel | Should Be 'Po1'
        }

        It 'returns null for non-link descriptions' {
            $result = Find-LinksFromDescription -SourceDevice 'SW-01' -SourcePort 'Gi1/0/1' `
                -Description 'User PC - John Doe'

            $result | Should BeNullOrEmpty
        }

        It 'returns null for empty descriptions' {
            $result = Find-LinksFromDescription -SourceDevice 'SW-01' -SourcePort 'Gi1/0/1' `
                -Description ''

            $result | Should BeNullOrEmpty
        }
    }

    Context 'Build Topology From Interfaces' {

        It 'creates nodes from interface data' {
            $interfaces = @(
                @{ Hostname = 'SW-01'; PortName = 'Gi1/0/1'; Description = '' },
                @{ Hostname = 'SW-02'; PortName = 'Gi1/0/1'; Description = '' }
            )

            $result = New-TopologyFromInterfaces -Interfaces $interfaces

            $result.NodesCreated | Should Be 2
            $nodes = Get-TopologyNode
            $nodes.Count | Should Be 2
        }

        It 'discovers and creates links from descriptions' {
            $interfaces = @(
                @{ Hostname = 'SW-01'; PortName = 'Gi1/0/48'; Description = 'To CORE-01 Gi1/0/1' },
                @{ Hostname = 'CORE-01'; PortName = 'Gi1/0/1'; Description = 'To SW-01 Gi1/0/48' }
            )

            $result = New-TopologyFromInterfaces -Interfaces $interfaces

            $result.LinksDiscovered | Should BeGreaterThan 0
            $links = @(Get-TopologyLink)
            $links.Count | Should BeGreaterThan 0
        }

        It 'clears existing topology when requested' {
            New-TopologyNode -DeviceID 'OLD-SW' | Out-Null

            $interfaces = @(
                @{ Hostname = 'NEW-SW'; PortName = 'Gi1/0/1'; Description = '' }
            )
            New-TopologyFromInterfaces -Interfaces $interfaces -ClearExisting

            $nodes = Get-TopologyNode
            ($nodes | Where-Object { $_.DeviceID -eq 'OLD-SW' }) | Should BeNullOrEmpty
        }

        It 'assigns site ID to discovered nodes' {
            $interfaces = @(
                @{ Hostname = 'SW-01'; PortName = 'Gi1/0/1'; Description = '' }
            )

            New-TopologyFromInterfaces -Interfaces $interfaces -SiteID 'CAMPUS-A'

            $node = Get-TopologyNode -DeviceID 'SW-01'
            $node.SiteID | Should Be 'CAMPUS-A'
        }
    }

    Context 'Layout Algorithms' {

        BeforeEach {
            # Create a simple topology for layout tests
            $script:core = New-TopologyNode -DeviceID 'CORE-01'
            $script:dist1 = New-TopologyNode -DeviceID 'DS-01'
            $script:dist2 = New-TopologyNode -DeviceID 'DS-02'
            $script:access1 = New-TopologyNode -DeviceID 'SW-01'
            $script:access2 = New-TopologyNode -DeviceID 'SW-02'

            New-TopologyLink -SourceNodeID $core.NodeID -DestNodeID $dist1.NodeID | Out-Null
            New-TopologyLink -SourceNodeID $core.NodeID -DestNodeID $dist2.NodeID | Out-Null
            New-TopologyLink -SourceNodeID $dist1.NodeID -DestNodeID $access1.NodeID | Out-Null
            New-TopologyLink -SourceNodeID $dist2.NodeID -DestNodeID $access2.NodeID | Out-Null
        }

        It 'applies hierarchical layout' {
            Set-HierarchicalLayout -Width 800 -Height 600

            $nodes = Get-TopologyNode
            foreach ($node in $nodes) {
                $node.XPosition | Should BeGreaterThan 0
                $node.YPosition | Should BeGreaterThan 0
            }

            # Core should be at top (smallest Y)
            $coreNode = Get-TopologyNode -DeviceID 'CORE-01'
            $accessNode = Get-TopologyNode -DeviceID 'SW-01'
            $coreNode.YPosition | Should BeLessThan $accessNode.YPosition
        }

        It 'applies force-directed layout' {
            Set-ForceDirectedLayout -Width 800 -Height 600 -Iterations 50

            $nodes = Get-TopologyNode
            foreach ($node in $nodes) {
                $node.XPosition | Should BeGreaterThan 0
                $node.YPosition | Should BeGreaterThan 0
            }
        }

        It 'applies circular layout' {
            Set-CircularLayout -CenterX 400 -CenterY 300 -Radius 200

            $nodes = Get-TopologyNode
            foreach ($node in $nodes) {
                $distance = [math]::Sqrt(
                    [math]::Pow($node.XPosition - 400, 2) +
                    [math]::Pow($node.YPosition - 300, 2)
                )
                # Allow some tolerance
                $distance | Should BeGreaterThan 180
                $distance | Should BeLessThan 220
            }
        }

        It 'applies grid layout' {
            Set-GridLayout -StartX 50 -StartY 50 -SpacingX 100 -SpacingY 100 -Columns 3

            $nodes = Get-TopologyNode
            # First node should be at start position
            $nodes[0].XPosition | Should Be 50
            $nodes[0].YPosition | Should Be 50
        }
    }

    Context 'Impact Analysis' {

        BeforeEach {
            $script:core = New-TopologyNode -DeviceID 'CORE-01'
            $script:dist = New-TopologyNode -DeviceID 'DS-01'
            $script:sw1 = New-TopologyNode -DeviceID 'SW-01'
            $script:sw2 = New-TopologyNode -DeviceID 'SW-02'

            # DS-01 has redundant uplink to CORE
            New-TopologyLink -SourceNodeID $core.NodeID -DestNodeID $dist.NodeID | Out-Null
            # SW-01 has only one uplink (no redundancy)
            New-TopologyLink -SourceNodeID $dist.NodeID -DestNodeID $sw1.NodeID | Out-Null
            # SW-02 has redundant uplinks
            New-TopologyLink -SourceNodeID $dist.NodeID -DestNodeID $sw2.NodeID | Out-Null
            New-TopologyLink -SourceNodeID $core.NodeID -DestNodeID $sw2.NodeID | Out-Null
        }

        It 'identifies directly affected devices' {
            $impact = Get-ImpactAnalysis -NodeID $dist.NodeID

            $impact | Should Not BeNullOrEmpty
            $impact.DirectlyAffected.Count | Should Be 3  # Core, SW-01, SW-02
        }

        It 'identifies devices without redundancy' {
            $impact = Get-ImpactAnalysis -NodeID $dist.NodeID

            $critical = $impact.DirectlyAffected | Where-Object { $_.IsCritical }
            # SW-01 has no redundancy
            ($critical.Node.DeviceID -contains 'SW-01') | Should Be $true
        }

        It 'identifies devices with redundancy' {
            $impact = Get-ImpactAnalysis -NodeID $dist.NodeID

            $redundant = $impact.DirectlyAffected | Where-Object { $_.HasRedundancy }
            # SW-02 has redundant link to CORE
            ($redundant.Node.DeviceID -contains 'SW-02') | Should Be $true
        }

        It 'provides impact summary' {
            $impact = Get-ImpactAnalysis -NodeID $dist.NodeID

            $impact.Summary | Should Not BeNullOrEmpty
            $impact.CriticalDevices | Should BeGreaterThan 0
        }
    }

    Context 'Connected Nodes' {

        It 'finds all connected nodes' {
            $node1 = New-TopologyNode -DeviceID 'SW-01'
            $node2 = New-TopologyNode -DeviceID 'SW-02'
            $node3 = New-TopologyNode -DeviceID 'SW-03'
            $isolated = New-TopologyNode -DeviceID 'ISOLATED'

            New-TopologyLink -SourceNodeID $node1.NodeID -DestNodeID $node2.NodeID | Out-Null
            New-TopologyLink -SourceNodeID $node2.NodeID -DestNodeID $node3.NodeID | Out-Null

            $connected = Get-ConnectedNodes -NodeID $node1.NodeID

            $connected.Count | Should Be 2
            ($connected.Node.DeviceID -contains 'ISOLATED') | Should Be $false
        }

        It 'returns nodes sorted by depth' {
            $node1 = New-TopologyNode -DeviceID 'SW-01'
            $node2 = New-TopologyNode -DeviceID 'SW-02'
            $node3 = New-TopologyNode -DeviceID 'SW-03'

            New-TopologyLink -SourceNodeID $node1.NodeID -DestNodeID $node2.NodeID | Out-Null
            New-TopologyLink -SourceNodeID $node2.NodeID -DestNodeID $node3.NodeID | Out-Null

            $connected = Get-ConnectedNodes -NodeID $node1.NodeID

            $connected[0].Depth | Should Be 1
            $connected[1].Depth | Should Be 2
        }
    }

    Context 'Export Functions' {

        BeforeEach {
            $script:node1 = New-TopologyNode -DeviceID 'CORE-01'
            $script:node2 = New-TopologyNode -DeviceID 'DS-01'
            New-TopologyLink -SourceNodeID $node1.NodeID -DestNodeID $node2.NodeID | Out-Null
            Set-HierarchicalLayout
        }

        It 'exports topology to SVG' {
            $svg = Export-TopologyToSVG

            $svg | Should Not BeNullOrEmpty
            $svg | Should Match '<svg'
            $svg | Should Match 'CORE-01'
            $svg | Should Match 'DS-01'
        }

        It 'exports topology to JSON' {
            $json = Export-TopologyToJSON

            $json | Should Not BeNullOrEmpty
            $parsed = $json | ConvertFrom-Json
            @($parsed.nodes).Count | Should Be 2
            @($parsed.links).Count | Should Be 1
        }

        It 'exports topology to Draw.io format' {
            $xml = Export-TopologyToDrawIO

            $xml | Should Not BeNullOrEmpty
            $xml | Should Match '<mxfile'
            $xml | Should Match 'mxCell'
        }

        It 'saves SVG to file when path provided' {
            $tempPath = Join-Path $env:TEMP 'test-topology.svg'

            try {
                $result = Export-TopologyToSVG -OutputPath $tempPath
                $result | Should Be $tempPath
                Test-Path $tempPath | Should Be $true
            }
            finally {
                if (Test-Path $tempPath) {
                    Remove-Item $tempPath -Force
                }
            }
        }
    }

    Context 'Layout Persistence' {

        It 'saves and retrieves layout' {
            $node = New-TopologyNode -DeviceID 'SW-01'
            $node.XPosition = 100
            $node.YPosition = 200

            Save-TopologyLayout -LayoutName 'TestLayout'

            $layout = Get-TopologyLayout -LayoutName 'TestLayout'
            $layout | Should Not BeNullOrEmpty
            $layout.LayoutName | Should Be 'TestLayout'
        }

        It 'restores saved layout' {
            $node = New-TopologyNode -DeviceID 'SW-01'
            $node.XPosition = 100
            $node.YPosition = 200
            Save-TopologyLayout -LayoutName 'TestLayout'

            # Change positions
            $node.XPosition = 500
            $node.YPosition = 500

            Restore-TopologyLayout -LayoutName 'TestLayout'

            $restoredNode = Get-TopologyNode -DeviceID 'SW-01'
            $restoredNode.XPosition | Should Be 100
            $restoredNode.YPosition | Should Be 200
        }

        It 'updates existing layout on save' {
            $node = New-TopologyNode -DeviceID 'SW-01'
            $node.XPosition = 100
            $node.YPosition = 200
            Save-TopologyLayout -LayoutName 'TestLayout'

            $node.XPosition = 300
            Save-TopologyLayout -LayoutName 'TestLayout'

            $layouts = Get-TopologyLayout
            @($layouts | Where-Object { $_.LayoutName -eq 'TestLayout' }).Count | Should Be 1
        }
    }

    Context 'Statistics' {

        It 'returns correct node and link counts' {
            New-TopologyNode -DeviceID 'CORE-01' | Out-Null
            New-TopologyNode -DeviceID 'DS-01' | Out-Null
            $core = Get-TopologyNode -DeviceID 'CORE-01'
            $dist = Get-TopologyNode -DeviceID 'DS-01'
            New-TopologyLink -SourceNodeID $core.NodeID -DestNodeID $dist.NodeID | Out-Null

            $stats = Get-TopologyStatistics

            $stats.TotalNodes | Should Be 2
            $stats.TotalLinks | Should Be 1
        }

        It 'provides role breakdown' {
            New-TopologyNode -DeviceID 'CORE-01' | Out-Null
            New-TopologyNode -DeviceID 'DS-01' | Out-Null
            New-TopologyNode -DeviceID 'SW-01' | Out-Null

            $stats = Get-TopologyStatistics

            $stats.RoleBreakdown | Should Not BeNullOrEmpty
            ($stats.RoleBreakdown | Where-Object { $_.Role -eq 'Core' }).Count | Should Be 1
        }

        It 'identifies isolated nodes' {
            New-TopologyNode -DeviceID 'CONNECTED-01' | Out-Null
            New-TopologyNode -DeviceID 'CONNECTED-02' | Out-Null
            New-TopologyNode -DeviceID 'ISOLATED-01' | Out-Null
            $c1 = Get-TopologyNode -DeviceID 'CONNECTED-01'
            $c2 = Get-TopologyNode -DeviceID 'CONNECTED-02'
            New-TopologyLink -SourceNodeID $c1.NodeID -DestNodeID $c2.NodeID | Out-Null

            $stats = Get-TopologyStatistics

            $stats.IsolatedNodes | Should Be 1
        }
    }

    Context 'Device Role Detection' {

        It 'detects Core role' {
            (Get-DeviceRole -DeviceName 'CORE-01') | Should Be 'Core'
            (Get-DeviceRole -DeviceName 'CR-MAIN') | Should Be 'Core'
        }

        It 'detects Distribution role' {
            (Get-DeviceRole -DeviceName 'DS-01') | Should Be 'Distribution'
            (Get-DeviceRole -DeviceName 'DIST-BLDG-A') | Should Be 'Distribution'
        }

        It 'detects Access role' {
            (Get-DeviceRole -DeviceName 'SW-01') | Should Be 'Access'
            (Get-DeviceRole -DeviceName 'ACCESS-RM101') | Should Be 'Access'
        }

        It 'detects Router role' {
            (Get-DeviceRole -DeviceName 'RTR-EDGE') | Should Be 'Router'
            (Get-DeviceRole -DeviceName 'GW-MAIN') | Should Be 'Router'
        }

        It 'detects Firewall role' {
            (Get-DeviceRole -DeviceName 'FW-EDGE') | Should Be 'Firewall'
            (Get-DeviceRole -DeviceName 'ASA-DMZ') | Should Be 'Firewall'
            (Get-DeviceRole -DeviceName 'PALO-01') | Should Be 'Firewall'
        }

        It 'detects Wireless role' {
            (Get-DeviceRole -DeviceName 'WLC-01') | Should Be 'Wireless'
        }

        It 'defaults to Access for unknown patterns' {
            (Get-DeviceRole -DeviceName 'UNKNOWN-DEVICE') | Should Be 'Access'
        }
    }

    #region ST-W-004: L3 Topology Tests

    Context 'L3 Interface Management' {

        It 'adds L3 interface to node' {
            $node = New-TopologyNode -DeviceID 'RTR-01'

            $iface = Add-L3Interface -NodeID $node.NodeID `
                -InterfaceName 'Gi0/0' `
                -IPAddress '10.1.1.1' `
                -SubnetMask '255.255.255.0'

            $iface | Should Not BeNullOrEmpty
            $iface.IPAddress | Should Be '10.1.1.1'
            $iface.PrefixLength | Should Be 24
        }

        It 'calculates network address correctly' {
            $node = New-TopologyNode -DeviceID 'RTR-01'

            $iface = Add-L3Interface -NodeID $node.NodeID `
                -InterfaceName 'Gi0/1' `
                -IPAddress '10.1.1.100' `
                -SubnetMask '255.255.255.0'

            $iface.NetworkAddress | Should Be '10.1.1.0'
            $iface.CIDR | Should Be '10.1.1.0/24'
        }

        It 'retrieves L3 interfaces for node' {
            $node = New-TopologyNode -DeviceID 'RTR-01'

            Add-L3Interface -NodeID $node.NodeID -InterfaceName 'Gi0/0' -IPAddress '10.1.1.1' | Out-Null
            Add-L3Interface -NodeID $node.NodeID -InterfaceName 'Gi0/1' -IPAddress '10.1.2.1' | Out-Null

            $interfaces = @(Get-L3Interfaces -NodeID $node.NodeID)

            $interfaces.Count | Should Be 2
        }

        It 'stores routing protocol information' {
            $node = New-TopologyNode -DeviceID 'RTR-01'

            $iface = Add-L3Interface -NodeID $node.NodeID `
                -InterfaceName 'Gi0/0' `
                -IPAddress '10.1.1.1' `
                -OSPFArea '0' `
                -RoutingProtocol 'OSPF'

            $iface.OSPFArea | Should Be '0'
            $iface.RoutingProtocol | Should Be 'OSPF'
        }

        It 'marks gateway interfaces' {
            $node = New-TopologyNode -DeviceID 'RTR-01'

            $iface = Add-L3Interface -NodeID $node.NodeID `
                -InterfaceName 'Gi0/0' `
                -IPAddress '10.1.1.1' `
                -IsGateway $true

            $iface.IsGateway | Should Be $true
        }
    }

    Context 'Subnet Grouping' {

        It 'groups nodes by subnet' {
            $rtr = New-TopologyNode -DeviceID 'RTR-01'
            $sw1 = New-TopologyNode -DeviceID 'SW-01'
            $sw2 = New-TopologyNode -DeviceID 'SW-02'

            Add-L3Interface -NodeID $rtr.NodeID -InterfaceName 'Vlan10' -IPAddress '10.1.10.1' -SubnetMask '255.255.255.0' | Out-Null
            Add-L3Interface -NodeID $sw1.NodeID -InterfaceName 'Vlan10' -IPAddress '10.1.10.2' -SubnetMask '255.255.255.0' | Out-Null
            Add-L3Interface -NodeID $sw2.NodeID -InterfaceName 'Vlan20' -IPAddress '10.1.20.1' -SubnetMask '255.255.255.0' | Out-Null

            $groups = Get-SubnetGroups -VRF '*'

            $groups.Count | Should Be 2
            $groups['10.1.10.0/24'].Nodes.Count | Should Be 2
            $groups['10.1.20.0/24'].Nodes.Count | Should Be 1
        }

        It 'identifies gateways in subnet groups' {
            $rtr = New-TopologyNode -DeviceID 'RTR-01'
            $sw = New-TopologyNode -DeviceID 'SW-01'

            Add-L3Interface -NodeID $rtr.NodeID -InterfaceName 'Vlan10' -IPAddress '10.1.10.1' -SubnetMask '255.255.255.0' -IsGateway $true | Out-Null
            Add-L3Interface -NodeID $sw.NodeID -InterfaceName 'Vlan10' -IPAddress '10.1.10.2' -SubnetMask '255.255.255.0' | Out-Null

            $groups = Get-SubnetGroups -VRF '*'

            $groups['10.1.10.0/24'].Gateways.Count | Should Be 1
        }
    }

    Context 'L3 Links' {

        It 'creates L3 links between nodes in same subnet' {
            $rtr = New-TopologyNode -DeviceID 'RTR-01'
            $sw1 = New-TopologyNode -DeviceID 'SW-01'
            $sw2 = New-TopologyNode -DeviceID 'SW-02'

            Add-L3Interface -NodeID $rtr.NodeID -InterfaceName 'Vlan10' -IPAddress '10.1.10.1' -SubnetMask '255.255.255.0' | Out-Null
            Add-L3Interface -NodeID $sw1.NodeID -InterfaceName 'Vlan10' -IPAddress '10.1.10.2' -SubnetMask '255.255.255.0' | Out-Null
            Add-L3Interface -NodeID $sw2.NodeID -InterfaceName 'Vlan10' -IPAddress '10.1.10.3' -SubnetMask '255.255.255.0' | Out-Null

            $l3Links = @(Get-L3Links)

            # 3 nodes in same subnet = 3 pairwise links
            $l3Links.Count | Should Be 3
        }

        It 'includes subnet info in L3 links' {
            $rtr = New-TopologyNode -DeviceID 'RTR-01'
            $sw = New-TopologyNode -DeviceID 'SW-01'

            Add-L3Interface -NodeID $rtr.NodeID -InterfaceName 'Vlan10' -IPAddress '10.1.10.1' -SubnetMask '255.255.255.0' | Out-Null
            Add-L3Interface -NodeID $sw.NodeID -InterfaceName 'Vlan10' -IPAddress '10.1.10.2' -SubnetMask '255.255.255.0' | Out-Null

            $l3Links = @(Get-L3Links)

            $l3Links[0].Subnet | Should Be '10.1.10.0/24'
            $l3Links[0].SourceIP | Should Not BeNullOrEmpty
            $l3Links[0].DestIP | Should Not BeNullOrEmpty
        }
    }

    Context 'Subnet Group Layout' {

        It 'applies subnet group layout' {
            $rtr = New-TopologyNode -DeviceID 'RTR-01'
            $sw1 = New-TopologyNode -DeviceID 'SW-01'
            $sw2 = New-TopologyNode -DeviceID 'SW-02'

            Add-L3Interface -NodeID $rtr.NodeID -InterfaceName 'Vlan10' -IPAddress '10.1.10.1' -SubnetMask '255.255.255.0' | Out-Null
            Add-L3Interface -NodeID $sw1.NodeID -InterfaceName 'Vlan10' -IPAddress '10.1.10.2' -SubnetMask '255.255.255.0' | Out-Null
            Add-L3Interface -NodeID $sw2.NodeID -InterfaceName 'Vlan20' -IPAddress '10.1.20.1' -SubnetMask '255.255.255.0' | Out-Null

            Set-SubnetGroupLayout

            # Nodes should have updated positions
            $rtr = Get-TopologyNode -DeviceID 'RTR-01'
            $sw2 = Get-TopologyNode -DeviceID 'SW-02'

            $rtr.XPosition | Should BeGreaterThan 0
            $sw2.XPosition | Should BeGreaterThan 0
        }
    }

    Context 'Routing Protocol Topology' {

        It 'groups nodes by OSPF area' {
            $rtr1 = New-TopologyNode -DeviceID 'RTR-01'
            $rtr2 = New-TopologyNode -DeviceID 'RTR-02'
            $rtr3 = New-TopologyNode -DeviceID 'RTR-03'

            Add-L3Interface -NodeID $rtr1.NodeID -InterfaceName 'Gi0/0' -IPAddress '10.1.1.1' -OSPFArea '0' | Out-Null
            Add-L3Interface -NodeID $rtr2.NodeID -InterfaceName 'Gi0/0' -IPAddress '10.1.2.1' -OSPFArea '0' | Out-Null
            Add-L3Interface -NodeID $rtr3.NodeID -InterfaceName 'Gi0/0' -IPAddress '10.2.1.1' -OSPFArea '1' | Out-Null

            $groups = Get-RoutingProtocolTopology -Protocol 'OSPF'

            $groups.Count | Should Be 2
            $groups['OSPF-Area-0'].Count | Should Be 2
            $groups['OSPF-Area-1'].Count | Should Be 1
        }
    }

    Context 'L3 Topology Statistics' {

        It 'returns correct L3 statistics' {
            $rtr = New-TopologyNode -DeviceID 'RTR-01'
            $sw = New-TopologyNode -DeviceID 'SW-01'
            $noL3 = New-TopologyNode -DeviceID 'SW-02'

            Add-L3Interface -NodeID $rtr.NodeID -InterfaceName 'Gi0/0' -IPAddress '10.1.1.1' -IsGateway $true | Out-Null
            Add-L3Interface -NodeID $rtr.NodeID -InterfaceName 'Gi0/1' -IPAddress '10.1.2.1' -IsGateway $true | Out-Null
            Add-L3Interface -NodeID $sw.NodeID -InterfaceName 'Vlan10' -IPAddress '10.1.1.2' | Out-Null

            $stats = Get-L3TopologyStatistics

            $stats.TotalNodes | Should Be 3
            $stats.NodesWithL3 | Should Be 2
            $stats.TotalInterfaces | Should Be 3
            $stats.GatewayCount | Should Be 2
        }
    }

    Context 'Helper Functions' {

        It 'converts subnet mask to prefix length' {
            (ConvertTo-PrefixLength -SubnetMask '255.255.255.0') | Should Be 24
            (ConvertTo-PrefixLength -SubnetMask '255.255.255.128') | Should Be 25
            (ConvertTo-PrefixLength -SubnetMask '255.255.0.0') | Should Be 16
            (ConvertTo-PrefixLength -SubnetMask '255.255.255.252') | Should Be 30
        }

        It 'calculates network address' {
            (Get-NetworkAddress -IPAddress '10.1.1.100' -PrefixLength 24) | Should Be '10.1.1.0'
            (Get-NetworkAddress -IPAddress '192.168.1.50' -PrefixLength 25) | Should Be '192.168.1.0'
            (Get-NetworkAddress -IPAddress '172.16.5.200' -PrefixLength 16) | Should Be '172.16.0.0'
        }
    }

    #endregion

    #region ST-W-006: Visio Export Tests

    Context 'Visio Export' {

        It 'exports topology to Visio format' {
            $node1 = New-TopologyNode -DeviceID 'CORE-01'
            $node2 = New-TopologyNode -DeviceID 'DS-01'
            New-TopologyLink -SourceNodeID $node1.NodeID -DestNodeID $node2.NodeID | Out-Null
            Set-HierarchicalLayout

            $tempPath = Join-Path $env:TEMP "test-topology-$([guid]::NewGuid().ToString('N').Substring(0,8)).vsdx"

            try {
                $result = Export-TopologyToVisio -OutputPath $tempPath

                $result | Should Not BeNullOrEmpty
                Test-Path $result | Should Be $true
                $result | Should Match '\.vsdx$'
            }
            finally {
                if (Test-Path $tempPath) {
                    Remove-Item $tempPath -Force
                }
            }
        }

        It 'creates valid ZIP structure for VSDX' {
            $node1 = New-TopologyNode -DeviceID 'SW-01'
            Set-HierarchicalLayout

            $tempPath = Join-Path $env:TEMP "test-topology-$([guid]::NewGuid().ToString('N').Substring(0,8)).vsdx"

            try {
                Export-TopologyToVisio -OutputPath $tempPath

                # Verify it's a valid ZIP (VSDX is ZIP-based)
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                $zip = [System.IO.Compression.ZipFile]::OpenRead($tempPath)

                $entryNames = $zip.Entries.Name
                $entryNames -contains 'document.xml' | Should Be $true
                $entryNames -contains 'page1.xml' | Should Be $true

                $zip.Dispose()
            }
            finally {
                if (Test-Path $tempPath) {
                    Remove-Item $tempPath -Force
                }
            }
        }

        It 'includes node data in Visio export' {
            $node = New-TopologyNode -DeviceID 'CORE-01'
            $node.XPosition = 100
            $node.YPosition = 100

            $tempPath = Join-Path $env:TEMP "test-topology-$([guid]::NewGuid().ToString('N').Substring(0,8)).vsdx"

            try {
                Export-TopologyToVisio -OutputPath $tempPath

                Add-Type -AssemblyName System.IO.Compression.FileSystem
                $zip = [System.IO.Compression.ZipFile]::OpenRead($tempPath)

                $pageEntry = $zip.Entries | Where-Object { $_.Name -eq 'page1.xml' }
                $reader = New-Object System.IO.StreamReader($pageEntry.Open())
                $content = $reader.ReadToEnd()
                $reader.Dispose()
                $zip.Dispose()

                $content | Should Match 'CORE-01'
            }
            finally {
                if (Test-Path $tempPath) {
                    Remove-Item $tempPath -Force
                }
            }
        }

        It 'returns null for empty topology' {
            Clear-Topology

            $tempPath = Join-Path $env:TEMP "test-empty.vsdx"
            $result = Export-TopologyToVisio -OutputPath $tempPath

            $result | Should Be $null
        }
    }

    #endregion
}
