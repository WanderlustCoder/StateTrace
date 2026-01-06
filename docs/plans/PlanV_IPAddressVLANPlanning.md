# Plan V - IP Address & VLAN Planning

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

## Objective
Provide lightweight IP address management (IPAM) and VLAN planning capabilities that work offline. Enable network engineers to plan subnet allocations, track VLAN assignments, identify conflicts, and prepare addressing schemes before deployment.

## Problem Statement
Network engineers often need to:
- Plan IP addressing for new sites or expansions without access to enterprise IPAM tools
- Track VLAN IDs across multiple switches to avoid conflicts
- Document subnet allocations and identify available address space
- Prepare addressing documentation for change requests
- Quickly calculate subnet boundaries and usable ranges

## Current status (2026-01)
- **Complete (6/6 Done)**. Full IPAM functionality with VLAN discovery and site planning wizard.
- IPAMModule.psm1 provides VLAN, subnet, and IP address data model
- IPAMView.xaml offers interactive UI with tabs for VLANs, Subnets, IPs, Conflicts, and Statistics
- Subnet calculations, conflict detection, and site planning tools implemented
- VLAN discovery: Import-VLANsFromConfig, Import-SVIsFromConfig, Import-VLANsToDatabase, Merge-VLANDiscovery, New-VLANDiscoveryReport
- Site Planning Wizard: Full wizard UI with VLAN type selection, host count inputs, growth factor slider, real-time subnet recommendations, plan preview and apply
- 85 Pester tests cover all module and wizard functionality

## Proposed Features

### V.1 VLAN Management
- **VLAN Database**: Centralized VLAN registry with:
  - VLAN ID and name
  - Purpose/description
  - Associated sites/buildings
  - Status (active, reserved, deprecated)
  - Layer 3 interface (SVI) information
- **VLAN Discovery**: Import VLANs from device data
- **Conflict Detection**: Identify:
  - Same VLAN ID with different names across devices
  - VLAN ID reuse across sites (when unintended)
  - Missing VLANs (configured but not trunked)
  - Orphan VLANs (trunked but not configured)
- **VLAN Allocation**: Track used/available VLAN IDs by range

### V.2 Subnet Planning
- **Subnet Registry**: Track subnet allocations with:
  - Network address and prefix length
  - VLAN association
  - Site/location
  - Purpose (user, voice, management, infrastructure)
  - Gateway address
  - DHCP scope (if applicable)
  - Status (active, reserved, available)
- **Subnet Hierarchy**: Visualize supernet/subnet relationships
- **Address Space Map**: Visual representation of IP ranges
- **Utilization Tracking**: Estimate subnet utilization from device data

### V.3 IP Address Tracking
- **Known Addresses**: Track statically assigned IPs:
  - Device management IPs
  - Infrastructure addresses (gateways, HSRP VIPs)
  - Server/critical device IPs
- **Address Discovery**: Import known IPs from device configs
- **Conflict Detection**: Identify duplicate IP assignments
- **Available Address Finder**: Find available IPs in a subnet

### V.4 Planning Tools
- **New Site Planner**: Wizard to allocate addressing for new sites:
  - Input: required VLANs, user counts, growth factor
  - Output: recommended subnet sizes and VLAN assignments
- **Subnet Calculator**: Interactive subnet calculation
- **VLAN Matrix**: Cross-reference VLANs across switches/sites
- **Addressing Template**: Standard addressing schemes (management, voice, data, guest)

### V.5 Documentation & Export
- **IP Address Plan Document**: Generate comprehensive addressing docs
- **VLAN Summary Report**: Per-site VLAN documentation
- **Conflict Report**: List all detected conflicts with remediation
- **Export Formats**: Excel, CSV, PDF, Visio-compatible

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-V-001 | VLAN database schema | Data | Done | IPAMModule.psm1 with New-VLAN, Add/Get/Update/Remove-VLAN |
| ST-V-002 | Subnet registry | Data | Done | New-Subnet with auto-calculation, Add/Get/Remove-Subnet |
| ST-V-003 | VLAN discovery import | Tools | Done | Import-VLANsFromConfig, Import-SVIsFromConfig, Import-VLANsToDatabase, Merge-VLANDiscovery, New-VLANDiscoveryReport |
| ST-V-004 | Conflict detection engine | Tools | Done | Find-VLANConflicts, Find-IPConflicts, Find-IPAMConflicts |
| ST-V-005 | Subnet visualization | UI | Done | IPAMView.xaml with tabs and statistics |
| ST-V-006 | New site planning wizard | UI | Done | Full wizard UI with VLAN selection, host counts, growth slider, recommendations, preview/apply |

## Recently delivered
| ID | Title | Delivered | Notes |
|----|-------|-----------|-------|
| ST-V-006 | Site planning wizard | 2026-01-06 | 24 new tests for wizard controls and module wiring |

## Data Model (Proposed)

### VLAN Table
```
VlanID (PK), VlanNumber, VlanName, Description, Purpose, SiteID, Status,
SVIAddress, SVIMask, DHCPEnabled, CreatedDate, ModifiedDate, Notes
```

### Subnet Table
```
SubnetID (PK), NetworkAddress, PrefixLength, VlanID (FK), SiteID, Purpose,
GatewayAddress, DHCPStart, DHCPEnd, Status, Utilization, CreatedDate, Notes
```

### IPAddress Table
```
AddressID (PK), IPAddress, SubnetID (FK), DeviceID, InterfaceName,
AddressType, Description, Status, LastSeen, Notes
```

### VLANDeviceMapping Table
```
VlanID (FK), DeviceID, VlanState, TrunkPorts, AccessPorts, DiscoveredDate
```

