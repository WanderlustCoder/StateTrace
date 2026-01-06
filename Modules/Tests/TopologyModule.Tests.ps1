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

    Describe 'Node Management' {

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

            $cores = Get-TopologyNode -Role 'Core'

            $cores.Count | Should Be 1
            $cores.DeviceID | Should Be 'CORE-01'
        }

        It 'removes a node and its links' {
            $node1 = New-TopologyNode -DeviceID 'SW-01'
            $node2 = New-TopologyNode -DeviceID 'SW-02'
            New-TopologyLink -SourceNodeID $node1.NodeID -DestNodeID $node2.NodeID | Out-Null

            $result = Remove-TopologyNode -NodeID $node1.NodeID

            $result | Should Be $true
            $remaining = Get-TopologyNode
            $remaining.Count | Should Be 1
            $links = Get-TopologyLink
            $links.Count | Should Be 0
        }
    }

    Describe 'Link Management' {

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

            $allLinks = Get-TopologyLink
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

    Describe 'Link Discovery' {

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

    Describe 'Build Topology From Interfaces' {

        It 'creates nodes from interface data' {
            $interfaces = @(
                @{ Hostname = 'SW-01'; PortName = 'Gi1/0/1'; Description = '' },
                @{ Hostname = 'SW-02'; PortName = 'Gi1/0/1'; Description = '' }
            )

            $result = Build-TopologyFromInterfaces -Interfaces $interfaces

            $result.NodesCreated | Should Be 2
            $nodes = Get-TopologyNode
            $nodes.Count | Should Be 2
        }

        It 'discovers and creates links from descriptions' {
            $interfaces = @(
                @{ Hostname = 'SW-01'; PortName = 'Gi1/0/48'; Description = 'To CORE-01 Gi1/0/1' },
                @{ Hostname = 'CORE-01'; PortName = 'Gi1/0/1'; Description = 'To SW-01 Gi1/0/48' }
            )

            $result = Build-TopologyFromInterfaces -Interfaces $interfaces

            $result.LinksDiscovered | Should BeGreaterThan 0
            $links = Get-TopologyLink
            $links.Count | Should BeGreaterThan 0
        }

        It 'clears existing topology when requested' {
            New-TopologyNode -DeviceID 'OLD-SW' | Out-Null

            $interfaces = @(
                @{ Hostname = 'NEW-SW'; PortName = 'Gi1/0/1'; Description = '' }
            )
            Build-TopologyFromInterfaces -Interfaces $interfaces -ClearExisting

            $nodes = Get-TopologyNode
            ($nodes | Where-Object { $_.DeviceID -eq 'OLD-SW' }) | Should BeNullOrEmpty
        }

        It 'assigns site ID to discovered nodes' {
            $interfaces = @(
                @{ Hostname = 'SW-01'; PortName = 'Gi1/0/1'; Description = '' }
            )

            Build-TopologyFromInterfaces -Interfaces $interfaces -SiteID 'CAMPUS-A'

            $node = Get-TopologyNode -DeviceID 'SW-01'
            $node.SiteID | Should Be 'CAMPUS-A'
        }
    }

    Describe 'Layout Algorithms' {

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

    Describe 'Impact Analysis' {

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

    Describe 'Connected Nodes' {

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

    Describe 'Export Functions' {

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
            $parsed.nodes.Count | Should Be 2
            $parsed.links.Count | Should Be 1
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

    Describe 'Layout Persistence' {

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
            ($layouts | Where-Object { $_.LayoutName -eq 'TestLayout' }).Count | Should Be 1
        }
    }

    Describe 'Statistics' {

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

    Describe 'Device Role Detection' {

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
}
