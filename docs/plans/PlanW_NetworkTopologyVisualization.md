# Plan W - Network Topology Visualization

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

## Objective
Generate visual network topology diagrams from collected device and interface data. Provide interactive topology views that help network engineers understand connectivity, plan changes, and document network architecture without manual diagram creation.

## Problem Statement
Network engineers struggle with:
- Maintaining accurate network diagrams as infrastructure changes
- Understanding connectivity between devices discovered from configs
- Visualizing layer 2 (VLAN) and layer 3 (routing) relationships
- Generating professional diagrams for documentation and change requests
- Quickly identifying the impact radius of a device or link failure

## Current status (2026-01)
- **Complete (6/6 Done)**: Core module, tests, UI, MainWindow integration, L3 topology, and Visio export
- Link discovery from interface descriptions (6 patterns)
- Topology graph model with nodes and links
- Layout algorithms: Hierarchical, Force-Directed, Circular, Grid, Subnet-Group
- Impact analysis with redundancy detection
- L3 topology: subnet grouping, gateway detection, routing protocol views (OSPF/EIGRP)
- Export formats: SVG, JSON, Draw.io, Visio (.vsdx)
- Interactive canvas with zoom, pan, and filtering
- 74 Pester tests passing

## Proposed Features

### W.1 Topology Discovery
- **Link Discovery**: Build topology from:
  - Interface descriptions ("To SW-02 Gi1/0/48")
  - CDP/LLDP neighbor data (when available in parsed logs)
  - Cable documentation (Plan T integration)
  - Manual link definitions
- **Device Role Detection**: Infer device roles:
  - Core/distribution/access based on naming or connections
  - WLC, firewall, router based on interface patterns
- **Site/Building Grouping**: Organize devices by location

### W.2 Layer 2 Topology View
- **Physical Connectivity**: Show switch-to-switch links
- **Trunk Visualization**: Indicate trunk links with VLAN info
- **Port Channel/LAG**: Show aggregated links
- **STP Topology**: Indicate root bridge, blocked ports
- **VLAN Overlay**: Filter view by VLAN membership

### W.3 Layer 3 Topology View
- **Routing Relationships**: Show router/L3 switch connections
- **Subnet Visualization**: Group devices by subnet
- **Gateway Indicators**: Show default gateway relationships
- **Routing Protocol Context**: Indicate OSPF areas, EIGRP AS
- **WAN Links**: Distinguish LAN vs WAN connections

### W.4 Interactive Features
- **Zoom/Pan**: Navigate large topologies
- **Device Details**: Click device for interface/config summary
- **Link Details**: Click link for port info, utilization, VLANs
- **Filtering**: Show/hide by:
  - Device type/role
  - Site/building
  - VLAN
  - Connection type
- **Search**: Find and highlight specific devices/ports
- **Impact Analysis**: Select device to highlight all connected paths

### W.5 Diagram Generation
- **Auto-Layout**: Automatic device positioning with:
  - Hierarchical layout (core at top)
  - Circular layout
  - Force-directed layout
  - Grid layout
- **Manual Adjustment**: Drag devices to preferred positions
- **Save Layouts**: Remember positioning per topology
- **Export Formats**:
  - PNG/SVG images
  - Visio-compatible (.vsdx)
  - Draw.io compatible
  - PDF documentation

### W.6 Documentation Integration
- **Rack Elevation Context**: Link to rack positions
- **Cable Documentation**: Show cable IDs on links
- **Change Highlighting**: Mark recent topology changes
- **Historical Views**: Compare current vs past topology

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-W-001 | Link discovery engine | Tools | Done | 6 description patterns, interface parsing |
| ST-W-002 | Topology data model | Data | Done | Nodes, links, layouts in TopologyModule.psm1 |
| ST-W-003 | L2 topology view | UI | Done | TopologyView.xaml with interactive canvas |
| ST-W-004 | L3 topology view | UI | Done | L3 interface mgmt, subnet grouping, routing protocols |
| ST-W-005 | Auto-layout algorithms | UI | Done | Hierarchical, force-directed, circular, grid, subnet-group |
| ST-W-006 | Export to Visio/Draw.io | Tools | Done | Draw.io XML, Visio .vsdx (Open Packaging) |

## Recently delivered
| ID | Title | Delivered | Notes |
|----|-------|-----------|-------|
| ST-W-001 | Link discovery engine | 2026-01-05 | `Modules/TopologyModule.psm1` |
| ST-W-002 | Topology data model | 2026-01-05 | Node/Link management, impact analysis |
| ST-W-003 | L2 topology view | 2026-01-05 | `Views/TopologyView.xaml`, view module |
| ST-W-005 | Auto-layout algorithms | 2026-01-05 | 4 layout algorithms implemented |
| ST-W-004 | L3 topology view | 2026-01-06 | Add-L3Interface, Get-SubnetGroups, Get-L3Links, Set-SubnetGroupLayout, Get-RoutingProtocolTopology |
| ST-W-006 | Export to Visio/Draw.io | 2026-01-06 | Export-TopologyToVisio with .vsdx ZIP package |

## Data Model (Proposed)

### TopologyNode Table
```
NodeID (PK), DeviceID (FK), NodeType, DisplayName, XPosition, YPosition,
Role, SiteID, BuildingID, RackID, IconType, Notes
```

