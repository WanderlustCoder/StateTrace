# Plan X - Inventory & Asset Tracking

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

## Objective
Provide comprehensive network inventory and asset tracking capabilities. Enable network teams to track hardware assets, monitor warranty status, manage firmware versions, and maintain lifecycle documentation for all network infrastructure.

## Problem Statement
Network teams struggle with:
- Tracking what hardware is deployed and where
- Monitoring warranty expiration dates across hundreds of devices
- Managing firmware versions and identifying devices needing updates
- Maintaining accurate serial number and asset tag records
- Planning hardware refresh cycles and budget forecasting
- Generating inventory reports for audits and compliance

## Current status (2026-01)
- **In Progress (4/6 Done)**. Core inventory and asset tracking system delivered.
- InventoryModule.psm1 provides asset registry, warranty tracking, firmware management, lifecycle planning
- InventoryViewModule.psm1 provides view wiring with full UI event handling
- InventoryView.xaml offers 5-tab interface: Inventory, Warranty Alerts, Firmware, Lifecycle, History
- Built-in lifecycle database with Cisco, Arista, Ruckus product information
- Pester tests cover all module functionality
- CSV import/export and HTML warranty reports implemented

## Proposed Features

### X.1 Asset Registry
- **Core Asset Data**: Track for each device:
  - Hostname and management IP
  - Vendor, model, platform
  - Serial number (chassis and modules)
  - Asset tag / inventory ID
  - Purchase date and vendor
  - Warranty expiration date
  - Support contract details
  - Physical location (site, building, rack, U position)
  - Status (active, spare, RMA, decommissioned)
- **Module Tracking**: Track line cards, power supplies, SFPs:
  - Module type and part number
  - Serial number
  - Slot position
  - Status
- **Bulk Import**: Import from CSV, Excel, or existing inventory systems

### X.2 Firmware Management
- **Version Tracking**: Record current firmware for each device:
  - OS version (IOS, EOS, etc.)
  - Boot image
  - ROMMON/bootloader version
- **Version Database**: Maintain known firmware versions:
  - Release date
  - End of support date
  - Known vulnerabilities (CVEs)
  - Recommended status (current, deprecated, critical)
- **Update Planning**: Identify devices needing updates:
  - Devices below minimum version
  - Devices with known vulnerabilities
  - Devices approaching end of support
- **Firmware Compliance Report**: Track fleet compliance with standards

### X.3 Warranty & Lifecycle
- **Warranty Tracking**: Monitor warranty status:
  - Expiration alerts (30, 60, 90, 180 days out)
  - Coverage level (NBD, 4-hour, etc.)
  - Support contract number
- **Lifecycle Management**:
  - End of sale (EoS) dates
  - End of support (EoSu) dates
  - Last date of support (LDoS)
  - Replacement recommendations
- **Refresh Planning**:
  - Devices approaching end of life
  - Budget forecasting based on refresh cycles
  - Recommended replacement models

### X.4 Reporting & Analytics
- **Inventory Summary**: Device counts by:
  - Vendor/model
  - Site/location
  - Age/purchase year
  - Status
- **Warranty Report**:
  - Devices expiring in next N days
  - Devices out of warranty
  - Coverage gap analysis
- **Firmware Report**:
  - Version distribution
  - Devices needing updates
  - Compliance percentage
- **Lifecycle Report**:
  - EoL timeline
  - Refresh recommendations
  - Budget impact

### X.5 Integration Points
- **Device Discovery Import**: Pull hardware info from parsed configs
- **Vendor API Ready**: Structure for future vendor lookups (Cisco, Arista)
- **Export to CMDB**: Export for enterprise asset management systems
- **Audit Trail**: Track all changes to asset records

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-X-001 | Asset registry module | Data | Done | InventoryModule.psm1 with New/Get/Update/Remove-Asset |
| ST-X-002 | Firmware version database | Data | Done | Parse-FirmwareVersion, Set-MinimumFirmware, CVE tracking |
| ST-X-003 | Device info import | Tools | Done | Parse-ShowVersion, Import-AssetInventory from CSV |
| ST-X-004 | Warranty tracking UI | UI | Done | InventoryView.xaml Warranty Alerts tab with expiring/expired grids |
| ST-X-005 | Inventory reports | Tools | Pending | Advanced analytics and PDF export |
| ST-X-006 | Lifecycle planning view | UI | Pending | Budget forecasting and refresh recommendations |

