# Access DB Schema

This document is the canonical description of the local persistence schema used by StateTrace.
Plans reference Access-backed persistence and connection caching. To make agent work reliable, the store schema must be documented and kept current.

## LANDMARK: Store identity
- Store type: Microsoft Access (.accdb primary; .mdb legacy fallback).
- Default path: per-site `Data/<site>/<site>.accdb` (see `DeviceRepositoryModule\Get-DbPathForSite`).
- Ownership: Ingestion / Platform.
- Migration strategy: schema is created/ensured at runtime by `Modules/DatabaseModule.psm1` and `Modules/ParserPersistenceModule.psm1` (additive ALTERs for new columns). For breaking changes, add an ADR + plan entry.

## LANDMARK: Connection string
Document the exact provider used and any required prerequisites.

Example:
```text
Provider=Microsoft.ACE.OLEDB.12.0;
Data Source=<repo-root>\Data\<site>\<site>.accdb;
Persist Security Info=False;
```

## LANDMARK: Schema export procedure (recommended)

There is no dedicated export script yet. Use the snippet below and store the output at:
- `docs/schemas/access/schema.snapshot.json`

```powershell
# LANDMARK: Export Access schema
$dbPath = Join-Path $PSScriptRoot "..\..\..\Data\BOYO\BOYO.accdb"
$connStr = "Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$dbPath;Persist Security Info=False;"

Add-Type -AssemblyName System.Data
$conn = New-Object System.Data.OleDb.OleDbConnection($connStr)
$conn.Open()

# Tables
$tables = $conn.GetSchema("Tables") | Where-Object { $_.TABLE_TYPE -eq "TABLE" }

$schema = @()
foreach ($t in $tables) {
  $tableName = $t.TABLE_NAME
  $cols = $conn.GetSchema("Columns", @($null, $null, $tableName, $null)) |
    Select-Object COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE, ORDINAL_POSITION
  $schema += [pscustomobject]@{
    Table   = $tableName
    Columns = $cols
  }
}

$outDir = Join-Path $PSScriptRoot "..\..\..\docs\schemas\access"
$outFile = Join-Path $outDir "schema.snapshot.json"
$schema | ConvertTo-Json -Depth 10 | Set-Content -Path $outFile -Encoding UTF8

$conn.Close()
Write-Host "Wrote $outFile"
```

## LANDMARK: Tables

Maintain a table inventory below. Keep it updated whenever schema changes.

### DeviceSummary
**Purpose:** Current device summary row per hostname.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| Hostname | TEXT(64) | No | Primary key. |
| Make | TEXT(64) | Yes | Vendor make. |
| Model | TEXT(64) | Yes | Device model. |
| Uptime | TEXT(64) | Yes | Raw uptime string. |
| Site | TEXT(64) | Yes | Site prefix. |
| Building | TEXT(64) | Yes | Building name. |
| Room | TEXT(64) | Yes | Room name. |
| Ports | INTEGER | Yes | Port count. |
| AuthDefaultVLAN | TEXT(32) | Yes | Auth default VLAN. |
| AuthBlock | MEMO | Yes | Auth block text. |

### Interfaces
**Purpose:** Current interface rows per hostname.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| ID | COUNTER | No | Primary key. |
| Hostname | TEXT(64) | Yes | Foreign key to DeviceSummary. |
| Port | TEXT(64) | Yes | Port name (string). |
| Name | TEXT(128) | Yes | Port description. |
| Status | TEXT(32) | Yes | Up/Down/etc. |
| VLAN | INTEGER | Yes | VLAN numeric. |
| Duplex | TEXT(32) | Yes | Duplex mode. |
| Speed | TEXT(32) | Yes | Speed string. |
| Type | TEXT(32) | Yes | Port type. |
| LearnedMACs | MEMO | Yes | Learned MACs list. |
| AuthState | TEXT(32) | Yes | Auth state. |
| AuthMode | TEXT(32) | Yes | Auth mode. |
| AuthClientMAC | TEXT(64) | Yes | Auth client MAC. |
| AuthTemplate | TEXT(64) | Yes | Auth template. |
| Config | MEMO | Yes | Config snippet. |
| PortColor | TEXT(32) | Yes | UI color label. |
| ConfigStatus | TEXT(32) | Yes | Config status label. |
| ToolTip | MEMO | Yes | UI tooltip text. |

### DeviceHistory
**Purpose:** Historical device summary snapshots.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| ID | COUNTER | No | Primary key. |
| Hostname | TEXT(64) | Yes | Hostname. |
| RunDate | DATETIME | Yes | Snapshot timestamp. |
| Make | TEXT(64) | Yes | Vendor make. |
| Model | TEXT(64) | Yes | Device model. |
| Uptime | TEXT(64) | Yes | Raw uptime string. |
| Site | TEXT(64) | Yes | Site prefix. |
| Building | TEXT(64) | Yes | Building name. |
| Room | TEXT(64) | Yes | Room name. |
| Ports | INTEGER | Yes | Port count. |
| AuthDefaultVLAN | TEXT(32) | Yes | Auth default VLAN. |
| AuthBlock | MEMO | Yes | Auth block text. |