### TopologyLink Table
```
LinkID (PK), SourceNodeID (FK), SourcePort, DestNodeID (FK), DestPort,
LinkType, Speed, VLANs, IsAggregate, DiscoveryMethod, Status, Notes
```

### TopologyLayout Table
```
LayoutID (PK), LayoutName, Scope, CreatedDate, ModifiedDate, LayoutData
```

## UI Mockup Concepts

### Layer 2 Topology View
```
+------------------------------------------------------------------+
| L2 Topology - Site: CAMPUS-MAIN         [L2] [L3] [Racks]        |
+------------------------------------------------------------------+
|  Filter: [All VLANs v] [All Types v]    [Search...] [Export]     |
+------------------------------------------------------------------+
|                                                                   |
|                    +------------+                                 |
|                    |  CORE-01   |                                 |
|                    | (Core SW)  |                                 |
|                    +-----+------+                                 |
|                     /    |    \                                   |
|                    /     |     \                                  |
|          +--------+  +--------+  +--------+                       |
|          | DS-01  |  | DS-02  |  | DS-03  |                       |
|          | (Dist) |  | (Dist) |  | (Dist) |                       |
|          +---+----+  +---+----+  +---+----+                       |
|             /|\         /|\         /|\                           |
|            / | \       / | \       / | \                          |
|     +----+ +----+ +----+ +----+ +----+ +----+                     |
|     |SW01| |SW02| |SW03| |SW04| |SW05| |SW06|                     |
|     +----+ +----+ +----+ +----+ +----+ +----+                     |
|                                                                   |
+------------------------------------------------------------------+
| Selected: DS-01 | Ports: 48 | Uplinks: 2x10G | VLANs: 10,20,100  |
+------------------------------------------------------------------+
```

### Link Detail Panel
```
+----------------------------------+
| Link: DS-01 <-> CORE-01          |
+----------------------------------+
| Source: DS-01 Te1/0/1            |
| Dest:   CORE-01 Te1/0/5          |
| Type:   Trunk (10G)              |
| VLANs:  10, 20, 30, 100          |
| Status: Active                   |
| Cable:  MDF-001 (Cat6a, 15m)     |
|                                  |
| [View Source Port] [View Cable]  |
+----------------------------------+
```

### Impact Analysis View
```
+------------------------------------------------------------------+
| Impact Analysis: DS-02 Failure                                    |
+------------------------------------------------------------------+
|                                                                   |
|        Directly Affected (6 devices):                             |
|        SW-03, SW-04 (lose uplink)                                 |
|        Access ports: 96 ports impacted                            |
|                                                                   |
|        Redundancy Status:                                         |
|        SW-03: Has backup uplink to DS-01 (OK)                    |
|        SW-04: No redundant uplink (CRITICAL)                     |
|                                                                   |
+------------------------------------------------------------------+
```

## Link Discovery Patterns

### Interface Description Parsing
```
Description patterns to match:
- "To CORE-01 Gi1/0/48" -> Link to CORE-01, port Gi1/0/48
- "Uplink to DS-01" -> Link to DS-01, port unknown
- "Po1 - CORE-01 Te1/0/1-2" -> Port-channel to CORE-01
- "WAN to BRANCH-01" -> WAN link to BRANCH-01
```

### CDP/LLDP Data (when available)
```
Parse from show cdp neighbors detail:
- Device ID
- Platform
- Remote port
- Native VLAN
- Duplex/speed
```

## Auto-Layout Algorithms

### Hierarchical Layout
- Place core devices at top
- Distribution one level down
- Access at bottom
- Minimize link crossings

### Force-Directed Layout
- Devices repel each other
- Links act as springs
- Iterate until stable
- Good for complex meshes

### Site-Grouped Layout
- Group devices by site/building
- Show inter-site links prominently
- Collapse/expand site groups

## Export Formats

### Visio Export
- Generate .vsdx with:
  - Proper network stencil shapes
  - Link connections
  - Text labels
  - Layer organization

### Draw.io Export
- Generate .drawio XML with:
  - Device shapes
  - Connectors
  - Grouping
  - Styling

### SVG/PNG Export
- High-resolution images
- Configurable size/DPI
- Transparent background option

## Automation hooks
- `Tools\Build-TopologyGraph.ps1 -Site CAMPUS-MAIN` to discover topology
- `Tools\Export-TopologyDiagram.ps1 -Format Visio -Layout Hierarchical`
- `Tools\Test-TopologyRedundancy.ps1 -Device DS-02` for impact analysis
- `Tools\Compare-TopologyChanges.ps1 -Before snapshot1 -After snapshot2`

## Telemetry gates
- Topology discovery emits `TopologyDiscovery` with node/link counts
- Export operations emit `TopologyExport` with format and complexity
- Impact analysis emits `ImpactAnalysis` with affected device counts

## Dependencies
- Interface data with descriptions
- CDP/LLDP data if available
- Cable documentation (Plan T) for enhanced link info
- WPF graphics capabilities for interactive view

## References
- `docs/plans/PlanT_CablePortDocumentation.md` (Cable data integration)
- `docs/plans/PlanD_FeatureExpansion.md` (SPAN view patterns)
- `Modules/SpanViewModule.psm1` (Relationship visualization patterns)
