# RoutingDiscoveryCapture Schema (v1)

## Purpose
Defines the offline routing discovery capture input used to generate RouteRecord
entries deterministically without live device access.

## Schema Version
- `SchemaVersion`: `1.0`

## Required Fields (top-level)
- `SchemaVersion` (string) - schema version, currently `1.0`
- `CapturedAt` (string) - ISO 8601 timestamp when the capture was created
- `Site` (string) - site key (uppercase)
- `Hostname` (string) - device hostname (uppercase)
- `Vrf` (string) - VRF name (`default` if none)
- `Routes` (array) - collection of route entries

## Required Fields (per route)
- `Prefix` (string) - destination prefix (e.g., `10.10.0.0`)
- `PrefixLength` (integer) - prefix length (e.g., `24`)
- `NextHop` (string) - next-hop IP address
- `Protocol` (string) - routing protocol (`OSPF`, `BGP`, `Static`, etc.)
- `RouteRole` (string) - `Primary` or `Secondary`
- `RouteState` (string) - `Active` or `Inactive`

## Optional Fields (per route)
- `InterfaceName` (string) - outgoing interface
- `AdminDistance` (integer) - administrative distance
- `Metric` (integer) - protocol metric
- `Tag` (string) - route tag (if present)
- `AgeSeconds` (integer) - route age in seconds

## Normalization Notes
- `Site` and `Hostname` should be uppercase to match UI filtering.
- Use `default` for `Vrf` when none is provided.
- `CapturedAt` must be ISO 8601 (`Get-Date -Format o`).

## Machine-Readable Schema
- `docs/schemas/routing/routing_discovery_capture.schema.json`