### InterfaceHistory
**Purpose:** Historical interface snapshots per host/run.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| ID | COUNTER | No | Primary key. |
| Hostname | TEXT(64) | Yes | Hostname. |
| RunDate | DATETIME | Yes | Snapshot timestamp. |
| Port | TEXT(64) | Yes | Port name. |
| Name | TEXT(128) | Yes | Port description. |
| Status | TEXT(32) | Yes | Up/Down/etc. |
| VLAN | INTEGER | Yes | VLAN numeric. |
| Duplex | TEXT(32) | Yes | Duplex mode. |
| Speed | TEXT(32) | Yes | Speed string. |
| Type | TEXT(32) | Yes | Port type. |
| LearnedMACs | MEMO | Yes | Learned MACs list. |
| AuthState | TEXT(32) | Yes | Auth state. |
| AuthMode | TEXT(32) | Yes | Auth mode. |
| AuthClientMAC | TEXT(64) | Yes | Auth client MAC. |
| AuthTemplate | TEXT(64) | Yes | Auth template. |
| Config | MEMO | Yes | Config snippet. |
| PortColor | TEXT(32) | Yes | UI color label. |
| ConfigStatus | TEXT(32) | Yes | Config status label. |
| ToolTip | MEMO | Yes | UI tooltip text. |

### SpanInfo
**Purpose:** Current spanning-tree snapshot per host/VLAN.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| Hostname | TEXT(64) | Yes | Hostname. |
| Vlan | TEXT(32) | Yes | VLAN identifier. |
| RootSwitch | TEXT(64) | Yes | Root switch. |
| RootPort | TEXT(32) | Yes | Root port. |
| Role | TEXT(32) | Yes | STP role. |
| Upstream | TEXT(64) | Yes | Upstream switch. |
| LastUpdated | DATETIME | Yes | Snapshot timestamp. |

### SpanHistory
**Purpose:** Historical spanning-tree snapshots.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| ID | COUNTER | No | Primary key. |
| Hostname | TEXT(64) | Yes | Hostname. |
| RunDate | DATETIME | Yes | Snapshot timestamp. |
| Vlan | TEXT(32) | Yes | VLAN identifier. |
| RootSwitch | TEXT(64) | Yes | Root switch. |
| RootPort | TEXT(32) | Yes | Root port. |
| Role | TEXT(32) | Yes | STP role. |
| Upstream | TEXT(64) | Yes | Upstream switch. |

### InterfaceBulkSeed
**Purpose:** Staging table for bulk interface inserts (parser persistence).

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| BatchId | TEXT(36) | No | Batch identifier. |
| Hostname | TEXT(255) | Yes | Hostname. |
| RunDateText | TEXT(32) | Yes | Run date string. |
| RunDate | DATETIME | Yes | Parsed run date. |
| Port | TEXT(255) | Yes | Port name. |
| Name | TEXT(255) | Yes | Port description. |
| Status | TEXT(255) | Yes | Port status. |
| VLAN | INTEGER | Yes | VLAN numeric. |
| Duplex | TEXT(255) | Yes | Duplex mode. |
| Speed | TEXT(255) | Yes | Speed string. |
| Type | TEXT(255) | Yes | Port type. |
| LearnedMACs | MEMO | Yes | Learned MACs list. |
| AuthState | TEXT(255) | Yes | Auth state. |
| AuthMode | TEXT(255) | Yes | Auth mode. |
| AuthClientMAC | TEXT(255) | Yes | Auth client MAC. |
| AuthTemplate | TEXT(255) | Yes | Auth template. |
| Config | MEMO | Yes | Config snippet. |
| PortColor | TEXT(255) | Yes | UI color label. |
| ConfigStatus | TEXT(255) | Yes | Config status label. |
| ToolTip | MEMO | Yes | UI tooltip text. |

## LANDMARK: Indexes & constraints

Documented indexes (see `Modules/DatabaseIndexes.psm1`):
- `DeviceSummary`: primary key on `Hostname`.
- `Interfaces`: `IX_Interfaces_Hostname`, `IX_Interfaces_HostnamePort`.
- `InterfaceHistory`: `IX_InterfaceHistory_HostnameRunDate`.
- `SpanInfo`: `idx_spaninfo_host_vlan`.
- `SpanHistory`: `idx_spanhistory_host`.
- `InterfaceBulkSeed`: `IX_InterfaceBulkSeed_BatchId`.

Foreign keys:
- `Interfaces.Hostname` references `DeviceSummary.Hostname` (logical; Access may not enforce).

## LANDMARK: Performance notes

Plans mention caching Access connections and reducing persistence overhead. Track:
- known slow queries/tables (log in Plan B)
- compaction/maintenance commands (`Tools/Maintain-AccessDatabases.ps1 -DataRoot Data -IndexAudit`)
- any safe-to-delete caches under `Data/` (document before removing)