## Data Model (Proposed)

### Asset Table
```
AssetID (PK), Hostname, DeviceID (FK), Vendor, Model, Platform,
SerialNumber, AssetTag, PurchaseDate, PurchaseVendor, PurchasePrice,
WarrantyExpiration, SupportContract, SupportLevel,
SiteID, BuildingID, RackID, RackU, Status, Notes, CreatedDate, ModifiedDate
```

### Module Table
```
ModuleID (PK), AssetID (FK), ModuleType, PartNumber, SerialNumber,
SlotPosition, Status, InstallDate, Notes
```

### FirmwareVersion Table
```
VersionID (PK), Vendor, Platform, VersionString, ReleaseDate,
EndOfSupportDate, IsRecommended, IsCritical, CVEList, Notes
```

### DeviceFirmware Table
```
DeviceID (FK), VersionID (FK), ImageName, BootImage, RommonVersion,
LastUpdated, UpdatedBy, Notes
```

### LifecycleDate Table
```
ProductID (PK), Vendor, Model, EndOfSaleDate, EndOfSupportDate,
LastDateOfSupport, ReplacementModel, Notes
```

## Testing Requirements

### Unit Tests (`Modules/Tests/InventoryModule.Tests.ps1`)

```powershell
Describe 'Asset Registry' -Tag 'Inventory' {
    It 'creates new asset record with required fields' {
        $asset = New-Asset -Hostname 'SW-01' -Vendor 'Cisco' -Model 'C9300-48P' -SerialNumber 'FCW12345678'
        $asset | Should -Not -BeNullOrEmpty
        $asset.Hostname | Should -Be 'SW-01'
        $asset.SerialNumber | Should -Be 'FCW12345678'
    }

    It 'validates serial number format' {
        { New-Asset -Hostname 'SW-01' -SerialNumber '' } | Should -Throw
    }

    It 'prevents duplicate serial numbers' {
        New-Asset -Hostname 'SW-01' -SerialNumber 'FCW12345678'
        { New-Asset -Hostname 'SW-02' -SerialNumber 'FCW12345678' } | Should -Throw
    }

    It 'updates asset status correctly' {
        $asset = New-Asset -Hostname 'SW-01' -SerialNumber 'FCW12345678' -Status 'Active'
        Set-AssetStatus -AssetID $asset.AssetID -Status 'RMA'
        $updated = Get-Asset -AssetID $asset.AssetID
        $updated.Status | Should -Be 'RMA'
    }
}

Describe 'Warranty Tracking' -Tag 'Inventory' {
    BeforeAll {
        $today = Get-Date
        $script:expiringSoon = New-Asset -Hostname 'SW-EXPIRE' -SerialNumber 'EXP001' `
            -WarrantyExpiration ($today.AddDays(30))
        $script:expired = New-Asset -Hostname 'SW-EXPIRED' -SerialNumber 'EXP002' `
            -WarrantyExpiration ($today.AddDays(-10))
        $script:covered = New-Asset -Hostname 'SW-COVERED' -SerialNumber 'COV001' `
            -WarrantyExpiration ($today.AddDays(365))
    }

    It 'identifies warranties expiring within 60 days' {
        $expiring = Get-ExpiringWarranties -DaysAhead 60
        $expiring.Hostname | Should -Contain 'SW-EXPIRE'
        $expiring.Hostname | Should -Not -Contain 'SW-COVERED'
    }

    It 'identifies expired warranties' {
        $expired = Get-ExpiredWarranties
        $expired.Hostname | Should -Contain 'SW-EXPIRED'
    }

    It 'calculates days until expiration correctly' {
        $asset = Get-Asset -Hostname 'SW-EXPIRE'
        $asset.DaysUntilExpiration | Should -BeGreaterThan 25
        $asset.DaysUntilExpiration | Should -BeLessThan 35
    }
}

