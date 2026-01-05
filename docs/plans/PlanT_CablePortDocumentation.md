# Plan T - Cable & Port Documentation

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

## Objective
Provide comprehensive cable and port documentation capabilities so network technicians can track physical connections, generate professional cable labels, map ports to patch panels, and maintain accurate as-built documentation without direct device access.

## Problem Statement
Network technicians often struggle with:
- Tracking which cables connect which ports across patch panels, switches, and end devices
- Generating consistent, professional cable labels for installation and maintenance
- Maintaining accurate documentation when physical changes are made
- Cross-referencing logical port configurations with physical cable runs
- Planning cable installations before maintenance windows

## Current status (2026-01)
- Port Reorg feature provides port-to-label mapping and script generation
- No dedicated cable tracking or patch panel mapping exists
- Label generation is limited to port descriptions in device configs
- No integration between physical documentation and logical configuration

## Proposed Features

### T.1 Cable Run Tracking
- **Cable Run Database**: Track individual cable runs with:
  - Unique cable ID (auto-generated or user-defined)
  - Source endpoint (device/port or patch panel/position)
  - Destination endpoint (device/port or patch panel/position)
  - Cable type (Cat6, Cat6a, fiber OM3/OM4/OS2, etc.)
  - Length (measured or estimated)
  - Color coding
  - Installation date
  - Last verified date
  - Status (active, reserved, abandoned, faulty)
- **Cable Path Visualization**: Show cable routes through intermediate patch panels
- **Bulk Import**: Import cable data from CSV/Excel spreadsheets

### T.2 Patch Panel Management
- **Patch Panel Registry**: Define patch panels with:
  - Panel name/ID and location (room, rack, U position)
  - Port count and layout (24-port, 48-port, fiber panels)
  - Port numbering scheme
- **Port Assignment View**: Visual grid showing each patch panel position and its connections
- **Cross-Connect Tracking**: Map patch panel ports to switch ports and end devices

### T.3 Label Generation
- **Cable Label Templates**: Generate printable labels for:
  - Cable ends (source and destination)
  - Patch panel ports
  - Switch port overlays
- **Label Formats**: Support common label printer formats (Brady, Dymo, Brother)
- **Batch Label Generation**: Generate labels for entire cable runs, racks, or projects
- **QR Code Support**: Optional QR codes linking to cable documentation

### T.4 Documentation Integration
- **Port Reorg Integration**: Link cable documentation to Port Reorg assignments
- **Interface View Integration**: Show cable info in Interfaces view tooltip/details
- **Export Formats**: Generate documentation in PDF, Excel, and Visio-compatible formats
- **Change Tracking**: Audit trail for cable documentation changes

### T.5 Verification & Maintenance
- **Verification Checklist**: Generate checklists for cable verification during maintenance
- **Discrepancy Tracking**: Flag mismatches between documented and discovered configurations
- **Scheduled Review Reminders**: Track cables due for verification

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-T-001 | Cable run data model | Data | Pending | Design Access schema for cable tracking |
| ST-T-002 | Patch panel registry UI | UI | Pending | Create patch panel management view |
| ST-T-003 | Label template engine | Tools | Pending | Implement label generation with multiple formats |
| ST-T-004 | Cable path visualization | UI | Pending | Visual representation of cable routes |
| ST-T-005 | Port Reorg cable integration | UI | Pending | Link cable docs to port assignments |

## Data Model (Proposed)

### CableRun Table
```
CableID (PK), SourceType, SourceDevice, SourcePort, DestType, DestDevice, DestPort,
CableType, Length, Color, InstallDate, VerifyDate, Status, Notes, CreatedBy, ModifiedDate
```

### PatchPanel Table
```
PanelID (PK), PanelName, Location, RackID, RackU, PortCount, PortLayout, PanelType, Notes
```

### PatchPanelPort Table
```
PanelID (FK), PortNumber, CableID (FK), Label, Status, Notes
```

## Automation hooks
- `Tools\New-CableLabel.ps1 -CableID <id> -Format Brady` to generate individual labels
- `Tools\Export-CableDocumentation.ps1 -Scope Rack -RackID <id>` to export rack documentation
- `Tools\Import-CableInventory.ps1 -Path cables.csv` to bulk import cable data
- `Tools\Test-CableVerification.ps1 -PanelID <id>` to generate verification checklist

## Telemetry gates
- Cable database operations emit `CableDocChange` events for audit trail
- Label generation emits `LabelGenerated` with format/count metrics
- Verification runs emit `CableVerification` with pass/fail counts

## UI Mockup Concepts

### Patch Panel View
```
+--------------------------------------------------+
| Patch Panel: MDF-PP-01  Location: MDF Rack A U42 |
+--------------------------------------------------+
| 01 [SW1-Gi1/0/1]  02 [SW1-Gi1/0/2]  03 [empty]  |
| 04 [SW1-Gi1/0/4]  05 [reserved]     06 [faulty] |
| ...                                              |
+--------------------------------------------------+
| Legend: [active] [reserved] [empty] [faulty]     |
+--------------------------------------------------+
```

### Cable Label Preview
```
+-------------------+
| CABLE: MDF-001    |
| FROM: SW1-Gi1/0/1 |
| TO: PP-01 Port 1  |
| Type: Cat6a       |
| [QR CODE]         |
+-------------------+
```

## Dependencies
- Port Reorg module for integration
- Access database infrastructure
- Label printer driver integration (future)

## References
- `docs/plans/PlanD_FeatureExpansion.md` (Port Reorg context)
- `docs/plans/PlanH_UserExperience.md` (UI patterns)
- `Modules/PortReorgViewModule.psm1` (integration point)
