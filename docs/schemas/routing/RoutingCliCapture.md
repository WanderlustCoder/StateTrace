# RoutingCliCapture Schema (v1)

## Purpose
Defines the offline CLI capture manifest that references raw routing command output files and feeds deterministic routing discovery ingestion.

## Schema Version
- `SchemaVersion`: `1.0`

## Required Fields (top-level)
- `SchemaVersion` (string) - schema version, currently `1.0`
- `CapturedAt` (string) - ISO 8601 timestamp when the capture was created
- `Site` (string) - site key (uppercase)
- `Hostname` (string) - device hostname (uppercase)
- `Vendor` (string) - routing platform identifier (e.g., `CiscoIOSXE`, `AristaEOS`)
- `Vrf` (string) - VRF name (`default` if none)
- `Artifacts` (array) - referenced CLI output files

## Required Fields (artifact entries)
- `Name` (string) - logical name of the command output (required: `show_ip_route`)
- `Command` (string) - command executed (e.g., `show ip route`)
- `Path` (string) - relative path to the output file (relative to Capture.json)

## Supported Vendors (v1)
- `CiscoIOSXE`
- `AristaEOS`

## Normalization Notes
- `Site` and `Hostname` should be uppercase to match UI filtering.
- Use `default` for `Vrf` when none is provided.
- `CapturedAt` must be ISO 8601 (`Get-Date -Format o`).

## Machine-Readable Schema
- `docs/schemas/routing/routing_cli_capture.schema.json`