Describe 'Firmware Version Management' -Tag 'Inventory' {
    It 'parses Cisco IOS version string correctly' {
        $version = Parse-FirmwareVersion -VersionString '17.06.05' -Vendor 'Cisco'
        $version.Major | Should -Be 17
        $version.Minor | Should -Be 6
        $version.Patch | Should -Be 5
    }

    It 'identifies devices below minimum version' {
        Set-MinimumFirmware -Vendor 'Cisco' -Platform 'C9300' -MinVersion '17.06.03'
        $below = Get-DevicesBelowMinimumFirmware -Vendor 'Cisco' -Platform 'C9300'
        # Should return devices running older versions
    }

    It 'flags devices with known CVEs' {
        $vulnerable = Get-VulnerableDevices
        $vulnerable | ForEach-Object {
            $_.CVEList | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Import Functions' -Tag 'Inventory' {
    It 'imports assets from CSV' {
        $csv = @"
Hostname,Vendor,Model,SerialNumber,AssetTag
SW-IMPORT-01,Cisco,C9300-48P,CSV001,AT001
SW-IMPORT-02,Cisco,C9300-24P,CSV002,AT002
"@
        $tempFile = [System.IO.Path]::GetTempFileName() + '.csv'
        $csv | Set-Content $tempFile

        $result = Import-AssetInventory -Path $tempFile
        $result.ImportedCount | Should -Be 2
        $result.Errors | Should -BeNullOrEmpty
    }

    It 'parses show version output for hardware info' {
        $showVersion = @"
Cisco IOS Software, C9300 Software (C9300-UNIVERSALK9-M), Version 17.06.05
System serial number: FCW12345678
Model number: C9300-48P
"@
        $info = Parse-ShowVersion -Content $showVersion -Vendor 'Cisco'
        $info.SerialNumber | Should -Be 'FCW12345678'
        $info.Model | Should -Be 'C9300-48P'
        $info.Version | Should -Be '17.06.05'
    }
}

Describe 'Report Generation' -Tag 'Inventory' {
    It 'generates inventory summary with correct counts' {
        $summary = Get-InventorySummary
        $summary.TotalDevices | Should -BeGreaterThan 0
        $summary.ByVendor | Should -Not -BeNullOrEmpty
        $summary.BySite | Should -Not -BeNullOrEmpty
    }

    It 'generates warranty report in PDF format' {
        $report = Export-WarrantyReport -Format PDF -OutputPath $env:TEMP
        Test-Path $report.Path | Should -BeTrue
    }
}
```

### Integration Tests (`Modules/Tests/InventoryModule.Integration.Tests.ps1`)

```powershell
Describe 'Inventory Database Integration' -Tag 'Integration','Inventory' {
    BeforeAll {
        # Use test database
        Initialize-InventoryDatabase -TestMode
    }

    It 'persists asset data to Access database' {
        $asset = New-Asset -Hostname 'INT-SW-01' -Vendor 'Cisco' -SerialNumber 'INT001'

        # Reload from database
        $loaded = Get-Asset -SerialNumber 'INT001'
        $loaded.Hostname | Should -Be 'INT-SW-01'
    }

    It 'maintains audit trail for changes' {
        $asset = New-Asset -Hostname 'AUDIT-SW-01' -SerialNumber 'AUD001' -Status 'Active'
        Set-AssetStatus -SerialNumber 'AUD001' -Status 'RMA'

        $history = Get-AssetHistory -SerialNumber 'AUD001'
        $history.Count | Should -BeGreaterThan 1
        $history[-1].ChangeType | Should -Be 'StatusChange'
    }

    AfterAll {
        # Cleanup test data
        Remove-TestInventoryData
    }
}
```

### UI Tests (`Modules/Tests/InventoryView.Tests.ps1`)

```powershell
Describe 'Inventory View Controls' -Tag 'UI','Inventory' {
    BeforeAll {
        $xamlPath = Join-Path $PSScriptRoot '..\..\Views\InventoryView.xaml'
        $script:xamlContent = Get-Content $xamlPath -Raw
    }

    It 'defines asset grid control' {
        $xamlContent | Should -Match 'Name="InventoryGrid"'
    }

    It 'defines warranty alert panel' {
        $xamlContent | Should -Match 'Name="WarrantyAlertsPanel"'
    }

    It 'defines firmware compliance indicator' {
        $xamlContent | Should -Match 'Name="FirmwareComplianceStatus"'
    }

    It 'defines export buttons' {
        $xamlContent | Should -Match 'Name="ExportInventoryButton"'
        $xamlContent | Should -Match 'Name="ExportWarrantyButton"'
    }
}
```

## UI Mockup Concepts

### Inventory Dashboard
```
+------------------------------------------------------------------+
| Network Inventory Dashboard                                       |
+------------------------------------------------------------------+
| Summary:  [456 Devices] [23 Sites] [5 Vendors]                   |
+------------------------------------------------------------------+
| WARRANTY ALERTS                    | FIRMWARE STATUS              |
| [!] 12 expiring in 30 days        | [*] 89% compliant            |
| [!] 5 expiring in 60 days         | [!] 23 devices need updates  |
| [X] 8 expired                      | [X] 5 have critical CVEs     |
+------------------------------------------------------------------+
| LIFECYCLE ALERTS                   | QUICK ACTIONS                |
| [!] 15 devices EoL in 2026        | [Import Inventory]           |
| [!] 8 devices need replacement    | [Generate Report]            |
|                                    | [Export to Excel]            |
+------------------------------------------------------------------+
```

### Asset Detail View
```
+------------------------------------------------------------------+
| Asset: SW-BLDG1-FL2-01                              [Edit] [RMA] |
+------------------------------------------------------------------+
| DEVICE INFO                        | WARRANTY & SUPPORT          |
| Vendor: Cisco                      | Status: Active              |
| Model: C9300-48P                   | Expires: 2027-03-15         |
| Serial: FCW12345678                | Days Left: 437              |
| Asset Tag: NT-2024-0456            | Contract: SWSS-12345        |
| Firmware: 17.06.05                 | Level: 24x7x4               |
+------------------------------------------------------------------+
| LOCATION                           | MODULES                     |
| Site: Campus Main                  | PWR-C1-1100WAC (FCW111)     |
| Building: Building 1               | C9300-NM-4G (FCW222)        |
| Rack: Row A, Rack 5, U22-23        | SFP-10G-SR x 2              |
+------------------------------------------------------------------+
| HISTORY                                                          |
| 2024-01-15: Created (imported from CSV)                          |
| 2024-06-20: Firmware updated 17.03.05 -> 17.06.05               |
| 2024-08-10: Moved from Rack 3 to Rack 5                         |
+------------------------------------------------------------------+
```

## Automation hooks
- `Tools\Import-AssetInventory.ps1 -Path inventory.csv` to bulk import
- `Tools\Update-FirmwareInventory.ps1 -DeviceFilter CAMPUS*` to scan versions
- `Tools\Get-WarrantyReport.ps1 -ExpiringWithin 90` to generate alerts
- `Tools\Export-AssetReport.ps1 -Format Excel -Scope Site -Site CAMPUS`
- `Tools\Test-FirmwareCompliance.ps1 -Standard security-baseline` for compliance
- `Tools\Get-LifecycleReport.ps1 -EoLWithin 365` for refresh planning

## Telemetry gates
- Asset operations emit `AssetChange` events for audit
- Import operations emit `AssetImport` with counts and errors
- Report generation emits `InventoryReport` with scope and format
- Compliance checks emit `FirmwareCompliance` with pass/fail counts

## Dependencies
- Access database infrastructure
- Device data from parsed configs
- Vendor lifecycle databases (manual updates initially)

## References
- `docs/plans/PlanT_CablePortDocumentation.md` (Location tracking)
- `docs/plans/PlanU_ConfigurationTemplates.md` (Firmware standards)
- `docs/schemas/access/Access_DB_Schema.md` (Database patterns)
