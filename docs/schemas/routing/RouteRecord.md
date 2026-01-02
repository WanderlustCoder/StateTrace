# RouteRecord Schema (v1)

## Purpose
Defines a single routing table entry captured from a device or parser run. This
is the atomic record used to build routing health snapshots and evidence of
primary/secondary path behavior.

## Schema Version
- `SchemaVersion`: `1.0`

## Required Fields
- `SchemaVersion` (string) - schema version, currently `1.0`
- `RecordId` (string) - unique identifier for this record
- `CapturedAt` (string) - ISO 8601 timestamp when the record was captured
- `Site` (string) - site key (uppercase)
- `Hostname` (string) - device hostname (uppercase)
- `Vrf` (string) - VRF name (`default` if none)
- `Prefix` (string) - destination prefix (e.g., `10.10.0.0`)
- `PrefixLength` (integer) - prefix length (e.g., `24`)
- `NextHop` (string) - next-hop IP address
- `Protocol` (string) - routing protocol (`OSPF`, `BGP`, `Static`, etc.)
- `RouteRole` (string) - `Primary` or `Secondary`
- `RouteState` (string) - `Active` or `Inactive`

## Optional Fields
- `InterfaceName` (string) - outgoing interface
- `AdminDistance` (integer) - administrative distance
- `Metric` (integer) - protocol metric
- `Tag` (string) - route tag (if present)
- `AgeSeconds` (integer) - route age in seconds
- `SourceSystem` (string) - source component (e.g., `Parser`, `Snapshot`)

## Normalization Notes
- `Site` and `Hostname` should be uppercase to match UI filtering.
- Use `default` for `Vrf` when none is provided.
- `CapturedAt` must be ISO 8601 (`Get-Date -Format o`).

## Machine-Readable Schema
- `docs/schemas/routing/route_record.schema.json`