## UI Mockup Concepts

### VLAN Matrix View
```
+--------------------------------------------------------------+
| VLAN Matrix - Site: CAMPUS-MAIN                               |
+--------------------------------------------------------------+
| VLAN | Name        | SW-1 | SW-2 | SW-3 | DS-1 | Conflicts  |
+--------------------------------------------------------------+
|   10 | Users       |  T   |  T   |  T   |  T   |            |
|   20 | Voice       |  T   |  T   |  T   |  T   |            |
|   30 | Servers     |  -   |  -   |  -   |  T   |            |
|  100 | Management  |  T   |  T   |  T   |  T   | Name diff! |
|  999 | Native      |  T   |  T   |  -   |  T   | Missing    |
+--------------------------------------------------------------+
| Legend: T=Trunked, A=Access, -=Not Present                   |
| [Add VLAN] [Import from Device] [Export Matrix]              |
+--------------------------------------------------------------+
```

### Subnet Hierarchy View
```
+--------------------------------------------------------------+
| Address Space: 10.0.0.0/8                                     |
+--------------------------------------------------------------+
| + 10.1.0.0/16 (Campus Main)                                   |
|   + 10.1.10.0/24 (VLAN 10 - Users)        [85% used]         |
|   + 10.1.20.0/24 (VLAN 20 - Voice)        [42% used]         |
|   + 10.1.100.0/24 (VLAN 100 - Mgmt)       [15% used]         |
|   - 10.1.200.0/24 (Available)                                 |
| + 10.2.0.0/16 (Campus North)                                  |
|   + 10.2.10.0/24 (VLAN 10 - Users)        [72% used]         |
+--------------------------------------------------------------+
| [Allocate Subnet] [Find Available Space] [Export Plan]        |
+--------------------------------------------------------------+
```

### New Site Planning Wizard
```
+--------------------------------------------------------------+
| New Site Address Planning                                      |
+--------------------------------------------------------------+
| Site Name: [Building C              ]                         |
| Parent Supernet: [10.3.0.0/16       ] (Available: 10.3.x.x)  |
|                                                               |
| Required VLANs:                                               |
| [x] User Data      Hosts: [200]  Recommended: /24            |
| [x] Voice          Hosts: [150]  Recommended: /24            |
| [x] Management     Hosts: [20 ]  Recommended: /27            |
| [ ] Guest          Hosts: [   ]                              |
| [ ] IoT            Hosts: [   ]                              |
|                                                               |
| Growth Factor: [25%]                                          |
|                                                               |
| [Generate Plan] [Cancel]                                      |
+--------------------------------------------------------------+
```

### Conflict Report
```
+--------------------------------------------------------------+
| IP/VLAN Conflict Report                                       |
| Generated: 2026-01-04 14:30                                   |
+--------------------------------------------------------------+
| CRITICAL: Duplicate IP Addresses (2)                          |
| - 10.1.100.5 assigned to SW-01 AND SW-02 (Loopback)          |
| - 10.1.10.50 assigned to DS-01 (HSRP) AND Server-DB (Static) |
+--------------------------------------------------------------+
| WARNING: VLAN Name Mismatches (3)                             |
| - VLAN 100: "Management" (SW-01) vs "Mgmt" (SW-02)           |
| - VLAN 20: "Voice" (SW-01) vs "VoIP" (DS-01)                 |
+--------------------------------------------------------------+
| INFO: Orphan VLANs (1)                                        |
| - VLAN 50: Trunked on SW-01 Gi1/0/48 but not configured      |
+--------------------------------------------------------------+
| [Export Report] [Generate Remediation]                        |
+--------------------------------------------------------------+
```

## Automation hooks
- `Tools\Import-VLANData.ps1 -DeviceFilter CAMPUS*` to discover VLANs from devices
- `Tools\Test-VLANConflicts.ps1 -Site CAMPUS-MAIN` to check for conflicts
- `Tools\Test-IPConflicts.ps1 -Subnet 10.1.0.0/16` to find duplicate IPs
- `Tools\New-SiteAddressPlan.ps1 -SiteName "Building C" -Supernet 10.3.0.0/16`
- `Tools\Export-AddressPlan.ps1 -Format Excel -Scope Site -Site CAMPUS-MAIN`
- `Tools\Find-AvailableSubnet.ps1 -Parent 10.0.0.0/8 -Size /24`

## Telemetry gates
- VLAN import/discovery emits `VLANDiscovery` with counts
- Conflict detection emits `AddressConflict` with severity counts
- Planning operations emit `AddressPlan` with allocation sizes

## Subnet Calculator Integration

Built-in subnet calculator features:
- CIDR to subnet mask conversion
- Subnet mask to CIDR conversion
- Network/broadcast address calculation
- Usable host range calculation
- Subnet splitting (divide /24 into /26s)
- Supernet aggregation (combine /25s into /24)

Example:
```
Input: 10.1.10.0/24
Output:
  Network:    10.1.10.0
  Broadcast:  10.1.10.255
  Subnet Mask: 255.255.255.0
  Usable Range: 10.1.10.1 - 10.1.10.254
  Total Hosts: 254
  Subnets (/26): 10.1.10.0/26, 10.1.10.64/26, 10.1.10.128/26, 10.1.10.192/26
```

## Dependencies
- Existing device/interface data model
- Access database infrastructure
- Compare view patterns for conflict visualization

## References
- `docs/plans/PlanD_FeatureExpansion.md` (Interfaces view context)
- `docs/schemas/access/Access_DB_Schema.md` (Database patterns)
- `Modules/DeviceRepositoryModule.psm1` (Device data access)
